Shader "Hidden/FluidFlux/CausticsGenerator"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }

    HLSLINCLUDE
    #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

    struct Attributes
    {
        float4 positionOS : POSITION;
        float2 uv : TEXCOORD0;
    };

    struct Varyings
    {
        float4 positionCS : SV_POSITION;
        float2 uv : TEXCOORD0;
    };

    Varyings Vert(Attributes input)
    {
        Varyings output;
        output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
        output.uv = input.uv;
        return output;
    }

    float Hash(float2 p)
    {
        return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
    }

    float Noise(float2 p)
    {
        float2 i = floor(p);
        float2 f = frac(p);
        f = f * f * (3.0 - 2.0 * f);

        float a = Hash(i);
        float b = Hash(i + float2(1.0, 0.0));
        float c = Hash(i + float2(0.0, 1.0));
        float d = Hash(i + float2(1.0, 1.0));

        return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
    }

    float FBM(float2 p, int octaves)
    {
        float value = 0.0;
        float amplitude = 0.5;
        float frequency = 1.0;

        for (int i = 0; i < octaves; i++)
        {
            value += amplitude * Noise(p * frequency);
            amplitude *= 0.5;
            frequency *= 2.0;
        }

        return value;
    }

    float Voronoi(float2 uv, float scale)
    {
        float2 g = floor(uv * scale);
        float2 f = frac(uv * scale);

        float minDist = 1.0;
        float minDist2 = 1.0;

        for (int y = -1; y <= 1; y++)
        {
            for (int x = -1; x <= 1; x++)
            {
                float2 offset = float2(x, y);
                float2 cellPoint = g + offset;
                cellPoint = cellPoint + Hash(cellPoint) * 0.8 + 0.1;

                float d = length(cellPoint - (g + f));

                if (d < minDist)
                {
                    minDist2 = minDist;
                    minDist = d;
                }
                else if (d < minDist2)
                {
                    minDist2 = d;
                }
            }
        }

        return minDist2 - minDist;
    }

    float CausticsPattern(float2 uv, float time)
    {
        float2 uv1 = uv + float2(time * 0.02, time * 0.015);
        float2 uv2 = uv * 1.3 + float2(-time * 0.018, time * 0.022);
        float2 uv3 = uv * 0.7 + float2(time * 0.025, -time * 0.017);

        float v1 = Voronoi(uv1, 8.0);
        float v2 = Voronoi(uv2, 6.0);
        float v3 = Voronoi(uv3, 10.0);

        float caustics = (v1 + v2 + v3) / 3.0;
        caustics = pow(caustics, 1.5);

        float n = FBM(uv * 3.0 + time * 0.1, 4);
        caustics *= 0.8 + 0.2 * n;

        return saturate(caustics);
    }

    float4 GenerateCaustics(Varyings input) : SV_Target
    {
        float time = _Time.y * 0.5;
        float caustics = CausticsPattern(input.uv, time);
        return float4(caustics.xxx, 1.0);
    }

    float4 GenerateCausticsRGB(Varyings input) : SV_Target
    {
        float time = _Time.y * 0.5;
        
        float r = CausticsPattern(input.uv + float2(0.0, 0.0), time);
        float g = CausticsPattern(input.uv + float2(0.1, 0.05), time * 1.1);
        float b = CausticsPattern(input.uv + float2(0.05, 0.1), time * 0.9);

        return float4(r, g, b, 1.0);
    }

    ENDHLSL

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        LOD 100

        Pass
        {
            Name "GenerateCaustics"
            
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment GenerateCaustics
            ENDHLSL
        }

        Pass
        {
            Name "GenerateCausticsRGB"
            
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment GenerateCausticsRGB
            ENDHLSL
        }
    }
}
