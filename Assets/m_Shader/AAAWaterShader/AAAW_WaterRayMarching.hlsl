#ifndef AAAW_WATER_RAY_MARCHING_INCLUDED
#define AAAW_WATER_RAY_MARCHING_INCLUDED

#include "AAAW_WaterCommon.hlsl"
#include "AAAW_WaterPhase.hlsl"

struct RayMarchConfig
{
    int stepCount;
    float expFactor;
    float maxDistance;
    float jitterStrength;
};

RayMarchConfig CreateDefaultRayMarchConfig()
{
    RayMarchConfig config;
    config.stepCount = AAAW_RAY_MARCH_STEPS;
    config.expFactor = AAAW_EXP_FACTOR;
    config.maxDistance = 100.0;
    config.jitterStrength = 1.0;
    return config;
}

struct RayMarchSample
{
    float3 position;
    float distance;
    float stepSize;
    float3 transmittance;
};

float GetExponentialStepSize(int stepIndex, int totalSteps, float expFactor, float maxDistance)
{
    float t = float(stepIndex) / float(totalSteps);
    float normalizedPos = ExponentialStep(t, expFactor, totalSteps);
    float nextNormalizedPos = ExponentialStep((float(stepIndex + 1)) / float(totalSteps), expFactor, totalSteps);
    return (nextNormalizedPos - normalizedPos) * maxDistance;
}

float GetLinearStepSize(float maxDistance, int totalSteps)
{
    return maxDistance / float(totalSteps);
}

float3 CalculateMarchTransmittance(float3 extinctionCoeff, float distance)
{
    return exp(-extinctionCoeff * distance);
}

float3 AccumulateScattering(
    float3 accumulatedScatter,
    float3 lightColor,
    float3 extinctionCoeff,
    float3 scatterAlbedo,
    float stepDistance,
    float accumulatedDistance,
    float phaseValue,
    float shadowValue)
{
    float3 stepTransmittance = exp(-extinctionCoeff * stepDistance);
    float3 totalTransmittance = exp(-extinctionCoeff * accumulatedDistance);
    
    float3 extinctionFactor = 1.0 - stepTransmittance;
    float3 scatterContribution = lightColor * extinctionFactor * scatterAlbedo * phaseValue * (1.0 - shadowValue);
    
    return accumulatedScatter + scatterContribution * totalTransmittance;
}

float3 RayMarchVolumeScattering(
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
    RayMarchConfig config)
{
    float3 totalScatter = 0;
    float3 accumulatedTransmittance = 1;
    
    float dither = InterleavedGradientNoise(rayOrigin.xy * _ScreenParams.xy) * config.jitterStrength;
    
    float cosTheta = ComputePhaseCosTheta(viewDir, lightDir);
    
    [loop]
    for (int i = 0; i < config.stepCount; i++)
    {
        float t = (float(i) + dither) / float(config.stepCount);
        float normalizedDistance = ExponentialStep(t, config.expFactor, config.stepCount);
        float stepDistance = normalizedDistance * maxDistance;
        
        float3 samplePos = rayOrigin + rayDirection * stepDistance;
        
        float localStepSize = GetExponentialStepSize(i, config.stepCount, config.expFactor, maxDistance);
        
        float3 stepTransmittance = exp(-extinctionCoeff * localStepSize);
        
        float phaseValue = WaterPhaseFunctionFast(phaseG, cosTheta);
        
        float3 extinctionFactor = 1.0 - stepTransmittance;
        float3 scatterContribution = lightColor * extinctionFactor * scatterAlbedo * phaseValue * (1.0 - shadowValue);
        
        totalScatter += scatterContribution * accumulatedTransmittance;
        
        accumulatedTransmittance *= stepTransmittance;
    }
    
    return totalScatter;
}

float3 RayMarchVolumeScatteringLinear(
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
    float dither = InterleavedGradientNoise(rayOrigin.xy * _ScreenParams.xy);
    
    float cosTheta = ComputePhaseCosTheta(viewDir, lightDir);
    float phaseValue = WaterPhaseFunctionFast(phaseG, cosTheta);
    
    [loop]
    for (int i = 0; i < stepCount; i++)
    {
        float t = (float(i) + dither) / float(stepCount);
        float currentDistance = t * maxDistance;
        float3 samplePos = rayOrigin + rayDirection * currentDistance;
        
        float3 stepTransmittance = exp(-extinctionCoeff * stepSize);
        float3 extinctionFactor = 1.0 - stepTransmittance;
        
        float3 scatterContribution = lightColor * extinctionFactor * scatterAlbedo * phaseValue * (1.0 - shadowValue);
        
        totalScatter += scatterContribution * accumulatedTransmittance;
        
        accumulatedTransmittance *= stepTransmittance;
    }
    
    return totalScatter;
}

float3 RayMarchWithSceneColor(
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
    RayMarchConfig config)
{
    float3 volumeScatter = RayMarchVolumeScattering(
        rayOrigin, rayDirection, maxDistance,
        extinctionCoeff, scatterAlbedo,
        lightDir, viewDir, lightColor,
        phaseG, shadowValue, config
    );
    
    float3 totalTransmittance = exp(-extinctionCoeff * maxDistance);
    
    float3 sceneScatter = sceneColor * totalTransmittance * scatterCoeff * maxDistance * Luminance(lightColor) * 0.3;
    
    return volumeScatter + sceneScatter;
}

float3 RayMarchDeepWater(
    float3 surfacePos,
    float3 viewDir,
    float waterDepth,
    float3 extinctionCoeff,
    float3 scatterAlbedo,
    float3 lightDir,
    float3 lightColor,
    float phaseG,
    float shadowValue)
{
    RayMarchConfig config = CreateDefaultRayMarchConfig();
    config.maxDistance = waterDepth;
    
    float3 rayDir = -viewDir;
    rayDir.y = -abs(rayDir.y);
    rayDir = normalize(rayDir);
    
    float maxMarchDistance = min(waterDepth * 2.0, config.maxDistance);
    
    return RayMarchVolumeScattering(
        surfacePos, rayDir, maxMarchDistance,
        extinctionCoeff, scatterAlbedo,
        lightDir, viewDir, lightColor,
        phaseG, shadowValue, config
    );
}

float3 FastVolumeScattering(
    float waterDepth,
    float3 extinctionCoeff,
    float3 scatterAlbedo,
    float3 lightDir,
    float3 viewDir,
    float3 lightColor,
    float phaseG)
{
    float opticalDepth = Luminance(extinctionCoeff) * waterDepth;
    float3 transmittance = exp(-extinctionCoeff * waterDepth);
    
    float cosTheta = ComputePhaseCosTheta(viewDir, lightDir);
    float phaseValue = WaterPhaseFunctionFast(phaseG, cosTheta);
    
    float3 extinctionFactor = 1.0 - transmittance;
    float3 scatter = lightColor * extinctionFactor * scatterAlbedo * phaseValue;
    
    return scatter;
}

float3 EstimateWaterDepth(float2 screenUV, float linearEyeDepth, float surfaceHeight)
{
    float sceneDepth = linearEyeDepth;
    float waterSurfaceDepth = surfaceHeight;
    float waterDepth = max(0, sceneDepth - waterSurfaceDepth);
    
    return waterDepth;
}

float3 ComputeRefractionOffset(float3 normalWS, float3 viewDirWS, float refractionStrength, float depth)
{
    float2 refractionOffset = normalWS.xz * refractionStrength;
    float depthFactor = saturate(depth / 10.0);
    return float3(refractionOffset * depthFactor, 0);
}

float3 SampleRefractionColor(float2 screenUV, float2 offset, float depth)
{
    float2 refractedUV = screenUV + offset;
    refractedUV = saturate(refractedUV);
    
    float3 refractionColor = SAMPLE_TEXTURE2D(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, refractedUV).rgb;
    
    float3 depthAttenuation = exp(-float3(0.1, 0.05, 0.02) * depth);
    refractionColor *= depthAttenuation;
    
    return refractionColor;
}

float ComputeFoam(float depth, float waveHeight, float threshold, float smoothness)
{
    float foamFactor = 1.0 - saturate(depth / threshold);
    foamFactor = smoothstep(0.0, 1.0, foamFactor);
    foamFactor *= saturate(waveHeight * 2.0);
    return foamFactor;
}

float3 ApplyFoam(float3 baseColor, float foamFactor, float3 foamColor, float intensity)
{
    float3 foam = foamColor * foamFactor * intensity;
    return baseColor + foam;
}

#endif
