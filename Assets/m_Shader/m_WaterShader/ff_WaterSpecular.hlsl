#ifndef FF_WATER_SPECULAR_INCLUDED
#define FF_WATER_SPECULAR_INCLUDED

#include "ff_WaterCommon.hlsl"

float3 FFCalculateSpecularBlinnPhong(
    float3 normalWS,
    float3 viewDirWS,
    float3 lightDir,
    float3 lightColor,
    float specularPower,
    float intensity)
{
    float3 halfDir = normalize(lightDir + viewDirWS);
    float NdotH = saturate(dot(normalWS, halfDir));
    float specular = pow(NdotH, specularPower);
    return lightColor * specular * intensity;
}

float3 FFCalculateSpecularPhong(
    float3 normalWS,
    float3 viewDirWS,
    float3 lightDir,
    float3 lightColor,
    float specularPower,
    float intensity)
{
    float3 reflectDir = reflect(-lightDir, normalWS);
    float RdotV = saturate(dot(reflectDir, viewDirWS));
    float specular = pow(RdotV, specularPower);
    return lightColor * specular * intensity;
}

float FFNormalDistributionGGX(float NdotH, float roughness)
{
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH2 = NdotH * NdotH;
    
    float denom = NdotH2 * (a2 - 1.0) + 1.0;
    denom = FF_PI * denom * denom;
    
    return a2 / denom;
}

float FFGeometrySchlickGGX(float NdotV, float roughness)
{
    float r = roughness + 1.0;
    float k = (r * r) / 8.0;
    
    return NdotV / (NdotV * (1.0 - k) + k);
}

float FFGeometrySmith(float NdotV, float NdotL, float roughness)
{
    float ggx1 = FFGeometrySchlickGGX(NdotV, roughness);
    float ggx2 = FFGeometrySchlickGGX(NdotL, roughness);
    return ggx1 * ggx2;
}

float3 FFFresnelSchlickRoughness(float3 f0, float cosTheta, float roughness)
{
    float t = 1.0 - cosTheta;
    float t2 = t * t;
    float t5 = t2 * t2 * t;
    float3 oneMinusRoughness = 1.0 - roughness;
    return f0 + (max(oneMinusRoughness, f0) - f0) * t5;
}

float3 FFCalculateSpecularGGX(
    float3 normalWS,
    float3 viewDirWS,
    float3 lightDir,
    float3 lightColor,
    float roughness,
    float3 f0,
    float intensity)
{
    float3 halfDir = normalize(lightDir + viewDirWS);
    
    float NdotH = saturate(dot(normalWS, halfDir));
    float NdotV = saturate(dot(normalWS, viewDirWS));
    float NdotL = saturate(dot(normalWS, lightDir));
    float HdotV = saturate(dot(halfDir, viewDirWS));
    
    float D = FFNormalDistributionGGX(NdotH, roughness);
    float G = FFGeometrySmith(NdotV, NdotL, roughness);
    float3 F = FFFresnelSchlickRoughness(f0, HdotV, roughness);
    
    float3 numerator = D * G * F;
    float denominator = 4.0 * NdotV * NdotL + 0.0001;
    float3 specular = numerator / denominator;
    
    return specular * lightColor * intensity * NdotL;
}

float3 FFCalculateSpecularGGXSimple(
    float3 normalWS,
    float3 viewDirWS,
    float3 lightDir,
    float3 lightColor,
    float roughness,
    float intensity)
{
    float3 f0 = float3(0.02, 0.02, 0.02);
    return FFCalculateSpecularGGX(normalWS, viewDirWS, lightDir, lightColor, roughness, f0, intensity);
}

float3 FFCalculateWaterSpecular(
    float3 normalWS,
    float3 viewDirWS,
    float3 lightDir,
    float3 lightColor,
    float specularPower,
    float intensity)
{
    return FFCalculateSpecularBlinnPhong(normalWS, viewDirWS, lightDir, lightColor, specularPower, intensity);
}

float3 FFCalculateSpecularMultiLight(
    float3 normalWS,
    float3 viewDirWS,
    float specularPower,
    float intensity)
{
    float3 totalSpecular = 0;
    
    Light mainLight = GetMainLight();
    totalSpecular += FFCalculateSpecularBlinnPhong(
        normalWS, viewDirWS, mainLight.direction, 
        mainLight.color, specularPower, intensity
    );
    
#ifdef _ADDITIONAL_LIGHTS
    int additionalLightsCount = GetAdditionalLightsCount();
    for (int i = 0; i < additionalLightsCount; i++)
    {
        Light light = GetAdditionalLight(i, float3(0, 0, 0));
        totalSpecular += FFCalculateSpecularBlinnPhong(
            normalWS, viewDirWS, light.direction,
            light.color, specularPower, intensity * 0.5
        );
    }
#endif
    
    return totalSpecular;
}

float3 FFGetSpecularDominantDirection(float3 normalWS, float3 viewDirWS)
{
    float NdotV = saturate(dot(normalWS, viewDirWS));
    float3 reflectDir = reflect(-viewDirWS, normalWS);
    float lerpFactor = pow(1.0 - NdotV, 2.0) * 0.5;
    return normalize(lerp(normalWS, reflectDir, lerpFactor));
}

float3 FFBlendSpecularEnv(
    float3 specular,
    float3 envReflection,
    float fresnel,
    float envStrength)
{
    return specular + envReflection * fresnel * envStrength;
}

float3 FFSampleEnvReflectionWithFresnel(
    float3 reflectDir,
    float roughness,
    float envStrength,
    float fresnel)
{
    float perceptualRoughness = roughness;
    float3 envColor = GlossyEnvironmentReflection(reflectDir, perceptualRoughness, 1.0);
    return envColor * envStrength * fresnel;
}

float3 FFComputeFullSpecular(
    float3 normalWS,
    float3 viewDirWS,
    float3 lightDir,
    float3 lightColor,
    float specularPower,
    float specularIntensity,
    float roughness,
    float envReflectionStrength,
    float fresnel)
{
    float3 directSpecular = FFCalculateSpecularBlinnPhong(
        normalWS, viewDirWS, lightDir, lightColor, 
        specularPower, specularIntensity
    );
    
    float3 reflectDir = reflect(-viewDirWS, normalWS);
    float3 envReflection = GlossyEnvironmentReflection(reflectDir, roughness, 1.0);
    float3 indirectSpecular = envReflection * envReflectionStrength * fresnel;
    
    return directSpecular + indirectSpecular;
}

#endif
