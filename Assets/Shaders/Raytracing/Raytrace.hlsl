#ifndef RAYTRACE_HLSL
#define RAYTRACE_HLSL

#include "Ray.hlsl"
#include "Intersection.hlsl"

// Expects globals:
// StructuredBuffer<GPUPrimitive> _Primitives;
// StructuredBuffer<RTMaterial>   _Materials;
// int _PrimitiveCount;

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
        GPUPrimitive p = _Primitives[i];

        float t; float3 nrm;
        bool ok = false;

        if (p.type == PRIM_SPHERE)
        {
            ok = IntersectSphere(ray, p.data0.xyz, p.data0.w, t, nrm);
        }
        else if (p.type == PRIM_PLANE)
        {
            ok = IntersectPlane(ray, p.data0.xyz, p.data0.w, t, nrm);
        }

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

#endif // RAYTRACE_HLSL
