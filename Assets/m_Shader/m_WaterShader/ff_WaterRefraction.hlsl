#ifndef FF_WATER_REFRACTION_INCLUDED
#define FF_WATER_REFRACTION_INCLUDED

#include "ff_WaterCommon.hlsl"

float2 FFGetRefractionOffset(float3 normalWS, float3 viewDirWS, float strength)
{
    float2 offset = normalWS.xz * strength;
    return offset;
}

float3 FFSampleRefractionColor(float2 screenUV, float2 offset, TEXTURE2D_PARAM(tex, samplerTex))
{
    float2 refractedUV = screenUV + offset;
    refractedUV = saturate(refractedUV);
    return SAMPLE_TEXTURE2D(tex, samplerTex, refractedUV).rgb;
}

float3 FFSampleRefractionColorWithDepthFade(
    float2 screenUV, 
    float2 offset, 
    float waterDepth,
    float3 absorptionColor,
    TEXTURE2D_PARAM(tex, samplerTex))
{
    float2 refractedUV = screenUV + offset;
    refractedUV = saturate(refractedUV);
    
    float3 refractionColor = SAMPLE_TEXTURE2D(tex, samplerTex, refractedUV).rgb;
    
    float3 depthFade = exp(-absorptionColor * waterDepth);
    refractionColor *= depthFade;
    
    return refractionColor;
}

float FFGetRefractionStrength(float waterDepth, float maxDepth, float baseStrength)
{
    float depthFactor = saturate(waterDepth / maxDepth);
    return baseStrength * (1.0 - depthFactor * 0.5);
}

float3 FFApplyRefraction(
    float3 baseColor,
    float2 screenUV,
    float3 normalWS,
    float3 viewDirWS,
    float waterDepth,
    float refractionStrength,
    float3 absorptionColor,
    TEXTURE2D_PARAM(tex, samplerTex))
{
    float2 offset = FFGetRefractionOffset(normalWS, viewDirWS, refractionStrength);
    float3 refractionColor = FFSampleRefractionColorWithDepthFade(screenUV, offset, waterDepth, absorptionColor, TEXTURE2D_ARGS(tex, samplerTex));
    return refractionColor;
}

float3 FFBeerLambertAbsorption(float3 absorptionColor, float distance)
{
    return exp(-absorptionColor * distance);
}

float3 FFApplyWaterAbsorption(float3 color, float waterDepth, float3 absorptionColor)
{
    float3 absorption = FFBeerLambertAbsorption(absorptionColor, waterDepth);
    return color * absorption;
}

#endif
