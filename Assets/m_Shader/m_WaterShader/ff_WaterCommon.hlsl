/*
 * ═══════════════════════════════════════════════════════════════════════════
 * FluidFlux Water Common - 水体渲染基础工具库
 * ═══════════════════════════════════════════════════════════════════════════
 * 
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │                           模块概述                                      │
 * └─────────────────────────────────────────────────────────────────────────┘
 * 
 * 本文件是 FluidFlux 水体渲染系统的核心基础库，提供所有其他模块共用的：
 *   - 常量定义（PI 等）
 *   - 数学工具函数
 *   - 深度缓冲相关函数
 *   - 坐标转换函数
 *   - 随机数/抖动函数
 * 
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │                           依赖关系                                      │
 * └─────────────────────────────────────────────────────────────────────────┘
 * 
 * ff_WaterCommon.hlsl (本文件)
 *     ├── Unity Core Shader Library
 *     ├── Unity URP Shader Library
 *     ├── Unity Lighting Library
 *     └── DeclareDepthTexture
 * 
 * 被以下文件引用：
 *     ├── ff_WaterFresnel.hlsl
 *     ├── ff_WaterPhase.hlsl
 *     ├── ff_WaterBSDF.hlsl
 *     ├── ff_WaterRayMarching.hlsl
 *     ├── ff_WaterRefraction.hlsl
 *     ├── ff_WaterReflection.hlsl
 *     ├── ff_WaterSpecular.hlsl
 *     ├── ff_WaterForwardScatter.hlsl
 *     └── water.shader
 * 
 * ═══════════════════════════════════════════════════════════════════════════
 */

#ifndef FF_WATER_COMMON_INCLUDED
#define FF_WATER_COMMON_INCLUDED

// ═══════════════════════════════════════════════════════════════════════════
// Unity URP 核心库引用
// ═══════════════════════════════════════════════════════════════════════════

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

// ═══════════════════════════════════════════════════════════════════════════
// 常量定义
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FF_PI - 圆周率常量
 * 
 * 用于各种涉及角度和弧度转换的计算，如相位函数、GGX分布等。
 * 精度：小数点后11位，满足大多数图形计算需求。
 */
#define FF_PI 3.14159265359

// ═══════════════════════════════════════════════════════════════════════════
// 颜色与亮度函数
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFLuminance - 计算颜色的感知亮度
 * 
 * 使用 ITU-R BT.709 标准的亮度权重计算人眼感知亮度。
 * 
 * 参数：
 *   color - RGB 颜色值
 * 
 * 返回：
 *   感知亮度值 [0, 1]
 * 
 * 公式：
 *   Y = 0.2126*R + 0.7152*G + 0.0722*B
 * 
 * 权重说明：
 *   - 绿色权重最大（人眼对绿色最敏感）
 *   - 红色次之
 *   - 蓝色最小
 */
float FFLuminance(float3 color)
{
    return dot(color, float3(0.2126729, 0.7151522, 0.0721750));
}

// ═══════════════════════════════════════════════════════════════════════════
// 数学工具函数
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFPow5 - 快速计算 x 的 5 次方
 * 
 * 优化版本，减少乘法次数。
 * 常用于 Schlick 菲涅尔近似。
 * 
 * 参数：
 *   x - 输入值
 * 
 * 返回：
 *   x^5
 * 
 * 实现原理：
 *   x^5 = x^2 * x^2 * x
 *   只需 3 次乘法
 */
float FFPow5(float x)
{
    float x2 = x * x;
    return x2 * x2 * x;
}

/*
 * FFPow5 - 向量版本的 5 次方计算
 * 
 * 对 float3 的每个分量分别计算 5 次方。
 * 用于颜色相关的菲涅尔计算。
 */
float3 FFPow5(float3 x)
{
    float3 x2 = x * x;
    return x2 * x2 * x;
}

/*
 * FFSquare - 计算平方
 * 
 * 简单的平方函数，提高代码可读性。
 * 
 * 参数：
 *   x - 输入值
 * 
 * 返回：
 *   x^2
 */
float FFSquare(float x)
{
    return x * x;
}

/*
 * FFSafeNormalize - 安全归一化
 * 
 * 对向量进行归一化，处理零向量情况避免除零错误。
 * 
 * 参数：
 *   v - 输入向量
 * 
 * 返回：
 *   归一化后的向量，零向量返回 (0, 1, 0)
 * 
 * 注意：
 *   阈值 1e-6 用于避免浮点精度问题
 */
float3 FFSafeNormalize(float3 v)
{
    float len = length(v);
    return len > 1e-6 ? v / len : float3(0, 1, 0);
}

// ═══════════════════════════════════════════════════════════════════════════
// 深度缓冲函数
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFGetLinearEyeDepth - 从屏幕 UV 获取线性眼空间深度
 * 
 * 采样深度缓冲并转换为线性眼空间深度（以相机为原点的深度）。
 * 
 * 参数：
 *   uv - 屏幕 UV 坐标 [0, 1]
 * 
 * 返回：
 *   线性眼空间深度（世界单位）
 * 
 * 用途：
 *   - 计算水深
 *   - 判断物体在水下/水上
 *   - 深度雾效果
 */
float FFGetLinearEyeDepth(float2 uv)
{
    float rawDepth = SampleSceneDepth(uv);
    return LinearEyeDepth(rawDepth, _ZBufferParams);
}

/*
 * FFGetLinearEyeDepthFromRaw - 从原始深度值获取线性眼空间深度
 * 
 * 将深度缓冲的原始值转换为线性眼空间深度。
 * 
 * 参数：
 *   rawDepth - 深度缓冲原始值
 * 
 * 返回：
 *   线性眼空间深度
 */
float FFGetLinearEyeDepthFromRaw(float rawDepth)
{
    return LinearEyeDepth(rawDepth, _ZBufferParams);
}

/*
 * FFGetWorldPositionFromDepth - 从深度重建世界坐标
 * 
 * 通过深度缓冲和屏幕 UV 重建像素的世界坐标。
 * 
 * 参数：
 *   uv            - 屏幕 UV 坐标
 *   linearEyeDepth - 线性眼空间深度
 * 
 * 返回：
 *   世界坐标位置
 * 
 * 原理：
 *   1. 从 UV 构建NDC坐标
 *   2. 逆投影变换到视图空间
 *   3. 逆视图变换到世界空间
 */
float3 FFGetWorldPositionFromDepth(float2 uv, float linearEyeDepth)
{
    // 构建 NDC 坐标
    float4 positionNDC = float4(uv * 2.0 - 1.0, 1.0, 1.0);
    // 逆投影变换
    float4 positionVS = mul(UNITY_MATRIX_I_P, positionNDC);
    positionVS /= positionVS.w;
    // 逆视图变换
    float4 positionWS = mul(UNITY_MATRIX_I_V, positionVS);
    return positionWS.xyz;
}

// ═══════════════════════════════════════════════════════════════════════════
// 值映射函数
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFRemap - 值重映射
 * 
 * 将值从一个范围映射到另一个范围。
 * 
 * 参数：
 *   value  - 输入值
 *   inMin  - 输入范围最小值
 *   inMax  - 输入范围最大值
 *   outMin - 输出范围最小值
 *   outMax - 输出范围最大值
 * 
 * 返回：
 *   重映射后的值
 * 
 * 公式：
 *   out = outMin + (value - inMin) * (outMax - outMin) / (inMax - inMin)
 */
float FFRemap(float value, float inMin, float inMax, float outMin, float outMax)
{
    return outMin + (value - inMin) * (outMax - outMin) / (inMax - inMin);
}

/*
 * FFRemap01 - 值重映射到 [0, 1] 范围
 * 
 * 将值从任意范围映射到 [0, 1] 并截断。
 * 
 * 参数：
 *   value  - 输入值
 *   inMin  - 输入范围最小值
 *   inMax  - 输入范围最大值
 * 
 * 返回：
 *   归一化值 [0, 1]
 * 
 * 用途：
 *   - 创建平滑过渡
 *   - 深度归一化
 *   - 距离衰减
 */
float FFRemap01(float value, float inMin, float inMax)
{
    return saturate((value - inMin) / (inMax - inMin));
}

// ═══════════════════════════════════════════════════════════════════════════
// 法线混合函数
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFBlendNormal - 法线贴图混合
 * 
 * 使用 Whiteout 方法混合两个法线贴图。
 * 比简单的相加更正确，保持法线长度。
 * 
 * 参数：
 *   n1 - 第一个法线（法线贴图采样，范围 [0, 1]）
 *   n2 - 第二个法线（法线贴图采样，范围 [0, 1]）
 * 
 * 返回：
 *   混合后的归一化法线
 * 
 * 原理：
 *   Whiteout 混合保持两个法线的细节，
 *   同时产生正确的凹凸效果。
 * 
 * 参考：
 *   "Normal Map Blending in Unity" - Stephen Hill
 */
float3 FFBlendNormal(float3 n1, float3 n2)
{
    // 将 [0, 1] 范围转换为 [-1, 1]
    float3 t = n1 * float3(2, 2, 2) + float3(-1, -1, 0);
    float3 u = n2 * float3(2, 2, 2) + float3(-1, -1, 0);
    // Whiteout 混合公式
    float3 r = t * dot(t, u) - u * t.z;
    return normalize(r);
}

// ═══════════════════════════════════════════════════════════════════════════
// 随机数与抖动函数
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFSampleBlueNoise - 蓝噪声采样
 * 
 * 生成伪随机蓝噪声值。
 * 用于抖动、抗锯齿、Ray Marching 等。
 * 
 * 参数：
 *   screenPos - 屏幕位置（作为随机种子）
 *   time      - 时间（用于动画）
 * 
 * 返回：
 *   伪随机值 [0, 1)
 * 
 * 原理：
 *   使用正弦函数和点积生成伪随机数。
 *   魔法常数 12.9898 和 78.233 是常用的噪声参数。
 * 
 * 注意：
 *   这不是真正的蓝噪声，而是伪随机噪声。
 *   真正的蓝噪声需要预计算的纹理。
 */
float FFSampleBlueNoise(float2 screenPos, float time)
{
    float2 uv = screenPos + time * 0.1;
    return frac(sin(dot(uv, float2(12.9898, 78.233))) * 43758.5453);
}

/*
 * FFSampleDither - 抖动采样
 * 
 * 蓝噪声的别名，用于抖动效果。
 * 
 * 参数：
 *   screenPos - 屏幕位置
 *   time      - 时间
 * 
 * 返回：
 *   抖动值 [0, 1)
 * 
 * 用途：
 *   - Ray Marching 步进偏移
 *   - 消除带状伪影
 *   - 透明度抖动
 */
float FFSampleDither(float2 screenPos, float time)
{
    return FFSampleBlueNoise(screenPos, time);
}

#endif
