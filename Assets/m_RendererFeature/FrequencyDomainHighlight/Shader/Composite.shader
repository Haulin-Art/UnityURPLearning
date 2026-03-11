Shader "Hidden/FrequencyHighlight/Composite"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        //_HighlightTex ("Highlight Texture", 2D) = "white" {} // 这个必须通过代码SetGlobalTexture设置，因为它是一个临时渲染纹理
        _Intensity ("Intensity", Range(0, 5)) = 1.0
        _HighlightColor ("Highlight Color", Color) = (1, 1, 1, 1)
        _BorderFade ("Border Fade", Range(0, 0.5)) = 0.1
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        LOD 100
        ZTest Always ZWrite Off Cull Off

        Pass
        {
            Name "Composite"

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
            TEXTURE2D(_HighlightTex);
            SAMPLER(sampler_HighlightTex);

            float _Intensity;
            float4 _HighlightColor;
            float _BorderFade;

            Varyings VertexSimple(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.uv = input.uv;
                return output;
            }

            float4 frag(Varyings input) : SV_Target
            {
                // 采样原始屏幕颜色
                float4 screenColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv);
                
                // 采样高光纹理（IFFT结果的实部）
                float4 highlightData = SAMPLE_TEXTURE2D(_HighlightTex, sampler_HighlightTex, input.uv);
                float highlight = highlightData.r;
                
                // 边界淡出：防止FFT周期性边界问题
                // 使用smoothstep在边缘区域淡出
                float2 uv = input.uv;
                float borderFade = 1.0;
                
                // 计算到边界的最小距离
                float distToEdge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
                
                // 在边界区域淡出
                borderFade = smoothstep(0.0, _BorderFade, distToEdge);
                
                // 应用边界淡出
                highlight *= borderFade;
                
                // 高光颜色乘以强度
                float3 highlightResult = _HighlightColor.rgb * highlight * _Intensity;
                
                // 叠加混合（Additive Blending）
                float3 finalColor = screenColor.rgb + highlightResult;
                
                return float4(finalColor, 1.0);
            }
            ENDHLSL
        }
    }
}
