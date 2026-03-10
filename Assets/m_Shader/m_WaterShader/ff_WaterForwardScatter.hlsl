/*
 * ═══════════════════════════════════════════════════════════════════════════
 * FluidFlux Water Forward Scatter - 水体前向散射模块
 * ═══════════════════════════════════════════════════════════════════════════
 * 
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │                           原理框架                                      │
 * └─────────────────────────────────────────────────────────────────────────┘
 * 
 * 一、前向散射概述
 * ─────────────────────────────────────────────────────────────────────────
 * 前向散射是指光线穿过介质后，主要沿着原传播方向散射的现象。
 * 在水体渲染中，前向散射产生以下视觉效果：
 * 
 *   1. 次表面散射 (SSS) - 光线穿透水面后在内部散射，产生柔和的辉光
 *   2. 背光透射 - 逆光观看时水面边缘的透光效果
 *   3. 太阳闪烁 - 水面波峰对太阳光的镜面反射闪烁
 * 
 * 二、次表面散射 (SSS) 原理
 * ─────────────────────────────────────────────────────────────────────────
 * 
 * ┌───────────────────────────────────────────────────────────────────────┐
 * │                        SSS 光路示意                                    │
 * │                                                                       │
 * │    太阳 \     / 观察者                                                │
 * │          \   /                                                        │
 * │           \ /                                                         │
 * │    ────────●──────── 水面                                            │
 * │            │\                                                        │
 * │            │ \  光线进入水体后被散射                                  │
 * │            │  \                                                       │
 * │            ●   ●  散射点                                              │
 * │           /     \                                                     │
 * │          /       \                                                    │
 * │         /         \                                                   │
 * │        观察者看到散射光                                                │
 * └───────────────────────────────────────────────────────────────────────┘
 * 
 * SSS 的关键因素：
 *   - 视线方向：掠射角（接近水平）时SSS效果最强
 *   - 光照方向：光线与视线反向时效果最好（背光）
 *   - 水深：深水区域散射更充分，效果更明显
 *   - 法线方向：波峰处的法线变化影响散射分布
 * 
 * 三、SSS 近似计算
 * ─────────────────────────────────────────────────────────────────────────
 * 本模块使用快速近似方法计算SSS，避免昂贵的体积采样：
 * 
 *   1. 深度因子：depthFactor = saturate(waterDepth / depthScale)
 *   2. 面向因子：sssFacePart = dot(viewDir, blendedNormal)
 *   3. 光照因子：lightPart = (1 - viewDir.y)² * dot(lightDir, reflectedView)
 *   4. 最终SSS：sssResult = lightPart * depthSSSColor * lightYFactor * lightColor
 * 
 * 其中 reflectedView = viewDir * (-1, 1, -1) 用于模拟光线反向散射
 * 
 * 四、太阳闪烁 (Sun Glitter) 原理
 * ─────────────────────────────────────────────────────────────────────────
 * 太阳闪烁是水面微小波纹对太阳光的镜面反射产生的闪烁效果。
 * 
 * 计算方法：
 *   1. 计算反射方向：reflectDir = reflect(-viewDir, normal)
 *   2. 计算反射方向与太阳方向的接近程度：RdotL = dot(reflectDir, lightDir)
 *   3. 使用高次幂函数产生尖锐的高光：glitter = pow(RdotL, 256)
 *   4. 可选：添加时间噪声产生闪烁动画
 * 
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │                           使用说明                                      │
 * └─────────────────────────────────────────────────────────────────────────┘
 * 
 * 1. SSS 计算使用：
 *    // 基础版本
 *    float3 sss = FFComputeWaterSSS(
 *        normalWS, vertexNormal, viewDirWS,
 *        lightDir, lightColor, waterDepth,
 *        sssColor, sssStrength, sssDepthScale
 *    );
 *    
 *    // 完整版本（带衰减控制）
 *    float3 sss = FFComputeWaterSSSFull(
 *        normalWS, vertexNormal, viewDirWS,
 *        lightDir, lightColor, waterDepth,
 *        sssColor, sssStrength, sssDepthScale, sssFade
 *    );
 * 
 * 2. 太阳闪烁使用：
 *    // 简单版本
 *    float3 glitter = FFComputeSunGlitterSimple(
 *        normalWS, viewDirWS, lightDirWS,
 *        lightColor, intensity
 *    );
 *    
 *    // 动画版本（带时间噪声）
 *    float3 glitter = FFComputeSunGlitterAnimated(
 *        normalWS, viewDirWS, lightDirWS,
 *        lightColor, roughness, intensity,
 *        _Time.y, speed
 *    );
 * 
 * 3. 参数说明：
 *    - sssColor      : SSS颜色，通常为浅蓝/青色
 *    - sssStrength   : SSS强度 [0, 5]
 *    - sssDepthScale : 深度缩放因子，控制SSS随深度的变化
 *    - sssFade       : SSS衰减向量，用于控制各方向的衰减
 *    - roughness     : 粗糙度，影响闪烁的锐度
 *    - intensity     : 闪烁强度
 *    - speed         : 闪烁动画速度
 * 
 * 4. 视觉效果建议：
 *    - SSS 在夕阳/背光场景效果最明显
 *    - 太阳闪烁需要配合波浪法线使用
 *    - 调整 sssDepthScale 控制深浅水区域的SSS过渡
 * 
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │                           依赖关系                                      │
 * └─────────────────────────────────────────────────────────────────────────┘
 * 
 * ff_WaterForwardScatter.hlsl
 *     └── ff_WaterCommon.hlsl    (基础工具函数)
 * 
 * 被以下文件引用：
 *     └── water.shader          (主着色器)
 * 
 * ═══════════════════════════════════════════════════════════════════════════
 */

#ifndef FF_WATER_FORWARD_SCATTER_INCLUDED
#define FF_WATER_FORWARD_SCATTER_INCLUDED

#include "ff_WaterCommon.hlsl"

// ═══════════════════════════════════════════════════════════════════════════
// 次表面散射 (SSS) 函数
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFComputeWaterSSS - 计算水体次表面散射（基础版）
 * 
 * 使用快速近似方法计算水体的次表面散射效果。
 * 适用于需要基本SSS效果的场景。
 * 
 * 参数：
 *   normalWS      - 世界空间法线（扰动后的波浪法线）
 *   vertexNormal  - 世界空间顶点法线（原始平滑法线）
 *   viewDirWS     - 世界空间视线方向
 *   lightDir      - 光源方向
 *   lightColor    - 光源颜色
 *   waterDepth    - 水深
 *   sssColor      - SSS颜色
 *   sssStrength   - SSS强度
 *   sssDepthScale - 深度缩放因子
 * 
 * 返回：
 *   SSS散射颜色
 * 
 * 算法要点：
 *   1. 深度因子控制SSS随水深的变化
 *   2. 面向因子根据视线角度调整强度
 *   3. 光照因子模拟背光透射效果
 */
float3 FFComputeWaterSSS(
    float3 normalWS,
    float3 vertexNormal,
    float3 viewDirWS,
    float3 lightDir,
    float3 lightColor,
    float waterDepth,
    float3 sssColor,
    float sssStrength,
    float sssDepthScale)
{
    // 计算深度因子：水深越深，SSS效果越强
    float depthFactor = saturate(waterDepth / sssDepthScale);
    
    float3 sssResult = 0;
    
    // 计算面向因子：混合顶点法线和波浪法线
    // 使用混合法线避免波浪扰动导致的SSS闪烁
    float sssFacePart = saturate(dot(viewDirWS, lerp(vertexNormal, normalWS, 0.3)));
    sssFacePart *= sssStrength;
    
    // 计算深度相关的SSS颜色
    float3 depthSSSColor = sssColor * depthFactor;
    depthSSSColor = depthSSSColor * sssFacePart;
    
    // 计算光照因子
    // (1 - viewDir.y)² 使掠射角（水平视线）时效果最强
    float lightPart = 1.0 - viewDirWS.y;
    lightPart *= lightPart;
    
    // 反射视线方向，用于计算背光效果
    // viewDir * (-1, 1, -1) 将视线在XZ平面反射
    float3 reflectedView = viewDirWS * float3(-1, 1, -1);
    // 与光照方向的点积决定背光强度
    lightPart = (dot(lightDir, reflectedView) + 1.0) * lightPart;
    
    // 光源Y因子：太阳越高，SSS越强
    float lightYFactor = saturate(lightDir.y);
    // 最终SSS结果
    sssResult = lightPart * depthSSSColor * lightYFactor * lightColor;
    
    return sssResult;
}

/*
 * FFComputeWaterSSSFull - 计算水体次表面散射（完整版）
 * 
 * 带额外衰减控制的完整SSS计算。
 * 提供更精细的控制参数。
 * 
 * 参数：
 *   normalWS      - 世界空间法线
 *   vertexNormal  - 世界空间顶点法线
 *   viewDirWS     - 世界空间视线方向
 *   lightDir      - 光源方向
 *   lightColor    - 光源颜色
 *   waterDepth    - 水深
 *   sssColor      - SSS颜色
 *   sssStrength   - SSS强度
 *   sssDepthScale - 深度缩放因子
 *   sssFade       - SSS衰减向量，用于控制各方向的衰减
 * 
 * 返回：
 *   SSS散射颜色
 * 
 * 与基础版的区别：
 *   - sssFade 参数允许对视线方向进行额外的衰减控制
 *   - 可用于实现方向性的SSS效果
 */
float3 FFComputeWaterSSSFull(
    float3 normalWS,
    float3 vertexNormal,
    float3 viewDirWS,
    float3 lightDir,
    float3 lightColor,
    float waterDepth,
    float3 sssColor,
    float sssStrength,
    float sssDepthScale,
    float sssFade)
{
    // 计算深度因子
    float depthFactor = saturate(waterDepth / sssDepthScale);
    
    float3 sssResult = 0;
    
    // 混合法线计算面向因子
    float3 blendedNormal = lerp(vertexNormal, normalWS, 0.3);
    // 使用sssFade对视线方向进行衰减
    float sssFacePart = saturate(dot(sssFade * viewDirWS, blendedNormal)) * sssStrength;
    
    // 计算深度相关的SSS颜色
    float3 depthSSSColor = sssColor * depthFactor * sssFacePart;
    
    // 计算光照因子
    float lightPart = 1.0 - viewDirWS.y;
    lightPart *= lightPart;
    
    // 反射视线计算背光效果
    float3 reflectedView = viewDirWS * float3(-1, 1, -1);
    lightPart = (dot(lightDir, reflectedView) + 1.0) * lightPart;
    
    // 光源Y因子
    float lightYFactor = saturate(lightDir.y);
    // 最终结果
    sssResult = lightPart * depthSSSColor * lightYFactor * lightColor;
    
    return sssResult;
}

// ═══════════════════════════════════════════════════════════════════════════
// 太阳闪烁 (Sun Glitter) 函数
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFComputeSunGlitterSimple - 计算太阳闪烁（简单版）
 * 
 * 使用高次幂镜面反射计算水面闪烁效果。
 * 简单高效，适合静态或缓慢变化的水面。
 * 
 * 参数：
 *   normalWS    - 世界空间法线
 *   viewDirWS   - 世界空间视线方向
 *   lightDirWS  - 世界空间光源方向
 *   lightColor  - 光源颜色
 *   intensity   - 闪烁强度
 * 
 * 返回：
 *   闪烁颜色
 * 
 * 原理：
 *   1. 计算视线在法线方向的反射
 *   2. 计算反射方向与光源方向的接近程度
 *   3. 使用256次幂产生极尖锐的高光
 */
float3 FFComputeSunGlitterSimple(
    float3 normalWS,
    float3 viewDirWS,
    float3 lightDirWS,
    float3 lightColor,
    float intensity)
{
    // 计算反射方向
    float3 reflectDir = reflect(-viewDirWS, normalWS);
    // 计算反射方向与光源方向的点积
    float RdotL = saturate(dot(reflectDir, lightDirWS));
    
    // 使用高次幂产生尖锐的闪烁效果
    // 256次幂使高光非常集中，模拟微小波纹的镜面反射
    float glitter = pow(RdotL, 256.0);
    
    return lightColor * glitter * intensity;
}

/*
 * FFComputeSunGlitterAnimated - 计算太阳闪烁（动画版）
 * 
 * 带时间噪声的太阳闪烁，产生动态闪烁效果。
 * 适合需要动态表现的水面场景。
 * 
 * 参数：
 *   normalWS    - 世界空间法线
 *   viewDirWS   - 世界空间视线方向
 *   lightDirWS  - 世界空间光源方向
 *   lightColor  - 光源颜色
 *   roughness   - 粗糙度 [0, 1]，影响闪烁锐度
 *   intensity   - 闪烁强度
 *   time        - 当前时间（通常使用 _Time.y）
 *   speed       - 闪烁动画速度
 * 
 * 返回：
 *   闪烁颜色
 * 
 * 特点：
 *   - 基于时间的噪声产生随机闪烁
 *   - roughness 控制闪烁的锐度（粗糙度越高，闪烁越柔和）
 *   - 适合表现真实水面上的阳光闪烁
 */
float3 FFComputeSunGlitterAnimated(
    float3 normalWS,
    float3 viewDirWS,
    float3 lightDirWS,
    float3 lightColor,
    float roughness,
    float intensity,
    float time,
    float speed)
{
    // 计算反射方向
    float3 reflectDir = reflect(-viewDirWS, normalWS);
    // 计算反射方向与光源方向的点积
    float RdotL = saturate(dot(reflectDir, lightDirWS));
    
    // 生成基于时间的随机噪声
    // 使用 floor(time * speed) 使噪声在短时间内保持稳定
    // 然后突然变化，产生闪烁效果
    float noise = frac(sin(dot(floor(time * speed), float2(12.9898, 78.233))) * 43758.5453);
    
    // 根据粗糙度调整高光锐度
    // roughness = 0 时使用256次幂（极尖锐）
    // roughness = 1 时使用64次幂（较柔和）
    float specularPower = lerp(256.0, 64.0, roughness);
    // 将噪声融入高光计算，产生闪烁变化
    float glitter = pow(RdotL * (0.8 + 0.2 * noise), specularPower);
    
    return lightColor * glitter * intensity;
}

#endif
