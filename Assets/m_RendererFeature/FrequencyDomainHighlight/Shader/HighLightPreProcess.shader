Shader "Hidden/FrequencyHighlight/HighLightPreProcess"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _Scale ("大小缩放", Vector) = (1.0, 1.0, 0.0, 0.0)
        _AspectRatio ("屏幕宽高比", Float) = 1.0
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        LOD 100
        ZTest Always ZWrite Off Cull Off

        Pass
        {
            Name "HighLightPreProcess"

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

            float2 _Scale;
            float _AspectRatio;

            // 这个函数将UV坐标进行转换，用于FFT的高光形状必须得是以图片的四个角为原点进行对称的，否则结果是不对的
            float2 UVTransformForFFT(float2 uv)
            {
                // 步骤1：将UV从[0,1]转换到[-1,1]，并取绝对值使其以中心为对称点
                float2 centeredUV = abs(uv * 2.0 - 1.0);
                
                float2 quadrant = sign(uv * 2.0 - 1.0); // 获取象限信息
                //quantized = 1.0;
                // 步骤2：应用宽高比校正
                // 步骤3：应用缩放
                float2 scaledUV = (centeredUV - 1.0) * _Scale * float2(_AspectRatio, 1.0) * quadrant + float2(0.5, 0.5);
                
                return scaledUV;
            }

            Varyings VertexSimple(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.uv = input.uv;
                return output;
            }

            float4 frag(Varyings input) : SV_Target
            {
                float2 transformedUV = UVTransformForFFT(input.uv);
                float4 color = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, transformedUV);
                return float4(color.rgb, 1.0);
            }
            ENDHLSL
        }
    }
}
