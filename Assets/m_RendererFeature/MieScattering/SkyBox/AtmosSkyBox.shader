Shader "Custom/URP Fixed Skybox"
{
    Properties
    {
        [Header(Gradient Sky)]
        _TopColor ("Top", Color) = (0.17, 0.36, 0.81, 1)
        _BottomColor ("Bottom", Color) = (0.48, 0.75, 0.91, 1)
        _GradientHeight ("Gradient Height", Range(-1, 1)) = 0.5
        [Header(Skybox Cubemap)]
        [NoScaleOffset] _Cubemap ("Cubemap", Cube) = "grey" {}
        _CubemapBlend ("Cubemap Intensity", Range(0, 1)) = 0.0
        _Exposure ("Exposure", Range(0, 8)) = 1.0
    }
    SubShader
    {
        Tags
        {
            "RenderPipeline"="UniversalPipeline"
            "Queue"="Background"        // 最先渲染
            "RenderType"="Background"   // 标识为背景
            "PreviewType"="Skybox"      // 在材质面板显示为天空球
            "IgnoreProjector"="True"
        }
        LOD 100
        Cull Off      // 内部渲染所有面
        ZWrite Off    // 不写入深度，避免遮挡
        ZTest LEqual  // 默认深度测试
        Blend One Zero

        Pass
        {
            Name "Unlit"

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            // 明确声明不进行雾效、光照图等处理，避免额外采样
            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            struct Attributes
            {
                float4 vertex : POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 vertex : SV_POSITION;
                float3 viewDir : TEXCOORD0;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            CBUFFER_START(UnityPerMaterial)
                half4 _TopColor;
                half4 _BottomColor;
                half _GradientHeight;
                half _CubemapBlend;
                half _Exposure;
                samplerCUBE _Cubemap;
            CBUFFER_END

            Varyings vert(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                // 关键修正：使用标准的顶点变换，不再手动干预深度值。
                // 天空盒的“背景”特性由Tags中的Queue和ZWrite Off保证。
                o.vertex = TransformObjectToHClip(v.vertex.xyz);
                // 获取世界空间视图方向用于采样
                float3 worldPos = TransformObjectToWorld(v.vertex.xyz);
                o.viewDir = GetWorldSpaceViewDir(worldPos);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                // 1. 计算基础渐变颜色
                float3 viewDirNormalized = normalize(i.viewDir);
                float gradientFactor = saturate(viewDirNormalized.y * _GradientHeight + (1.0 - _GradientHeight));
                half3 color = lerp(_BottomColor.rgb, _TopColor.rgb, gradientFactor);

                // 2. 可选：混合立方体贴图
                if (_CubemapBlend > 0.001)
                {
                    // 对视图方向取反，以从“内部”正确采样cubemap
                    float3 sampleDir = -i.viewDir;
                    half3 cubemapColor = texCUBE(_Cubemap, sampleDir).rgb;
                    color = lerp(color, cubemapColor, _CubemapBlend);
                }

                // 3. 应用曝光
                color *= _Exposure;

                return half4(color, 1.0);
            }
            ENDHLSL
        }
    }
    FallBack Off
}