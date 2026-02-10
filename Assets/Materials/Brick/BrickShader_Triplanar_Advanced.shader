Shader "PCGClass/BrickTexture_Triplanar_Advanced"
{
    Properties
    {
        // Equivalent to iChannel0 in Shadertoy: a small gradient lookup texture (RG in [0..1])
        [NoScaleOffset]
        _GradTex ("Gradient Texture (RG)", 2D) = "white" {}

        _Tiles ("TILES (x,y)", Vector) = (4, 3, 0, 0)
        _MortarThickness ("MORTAR_THICKNESS", Range(0, 0.25)) = 0.04

        _BrickColor ("Brick Base Color", Color) = (0.55, 0.18, 0.14, 1)
        _BrickNoiseFreq   ("Brick Noise Frequency", Float) = 7.31
        _BrickGrainFreq   ("Brick Grain Frequency", Float) = 22.0
        _BrickNoiseAmount ("Brick Noise Amount", Range(0, 1)) = 0.35
        _BrickFBMOctaves   ("Brick fBM Octaves", Range(1,8)) = 4

        _MortarEdgeNoiseFreq   ("Mortar Edge Noise Freq", Float) = 3.0
        _MortarEdgeNoiseAmp    ("Mortar Edge Noise Amount", Range(0,0.2)) = 0.05
        _MortarColor ("Mortar Base Color", Color) = (0.45, 0.45, 0.45, 1)
        _MortarNoiseFreq   ("Mortar Noise Frequency", Float) = 18.7
        _MortarNoiseAmount ("Mortar Noise Amount", Range(0, 1)) = 0.25
        _MortarFBMOctaves  ("Mortar fBM Octaves", Range(1,8)) = 3

        _FBM_Lacunarity ("fBM Lacunarity", Float) = 2.0
        _FBM_Gain       ("fBM Gain", Float) = 0.5

        // Planar projection scale in world units (bigger = larger bricks)
        _PlanarScale ("Planar UV Scale", Float) = 1.0

        _TriplanarBlendFactor ("Triplanar Blend Factor", Float) = 4.0

        _SupersampleCount ("Supersample Count", Range(1,32)) = 1
        _SupersampleRadius ("Supersample Radius", Float) = 0.002
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" "RenderPipeline"="UniversalPipeline" }
        Pass
        {
            Name "ForwardUnlit"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            // --- Textures / uniforms ---
            TEXTURE2D(_GradTex);
            SAMPLER(sampler_GradTex); // (not used for Load, but Unity expects it)

            float4 _GradTex_TexelSize; // x=1/w, y=1/h, z=w, w=h
            float4 _Tiles;             // use .xy
            float  _MortarThickness;

            float4 _BrickColor;
            float4 _MortarColor;
            float  _PlanarScale;

            float _BrickNoiseFreq;
            float _BrickGrainFreq;
            float _BrickNoiseAmount;

            float _MortarEdgeNoiseFreq;
            float _MortarEdgeNoiseAmp;
            float _MortarNoiseFreq;
            float _MortarNoiseAmount;

            int   _BrickFBMOctaves;
            int   _MortarFBMOctaves;
            float _FBM_Lacunarity;
            float _FBM_Gain;

            float _TriplanarBlendFactor;

            int   _SupersampleCount;
            float _SupersampleRadius;

            float2 hash22(float2 p)
            {
                uint x = asuint(p.x * 1234.5);
                uint y = asuint(p.y * 5678.9);
                uint h = x * 374761393u + y * 668265263u;
                h = (h ^ (h >> 13)) * 1274126177u;
                return float2(h & 65535u, (h >> 16) & 65535u) / 65535.0;
            }

            // Fade curve (Perlin's improved fade).
            float2 fade(float2 t)
            {
                return t*t*t*(t*(t*6.0 - 15.0) + 10.0);
            }

            // Fetch a gradient vector from _GradTex at integer grid coord 'p'
            // Equivalent to texelFetch(iChannel0, q, 0).rg * 2 - 1.
           float2 gradAt(int2 p)
            {
                uint w, h;
                _GradTex.GetDimensions(w, h);
                int2 res = int2((int)w, (int)h);

                // Wrap coordinates into texture range (positive modulo)
                int2 q = int2((p.x % res.x + res.x) % res.x, (p.y % res.y + res.y) % res.y);

                float4 texel = _GradTex.Load(int3(q, 0));

                float2 g = texel.rg * 2.0 - 1.0;

                // Safe normalize (avoid NaNs if g ~= 0)
                float len2 = dot(g, g);
                if (len2 < 1e-6) return float2(1, 0);
                return g * rsqrt(len2);
            }

            // 2D Gradient Noise (Perlin-style), using gradient texture as lattice gradients.
            // Returns a *signed* value roughly in [-0.7, 0.7].
            float gradientNoise2D_Signed(float2 p)
            {
                int2   i = (int2)floor(p);  // cell integer coords
                float2 f = frac(p);         // local coords in [0..1)

                // Gradients at four corners
                float2 g00 = gradAt(i + int2(0, 0));
                float2 g10 = gradAt(i + int2(1, 0));
                float2 g01 = gradAt(i + int2(0, 1));
                float2 g11 = gradAt(i + int2(1, 1));

                // Displacement vectors from corners to point
                float2 d00 = f - float2(0.0, 0.0);
                float2 d10 = f - float2(1.0, 0.0);
                float2 d01 = f - float2(0.0, 1.0);
                float2 d11 = f - float2(1.0, 1.0);

                // Dot products (influence)
                float n00 = dot(g00, d00);
                float n10 = dot(g10, d10);
                float n01 = dot(g01, d01);
                float n11 = dot(g11, d11);

                // Interpolate
                float2 u  = fade(f);
                float nx0 = lerp(n00, n10, u.x);
                float nx1 = lerp(n01, n11, u.x);
                float nxy = lerp(nx0, nx1, u.y);

                return nxy;
            }

            // Convenience wrapper: map signed noise to [0,1] without hard clipping.
            float gradientNoise2D_01(float2 p)
            {
                // Conservative remap range for the Perlin-style kernel.
                float n = gradientNoise2D_Signed(p);
                return (n + 0.7) / 1.4;
            }

            // fBM built from signed gradient noise.
            // Includes a small rotation + shift each octave to avoid sampling artifacts
            // (e.g. when frequencies/inputs land on lattice-aligned coordinates).
            float fbm01(float2 p, int octaves)
            {
                float sum = 0.0;
                float amp = 0.5;
                float freq = 1.0;

                float ampSum = 0.0;

                // Fixed rotation matrix (approx 2D rotation by ~0.5 rad)
                float2x2 rot = float2x2(0.87758, -0.47943,
                                        0.47943,  0.87758);
                float2 shift = float2(37.2, 91.7);

                for (int i = 0; i < 8; i++) // hard max
                {
                    if (i >= octaves) break;

                    sum += amp * gradientNoise2D_Signed(p * freq);
                    ampSum += amp;

                    // Decorrelate octaves a bit
                    p = mul(rot, p) + shift;
                    shift *= 1.17;

                    freq *= _FBM_Lacunarity;
                    amp  *= _FBM_Gain;
                }

                // Normalize to [-1,1] then remap to [0,1]
                float n = (ampSum > 0.0) ? (sum / ampSum) : 0.0;
                return n * 0.5 + 0.5;
            }

            // Mask: 1 = mortar, 0 = brick
            float mortarMaskNoisy(float2 tileUV)
            {
                float2 f = frac(tileUV);

                float dx = min(f.x, 1.0 - f.x);
                float dy = min(f.y, 1.0 - f.y);

                float d = min(dx, dy);

                // Low-frequency noise to perturb the boundary
                float n = gradientNoise2D_01(tileUV * _MortarEdgeNoiseFreq);

                // Signed noise in [-1,1]
                n = n * 2.0 - 1.0;

                d += n * _MortarEdgeNoiseAmp;

                return step(d, _MortarThickness);
            }

            // ---------------------------------------------------------
            // Entry point requested: equivalent to Shadertoy "main"
            // ---------------------------------------------------------
            float3 brickTexture(float2 inUV)
            {
                // Work in *tile space* for everything related to the brick layout.
                // This keeps _Tiles behaving intuitively (more tiles per unit).
                float2 tileUV0 = inUV * _Tiles.xy;

                // IMPORTANT: parity must be stable for negative rows too
                int row = (int)floor(tileUV0.y);
                float oddRow = (float)(row & 1);

                // Stagger in tile space: half a brick = +0.5 in tile units
                float2 tileUV = tileUV0;
                tileUV.x += oddRow * 0.5;

                float2 cell      = floor(tileUV);
                float2 cellCoord = frac(tileUV);

                // Mortar mask must be computed in the same (staggered) tile space,
                // otherwise mortar thickness/noise won't match the brick layout.
                float mMask = mortarMaskNoisy(tileUV);

                // Base colors
                float3 brickBase  = _BrickColor.rgb;
                float3 mortarBase = _MortarColor.rgb;

                // Brick variation:
                //  - a low-frequency per-brick "tone" (stable)
                //  - plus a higher-frequency in-brick detail (continuous)
                float brickTone   = fbm01(cell * _BrickNoiseFreq + 17.3, _BrickFBMOctaves);
                float brickDetail = fbm01((cell + cellCoord) * _BrickGrainFreq + 53.1, _BrickFBMOctaves);
                float brickNoise  = lerp(brickTone, brickDetail, 0.35);

                // Mortar color variation (use inUV so it isn't "locked" to the brick staggering)
                float mortarNoise = fbm01(inUV * _MortarNoiseFreq + 91.7, _MortarFBMOctaves);

                // Signed modulation
                float brickMod  = 1.0 + (brickNoise  * 2.0 - 1.0) * _BrickNoiseAmount;
                float mortarMod = 1.0 + (mortarNoise * 2.0 - 1.0) * _MortarNoiseAmount;

                float3 brickCol  = brickBase  * brickMod;
                float3 mortarCol = mortarBase * mortarMod;

                // Blend: mortar where mask=1, brick where mask=0
                return lerp(brickCol, mortarCol, mMask);
            }

            // =========================================================
            // Planar projection: derive UV from world position + normal
            // =========================================================

            float3 SafeNormalize3(float3 v)
            {
                float len2 = dot(v, v);
                if (len2 < 1e-8) return float3(0, 1, 0);
                return v * rsqrt(len2);
            }

            float2 PlanarUV_Object(float3 positionOS, float3 normalOS)
            {
                float3 n = SafeNormalize3(normalOS);

                float3 helper = (abs(n.y) < 0.999) ? float3(0, 1, 0) : float3(1, 0, 0);
                float3 t = normalize(cross(helper, n));
                float3 b = cross(n, t);

                // remove component along normal (project onto tangent plane)
                float3 pPlane = positionOS - n * dot(positionOS, n);

                float2 uv;
                uv.x = dot(pPlane, t);
                uv.y = dot(pPlane, b);

                uv *= _PlanarScale;
                return uv;
            }

            // =========================================================
            // URP boilerplate
            // =========================================================

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float3 positionOS  : TEXCOORD0;
                float3 normalOS    : TEXCOORD1;
            };

            Varyings vert (Attributes IN)
            {
                Varyings OUT;

                VertexPositionInputs posInputs = GetVertexPositionInputs(IN.positionOS.xyz);

                OUT.positionHCS = posInputs.positionCS;
                OUT.positionOS  = IN.positionOS.xyz;
                OUT.normalOS    = normalize(IN.normalOS);

                return OUT;
            }

            half4 frag (Varyings IN) : SV_Target
            {
                float3 p = IN.positionOS * _PlanarScale;
                float3 n = normalize(IN.normalOS);

                float3 w = abs(n);
                w = max(w, 1e-4);
                w = pow(w, max(1.0, _TriplanarBlendFactor));
                w /= (w.x + w.y + w.z + 1e-6);

                float3 accum = 0.0;

                int samples = max(1, _SupersampleCount);

                for (int i = 0; i < 32; i++)
                {
                    if (i >= samples) break;

                    // Jitter in the *pixel footprint* of each projection (procedural SSAA).
                    // This makes the filter naturally stronger as the object gets farther away.
                    float2 r = hash22(IN.positionHCS.xy + (float)i * 19.19) * 2.0 - 1.0;

                    float2 uvX = p.zy;
                    float2 uvY = p.xz;
                    float2 uvZ = p.xy;

                    float2 jx = (r.x * ddx(uvX) + r.y * ddy(uvX)) * _SupersampleRadius;
                    float2 jy = (r.x * ddx(uvY) + r.y * ddy(uvY)) * _SupersampleRadius;
                    float2 jz = (r.x * ddx(uvZ) + r.y * ddy(uvZ)) * _SupersampleRadius;

                    uvX += jx;
                    uvY += jy;
                    uvZ += jz;

                    float3 col =
                          brickTexture(uvX) * w.x +
                          brickTexture(uvY) * w.y +
                          brickTexture(uvZ) * w.z;

                    accum += col;
                }

                accum /= samples;
                return half4(accum, 1.0);
            }

            ENDHLSL
        }
    }
}
