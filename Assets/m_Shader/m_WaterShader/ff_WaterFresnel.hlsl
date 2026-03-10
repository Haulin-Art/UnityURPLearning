/*
 * ═══════════════════════════════════════════════════════════════════════════
 * FluidFlux Water Fresnel - 水体菲涅尔效果模块
 * ═══════════════════════════════════════════════════════════════════════════
 * 
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │                           原理框架                                      │
 * └─────────────────────────────────────────────────────────────────────────┘
 * 
 * 一、菲涅尔效应概述
 * ─────────────────────────────────────────────────────────────────────────
 * 菲涅尔效应描述了光在两种介质界面上的反射和透射比例。
 * 当我们观察水面时：
 *   - 正视（垂直俯视）：看到更多水下的内容（透射强，反射弱）
 *   - 掠视（接近平视）：看到更多水面反射（反射强，透射弱）
 * 
 * 这是真实世界中常见的光学现象，对于真实感水体渲染至关重要。
 * 
 * 二、物理原理
 * ─────────────────────────────────────────────────────────────────────────
 * 
 * ┌───────────────────────────────────────────────────────────────────────┐
 * │                     菲涅尔效应示意                                     │
 * │                                                                       │
 * │    入射光 ────────┬──────── 反射光                                    │
 * │                  │                                                    │
 * │                  │ θᵢ                                                 │
 * │                  │                                                    │
 * │    ══════════════╪═════════════ 界面                                 │
 * │                  │                                                    │
 * │                  │ θₜ                                                 │
 * │                  │                                                    │
 * │              透射光                                                   │
 * │                                                                       │
 * │    n₁ (空气 ≈ 1.0)                                                    │
 * │    n₂ (水 ≈ 1.33)                                                     │
 * │                                                                       │
 * │    反射率 R = f(θᵢ, n₁, n₂)                                          │
 * │    透射率 T = 1 - R                                                   │
 * └───────────────────────────────────────────────────────────────────────┘
 * 
 * 完整菲涅尔方程（考虑偏振光）：
 * 
 *   r_s = |(n₁·cosθᵢ - n₂·cosθₜ) / (n₁·cosθᵢ + n₂·cosθₜ)|²
 *   r_p = |(n₂·cosθᵢ - n₁·cosθₜ) / (n₂·cosθᵢ + n₁·cosθₜ)|²
 *   
 *   R = (r_s + r_p) / 2
 * 
 * 其中：
 *   θᵢ - 入射角
 *   θₜ - 折射角（由斯涅尔定律确定）
 *   n₁, n₂ - 两介质的折射率
 * 
 * 三、Schlick 近似
 * ─────────────────────────────────────────────────────────────────────────
 * 完整菲涅尔方程计算量大，Schlick 提出了高效的近似：
 * 
 *   R(θ) = R₀ + (1 - R₀)(1 - cosθ)⁵
 * 
 * 其中 R₀ 是垂直入射时的反射率：
 *   R₀ = ((n₁ - n₂) / (n₁ + n₂))²
 * 
 * 对于水-空气界面：
 *   n₁ = 1.0 (空气)
 *   n₂ = 1.33 (水)
 *   R₀ ≈ 0.02
 * 
 * 四、水体渲染中的菲涅尔应用
 * ─────────────────────────────────────────────────────────────────────────
 * 
 * 1. 反射/折射混合：
 *    finalColor = lerp(refractionColor, reflectionColor, fresnel)
 * 
 * 2. 入射透射率 (T_entry)：
 *    光线进入水面时的透射比例
 * 
 * 3. 出射透射率 (T_exit)：
 *    光线离开水面时的透射比例
 * 
 * 4. BSDF 散射计算：
 *    散射光需要乘以入射和出射透射率
 * 
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │                           使用说明                                      │
 * └─────────────────────────────────────────────────────────────────────────┘
 * 
 * 1. 基本菲涅尔计算：
 *    // 简单 Schlick 近似
 *    float fresnel = FFFresnelSchlick(f0, cosTheta);
 *    
 *    // 水体专用（自动计算 NdotV）
 *    float fresnel = FFFresnelWater(normalWS, viewDirWS, f0);
 * 
 * 2. 透射率计算：
 *    // 入射透射率
 *    float T_entry = FFFresnelEntry(f0, normalWS, lightDirWS);
 *    
 *    // 出射透射率
 *    float T_exit = FFFresnelExit(f0, normalWS, viewDirWS);
 * 
 * 3. 参数说明：
 *    - f0        : 垂直入射反射率，水约为 0.02
 *    - normalWS  : 世界空间法线
 *    - viewDirWS : 世界空间视线方向
 *    - lightDirWS: 世界空间光源方向
 *    - roughness : 粗糙度（影响菲涅尔强度）
 * 
 * 4. 折射率与 F0 转换：
 *    // 从折射率计算 F0
 *    float f0 = FFIorToF0(1.33);  // 水的折射率
 *    
 *    // 从 F0 计算折射率
 *    float ior = FFF0ToIor(0.02);
 * 
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │                           依赖关系                                      │
 * └─────────────────────────────────────────────────────────────────────────┘
 * 
 * ff_WaterFresnel.hlsl
 *     └── ff_WaterCommon.hlsl    (基础工具函数)
 * 
 * 被以下文件引用：
 *     ├── ff_WaterBSDF.hlsl
 *     └── water.shader
 * 
 * ═══════════════════════════════════════════════════════════════════════════
 */

#ifndef FF_WATER_FRESNEL_INCLUDED
#define FF_WATER_FRESNEL_INCLUDED

#include "ff_WaterCommon.hlsl"

// ═══════════════════════════════════════════════════════════════════════════
// Schlick 菲涅尔近似
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFFresnelSchlick - Schlick 菲涅尔近似（标量版）
 * 
 * 高效的菲涅尔近似计算，广泛用于实时渲染。
 * 
 * 参数：
 *   f0       - 垂直入射时的反射率 (F0)
 *   cosTheta - 角度的余弦值（通常为 NdotV）
 * 
 * 返回：
 *   菲涅尔反射率 [f0, 1]
 * 
 * 公式：
 *   R(θ) = f0 + (1 - f0)(1 - cosθ)⁵
 * 
 * 特点：
 *   - 计算量小
 *   - 精度足够用于实时渲染
 *   - 在掠射角时趋近于 1
 */
float FFFresnelSchlick(float f0, float cosTheta)
{
    float t = 1.0 - cosTheta;
    float t2 = t * t;
    float t5 = t2 * t2 * t;
    return f0 + (1.0 - f0) * t5;
}

/*
 * FFFresnelSchlick3 - Schlick 菲涅尔近似（向量版）
 * 
 * 对每个颜色通道分别计算菲涅尔，用于金属材质。
 * 水体通常使用标量版本。
 * 
 * 参数：
 *   f0       - 垂直入射时的反射率（RGB）
 *   cosTheta - 角度的余弦值
 * 
 * 返回：
 *   菲涅尔反射率（RGB）
 */
float3 FFFresnelSchlick3(float3 f0, float cosTheta)
{
    float t = 1.0 - cosTheta;
    float t2 = t * t;
    float t5 = t2 * t2 * t;
    return f0 + (1.0 - f0) * t5;
}

/*
 * FFFresnelSchlickRoughness - 带粗糙度的 Schlick 菲涅尔近似
 * 
 * 考虑表面粗糙度对菲涅尔的影响。
 * 粗糙度越高，菲涅尔效果越弱。
 * 
 * 参数：
 *   f0        - 垂直入射时的反射率
 *   cosTheta  - 角度的余弦值
 *   roughness - 表面粗糙度 [0, 1]
 * 
 * 返回：
 *   修正后的菲涅尔反射率
 * 
 * 原理：
 *   粗糙表面的微面元朝向不同，会减弱菲涅尔效果。
 *   使用 max(oneMinusRoughness, f0) 确保结果不会低于 f0。
 */
float FFFresnelSchlickRoughness(float f0, float cosTheta, float roughness)
{
    float t = 1.0 - cosTheta;
    float t2 = t * t;
    float t5 = t2 * t2 * t;
    float oneMinusRoughness = 1.0 - roughness;
    return f0 + (max(oneMinusRoughness, f0) - f0) * t5;
}

// ═══════════════════════════════════════════════════════════════════════════
// 水体专用菲涅尔函数
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFFresnelWater - 水体菲涅尔计算
 * 
 * 专为水体设计的菲涅尔计算函数。
 * 自动计算 NdotV 并应用 Schlick 近似。
 * 
 * 参数：
 *   normalWS  - 世界空间法线
 *   viewDirWS - 世界空间视线方向
 *   f0        - 水的垂直入射反射率（≈ 0.02）
 * 
 * 返回：
 *   菲涅尔反射率
 * 
 * 用途：
 *   - 反射/折射混合权重
 *   - 水面高光强度调制
 */
float FFFresnelWater(float3 normalWS, float3 viewDirWS, float f0)
{
    float NdotV = saturate(dot(normalWS, viewDirWS));
    return FFFresnelSchlick(f0, NdotV);
}

/*
 * FFFresnelWaterFull - 完整菲涅尔方程计算
 * 
 * 使用完整物理公式计算菲涅尔反射率。
 * 考虑了偏振光和全内反射。
 * 
 * 参数：
 *   n1       - 介质1的折射率（如空气 = 1.0）
 *   n2       - 介质2的折射率（如水 = 1.33）
 *   normalWS - 世界空间法线
 *   viewDirWS- 世界空间视线方向
 * 
 * 返回：
 *   精确的菲涅尔反射率
 * 
 * 特点：
 *   - 物理正确
 *   - 考虑全内反射（sinθₜ² > 1 时返回 1）
 *   - 计算量较大
 * 
 * 注意：
 *   当 sinθₜ² > 1 时发生全内反射，反射率为 1。
 */
float FFFresnelWaterFull(float n1, float n2, float3 normalWS, float3 viewDirWS)
{
    float NdotV = dot(normalWS, viewDirWS);
    float cosThetaI = abs(NdotV);
    // 斯涅尔定律计算折射角的正弦平方
    float sinThetaT2 = (n1 / n2) * (n1 / n2) * (1.0 - cosThetaI * cosThetaI);
    
    // 全内反射检查
    if (sinThetaT2 > 1.0)
        return 1.0;
    
    float cosThetaT = sqrt(1.0 - sinThetaT2);
    // s偏振光反射率
    float r_s = FFSquare((n1 * cosThetaI - n2 * cosThetaT) / (n1 * cosThetaI + n2 * cosThetaT));
    // p偏振光反射率
    float r_p = FFSquare((n2 * cosThetaI - n1 * cosThetaT) / (n2 * cosThetaI + n1 * cosThetaT));
    
    // 平均反射率（非偏振光）
    return (r_s + r_p) * 0.5;
}

// ═══════════════════════════════════════════════════════════════════════════
// 透射率函数
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFFresnelTransmission - 计算菲涅尔透射率
 * 
 * 透射率 = 1 - 反射率
 * 
 * 参数：
 *   f0       - 垂直入射反射率
 *   cosTheta - 角度的余弦值
 * 
 * 返回：
 *   透射率 [1-f0, 0]
 */
float FFFresnelTransmission(float f0, float cosTheta)
{
    return 1.0 - FFFresnelSchlick(f0, cosTheta);
}

/*
 * FFFresnelExit - 出射透射率
 * 
 * 计算光线从水中射出时的透射率。
 * 用于 BSDF 散射计算的最终输出。
 * 
 * 参数：
 *   f0        - 垂直入射反射率
 *   normalWS  - 世界空间法线
 *   viewDirWS - 世界空间视线方向
 * 
 * 返回：
 *   出射透射率
 */
float FFFresnelExit(float f0, float3 normalWS, float3 viewDirWS)
{
    float NdotV = saturate(dot(normalWS, viewDirWS));
    return FFFresnelTransmission(f0, NdotV);
}

/*
 * FFFresnelEntry - 入射透射率
 * 
 * 计算光线进入水面时的透射率。
 * 用于 BSDF 散射计算的入射能量。
 * 
 * 参数：
 *   f0         - 垂直入射反射率
 *   normalWS   - 世界空间法线
 *   lightDirWS - 世界空间光源方向
 * 
 * 返回：
 *   入射透射率
 */
float FFFresnelEntry(float f0, float3 normalWS, float3 lightDirWS)
{
    float NdotL = saturate(dot(normalWS, lightDirWS));
    return FFFresnelTransmission(f0, NdotL);
}

// ═══════════════════════════════════════════════════════════════════════════
// 折射率转换函数
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFIorToF0 - 从折射率计算 F0
 * 
 * 将折射率转换为垂直入射时的反射率。
 * 
 * 参数：
 *   ior - 折射率（相对于真空）
 * 
 * 返回：
 *   F0 值
 * 
 * 公式：
 *   F0 = ((n - 1) / (n + 1))²
 * 
 * 示例：
 *   水 (n=1.33): F0 ≈ 0.02
 *   玻璃 (n=1.5): F0 ≈ 0.04
 */
float FFIorToF0(float ior)
{
    float temp = (ior - 1.0) / (ior + 1.0);
    return temp * temp;
}

/*
 * FFF0ToIor - 从 F0 计算折射率
 * 
 * 将垂直入射反射率转换为折射率。
 * 
 * 参数：
 *   f0 - 垂直入射反射率
 * 
 * 返回：
 *   折射率
 * 
 * 公式：
 *   n = (1 + √F0) / (1 - √F0)
 */
float FFF0ToIor(float f0)
{
    float sqrtF0 = sqrt(f0);
    return (1.0 + sqrtF0) / (1.0 - sqrtF0);
}

#endif
