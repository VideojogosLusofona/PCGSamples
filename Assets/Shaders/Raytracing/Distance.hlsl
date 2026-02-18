#ifndef DISTANCE_HLSL
#define DISTANCE_HLSL

// Signed distance to a sphere centered at c with radius r.
float sdSphere(float3 p, float3 c, float r)
{
    return length(p - c) - r;
}

// Signed distance to a plane defined by normal n and offset d,
// using the implicit form: dot(n, p) + d = 0
float sdPlane(float3 p, float3 n, float d)
{
    n = normalize(n);
    return dot(n, p) + d;
}

// Signed distance to a double sided plane (always positive by nature) defined by normal n and offset d,
// using the implicit form: dot(n, p) + d = 0
float sdDoubleSidedPlane(float3 p, float3 n, float d)
{
    n = normalize(n);
    return abs(dot(n, p) + d);
}

// ---------------- Optional helpers (useful later) ----------------

// Hard CSG operations on distances.
float opUnion(float a, float b) { return min(a, b); }
float opIntersection(float a, float b) { return max(a, b); }
float opSubtraction(float a, float b) { return max(a, -b); }

float smin(float a, float b, float k)
{
    float h = saturate(0.5 + 0.5 * (b - a) / k);
    return lerp(b, a, h) - k * h * (1.0 - h);
}

float smax(float a, float b, float k)
{
    return -smin(-a, -b, k);
}

float opSmoothUnion(float a, float b, float k)
{
    return smin(a, b, k);
}

float opSmoothIntersection(float a, float b, float k)
{
    return smax(a, b, k);
}

float opSmoothSubtraction(float a, float b, float k)
{
    return smax(a, -b, k);
}

#endif // DISTANCE_HLSL
