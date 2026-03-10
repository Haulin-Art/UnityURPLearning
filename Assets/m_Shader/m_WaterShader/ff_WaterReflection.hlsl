/*
 * ═══════════════════════════════════════════════════════════════════════════
 * FluidFlux Water Reflection - 水体环境反射模块
 * ═══════════════════════════════════════════════════════════════════════════
 * 
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │                           原理框架                                      │
 * └─────────────────────────────────────────────────────────────────────────┘
 * 
 * 一、环境反射概述
 * ─────────────────────────────────────────────────────────────────────────
 * 水面反射是水体渲染中最重要的视觉效果之一。平静的水面如同一面镜子，
 * 能够反射周围的环境（天空、地形、物体等）。
 * 
 * 反射强度受菲涅尔效应影响：
 *   - 正视（视线垂直于水面）：反射弱，透射强
 *   - 掠视（视线接近平行于水面）：反射强，透射弱
 * 
 * 二、反射方向计算
 * ─────────────────────────────────────────────────────────────────────────
 * 
 * ┌───────────────────────────────────────────────────────────────────────┐
 * │                        反射几何示意                                    │
 * │                                                                       │
 * │              反射方向 R                                                │
 * │                ↑                                                      │
 * │               /                                                       │
 * │              /  θ                                                     │
 * │             /                                                         │
 * │    ────────●──────── 水面                                            │
 * │             \                                                         │
 * │              \  θ                                                     │
 * │               \                                                       │
 * │                ↓                                                      │
 * │              视线 V                                                    │
 * │                                                                       │
 * │    R = reflect(-V, N)                                                 │
 * │    入射角 = 反射角 (斯涅尔定律)                                        │
 * └───────────────────────────────────────────────────────────────────────┘
 * 
 * 反射方向计算公式：
 *   R = reflect(-V, N) = V - 2(V·N)N
 * 
 * 其中：
 *   V - 视线方向（从观察点到水面点）
 *   N - 法线方向
 *   R - 反射方向
 * 
 * 三、环境贴图采样
 * ─────────────────────────────────────────────────────────────────────────
 * 使用 Unity URP 的 GlossyEnvironmentReflection 函数采样环境贴图：
 * 
 *   - 支持反射探针 (Reflection Probe)
 *   - 支持天空盒 (Skybox)
 *   - 根据粗糙度自动选择 Mipmap 级别
 *   - 粗糙度越高，反射越模糊
 * 
 * 四、菲涅尔混合
 * ─────────────────────────────────────────────────────────────────────────
 * 反射颜色与基础颜色的混合比例由菲涅尔项控制：
 * 
 *   finalColor = lerp(baseColor, reflectionColor, fresnel * strength)
 * 
 * 菲涅尔项确保：
 *   - 近距离（正视）：看到更多水下内容
 *   - 远距离（掠视）：看到更多环境反射
 * 
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │                           使用说明                                      │
 * └─────────────────────────────────────────────────────────────────────────┘
 * 
 * 1. 基本使用流程：
 *    // 方式一：分步调用
 *    float3 reflectDir = FFGetReflectionDir(normalWS, viewDirWS);
 *    float3 reflectionColor = FFSampleEnvReflection(reflectDir, roughness, strength);
 *    float3 finalColor = FFBlendReflection(baseColor, reflectionColor, fresnel, 1.0);
 *    
 *    // 方式二：一站式调用
 *    float3 finalColor = FFApplyReflectionWithFresnel(
 *        baseColor, normalWS, viewDirWS,
 *        fresnel, roughness, envStrength
 *    );
 * 
 * 2. 参数说明：
 *    - normalWS     : 世界空间法线
 *    - viewDirWS    : 世界空间视线方向（从观察点到水面）
 *    - roughness    : 粗糙度 [0, 1]，影响反射模糊程度
 *    - envStrength  : 环境反射强度 [0, 2]
 *    - fresnel      : 菲涅尔项 [0, 1]
 * 
 * 3. 性能建议：
 *    - 粗糙度采样会访问不同 Mipmap 级别
 *    - 对于完全平静的水面，可使用 roughness = 0
 *    - 对于波动剧烈的水面，可适当增加 roughness
 * 
 * 4. 视觉效果建议：
 *    - 配合法线扰动产生波纹反射效果
 *    - 调整 envStrength 控制反射亮度
 *    - 菲涅尔项应与折射计算配合使用
 * 
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │                           依赖关系                                      │
 * └─────────────────────────────────────────────────────────────────────────┘
 * 
 * ff_WaterReflection.hlsl
 *     └── ff_WaterCommon.hlsl    (基础工具函数)
 * 
 * 被以下文件引用：
 *     └── water.shader          (主着色器)
 * 
 * ═══════════════════════════════════════════════════════════════════════════
 */

#ifndef FF_WATER_REFLECTION_INCLUDED
#define FF_WATER_REFLECTION_INCLUDED

#include "ff_WaterCommon.hlsl"

// ═══════════════════════════════════════════════════════════════════════════
// 反射方向计算
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFGetReflectionDir - 计算反射方向
 * 
 * 根据视线方向和法线计算反射方向。
 * 使用标准的反射公式：R = reflect(-V, N)
 * 
 * 参数：
 *   normalWS  - 世界空间法线
 *   viewDirWS - 世界空间视线方向（从观察点指向水面点）
 * 
 * 返回：
 *   反射方向（用于采样环境贴图）
 * 
 * 注意：
 *   viewDirWS 应该是从相机指向表面的方向
 *   反射方向用于采样环境贴图
 */
float3 FFGetReflectionDir(float3 normalWS, float3 viewDirWS)
{
    return reflect(-viewDirWS, normalWS);
}

// ═══════════════════════════════════════════════════════════════════════════
// 环境反射采样
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFSampleEnvReflection - 采样环境反射
 * 
 * 使用 Unity URP 的 GlossyEnvironmentReflection 函数采样环境贴图。
 * 支持反射探针和天空盒，根据粗糙度自动选择 Mipmap 级别。
 * 
 * 参数：
 *   reflectDir    - 反射方向
 *   roughness     - 粗糙度 [0, 1]
 *   envStrength   - 环境反射强度
 * 
 * 返回：
 *   环境反射颜色
 * 
 * 原理：
 *   - roughness = 0：完全清晰的反射
 *   - roughness = 1：完全模糊的反射
 *   - Unity 会根据 roughness 选择合适的 Mipmap 级别
 */
float3 FFSampleEnvReflection(float3 reflectDir, float roughness, float envStrength)
{
    float perceptualRoughness = roughness;
    // 使用 URP 内置函数采样环境反射
    float3 envColor = GlossyEnvironmentReflection(reflectDir, perceptualRoughness, 1.0);
    return envColor * envStrength;
}

// ═══════════════════════════════════════════════════════════════════════════
// 反射混合
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFBlendReflection - 混合反射颜色
 * 
 * 将反射颜色与基础颜色混合，混合比例由菲涅尔项控制。
 * 
 * 参数：
 *   baseColor         - 基础颜色（通常是折射后的颜色）
 *   reflectionColor   - 反射颜色
 *   fresnel           - 菲涅尔项 [0, 1]
 *   reflectionStrength - 反射强度
 * 
 * 返回：
 *   混合后的颜色
 * 
 * 公式：
 *   result = lerp(baseColor, reflectionColor, fresnel * reflectionStrength)
 * 
 * 菲涅尔效果：
 *   - fresnel = 0：完全显示基础颜色（正视水面）
 *   - fresnel = 1：完全显示反射颜色（掠视水面）
 */
float3 FFBlendReflection(
    float3 baseColor,
    float3 reflectionColor,
    float fresnel,
    float reflectionStrength)
{
    return lerp(baseColor, reflectionColor, fresnel * reflectionStrength);
}

// ═══════════════════════════════════════════════════════════════════════════
// 一站式反射函数
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFApplyReflectionWithFresnel - 应用带菲涅尔的反射
 * 
 * 一站式函数：计算反射方向 -> 采样环境 -> 混合颜色
 * 适用于需要快速应用反射效果的场景。
 * 
 * 参数：
 *   baseColor    - 基础颜色
 *   normalWS     - 世界空间法线
 *   viewDirWS    - 世界空间视线方向
 *   fresnel      - 菲涅尔项
 *   roughness    - 粗糙度
 *   envStrength  - 环境反射强度
 * 
 * 返回：
 *   混合反射后的颜色
 */
float3 FFApplyReflectionWithFresnel(
    float3 baseColor,
    float3 normalWS,
    float3 viewDirWS,
    float fresnel,
    float roughness,
    float envStrength)
{
    // 计算反射方向
    float3 reflectDir = FFGetReflectionDir(normalWS, viewDirWS);
    // 采样环境反射
    float3 reflectionColor = FFSampleEnvReflection(reflectDir, roughness, envStrength);
    // 混合颜色
    return FFBlendReflection(baseColor, reflectionColor, fresnel, 1.0);
}

#endif
