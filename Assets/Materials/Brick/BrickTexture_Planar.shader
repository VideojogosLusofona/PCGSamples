Shader "PCGClass/BrickTexture_Planar"
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

        _MortarColor ("Mortar Base Color", Color) = (0.45, 0.45, 0.45, 1)
        _MortarNoiseFreq   ("Mortar Noise Frequency", Float) = 18.7
        _MortarNoiseAmount ("Mortar Noise Amount", Range(0, 1)) = 0.25

        // Planar projection scale in world units (bigger = larger bricks)
        _PlanarScale ("Planar UV Scale", Float) = 1.0
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

            float _MortarNoiseFreq;
            float _MortarNoiseAmount;

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
            float gradientNoise2D(float2 p)
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

                // Remap approx [-0.7..0.7] -> [0..1]
                return saturate((nxy + 0.7) / 1.4);
            }

            // Mask: 1 = mortar, 0 = brick
            float mortarMask(float2 uv)
            {
                float2 f = frac(uv * _Tiles.xy);

                float dx = min(f.x, 1.0 - f.x);
                float dy = min(f.y, 1.0 - f.y);

                float d = min(dx, dy);

                return step(d, _MortarThickness);
            }

            // ---------------------------------------------------------
            // Equivalent to Shadertoy "main"
            // ---------------------------------------------------------
            float3 brickTexture(float2 inUV)
            {
                float2 uv = inUV;

                // Compute tile-space once
                float2 tileUV0 = uv * _Tiles.xy;

                // IMPORTANT: parity must be stable for negative rows too
                int row = (int)floor(tileUV0.y);
                float oddRow = (float)(row & 1);

                // Offset odd rows by half a brick width (in UV space)
                uv.x += oddRow * (0.5 / _Tiles.x);

                // Recompute after offset
                float2 tileUV    = uv * _Tiles.xy;
                float2 cell      = floor(tileUV);
                float2 cellCoord = frac(tileUV);

                float mMask = mortarMask(uv);

                // Base colors
                float3 brickBase  = _BrickColor.rgb;
                float3 mortarBase = _MortarColor.rgb;

                // --- Subtle noise (parameterized) ---
                // Brick: readable per-brick variation + optional grain
                float nBrickA = gradientNoise2D(cell * _BrickNoiseFreq + float2(11.2, 4.7));                 // per-brick
                float nBrickB = gradientNoise2D((cell + cellCoord) * _BrickGrainFreq + float2(3.1, 9.8));    // grain
                float brickNoise = lerp(nBrickA, nBrickB, 0.35);                                             // 0..1

                // Mortar: different frequency/seed so it doesn't line up with bricks
                float mortarNoise = gradientNoise2D(inUV * _MortarNoiseFreq + float2(91.3, 27.5));         // 0..1

                // Turn 0..1 into a signed modulation around 1.0 (more visually obvious)
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
                float2 uv = PlanarUV_Object(IN.positionOS, IN.normalOS);
                float3 col = brickTexture(uv);

                return half4(col, 1);
            }

            ENDHLSL
        }
    }
}
