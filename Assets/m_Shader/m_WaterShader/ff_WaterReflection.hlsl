#ifndef FF_WATER_REFLECTION_INCLUDED
#define FF_WATER_REFLECTION_INCLUDED

#include "ff_WaterCommon.hlsl"

float3 FFGetReflectionDir(float3 normalWS, float3 viewDirWS)
{
    return reflect(-viewDirWS, normalWS);
}

float3 FFSampleEnvReflection(float3 reflectDir, float roughness, float envStrength)
{
    float perceptualRoughness = roughness;
    float3 envColor = GlossyEnvironmentReflection(reflectDir, perceptualRoughness, 1.0);
    return envColor * envStrength;
}

float3 FFBlendReflection(
    float3 baseColor,
    float3 reflectionColor,
    float fresnel,
    float reflectionStrength)
{
    return lerp(baseColor, reflectionColor, fresnel * reflectionStrength);
}

float3 FFApplyReflectionWithFresnel(
    float3 baseColor,
    float3 normalWS,
    float3 viewDirWS,
    float fresnel,
    float roughness,
    float envStrength)
{
    float3 reflectDir = FFGetReflectionDir(normalWS, viewDirWS);
    float3 reflectionColor = FFSampleEnvReflection(reflectDir, roughness, envStrength);
    return FFBlendReflection(baseColor, reflectionColor, fresnel, 1.0);
}

#endif
