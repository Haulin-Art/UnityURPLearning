Shader "Hidden/GLM_SWE_Debug"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

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

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            Varyings vert(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.uv = input.uv;
                return output;
            }

            float4 frag(Varyings input) : SV_Target
            {
                float4 state = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv);

                float velocity = length(state.rg);
                float height = state.b;

                float3 color = float3(0, 0, 0);

                color.r = saturate(velocity * 0.5);

                float heightDiff = height - 1.0;
                color.g = saturate(heightDiff * 2.0 + 0.5);
                color.b = saturate(-heightDiff * 2.0 + 0.5);

                return float4(color, 1);
            }
            ENDHLSL
        }
    }
}
