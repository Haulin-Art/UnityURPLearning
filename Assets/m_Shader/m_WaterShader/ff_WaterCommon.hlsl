#ifndef FF_WATER_COMMON_INCLUDED
#define FF_WATER_COMMON_INCLUDED

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

#define FF_PI 3.14159265359

float FFLuminance(float3 color)
{
    return dot(color, float3(0.2126729, 0.7151522, 0.0721750));
}

float FFPow5(float x)
{
    float x2 = x * x;
    return x2 * x2 * x;
}

float3 FFPow5(float3 x)
{
    float3 x2 = x * x;
    return x2 * x2 * x;
}

float FFSquare(float x)
{
    return x * x;
}

float3 FFSafeNormalize(float3 v)
{
    float len = length(v);
    return len > 1e-6 ? v / len : float3(0, 1, 0);
}

float FFGetLinearEyeDepth(float2 uv)
{
    float rawDepth = SampleSceneDepth(uv);
    return LinearEyeDepth(rawDepth, _ZBufferParams);
}

float FFGetLinearEyeDepthFromRaw(float rawDepth)
{
    return LinearEyeDepth(rawDepth, _ZBufferParams);
}

float3 FFGetWorldPositionFromDepth(float2 uv, float linearEyeDepth)
{
    float4 positionNDC = float4(uv * 2.0 - 1.0, 1.0, 1.0);
    float4 positionVS = mul(UNITY_MATRIX_I_P, positionNDC);
    positionVS /= positionVS.w;
    float4 positionWS = mul(UNITY_MATRIX_I_V, positionVS);
    return positionWS.xyz;
}

float FFRemap(float value, float inMin, float inMax, float outMin, float outMax)
{
    return outMin + (value - inMin) * (outMax - outMin) / (inMax - inMin);
}

float FFRemap01(float value, float inMin, float inMax)
{
    return saturate((value - inMin) / (inMax - inMin));
}

float3 FFBlendNormal(float3 n1, float3 n2)
{
    float3 t = n1 * float3(2, 2, 2) + float3(-1, -1, 0);
    float3 u = n2 * float3(2, 2, 2) + float3(-1, -1, 0);
    float3 r = t * dot(t, u) - u * t.z;
    return normalize(r);
}

float FFSampleBlueNoise(float2 screenPos, float time)
{
    float2 uv = screenPos + time * 0.1;
    return frac(sin(dot(uv, float2(12.9898, 78.233))) * 43758.5453);
}

float FFSampleDither(float2 screenPos, float time)
{
    return FFSampleBlueNoise(screenPos, time);
}

#endif
