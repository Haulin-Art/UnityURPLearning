Shader "Hidden/FrequencyHighlight/FFTVisualize"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        LOD 100
        ZTest Always ZWrite Off Cull Off

        Pass
        {
            Name "FFTVisualize"

            HLSLPROGRAM
            #pragma vertex VertexSimple
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

            Varyings VertexSimple(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.uv = input.uv;
                return output;
            }

            float4 frag(Varyings input) : SV_Target
            {
                // 读取复数数据：R=实部，G=虚部
                float4 data = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv);
                float realPart = data.r;
                float imagPart = data.g;
                
                // 计算幅度
                float magnitude = sqrt(realPart * realPart + imagPart * imagPart);
                
                // 对数缩放，使低频细节更清晰
                // log(1 + x) 可以避免log(0)的问题
                float logMagnitude = log(1.0 + magnitude);
                
                // 归一化到0-1范围（假设最大值约为10左右，可以根据实际情况调整）
                float normalized = saturate(logMagnitude / 5.0);
                
                return float4(normalized, normalized, normalized, 1.0);
            }
            ENDHLSL
        }
    }
}
