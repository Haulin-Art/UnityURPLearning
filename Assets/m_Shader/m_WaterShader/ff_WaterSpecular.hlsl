/*
 * ═══════════════════════════════════════════════════════════════════════════
 * FluidFlux Water Specular - 水体高光模块
 * ═══════════════════════════════════════════════════════════════════════════
 * 
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │                           原理框架                                      │
 * └─────────────────────────────────────────────────────────────────────────┘
 * 
 * 一、高光反射概述
 * ─────────────────────────────────────────────────────────────────────────
 * 高光是光源在光滑表面上形成的明亮反射点。对于水面，高光主要来自：
 *   - 太阳光的直接反射
 *   - 环境光的镜面反射
 * 
 * 高光的特点：
 *   - 强度集中：只在特定角度可见
 *   - 颜色纯白：通常使用光源颜色
 *   - 形状尖锐：水面高光通常很锐利
 * 
 * 二、高光模型对比
 * ─────────────────────────────────────────────────────────────────────────
 * 
 * ┌───────────────────────────────────────────────────────────────────────┐
 * │                     高光模型对比                                       │
 * ├───────────────────────────────────────────────────────────────────────┤
 * │ 模型          │ 特点                │ 适用场景           │ 性能      │
 * ├───────────────┼─────────────────────┼────────────────────┼───────────┤
 * │ Phong         │ 经典，反射向量计算   │ 教学演示           │ 快        │
 * │ Blinn-Phong   │ 半角向量，更稳定     │ 通用场景           │ 快        │
 * │ GGX/PBR       │ 物理正确，能量守恒   │ 高质量渲染         │ 慢        │
 * └───────────────────────────────────────────────────────────────────────┘
 * 
 * 三、Blinn-Phong 模型
 * ─────────────────────────────────────────────────────────────────────────
 * 使用半角向量 H = normalize(L + V) 计算高光：
 * 
 *   specular = pow(saturate(N·H), power)
 * 
 * 优点：
 *   - 计算简单高效
 *   - 在掠射角时效果更稳定
 *   - 适合实时渲染
 * 
 * ┌───────────────────────────────────────────────────────────────────────┐
 * │                    Blinn-Phong 几何示意                                │
 * │                                                                       │
 * │              L (光源方向)                                              │
 * │               ↖                                                       │
 * │                \                                                      │
 * │                 \  H (半角向量)                                        │
 * │                  \ ↗                                                  │
 * │                   ●──────── N (法线)                                  │
 * │                  /                                                    │
 * │                 /                                                     │
 * │                ↙                                                      │
 * │              V (视线方向)                                              │
 * │                                                                       │
 * │    H = normalize(L + V)                                               │
 * │    specular = pow(max(0, N·H), power)                                 │
 * └───────────────────────────────────────────────────────────────────────┘
 * 
 * 四、GGX/PBR 模型
 * ─────────────────────────────────────────────────────────────────────────
 * 基于物理的渲染模型，包含三个组成部分：
 * 
 *   1. 法线分布函数 (D) - GGX/Trowbridge-Reitz
 *      描述微表面法线分布，决定高光形状
 * 
 *   2. 几何遮蔽函数 (G) - Smith/GGX
 *      描述微表面自遮挡，影响高光强度
 * 
 *   3. 菲涅尔项 (F) - Schlick 近似
 *      描述反射率随角度变化
 * 
 * 最终高光：
 *   specular = (D * G * F) / (4 * N·V * N·L)
 * 
 * 五、粗糙度影响
 * ─────────────────────────────────────────────────────────────────────────
 * 粗糙度控制高光的锐度和范围：
 * 
 *   - roughness = 0：完全镜面反射，高光极尖锐
 *   - roughness = 0.3：水面典型值，高光较尖锐
 *   - roughness = 1：完全粗糙，高光非常分散
 * 
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │                           使用说明                                      │
 * └─────────────────────────────────────────────────────────────────────────┘
 * 
 * 1. 基本使用流程：
 *    // Blinn-Phong 高光
 *    float3 specular = FFCalculateSpecularBlinnPhong(
 *        normalWS, viewDirWS, lightDir, lightColor,
 *        specularPower, intensity
 *    );
 *    
 *    // GGX 高光（推荐）
 *    float3 specular = FFCalculateSpecularGGXSimple(
 *        normalWS, viewDirWS, lightDir, lightColor,
 *        roughness, intensity
 *    );
 * 
 * 2. 参数说明：
 *    - normalWS       : 世界空间法线
 *    - viewDirWS      : 世界空间视线方向
 *    - lightDir       : 光源方向
 *    - lightColor     : 光源颜色
 *    - specularPower  : Blinn-Phong 高光锐度 [8, 256]
 *    - roughness      : GGX 粗糙度 [0, 1]
 *    - intensity      : 高光强度 [0, 3]
 * 
 * 3. 参数建议：
 *    - 水面 specularPower：64-128
 *    - 水面 roughness：0.1-0.4
 *    - 水面 intensity：0.5-2.0
 * 
 * 4. 性能建议：
 *    - 移动端推荐 Blinn-Phong
 *    - PC端推荐 GGX
 *    - 多光源场景注意性能开销
 * 
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │                           依赖关系                                      │
 * └─────────────────────────────────────────────────────────────────────────┘
 * 
 * ff_WaterSpecular.hlsl
 *     └── ff_WaterCommon.hlsl    (基础工具函数、PI常量)
 * 
 * 被以下文件引用：
 *     └── water.shader          (主着色器)
 * 
 * ═══════════════════════════════════════════════════════════════════════════
 */

#ifndef FF_WATER_SPECULAR_INCLUDED
#define FF_WATER_SPECULAR_INCLUDED

#include "ff_WaterCommon.hlsl"

// ═══════════════════════════════════════════════════════════════════════════
// 经典高光模型
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFCalculateSpecularBlinnPhong - Blinn-Phong 高光模型
 * 
 * 使用半角向量计算高光，比 Phong 模型更稳定。
 * 适合实时渲染，计算效率高。
 * 
 * 参数：
 *   normalWS      - 世界空间法线
 *   viewDirWS     - 世界空间视线方向
 *   lightDir      - 光源方向
 *   lightColor    - 光源颜色
 *   specularPower - 高光锐度（值越大越尖锐）
 *   intensity     - 高光强度
 * 
 * 返回：
 *   高光颜色
 * 
 * 公式：
 *   H = normalize(L + V)
 *   specular = lightColor * pow(saturate(N·H), power) * intensity
 */
float3 FFCalculateSpecularBlinnPhong(
    float3 normalWS,
    float3 viewDirWS,
    float3 lightDir,
    float3 lightColor,
    float specularPower,
    float intensity)
{
    // 计算半角向量
    float3 halfDir = normalize(lightDir + viewDirWS);
    // 计算高光
    float NdotH = saturate(dot(normalWS, halfDir));
    float specular = pow(NdotH, specularPower);
    return lightColor * specular * intensity;
}

/*
 * FFCalculateSpecularPhong - Phong 高光模型
 * 
 * 经典 Phong 模型，使用反射向量计算高光。
 * 在掠射角时可能出现高光断裂。
 * 
 * 参数：
 *   normalWS      - 世界空间法线
 *   viewDirWS     - 世界空间视线方向
 *   lightDir      - 光源方向
 *   lightColor    - 光源颜色
 *   specularPower - 高光锐度
 *   intensity     - 高光强度
 * 
 * 返回：
 *   高光颜色
 * 
 * 公式：
 *   R = reflect(-L, N)
 *   specular = lightColor * pow(saturate(R·V), power) * intensity
 */
float3 FFCalculateSpecularPhong(
    float3 normalWS,
    float3 viewDirWS,
    float3 lightDir,
    float3 lightColor,
    float specularPower,
    float intensity)
{
    // 计算反射方向
    float3 reflectDir = reflect(-lightDir, normalWS);
    // 计算高光
    float RdotV = saturate(dot(reflectDir, viewDirWS));
    float specular = pow(RdotV, specularPower);
    return lightColor * specular * intensity;
}

// ═══════════════════════════════════════════════════════════════════════════
// GGX/PBR 高光组件
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFNormalDistributionGGX - GGX 法线分布函数
 * 
 * 描述微表面法线分布，决定高光的形状和大小。
 * 使用 Trowbridge-Reitz GGX 分布。
 * 
 * 参数：
 *   NdotH     - 法线与半角向量的点积
 *   roughness - 粗糙度 [0, 1]
 * 
 * 返回：
 *   法线分布值
 * 
 * 公式：
 *   D(h) = α² / (π * ((n·h)² * (α² - 1) + 1)²)
 * 
 * 其中 α = roughness²
 */
float FFNormalDistributionGGX(float NdotH, float roughness)
{
    // 计算粗糙度的平方
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH2 = NdotH * NdotH;
    
    // 计算分母
    float denom = NdotH2 * (a2 - 1.0) + 1.0;
    denom = FF_PI * denom * denom;
    
    return a2 / denom;
}

/*
 * FFGeometrySchlickGGX - Schlick-GGX 几何遮蔽函数
 * 
 * 描述微表面的自遮挡效应。
 * 单方向的几何项计算。
 * 
 * 参数：
 *   NdotV     - 法线与视线方向的点积
 *   roughness - 粗糙度
 * 
 * 返回：
 *   几何遮蔽值
 * 
 * 公式：
 *   k = (roughness + 1)² / 8  (用于直接光照)
 *   G(v) = NdotV / (NdotV * (1 - k) + k)
 */
float FFGeometrySchlickGGX(float NdotV, float roughness)
{
    // 计算重映射系数（用于直接光照）
    float r = roughness + 1.0;
    float k = (r * r) / 8.0;
    
    return NdotV / (NdotV * (1.0 - k) + k);
}

/*
 * FFGeometrySmith - Smith 几何函数
 * 
 * 组合两个方向的几何遮蔽，得到完整的几何项。
 * 
 * 参数：
 *   NdotV     - 法线与视线方向的点积
 *   NdotL     - 法线与光源方向的点积
 *   roughness - 粗糙度
 * 
 * 返回：
 *   完整几何项
 * 
 * 公式：
 *   G = G1(V) * G1(L)
 */
float FFGeometrySmith(float NdotV, float NdotL, float roughness)
{
    // 分别计算视线方向和光源方向的几何项
    float ggx1 = FFGeometrySchlickGGX(NdotV, roughness);
    float ggx2 = FFGeometrySchlickGGX(NdotL, roughness);
    return ggx1 * ggx2;
}

/*
 * FFFresnelSchlickRoughness - 带粗糙度的 Schlick 菲涅尔近似
 * 
 * 考虑粗糙度影响的菲涅尔计算。
 * 粗糙度越高，菲涅尔效果越弱。
 * 
 * 参数：
 *   f0        - 基础反射率（垂直入射时的反射率）
 *   cosTheta  - 角度的余弦值
 *   roughness - 粗糙度
 * 
 * 返回：
 *   菲涅尔反射率
 */
float3 FFFresnelSchlickRoughness(float3 f0, float cosTheta, float roughness)
{
    float t = 1.0 - cosTheta;
    float t2 = t * t;
    float t5 = t2 * t2 * t;
    float3 oneMinusRoughness = 1.0 - roughness;
    return f0 + (max(oneMinusRoughness, f0) - f0) * t5;
}

// ═══════════════════════════════════════════════════════════════════════════
// GGX 高光计算
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFCalculateSpecularGGX - 完整 GGX 高光计算
 * 
 * 完整的基于物理的高光计算，包含 D、G、F 三项。
 * 适合高质量渲染场景。
 * 
 * 参数：
 *   normalWS   - 世界空间法线
 *   viewDirWS  - 世界空间视线方向
 *   lightDir   - 光源方向
 *   lightColor - 光源颜色
 *   roughness  - 粗糙度 [0, 1]
 *   f0         - 基础反射率（水的 F0 ≈ 0.02）
 *   intensity  - 高光强度
 * 
 * 返回：
 *   高光颜色
 * 
 * 公式：
 *   specular = (D * G * F) / (4 * N·V * N·L) * lightColor * intensity * N·L
 */
float3 FFCalculateSpecularGGX(
    float3 normalWS,
    float3 viewDirWS,
    float3 lightDir,
    float3 lightColor,
    float roughness,
    float3 f0,
    float intensity)
{
    // 计算半角向量
    float3 halfDir = normalize(lightDir + viewDirWS);
    
    // 计算各项点积
    float NdotH = saturate(dot(normalWS, halfDir));
    float NdotV = saturate(dot(normalWS, viewDirWS));
    float NdotL = saturate(dot(normalWS, lightDir));
    float HdotV = saturate(dot(halfDir, viewDirWS));
    
    // 计算 D、G、F 三项
    float D = FFNormalDistributionGGX(NdotH, roughness);
    float G = FFGeometrySmith(NdotV, NdotL, roughness);
    float3 F = FFFresnelSchlickRoughness(f0, HdotV, roughness);
    
    // 计算高光
    float3 numerator = D * G * F;
    float denominator = 4.0 * NdotV * NdotL + 0.0001;  // 避免除零
    float3 specular = numerator / denominator;
    
    return specular * lightColor * intensity * NdotL;
}

/*
 * FFCalculateSpecularGGXSimple - 简化 GGX 高光计算
 * 
 * 使用水的默认 F0 值 (0.02) 的简化版本。
 * 适合大多数水体渲染场景。
 * 
 * 参数：
 *   normalWS   - 世界空间法线
 *   viewDirWS  - 世界空间视线方向
 *   lightDir   - 光源方向
 *   lightColor - 光源颜色
 *   roughness  - 粗糙度
 *   intensity  - 高光强度
 * 
 * 返回：
 *   高光颜色
 */
float3 FFCalculateSpecularGGXSimple(
    float3 normalWS,
    float3 viewDirWS,
    float3 lightDir,
    float3 lightColor,
    float roughness,
    float intensity)
{
    // 水的基础反射率 F0 ≈ 0.02
    float3 f0 = float3(0.02, 0.02, 0.02);
    return FFCalculateSpecularGGX(normalWS, viewDirWS, lightDir, lightColor, roughness, f0, intensity);
}

// ═══════════════════════════════════════════════════════════════════════════
// 便捷函数
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFCalculateWaterSpecular - 水体高光计算（默认使用 Blinn-Phong）
 * 
 * 便捷函数，默认使用 Blinn-Phong 模型。
 * 
 * 参数：
 *   normalWS      - 世界空间法线
 *   viewDirWS     - 世界空间视线方向
 *   lightDir      - 光源方向
 *   lightColor    - 光源颜色
 *   specularPower - 高光锐度
 *   intensity     - 高光强度
 * 
 * 返回：
 *   高光颜色
 */
float3 FFCalculateWaterSpecular(
    float3 normalWS,
    float3 viewDirWS,
    float3 lightDir,
    float3 lightColor,
    float specularPower,
    float intensity)
{
    return FFCalculateSpecularBlinnPhong(normalWS, viewDirWS, lightDir, lightColor, specularPower, intensity);
}

/*
 * FFCalculateSpecularMultiLight - 多光源高光计算
 * 
 * 计算主光源和附加光源的高光总和。
 * 附加光源的高光强度减半。
 * 
 * 参数：
 *   normalWS      - 世界空间法线
 *   viewDirWS     - 世界空间视线方向
 *   specularPower - 高光锐度
 *   intensity     - 高光强度
 * 
 * 返回：
 *   总高光颜色
 */
float3 FFCalculateSpecularMultiLight(
    float3 normalWS,
    float3 viewDirWS,
    float specularPower,
    float intensity)
{
    float3 totalSpecular = 0;
    
    // 计算主光源高光
    Light mainLight = GetMainLight();
    totalSpecular += FFCalculateSpecularBlinnPhong(
        normalWS, viewDirWS, mainLight.direction, 
        mainLight.color, specularPower, intensity
    );
    
    // 计算附加光源高光
#ifdef _ADDITIONAL_LIGHTS
    int additionalLightsCount = GetAdditionalLightsCount();
    for (int i = 0; i < additionalLightsCount; i++)
    {
        Light light = GetAdditionalLight(i, float3(0, 0, 0));
        // 附加光源强度减半
        totalSpecular += FFCalculateSpecularBlinnPhong(
            normalWS, viewDirWS, light.direction,
            light.color, specularPower, intensity * 0.5
        );
    }
#endif
    
    return totalSpecular;
}

// ═══════════════════════════════════════════════════════════════════════════
// 高级功能
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFGetSpecularDominantDirection - 获取高光主导方向
 * 
 * 根据视角计算高光的主导反射方向。
 * 用于某些需要预计算反射方向的情况。
 * 
 * 参数：
 *   normalWS  - 世界空间法线
 *   viewDirWS - 世界空间视线方向
 * 
 * 返回：
 *   主导反射方向
 */
float3 FFGetSpecularDominantDirection(float3 normalWS, float3 viewDirWS)
{
    float NdotV = saturate(dot(normalWS, viewDirWS));
    float3 reflectDir = reflect(-viewDirWS, normalWS);
    // 根据视角插值法线和反射方向
    float lerpFactor = pow(1.0 - NdotV, 2.0) * 0.5;
    return normalize(lerp(normalWS, reflectDir, lerpFactor));
}

/*
 * FFBlendSpecularEnv - 混合高光与环境反射
 * 
 * 将直接高光与环境反射混合。
 * 
 * 参数：
 *   specular     - 直接高光
 *   envReflection - 环境反射
 *   fresnel      - 菲涅尔项
 *   envStrength  - 环境强度
 * 
 * 返回：
 *   混合后的高光
 */
float3 FFBlendSpecularEnv(
    float3 specular,
    float3 envReflection,
    float fresnel,
    float envStrength)
{
    return specular + envReflection * fresnel * envStrength;
}

/*
 * FFSampleEnvReflectionWithFresnel - 带菲涅尔的环境反射采样
 * 
 * 采样环境反射并应用菲涅尔效果。
 * 
 * 参数：
 *   reflectDir   - 反射方向
 *   roughness    - 粗糙度
 *   envStrength  - 环境强度
 *   fresnel      - 菲涅尔项
 * 
 * 返回：
 *   环境反射颜色
 */
float3 FFSampleEnvReflectionWithFresnel(
    float3 reflectDir,
    float roughness,
    float envStrength,
    float fresnel)
{
    float perceptualRoughness = roughness;
    float3 envColor = GlossyEnvironmentReflection(reflectDir, perceptualRoughness, 1.0);
    return envColor * envStrength * fresnel;
}

/*
 * FFComputeFullSpecular - 计算完整高光（直接+间接）
 * 
 * 计算直接高光和间接高光（环境反射）的总和。
 * 
 * 参数：
 *   normalWS              - 世界空间法线
 *   viewDirWS             - 世界空间视线方向
 *   lightDir              - 光源方向
 *   lightColor            - 光源颜色
 *   specularPower         - 高光锐度
 *   specularIntensity     - 高光强度
 *   roughness             - 粗糙度
 *   envReflectionStrength - 环境反射强度
 *   fresnel               - 菲涅尔项
 * 
 * 返回：
 *   完整高光颜色
 */
float3 FFComputeFullSpecular(
    float3 normalWS,
    float3 viewDirWS,
    float3 lightDir,
    float3 lightColor,
    float specularPower,
    float specularIntensity,
    float roughness,
    float envReflectionStrength,
    float fresnel)
{
    // 计算直接高光
    float3 directSpecular = FFCalculateSpecularBlinnPhong(
        normalWS, viewDirWS, lightDir, lightColor, 
        specularPower, specularIntensity
    );
    
    // 计算间接高光（环境反射）
    float3 reflectDir = reflect(-viewDirWS, normalWS);
    float3 envReflection = GlossyEnvironmentReflection(reflectDir, roughness, 1.0);
    float3 indirectSpecular = envReflection * envReflectionStrength * fresnel;
    
    return directSpecular + indirectSpecular;
}

#endif
