#ifndef AAAW_WATER_FRESNEL_INCLUDED
#define AAAW_WATER_FRESNEL_INCLUDED

#include "AAAW_WaterCommon.hlsl"

float AAAWFresnelSchlick(float f0, float cosTheta)
{
    float t = 1.0 - cosTheta;
    float t2 = t * t;
    float t5 = t2 * t2 * t;
    return f0 + (1.0 - f0) * t5;
}

float AAAWFresnelSchlickRoughness(float f0, float cosTheta, float roughness)
{
    float t = 1.0 - cosTheta;
    float t2 = t * t;
    float t5 = t2 * t2 * t;
    float oneMinusRoughness = 1.0 - roughness;
    return f0 + (max(oneMinusRoughness, f0) - f0) * t5;
}

float AAAWFresnelUnreal(float f0, float cosTheta)
{
    float t = saturate(1.0 - cosTheta);
    float t2 = t * t;
    float t5 = t2 * t2 * t;
    return saturate(50.0 * f0 * t5 + f0 + (1.0 - f0) * t5);
}

float3 AAAWFresnelSchlick3(float3 f0, float cosTheta)
{
    float t = 1.0 - cosTheta;
    float t2 = t * t;
    float t5 = t2 * t2 * t;
    return f0 + (1.0 - f0) * t5;
}

float3 AAAWFresnelSchlickRoughness3(float3 f0, float cosTheta, float roughness)
{
    float t = 1.0 - cosTheta;
    float t2 = t * t;
    float t5 = t2 * t2 * t;
    float oneMinusRoughness = 1.0 - roughness;
    return f0 + (max(oneMinusRoughness.xxx, f0) - f0) * t5;
}

float AAAWFresnelFull(float n1, float n2, float cosThetaI)
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

float AAAWFresnelTransmission(float f0, float cosTheta)
{
    float fresnelReflect = AAAWFresnelSchlick(f0, cosTheta);
    return 1.0 - fresnelReflect;
}

float3 AAAWFresnelTransmission3(float3 f0, float cosTheta)
{
    float3 fresnelReflect = AAAWFresnelSchlick3(f0, cosTheta);
    return 1.0 - fresnelReflect;
}

float AAAWFresnelEntry(float f0, float3 normalWS, float3 lightDirWS)
{
    float NdotL = saturate(dot(normalWS, lightDirWS));
    return AAAWFresnelTransmission(f0, NdotL);
}

float AAAWFresnelExit(float f0, float3 normalWS, float3 viewDirWS)
{
    float NdotV = saturate(dot(normalWS, viewDirWS));
    return AAAWFresnelTransmission(f0, NdotV);
}

float AAAWFresnelEntryFull(float n1, float n2, float3 normalWS, float3 lightDirWS)
{
    float cosThetaI = saturate(dot(normalWS, lightDirWS));
    return 1.0 - AAAWFresnelFull(n1, n2, cosThetaI);
}

float AAAWFresnelExitFull(float n1, float n2, float3 normalWS, float3 viewDirWS)
{
    float cosThetaI = saturate(dot(normalWS, viewDirWS));
    return 1.0 - AAAWFresnelFull(n1, n2, cosThetaI);
}

float AAAWFresnelDielectric(float eta, float cosThetaI)
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

float3 AAAWEvaluateFresnelWater(float3 normalWS, float3 viewDirWS, float f0)
{
    float NdotV = saturate(dot(normalWS, viewDirWS));
    return AAAWFresnelSchlick3(float3(f0, f0, f0), NdotV);
}

float AAAWEvaluateFresnelWaterScalar(float3 normalWS, float3 viewDirWS, float f0)
{
    float NdotV = saturate(dot(normalWS, viewDirWS));
    return AAAWFresnelSchlick(f0, NdotV);
}

struct AAAWFresnelData
{
    float reflectance;
    float transmittance;
    float entryTransmittance;
    float exitTransmittance;
};

AAAWFresnelData AAAWComputeFresnelData(float f0, float3 normalWS, float3 viewDirWS, float3 lightDirWS)
{
    AAAWFresnelData data;
    
    float NdotV = saturate(dot(normalWS, viewDirWS));
    float NdotL = saturate(dot(normalWS, lightDirWS));
    
    data.reflectance = AAAWFresnelSchlick(f0, NdotV);
    data.transmittance = 1.0 - data.reflectance;
    data.entryTransmittance = AAAWFresnelTransmission(f0, NdotL);
    data.exitTransmittance = AAAWFresnelTransmission(f0, NdotV);
    
    return data;
}

float AAAWFresnelAverage(float f0)
{
    return f0 + (1.0 - f0) / 3.0;
}

float AAAWIorToF0(float ior)
{
    float temp = (ior - 1.0) / (ior + 1.0);
    return temp * temp;
}

float AAAWF0ToIor(float f0)
{
    float sqrtF0 = sqrt(f0);
    return (1.0 + sqrtF0) / (1.0 - sqrtF0);
}

#endif
