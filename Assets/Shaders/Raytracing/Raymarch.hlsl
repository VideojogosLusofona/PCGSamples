#ifndef RAYMARCH_HLSL
#define RAYMARCH_HLSL

#include "Ray.hlsl"
#include "Distance.hlsl"

// Expects globals:
// StructuredBuffer<GPUPrimitive> _Primitives;
// StructuredBuffer<RTMaterial>   _Materials;
// int _PrimitiveCount;

static const int   RM_MAX_STEPS = 128;
static const float RM_MAX_DIST = 5000.0;
static const float RM_EPSILON = 1e-3;
static const float RM_NORMAL_EPS = 2e-3;

struct SdfSample
{
    float dist;
    int   matId;
};

#define MAX_PRIMITIVES 32

SdfSample SceneSDF(float3 p)
{
    SdfSample ret;
    ret.dist = RM_MAX_DIST;
    ret.matId = -1;

    float distanceCache[MAX_PRIMITIVES];

    for (int i = 0; i < _PrimitiveCount; i++)
    {
        GPUPrimitive primitive = _Primitives[i];

        uint typeU = (uint)primitive.type;

        bool isArg = (typeU & 0x80000000u) != 0u;

        int primType = (int)(typeU & 0xFFFFu);

        float d = RM_MAX_DIST;
        if (primType == PRIM_SPHERE)
        {
            d = sdSphere(p, primitive.data0.xyz, primitive.data0.w);
        }
        else if (primType == PRIM_PLANE)
        {
            d = sdPlane(p, primitive.data0.xyz, primitive.data0.w);
        }
        else if (primType == PRIM_DUALSIDEDPLANE)
        {
            d = sdDoubleSidedPlane(p, primitive.data0.xyz, primitive.data0.w);
        }
        else if (primType == PRIM_UNION)
        {
            d = opUnion(distanceCache[primitive.arg1], distanceCache[primitive.arg2]);
        }
        else if (primType == PRIM_INTERSECT)
        {
            d = opIntersection(distanceCache[primitive.arg1], distanceCache[primitive.arg2]);
        }
        else if (primType == PRIM_SUBTRACT)
        {
            d = opSubtraction(distanceCache[primitive.arg1], distanceCache[primitive.arg2]);
        }
        else if (primType == PRIM_SMOOTH_UNION)
        {
            d = opSmoothUnion(distanceCache[primitive.arg1], distanceCache[primitive.arg2], primitive.data0.x);
        }
        else if (primType == PRIM_SMOOTH_INTERSECT)
        {
            d = opSmoothIntersection(distanceCache[primitive.arg1], distanceCache[primitive.arg2], primitive.data0.x);
        }
        else if (primType == PRIM_SMOOTH_SUBTRACT)
        {
            d = opSmoothSubtraction(distanceCache[primitive.arg1], distanceCache[primitive.arg2], primitive.data0.x);
        }
        distanceCache[i] = d;
        if ((d < ret.dist) && (!isArg))
        {
            ret.dist = d;
            ret.matId = primitive.material;
        }
    }

    return ret;
}

// Estimate normal from the SDF (central differences).
float3 EstimateSDFNormal(float3 p)
{
    float e = RM_NORMAL_EPS;

    float dx = SceneSDF(p + float3(e, 0, 0)).dist - SceneSDF(p - float3(e, 0, 0)).dist;
    float dy = SceneSDF(p + float3(0, e, 0)).dist - SceneSDF(p - float3(0, e, 0)).dist;
    float dz = SceneSDF(p + float3(0, 0, e)).dist - SceneSDF(p - float3(0, 0, e)).dist;

    return normalize(float3(dx, dy, dz));
}

// Raymarching core: marches either in positive region or negative region
// depending on where the ray starts.
//
// Idea: if initial distance d0 >= 0 => march using +d (standard sphere tracing)
//       if initial distance d0 <  0 => march using -d (so step size is positive while staying "inside")
// Hit when abs(d) < epsilon
Hit Trace(Ray ray)
{
    Hit outHit = MakeMissHit();

    float t = 0.0;

    // Determine whether we start "outside" (positive) or "inside" (negative)
    SdfSample s0 = SceneSDF(ray.origin);

    int lastMat = s0.matId;

    [loop]
    for (int i = 0; i < RM_MAX_STEPS; i++)
    {
        float3 p = ray.origin + ray.dir * t;
        SdfSample s = SceneSDF(p);

        lastMat = s.matId;

        float d = s.dist;

        // Hit test: near surface regardless of sign
        if (abs(d) <= RM_EPSILON)
        {
            outHit.hit = true;
            outHit.t = t;
            outHit.pos = p;
            outHit.material = s.matId;

            // ensure outward orientation
            float3 n = EstimateSDFNormal(p);
            // Flip if needed (ensure outward)
            float d1 = SceneSDF(p + n * RM_NORMAL_EPS).dist;
            if (d1 < d) n = -n;

            outHit.normal = n;

            return outHit;
        }

        t += max(abs(d), RM_EPSILON);

        if (t >= RM_MAX_DIST)
            break;
    }

    // Miss: keep material as last seen (- not necessary, but sometimes useful for debug)
    outHit.material = lastMat;
    return outHit;
}

// Same as Trace, but early-out if we exceed maxT (e.g., for shadows).
Hit TraceNearest(Ray ray, float maxT)
{
    Hit outHit = MakeMissHit();

    float t = 0.0;

    // Decide marching mode based on starting sign
    SdfSample s0 = SceneSDF(ray.origin);
    float sign = (s0.dist < 0.0) ? -1.0 : 1.0;

    float tLimit = min(maxT, RM_MAX_DIST);

    [loop]
    for (int i = 0; i < RM_MAX_STEPS; i++)
    {
        if (t >= tLimit) break;

        float3 p = ray.origin + ray.dir * t;
        SdfSample s = SceneSDF(p);

        float d = s.dist;

        if (abs(d) <= RM_EPSILON)
        {
            outHit.hit = true;
            outHit.t = t;
            outHit.pos = p;
            outHit.material = s.matId;

            // ensure outward orientation
            float3 n = EstimateSDFNormal(p);
            // Flip if needed (ensure outward)
            float d1 = SceneSDF(p + n * RM_NORMAL_EPS).dist;
            if (d1 < d) n = -n;

            outHit.normal = n;

            return outHit;
        }

        float stepLen = sign * d;
        stepLen = max(stepLen, RM_EPSILON);

        t += stepLen;
    }

    return outHit;
}

// ------------------------------------------------------------
// Soft shadows (IQ-style) for raymarching / SDF sphere tracing.
// Same signature as the raytracing version.
//
// Returns RGB visibility in [0..1] (grayscale replicated).
// 1 = fully visible, 0 = fully occluded.
// ------------------------------------------------------------
float3 ShadowVisibility(Ray shadowRay, float maxT, int maxLayers, float lightSize)
{
    // Small origin offset to avoid self-shadow acne.
    // (We bias along the ray direction because we don't have the surface normal here.)
    float t = RM_EPSILON * 8.0;

    // "k" controls softness: higher -> sharper shadows, lower -> softer.
    // Typical IQ values: 8..32 depending on scale.
    const float k = 4.0f / lightSize;

    float visibility = 1.0;

    // Your caller passes maxLayers=4 in the raytracer.
    // For soft shadows we need *many* samples, so interpret maxLayers as a quality knob.
    int steps = clamp(maxLayers * 32, 16, RM_MAX_STEPS); // 4 -> 128 (your RM_MAX_STEPS)

    float tLimit = min(maxT, RM_MAX_DIST);

    [loop]
    for (int i = 0; i < steps; i++)
    {
        if (t >= tLimit) break;

        float3 p = shadowRay.origin + shadowRay.dir * t;
        float h = SceneSDF(p).dist;

        // If we're extremely close to geometry, consider it blocked.
        if (h <= RM_EPSILON)
            return float3(0.0, 0.0, 0.0);

        // IQ soft shadow visibility update:
        // visibility = min(visibility, k*h/t)
        visibility = min(visibility, k * h / max(t, 1e-4));

        // Advance: sphere tracing step (clamped to avoid tiny steps causing stalls)
        // Tweak minStep if you see banding vs performance issues.
        float stepLen = clamp(h, 0.01, 1.0);
        t += stepLen;

        // Early out if basically fully shadowed.
        if (visibility <= 0.001)
            return float3(0.0, 0.0, 0.0);
    }

    visibility = saturate(visibility);
    return float3(visibility, visibility, visibility);
}

#endif // RAYMARCH_HLSL