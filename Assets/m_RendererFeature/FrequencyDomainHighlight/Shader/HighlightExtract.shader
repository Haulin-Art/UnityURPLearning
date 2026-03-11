Shader "Hidden/FrequencyHighlight/HighlightExtract"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _Threshold ("Threshold", Range(0, 1)) = 0.5
        _Softness ("Softness", Range(0.01, 1)) = 0.1
        _DistanceMin ("Distance Min", Float) = 1.0
        _DistanceMax ("Distance Max", Float) = 100.0
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        LOD 100
        ZTest Always ZWrite Off Cull Off

        Pass
        {
            Name "HighlightExtract"

            HLSLPROGRAM
            #pragma vertex VertexSimple
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

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

            float _Threshold;
            float _Softness;
            float _DistanceMin;
            float _DistanceMax;

            Varyings VertexSimple(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.uv = input.uv;
                return output;
            }

            float4 frag(Varyings input) : SV_Target
            {
                float3 color = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv).rgb;
                
                // 转换为灰度（使用感知亮度权重）
                float luminance = dot(color, float3(0.2126, 0.7152, 0.0722));
                
                // 使用smoothstep提取高光区域
                float highlight = smoothstep(_Threshold, _Threshold + _Softness, luminance);
                
                // 采样深度纹理
                float depth = SampleSceneDepth(input.uv);
                
                // 转换为线性深度（视图空间深度）
                float linearDepth = LinearEyeDepth(depth, _ZBufferParams);
                
                // 使用smoothstep进行距离限制
                // 在DistanceMin到DistanceMax之间平滑过渡
                // 超过DistanceMax的地方会被忽略（变黑）
                float distanceFactor = smoothstep(_DistanceMax,_DistanceMin,  linearDepth);
                
                // 结合亮度高光和距离因子
                highlight *= distanceFactor;
                
                return float4(highlight, highlight, highlight, 1.0);
            }
            ENDHLSL
        }
    }
}
