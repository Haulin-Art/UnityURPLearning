#ifndef BSDF_SSS_INCLUDED
#define BSDF_SSS_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"


struct BSDFParameters
{
    float3 normalWS;
    float3 viewDirWS;
    float thickness;
    float3 lightDir;
    float3 lightColor;
    float SSSIntensity;
    float SSSDistortion;
    float SSSPower;
    float SSSScale;
    float4 SSSColor;
};

float3 BSDF_SSS_Calculate(BSDFParameters para)
{  
    float3 H = normalize(para.lightDir + para.normalWS * para.SSSDistortion);
    float VdotH = pow(saturate(dot(para.viewDirWS, -H)), para.SSSPower);
    
    float3 sss = para.SSSColor.rgb * para.lightColor * VdotH * para.SSSIntensity * para.thickness * para.SSSScale;
    
    return sss;
}


float3 BSDF_SSS_Improved(BSDFParameters para)
{
    float3 H = normalize(para.lightDir + para.normalWS * para.SSSDistortion);
    float VdotH = pow(saturate(dot(para.viewDirWS, -H)), para.SSSPower);
    
    float NdotL = saturate(dot(para.normalWS, para.lightDir));
    float wrapLight = saturate((NdotL + 0.5) / 1.5);
    
    float3 frontLight = para.lightColor * NdotL;
    float3 backLight = para.SSSColor.rgb * para.lightColor * VdotH * para.thickness * para.SSSScale;
    
    return frontLight + backLight * para.SSSIntensity * (1.0 - NdotL);
}

#endif
