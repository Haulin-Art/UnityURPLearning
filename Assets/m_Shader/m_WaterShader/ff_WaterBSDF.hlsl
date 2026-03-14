/*
 * ═══════════════════════════════════════════════════════════════════════════
 * FluidFlux Water BSDF - 水体双向散射分布函数模块
 * ═══════════════════════════════════════════════════════════════════════════
 * 
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │                           原理框架                                      │
 * └─────────────────────────────────────────────────────────────────────────┘
 * 
 * 一、BSDF 双通道模型概述
 * ─────────────────────────────────────────────────────────────────────────
 * 本模块实现了基于 HPWater 的水体 BSDF (Bidirectional Scattering Distribution Function)
 * 双通道散射模型，将水体散射分为两个独立通道进行计算：
 * 
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │                    最终输出                                             │
 * │         output = (diffR + diffT) * T_exit                              │
 * └─────────────────────────────────────────────────────────────────────────┘
 *                              │
 *              ┌───────────────┴───────────────┐
 *              ▼                               ▼
 * ┌─────────────────────────┐     ┌─────────────────────────────┐
 * │   diffR 宏观体积散射     │     │      diffT 薄层散射         │
 * │                         │     │                             │
 * │  G_entry * T_entry      │     │  thinLayerSSS项 +           │
 * │  * S_volume             │     │  backlitTransmission项      │
 * │                         │     │                             │
 * │  适用：深水区域          │     │  适用：波峰、浪花、薄层      │
 * │  方法：近似体积散射      │     │  方法：快速近似计算          │
 * └─────────────────────────┘     └─────────────────────────────┘
 * 
 * 二、入射几何项 (Incident Geometry)
 * ─────────────────────────────────────────────────────────────────────────
 * 根据光线与法线的夹角，将入射光分配到不同的散射通道：
 * 
 *   G_entry   = saturate(N·L)     正面入射几何项，光线直接照射水面
 *   G_sss     = 1 - G_entry       侧面入射几何项，光线掠射水面
 *   G_backlit = saturate(-N·L)    背面入射几何项，光线从水下照射
 *   T_entry   = 1 - Fresnel       入射菲涅尔透射率
 * 
 * 三、体积散射计算 (Volume Scattering)
 * ─────────────────────────────────────────────────────────────────────────
 * 使用 Beer-Lambert 定律计算光线在水中的衰减和散射：
 * 
 *   透射率：T = e^(-σ_t * d)
 *   消光因子：extinction = 1 - T
 *   散射光：L_s = L_in * extinction * ω * P(θ)
 * 
 * 其中：
 *   σ_t = σ_s + σ_a    消光系数（散射+吸收）
 *   ω = σ_s / σ_t      散射反照率
 *   P(θ)               相位函数值
 *   d                  光程长度
 * 
 * 四、薄层SSS (Subsurface Scattering)
 * ─────────────────────────────────────────────────────────────────────────
 * 对于薄水层（波峰、浪花），使用非线性光程修正：
 * 
 *   linearPath    = thickness * pathScale
 *   nonlinearPath = thickness² * pathScale * (1 + luminance(σ_s))
 *   effectivePath = lerp(linearPath, nonlinearPath, strengthFactor)
 * 
 * 非线性修正使薄层区域的散射更加明显，模拟真实的水体次表面散射效果。
 * 
 * 五、背光透射 (Backlit Transmission)
 * ─────────────────────────────────────────────────────────────────────────
 * 当光线从水面下方照射时（如夕阳照射波浪背面），产生透射辉光：
 * 
 *   使用极强前向散射相位函数 (g = 0.998)
 *   透射光 = L * T * P_backlit * G_backlit
 * 
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │                           使用说明                                      │
 * └─────────────────────────────────────────────────────────────────────────┘
 * 
 * 1. 基本使用流程：
 *    // 方式一：使用便捷函数
 *    float3 scattering = FFEvaluateWaterScattering(
 *        normalWS, viewDirWS, lightDirWS, lightColor,
 *        scatterColor, absorptionColor, thickness,
 *        fresnel0, phaseG, shadowValue
 *    );
 *    
 *    // 方式二：使用完整BSDF结构
 *    FFWaterBSDFInput input;
 *    input.scatterCoeff = scatterColor;
 *    input.absorptionCoeff = absorptionColor;
 *    // ... 设置其他参数
 *    FFWaterBSDFOutput output = FFEvaluateWaterBSDFSimple(input);
 *    float3 scattering = output.totalScattering;
 * 
 * 2. 参数说明：
 *    - scatterColor    : 散射系数 σ_s，控制散射强度和颜色
 *    - absorptionColor : 吸收系数 σ_a，控制吸收强度和颜色
 *    - thickness       : 归一化厚度 [0, 1]，0=极薄，1=最深
 *    - fresnel0        : 菲涅尔基础反射率，水约为 0.02
 *    - phaseG          : HG相位参数，水体典型值 0.8
 *    - shadowValue     : 阴影值 [0, 1]，0=无阴影
 * 
 * 3. 输出结构说明：
 *    - diffR           : 宏观体积散射分量
 *    - diffT           : 薄层散射分量（SSS + 背光透射）
 *    - totalScattering : 最终总散射（已乘以出射透射率）
 * 
 * 4. 性能建议：
 *    - 对于深水区域，可只使用 diffR 分量
 *    - 对于浅水/波峰，diffT 分量更重要
 *    - thickness 参数对结果影响显著，需合理设置
 * 
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │                           依赖关系                                      │
 * └─────────────────────────────────────────────────────────────────────────┘
 * 
 * ff_WaterBSDF.hlsl
 *     ├── ff_WaterCommon.hlsl    (基础工具函数)
 *     ├── ff_WaterFresnel.hlsl   (菲涅尔计算)
 *     └── ff_WaterPhase.hlsl     (相位函数)
 * 
 * 被以下文件引用：
 *     └── water.shader          (主着色器)
 * 
 * ═══════════════════════════════════════════════════════════════════════════
 */

#ifndef FF_WATER_BSDF_INCLUDED
#define FF_WATER_BSDF_INCLUDED

#include "ff_WaterCommon.hlsl"
#include "ff_WaterFresnel.hlsl"
#include "ff_WaterPhase.hlsl"

// ═══════════════════════════════════════════════════════════════════════════
// 常量定义
// ═══════════════════════════════════════════════════════════════════════════

#define FF_SSS_PATH_SCALE 20.0        // SSS光程缩放因子
#define FF_SSS_NONLINEAR_STRENGTH 0.5 // 非线性光程强度
#define FF_SSS_SCATTER_BOOST 1.5      // SSS散射增强因子
#define FF_BACKLIT_PATH_SCALE 10.0     // 背光透射光程缩放

// ═══════════════════════════════════════════════════════════════════════════
// 结构体定义
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFWaterBSDFInput - BSDF输入参数结构体
 * 
 * 包含计算水体散射所需的所有输入参数。
 */
struct FFWaterBSDFInput
{
    float3 scatterCoeff;       // 散射系数 σ_s
    float3 absorptionCoeff;    // 吸收系数 σ_a
    float3 extinctionCoeff;    // 消光系数 σ_t = σ_s + σ_a
    float3 scatterAlbedo;      // 散射反照率 ω = σ_s / σ_t
    
    float thickness;           // 归一化厚度 [0, 1]
    float fresnel0;            // 菲涅尔基础反射率
    float phaseG;              // HG相位函数参数g
    
    float3 normalWS;           // 世界空间法线
    float3 viewDirWS;          // 世界空间视线方向
    float3 lightDirWS;         // 世界空间光源方向
    float3 lightColor;         // 光源颜色
    
    float shadowValue;         // 阴影值 [0, 1]
};

/*
 * FFWaterBSDFOutput - BSDF输出结构体
 * 
 * 包含BSDF计算的各个分量结果。
 */
struct FFWaterBSDFOutput
{
    float3 diffR;              // 宏观体积散射分量
    float3 diffT;              // 薄层散射分量
    float3 totalScattering;    // 最终总散射
};

/*
 * FFIncidentGeometry - 入射几何项结构体
 * 
 * 描述光线入射到水面的几何关系。
 */
struct FFIncidentGeometry
{
    float G_entry;             // 正面入射几何项 saturate(N·L)
    float G_sss;               // 侧面入射几何项 1 - G_entry
    float G_backlit;           // 背面入射几何项 saturate(-N·L)
    float T_entry;             // 入射菲涅尔透射率
};

// ═══════════════════════════════════════════════════════════════════════════
// 入射几何计算
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFComputeIncidentGeometry - 计算入射几何项
 * 
 * 根据法线和光源方向计算光线入射的几何关系，
 * 用于分配不同散射通道的能量。
 * 
 * 参数：
 *   normalWS   - 世界空间法线
 *   lightDirWS - 世界空间光源方向
 *   fresnel0   - 菲涅尔基础反射率
 * 
 * 返回：
 *   包含各几何项的结构体
 * 
 * 几何意义：
 *   - G_entry:   光线从上方照射水面，产生正面散射
 *   - G_sss:     光线掠射水面，产生侧面SSS效果
 *   - G_backlit: 光线从下方照射，产生背光透射
 */
FFIncidentGeometry FFComputeIncidentGeometry(float3 normalWS, float3 lightDirWS, float fresnel0)
{
    FFIncidentGeometry geo;
    
    // 计算法线与光源方向的点积
    float NdotL = dot(normalWS, lightDirWS);
    
    // 正面入射：光线与法线同向
    geo.G_entry = saturate(NdotL);
    // 侧面入射：用于SSS计算
    geo.G_sss = 1.0 - geo.G_entry;
    // 背面入射：光线与法线反向
    geo.G_backlit = saturate(-NdotL);
    
    // 入射菲涅尔透射率
    geo.T_entry = FFFresnelTransmission(fresnel0, saturate(abs(NdotL)));
    
    return geo;
}

// ═══════════════════════════════════════════════════════════════════════════
// 散射光计算
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFCalculateScatteredLight - 计算散射光
 * 
 * 核心散射计算函数，基于 Beer-Lambert 定律。
 * 
 * 参数：
 *   lightColor     - 入射光颜色
 *   extinctionCoeff - 消光系数 σ_t
 *   scatterAlbedo  - 散射反照率 ω
 *   opticalDepth   - 光学深度
 *   phaseValue     - 相位函数值
 *   shadowValue    - 阴影值
 * 
 * 返回：
 *   散射光颜色
 * 
 * 公式：
 *   L_s = L_in * (1 - e^(-σ_t * d)) * ω * P(θ) * (1 - shadow)
 */
float3 FFCalculateScatteredLight(
    float3 lightColor,
    float3 extinctionCoeff,
    float3 scatterAlbedo,
    float opticalDepth,
    float phaseValue,
    float shadowValue)
{
    // Beer-Lambert 透射率
    float3 transmittance = exp(-extinctionCoeff * opticalDepth);
    // 消光因子：被散射或吸收的光比例
    float3 extinctionFactor = 1.0 - transmittance;
    // 散射光 = 入射光 * 消光因子 * 散射反照率 * 相位函数
    float3 scatteredLight = lightColor * extinctionFactor * scatterAlbedo * phaseValue;
    // 应用阴影
    scatteredLight *= (1.0 - shadowValue);
    
    return scatteredLight;
}

/*
 * FFCalculateScatteredLightSimple - 简化版散射光计算
 * 
 * 不考虑吸收的简化版本，仅使用散射系数。
 * 适用于快速近似计算。
 */
float3 FFCalculateScatteredLightSimple(
    float3 lightColor,
    float3 scatterCoeff,
    float opticalDepth,
    float phaseValue)
{
    float3 transmittance = exp(-scatterCoeff * opticalDepth);
    float3 scatteredLight = lightColor * (1.0 - transmittance) * phaseValue;
    
    return scatteredLight;
}

// ═══════════════════════════════════════════════════════════════════════════
// 光程计算
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFComputeEffectivePathLength - 计算有效光程长度
 * 
 * 使用非线性修正计算有效光程，使薄层区域的散射更加明显。
 * 
 * 参数：
 *   thickness   - 归一化厚度
 *   scatterCoeff - 散射系数
 *   pathScale   - 光程缩放因子
 * 
 * 返回：
 *   有效光程长度
 * 
 * 原理：
 *   - 线性光程：thickness * pathScale
 *   - 非线性光程：thickness² * pathScale * (1 + luminance(σ_s))
 *   - 根据光学深度在两者间插值
 * 
 * 非线性修正使薄层（如波峰）的SSS效果更明显，
 * 同时避免厚层区域的过度散射。
 */
float FFComputeEffectivePathLength(float thickness, float3 scatterCoeff, float pathScale)
{
    // 线性光程
    float linearPath = thickness * pathScale;
    // 非线性光程：厚度平方项使薄层效果增强
    float nonlinearPath = thickness * thickness * pathScale * (1.0 + FFLuminance(scatterCoeff));
    
    // 计算光学深度决定插值权重
    float opticalDepth = FFLuminance(scatterCoeff) * thickness * pathScale;
    float strengthFactor = FF_SSS_NONLINEAR_STRENGTH * opticalDepth;
    
    // 在线性和非线性之间插值
    float effectivePath = lerp(linearPath, nonlinearPath, saturate(strengthFactor));
    
    return effectivePath;
}

// ═══════════════════════════════════════════════════════════════════════════
// 薄层SSS计算
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFComputeThinLayerSSS - 计算薄层次表面散射
 * 
 * 专门针对薄水层（波峰、浪花）的SSS计算。
 * 使用非线性光程修正和深水散射回退机制。
 * 
 * 参数：
 *   input            - BSDF输入参数
 *   geo              - 入射几何项
 *   volumeScattering - 体积散射结果（用于回退混合）
 * 
 * 返回：
 *   薄层SSS散射颜色
 * 
 * 特点：
 *   1. 非线性光程修正增强薄层效果
 *   2. 散射增强因子提升视觉表现
 *   3. 根据透射率自动回退到体积散射
 */
float3 FFComputeThinLayerSSS(
    FFWaterBSDFInput input,
    FFIncidentGeometry geo,
    float3 volumeScattering)
{
    // 计算有效光程（非线性修正）
    float effectivePath = FFComputeEffectivePathLength(
        input.thickness, 
        input.scatterCoeff, 
        FF_SSS_PATH_SCALE
    );
    
    // 计算光学深度
    float opticalDepth = FFLuminance(input.extinctionCoeff) * effectivePath;
    
    // 计算相位函数
    float cosTheta = FFComputePhaseCosTheta(input.viewDirWS, input.lightDirWS);
    float phaseValue = FFWaterPhaseFunctionFast(input.phaseG, cosTheta);
    
    // 计算薄层散射
    float3 thinLayerScatter = FFCalculateScatteredLight(
        input.lightColor,
        input.extinctionCoeff,
        input.scatterAlbedo,
        opticalDepth,
        phaseValue,
        input.shadowValue
    );
    
    // 散射增强：补偿薄层散射的能量损失
    thinLayerScatter *= FF_SSS_SCATTER_BOOST;
    
    // 计算透射率，用于回退混合
    float3 transmittance = exp(-input.extinctionCoeff * effectivePath);
    float sssWeight = 1.0 - FFLuminance(transmittance);
    
    // 根据透射率在薄层散射和体积散射间插值
    // 透射率低时使用薄层SSS，透射率高时回退到体积散射
    float3 result = lerp(volumeScattering, thinLayerScatter, sssWeight);
    // 应用侧面入射几何项
    result *= geo.G_sss;
    
    return result;
}

// ═══════════════════════════════════════════════════════════════════════════
// 背光透射计算
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFComputeBacklitTransmission - 计算背光透射
 * 
 * 当光线从水面下方照射时（如夕阳照射波浪背面），
 * 产生美丽的透射辉光效果。
 * 
 * 参数：
 *   input - BSDF输入参数
 *   geo   - 入射几何项
 * 
 * 返回：
 *   背光透射颜色
 * 
 * 特点：
 *   - 使用极强前向散射相位函数 (g = 0.998)
 *   - 仅在背面入射时生效 (G_backlit > 0)
 *   - 适合表现夕阳下的波浪透光效果
 */
float3 FFComputeBacklitTransmission(
    FFWaterBSDFInput input,
    FFIncidentGeometry geo)
{
    // 计算有效光程
    float effectivePath = input.thickness * FF_BACKLIT_PATH_SCALE;
    
    // 计算透射率
    float3 transmittance = exp(-input.extinctionCoeff * effectivePath);
    
    // 使用背光专用相位函数（极强前向散射）
    float cosTheta = FFComputePhaseCosTheta(input.viewDirWS, input.lightDirWS);
    float phaseValue = FFPhaseWaterBacklitFast(cosTheta);
    
    // 计算背光透射结果
    float3 backlitResult = input.lightColor * transmittance * phaseValue;
    // 应用背面入射几何项
    backlitResult *= geo.G_backlit;
    // 应用阴影
    backlitResult *= (1.0 - input.shadowValue);
    
    return backlitResult;
}

// ═══════════════════════════════════════════════════════════════════════════
// 体积散射计算
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFComputeVolumeScatteringSimple - 简化体积散射计算
 * 
 * 计算宏观体积散射，适用于深水区域。
 * 使用有效光程进行近似计算，避免完整的Ray Marching。
 * 
 * 参数：
 *   input - BSDF输入参数
 *   geo   - 入射几何项
 * 
 * 返回：
 *   体积散射颜色
 */
float3 FFComputeVolumeScatteringSimple(
    FFWaterBSDFInput input,
    FFIncidentGeometry geo)
{
    // 计算有效光程
    float effectivePath = FFComputeEffectivePathLength(
        input.thickness, 
        input.scatterCoeff, 
        FF_SSS_PATH_SCALE
    );
    
    // 计算光学深度和相位函数
    float opticalDepth = FFLuminance(input.extinctionCoeff) * effectivePath;
    float cosTheta = FFComputePhaseCosTheta(input.viewDirWS, input.lightDirWS);
    float phaseValue = FFWaterPhaseFunctionFast(input.phaseG, cosTheta);
    
    // 计算体积散射
    float3 volumeScatter = FFCalculateScatteredLight(
        input.lightColor,
        input.extinctionCoeff,
        input.scatterAlbedo,
        opticalDepth,
        phaseValue,
        input.shadowValue
    );
    
    return volumeScatter;
}

// ═══════════════════════════════════════════════════════════════════════════
// BSDF主评估函数
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFEvaluateWaterBSDFSimple - 评估水体BSDF（简化版）
 * 
 * 主BSDF评估函数，整合所有散射通道。
 * 
 * 参数：
 *   input - BSDF输入参数结构体
 * 
 * 返回：
 *   BSDF输出结构体，包含各散射分量
 * 
 * 计算流程：
 *   1. 计算入射几何项
 *   2. 计算体积散射 (diffR)
 *   3. 计算薄层SSS和背光透射 (diffT)
 *   4. 应用出射菲涅尔透射率
 */
FFWaterBSDFOutput FFEvaluateWaterBSDFSimple(FFWaterBSDFInput input)
{
    FFWaterBSDFOutput output = (FFWaterBSDFOutput)0;
    
    // Step 1: 计算入射几何项
    FFIncidentGeometry geo = FFComputeIncidentGeometry(
        input.normalWS, 
        input.lightDirWS, 
        input.fresnel0
    );
    
    // Step 2: 计算体积散射
    float3 volumeScatter = FFComputeVolumeScatteringSimple(input, geo);
    
    // Step 3: 计算diffR（宏观体积散射）
    // diffR = 正面入射 * 入射透射率 * 体积散射
    output.diffR = geo.G_entry * geo.T_entry * volumeScatter;
    
    // Step 4: 计算diffT（薄层散射）
    // diffT = 薄层SSS + 背光透射
    float3 thinLayerSSS = FFComputeThinLayerSSS(input, geo, volumeScatter);
    float3 backlitTransmission = FFComputeBacklitTransmission(input, geo);
    output.diffT = thinLayerSSS + backlitTransmission;
    
    // Step 5: 应用出射菲涅尔透射率
    float T_exit = FFFresnelExit(input.fresnel0, input.normalWS, input.viewDirWS);
    output.totalScattering = (output.diffR + output.diffT) * lerp(T_exit,1.0,0.0);
    
    return output;
}

// ═══════════════════════════════════════════════════════════════════════════
// 便捷函数
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFEvaluateWaterScattering - 便捷水体散射计算函数
 * 
 * 提供简化的函数接口，直接返回总散射结果。
 * 适用于不需要访问各分量的场景。
 * 
 * 参数：
 *   normalWS        - 世界空间法线
 *   viewDirWS       - 世界空间视线方向
 *   lightDirWS      - 世界空间光源方向
 *   lightColor      - 光源颜色
 *   scatterColor    - 散射系数（颜色）
 *   absorptionColor - 吸收系数（颜色）
 *   thickness       - 归一化厚度 [0, 1]
 *   fresnel0        - 菲涅尔基础反射率
 *   phaseG          - HG相位参数
 *   shadowValue     - 阴影值 [0, 1]
 * 
 * 返回：
 *   总散射颜色
 */
float3 FFEvaluateWaterScattering(
    float3 normalWS,
    float3 viewDirWS,
    float3 lightDirWS,
    float3 lightColor,
    float3 scatterColor,
    float3 absorptionColor,
    float thickness,
    float fresnel0,
    float phaseG,
    float shadowValue)
{
    // 构建输入结构体
    FFWaterBSDFInput input;
    input.scatterCoeff = scatterColor;
    input.absorptionCoeff = absorptionColor;
    input.extinctionCoeff = scatterColor + absorptionColor;
    input.scatterAlbedo = scatterColor / max(input.extinctionCoeff, 1e-6);
    input.thickness = thickness;
    input.fresnel0 = fresnel0;
    input.phaseG = phaseG;
    input.normalWS = normalWS;
    input.viewDirWS = viewDirWS;
    input.lightDirWS = lightDirWS;
    input.lightColor = lightColor;
    input.shadowValue = shadowValue;
    
    // 评估BSDF
    FFWaterBSDFOutput output = FFEvaluateWaterBSDFSimple(input);
    
    return output.totalScattering  ;
}

#endif
