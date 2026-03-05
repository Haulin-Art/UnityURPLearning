#ifndef FF_WATER_RAY_MARCHING_INCLUDED
#define FF_WATER_RAY_MARCHING_INCLUDED

#include "ff_WaterCommon.hlsl"
#include "ff_WaterPhase.hlsl"

#define FF_RAY_MARCH_STEPS_DEFAULT 6
#define FF_EXP_FACTOR_DEFAULT 3.0

struct FFRayMarchConfig
{
    int stepCount;
    float expFactor;
    float maxDistance;
    float jitterStrength;
};

FFRayMarchConfig FFCreateDefaultRayMarchConfig()
{
    FFRayMarchConfig config;
    config.stepCount = FF_RAY_MARCH_STEPS_DEFAULT;
    config.expFactor = FF_EXP_FACTOR_DEFAULT;
    config.maxDistance = 100.0;
    config.jitterStrength = 1.0;
    return config;
}

float FFGetExponentialStepPosition(float t, float k, float n)
{
    float denom = exp(k) - 1.0;
    return (exp(k * t) - 1.0) / denom;
}

float FFGetExponentialStepSize(float t, float k, float n, float maxDistance)
{
    float posCurrent = FFGetExponentialStepPosition(t, k, n);
    float posNext = FFGetExponentialStepPosition(t + 1.0 / n, k, n);
    return (posNext - posCurrent) * maxDistance;
}

float FFGetLinearStepSize(float maxDistance, int stepCount)
{
    return maxDistance / float(stepCount);
}

float3 FFAccumulateScattering(
    float3 accumulatedScatter,
    float3 accumulatedTransmittance,
    float3 lightColor,
    float3 extinctionCoeff,
    float3 scatterAlbedo,
    float stepDistance,
    float phaseValue,
    float shadowValue)
{
    float3 stepTransmittance = exp(-extinctionCoeff * stepDistance);
    float3 extinctionFactor = 1.0 - stepTransmittance;
    
    float3 scatterContribution = lightColor * extinctionFactor * scatterAlbedo * phaseValue * (1.0 - shadowValue);
    
    return accumulatedScatter + scatterContribution * accumulatedTransmittance;
}

float3 FFRayMarchVolumeScattering(
    float3 rayOrigin,
    float3 rayDirection,
    float maxDistance,
    float3 extinctionCoeff,
    float3 scatterAlbedo,
    float3 lightDir,
    float3 viewDir,
    float3 lightColor,
    float phaseG,
    float shadowValue,
    FFRayMarchConfig config)
{
    float3 totalScatter = 0;
    float3 accumulatedTransmittance = 1;
    
    float dither = FFSampleDither(rayOrigin.xy, _Time.y) * config.jitterStrength;
    
    float cosTheta = FFComputePhaseCosTheta(viewDir, lightDir);
    
    [loop]
    for (int i = 0; i < config.stepCount; i++)
    {
        float t = (float(i) + dither) / float(config.stepCount);
        float normalizedDistance = FFGetExponentialStepPosition(t, config.expFactor, config.stepCount);
        float currentDistance = normalizedDistance * maxDistance;
        
        float stepSize = FFGetExponentialStepSize(t, config.expFactor, config.stepCount, maxDistance);
        
        float3 stepTransmittance = exp(-extinctionCoeff * stepSize);
        
        float phaseValue = FFWaterPhaseFunctionFast(phaseG, cosTheta);
        
        float3 extinctionFactor = 1.0 - stepTransmittance;
        float3 scatterContribution = lightColor * extinctionFactor * scatterAlbedo * phaseValue * (1.0 - shadowValue);
        
        totalScatter += scatterContribution * accumulatedTransmittance;
        
        accumulatedTransmittance *= stepTransmittance;
    }
    
    return totalScatter;
}

float3 FFRayMarchVolumeScatteringLinear(
    float3 rayOrigin,
    float3 rayDirection,
    float maxDistance,
    float3 extinctionCoeff,
    float3 scatterAlbedo,
    float3 lightDir,
    float3 viewDir,
    float3 lightColor,
    float phaseG,
    float shadowValue,
    int stepCount)
{
    float3 totalScatter = 0;
    float3 accumulatedTransmittance = 1;
    
    float stepSize = maxDistance / float(stepCount);
    float dither = FFSampleDither(rayOrigin.xy, _Time.y);
    
    float cosTheta = FFComputePhaseCosTheta(viewDir, lightDir);
    float phaseValue = FFWaterPhaseFunctionFast(phaseG, cosTheta);
    
    [loop]
    for (int i = 0; i < stepCount; i++)
    {
        float t = (float(i) + dither) / float(stepCount);
        float currentDistance = t * maxDistance;
        
        float3 stepTransmittance = exp(-extinctionCoeff * stepSize);
        float3 extinctionFactor = 1.0 - stepTransmittance;
        
        float3 scatterContribution = lightColor * extinctionFactor * scatterAlbedo * phaseValue * (1.0 - shadowValue);
        
        totalScatter += scatterContribution * accumulatedTransmittance;
        
        accumulatedTransmittance *= stepTransmittance;
    }
    
    return totalScatter;
}

float3 FFRayMarchWithSceneColor(
    float3 rayOrigin,
    float3 rayDirection,
    float maxDistance,
    float3 extinctionCoeff,
    float3 scatterCoeff,
    float3 scatterAlbedo,
    float3 lightDir,
    float3 viewDir,
    float3 lightColor,
    float3 sceneColor,
    float phaseG,
    float shadowValue,
    FFRayMarchConfig config)
{
    float3 volumeScatter = FFRayMarchVolumeScattering(
        rayOrigin, rayDirection, maxDistance,
        extinctionCoeff, scatterAlbedo,
        lightDir, viewDir, lightColor,
        phaseG, shadowValue, config
    );
    
    float3 totalTransmittance = exp(-extinctionCoeff * maxDistance);
    
    float3 sceneScatter = sceneColor * 
        totalTransmittance * 
        scatterCoeff * 
        maxDistance * 
        FFLuminance(lightColor) * 
        0.3;
    
    return volumeScatter + sceneScatter;
}

float3 FFRayMarchDeepWater(
    float3 surfacePos,
    float3 viewDir,
    float waterDepth,
    float3 extinctionCoeff,
    float3 scatterAlbedo,
    float3 lightDir,
    float3 lightColor,
    float phaseG,
    float shadowValue,
    int stepCount)
{
    FFRayMarchConfig config = FFCreateDefaultRayMarchConfig();
    config.stepCount = stepCount;
    config.maxDistance = waterDepth;
    
    float3 rayDir = -viewDir;
    rayDir.y = -abs(rayDir.y);
    rayDir = normalize(rayDir);
    
    float maxMarchDistance = min(waterDepth * 2.0, config.maxDistance);
    
    return FFRayMarchVolumeScattering(
        surfacePos, rayDir, maxMarchDistance,
        extinctionCoeff, scatterAlbedo,
        lightDir, viewDir, lightColor,
        phaseG, shadowValue, config
    );
}

float3 FFFastVolumeScattering(
    float waterDepth,
    float3 extinctionCoeff,
    float3 scatterAlbedo,
    float3 lightDir,
    float3 viewDir,
    float3 lightColor,
    float phaseG)
{
    float opticalDepth = FFLuminance(extinctionCoeff) * waterDepth;
    float3 transmittance = exp(-extinctionCoeff * waterDepth);
    
    float cosTheta = FFComputePhaseCosTheta(viewDir, lightDir);
    float phaseValue = FFWaterPhaseFunctionFast(phaseG, cosTheta);
    
    float3 extinctionFactor = 1.0 - transmittance;
    float3 scatter = lightColor * extinctionFactor * scatterAlbedo * phaseValue;
    
    return scatter;
}

float3 FFEstimateWaterDepthFromScene(
    float2 screenUV,
    float linearEyeDepth,
    float surfaceHeight)
{
    float sceneDepth = linearEyeDepth;
    float waterSurfaceDepth = surfaceHeight;
    float waterDepth = max(0, sceneDepth - waterSurfaceDepth);
    
    return waterDepth;
}

#endif
