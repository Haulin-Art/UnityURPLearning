Shader "Custom/PlanarReflectionTest"
{
    Properties
    {
        _Tint ("Tint Color", Color) = (1,1,1,1)
        _ReflectionStrength ("Reflection Strength", Range(0,1)) = 1
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
        }

        Pass
        {
            Name "PlanarReflection"
            ZWrite On
            Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float4 screenPos  : TEXCOORD0;
            };

            /* 来自 PlanarReflections.cs */
            TEXTURE2D(_PlanarReflectionTexture);
            SAMPLER(sampler_PlanarReflectionTexture);

            CBUFFER_START(UnityPerMaterial)
                half4 _Tint;
                half  _ReflectionStrength;
            CBUFFER_END

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.screenPos  = ComputeScreenPos(OUT.positionCS);
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                // ✅ 正确的屏幕 UV（自动处理 DX / OpenGL）
                float2 screenUV = IN.screenPos.xy / IN.screenPos.w;

                // ✅ 解决部分平台上下颠倒的问题
                #if UNITY_UV_STARTS_AT_TOP
                    screenUV.y = 1.0 - screenUV.y;
                #endif

                // ✅ 采样反射纹理
                half3 reflection = SAMPLE_TEXTURE2D(
                    _PlanarReflectionTexture,
                    sampler_PlanarReflectionTexture,
                    screenUV
                ).rgb;

                // ✅ 简单色调校正（防止 HDR 过曝）
                //reflection = max(reflection, 0.0);
                //reflection = reflection / (reflection + 1.0); // Reinhard

                half3 finalColor = reflection * _ReflectionStrength * _Tint.rgb;
                return half4(reflection, 1);
            }
            ENDHLSL
        }
    }
}