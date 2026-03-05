#ifndef AAAW_WATER_BSDF_INCLUDED
#define AAAW_WATER_BSDF_INCLUDED

#include "AAAW_WaterCommon.hlsl"
#include "AAAW_WaterFresnel.hlsl"
#include "AAAW_WaterPhase.hlsl"

struct AAAWWaterBSDFInput
{
    float3 scatterCoeff;
    float3 absorptionCoeff;
    float3 extinctionCoeff;
    float3 scatterAlbedo;
    
    float thickness;
    float fresnel0;
    float phaseG;
    
    float3 normalWS;
    float3 viewDirWS;
    float3 lightDirWS;
    float3 lightColor;
    
    float shadowValue;
};

struct AAAWWaterBSDFOutput
{
    float3 diffR;
    float3 diffT;
    float3 totalScattering;
};

struct AAAWIncidentGeometry
{
    float G_entry;
    float G_sss;
    float G_backlit;
    float T_entry;
};

AAAWIncidentGeometry AAAWComputeIncidentGeometry(float3 normalWS, float3 lightDirWS, float fresnel0)
{
    AAAWIncidentGeometry geo;
    
    float NdotL = dot(normalWS, lightDirWS);
    
    geo.G_entry = saturate(NdotL);
    geo.G_sss = 1.0 - geo.G_entry;
    geo.G_backlit = saturate(-NdotL);
    
    geo.T_entry = AAAWFresnelTransmission(fresnel0, saturate(abs(NdotL)));
    
    return geo;
}

float3 AAAWCalculateScatteredLight(
    float3 lightColor,
    float3 extinctionCoeff,
    float3 scatterAlbedo,
    float opticalDepth,
    float phaseValue,
    float shadowValue)
{
    float3 transmittance = exp(-extinctionCoeff * opticalDepth);
    float3 extinctionFactor = 1.0 - transmittance;
    float3 scatteredLight = lightColor * extinctionFactor * scatterAlbedo * phaseValue;
    scatteredLight *= (1.0 - shadowValue);
    
    return scatteredLight;
}

float3 AAAWCalculateScatteredLightSimple(
    float3 lightColor,
    float3 scatterCoeff,
    float opticalDepth,
    float phaseValue)
{
    float3 transmittance = exp(-scatterCoeff * opticalDepth);
    float3 scatteredLight = lightColor * (1.0 - transmittance) * phaseValue;
    
    return scatteredLight;
}

float AAAWComputeEffectivePathLength(float thickness, float3 scatterCoeff, float pathScale)
{
    float linearPath = thickness * pathScale;
    float nonlinearPath = thickness * thickness * pathScale * (1.0 + AAAWLuminance(scatterCoeff));
    
    float opticalDepth = AAAWLuminance(scatterCoeff) * thickness * pathScale;
    float strengthFactor = AAAW_SSS_NONLINEAR_STRENGTH * opticalDepth;
    
    float effectivePath = lerp(linearPath, nonlinearPath, saturate(strengthFactor));
    
    return effectivePath;
}

float3 AAAWComputeThinLayerSSS(
    AAAWWaterBSDFInput input,
    AAAWIncidentGeometry geo,
    float3 volumeScattering)
{
    float effectivePath = AAAWComputeEffectivePathLength(
        input.thickness, 
        input.scatterCoeff, 
        AAAW_SSS_PATH_SCALE
    );
    
    float opticalDepth = AAAWLuminance(input.extinctionCoeff) * effectivePath;
    
    float cosTheta = AAAWComputePhaseCosTheta(input.viewDirWS, input.lightDirWS);
    float phaseValue = AAAWWaterPhaseFunctionFast(input.phaseG, cosTheta);
    
    float3 thinLayerScatter = AAAWCalculateScatteredLight(
        input.lightColor,
        input.extinctionCoeff,
        input.scatterAlbedo,
        opticalDepth,
        phaseValue,
        input.shadowValue
    );
    
    thinLayerScatter *= AAAW_SSS_SCATTER_BOOST;
    
    float3 transmittance = exp(-input.extinctionCoeff * opticalDepth);
    float sssWeight = 1.0 - AAAWLuminance(transmittance);
    
    float3 result = lerp(volumeScattering, thinLayerScatter, sssWeight);
    result *= geo.G_sss;
    
    return result;
}

float3 AAAWComputeBacklitTransmission(
    AAAWWaterBSDFInput input,
    AAAWIncidentGeometry geo)
{
    float effectivePath = input.thickness * AAAW_BACKLIT_PATH_SCALE;
    
    float3 transmittance = exp(-input.extinctionCoeff * effectivePath);
    
    float cosTheta = AAAWComputePhaseCosTheta(input.viewDirWS, input.lightDirWS);
    float phaseValue = AAAWPhaseWaterBacklitFast(cosTheta);
    
    float3 backlitResult = input.lightColor * transmittance * phaseValue;
    backlitResult *= geo.G_backlit;
    backlitResult *= (1.0 - input.shadowValue);
    
    return backlitResult;
}

float3 AAAWComputeVolumeScattering(
    AAAWWaterBSDFInput input,
    AAAWIncidentGeometry geo,
    float3 rayStart,
    float3 rayEnd,
    float3 sceneColor)
{
    float3 totalScatter = 0;
    
    float3 rayDir = normalize(rayEnd - rayStart);
    float totalDistance = length(rayEnd - rayStart);
    
    float dither = AAAWInterleavedGradientNoise(input.normalWS.xy * 1000.0);
    
    [unroll]
    for (int i = 0; i < AAAW_RAY_MARCH_STEPS; i++)
    {
        float t = (float(i) + dither) / float(AAAW_RAY_MARCH_STEPS);
        float stepDistance = AAAWExponentialStep(t, AAAW_EXP_FACTOR, AAAW_RAY_MARCH_STEPS) * totalDistance;
        
        float3 samplePos = rayStart + rayDir * stepDistance;
        
        float opticalDepth = AAAWLuminance(input.extinctionCoeff) * stepDistance;
        float3 transmittance = exp(-input.extinctionCoeff * stepDistance);
        
        float cosTheta = AAAWComputePhaseCosTheta(input.viewDirWS, input.lightDirWS);
        float phaseValue = AAAWWaterPhaseFunctionFast(input.phaseG, cosTheta);
        
        float3 scatterContribution = input.lightColor * 
            (1.0 - transmittance) * 
            input.scatterAlbedo * 
            phaseValue * 
            (1.0 - input.shadowValue);
        
        totalScatter += scatterContribution * exp(-input.extinctionCoeff * stepDistance);
    }
    
    totalScatter /= float(AAAW_RAY_MARCH_STEPS);
    
    float3 sceneScatter = sceneColor * 
        exp(-input.extinctionCoeff * totalDistance) * 
        input.scatterCoeff * 
        totalDistance * 
        AAAWLuminance(input.lightColor) * 
        0.3;
    
    totalScatter += sceneScatter;
    
    return totalScatter;
}

AAAWWaterBSDFOutput AAAWEvaluateWaterBSDF(AAAWWaterBSDFInput input)
{
    AAAWWaterBSDFOutput output = (AAAWWaterBSDFOutput)0;
    
    AAAWIncidentGeometry geo = AAAWComputeIncidentGeometry(
        input.normalWS, 
        input.lightDirWS, 
        input.fresnel0
    );
    
    float3 volumeScatter = AAAWComputeVolumeScattering(
        input,
        geo,
        input.normalWS * 0.01,
        input.normalWS * -_DepthScale,
        float3(0, 0, 0)
    );
    
    output.diffR = geo.G_entry * geo.T_entry * volumeScatter;
    
    float3 thinLayerSSS = AAAWComputeThinLayerSSS(input, geo, volumeScatter);
    float3 backlitTransmission = AAAWComputeBacklitTransmission(input, geo);
    output.diffT = thinLayerSSS + backlitTransmission;
    
    float T_exit = AAAWFresnelExit(input.fresnel0, input.normalWS, input.viewDirWS);
    output.totalScattering = (output.diffR + output.diffT) * T_exit;
    
    return output;
}

AAAWWaterBSDFOutput AAAWEvaluateWaterBSDFSimple(AAAWWaterBSDFInput input)
{
    AAAWWaterBSDFOutput output = (AAAWWaterBSDFOutput)0;
    
    AAAWIncidentGeometry geo = AAAWComputeIncidentGeometry(
        input.normalWS, 
        input.lightDirWS, 
        input.fresnel0
    );
    
    float effectivePath = AAAWComputeEffectivePathLength(
        input.thickness, 
        input.scatterCoeff, 
        AAAW_SSS_PATH_SCALE
    );
    
    float opticalDepth = AAAWLuminance(input.extinctionCoeff) * effectivePath;
    float cosTheta = AAAWComputePhaseCosTheta(input.viewDirWS, input.lightDirWS);
    float phaseValue = AAAWWaterPhaseFunctionFast(input.phaseG, cosTheta);
    
    float3 volumeScatter = AAAWCalculateScatteredLight(
        input.lightColor,
        input.extinctionCoeff,
        input.scatterAlbedo,
        opticalDepth,
        phaseValue,
        input.shadowValue
    );
    
    output.diffR = geo.G_entry * geo.T_entry * volumeScatter;
    
    float3 thinLayerSSS = AAAWComputeThinLayerSSS(input, geo, volumeScatter);
    float3 backlitTransmission = AAAWComputeBacklitTransmission(input, geo);
    output.diffT = thinLayerSSS + backlitTransmission;
    
    float T_exit = AAAWFresnelExit(input.fresnel0, input.normalWS, input.viewDirWS);
    output.totalScattering = (output.diffR + output.diffT) * T_exit;
    
    return output;
}

float3 AAAWEvaluateWaterScattering(
    float3 normalWS,
    float3 viewDirWS,
    float3 lightDirWS,
    float3 lightColor,
    float3 scatterColor,
    float3 absorptionColor,
    float thickness,
    float fresnel0,
    float phaseG,
    float shadowValue)
{
    AAAWWaterBSDFInput input;
    input.scatterCoeff = scatterColor;
    input.absorptionCoeff = absorptionColor;
    input.extinctionCoeff = scatterColor + absorptionColor;
    input.scatterAlbedo = AAAWGetScatteringAlbedo3(scatterColor, input.extinctionCoeff);
    input.thickness = thickness;
    input.fresnel0 = fresnel0;
    input.phaseG = phaseG;
    input.normalWS = normalWS;
    input.viewDirWS = viewDirWS;
    input.lightDirWS = lightDirWS;
    input.lightColor = lightColor;
    input.shadowValue = shadowValue;
    
    AAAWWaterBSDFOutput output = AAAWEvaluateWaterBSDFSimple(input);
    
    return output.totalScattering;
}

float3 AAAWEvaluateWaterScatteringFull(
    float3 normalWS,
    float3 viewDirWS,
    float3 lightDirWS,
    float3 lightColor,
    float3 scatterColor,
    float3 absorptionColor,
    float thickness,
    float fresnel0,
    float phaseG,
    float shadowValue,
    float3 rayStart,
    float3 rayEnd,
    float3 sceneColor)
{
    AAAWWaterBSDFInput input;
    input.scatterCoeff = scatterColor;
    input.absorptionCoeff = absorptionColor;
    input.extinctionCoeff = scatterColor + absorptionColor;
    input.scatterAlbedo = AAAWGetScatteringAlbedo3(scatterColor, input.extinctionCoeff);
    input.thickness = thickness;
    input.fresnel0 = fresnel0;
    input.phaseG = phaseG;
    input.normalWS = normalWS;
    input.viewDirWS = viewDirWS;
    input.lightDirWS = lightDirWS;
    input.lightColor = lightColor;
    input.shadowValue = shadowValue;
    
    AAAWWaterBSDFOutput output = AAAWEvaluateWaterBSDF(input);
    
    return output.totalScattering;
}

#endif
