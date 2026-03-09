Shader "Hidden/FluidFlux/CausticsEffect"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _CausticsTexture ("Caustics Texture", 2D) = "white" {}
    }

    HLSLINCLUDE
    #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
    #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

    TEXTURE2D(_CausticsTexture);
    SAMPLER(sampler_CausticsTexture);

    TEXTURE2D(_CausticsOpaqueTexture);
    SAMPLER(sampler_CausticsOpaqueTexture);

    float _WaterSurfaceHeight;
    float _MaxCausticsDepth;
    float _CausticsIntensity;
    float _CausticsScale;
    float _CausticsSpeed;
    float _CausticsBlur;
    float3 _CausticsLightDirection;
    float4 _CausticsColor;
    float _CausticsTime;

    float4 _CausticsOpaqueTexture_TexelSize;

    float3 GetWorldPositionFromDepth(float2 uv, float depth)
    {
        float4 positionNDC = float4(uv * 2.0 - 1.0, depth, 1.0);
        #if UNITY_UV_STARTS_AT_TOP
            positionNDC.y = -positionNDC.y;
        #endif
        
        float4 positionVS = mul(UNITY_MATRIX_I_P, positionNDC);
        positionVS /= positionVS.w;
        float4 positionWS = mul(UNITY_MATRIX_I_V, positionVS);
        return positionWS.xyz;
    }

    float2 GetCausticsUV(float3 worldPos, float3 lightDir)
    {
        float3 refractedDir = refract(-lightDir, float3(0, 1, 0), 1.0 / 1.33);
        
        float waterDepth = _WaterSurfaceHeight - worldPos.y;
        float horizontalDist = waterDepth * abs(refractedDir.x / max(abs(refractedDir.y), 0.001));
        float horizontalDistZ = waterDepth * abs(refractedDir.z / max(abs(refractedDir.y), 0.001));
        
        float2 causticsUV = worldPos.xz / _CausticsScale;
        causticsUV.x += horizontalDist * sign(refractedDir.x);
        causticsUV.y += horizontalDistZ * sign(refractedDir.z);
        
        return causticsUV;
    }

    float SampleCaustics(float2 uv, float time)
    {
        float2 uv1 = uv + float2(time * 0.1, time * 0.05);
        float2 uv2 = uv * 0.8 + float2(-time * 0.08, time * 0.12);
        float2 uv3 = uv * 1.2 + float2(time * 0.07, -time * 0.09);

        float c1 = SAMPLE_TEXTURE2D(_CausticsTexture, sampler_CausticsTexture, uv1).r;
        float c2 = SAMPLE_TEXTURE2D(_CausticsTexture, sampler_CausticsTexture, uv2).g;
        float c3 = SAMPLE_TEXTURE2D(_CausticsTexture, sampler_CausticsTexture, uv3).b;

        return (c1 + c2 + c3) / 3.0;
    }

    float SampleCausticsBlurred(float2 uv, float time, float blur)
    {
        float total = 0;
        float weights = 0;
        float2 texelSize = 1.0 / float2(_CausticsScale, _CausticsScale) * blur;

        for (int x = -2; x <= 2; x++)
        {
            for (int y = -2; y <= 2; y++)
            {
                float weight = 1.0 / (1.0 + length(float2(x, y)));
                float2 offsetUV = uv + float2(x, y) * texelSize;
                total += SampleCaustics(offsetUV, time) * weight;
                weights += weight;
            }
        }

        return total / weights;
    }

    float3 SampleOpaqueBlurred(float2 uv, float blur)
    {
        if (blur < 0.01)
        {
            return SAMPLE_TEXTURE2D(_CausticsOpaqueTexture, sampler_CausticsOpaqueTexture, uv).rgb;
        }

        float mipLevel = blur * 4.0;
        return SAMPLE_TEXTURE2D_LOD(_CausticsOpaqueTexture, sampler_CausticsOpaqueTexture, uv, mipLevel).rgb;
    }

    float4 CausticsFragment(Varyings input) : SV_Target
    {
        float2 uv = input.texcoord;

        float depth = SampleSceneDepth(uv);
        float linearDepth = LinearEyeDepth(depth, _ZBufferParams);

        float3 worldPos = GetWorldPositionFromDepth(uv, depth);

        bool isUnderwater = worldPos.y < _WaterSurfaceHeight;
        
        if (!isUnderwater)
        {
            return SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv);
        }

        float waterDepth = _WaterSurfaceHeight - worldPos.y;

        float depthFade = 1.0 - saturate(waterDepth / _MaxCausticsDepth);
        if (depthFade <= 0.001)
        {
            return SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv);
        }

        float time = _CausticsTime * _CausticsSpeed;

        float2 causticsUV = GetCausticsUV(worldPos, _CausticsLightDirection);

        float caustics = SampleCausticsBlurred(causticsUV, time, _CausticsBlur);
        caustics = pow(caustics, 2.0);

        float3 causticsColor = _CausticsColor.rgb * caustics * _CausticsIntensity;

        float distanceBlur = saturate(waterDepth / (_MaxCausticsDepth * 0.5));
        float3 opaqueBlurred = SampleOpaqueBlurred(uv, distanceBlur * _CausticsBlur);

        float3 baseColor = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv).rgb;
        float3 scatteredColor = lerp(baseColor, opaqueBlurred, distanceBlur * 0.5);

        float3 finalColor = scatteredColor + causticsColor * depthFade;

        return float4(finalColor, 1.0);
    }

    float4 DebugCausticsFragment(Varyings input) : SV_Target
    {
        float2 uv = input.texcoord;

        float depth = SampleSceneDepth(uv);
        float3 worldPos = GetWorldPositionFromDepth(uv, depth);

        bool isUnderwater = worldPos.y < _WaterSurfaceHeight;

        float time = _CausticsTime * _CausticsSpeed;
        float2 causticsUV = GetCausticsUV(worldPos, _CausticsLightDirection);
        float caustics = SampleCaustics(causticsUV, time);

        float3 debugColor = caustics * _CausticsColor.rgb * _CausticsIntensity;

        if (!isUnderwater)
        {
            debugColor = float3(0.2, 0.2, 0.2);
        }

        return float4(debugColor, 1.0);
    }

    float4 DebugDepthFragment(Varyings input) : SV_Target
    {
        float2 uv = input.texcoord;

        float depth = SampleSceneDepth(uv);
        float3 worldPos = GetWorldPositionFromDepth(uv, depth);

        float waterDepth = max(0, _WaterSurfaceHeight - worldPos.y);
        float depthFade = 1.0 - saturate(waterDepth / _MaxCausticsDepth);

        return float4(depthFade.xxx, 1.0);
    }

    ENDHLSL

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        LOD 100
        ZWrite Off ZTest Always

        Pass
        {
            Name "CausticsEffect"
            
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment CausticsFragment
            ENDHLSL
        }

        Pass
        {
            Name "DebugCaustics"
            
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment DebugCausticsFragment
            ENDHLSL
        }

        Pass
        {
            Name "DebugDepth"
            
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment DebugDepthFragment
            ENDHLSL
        }
    }
}
