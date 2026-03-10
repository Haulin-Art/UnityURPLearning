/*
 * ═══════════════════════════════════════════════════════════════════════════
 * FluidFlux Water Refraction - 水体折射模块
 * ═══════════════════════════════════════════════════════════════════════════
 * 
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │                           原理框架                                      │
 * └─────────────────────────────────────────────────────────────────────────┘
 * 
 * 一、折射概述
 * ─────────────────────────────────────────────────────────────────────────
 * 折射是光线从一种介质进入另一种介质时方向发生改变的现象。
 * 对于水体渲染，折射使我们能够看到水面下的物体。
 * 
 * 水的折射率：n ≈ 1.33
 * 空气的折射率：n ≈ 1.0
 * 
 * 二、折射方向计算
 * ─────────────────────────────────────────────────────────────────────────
 * 
 * ┌───────────────────────────────────────────────────────────────────────┐
 * │                        折射几何示意                                    │
 * │                                                                       │
 * │              入射光线 I                                                │
 * │                ↓                                                      │
 * │               / θ₁                                                    │
 * │              /                                                        │
 * │    ────────●──────── 水面 (n₁ = 1.0)                                  │
 * │              \                                                        │
 * │               \ θ₂                                                    │
 * │                ↓                                                      │
 * │              折射光线 T                                                │
 * │                                                                       │
 * │         水下 (n₂ = 1.33)                                              │
 * │                                                                       │
 * │    斯涅尔定律：n₁·sin(θ₁) = n₂·sin(θ₂)                               │
 * └───────────────────────────────────────────────────────────────────────┘
 * 
 * 在实时渲染中，通常使用简化的折射模型：
 *   - 根据法线偏移屏幕 UV 坐标
 *   - 采样屏幕颜色缓冲获取水下颜色
 *   - 应用深度相关的吸收效果
 * 
 * 三、Beer-Lambert 吸收定律
 * ─────────────────────────────────────────────────────────────────────────
 * 光线在水中传播时会逐渐被吸收，吸收程度遵循 Beer-Lambert 定律：
 * 
 *   T = e^(-α·d)
 * 
 * 其中：
 *   T - 透射率 (Transmittance)
 *   α - 吸收系数 (Absorption Coefficient)
 *   d - 光程距离 (Distance)
 * 
 * 吸收特性：
 *   - 红光最先被吸收（深水呈蓝绿色）
 *   - 距离越远，吸收越多
 *   - 不同波长吸收率不同
 * 
 * 四、屏幕空间折射实现
 * ─────────────────────────────────────────────────────────────────────────
 * 本模块使用屏幕空间折射技术：
 * 
 *   1. 根据法线计算 UV 偏移量
 *   2. 偏移屏幕 UV 采样背景颜色
 *   3. 根据水深应用吸收效果
 *   4. 可选：根据深度选择 Mipmap 级别实现模糊
 * 
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │                           使用说明                                      │
 * └─────────────────────────────────────────────────────────────────────────┘
 * 
 * 1. 基本使用流程：
 *    // 计算折射偏移
 *    float2 offset = FFGetRefractionOffset(normalWS, viewDirWS, strength);
 *    float2 refractedUV = screenUV + offset;
 *    
 *    // 采样折射颜色
 *    float3 refractionColor = SAMPLE_TEXTURE2D(_CameraOpaqueTexture, sampler, refractedUV);
 *    
 *    // 应用水吸收
 *    refractionColor = FFApplyWaterAbsorption(refractionColor, waterDepth, absorptionColor);
 * 
 * 2. 参数说明：
 *    - normalWS          : 世界空间法线
 *    - viewDirWS         : 世界空间视线方向
 *    - strength          : 折射强度 [0, 0.1]
 *    - waterDepth        : 水深（线性深度）
 *    - absorptionColor   : 吸收颜色/系数
 * 
 * 3. 吸收颜色建议：
 *    - 清澈水：(0.1, 0.2, 0.3) - 轻微吸收
 *    - 普通水：(0.2, 0.4, 0.3) - 中等吸收
 *    - 浑浊水：(0.5, 0.6, 0.4) - 强烈吸收
 * 
 * 4. 性能建议：
 *    - 折射强度不宜过大，否则会产生不自然的扭曲
 *    - 深度模糊可使用预生成的 Mipmap 纹理
 *    - 对于浅水区域，可降低折射计算精度
 * 
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │                           依赖关系                                      │
 * └─────────────────────────────────────────────────────────────────────────┘
 * 
 * ff_WaterRefraction.hlsl
 *     └── ff_WaterCommon.hlsl    (基础工具函数)
 * 
 * 被以下文件引用：
 *     └── water.shader          (主着色器)
 * 
 * ═══════════════════════════════════════════════════════════════════════════
 */

#ifndef FF_WATER_REFRACTION_INCLUDED
#define FF_WATER_REFRACTION_INCLUDED

#include "ff_WaterCommon.hlsl"

// ═══════════════════════════════════════════════════════════════════════════
// 折射偏移计算
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFGetRefractionOffset - 计算折射 UV 偏移
 * 
 * 根据法线计算屏幕 UV 的折射偏移量。
 * 使用法线的 XZ 分量作为偏移方向。
 * 
 * 参数：
 *   normalWS  - 世界空间法线
 *   viewDirWS - 世界空间视线方向
 *   strength  - 折射强度
 * 
 * 返回：
 *   UV 偏移量
 * 
 * 注意：
 *   这是一个简化的折射模型，不考虑真实的折射角度计算。
 *   真实折射需要考虑折射率和入射角度。
 */
float2 FFGetRefractionOffset(float3 normalWS, float3 viewDirWS, float strength)
{
    // 使用法线的 XZ 分量作为偏移方向
    float2 offset = normalWS.xz * strength;
    return offset;
}

// ═══════════════════════════════════════════════════════════════════════════
// 折射颜色采样
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFSampleRefractionColor - 采样折射颜色
 * 
 * 根据偏移后的 UV 采样屏幕颜色。
 * 
 * 参数：
 *   screenUV - 原始屏幕 UV
 *   offset   - UV 偏移量
 *   tex      - 纹理（通常是屏幕颜色纹理）
 *   samplerTex - 采样器
 * 
 * 返回：
 *   折射后的颜色
 */
float3 FFSampleRefractionColor(float2 screenUV, float2 offset, TEXTURE2D_PARAM(tex, samplerTex))
{
    // 计算偏移后的 UV
    float2 refractedUV = screenUV + offset;
    // 限制在 [0, 1] 范围内
    refractedUV = saturate(refractedUV);
    // 采样颜色
    return SAMPLE_TEXTURE2D(tex, samplerTex, refractedUV).rgb;
}

/*
 * FFSampleRefractionColorWithDepthFade - 带深度衰减的折射采样
 * 
 * 采样折射颜色并应用基于水深的吸收效果。
 * 
 * 参数：
 *   screenUV       - 原始屏幕 UV
 *   offset         - UV 偏移量
 *   waterDepth     - 水深
 *   absorptionColor - 吸收颜色/系数
 *   tex            - 纹理
 *   samplerTex     - 采样器
 * 
 * 返回：
 *   应用吸收后的折射颜色
 */
float3 FFSampleRefractionColorWithDepthFade(
    float2 screenUV, 
    float2 offset, 
    float waterDepth,
    float3 absorptionColor,
    TEXTURE2D_PARAM(tex, samplerTex))
{
    // 计算偏移后的 UV
    float2 refractedUV = screenUV + offset;
    refractedUV = saturate(refractedUV);
    
    // 采样折射颜色
    float3 refractionColor = SAMPLE_TEXTURE2D(tex, samplerTex, refractedUV).rgb;
    
    // 应用深度衰减（Beer-Lambert）
    float3 depthFade = exp(-absorptionColor * waterDepth);
    refractionColor *= depthFade;
    
    return refractionColor;
}

// ═══════════════════════════════════════════════════════════════════════════
// 折射强度计算
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFGetRefractionStrength - 计算动态折射强度
 * 
 * 根据水深动态调整折射强度。
 * 浅水区域折射效果更明显，深水区域折射效果减弱。
 * 
 * 参数：
 *   waterDepth   - 水深
 *   maxDepth     - 最大深度阈值
 *   baseStrength - 基础折射强度
 * 
 * 返回：
 *   调整后的折射强度
 */
float FFGetRefractionStrength(float waterDepth, float maxDepth, float baseStrength)
{
    // 计算深度因子
    float depthFactor = saturate(waterDepth / maxDepth);
    // 深水区域折射强度降低 50%
    return baseStrength * (1.0 - depthFactor * 0.5);
}

// ═══════════════════════════════════════════════════════════════════════════
// 一站式折射函数
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFApplyRefraction - 应用折射效果
 * 
 * 一站式函数：计算偏移 -> 采样颜色 -> 应用吸收
 * 
 * 参数：
 *   baseColor          - 基础颜色（未使用，保留用于扩展）
 *   screenUV           - 屏幕 UV
 *   normalWS           - 世界空间法线
 *   viewDirWS          - 世界空间视线方向
 *   waterDepth         - 水深
 *   refractionStrength - 折射强度
 *   absorptionColor    - 吸收颜色
 *   tex                - 屏幕颜色纹理
 *   samplerTex         - 采样器
 * 
 * 返回：
 *   折射后的颜色
 */
float3 FFApplyRefraction(
    float3 baseColor,
    float2 screenUV,
    float3 normalWS,
    float3 viewDirWS,
    float waterDepth,
    float refractionStrength,
    float3 absorptionColor,
    TEXTURE2D_PARAM(tex, samplerTex))
{
    // 计算折射偏移
    float2 offset = FFGetRefractionOffset(normalWS, viewDirWS, refractionStrength);
    // 采样带深度衰减的折射颜色
    float3 refractionColor = FFSampleRefractionColorWithDepthFade(screenUV, offset, waterDepth, absorptionColor, TEXTURE2D_ARGS(tex, samplerTex));
    return refractionColor;
}

// ═══════════════════════════════════════════════════════════════════════════
// Beer-Lambert 吸收
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFBeerLambertAbsorption - Beer-Lambert 吸收计算
 * 
 * 计算光线在介质中传播时的透射率。
 * 
 * 参数：
 *   absorptionColor - 吸收系数（颜色形式）
 *   distance        - 传播距离
 * 
 * 返回：
 *   透射率 [0, 1]
 * 
 * 公式：
 *   T = e^(-α·d)
 * 
 * 其中 α 是吸收系数，d 是距离
 */
float3 FFBeerLambertAbsorption(float3 absorptionColor, float distance)
{
    return exp(-absorptionColor * distance);
}

/*
 * FFApplyWaterAbsorption - 应用水吸收效果
 * 
 * 对颜色应用水的吸收效果。
 * 
 * 参数：
 *   color           - 原始颜色
 *   waterDepth      - 水深
 *   absorptionColor - 吸收系数
 * 
 * 返回：
 *   吸收后的颜色
 */
float3 FFApplyWaterAbsorption(float3 color, float waterDepth, float3 absorptionColor)
{
    // 计算透射率
    float3 absorption = FFBeerLambertAbsorption(absorptionColor, waterDepth);
    // 应用吸收
    return color * absorption;
}

#endif
