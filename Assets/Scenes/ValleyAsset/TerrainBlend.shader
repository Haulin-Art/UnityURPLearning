Shader "Custom/Valley/TerrainBlend"
{
    Properties
    {
        [Header(Rock Textures)]
        _RockAlbedoMap ("岩石颜色贴图", 2D) = "white" {}
        _RockNormalMap ("岩石法线贴图", 2D) = "bump" {}
        _RockAOMap ("岩石AO贴图", 2D) = "white" {}
        _RockRoughnessMap ("岩石粗糙度贴图", 2D) = "white" {}
        _RockNormalScale ("岩石法线强度", Range(0.0, 2.0)) = 1.0
        _RockRoughness ("岩石粗糙度系数", Range(0.0, 2.0)) = 1.0
        
        [Header(Grass Textures)]
        _GrassAlbedoMap ("草地颜色贴图", 2D) = "white" {}
        _GrassNormalMap ("草地法线贴图", 2D) = "bump" {}
        _GrassAOMap ("草地AO贴图", 2D) = "white" {}
        _GrassRoughnessMap ("草地粗糙度贴图", 2D) = "white" {}
        _GrassNormalScale ("草地法线强度", Range(0.0, 2.0)) = 1.0
        _GrassRoughness ("草地粗糙度系数", Range(0.0, 2.0)) = 1.0
        
        [Header(Blend Mask)]
        _BlendMask ("岩石草地混合遮罩", 2D) = "white" {}
        _BlendThreshold ("混合阈值", Range(0.0, 1.0)) = 0.5
        _BlendSmoothness ("混合平滑度", Range(0.0, 1.0)) = 0.1
        _BlendMipLevel ("混合遮罩模糊层级", Range(0.0, 10.0)) = 0.0
        
        
        [Header(Common Settings)]
        _BaseColor ("基础颜色", Color) = (1, 1, 1, 1)
        _Metallic ("金属度", Range(0.0, 1.0)) = 0.0
        _OcclusionStrength ("AO强度", Range(0.0, 1.0)) = 1.0
        
        [HideInInspector] _Surface("__surface", Float) = 0.0
        [HideInInspector] _Blend("__blend", Float) = 0.0
        [HideInInspector] _Cull("__cull", Float) = 2.0
        [HideInInspector] _SrcBlend("__src", Float) = 1.0
        [HideInInspector] _DstBlend("__dst", Float) = 0.0
        [HideInInspector] _ZWrite("__zw", Float) = 1.0
    }
    
    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
            "UniversalMaterialType" = "Lit"
        }
        LOD 300
        
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }
            
            Blend[_SrcBlend][_DstBlend]
            ZWrite[_ZWrite]
            Cull[_Cull]
            
            HLSLPROGRAM
            #pragma target 3.0
            
            #pragma vertex vert
            #pragma fragment frag
            
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION
            #pragma multi_compile _ LIGHTMAP_ON
            #pragma multi_compile_fog
            #pragma multi_compile_instancing
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            
            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _RockAlbedoMap_ST;
                float4 _GrassAlbedoMap_ST;
                float4 _BlendMask_ST;
                float _Metallic;
                float _OcclusionStrength;
                float _RockNormalScale;
                float _RockRoughness;
                float _GrassNormalScale;
                float _GrassRoughness;
                float _BlendThreshold;
                float _BlendSmoothness;
                float _BlendMipLevel;
            CBUFFER_END
            
            TEXTURE2D(_RockAlbedoMap);    SAMPLER(sampler_RockAlbedoMap);
            TEXTURE2D(_RockNormalMap);    SAMPLER(sampler_RockNormalMap);
            TEXTURE2D(_RockAOMap);        SAMPLER(sampler_RockAOMap);
            TEXTURE2D(_RockRoughnessMap); SAMPLER(sampler_RockRoughnessMap);
            
            TEXTURE2D(_GrassAlbedoMap);    SAMPLER(sampler_GrassAlbedoMap);
            TEXTURE2D(_GrassNormalMap);    SAMPLER(sampler_GrassNormalMap);
            TEXTURE2D(_GrassAOMap);        SAMPLER(sampler_GrassAOMap);
            TEXTURE2D(_GrassRoughnessMap); SAMPLER(sampler_GrassRoughnessMap);
            
            TEXTURE2D(_BlendMask); SAMPLER(sampler_BlendMask);
            
            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
                float2 uv : TEXCOORD0;
                float2 staticLightmapUV : TEXCOORD1;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float2 uvRock : TEXCOORD1;
                float2 uvGrass : TEXCOORD2;
                float2 uvBlendMask : TEXCOORD3;
                float3 positionWS : TEXCOORD4;
                float3 normalWS : TEXCOORD5;
                float4 tangentWS : TEXCOORD6;
                float fogFactor : TEXCOORD7;
                DECLARE_LIGHTMAP_OR_SH(staticLightmapUV, vertexSH, 8);
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            
            Varyings vert(Attributes input)
            {
                Varyings output = (Varyings)0;
                
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
                
                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);
                
                output.positionCS = vertexInput.positionCS;
                output.positionWS = vertexInput.positionWS;
                output.normalWS = normalInput.normalWS;
                
                real sign = input.tangentOS.w * GetOddNegativeScale();
                output.tangentWS = float4(normalInput.tangentWS.xyz, sign);
                
                output.fogFactor = ComputeFogFactor(vertexInput.positionCS.z);
                OUTPUT_LIGHTMAP_UV(input.staticLightmapUV, unity_LightmapST, output.staticLightmapUV);
                OUTPUT_SH(output.normalWS.xyz, output.vertexSH);
                
                output.uv = input.uv;
                output.uvRock = TRANSFORM_TEX(input.uv, _RockAlbedoMap);
                output.uvGrass = TRANSFORM_TEX(input.uv, _GrassAlbedoMap);
                output.uvBlendMask = TRANSFORM_TEX(input.uv, _BlendMask);
                
                return output;
            }
            
            float4 frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);
                
                float3 normalWS = normalize(input.normalWS);
                float3 viewDirWS = GetWorldSpaceNormalizeViewDir(input.positionWS);
                
                float maskValue = SAMPLE_TEXTURE2D_LOD(_BlendMask, sampler_BlendMask, input.uvBlendMask, _BlendMipLevel).r;
                float blendFactor = smoothstep(_BlendThreshold - _BlendSmoothness, _BlendThreshold + _BlendSmoothness, maskValue);
                
                float3 rockAlbedo = SAMPLE_TEXTURE2D(_RockAlbedoMap, sampler_RockAlbedoMap, input.uvRock).rgb;
                float3 grassAlbedo = SAMPLE_TEXTURE2D(_GrassAlbedoMap, sampler_GrassAlbedoMap, input.uvGrass).rgb;
                float3 albedo = lerp(rockAlbedo, grassAlbedo, blendFactor) * _BaseColor.rgb;
                
                float3 rockNormalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_RockNormalMap, sampler_RockNormalMap, input.uvRock), _RockNormalScale);
                float3 grassNormalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_GrassNormalMap, sampler_GrassNormalMap, input.uvGrass), _GrassNormalScale);
                float3 normalTS = lerp(rockNormalTS, grassNormalTS, blendFactor);
                
                float rockAO = SAMPLE_TEXTURE2D(_RockAOMap, sampler_RockAOMap, input.uvRock).r;
                float grassAO = SAMPLE_TEXTURE2D(_GrassAOMap, sampler_GrassAOMap, input.uvGrass).r;
                float ao = lerp(rockAO, grassAO, blendFactor);
                
                float rockRoughness = SAMPLE_TEXTURE2D(_RockRoughnessMap, sampler_RockRoughnessMap, input.uvRock).r * _RockRoughness;
                float grassRoughness = SAMPLE_TEXTURE2D(_GrassRoughnessMap, sampler_GrassRoughnessMap, input.uvGrass).r * _GrassRoughness;
                float roughness = lerp(rockRoughness, grassRoughness, blendFactor);
                
                float sgn = input.tangentWS.w;
                float3 tangentWS = normalize(input.tangentWS.xyz);
                float3 bitangentWS = cross(normalWS.xyz, tangentWS.xyz) * sgn;
                float3x3 tangentToWorld = float3x3(tangentWS.xyz, bitangentWS.xyz, normalWS.xyz);
                float3 finalNormal = TransformTangentToWorld(normalTS, tangentToWorld);
                finalNormal = NormalizeNormalPerPixel(finalNormal);
                
                InputData inputData = (InputData)0;
                inputData.positionWS = input.positionWS;
                inputData.normalWS = finalNormal;
                inputData.viewDirectionWS = viewDirWS;
                inputData.shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                inputData.fogCoord = InitializeInputDataFog(float4(input.positionWS, 1.0), input.fogFactor);
                inputData.bakedGI = SAMPLE_GI(input.staticLightmapUV, input.vertexSH, inputData.normalWS);
                inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(input.positionCS);
                inputData.shadowMask = SAMPLE_SHADOWMASK(input.staticLightmapUV);
                
                SurfaceData surfaceData = (SurfaceData)0;
                surfaceData.albedo = albedo;
                surfaceData.metallic = _Metallic;
                surfaceData.smoothness = 1.0 - saturate(roughness);
                surfaceData.occlusion = lerp(1.0, ao, _OcclusionStrength);
                surfaceData.normalTS = normalTS;
                surfaceData.alpha = 1.0;
                
                float4 color = UniversalFragmentPBR(inputData, surfaceData);
                color.rgb = MixFog(color.rgb, inputData.fogCoord);
                
                return color;
            }
            ENDHLSL
        }
        
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }
            
            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull[_Cull]
            
            HLSLPROGRAM
            #pragma target 2.0
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment
            
            #pragma multi_compile_instancing
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            
            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            
            Varyings ShadowPassVertex(Attributes input)
            {
                Varyings output;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
                
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);
                
                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, _MainLightPosition.xyz));
                
                output.positionCS = positionCS;
                return output;
            }
            
            half4 ShadowPassFragment(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);
                return 0;
            }
            ENDHLSL
        }
        
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }
            
            ZWrite On
            ColorMask R
            Cull[_Cull]
            
            HLSLPROGRAM
            #pragma target 2.0
            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment
            
            #pragma multi_compile_instancing
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            
            struct Attributes
            {
                float4 positionOS : POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            
            Varyings DepthOnlyVertex(Attributes input)
            {
                Varyings output;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                return output;
            }
            
            half4 DepthOnlyFragment(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);
                return input.positionCS.z;
            }
            ENDHLSL
        }
        
        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode" = "DepthNormals" }
            
            ZWrite On
            Cull[_Cull]
            
            HLSLPROGRAM
            #pragma target 2.0
            #pragma vertex DepthNormalsVertex
            #pragma fragment DepthNormalsFragment
            
            #pragma multi_compile_instancing
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            
            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 normalWS : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            
            Varyings DepthNormalsVertex(Attributes input)
            {
                Varyings output;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
                
                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);
                
                output.positionCS = vertexInput.positionCS;
                output.normalWS = normalInput.normalWS;
                
                return output;
            }
            
            float4 DepthNormalsFragment(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);
                
                float3 normalWS = normalize(input.normalWS);
                
                return float4(normalWS * 0.5 + 0.5, 1.0);
            }
            ENDHLSL
        }
    }
    
    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}
