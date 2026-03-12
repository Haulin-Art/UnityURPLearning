/*
 * ═══════════════════════════════════════════════════════════════════════════
 * FluidFlux Water Phase - 水体相位函数模块
 * ═══════════════════════════════════════════════════════════════════════════
 * 
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │                           原理框架                                      │
 * └─────────────────────────────────────────────────────────────────────────┘
 * 
 * 一、相位函数概述
 * ─────────────────────────────────────────────────────────────────────────
 * 相位函数描述光在介质中散射时的角度分布。
 * 它回答了这个问题：当光被散射后，有多少光会朝特定方向散射？
 * 
 * 在水体渲染中，相位函数决定了：
 *   - 水体的散射颜色分布
 *   - 背光/顺光时的散射强度差异
 *   - 深水区域的颜色特征
 * 
 * 二、主要相位函数类型
 * ─────────────────────────────────────────────────────────────────────────
 * 
 * 1. Rayleigh 散射
 *    - 小粒子散射（分子级别）
 *    - 散射强度与波长四次方成反比
 *    - 天空呈蓝色的原因
 *    - 相位函数：P(θ) = 3/(16π) * (1 + cos²θ)
 * 
 * 2. Mie 散射
 *    - 大粒子散射（气溶胶、水滴）
 *    - 强烈的前向散射
 *    - 云、雾的白色外观
 *    - 使用 Henyey-Greenstein 相位函数近似
 * 
 * 3. 水体散射
 *    - 混合 Rayleigh 和 Mie 散射
 *    - 典型比例：5% Rayleigh + 95% Mie
 *    - 产生特征性的蓝绿色水体
 * 
 * 三、Henyey-Greenstein 相位函数
 * ─────────────────────────────────────────────────────────────────────────
 * HG 相位函数是 Mie 散射的常用近似：
 * 
 *   P(θ) = (1 - g²) / (4π * (1 + g² - 2g·cosθ)^(3/2))
 * 
 * 参数 g 控制散射方向性：
 *   - g = 0：各向同性散射（均匀分布）
 *   - g > 0：前向散射（光继续向前）
 *   - g < 0：后向散射（光反射回来）
 *   - g = 1：完全前向散射
 * 
 * ┌───────────────────────────────────────────────────────────────────────┐
 * │                    HG 相位函数示意                                     │
 * │                                                                       │
 * │              g = 0 (各向同性)        g = 0.8 (前向散射)               │
 * │                                                                       │
 * │                  ○                         ○                         │
 * │                /   \                     /   \                        │
 * │               /     \                   /     \                       │
 * │              ●───────●                 ●───────●──→ 光方向            │
 * │               \     /                   \     /                       │
 * │                \   /                     \   /                        │
 * │                  ○                         ○                         │
 * │                                                                       │
 * │              均匀分布                主要向前散射                      │
 * └───────────────────────────────────────────────────────────────────────┘
 * 
 * 四、水体相位参数
 * ─────────────────────────────────────────────────────────────────────────
 * 
 * 默认水体散射 (g = 0.8)：
 *   - 中等前向散射
 *   - 适合大多数水体场景
 *   - 产生自然的散射分布
 * 
 * 背光透射 (g = 0.998)：
 *   - 极强前向散射
 *   - 用于夕阳照射波浪背面的透光效果
 *   - 产生明亮的边缘辉光
 * 
 * 五、cosθ 的计算
 * ─────────────────────────────────────────────────────────────────────────
 * 
 * cosθ = dot(-viewDir, lightDir)
 * 
 * 其中：
 *   - viewDir 是从观察点到表面的方向
 *   - lightDir 是光源方向
 *   - 负号确保角度定义正确
 * 
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │                           使用说明                                      │
 * └─────────────────────────────────────────────────────────────────────────┘
 * 
 * 1. 基本使用：
 *    // 计算相位角度
 *    float cosTheta = FFComputePhaseCosTheta(viewDir, lightDir);
 *    
 *    // 计算相位值
 *    float phase = FFWaterPhaseFunctionFast(g, cosTheta);
 * 
 * 2. 水体默认相位：
 *    float phase = FFPhaseWaterDefault(cosTheta);  // g = 0.8
 * 
 * 3. 背光专用相位：
 *    float phase = FFPhaseWaterBacklitFast(cosTheta);  // g = 0.998
 * 
 * 4. 参数建议：
 *    - 普通水体：g = 0.7 ~ 0.9
 *    - 浑浊水体：g = 0.5 ~ 0.7
 *    - 背光效果：g = 0.95 ~ 0.999
 * 
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │                           依赖关系                                      │
 * └─────────────────────────────────────────────────────────────────────────┘
 * 
 * ff_WaterPhase.hlsl
 *     └── ff_WaterCommon.hlsl    (基础工具函数、PI常量)
 * 
 * 被以下文件引用：
 *     ├── ff_WaterBSDF.hlsl
 *     ├── ff_WaterRayMarching.hlsl
 *     └── water.shader
 * 
 * ═══════════════════════════════════════════════════════════════════════════
 */

#ifndef FF_WATER_PHASE_INCLUDED
#define FF_WATER_PHASE_INCLUDED

#include "ff_WaterCommon.hlsl"

// ═══════════════════════════════════════════════════════════════════════════
// 常量定义
// ═══════════════════════════════════════════════════════════════════════════

#define FF_RAYLEIGH_RATIO 0.05    // Rayleigh 散射比例
#define FF_MIE_RATIO 0.95         // Mie 散射比例
#define FF_PHASE_G_DEFAULT 0.8    // 默认水体相位参数 g
#define FF_PHASE_G_BACKLIT 0.998  // 背光专用相位参数 g（极强前向散射）

// ═══════════════════════════════════════════════════════════════════════════
// Henyey-Greenstein 相位函数
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFHenyeyGreensteinPhase - Henyey-Greenstein 相位函数
 * 
 * Mie 散射的标准近似函数。
 * 
 * 参数：
 *   g        - 不对称参数 [-1, 1]
 *   cosTheta - 散射角度的余弦值
 * 
 * 返回：
 *   相位函数值
 * 
 * 公式：
 *   P(θ) = (1 - g²) / (4π * (1 + g² - 2g·cosθ)^(3/2))
 * 
 * 特点：
 *   - g = 0：各向同性
 *   - g > 0：前向散射
 *   - g < 0：后向散射
 */
float FFHenyeyGreensteinPhase(float g, float cosTheta)
{
    float g2 = g * g;
    float denom = 1.0 + g2 - 2.0 * g * cosTheta;
    float sqrtDenom = sqrt(denom);
    return (1.0 - g2) / (4.0 * FF_PI * sqrtDenom * denom);
}

/*
 * FFHenyeyGreensteinPhaseFast - 快速 HG 相位函数
 * 
 * 使用 pow 代替 sqrt 的优化版本。
 * 精度略有降低，但性能更好。
 * 
 * 参数：
 *   g        - 不对称参数
 *   cosTheta - 散射角度的余弦值
 * 
 * 返回：
 *   相位函数值
 */
float FFHenyeyGreensteinPhaseFast(float g, float cosTheta)
{
    float g2 = g * g;
    float denom = 1.0 + g2 - 2.0 * g * cosTheta;
    return (1.0 - g2) * pow(abs(denom), -1.5) / (4.0 * FF_PI);
}

// ═══════════════════════════════════════════════════════════════════════════
// Rayleigh 相位函数
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFRayleighPhase - Rayleigh 相位函数
 * 
 * 描述小粒子（分子级别）的散射特性。
 * 
 * 参数：
 *   cosTheta - 散射角度的余弦值
 * 
 * 返回：
 *   相位函数值
 * 
 * 公式：
 *   P(θ) = 3/(16π) * (1 + cos²θ)
 * 
 * 特点：
 *   - 前向和后向散射对称
 *   - 90度方向散射最弱
 *   - 天空蓝色的物理基础
 */
float FFRayleighPhase(float cosTheta)
{
    float cosTheta2 = cosTheta * cosTheta;
    return 3.0 / (16.0 * FF_PI) * (1.0 + cosTheta2);
}

/*
 * FFRayleighPhaseNormalized - 归一化 Rayleigh 相位函数
 * 
 * 简化版本，省略了 π 因子。
 * 用于与其他相位函数混合时简化计算。
 * 
 * 参数：
 *   cosTheta - 散射角度的余弦值
 * 
 * 返回：
 *   归一化相位值
 */
float FFRayleighPhaseNormalized(float cosTheta)
{
    float cosTheta2 = cosTheta * cosTheta;
    return 0.75 * (1.0 + cosTheta2);
}

// ═══════════════════════════════════════════════════════════════════════════
// Mie 相位函数
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFMiePhase - Mie 相位函数
 * 
 * Mie 散射的相位函数，直接调用 HG 函数。
 * 
 * 参数：
 *   g        - 不对称参数
 *   cosTheta - 散射角度的余弦值
 * 
 * 返回：
 *   相位函数值
 */
float FFMiePhase(float g, float cosTheta)
{
    return FFHenyeyGreensteinPhase(g, cosTheta);
}

// ═══════════════════════════════════════════════════════════════════════════
// 水体相位函数
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFWaterPhaseFunction - 水体相位函数
 * 
 * 混合 Rayleigh 和 Mie 散射的水体专用相位函数。
 * 
 * 参数：
 *   g        - Mie 散射的不对称参数
 *   cosTheta - 散射角度的余弦值
 * 
 * 返回：
 *   混合相位值
 * 
 * 公式：
 *   P = 0.05 * Rayleigh + 0.95 * Mie
 * 
 * 比例说明：
 *   - 5% Rayleigh：小粒子散射贡献
 *   - 95% Mie：大粒子/水滴散射贡献
 */
float FFWaterPhaseFunction(float g, float cosTheta)
{
    float rayleigh = FFRayleighPhase(cosTheta);
    float mie = FFMiePhase(g, cosTheta);
    return FF_RAYLEIGH_RATIO * rayleigh + FF_MIE_RATIO * mie;
}

/*
 * FFWaterPhaseFunctionFast - 快速水体相位函数
 * 
 * 使用快速版本和归一化 Rayleigh 的优化版本。
 * 
 * 参数：
 *   g        - Mie 散射的不对称参数
 *   cosTheta - 散射角度的余弦值
 * 
 * 返回：
 *   混合相位值
 */
float FFWaterPhaseFunctionFast(float g, float cosTheta)
{
    float rayleigh = FFRayleighPhaseNormalized(cosTheta);
    float mie = FFHenyeyGreensteinPhaseFast(g, cosTheta);
    return FF_RAYLEIGH_RATIO * rayleigh + FF_MIE_RATIO * mie;
}

// ═══════════════════════════════════════════════════════════════════════════
// 预设相位函数
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFPhaseWaterDefault - 默认水体相位函数
 * 
 * 使用 g = 0.8 的预设相位函数。
 * 适合大多数水体场景。
 * 
 * 参数：
 *   cosTheta - 散射角度的余弦值
 * 
 * 返回：
 *   相位值
 */
float FFPhaseWaterDefault(float cosTheta)
{
    return FFWaterPhaseFunction(FF_PHASE_G_DEFAULT, cosTheta);
}

/*
 * FFPhaseWaterBacklit - 背光水体相位函数
 * 
 * 使用 g = 0.998 的极强前向散射相位函数。
 * 用于夕阳照射波浪背面时的透光效果。
 * 
 * 参数：
 *   cosTheta - 散射角度的余弦值
 * 
 * 返回：
 *   相位值
 * 
 * 特点：
 *   - 极强的前向散射
 *   - 产生明亮的边缘辉光
 *   - 适合逆光场景
 */
float FFPhaseWaterBacklit(float cosTheta)
{
    return FFHenyeyGreensteinPhase(FF_PHASE_G_BACKLIT, cosTheta);
}

/*
 * FFPhaseWaterBacklitFast - 快速背光相位函数
 * 
 * 背光相位函数的优化版本。
 * 使用 rsqrt 进一步优化性能。
 * 
 * 参数：
 *   cosTheta - 散射角度的余弦值
 * 
 * 返回：
 *   相位值
 */
float FFPhaseWaterBacklitFast(float cosTheta)
{
    float g2 = FF_PHASE_G_BACKLIT * FF_PHASE_G_BACKLIT;
    float denom = 1.0 + g2 - 2.0 * FF_PHASE_G_BACKLIT * cosTheta;
    return (1.0 - g2) * rsqrt(denom) / denom;
}

// ═══════════════════════════════════════════════════════════════════════════
// 辅助函数
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFComputePhaseCosTheta - 计算相位角度余弦
 * 
 * 计算视线方向与光源方向的夹角余弦。
 * 
 * 参数：
 *   viewDir  - 视线方向
 *   lightDir - 光源方向
 * 
 * 返回：
 *   cos(θ)，θ 是散射角度
 * 
 * 注意：
 *   使用 -viewDir 确保角度定义正确
 */
float FFComputePhaseCosTheta(float3 viewDir, float3 lightDir)
{
    return dot(-viewDir, lightDir);
}

/*
 * FFEvaluatePhaseWater - 评估水体相位（完整版）
 * 
 * 从方向向量计算相位值。
 * 
 * 参数：
 *   viewDir  - 视线方向
 *   lightDir - 光源方向
 *   g        - 不对称参数
 * 
 * 返回：
 *   相位值
 */
float FFEvaluatePhaseWater(float3 viewDir, float3 lightDir, float g)
{
    float cosTheta = FFComputePhaseCosTheta(viewDir, lightDir);
    return FFWaterPhaseFunction(g, cosTheta);
}

/*
 * FFEvaluatePhaseWaterFast - 评估水体相位（快速版）
 * 
 * 从方向向量计算相位值（优化版本）。
 * 
 * 参数：
 *   viewDir  - 视线方向
 *   lightDir - 光源方向
 *   g        - 不对称参数
 * 
 * 返回：
 *   相位值
 */
float FFEvaluatePhaseWaterFast(float3 viewDir, float3 lightDir, float g)
{
    float cosTheta = FFComputePhaseCosTheta(viewDir, lightDir);
    return FFWaterPhaseFunctionFast(g, cosTheta);
}

/*
 * FFEvaluatePhaseBacklit - 评估背光相位（完整版）
 * 
 * 从方向向量计算背光相位值。
 * 
 * 参数：
 *   viewDir  - 视线方向
 *   lightDir - 光源方向
 * 
 * 返回：
 *   背光相位值
 */
float FFEvaluatePhaseBacklit(float3 viewDir, float3 lightDir)
{
    float cosTheta = FFComputePhaseCosTheta(viewDir, lightDir);
    return FFPhaseWaterBacklit(cosTheta);
}

/*
 * FFEvaluatePhaseBacklitFast - 评估背光相位（快速版）
 * 
 * 从方向向量计算背光相位值（优化版本）。
 * 
 * 参数：
 *   viewDir  - 视线方向
 *   lightDir - 光源方向
 * 
 * 返回：
 *   背光相位值
 */
float FFEvaluatePhaseBacklitFast(float3 viewDir, float3 lightDir)
{
    float cosTheta = FFComputePhaseCosTheta(viewDir, lightDir);
    return FFPhaseWaterBacklitFast(cosTheta);
}

// ═══════════════════════════════════════════════════════════════════════════
// 相位数据结构
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFPhaseData - 相位数据结构体
 * 
 * 存储完整的相位计算结果，便于调试和分项使用。
 */
struct FFPhaseData
{
    float phaseValue;     // 最终混合相位值
    float cosTheta;       // 散射角度余弦
    float rayleighPhase;  // Rayleigh 相位分量
    float miePhase;       // Mie 相位分量
};

/*
 * FFComputePhaseData - 计算完整相位数据
 * 
 * 计算并返回所有相位相关信息。
 * 适用于需要分项分析的场景。
 * 
 * 参数：
 *   viewDir  - 视线方向
 *   lightDir - 光源方向
 *   g        - 不对称参数
 * 
 * 返回：
 *   包含所有相位分量的结构体
 */
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
