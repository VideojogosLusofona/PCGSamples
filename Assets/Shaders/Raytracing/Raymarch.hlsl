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

SdfSample SceneSDF(float3 p)
{
    SdfSample ret;
    ret.dist = RM_MAX_DIST;
    ret.matId = -1;

    for (int i = 0; i < _PrimitiveCount; i++)
    {
        GPUPrimitive primitive = _Primitives[i];

        float d = RM_MAX_DIST;
        if (primitive.type == PRIM_SPHERE)
        {
            d = sdSphere(p, primitive.data0.xyz, primitive.data0.w);
        }
        else if (primitive.type == PRIM_PLANE)
        {
            d = sdDoubleSidedPlane(p, primitive.data0.xyz, primitive.data0.w);
        }
        if (d < ret.dist)
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
            float d0 = SceneSDF(p).dist;
            float d1 = SceneSDF(p + n * RM_NORMAL_EPS).dist;
            if (d1 < d0) n = -n;

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
            float d0 = SceneSDF(p).dist;
            float d1 = SceneSDF(p + n * RM_NORMAL_EPS).dist;
            if (d1 < d0) n = -n;

            outHit.normal = n;

            return outHit;
        }

        float stepLen = sign * d;
        stepLen = max(stepLen, RM_EPSILON);

        t += stepLen;
    }

    return outHit;
}

#endif // RAYMARCH_HLSL