Shader "Custom/AdvancedArrayInstanced"
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

            // GPU Instancing 支持
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

            // ============================================
            // 实例数据结构（与Compute Shader保持一致）
            // ============================================
            struct InstanceData
            {
                float3 position;
                float padding;
            };

            // ============================================
            // Compute Buffer 声明
            // ============================================
            StructuredBuffer<InstanceData> _InstanceDataBuffer;

            // ============================================
            // 实例变换参数（作为全局参数传入）
            // ============================================
            float3 _InstanceScale;
            float4 _InstanceRotation;

            // ============================================
            // 纹理声明
            // ============================================
            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            // ============================================
            // 材质属性缓冲区
            // ============================================
            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half4 _BaseColor;
                half _Metallic;
                half _Smoothness;
            CBUFFER_END

            // ============================================
            // 顶点输入结构体
            // ============================================
            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
                float2 uv : TEXCOORD0;
                float2 lightmapUV : TEXCOORD1;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            // ============================================
            // 顶点到片元的数据传递结构体
            // ============================================
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
                float4 tangentWS : TEXCOORD3;
                float fogFactor : TEXCOORD4;
                float2 lightmapUV : TEXCOORD5;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            // ============================================
            // 四元数旋转函数
            // ============================================
            float3 RotateByQuaternion(float3 v, float4 q)
            {
                float3 t = 2.0 * cross(q.xyz, v);
                return v + q.w * t + cross(q.xyz, t);
            }

            // ============================================
            // 顶点着色器
            // ============================================
            Varyings vert(Attributes input, uint instanceID : SV_InstanceID)
            {
                Varyings output;

                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);

                // 从ComputeBuffer获取实例位置
                float3 instancePosition = _InstanceDataBuffer[instanceID].position;

                // 应用缩放
                float3 localPos = input.positionOS.xyz * _InstanceScale;

                // 应用旋转
                localPos = RotateByQuaternion(localPos, _InstanceRotation);

                // 计算最终世界位置
                float3 positionWS = instancePosition + localPos;

                // 获取顶点位置信息
                VertexPositionInputs vertexInput;
                vertexInput.positionCS = TransformObjectToHClip(positionWS);
                vertexInput.positionWS = positionWS;

                // 获取法线和切线信息
                float3 normalOS = RotateByQuaternion(input.normalOS, _InstanceRotation);
                float3 tangentOS = RotateByQuaternion(input.tangentOS.xyz, _InstanceRotation);
                VertexNormalInputs normalInput = GetVertexNormalInputs(normalOS, float4(tangentOS, input.tangentOS.w));

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

            // ============================================
            // 片元着色器
            // ============================================
            half4 frag(Varyings input) : SV_Target
            {
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
                inputData.bakedGI = SampleSH(input.normalWS);
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

        // ============================================
        // 阴影投射Pass
        // ============================================
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

            // 实例数据结构
            struct InstanceData
            {
                float3 position;
                float padding;
            };

            StructuredBuffer<InstanceData> _InstanceDataBuffer;
            float3 _InstanceScale;
            float4 _InstanceRotation;

            // 阴影Pass专用结构体
            struct ShadowAttributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct ShadowVaryings
            {
                float4 positionCS : SV_POSITION;
            };

            float3 RotateByQuaternion(float3 v, float4 q)
            {
                float3 t = 2.0 * cross(q.xyz, v);
                return v + q.w * t + cross(q.xyz, t);
            }

            ShadowVaryings ShadowPassVertex(ShadowAttributes input, uint instanceID : SV_InstanceID)
            {
                ShadowVaryings output;
                UNITY_SETUP_INSTANCE_ID(input);

                float3 instancePosition = _InstanceDataBuffer[instanceID].position;
                float3 localPos = input.positionOS.xyz * _InstanceScale;
                localPos = RotateByQuaternion(localPos, _InstanceRotation);
                float3 positionWS = instancePosition + localPos;

                // 阴影投射位置计算
                float3 normalWS = RotateByQuaternion(input.normalOS, _InstanceRotation);
                Light mainLight = GetMainLight();
                float3 shadowPos = positionWS - mainLight.direction * 0.1;

                output.positionCS = TransformWorldToHClip(shadowPos);
                return output;
            }

            half4 ShadowPassFragment(ShadowVaryings input) : SV_Target
            {
                return 0;
            }

            ENDHLSL
        }

        // ============================================
        // 深度Only Pass
        // ============================================
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

            // 实例数据结构
            struct InstanceData
            {
                float3 position;
                float padding;
            };

            StructuredBuffer<InstanceData> _InstanceDataBuffer;
            float3 _InstanceScale;
            float4 _InstanceRotation;

            // 深度Pass专用结构体
            struct DepthAttributes
            {
                float4 positionOS : POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct DepthVaryings
            {
                float4 positionCS : SV_POSITION;
            };

            float3 RotateByQuaternion(float3 v, float4 q)
            {
                float3 t = 2.0 * cross(q.xyz, v);
                return v + q.w * t + cross(q.xyz, t);
            }

            DepthVaryings DepthOnlyVertex(DepthAttributes input, uint instanceID : SV_InstanceID)
            {
                DepthVaryings output;
                UNITY_SETUP_INSTANCE_ID(input);

                float3 instancePosition = _InstanceDataBuffer[instanceID].position;
                float3 localPos = input.positionOS.xyz * _InstanceScale;
                localPos = RotateByQuaternion(localPos, _InstanceRotation);
                float3 positionWS = instancePosition + localPos;

                output.positionCS = TransformWorldToHClip(positionWS);
                return output;
            }

            half4 DepthOnlyFragment(DepthVaryings input) : SV_Target
            {
                return 0;
            }

            ENDHLSL
        }
    }
    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}
