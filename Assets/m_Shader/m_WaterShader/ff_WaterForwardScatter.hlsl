#ifndef FF_WATER_FORWARD_SCATTER_INCLUDED
#define FF_WATER_FORWARD_SCATTER_INCLUDED

#include "ff_WaterCommon.hlsl"

float3 FFComputeWaterSSS(
    float3 normalWS,
    float3 vertexNormal,
    float3 viewDirWS,
    float3 lightDir,
    float3 lightColor,
    float waterDepth,
    float3 sssColor,
    float sssStrength,
    float sssDepthScale)
{
    float depthFactor = saturate(waterDepth / sssDepthScale);
    
    float3 sssResult = 0;
    
    float sssFacePart = saturate(dot(viewDirWS, lerp(vertexNormal, normalWS, 0.3)));
    sssFacePart *= sssStrength;
    
    float3 depthSSSColor = sssColor * depthFactor;
    depthSSSColor = depthSSSColor * sssFacePart;
    
    float lightPart = 1.0 - viewDirWS.y;
    lightPart *= lightPart;
    
    float3 reflectedView = viewDirWS * float3(-1, 1, -1);
    lightPart = (dot(lightDir, reflectedView) + 1.0) * lightPart;
    
    float lightYFactor = saturate(lightDir.y);
    sssResult = lightPart * depthSSSColor * lightYFactor * lightColor;
    
    return sssResult;
}

float3 FFComputeWaterSSSFull(
    float3 normalWS,
    float3 vertexNormal,
    float3 viewDirWS,
    float3 lightDir,
    float3 lightColor,
    float waterDepth,
    float3 sssColor,
    float sssStrength,
    float sssDepthScale,
    float sssFade)
{
    float depthFactor = saturate(waterDepth / sssDepthScale);
    
    float3 sssResult = 0;
    
    float3 blendedNormal = lerp(vertexNormal, normalWS, 0.3);
    float sssFacePart = saturate(dot(sssFade * viewDirWS, blendedNormal)) * sssStrength;
    
    float3 depthSSSColor = sssColor * depthFactor * sssFacePart;
    
    float lightPart = 1.0 - viewDirWS.y;
    lightPart *= lightPart;
    
    float3 reflectedView = viewDirWS * float3(-1, 1, -1);
    lightPart = (dot(lightDir, reflectedView) + 1.0) * lightPart;
    
    float lightYFactor = saturate(lightDir.y);
    sssResult = lightPart * depthSSSColor * lightYFactor * lightColor;
    
    return sssResult;
}

float3 FFComputeSunGlitterSimple(
    float3 normalWS,
    float3 viewDirWS,
    float3 lightDirWS,
    float3 lightColor,
    float intensity)
{
    float3 reflectDir = reflect(-viewDirWS, normalWS);
    float RdotL = saturate(dot(reflectDir, lightDirWS));
    
    float glitter = pow(RdotL, 256.0);
    
    return lightColor * glitter * intensity;
}

float3 FFComputeSunGlitterAnimated(
    float3 normalWS,
    float3 viewDirWS,
    float3 lightDirWS,
    float3 lightColor,
    float roughness,
    float intensity,
    float time,
    float speed)
{
    float3 reflectDir = reflect(-viewDirWS, normalWS);
    float RdotL = saturate(dot(reflectDir, lightDirWS));
    
    float noise = frac(sin(dot(floor(time * speed), float2(12.9898, 78.233))) * 43758.5453);
    
    float specularPower = lerp(256.0, 64.0, roughness);
    float glitter = pow(RdotL * (0.8 + 0.2 * noise), specularPower);
    
    return lightColor * glitter * intensity;
}

#endif
