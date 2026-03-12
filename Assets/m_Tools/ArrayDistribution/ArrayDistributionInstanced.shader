Shader "Custom/ArrayDistributionInstanced"
{
    Properties
    {
        [MainColor] _BaseColor ("基础颜色", Color) = (1, 1, 1, 1)
        [MainTexture] _BaseMap ("基础纹理", 2D) = "white" {}
        _Metallic ("金属度", Range(0, 1)) = 0
        _Smoothness ("光滑度", Range(0, 1)) = 0.5
    }

    SubShader
    {
        Tags 
        { 
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
        }
        LOD 100

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            // GPU Instancing 支持 - 使用DrawMeshInstanced必须开启
            #pragma multi_compile_instancing

            // 主光源阴影相关变体
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN

            // 额外光源支持
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS

            // 软阴影支持
            #pragma multi_compile_fragment _ _SHADOWS_SOFT

            // 混合光照支持
            #pragma multi_compile _ _MIXED_LIGHTING_SUBTRACTIVE

            // 光照贴图支持
            #pragma multi_compile _ LIGHTMAP_ON

            // 雾效支持
            #pragma multi_compile_fog

            // URP 核心库
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            // 顶点输入结构体
            struct Attributes
            {
                float4 positionOS : POSITION;       // 物体空间位置
                float3 normalOS : NORMAL;           // 物体空间法线
                float4 tangentOS : TANGENT;         // 物体空间切线
                float2 uv : TEXCOORD0;              // 纹理坐标
                float2 lightmapUV : TEXCOORD1;      // 光照贴图UV
                UNITY_VERTEX_INPUT_INSTANCE_ID      // 实例ID（GPU Instancing必需）
            };

            // 顶点到片元的数据传递结构体
            struct Varyings
            {
                float4 positionCS : SV_POSITION;    // 裁剪空间位置
                float2 uv : TEXCOORD0;              // 纹理坐标
                float3 positionWS : TEXCOORD1;      // 世界空间位置
                float3 normalWS : TEXCOORD2;        // 世界空间法线
                float4 tangentWS : TEXCOORD3;       // 世界空间切线（w分量存储副切线符号）
                float fogFactor : TEXCOORD4;        // 雾效因子
                float2 lightmapUV : TEXCOORD5;      // 光照贴图UV
                UNITY_VERTEX_INPUT_INSTANCE_ID      // 实例ID
            };

            // 纹理声明
            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            // 材质属性缓冲区（支持SRP Batcher）
            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;     // 纹理缩放与偏移
                half4 _BaseColor;       // 基础颜色
                half _Metallic;         // 金属度
                half _Smoothness;       // 光滑度
            CBUFFER_END

            // 顶点着色器
            Varyings vert(Attributes input)
            {
                Varyings output;

                // 设置实例ID（GPU Instancing必需）
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);

                // 获取顶点位置信息（物体空间 -> 世界空间 -> 裁剪空间）
                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);

                // 获取法线和切线信息
                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);

                output.positionCS = vertexInput.positionCS;
                output.positionWS = vertexInput.positionWS;
                output.normalWS = normalInput.normalWS;

                // 计算副切线符号并存储切线数据
                real sign = input.tangentOS.w * GetOddNegativeScale();
                output.tangentWS = float4(normalInput.tangentWS.xyz, sign);

                // 变换纹理坐标
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);

                // 计算雾效因子
                output.fogFactor = ComputeFogFactor(vertexInput.positionCS.z);

                // 变换光照贴图UV
                output.lightmapUV = input.lightmapUV * unity_LightmapST.xy + unity_LightmapST.zw;

                return output;
            }

            // 片元着色器
            half4 frag(Varyings input) : SV_Target
            {
                // 设置实例ID（GPU Instancing必需）
                UNITY_SETUP_INSTANCE_ID(input);

                // 采样基础纹理并应用颜色
                half4 albedoAlpha = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
                half3 albedo = albedoAlpha.rgb * _BaseColor.rgb;
                half alpha = albedoAlpha.a * _BaseColor.a;

                // 构建切线空间到世界空间的变换矩阵
                half3 normalTS = half3(0, 0, 1);
                float sgn = input.tangentWS.w;
                float3 bitangent = sgn * cross(input.normalWS.xyz, input.tangentWS.xyz);
                float3x3 tangentToWorld = float3x3(input.tangentWS.xyz, bitangent.xyz, input.normalWS.xyz);
                half3 normalWS = TransformTangentToWorld(normalTS, tangentToWorld);
                normalWS = normalize(normalWS);

                // 填充输入数据结构
                InputData inputData = (InputData)0;
                inputData.positionWS = input.positionWS;
                inputData.normalWS = normalWS;
                inputData.viewDirectionWS = GetWorldSpaceNormalizeViewDir(input.positionWS);
                inputData.shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                inputData.fogCoord = input.fogFactor;
                inputData.bakedGI = SampleSH(input.normalWS);  // 采样球谐光照
                inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(input.positionCS);
                inputData.shadowMask = SAMPLE_SHADOWMASK(input.lightmapUV);

                // 填充表面数据结构
                SurfaceData surfaceData = (SurfaceData)0;
                surfaceData.albedo = albedo;
                surfaceData.metallic = _Metallic;
                surfaceData.smoothness = _Smoothness;
                surfaceData.normalTS = normalTS;
                surfaceData.alpha = alpha;

                // URP PBR光照计算
                half4 color = UniversalFragmentPBR(inputData, surfaceData);

                // 应用雾效
                color.rgb = MixFog(color.rgb, inputData.fogCoord);

                return color;
            }
            ENDHLSL
        }

        // 阴影投射Pass
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"

            ENDHLSL
        }

        // 深度Only Pass（用于深度预渲染）
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }

            ZWrite On
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthOnlyPass.hlsl"

            ENDHLSL
        }
    }
    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}
