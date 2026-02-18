#ifndef INTERSECTION_HLSL
#define INTERSECTION_HLSL

#include "Ray.hlsl"

bool IntersectSphere(Ray ray, float3 c, float r, out float t, out float3 nrm)
{
    float3 oc = ray.origin - c;

    // Solve t^2 + 2*b*t + c = 0 with b = dot(oc, dir), c = dot(oc,oc)-r^2
    float b = dot(oc, ray.dir);
    float cc = dot(oc, oc) - r * r;
    float h = b * b - cc;

    if (h < 0.0)
    {
        t = 0; nrm = 0;
        return false;
    }

    h = sqrt(h);

    // nearest positive hit
    float t0 = -b - h;
    float t1 = -b + h;

    t = (t0 > 1e-4) ? t0 : ((t1 > 1e-4) ? t1 : -1.0);
    if (t < 0.0)
    {
        nrm = 0;
        return false;
    }

    float3 p = ray.origin + ray.dir * t;
    nrm = normalize(p - c);
    return true;
}

bool IntersectPlane(Ray ray, float3 n, float d, out float t, out float3 nrm)
{
    n = normalize(n);
    float denom = dot(n, ray.dir);

    // Reject parallel rays
    if (abs(denom) < 1e-6)
    {
        t = 0; nrm = 0;
        return false;
    }

    // Reject backface hits (single-sided)
    if (denom >= 0.0)
    {
        t = 0; nrm = 0;
        return false;
    }

    float tt = -(dot(n, ray.origin) + d) / denom;

    if (tt <= 1e-4)
    {
        t = 0; nrm = 0;
        return false;
    }

    t = tt;
    nrm = n; // no need to flip anymore

    return true;
}


bool IntersectPlaneDualSided(Ray ray, float3 n, float d, out float t, out float3 nrm)
{
    n = normalize(n);
    float denom = dot(n, ray.dir);

    if (abs(denom) < 1e-6)
    {
        t = 0; nrm = 0;
        return false;
    }

    // plane: dot(n, p) + d = 0
    float tt = -(dot(n, ray.origin) + d) / denom;

    if (tt <= 1e-4)
    {
        t = 0; nrm = 0;
        return false;
    }

    t = tt;

    // flip so it faces the ray (useful for shading)
    nrm = (denom < 0.0) ? n : -n;
    return true;
}

#endif // INTERSECTION_HLSL
