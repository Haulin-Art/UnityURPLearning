Shader "Custom/PlanarReflectionShader"
{
    Properties
    {
        _Color ("Color", Color) = (1,1,1,1)
        _ReflectionStrength ("Reflection Strength", Range(0,1)) = 0.5
        _FresnelPower ("Fresnel Power", Range(0.1,10)) = 2.0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" }
        LOD 100

        Pass
        {
            Name "Forward"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            // 全局反射纹理
            TEXTURE2D(_PlanarReflectionTexture);
            SAMPLER(sampler_PlanarReflectionTexture);

            // 材质属性
            CBUFFER_START(UnityPerMaterial)
            float4 _Color;
            float _ReflectionStrength;
            float _FresnelPower;
            CBUFFER_END

            // 顶点输入
            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
            };

            // 片元输入
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float fogFactor : TEXCOORD2;
            };

            // 顶点着色器
            Varyings vert(Attributes input)
            {
                Varyings output;
                // 计算世界空间位置和法线
                output.positionWS = TransformObjectToWorld(input.positionOS.xyz);
                output.normalWS = normalize(TransformObjectToWorldNormal(input.normalOS));
                // 计算裁剪空间位置
                output.positionCS = TransformWorldToHClip(output.positionWS);
                // 计算雾因子
                output.fogFactor = ComputeFogFactor(output.positionCS.z);
                return output;
            }

            // 片元着色器
            float4 frag(Varyings input) : SV_Target
            {
                // 计算视图方向
                float3 viewDir = normalize(_WorldSpaceCameraPos - input.positionWS);
                // 计算菲涅尔效应
                float fresnel = pow(1.0 - saturate(dot(input.normalWS, viewDir)), _FresnelPower);

                // 计算反射UV
                float4 reflectionClipPos = mul(unity_MatrixVP, float4(input.positionWS, 1.0));
                float2 reflectionUV = reflectionClipPos.xy / reflectionClipPos.w;
                reflectionUV = reflectionUV * 0.5 + 0.5;

                // 采样反射纹理
                float4 reflectionColor = SAMPLE_TEXTURE2D(_PlanarReflectionTexture, sampler_PlanarReflectionTexture, reflectionUV);

                // 计算最终颜色
                float4 finalColor = lerp(_Color, reflectionColor, _ReflectionStrength * fresnel);

                // 应用雾效
                finalColor.rgb = MixFog(finalColor.rgb, input.fogFactor);

                return finalColor;
            }
            ENDHLSL
        }
    }
    FallBack "Universal Render Pipeline/Lit"
}
