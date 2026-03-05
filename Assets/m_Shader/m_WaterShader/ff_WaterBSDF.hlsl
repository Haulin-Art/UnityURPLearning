#ifndef FF_WATER_BSDF_INCLUDED
#define FF_WATER_BSDF_INCLUDED

#include "ff_WaterCommon.hlsl"
#include "ff_WaterFresnel.hlsl"
#include "ff_WaterPhase.hlsl"

#define FF_SSS_PATH_SCALE 20.0
#define FF_SSS_NONLINEAR_STRENGTH 0.5
#define FF_SSS_SCATTER_BOOST 1.5
#define FF_BACKLIT_PATH_SCALE 5.0

struct FFWaterBSDFInput
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

struct FFWaterBSDFOutput
{
    float3 diffR;
    float3 diffT;
    float3 totalScattering;
};

struct FFIncidentGeometry
{
    float G_entry;
    float G_sss;
    float G_backlit;
    float T_entry;
};

FFIncidentGeometry FFComputeIncidentGeometry(float3 normalWS, float3 lightDirWS, float fresnel0)
{
    FFIncidentGeometry geo;
    
    float NdotL = dot(normalWS, lightDirWS);
    
    geo.G_entry = saturate(NdotL);
    geo.G_sss = 1.0 - geo.G_entry;
    geo.G_backlit = saturate(-NdotL);
    
    geo.T_entry = FFFresnelTransmission(fresnel0, saturate(abs(NdotL)));
    
    return geo;
}

float3 FFCalculateScatteredLight(
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

float3 FFCalculateScatteredLightSimple(
    float3 lightColor,
    float3 scatterCoeff,
    float opticalDepth,
    float phaseValue)
{
    float3 transmittance = exp(-scatterCoeff * opticalDepth);
    float3 scatteredLight = lightColor * (1.0 - transmittance) * phaseValue;
    
    return scatteredLight;
}

float FFComputeEffectivePathLength(float thickness, float3 scatterCoeff, float pathScale)
{
    float linearPath = thickness * pathScale;
    float nonlinearPath = thickness * thickness * pathScale * (1.0 + FFLuminance(scatterCoeff));
    
    float opticalDepth = FFLuminance(scatterCoeff) * thickness * pathScale;
    float strengthFactor = FF_SSS_NONLINEAR_STRENGTH * opticalDepth;
    
    float effectivePath = lerp(linearPath, nonlinearPath, saturate(strengthFactor));
    
    return effectivePath;
}

float3 FFComputeThinLayerSSS(
    FFWaterBSDFInput input,
    FFIncidentGeometry geo,
    float3 volumeScattering)
{
    float effectivePath = FFComputeEffectivePathLength(
        input.thickness, 
        input.scatterCoeff, 
        FF_SSS_PATH_SCALE
    );
    
    float opticalDepth = FFLuminance(input.extinctionCoeff) * effectivePath;
    
    float cosTheta = FFComputePhaseCosTheta(input.viewDirWS, input.lightDirWS);
    float phaseValue = FFWaterPhaseFunctionFast(input.phaseG, cosTheta);
    
    float3 thinLayerScatter = FFCalculateScatteredLight(
        input.lightColor,
        input.extinctionCoeff,
        input.scatterAlbedo,
        opticalDepth,
        phaseValue,
        input.shadowValue
    );
    
    thinLayerScatter *= FF_SSS_SCATTER_BOOST;
    
    float3 transmittance = exp(-input.extinctionCoeff * effectivePath);
    float sssWeight = 1.0 - FFLuminance(transmittance);
    
    float3 result = lerp(volumeScattering, thinLayerScatter, sssWeight);
    result *= geo.G_sss;
    
    return result;
}

float3 FFComputeBacklitTransmission(
    FFWaterBSDFInput input,
    FFIncidentGeometry geo)
{
    float effectivePath = input.thickness * FF_BACKLIT_PATH_SCALE;
    
    float3 transmittance = exp(-input.extinctionCoeff * effectivePath);
    
    float cosTheta = FFComputePhaseCosTheta(input.viewDirWS, input.lightDirWS);
    float phaseValue = FFPhaseWaterBacklitFast(cosTheta);
    
    float3 backlitResult = input.lightColor * transmittance * phaseValue;
    backlitResult *= geo.G_backlit;
    backlitResult *= (1.0 - input.shadowValue);
    
    return backlitResult;
}

float3 FFComputeVolumeScatteringSimple(
    FFWaterBSDFInput input,
    FFIncidentGeometry geo)
{
    float effectivePath = FFComputeEffectivePathLength(
        input.thickness, 
        input.scatterCoeff, 
        FF_SSS_PATH_SCALE
    );
    
    float opticalDepth = FFLuminance(input.extinctionCoeff) * effectivePath;
    float cosTheta = FFComputePhaseCosTheta(input.viewDirWS, input.lightDirWS);
    float phaseValue = FFWaterPhaseFunctionFast(input.phaseG, cosTheta);
    
    float3 volumeScatter = FFCalculateScatteredLight(
        input.lightColor,
        input.extinctionCoeff,
        input.scatterAlbedo,
        opticalDepth,
        phaseValue,
        input.shadowValue
    );
    
    return volumeScatter;
}

FFWaterBSDFOutput FFEvaluateWaterBSDFSimple(FFWaterBSDFInput input)
{
    FFWaterBSDFOutput output = (FFWaterBSDFOutput)0;
    
    FFIncidentGeometry geo = FFComputeIncidentGeometry(
        input.normalWS, 
        input.lightDirWS, 
        input.fresnel0
    );
    
    float3 volumeScatter = FFComputeVolumeScatteringSimple(input, geo);
    
    output.diffR = geo.G_entry * geo.T_entry * volumeScatter;
    
    float3 thinLayerSSS = FFComputeThinLayerSSS(input, geo, volumeScatter);
    float3 backlitTransmission = FFComputeBacklitTransmission(input, geo);
    output.diffT = thinLayerSSS + backlitTransmission;
    
    float T_exit = FFFresnelExit(input.fresnel0, input.normalWS, input.viewDirWS);
    output.totalScattering = (output.diffR + output.diffT) * T_exit;
    
    return output;
}

float3 FFEvaluateWaterScattering(
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
    FFWaterBSDFInput input;
    input.scatterCoeff = scatterColor;
    input.absorptionCoeff = absorptionColor;
    input.extinctionCoeff = scatterColor + absorptionColor;
    input.scatterAlbedo = scatterColor / max(input.extinctionCoeff, 1e-6);
    input.thickness = thickness;
    input.fresnel0 = fresnel0;
    input.phaseG = phaseG;
    input.normalWS = normalWS;
    input.viewDirWS = viewDirWS;
    input.lightDirWS = lightDirWS;
    input.lightColor = lightColor;
    input.shadowValue = shadowValue;
    
    FFWaterBSDFOutput output = FFEvaluateWaterBSDFSimple(input);
    
    return output.totalScattering;
}

#endif
