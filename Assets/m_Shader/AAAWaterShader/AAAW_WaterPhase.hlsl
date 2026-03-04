#ifndef AAAW_WATER_PHASE_INCLUDED
#define AAAW_WATER_PHASE_INCLUDED

#include "AAAW_WaterCommon.hlsl"

float HenyeyGreensteinPhase(float g, float cosTheta)
{
    float g2 = g * g;
    float denom = 1.0 + g2 - 2.0 * g * cosTheta;
    float sqrtDenom = sqrt(denom);
    return (1.0 - g2) / (4.0 * AAAW_PI * sqrtDenom * denom);
}

float HenyeyGreensteinPhaseFast(float g, float cosTheta)
{
    float g2 = g * g;
    float denom = 1.0 + g2 - 2.0 * g * cosTheta;
    return (1.0 - g2) * pow(denom, -1.5) / (4.0 * AAAW_PI);
}

float HenyeyGreensteinPhaseNormalized(float g, float cosTheta)
{
    float g2 = g * g;
    float denom = 1.0 + g2 - 2.0 * g * cosTheta;
    return (1.0 - g2) * rsqrt(denom) / denom;
}

float RayleighPhase(float cosTheta)
{
    float cosTheta2 = cosTheta * cosTheta;
    return 3.0 / (16.0 * AAAW_PI) * (1.0 + cosTheta2);
}

float RayleighPhaseNormalized(float cosTheta)
{
    float cosTheta2 = cosTheta * cosTheta;
    return 0.75 * (1.0 + cosTheta2);
}

float MiePhase(float g, float cosTheta)
{
    return HenyeyGreensteinPhase(g, cosTheta);
}

float MiePhaseFast(float g, float cosTheta)
{
    return HenyeyGreensteinPhaseFast(g, cosTheta);
}

float WaterPhaseFunction(float g, float cosTheta)
{
    float rayleigh = RayleighPhase(cosTheta);
    float mie = MiePhase(g, cosTheta);
    return AAAW_RAYLEIGH_RATIO * rayleigh + AAAW_MIE_RATIO * mie;
}

float WaterPhaseFunctionFast(float g, float cosTheta)
{
    float rayleigh = RayleighPhaseNormalized(cosTheta);
    float mie = HenyeyGreensteinPhaseNormalized(g, cosTheta);
    return AAAW_RAYLEIGH_RATIO * rayleigh + AAAW_MIE_RATIO * mie;
}

float PhaseWaterDefault(float cosTheta)
{
    return WaterPhaseFunction(AAAW_PHASE_G_DEFAULT, cosTheta);
}

float PhaseWaterBacklit(float cosTheta)
{
    return HenyeyGreensteinPhase(AAAW_PHASE_G_BACKLIT, cosTheta);
}

float PhaseWaterBacklitFast(float cosTheta)
{
    return HenyeyGreensteinPhaseNormalized(AAAW_PHASE_G_BACKLIT, cosTheta);
}

float DoubleHenyeyGreensteinPhase(float g1, float g2, float alpha, float cosTheta)
{
    float phase1 = HenyeyGreensteinPhase(g1, cosTheta);
    float phase2 = HenyeyGreensteinPhase(g2, cosTheta);
    return alpha * phase1 + (1.0 - alpha) * phase2;
}

float SchlickPhase(float k, float cosTheta)
{
    float denom = 1.0 - k * cosTheta;
    return (1.0 - k * k) / (4.0 * AAAW_PI * denom * denom);
}

float CornetteShanksPhase(float g, float cosTheta)
{
    float g2 = g * g;
    float cosTheta2 = cosTheta * cosTheta;
    float numerator = 3.0 * (1.0 - g2) * (1.0 + cosTheta2);
    float denominator = 2.0 * (2.0 + g2) * pow(1.0 + g2 - 2.0 * g * cosTheta, 1.5);
    return numerator / (denominator * 4.0 * AAAW_PI);
}

float ComputePhaseCosTheta(float3 viewDir, float3 lightDir)
{
    return dot(-viewDir, lightDir);
}

float EvaluatePhaseWater(float3 viewDir, float3 lightDir, float g)
{
    float cosTheta = ComputePhaseCosTheta(viewDir, lightDir);
    return WaterPhaseFunction(g, cosTheta);
}

float EvaluatePhaseWaterFast(float3 viewDir, float3 lightDir, float g)
{
    float cosTheta = ComputePhaseCosTheta(viewDir, lightDir);
    return WaterPhaseFunctionFast(g, cosTheta);
}

float EvaluatePhaseBacklit(float3 viewDir, float3 lightDir)
{
    float cosTheta = ComputePhaseCosTheta(viewDir, lightDir);
    return PhaseWaterBacklit(cosTheta);
}

float EvaluatePhaseBacklitFast(float3 viewDir, float3 lightDir)
{
    float cosTheta = ComputePhaseCosTheta(viewDir, lightDir);
    return PhaseWaterBacklitFast(cosTheta);
}

float MultipleScatteringPhase(float g, float cosTheta, int bounceCount)
{
    float effectiveG = g;
    for (int i = 1; i < bounceCount; i++)
    {
        effectiveG = effectiveG * g;
    }
    return HenyeyGreensteinPhase(effectiveG, cosTheta);
}

float IsotropicPhase()
{
    return AAAW_INV_PI * 0.25;
}

float AnisotropicPhaseApproximation(float g, float cosTheta, float thickness)
{
    float thicknessFactor = saturate(thickness);
    float effectiveG = lerp(g, 0.0, thicknessFactor * 0.5);
    return HenyeyGreensteinPhase(effectiveG, cosTheta);
}

struct PhaseData
{
    float phaseValue;
    float cosTheta;
    float rayleighPhase;
    float miePhase;
};

PhaseData ComputePhaseData(float3 viewDir, float3 lightDir, float g)
{
    PhaseData data;
    data.cosTheta = ComputePhaseCosTheta(viewDir, lightDir);
    data.rayleighPhase = RayleighPhase(data.cosTheta);
    data.miePhase = MiePhase(g, data.cosTheta);
    data.phaseValue = AAAW_RAYLEIGH_RATIO * data.rayleighPhase + AAAW_MIE_RATIO * data.miePhase;
    return data;
}

#endif
