Shader "PCGClass/VolumetricMarble"
{
    Properties
    {
        _Scale ("Scale", Float) = 2.0
        _Turbulence ("Turbulence", Float) = 2.0
        _Frequency ("Vein Frequency", Float) = 5.0
        _Octaves("FBM Octaves", Float) = 4.0
        _Sharpness("Sharpness", Float) = 1.0
        _RotateAxis ("Rotate Axis (Object Space)", Vector) = (0,1,0,0)
        _RotateAngle ("Rotate Angle (Degrees)", Range(0,360)) = 25
        _ColorA ("Marble Light", Color) = (0.85,0.85,0.9,1)
        _ColorB ("Marble Dark", Color) = (0.2,0.2,0.25,1)
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 200

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            float _Scale;
            float _Turbulence;
            float _Frequency;
            float4 _ColorA;
            float4 _ColorB;
            float _Octaves;
            float4 _RotateAxis;
            float  _RotateAngle;
            float _Sharpness;

            struct appdata
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float3 objPos : TEXCOORD0;
                float3 normal : TEXCOORD1;
            };

            v2f vert (appdata v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.objPos = v.vertex.xyz;
                o.normal = UnityObjectToWorldNormal(v.normal);
                return o;
            }

            // ------------------------------
            // Fade function
            float3 fade(float3 t)
            {
                return t*t*t*(t*(t*6.0 - 15.0) + 10.0);
            }

            // Hash-based pseudo random gradient
            float3 randomGradient(float3 p)
            {
                p = float3(dot(p, float3(127.1,311.7,74.7)),
                           dot(p, float3(269.5,183.3,246.1)),
                           dot(p, float3(113.5,271.9,124.6)));
                return normalize(frac(sin(p)*43758.5453)*2.0 - 1.0);
            }

            // 3d gradient noise
            float gradientNoise3D(float3 p)
            {
                float3 i = floor(p);
                float3 f = frac(p);

                float3 g000 = randomGradient(i + float3(0,0,0));
                float3 g100 = randomGradient(i + float3(1,0,0));
                float3 g010 = randomGradient(i + float3(0,1,0));
                float3 g110 = randomGradient(i + float3(1,1,0));
                float3 g001 = randomGradient(i + float3(0,0,1));
                float3 g101 = randomGradient(i + float3(1,0,1));
                float3 g011 = randomGradient(i + float3(0,1,1));
                float3 g111 = randomGradient(i + float3(1,1,1));

                float n000 = dot(g000, f - float3(0,0,0));
                float n100 = dot(g100, f - float3(1,0,0));
                float n010 = dot(g010, f - float3(0,1,0));
                float n110 = dot(g110, f - float3(1,1,0));
                float n001 = dot(g001, f - float3(0,0,1));
                float n101 = dot(g101, f - float3(1,0,1));
                float n011 = dot(g011, f - float3(0,1,1));
                float n111 = dot(g111, f - float3(1,1,1));

                float3 u = fade(f);

                float nx00 = lerp(n000, n100, u.x);
                float nx10 = lerp(n010, n110, u.x);
                float nx01 = lerp(n001, n101, u.x);
                float nx11 = lerp(n011, n111, u.x);

                float nxy0 = lerp(nx00, nx10, u.y);
                float nxy1 = lerp(nx01, nx11, u.y);

                float nxyz = lerp(nxy0, nxy1, u.z);

                return saturate(nxyz * 0.5 + 0.5);
            }

            // The usual fBm
            float fbm(float3 p)
            {
                float value = 0.0;
                float amplitude = 0.5;

                for(int i = 0; i < _Octaves; i++)
                {
                    value += gradientNoise3D(p) * amplitude;
                    p *= 2.0;
                    amplitude *= 0.5;
                }

                return value;
            }

            float3 rotateAxisAngle(float3 p, float3 axis, float angleRad)
            {
                axis = normalize(axis);
                float s = sin(angleRad);
                float c = cos(angleRad);

                // Rodrigues formula - compact way to rotate a point around a given axis 
                // (Olinde Rodrigues - french mathematician)
                return p * c + cross(axis, p) * s + axis * dot(axis, p) * (1.0 - c);
            }

            fixed4 frag (v2f i) : SV_Target
            {
                float3 p = i.objPos * _Scale;

                float angleRad = radians(_RotateAngle);
                p = rotateAxisAngle(p, _RotateAxis.xyz, angleRad);

                // Get some fBm noise to use as turbulence
                float t = fbm(p) * _Turbulence;
                // Marble is just sines at a certain frequency, with the turbulence applied to it
                float marble = sin(p.x * _Frequency + t);
                // Remap from [-1, 1] to [0, 1]
                marble = marble * 0.5 + 0.5;
                // Enchance sharpness of veins
                marble = pow(marble, _Sharpness);
                // Lerp for color
                float3 col = lerp(_ColorA.rgb, _ColorB.rgb, marble);

                return float4(col, 1);
            }

            ENDCG
        }
    }
}
