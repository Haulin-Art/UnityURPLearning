// PBR_BRDF_Library.hlsl
// URP Cook-Torrance BRDF 函数库
// 使用方法: 在URP着色器中包含此文件，调用BRDF_CookTorrance函数

#ifndef PBR_BRDF_LIBRARY_INCLUDED
#define PBR_BRDF_LIBRARY_INCLUDED

// 数学常量 - 使用条件编译避免重复定义
#ifndef PI
#define PI 3.14159265359
#endif

#ifndef INV_PI
#define INV_PI 0.31830988618
#endif

#ifndef EPSILON
#define EPSILON 1e-6
#endif

// 结构体定义 - 避免与URP内置结构体冲突
#ifndef BRDF_DATA_DEFINED
#define BRDF_DATA_DEFINED
struct PBR_BRDF_Data
{
    float3 albedo;          // 基础颜色/反照率
    float3 normal;         // 法线向量(世界空间)
    float3 viewDir;        // 视线方向(世界空间)
    float3 lightDir;       // 光线方向(世界空间)
    float roughness;       // 粗糙度 (0-1)
    float metallic;        // 金属度 (0-1)
    float3 F0;            // 基础反射率(Fresnel反射率在0°入射角)
    float3 irradiance;    // 辐照度/光照颜色
    float occlusion;      // 环境光遮蔽
    float3 worldPos;      // 世界坐标(可选)
};
#endif

#ifndef BRDF_RESULT_DEFINED
#define BRDF_RESULT_DEFINED
struct PBR_BRDF_Result
{
    float3 diffuse;       // 漫反射分量
    float3 specular;      // 镜面反射分量
    float3 radiance;      // 总辐射度
};
#endif

// ==================== 工具函数 ====================

// 将粗糙度转换为α参数(用于NDF)
float PBR_RoughnessToAlpha(float roughness)
{
    return roughness * roughness;
}

// 将粗糙度转换为α参数(平方形式，更常用)
float PBR_RoughnessToAlphaSq(float roughness)
{
    float alpha = roughness * roughness;
    return alpha * alpha;
}

// 将向量夹在安全范围内
float3 PBR_SafeNormalize(float3 v)
{
    float sqrLen = max(dot(v, v), EPSILON);
    return v * rsqrt(sqrLen);
}

// 计算半程向量(Half Vector)
float3 PBR_HalfVector(float3 viewDir, float3 lightDir)
{
    return normalize(viewDir + lightDir);
}

// 计算Fresnel反射的Schlick近似
float3 PBR_FresnelSchlick(float cosTheta, float3 F0)
{
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

// 计算Fresnel反射的Schlick近似(带粗糙度修正)
float3 PBR_FresnelSchlickRoughness(float cosTheta, float3 F0, float roughness)
{
    return F0 + (max(float3(1.0 - roughness, 1.0 - roughness, 1.0 - roughness), F0) - F0) * pow(1.0 - cosTheta, 5.0);
}

// ==================== 法线分布函数(NDF) ====================

// GGX/Trowbridge-Reitz 法线分布函数
float PBR_NDF_GGX(float NdotH, float roughness)
{
    float alpha = PBR_RoughnessToAlphaSq(roughness);
    float NdotH2 = NdotH * NdotH;
    
    float denom = (NdotH2 * (alpha - 1.0) + 1.0);
    denom = PI * denom * denom;
    
    return alpha / max(denom, EPSILON);
}

// Beckmann 法线分布函数
float PBR_NDF_Beckmann(float NdotH, float roughness)
{
    float alpha = PBR_RoughnessToAlpha(roughness);
    float NdotH2 = NdotH * NdotH;
    
    float exponent = (NdotH2 - 1.0) / (alpha * alpha * NdotH2);
    float denom = PI * alpha * alpha * NdotH2 * NdotH2;
    
    return exp(exponent) / max(denom, EPSILON);
}

// ==================== 几何函数(G) ====================

// 计算Smith几何遮蔽函数的单项(G1)
float PBR_GeometrySchlickGGX(float NdotV, float roughness)
{
    // 直接光照的k计算方式
    float k = (roughness + 1.0) * (roughness + 1.0) / 8.0;
    
    float denom = NdotV * (1.0 - k) + k;
    return NdotV / max(denom, EPSILON);
}

// 计算Smith几何遮蔽函数的单项(G1) - 针对IBL
float PBR_GeometrySmithIBL(float NdotV, float roughness)
{
    // IBL的k计算方式
    float k = roughness * roughness / 2.0;
    
    float denom = NdotV * (1.0 - k) + k;
    return NdotV / max(denom, EPSILON);
}

// Smith联合几何函数(用于直接光照)
float PBR_GeometrySmith(float NdotV, float NdotL, float roughness)
{
    float ggx1 = PBR_GeometrySchlickGGX(NdotV, roughness);
    float ggx2 = PBR_GeometrySchlickGGX(NdotL, roughness);
    return ggx1 * ggx2;
}

// ==================== BRDF核心计算 ====================

// 计算微表面BRDF的镜面反射部分(Cook-Torrance模型)
float3 PBR_Specular_CookTorrance(float3 F, float D, float G, float NdotV, float NdotL)
{
    float denominator = 4.0 * NdotV * NdotL;
    return (D * F * G) / max(denominator, EPSILON);
}

// 计算漫反射BRDF(Lambert)
float3 PBR_Diffuse_Lambert(float3 albedo)
{
    return albedo * INV_PI;
}

// 计算漫反射BRDF(Disney模型)
float3 PBR_Diffuse_Disney(float3 albedo, float NdotV, float NdotL, float LdotH, float roughness)
{
    float energyBias = lerp(0.0, 0.5, roughness);
    float energyFactor = lerp(1.0, 1.0 / 1.51, roughness);
    float fd90 = energyBias + 2.0 * LdotH * LdotH * roughness;
    
    float lightScatter = 1.0 + (fd90 - 1.0) * pow(1.0 - NdotL, 5.0);
    float viewScatter = 1.0 + (fd90 - 1.0) * pow(1.0 - NdotV, 5.0);
    
    return albedo * lightScatter * viewScatter * energyFactor * INV_PI;
}

// ==================== 主BRDF计算函数 ====================

// 完整的Cook-Torrance BRDF计算
PBR_BRDF_Result BRDF_CookTorrance(PBR_BRDF_Data data, bool useDisneyDiffuse = false, bool useBeckmannNDF = false)
{
    PBR_BRDF_Result result = (PBR_BRDF_Result)0;
    
    // 确保向量归一化
    data.normal = PBR_SafeNormalize(data.normal);
    data.viewDir = PBR_SafeNormalize(data.viewDir);
    data.lightDir = PBR_SafeNormalize(data.lightDir);
    
    // 计算中间向量
    float3 halfVec = PBR_HalfVector(data.viewDir, data.lightDir);
    
    // 计算点积
    float NdotV = max(dot(data.normal, data.viewDir), 0.0);
    float NdotL = max(dot(data.normal, data.lightDir), 0.0);
    float NdotH = max(dot(data.normal, halfVec), 0.0);
    float VdotH = max(dot(data.viewDir, halfVec), 0.0);
    float LdotH = max(dot(data.lightDir, halfVec), 0.0);
    
    // 如果法线与光线或视线方向反向，则没有光照
    if (NdotL <= 0.0 || NdotV <= 0.0)
    {
        return result;
    }
    
    // 计算基础反射率(F0) - 如果未提供则根据金属度计算
    if (length(data.F0) < EPSILON)
    {
        // 电介质基础反射率
        float3 dielectricF0 = float3(0.04, 0.04, 0.04);
        // 根据金属度在电介质和金属之间插值
        data.F0 = lerp(dielectricF0, data.albedo, data.metallic);
    }
    
    // 计算Fresnel项(F)
    float3 F = PBR_FresnelSchlick(LdotH, data.F0);
    
    // 计算法线分布函数(D)
    float D = 0.0;
    if (useBeckmannNDF)
    {
        D = PBR_NDF_Beckmann(NdotH, data.roughness);
    }
    else
    {
        D = PBR_NDF_GGX(NdotH, data.roughness);
    }
    
    // 计算几何函数(G)
    float G = PBR_GeometrySmith(NdotV, NdotL, data.roughness);
    
    // 计算镜面反射BRDF
    float3 specularBRDF = PBR_Specular_CookTorrance(F, D, G, NdotV, NdotL);
    
    // 计算漫反射BRDF
    float3 kD = float3(1.0, 1.0, 1.0) - F; // 能量守恒
    kD *= 1.0 - data.metallic; // 金属没有漫反射
    
    float3 diffuseBRDF = float3(0.0, 0.0, 0.0);
    if (useDisneyDiffuse)
    {
        diffuseBRDF = PBR_Diffuse_Disney(data.albedo, NdotV, NdotL, LdotH, data.roughness);
    }
    else
    {
        diffuseBRDF = PBR_Diffuse_Lambert(data.albedo);
    }
    
    // 计算最终辐射度
    result.diffuse = data.irradiance * NdotL * kD * diffuseBRDF;
    result.specular = data.irradiance * NdotL * specularBRDF;
    result.radiance = (result.diffuse + result.specular) * data.occlusion;
    
    return result;
}

// 简化版本的主函数(使用默认参数)
PBR_BRDF_Result BRDF_CookTorrance_Simple(
    float3 albedo,
    float3 normal,
    float3 viewDir,
    float3 lightDir,
    float3 irradiance,
    float roughness,
    float metallic,
    float occlusion = 1.0
)
{
    PBR_BRDF_Data data;
    data.albedo = albedo;
    data.normal = normal;
    data.viewDir = viewDir;
    data.lightDir = lightDir;
    data.irradiance = irradiance;
    data.roughness = roughness;
    data.metallic = metallic;
    data.occlusion = occlusion;
    data.F0 = float3(0.0, 0.0, 0.0); // 自动计算
    data.worldPos = float3(0.0, 0.0, 0.0);
    
    return BRDF_CookTorrance(data, false, false);
}

// 完整版本的主函数(包含所有参数)
PBR_BRDF_Result BRDF_CookTorrance_Full(
    float3 albedo,
    float3 normal,
    float3 viewDir,
    float3 lightDir,
    float3 irradiance,
    float roughness,
    float metallic,
    float3 F0,
    float occlusion,
    float3 worldPos,
    bool useDisneyDiffuse,
    bool useBeckmannNDF
)
{
    PBR_BRDF_Data data;
    data.albedo = albedo;
    data.normal = normal;
    data.viewDir = viewDir;
    data.lightDir = lightDir;
    data.irradiance = irradiance;
    data.roughness = roughness;
    data.metallic = metallic;
    data.F0 = F0;
    data.occlusion = occlusion;
    data.worldPos = worldPos;
    
    return BRDF_CookTorrance(data, useDisneyDiffuse, useBeckmannNDF);
}

#endif // PBR_BRDF_LIBRARY_INCLUDED