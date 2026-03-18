// Hi-Z调试显示Shader
// 用于将Hi-Z深度纹理可视化输出到屏幕

Shader "Hidden/HiZ/DebugShow"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        LOD 100
        // 后处理标准设置：始终通过深度测试，不写入深度，不剔除
        ZTest Always ZWrite Off Cull Off

        Pass
        {
            Name "HiZDebugShow"
            
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            
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

            // Hi-Z深度纹理（由C#脚本设置）
            TEXTURE2D(_HiZDepthTex);
            SAMPLER(sampler_HiZDepthTex);

            Varyings Vert(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.uv = input.uv;
                return output;
            }

            // 片元着色器：将深度值转换为灰度颜色输出
            float4 Frag(Varyings input) : SV_Target
            {
                float depth = SAMPLE_TEXTURE2D(_HiZDepthTex, sampler_HiZDepthTex, input.uv).r;
                // 深度值显示为灰度图（深度越大越亮）
                return float4(depth.xxx, 1.0);
            }
            ENDHLSL
        }
    }
}
