#ifndef AAAW_WATER_FRESNEL_INCLUDED
#define AAAW_WATER_FRESNEL_INCLUDED

#include "AAAW_WaterCommon.hlsl"

float FresnelSchlick(float f0, float cosTheta)
{
    float t = 1.0 - cosTheta;
    float t2 = t * t;
    float t5 = t2 * t2 * t;
    return f0 + (1.0 - f0) * t5;
}

float FresnelSchlickRoughness(float f0, float cosTheta, float roughness)
{
    float t = 1.0 - cosTheta;
    float t2 = t * t;
    float t5 = t2 * t2 * t;
    float oneMinusRoughness = 1.0 - roughness;
    return f0 + (max(oneMinusRoughness, f0) - f0) * t5;
}

float FresnelUnreal(float f0, float cosTheta)
{
    float t = saturate(1.0 - cosTheta);
    float t2 = t * t;
    float t5 = t2 * t2 * t;
    return saturate(50.0 * f0 * t5 + f0 + (1.0 - f0) * t5);
}

float3 FresnelSchlick(float3 f0, float cosTheta)
{
    float t = 1.0 - cosTheta;
    float t2 = t * t;
    float t5 = t2 * t2 * t;
    return f0 + (1.0 - f0) * t5;
}

float3 FresnelSchlickRoughness(float3 f0, float cosTheta, float roughness)
{
    float t = 1.0 - cosTheta;
    float t2 = t * t;
    float t5 = t2 * t2 * t;
    float oneMinusRoughness = 1.0 - roughness;
    return f0 + (max(oneMinusRoughness.xxx, f0) - f0) * t5;
}

float FresnelFull(float n1, float n2, float cosThetaI)
{
    float sinThetaI = sqrt(1.0 - cosThetaI * cosThetaI);
    float sinThetaT = n1 / n2 * sinThetaI;
    
    if (sinThetaT >= 1.0)
        return 1.0;
    
    float cosThetaT = sqrt(1.0 - sinThetaT * sinThetaT);
    
    float rs = (n1 * cosThetaI - n2 * cosThetaT) / (n1 * cosThetaI + n2 * cosThetaT);
    float rp = (n2 * cosThetaI - n1 * cosThetaT) / (n2 * cosThetaI + n1 * cosThetaT);
    
    return (rs * rs + rp * rp) * 0.5;
}

float FresnelTransmission(float f0, float cosTheta)
{
    float fresnelReflect = FresnelSchlick(f0, cosTheta);
    return 1.0 - fresnelReflect;
}

float3 FresnelTransmission(float3 f0, float cosTheta)
{
    float3 fresnelReflect = FresnelSchlick(f0, cosTheta);
    return 1.0 - fresnelReflect;
}

float FresnelEntry(float f0, float3 normalWS, float3 lightDirWS)
{
    float NdotL = saturate(dot(normalWS, lightDirWS));
    return FresnelTransmission(f0, NdotL);
}

float FresnelExit(float f0, float3 normalWS, float3 viewDirWS)
{
    float NdotV = saturate(dot(normalWS, viewDirWS));
    return FresnelTransmission(f0, NdotV);
}

float FresnelEntryFull(float n1, float n2, float3 normalWS, float3 lightDirWS)
{
    float cosThetaI = saturate(dot(normalWS, lightDirWS));
    return 1.0 - FresnelFull(n1, n2, cosThetaI);
}

float FresnelExitFull(float n1, float n2, float3 normalWS, float3 viewDirWS)
{
    float cosThetaI = saturate(dot(normalWS, viewDirWS));
    return 1.0 - FresnelFull(n1, n2, cosThetaI);
}

float FresnelDielectric(float eta, float cosThetaI)
{
    float cosThetaI_abs = abs(cosThetaI);
    float sinThetaT2 = eta * eta * (1.0 - cosThetaI_abs * cosThetaI_abs);
    
    if (sinThetaT2 > 1.0)
        return 1.0;
    
    float cosThetaT = sqrt(1.0 - sinThetaT2);
    float r_orth = (eta * cosThetaI_abs - cosThetaT) / (eta * cosThetaI_abs + cosThetaT);
    float r_para = (cosThetaI_abs - eta * cosThetaT) / (cosThetaI_abs + eta * cosThetaT);
    
    return (r_orth * r_orth + r_para * r_para) * 0.5;
}

float3 EvaluateFresnelWater(float3 normalWS, float3 viewDirWS, float f0)
{
    float NdotV = saturate(dot(normalWS, viewDirWS));
    return FresnelSchlick(f0, NdotV);
}

float EvaluateFresnelWaterScalar(float3 normalWS, float3 viewDirWS, float f0)
{
    float NdotV = saturate(dot(normalWS, viewDirWS));
    return FresnelSchlick(f0, NdotV);
}

struct FresnelData
{
    float reflectance;
    float transmittance;
    float entryTransmittance;
    float exitTransmittance;
};

FresnelData ComputeFresnelData(float f0, float3 normalWS, float3 viewDirWS, float3 lightDirWS)
{
    FresnelData data;
    
    float NdotV = saturate(dot(normalWS, viewDirWS));
    float NdotL = saturate(dot(normalWS, lightDirWS));
    
    data.reflectance = FresnelSchlick(f0, NdotV);
    data.transmittance = 1.0 - data.reflectance;
    data.entryTransmittance = FresnelTransmission(f0, NdotL);
    data.exitTransmittance = FresnelTransmission(f0, NdotV);
    
    return data;
}

float FresnelAverage(float f0)
{
    return f0 + (1.0 - f0) / 3.0;
}

float IorToF0(float ior)
{
    float temp = (ior - 1.0) / (ior + 1.0);
    return temp * temp;
}

float F0ToIor(float f0)
{
    float sqrtF0 = sqrt(f0);
    return (1.0 + sqrtF0) / (1.0 - sqrtF0);
}

#endif
