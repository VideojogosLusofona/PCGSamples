#ifndef COMMON_HLSL
#define COMMON_HLSL

#include "Ray.hlsl"
#include "Random.hlsl"

// ---------------------- Materials ----------------------
struct RTMaterial
{
    float4  albedo;
    float   emission;
    float   roughness;
    float   metallic;
    float   ior;
    float3  absorption;
    float   pad;
};

// ---------------------- Primitive encoding ----------------------
static const int PRIM_SPHERE = 0;
static const int PRIM_PLANE = 1;
static const int PRIM_DUALSIDEDPLANE = 2;
static const int PRIM_UNION = 3;
static const int PRIM_INTERSECT = 4;
static const int PRIM_SUBTRACT = 5;
static const int PRIM_SMOOTH_UNION = 6;
static const int PRIM_SMOOTH_INTERSECT = 7;
static const int PRIM_SMOOTH_SUBTRACT = 8;

struct GPUPrimitive
{
    int     type;
    int     material;
    int     arg1;
    int     arg2;
    float4  data0;
};

// ---------------------- Light ----------------------
struct GPULight
{
    float3   position;
    float    intensity;
    float3   color;
    float    range;
    float    size;
};

// ---------------------- Camera parameters (set from C#) ----------------------
int2     _Resolution;
float4x4 _CamInvView;   // cameraToWorld
float4x4 _CamInvProj;   // inverse of projection matrix built for RT aspect
float3   _CamPos;

// Pixel -> world ray, respecting the RenderTexture aspect (because _CamInvProj was built for it)
Ray MakePrimaryRay(int2 pixel)
{
    // pixel center UV in [0..1]
    float2 uv = (float2(pixel) + 0.5) / float2(_Resolution);

    // NDC in [-1..1]
    float2 ndc = uv * 2.0 - 1.0;

    // Clip space point on near plane (z=0 is fine for this unprojection style)
    float4 clip = float4(ndc, 0.0, 1.0);

    // Unproject to view space
    float4 view = mul(_CamInvProj, clip);
    view.xyz /= max(view.w, 1e-6);

    float3 dirVS = normalize(view.xyz);

    // View -> world
    float3 dirWS = normalize(mul((float3x3)_CamInvView, dirVS));

    Ray r;
    r.origin = _CamPos;
    r.dir = dirWS;
    return r;
}

// ---------------------- Helper functions ----------------------

float ComputeFresnel(float3 incidentDir, float3 normal, float n1, float n2)
{
    // incidentDir: ray.dir (points *towards* the surface)
    // normal: geometric surface normal (either orientation)
    // n1: current medium IOR (e.g., 1.0)
    // n2: other side IOR (e.g., material.ior)

    float3 N = normal;
    float cosTheta = dot(-incidentDir, N);

    // Ensure N faces against the incoming ray
    if (cosTheta < 0.0)
    {
        N = -N;
        cosTheta = -cosTheta;
    }

    cosTheta = saturate(cosTheta);

    // F0 from indices of refraction
    float r0 = (n1 - n2) / (n1 + n2);
    float F0 = r0 * r0;

    // Schlick approximation
    float F = F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
    return saturate(F);
}

float3 FresnelSchlick3(float cosTheta, float3 F0)
{
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

float3 SampleGlossyDir(float3 R, float roughness, inout uint rng)
{
    roughness = saturate(roughness);
    if (roughness < 1e-4) return R;

    // crude but effective "blur": interpolate with random direction
    float3 u = RandomUnitVector(rng);
    return normalize(lerp(R, u, roughness));
}

// ---------------------- Globals ----------------------
StructuredBuffer<GPUPrimitive>  _Primitives;
int                             _PrimitiveCount;
StructuredBuffer<RTMaterial>    _Materials;
int                             _MaterialCount;
StructuredBuffer<GPULight>      _Lights;
int                             _LightCount;
float4                          _AmbientColor;
int                             _ReflectionRayCount;
int                             _MaxBounces;

#endif // COMMON_HLSL
