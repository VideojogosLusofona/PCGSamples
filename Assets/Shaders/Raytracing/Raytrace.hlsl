#ifndef RAYTRACE_HLSL
#define RAYTRACE_HLSL

#include "Ray.hlsl"
#include "Intersection.hlsl"

// Expects globals:
// StructuredBuffer<GPUPrimitive> _Primitives;
// StructuredBuffer<RTMaterial>   _Materials;
// int _PrimitiveCount;

#define MAX_BOOL_STACK 64

bool IntersectVolume(Ray ray, int rootIndex, out float tBest, out float3 nrmBest)
{
    tBest = 1e30;
    nrmBest = 0;
    bool hit = false;

    int stack[MAX_BOOL_STACK];
    int sp = 0;

    // push root
    stack[sp++] = rootIndex;

    [loop]
    while (sp > 0)
    {
        int idx = stack[--sp];
        GPUPrimitive p = _Primitives[idx];

        uint typeU = (uint)p.type;
        int primType = (int)(typeU & 0xFFFFu);

        // Leaf primitives
        if (primType == PRIM_SPHERE)
        {
            float t; float3 nrm;
            if (IntersectSphere(ray, p.data0.xyz, p.data0.w, t, nrm) && (t < tBest))
            {
                tBest = t;
                nrmBest = nrm;
                hit = true;
            }
        }
        else if (primType == PRIM_PLANE)
        {
            float t; float3 nrm;
            if (IntersectPlane(ray, p.data0.xyz, p.data0.w, t, nrm) && (t < tBest))
            {
                tBest = t;
                nrmBest = nrm;
                hit = true;
            }
        }
        else if (primType == PRIM_DUALSIDEDPLANE)
        {
            float t; 
            float3 nrm;
            if (IntersectPlaneDualSided(ray, p.data0.xyz, p.data0.w, t, nrm) && (t < tBest))
            {
                tBest = t;
                nrmBest = nrm;
                hit = true;
            }
        }
        else if (primType == PRIM_UNION)
        {
            // Push both children (nested unions supported)
            // Optional: if stack is full, you can early-out or drop deeper nodes.
            if (sp + 2 <= MAX_BOOL_STACK)
            {
                stack[sp++] = (int)p.arg1;
                stack[sp++] = (int)p.arg2;
            }
            else
            {
                // Stack overflow: you can either ignore deeper nodes (degrades correctness)
                // or return current best. I'd rather just return what we have.
                // (Or increase MAX_BOOL_STACK.)
                break;
            }
        }
        else
        {
            // Other boolean ops not supported in analytic RT in this codepath.
            // You can ignore or treat as miss.
        }
    }

    return hit;
}

Hit Trace(Ray ray)
{
    Hit h;
    h.hit = false;
    h.t = 1e30;
    h.pos = 0;
    h.normal = 0;
    h.material = -1;

    for (int i = 0; i < _PrimitiveCount; i++)
    {
        GPUPrimitive    p = _Primitives[i];
        float           t; 
        float3          nrm;
        bool            ok = false;

        uint typeU = (uint)p.type;
        if ((typeU & 0x80000000u) != 0u) continue;

        ok = IntersectVolume(ray, i, t, nrm);

        if (ok && (t < h.t))
        {
            h.hit = true;
            h.t = t;
            h.normal = nrm;
            h.material = p.material;
        }
    }

    if (h.hit)
        h.pos = ray.origin + ray.dir * h.t;

    return h;
}

Hit TraceNearest(Ray ray, float maxT)
{
    Hit h = Trace(ray);
    if (h.hit && h.t < maxT) return h;

    h.hit = false;
    return h;
}

// Transparent shadows using Beer-Lambert absorption.
// Returns RGB visibility (1 = fully lit, 0 = fully blocked).
float3 ShadowVisibility(Ray shadowRay, float maxT, int maxLayers, float lightSize)
{
    // Accumulated transmittance along the shadow ray
    float3 vis = float3(1.0, 1.0, 1.0);

    // Small offset to avoid self-intersections
    float eps = 1e-3;

    // We track whether the ray is currently inside an absorbing medium.
    // Start in "air": no absorption.
    float3 currentAbs = float3(0.0, 0.0, 0.0);
    float currentIor = 1.0;

    // Remaining distance to the light (shrinks as we march through blockers)
    float remaining = maxT;

    [loop]
    for (int layer = 0; layer < maxLayers; layer++)
    {
        // Find next intersection along the shadow ray
        Hit h = TraceNearest(shadowRay, remaining);

        // If nothing hit before the light, apply absorption for the remaining travel and exit
        if (!h.hit)
        {
            // Absorb along the last segment (only matters if we're inside something)
            vis *= exp(-currentAbs * remaining);
            break;
        }

        // Apply absorption from current medium along the traveled segment to this hit
        vis *= exp(-currentAbs * h.t);

        // Early out if essentially fully blocked
        if (max(vis.x, max(vis.y, vis.z)) < 0.001)
            return float3(0.0, 0.0, 0.0);

        // Determine if we are entering or exiting this hit material
        // Use geometric normal to decide: if ray dir points with normal -> we hit backface -> exiting
        float3 N = h.normal;
        bool exiting = (dot(shadowRay.dir, N) > 0.0);

        RTMaterial m = _Materials[h.material];

        // Update medium state *as if we refracted straight through*.
        // For shadow rays we don't need the refracted direction - just medium membership.
        if (!exiting)
        {
            // entering this material
            currentAbs = m.absorption;
            currentIor = max(m.ior, 1.0001);
        }
        else
        {
            // exiting to air (simple model)
            currentAbs = float3(0.0, 0.0, 0.0);
            currentIor = 1.0;
        }

        // Step forward and continue
        shadowRay.origin = h.pos + shadowRay.dir * (eps * 4.0);

        remaining -= h.t;
        if (remaining <= 0.0)
            break;
    }

    return saturate(vis);
}

#endif // RAYTRACE_HLSL
