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

// Repeat space with period (component-wise). Useful for tiling primitives.
float3 opRepeat(float3 p, float3 period)
{
    return p - period * round(p / period);
}

#endif // DISTANCE_HLSL
