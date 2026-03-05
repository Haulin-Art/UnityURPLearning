#ifndef AAAW_WATER_COMMON_INCLUDED
#define AAAW_WATER_COMMON_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

#define AAAW_PI 3.14159265359
#define AAAW_INV_PI 0.31830988618
#define AAAW_TWO_PI 6.28318530718

#define AAAW_RAY_MARCH_STEPS 6
#define AAAW_EXP_FACTOR 3.0

#define AAAW_SSS_PATH_SCALE 20.0
#define AAAW_SSS_NONLINEAR_STRENGTH 0.5
#define AAAW_SSS_SCATTER_BOOST 1.5
#define AAAW_BACKLIT_PATH_SCALE 5.0

#define AAAW_PHASE_G_DEFAULT 0.8
#define AAAW_PHASE_G_BACKLIT 0.998

#define AAAW_FRESNEL_0_WATER 0.02

#define AAAW_RAYLEIGH_RATIO 0.05
#define AAAW_MIE_RATIO 0.95

CBUFFER_START(UnityPerMaterial)
    float4 _BaseColor;
    float4 _ScatterColor;
    float4 _AbsorptionColor;
    
    float _Fresnel0;
    float _PhaseG;
    float _Thickness;
    float _DepthScale;
    
    float _NormalScale;
    float _WaveSpeed;
    float _WaveHeight;
    float _WaveFrequency;
    
    float _RefractionStrength;
    float _SpecularStrength;
    float _Smoothness;
    float _EnvReflectionStrength;
    
    float4 _WaveDirection1;
    float4 _WaveDirection2;
    
    float _FoamThreshold;
    float _FoamSmoothness;
    float _FoamDistance;
    float _FoamIntensity;
    
    float _RayMarchSteps;
CBUFFER_END

TEXTURE2D(_CameraOpaqueTexture);
SAMPLER(sampler_CameraOpaqueTexture);

TEXTURE2D(_WaterNormalMap);
SAMPLER(sampler_WaterNormalMap);

TEXTURE2D(_WaterNormalMap2);
SAMPLER(sampler_WaterNormalMap2);

TEXTURE2D(_FoamTexture);
SAMPLER(sampler_FoamTexture);

float AAAWLuminance(float3 color)
{
    return dot(color, float3(0.2126729, 0.7151522, 0.0721750));
}

float3 AAAWSafeNormalize(float3 v)
{
    float len = length(v);
    return len > 1e-6 ? v / len : float3(0, 1, 0);
}

float AAAWSquare(float x)
{
    return x * x;
}

float3 AAAWSquare3(float3 x)
{
    return x * x;
}

float AAAWPow5(float x)
{
    float x2 = x * x;
    return x2 * x2 * x;
}

float3 AAAWPow5_3(float3 x)
{
    float3 x2 = x * x;
    return x2 * x2 * x;
}

float AAAWRemap(float value, float inMin, float inMax, float outMin, float outMax)
{
    return outMin + (value - inMin) * (outMax - outMin) / (inMax - inMin);
}

float AAAWRemap01(float value, float inMin, float inMax)
{
    return saturate((value - inMin) / (inMax - inMin));
}

float3 AAAWBlendNormal(float3 n1, float3 n2)
{
    float3 t = n1 * float3(2, 2, 2) + float3(-1, -1, 0);
    float3 u = n2 * float3(2, 2, 2) + float3(-1, -1, 0);
    float3 r = t * dot(t, u) - u * t.z;
    return normalize(r);
}

float3 AAAWUnpackNormalAG(float4 packedNormal, float scale)
{
    float3 normal;
    normal.xy = packedNormal.ag * 2.0 - 1.0;
    normal.xy *= scale;
    normal.z = sqrt(1.0 - saturate(dot(normal.xy, normal.xy)));
    return normal;
}

float3 AAAWGetWaterNormal(float2 uv, float time)
{
    float2 uv1 = uv * _WaveFrequency + time * _WaveSpeed * _WaveDirection1.xy;
    float2 uv2 = uv * _WaveFrequency * 0.7 + time * _WaveSpeed * _WaveDirection2.xy;
    
    float4 normalSample1 = SAMPLE_TEXTURE2D(_WaterNormalMap, sampler_WaterNormalMap, uv1);
    float4 normalSample2 = SAMPLE_TEXTURE2D(_WaterNormalMap2, sampler_WaterNormalMap2, uv2);
    
    float3 normal1 = AAAWUnpackNormalAG(normalSample1, _NormalScale);
    float3 normal2 = AAAWUnpackNormalAG(normalSample2, _NormalScale * 0.8);
    
    return AAAWBlendNormal(normal1, normal2);
}

float AAAWBeerLambert(float extinction, float distance)
{
    return exp(-extinction * distance);
}

float3 AAAWBeerLambert3(float3 extinction, float distance)
{
    return exp(-extinction * distance);
}

float AAAWGetOpticalDepth(float extinction, float distance)
{
    return extinction * distance;
}

float3 AAAWGetOpticalDepth3(float3 extinction, float distance)
{
    return extinction * distance;
}

float AAAWGetScatteringAlbedo(float scatterCoeff, float extinctionCoeff)
{
    return scatterCoeff / max(extinctionCoeff, 1e-6);
}

float3 AAAWGetScatteringAlbedo3(float3 scatterCoeff, float3 extinctionCoeff)
{
    return scatterCoeff / max(extinctionCoeff, 1e-6);
}

float AAAWExponentialStep(float t, float k, float n)
{
    float denom = exp(k) - 1.0;
    return (exp(k * t) - 1.0) / denom;
}

float AAAWExponentialStepSize(float t, float k, float n)
{
    float denom = exp(k) - 1.0;
    return k * exp(k * t) / (denom * n);
}

float AAAWInterleavedGradientNoise(float2 screenPos)
{
    float3 magic = float3(0.06711056, 0.00583715, 52.9829189);
    return frac(magic.z * frac(dot(screenPos, magic.xy)));
}

float3 AAAWScreenSpaceDither(float2 screenPos)
{
    float dither = AAAWInterleavedGradientNoise(screenPos);
    return float3(dither, dither, dither) * 0.0078125;
}

float AAAWGetLinearEyeDepth(float2 uv)
{
    float rawDepth = SampleSceneDepth(uv);
    return LinearEyeDepth(rawDepth, _ZBufferParams);
}

float AAAWGetLinearEyeDepthFromRaw(float rawDepth)
{
    return LinearEyeDepth(rawDepth, _ZBufferParams);
}

float3 AAAWGetWorldPositionFromDepth(float2 uv, float linearEyeDepth)
{
    float4 positionNDC = float4(uv * 2.0 - 1.0, 1.0, 1.0);
    float4 positionVS = mul(UNITY_MATRIX_I_P, positionNDC);
    positionVS /= positionVS.w;
    float4 positionWS = mul(UNITY_MATRIX_I_V, positionVS);
    return positionWS.xyz;
}

struct AAAWWaterSurfaceData
{
    float3 normalWS;
    float3 positionWS;
    float thickness;
    float depth;
    float foam;
};

struct AAAWWaterLightingData
{
    float3 positionWS;
    float3 viewDirWS;
    float3 normalWS;
    float2 screenUV;
    float linearEyeDepth;
    float rawDepth;
};

AAAWWaterLightingData AAAWInitializeWaterLightingData(float3 positionWS, float3 viewDirWS, float3 normalWS, float2 screenUV)
{
    AAAWWaterLightingData data;
    data.positionWS = positionWS;
    data.viewDirWS = viewDirWS;
    data.normalWS = normalWS;
    data.screenUV = screenUV;
    data.linearEyeDepth = AAAWGetLinearEyeDepth(screenUV);
    data.rawDepth = SampleSceneDepth(screenUV);
    return data;
}

AAAWWaterSurfaceData AAAWInitializeWaterSurfaceData(float3 normalWS, float3 positionWS, float thickness, float depth)
{
    AAAWWaterSurfaceData data;
    data.normalWS = normalWS;
    data.positionWS = positionWS;
    data.thickness = thickness;
    data.depth = depth;
    data.foam = 0.0;
    return data;
}

#endif
