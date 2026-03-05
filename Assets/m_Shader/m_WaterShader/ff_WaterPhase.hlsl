#ifndef FF_WATER_PHASE_INCLUDED
#define FF_WATER_PHASE_INCLUDED

#include "ff_WaterCommon.hlsl"

#define FF_RAYLEIGH_RATIO 0.05
#define FF_MIE_RATIO 0.95
#define FF_PHASE_G_DEFAULT 0.8
#define FF_PHASE_G_BACKLIT 0.998

float FFHenyeyGreensteinPhase(float g, float cosTheta)
{
    float g2 = g * g;
    float denom = 1.0 + g2 - 2.0 * g * cosTheta;
    float sqrtDenom = sqrt(denom);
    return (1.0 - g2) / (4.0 * FF_PI * sqrtDenom * denom);
}

float FFHenyeyGreensteinPhaseFast(float g, float cosTheta)
{
    float g2 = g * g;
    float denom = 1.0 + g2 - 2.0 * g * cosTheta;
    return (1.0 - g2) * pow(denom, -1.5) / (4.0 * FF_PI);
}

float FFRayleighPhase(float cosTheta)
{
    float cosTheta2 = cosTheta * cosTheta;
    return 3.0 / (16.0 * FF_PI) * (1.0 + cosTheta2);
}

float FFRayleighPhaseNormalized(float cosTheta)
{
    float cosTheta2 = cosTheta * cosTheta;
    return 0.75 * (1.0 + cosTheta2);
}

float FFMiePhase(float g, float cosTheta)
{
    return FFHenyeyGreensteinPhase(g, cosTheta);
}

float FFWaterPhaseFunction(float g, float cosTheta)
{
    float rayleigh = FFRayleighPhase(cosTheta);
    float mie = FFMiePhase(g, cosTheta);
    return FF_RAYLEIGH_RATIO * rayleigh + FF_MIE_RATIO * mie;
}

float FFWaterPhaseFunctionFast(float g, float cosTheta)
{
    float rayleigh = FFRayleighPhaseNormalized(cosTheta);
    float mie = FFHenyeyGreensteinPhaseFast(g, cosTheta);
    return FF_RAYLEIGH_RATIO * rayleigh + FF_MIE_RATIO * mie;
}

float FFPhaseWaterDefault(float cosTheta)
{
    return FFWaterPhaseFunction(FF_PHASE_G_DEFAULT, cosTheta);
}

float FFPhaseWaterBacklit(float cosTheta)
{
    return FFHenyeyGreensteinPhase(FF_PHASE_G_BACKLIT, cosTheta);
}

float FFPhaseWaterBacklitFast(float cosTheta)
{
    float g2 = FF_PHASE_G_BACKLIT * FF_PHASE_G_BACKLIT;
    float denom = 1.0 + g2 - 2.0 * FF_PHASE_G_BACKLIT * cosTheta;
    return (1.0 - g2) * rsqrt(denom) / denom;
}

float FFComputePhaseCosTheta(float3 viewDir, float3 lightDir)
{
    return dot(-viewDir, lightDir);
}

float FFEvaluatePhaseWater(float3 viewDir, float3 lightDir, float g)
{
    float cosTheta = FFComputePhaseCosTheta(viewDir, lightDir);
    return FFWaterPhaseFunction(g, cosTheta);
}

float FFEvaluatePhaseWaterFast(float3 viewDir, float3 lightDir, float g)
{
    float cosTheta = FFComputePhaseCosTheta(viewDir, lightDir);
    return FFWaterPhaseFunctionFast(g, cosTheta);
}

float FFEvaluatePhaseBacklit(float3 viewDir, float3 lightDir)
{
    float cosTheta = FFComputePhaseCosTheta(viewDir, lightDir);
    return FFPhaseWaterBacklit(cosTheta);
}

float FFEvaluatePhaseBacklitFast(float3 viewDir, float3 lightDir)
{
    float cosTheta = FFComputePhaseCosTheta(viewDir, lightDir);
    return FFPhaseWaterBacklitFast(cosTheta);
}

struct FFPhaseData
{
    float phaseValue;
    float cosTheta;
    float rayleighPhase;
    float miePhase;
};

FFPhaseData FFComputePhaseData(float3 viewDir, float3 lightDir, float g)
{
    FFPhaseData data;
    data.cosTheta = FFComputePhaseCosTheta(viewDir, lightDir);
    data.rayleighPhase = FFRayleighPhase(data.cosTheta);
    data.miePhase = FFMiePhase(g, data.cosTheta);
    data.phaseValue = FF_RAYLEIGH_RATIO * data.rayleighPhase + FF_MIE_RATIO * data.miePhase;
    return data;
}

#endif
