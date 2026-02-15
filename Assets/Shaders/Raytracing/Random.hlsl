#ifndef RANDOM_HLSL
#define RANDOM_HLSL

// Tiny hash RNG (deterministic per pixel / bounce / sample)
uint Hash(uint x)
{
    x ^= x >> 16;
    x *= 0x7feb352d;
    x ^= x >> 15;
    x *= 0x846ca68b;
    x ^= x >> 16;
    return x;
}

float Random01(inout uint state)
{
    state = Hash(state);
    return (state & 0x00FFFFFF) / 16777216.0;
}

float3 RandomUnitVector(inout uint state)
{
    float z = Random01(state) * 2.0 - 1.0;
    float a = Random01(state) * 6.2831853;
    float r = sqrt(max(0.0, 1.0 - z * z));
    return float3(r * cos(a), z, r * sin(a));
}

#endif // RANDOM_HLSL
