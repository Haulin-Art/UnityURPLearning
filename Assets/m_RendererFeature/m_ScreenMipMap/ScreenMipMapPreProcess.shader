Shader "Hidden/ScreenMipMap/PreProcess"
{
    Properties
    {
        //_MainTex ("Main Tex", 2D) = "white" {}
        _Brightness ("Brightness", Range(0, 2)) = 1.0
        _Contrast ("Contrast", Range(0, 2)) = 1.0
        _Saturation ("Saturation", Range(0, 2)) = 1.0

        _SurfSpeed ("表面速度", Range(0, 1)) = 0.5
        _CautionTex ("焦散纹理", 3D) = "white" {}
        _CautionPow ("焦散强度", Range(0, 10)) = 4.0
    }
    
    HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
        
        TEXTURE2D(_MainTex);
        SAMPLER(sampler_MainTex);
        float _SurfSpeed;

        float _Brightness;
        float _Contrast;
        float _Saturation;
        float _CautionPow;
        
        TEXTURE3D(_CautionTex);
        SAMPLER(sampler_CautionTex);
        
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
        
        Varyings Vert(Attributes input)
        {
            Varyings output;
            output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
            output.uv = input.uv;
            return output;
        }
        
        float3 ApplyBrightnessContrastSaturation(float3 color, float brightness, float contrast, float saturation)
        {
            color *= brightness;
            color = (color - 0.5) * contrast + 0.5;
            float luminance = dot(color, float3(0.2126, 0.7152, 0.0722));
            color = lerp(luminance, color, saturation);
            return color;
        }
        
        float3 ReconstructWorldPosition(float2 uv)
        {
            float depth = SampleSceneDepth(uv);
            
            float4 ndc = float4(uv * 2.0 - 1.0, depth, 1.0);
            
            #if UNITY_UV_STARTS_AT_TOP
                ndc.y = -ndc.y;
            #endif
            
            float4 positionWS = mul(UNITY_MATRIX_I_VP, ndc);
            positionWS.xyz /= positionWS.w;
            
            return positionWS.xyz;
        }
        
        float3x3 CreateLightSpaceMatrix(float3 lightDir)
        {
            float3 up = abs(lightDir.y) < 0.999 ? float3(0, 1, 0) : float3(1, 0, 0);
            float3 right = normalize(cross(up, lightDir));
            float3 forward = normalize(cross(lightDir, right));
            return float3x3(right, forward, lightDir);
        }
        
        float3 WorldToLightSpace(float3 worldPos, float3 lightDir)
        {
            float3x3 lightMatrix = CreateLightSpaceMatrix(lightDir);
            float3 lightSpacePos = mul(lightMatrix, worldPos);
            return lightSpacePos;
        }
        
        float4 FragPreProcess(Varyings input) : SV_Target
        {
            float4 color = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv);
            color.rgb = ApplyBrightnessContrastSaturation(color.rgb, _Brightness, _Contrast, _Saturation);
            
            // ================================== 自定义部分 ==================================
            Light ld = GetMainLight();
            float3 lightDir = normalize(ld.direction);
            float3 lightColor = ld.color;

            // 通过深度还原世界位置
            float depth = SampleSceneDepth(input.uv);
            float linerDep = LinearEyeDepth(depth, _ZBufferParams);
            float3 worldPos = ReconstructWorldPosition(input.uv);
            
            // ================================= 阴影检测 ==================================
            float4 shadowCoord = TransformWorldToShadowCoord(worldPos);
            float notInShadow = 1.0;
            #if defined(_MAIN_LIGHT_SHADOWS) || defined(_MAIN_LIGHT_SHADOWS_CASCADE) || defined(_MAIN_LIGHT_SHADOWS_SCREEN)
                ShadowSamplingData shadowSamplingData = GetMainLightShadowSamplingData();
                float shadowStrength = GetMainLightShadowStrength();
                float shadowMask = SampleShadowmap(shadowCoord, TEXTURE2D_ARGS(_MainLightShadowmapTexture, sampler_MainLightShadowmapTexture), shadowSamplingData, shadowStrength, false);
                notInShadow = shadowMask;
            #else
                return float4(1, 0, 0, 1);
            #endif
            
            // ================================= 灯光空间转换 ==================================
            float3 lightSpacePos = WorldToLightSpace(worldPos, lightDir);
            //return float4(lightSpacePos, 1);
            // ================================= 焦散 ==================================
            float mask = smoothstep(30.0, 15.0, linerDep);
            
            // 使用灯光空间的XY坐标（垂直于光源方向的平面）
            float2 lightUV = frac(lightSpacePos.xy / 2.0) * mask;
            
            float2 cautionTex = SAMPLE_TEXTURE3D(_CautionTex, sampler_CautionTex, float3(lightUV, frac(_Time.y * _SurfSpeed))).rg;
            float caution = pow((cautionTex.x + cautionTex.y * 1.0) / 1.8, _CautionPow) * 1.0;
            
            float2 cautionTexR = SAMPLE_TEXTURE3D(_CautionTex, sampler_CautionTex, float3(lightUV+float2(caution*0.02, 0.0), frac(_Time.y * _SurfSpeed))).rg;
            float cautionR = pow((cautionTexR.x + cautionTexR.y * 1.0) / 1.8, _CautionPow) * 1.0;
            
            float2 cautionTexU = SAMPLE_TEXTURE3D(_CautionTex, sampler_CautionTex, float3(lightUV-float2(caution*0.02,0.0), frac(_Time.y * _SurfSpeed))).rg;
            float cautionU = pow((cautionTexU.x + cautionTexU.y * 1.0) / 1.8, _CautionPow) * 1.0;

            float3 cautionTotal = float3(cautionR, cautionU, caution) * mask * notInShadow;
            caution *= mask;
            caution *= notInShadow;

            return float4(color.xyz + cautionTotal * float3(1, 1, 1), 1);
        }
        
        float4 FragCopy(Varyings input) : SV_Target
        {
            return SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv);
        }
        
    ENDHLSL
    
    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        LOD 100
        ZTest Always ZWrite Off Cull Off
        
        Pass
        {
            Name "PreProcess"
            
            HLSLPROGRAM
                #pragma vertex Vert
                #pragma fragment FragPreProcess
                #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            ENDHLSL
        }
        
        Pass
        {
            Name "Copy"
            
            HLSLPROGRAM
                #pragma vertex Vert
                #pragma fragment FragCopy
            ENDHLSL
        }
    }
}
