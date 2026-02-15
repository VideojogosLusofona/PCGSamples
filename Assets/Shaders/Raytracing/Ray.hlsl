#ifndef RAY_HLSL
#define RAY_HLSL

// ---------------------- Ray / Hit ----------------------
struct Ray
{
    float3 origin;
    float3 dir;     // normalized
};

Ray MakeRay(float3 origin, float3 direction)
{
    Ray r;
    r.origin = origin;
    r.dir = direction;
    return r;
}

Ray MakeRayWithOffset(float3 origin, float3 direction, float epsilon)
{
    Ray r;
    r.origin = origin + direction * epsilon;
    r.dir = direction;
    return r;
}

Ray MakeRayToFrom(float3 from, float3 to, out float distance)
{
    Ray r;
    r.origin = from;
    r.dir = (to - from);
    distance = length(r.dir);
    r.dir /= distance;
    return r;
}

struct Hit
{
    bool   hit;
    float  t;
    float3 pos;
    float3 normal;  // normalized, pointing against ray.dir when possible
    int    material;
};

// Helper: create a "miss" Hit
Hit MakeMissHit()
{
    Hit h;
    h.hit = false;
    h.t = 0.0;
    h.pos = 0.0;
    h.normal = 0.0;
    h.material = -1;
    return h;
}

Ray OffsetRay(Ray inRay, float eps)
{
    Ray ret;
    ret.origin = inRay.origin + inRay.dir * eps;
    ret.dir = inRay.dir;

    return ret;
}

float3 OffsetOut(float3 p, float3 N, float bias) { return p + N * bias; }
float3 OffsetIn(float3 p, float3 N, float bias) { return p - N * bias; }

Ray GetReflectedRay(Ray inRay, Hit hit, float eps)
{
    float3 N = hit.normal;
    // make normal face the incoming ray
    if (dot(inRay.dir, N) > 0.0) N = -N;

    float3 Rdir = normalize(reflect(inRay.dir, N));

    Ray r;
    r.origin = hit.pos + Rdir * eps;
    r.dir = Rdir;
    return r;
}

bool GetRefractedRay(Ray inRay, Hit hit, float eps, float currentIor, float materialIor, out Ray outRay, out float nextIor)
{
    float3 N = hit.normal;
    float3 I = inRay.dir;

    // Determine if we are entering or exiting.
    // If ray dir points in the same hemisphere as N, we're hitting from the back side -> exiting.
    bool exiting = (dot(I, N) > 0.0);

    float n1 = currentIor;
    float n2 = exiting ? 1.0 : materialIor;  // assume outside medium is air (1.0)

    // Orient normal against incident ray
    float3 Nf = exiting ? -N : N;

    float eta = n1 / n2;

    // Snell's law
    float cosI = dot(-I, Nf);
    float sin2T = eta * eta * (1.0 - cosI * cosI);

    // Total internal reflection
    if (sin2T > 1.0)
    {
        outRay.origin = hit.pos;
        outRay.dir = 0;
        nextIor = currentIor;
        return false;
    }

    float cosT = sqrt(max(0.0, 1.0 - sin2T));
    float3 Tdir = normalize(eta * I + (eta * cosI - cosT) * Nf);

    outRay.origin = hit.pos + Tdir * eps;
    outRay.dir = Tdir;
     
    nextIor = n2;  // update medium
    return true;
}

// ---------------------- Work ray system ----------------------
#define MAX_RAYS 64

struct WorkRay
{
    Ray     ray;
    float3  weight;
    float   currentIor;
    float3  currentAbsorption;
    int     depth;
};

WorkRay MakeWorkRay(Ray ray, float3 weight, float currentIor, int depth, float3 absorption)
{
    WorkRay w;
    w.ray = ray;
    w.weight = weight;
    w.currentIor = currentIor;
    w.depth = depth;
    w.currentAbsorption = absorption;
    return w;
}

#endif // RAY_HLSL
