#ifndef AAAW_WATER_PHASE_INCLUDED
#define AAAW_WATER_PHASE_INCLUDED

#include "AAAW_WaterCommon.hlsl"

float AAAWHenyeyGreensteinPhase(float g, float cosTheta)
{
    float g2 = g * g;
    float denom = 1.0 + g2 - 2.0 * g * cosTheta;
    float sqrtDenom = sqrt(denom);
    return (1.0 - g2) / (4.0 * AAAW_PI * sqrtDenom * denom);
}

float AAAWHenyeyGreensteinPhaseFast(float g, float cosTheta)
{
    float g2 = g * g;
    float denom = 1.0 + g2 - 2.0 * g * cosTheta;
    return (1.0 - g2) * pow(denom, -1.5) / (4.0 * AAAW_PI);
}

float AAAWHenyeyGreensteinPhaseNormalized(float g, float cosTheta)
{
    float g2 = g * g;
    float denom = 1.0 + g2 - 2.0 * g * cosTheta;
    return (1.0 - g2) * rsqrt(denom) / denom;
}

float AAAWRayleighPhase(float cosTheta)
{
    float cosTheta2 = cosTheta * cosTheta;
    return 3.0 / (16.0 * AAAW_PI) * (1.0 + cosTheta2);
}

float AAAWRayleighPhaseNormalized(float cosTheta)
{
    float cosTheta2 = cosTheta * cosTheta;
    return 0.75 * (1.0 + cosTheta2);
}

float AAAWMiePhase(float g, float cosTheta)
{
    return AAAWHenyeyGreensteinPhase(g, cosTheta);
}

float AAAWMiePhaseFast(float g, float cosTheta)
{
    return AAAWHenyeyGreensteinPhaseFast(g, cosTheta);
}

float AAAWWaterPhaseFunction(float g, float cosTheta)
{
    float rayleigh = AAAWRayleighPhase(cosTheta);
    float mie = AAAWMiePhase(g, cosTheta);
    return AAAW_RAYLEIGH_RATIO * rayleigh + AAAW_MIE_RATIO * mie;
}

float AAAWWaterPhaseFunctionFast(float g, float cosTheta)
{
    float rayleigh = AAAWRayleighPhaseNormalized(cosTheta);
    float mie = AAAWHenyeyGreensteinPhaseNormalized(g, cosTheta);
    return AAAW_RAYLEIGH_RATIO * rayleigh + AAAW_MIE_RATIO * mie;
}

float AAAWPhaseWaterDefault(float cosTheta)
{
    return AAAWWaterPhaseFunction(AAAW_PHASE_G_DEFAULT, cosTheta);
}

float AAAWPhaseWaterBacklit(float cosTheta)
{
    return AAAWHenyeyGreensteinPhase(AAAW_PHASE_G_BACKLIT, cosTheta);
}

float AAAWPhaseWaterBacklitFast(float cosTheta)
{
    return AAAWHenyeyGreensteinPhaseNormalized(AAAW_PHASE_G_BACKLIT, cosTheta);
}

float AAAWDoubleHenyeyGreensteinPhase(float g1, float g2, float alpha, float cosTheta)
{
    float phase1 = AAAWHenyeyGreensteinPhase(g1, cosTheta);
    float phase2 = AAAWHenyeyGreensteinPhase(g2, cosTheta);
    return alpha * phase1 + (1.0 - alpha) * phase2;
}

float AAAWSchlickPhase(float k, float cosTheta)
{
    float denom = 1.0 - k * cosTheta;
    return (1.0 - k * k) / (4.0 * AAAW_PI * denom * denom);
}

float AAAWCornetteShanksPhase(float g, float cosTheta)
{
    float g2 = g * g;
    float cosTheta2 = cosTheta * cosTheta;
    float numerator = 3.0 * (1.0 - g2) * (1.0 + cosTheta2);
    float denominator = 2.0 * (2.0 + g2) * pow(1.0 + g2 - 2.0 * g * cosTheta, 1.5);
    return numerator / (denominator * 4.0 * AAAW_PI);
}

float AAAWComputePhaseCosTheta(float3 viewDir, float3 lightDir)
{
    return dot(-viewDir, lightDir);
}

float AAAWEvaluatePhaseWater(float3 viewDir, float3 lightDir, float g)
{
    float cosTheta = AAAWComputePhaseCosTheta(viewDir, lightDir);
    return AAAWWaterPhaseFunction(g, cosTheta);
}

float AAAWEvaluatePhaseWaterFast(float3 viewDir, float3 lightDir, float g)
{
    float cosTheta = AAAWComputePhaseCosTheta(viewDir, lightDir);
    return AAAWWaterPhaseFunctionFast(g, cosTheta);
}

float AAAWEvaluatePhaseBacklit(float3 viewDir, float3 lightDir)
{
    float cosTheta = AAAWComputePhaseCosTheta(viewDir, lightDir);
    return AAAWPhaseWaterBacklit(cosTheta);
}

float AAAWEvaluatePhaseBacklitFast(float3 viewDir, float3 lightDir)
{
    float cosTheta = AAAWComputePhaseCosTheta(viewDir, lightDir);
    return AAAWPhaseWaterBacklitFast(cosTheta);
}

float AAAWMultipleScatteringPhase(float g, float cosTheta, int bounceCount)
{
    float effectiveG = g;
    for (int i = 1; i < bounceCount; i++)
    {
        effectiveG = effectiveG * g;
    }
    return AAAWHenyeyGreensteinPhase(effectiveG, cosTheta);
}

float AAAWIsotropicPhase()
{
    return AAAW_INV_PI * 0.25;
}

float AAAWAnisotropicPhaseApproximation(float g, float cosTheta, float thickness)
{
    float thicknessFactor = saturate(thickness);
    float effectiveG = lerp(g, 0.0, thicknessFactor * 0.5);
    return AAAWHenyeyGreensteinPhase(effectiveG, cosTheta);
}

struct AAAWPhaseData
{
    float phaseValue;
    float cosTheta;
    float rayleighPhase;
    float miePhase;
};

AAAWPhaseData AAAWComputePhaseData(float3 viewDir, float3 lightDir, float g)
{
    AAAWPhaseData data;
    data.cosTheta = AAAWComputePhaseCosTheta(viewDir, lightDir);
    data.rayleighPhase = AAAWRayleighPhase(data.cosTheta);
    data.miePhase = AAAWMiePhase(g, data.cosTheta);
    data.phaseValue = AAAW_RAYLEIGH_RATIO * data.rayleighPhase + AAAW_MIE_RATIO * data.miePhase;
    return data;
}

#endif
