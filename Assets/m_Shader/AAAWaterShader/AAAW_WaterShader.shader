Shader "AAAWater/WaterSurface"
{
    Properties
    {
        [Header(Base Settings)]
        _BaseColor ("Base Color", Color) = (0.1, 0.3, 0.5, 1.0)
        _ScatterColor ("Scatter Color", Color) = (0.2, 0.5, 0.8, 1.0)
        _AbsorptionColor ("Absorption Color", Color) = (0.1, 0.2, 0.3, 1.0)
        
        [Header(Physical Parameters)]
        _Fresnel0 ("Fresnel F0", Range(0.0, 0.1)) = 0.02
        _PhaseG ("Phase G", Range(-1.0, 1.0)) = 0.8
        _Thickness ("Thickness", Range(0.0, 1.0)) = 0.5
        _DepthScale ("Depth Scale", Range(0.1, 100.0)) = 10.0
        
        [Header(Wave Settings)]
        _NormalScale ("Normal Scale", Range(0.0, 2.0)) = 1.0
        _WaveSpeed ("Wave Speed", Range(0.0, 5.0)) = 1.0
        _WaveHeight ("Wave Height", Range(0.0, 5.0)) = 0.5
        _WaveFrequency ("Wave Frequency", Range(0.0, 10.0)) = 1.0
        _WaveDirection1 ("Wave Direction 1", Vector) = (1.0, 0.0, 0.0, 0.0)
        _WaveDirection2 ("Wave Direction 2", Vector) = (0.0, 1.0, 0.0, 0.0)
        
        //[Header(Refraction & Reflection)]
        _RefractionStrength ("Refraction Strength", Range(0.0, 1.0)) = 0.1
        _SpecularStrength ("Specular Strength", Range(0.0, 2.0)) = 1.0
        _Smoothness ("Smoothness", Range(0.0, 1.0)) = 0.9
        _EnvReflectionStrength ("Environment Reflection Strength", Range(0.0, 2.0)) = 1.0
        
        [Header(Foam Settings)]
        _FoamThreshold ("Foam Threshold", Range(0.0, 10.0)) = 1.0
        _FoamSmoothness ("Foam Smoothness", Range(0.0, 1.0)) = 0.5
        _FoamDistance ("Foam Distance", Range(0.0, 5.0)) = 0.5
        _FoamIntensity ("Foam Intensity", Range(0.0, 2.0)) = 1.0
        
        [Header(Textures)]
        _WaterNormalMap ("Water Normal Map", 2D) = "bump" {}
        _WaterNormalMap2 ("Water Normal Map 2", 2D) = "bump" {}
        _FoamTexture ("Foam Texture", 2D) = "white" {}
        
        [Header(Advanced)]
        [Toggle(_USE_RAY_MARCHING)] _UseRayMarching ("Use Ray Marching", Float) = 1
        _RayMarchSteps ("Ray March Steps", Range(1, 16)) = 6
    }
    
    SubShader
    {
        Tags 
        { 
            "RenderType" = "Transparent" 
            "Queue" = "Transparent-100"
            "RenderPipeline" = "UniversalPipeline"
        }
        
        Blend SrcAlpha OneMinusSrcAlpha
        ZWrite Off
        ZTest LEqual
        Cull Back
        
        Pass
        {
            Name "AAAWaterForward"
            Tags { "LightMode" = "UniversalForward" }
            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile _ _REFLECTION_PROBE_BLENDING
            #pragma multi_compile _ _REFLECTION_PROBE_BOX_PROJECTION
            #pragma multi_compile_instancing
            #pragma shader_feature _USE_RAY_MARCHING
            
            #include "AAAW_WaterCommon.hlsl"
            #include "AAAW_WaterFresnel.hlsl"
            #include "AAAW_WaterPhase.hlsl"
            #include "AAAW_WaterBSDF.hlsl"
            #include "AAAW_WaterRayMarching.hlsl"
            
            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float3 tangentWS : TEXCOORD2;
                float3 bitangentWS : TEXCOORD3;
                float2 uv : TEXCOORD4;
                float4 screenPos : TEXCOORD5;
                float4 shadowCoord : TEXCOORD6;
                float3 viewDirWS : TEXCOORD7;
                float fogFactor : TEXCOORD8;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            
            Varyings vert(Attributes input)
            {
                Varyings output;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
                
                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);
                
                output.positionCS = vertexInput.positionCS;
                output.positionWS = vertexInput.positionWS;
                output.normalWS = normalInput.normalWS;
                output.tangentWS = normalInput.tangentWS;
                output.bitangentWS = normalInput.bitangentWS;
                
                output.uv = input.uv;
                output.screenPos = ComputeScreenPos(vertexInput.positionCS);
                
                output.viewDirWS = GetWorldSpaceViewDir(vertexInput.positionWS);
                
                output.shadowCoord = TransformWorldToShadowCoord(vertexInput.positionWS);
                
                output.fogFactor = ComputeFogFactor(vertexInput.positionCS.z);
                
                return output;
            }
            
            float3 AAAWCalculateSpecularReflection(float3 normalWS, float3 viewDirWS, float3 lightDirWS, float3 lightColor, float smoothness, float specularStrength)
            {
                float3 halfDir = normalize(lightDirWS + viewDirWS);
                float NdotH = saturate(dot(normalWS, halfDir));
                
                float roughness = 1.0 - smoothness;
                float roughness2 = roughness * roughness;
                
                float denom = NdotH * NdotH * (roughness2 - 1.0) + 1.0;
                float D = roughness2 / (AAAW_PI * denom * denom);
                
                float NdotV = saturate(dot(normalWS, viewDirWS));
                float NdotL = saturate(dot(normalWS, lightDirWS));
                float G = 0.25 / (NdotV * NdotL + 0.0001);
                
                float3 F = AAAWFresnelSchlick3(float3(0.04, 0.04, 0.04), saturate(dot(halfDir, viewDirWS)));
                
                float3 specular = D * G * F * specularStrength * lightColor;
                return specular * 0.25;
            }
            
            float3 AAAWCalculateEnvironmentReflection(float3 normalWS, float3 viewDirWS, float smoothness, float envStrength, float fresnel0)
            {
                float3 reflectDir = reflect(-viewDirWS, normalWS);
                
                float perceptualRoughness = 1.0 - smoothness;
                float roughness = perceptualRoughness * perceptualRoughness;
                
                float3 envColor = GlossyEnvironmentReflection(reflectDir, roughness, 1.0);
                
                float fresnel = AAAWFresnelSchlick(fresnel0, saturate(dot(normalWS, viewDirWS)));
                
                return envColor * envStrength * fresnel;
            }
            
            float4 frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);
                
                float3 normalWS = normalize(input.normalWS);
                float3 viewDirWS = normalize(input.viewDirWS);
                
                float time = _Time.y;
                float3 animatedNormal = AAAWGetWaterNormal(input.uv, time);
                
                float3x3 tangentToWorld = float3x3(
                    normalize(input.tangentWS),
                    normalize(input.bitangentWS),
                    normalWS
                );
                normalWS = normalize(mul(animatedNormal, tangentToWorld));
                
                float2 screenUV = input.screenPos.xy / input.screenPos.w;
                
                float sceneDepth = AAAWGetLinearEyeDepth(screenUV);
                float waterDepth = abs(sceneDepth - LinearEyeDepth(input.positionCS.z, _ZBufferParams));
                waterDepth = max(0.01, waterDepth);
                
                float thickness = saturate(waterDepth / _DepthScale);
                
                Light mainLight = GetMainLight(input.shadowCoord);
                float3 lightDirWS = mainLight.direction;
                float3 lightColor = mainLight.color;
                float shadowValue = mainLight.shadowAttenuation;
                
                float3 scatterColor = _ScatterColor.rgb;
                float3 absorptionColor = _AbsorptionColor.rgb;
                
                float3 waterScatter;
                
                #ifdef _USE_RAY_MARCHING
                    AAAWRayMarchConfig rmConfig = AAAWCreateDefaultRayMarchConfig();
                    rmConfig.stepCount = (int)_RayMarchSteps;
                    rmConfig.maxDistance = waterDepth;
                    
                    float3 extinctionCoeff = scatterColor + absorptionColor;
                    float3 scatterAlbedo = AAAWGetScatteringAlbedo3(scatterColor, extinctionCoeff);
                    
                    float3 rayOrigin = input.positionWS;
                    float3 rayDir = -viewDirWS;
                    rayDir.y = -abs(rayDir.y);
                    rayDir = normalize(rayDir);
                    
                    waterScatter = AAAWRayMarchVolumeScattering(
                        rayOrigin, rayDir, waterDepth,
                        extinctionCoeff, scatterAlbedo,
                        lightDirWS, viewDirWS, lightColor,
                        _PhaseG, 1.0 - shadowValue, rmConfig
                    );
                    
                    float T_exit = AAAWFresnelExit(_Fresnel0, normalWS, viewDirWS);
                    waterScatter *= T_exit;
                #else
                    waterScatter = AAAWEvaluateWaterScattering(
                        normalWS, viewDirWS, lightDirWS, lightColor,
                        scatterColor, absorptionColor,
                        thickness, _Fresnel0, _PhaseG,
                        1.0 - shadowValue
                    );
                #endif
                
                float3 specular = AAAWCalculateSpecularReflection(
                    normalWS, viewDirWS, lightDirWS, lightColor,
                    _Smoothness, _SpecularStrength
                );
                
                float3 envReflection = AAAWCalculateEnvironmentReflection(
                    normalWS, viewDirWS, _Smoothness, _EnvReflectionStrength, _Fresnel0
                );
                
                float2 refractionOffset = normalWS.xz * _RefractionStrength * saturate(waterDepth / 5.0);
                float2 refractedUV = screenUV + refractionOffset / _ScreenParams.xy;
                float3 refractionColor = SAMPLE_TEXTURE2D(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, refractedUV).rgb;
                
                float3 absorptionFactor = exp(-absorptionColor * waterDepth);
                refractionColor *= absorptionFactor;
                
                float foamFactor = AAAWComputeFoam(waterDepth, _WaveHeight, _FoamThreshold, _FoamSmoothness);
                foamFactor = saturate(foamFactor);
                
                float fresnel = AAAWEvaluateFresnelWaterScalar(normalWS, viewDirWS, _Fresnel0);
                
                float3 waterColor = lerp(refractionColor, envReflection, fresnel);
                waterColor += waterScatter;
                waterColor += specular;
                
                float3 foamColor = float3(1.0, 1.0, 1.0);
                waterColor = AAAWApplyFoam(waterColor, foamFactor, foamColor, _FoamIntensity);
                
                waterColor = MixFog(waterColor, input.fogFactor);
                
                float alpha = lerp(0.8, 1.0, fresnel);
                alpha = lerp(alpha, 1.0, foamFactor);
                
                return float4(waterColor, alpha);
            }
            ENDHLSL
        }
        /*
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }
            
            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Back
            
            HLSLPROGRAM
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment
            
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
            };
            
            float3 _LightDirection;
            
            Varyings ShadowPassVertex(Attributes input)
            {
                Varyings output;
                UNITY_SETUP_INSTANCE_ID(input);
                
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);
                
                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, _LightDirection));
                
                #if UNITY_REVERSED_Z
                    positionCS.z = min(positionCS.z, positionCS.w * UNITY_NEAR_CLIP_VALUE);
                #else
                    positionCS.z = max(positionCS.z, positionCS.w * UNITY_NEAR_CLIP_VALUE);
                #endif
                
                output.positionCS = positionCS;
                return output;
            }
            
            half4 ShadowPassFragment(Varyings input) : SV_Target
            {
                return 0;
            }
            ENDHLSL
        }
        
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }
            
            ZWrite On
            ColorMask 0
            Cull Back
            
            HLSLPROGRAM
            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment
            
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
                return 0;
            }
            ENDHLSL
        }
    }
    */
    
       }   //FallBack "Hidden/Universal Render Pipeline/FallbackError"
}
