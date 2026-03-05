#ifndef FF_WATER_FRESNEL_INCLUDED
#define FF_WATER_FRESNEL_INCLUDED

#include "ff_WaterCommon.hlsl"

float FFFresnelSchlick(float f0, float cosTheta)
{
    float t = 1.0 - cosTheta;
    float t2 = t * t;
    float t5 = t2 * t2 * t;
    return f0 + (1.0 - f0) * t5;
}

float3 FFFresnelSchlick3(float3 f0, float cosTheta)
{
    float t = 1.0 - cosTheta;
    float t2 = t * t;
    float t5 = t2 * t2 * t;
    return f0 + (1.0 - f0) * t5;
}

float FFFresnelSchlickRoughness(float f0, float cosTheta, float roughness)
{
    float t = 1.0 - cosTheta;
    float t2 = t * t;
    float t5 = t2 * t2 * t;
    float oneMinusRoughness = 1.0 - roughness;
    return f0 + (max(oneMinusRoughness, f0) - f0) * t5;
}

float FFFresnelWater(float3 normalWS, float3 viewDirWS, float f0)
{
    float NdotV = saturate(dot(normalWS, viewDirWS));
    return FFFresnelSchlick(f0, NdotV);
}

float FFFresnelWaterFull(float n1, float n2, float3 normalWS, float3 viewDirWS)
{
    float NdotV = dot(normalWS, viewDirWS);
    float cosThetaI = abs(NdotV);
    float sinThetaT2 = (n1 / n2) * (n1 / n2) * (1.0 - cosThetaI * cosThetaI);
    
    if (sinThetaT2 > 1.0)
        return 1.0;
    
    float cosThetaT = sqrt(1.0 - sinThetaT2);
    float r_s = FFSquare((n1 * cosThetaI - n2 * cosThetaT) / (n1 * cosThetaI + n2 * cosThetaT));
    float r_p = FFSquare((n2 * cosThetaI - n1 * cosThetaT) / (n2 * cosThetaI + n1 * cosThetaT));
    
    return (r_s + r_p) * 0.5;
}

float FFFresnelTransmission(float f0, float cosTheta)
{
    return 1.0 - FFFresnelSchlick(f0, cosTheta);
}

float FFFresnelExit(float f0, float3 normalWS, float3 viewDirWS)
{
    float NdotV = saturate(dot(normalWS, viewDirWS));
    return FFFresnelTransmission(f0, NdotV);
}

float FFFresnelEntry(float f0, float3 normalWS, float3 lightDirWS)
{
    float NdotL = saturate(dot(normalWS, lightDirWS));
    return FFFresnelTransmission(f0, NdotL);
}

float FFIorToF0(float ior)
{
    float temp = (ior - 1.0) / (ior + 1.0);
    return temp * temp;
}

float FFF0ToIor(float f0)
{
    float sqrtF0 = sqrt(f0);
    return (1.0 + sqrtF0) / (1.0 - sqrtF0);
}

#endif
