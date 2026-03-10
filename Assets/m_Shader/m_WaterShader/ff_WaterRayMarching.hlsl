/*
 * ═══════════════════════════════════════════════════════════════════════════
 * FluidFlux Water Ray Marching - 光线步进体积散射模块
 * ═══════════════════════════════════════════════════════════════════════════
 * 
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │                           原理框架                                      │
 * └─────────────────────────────────────────────────────────────────────────┘
 * 
 * 一、光线步进 (Ray Marching) 基本原理
 * ─────────────────────────────────────────────────────────────────────────
 * 光线步进是一种体积渲染技术，通过沿着视线方向逐步采样，
 * 累积计算光线穿过参与介质（如水、雾、云）时的散射效果。
 * 
 * 核心公式：
 *   L_out = ∫ L_in * σ_s * P(θ) * T(x) dx
 * 
 * 其中：
 *   L_out    - 出射辐射亮度
 *   L_in     - 入射光（直接光照）
 *   σ_s      - 散射系数 (scatterCoeff)
 *   P(θ)     - 相位函数，描述散射方向分布
 *   T(x)     - 透射率，T = e^(-σ_t * d)，描述光线被吸收的程度
 *   σ_t      - 消光系数 = σ_s + σ_a (散射 + 吸收)
 * 
 * 二、指数步进优化
 * ─────────────────────────────────────────────────────────────────────────
 * 传统均匀步进在远处浪费采样，近处采样不足。
 * 指数步进使采样点在近处密集、远处稀疏，提高效率。
 * 
 * 位置计算公式：
 *   pos(t) = (e^(k*t) - 1) / (e^k - 1)
 * 
 * 其中：
 *   t  - 归一化参数 [0, 1]
 *   k  - 指数因子，控制密度分布
 *   k值越大，近处采样越密集
 * 
 * 三、散射累积算法
 * ─────────────────────────────────────────────────────────────────────────
 * 每步的贡献计算：
 *   1. 计算当前步的透射率：T_step = e^(-σ_t * stepSize)
 *   2. 计算消光因子：extinction = 1 - T_step
 *   3. 计算散射贡献：scatter = L * extinction * ω * P(θ)
 *   4. 累积：totalScatter += scatter * accumulatedTransmittance
 *   5. 更新累积透射率：accumulatedTransmittance *= T_step
 * 
 * 其中 ω = σ_s / σ_t 为散射反照率 (scatterAlbedo)
 * 
 * 四、抖动去伪影
 * ─────────────────────────────────────────────────────────────────────────
 * 固定步长会产生带状伪影 (banding artifacts)。
 * 通过在采样位置添加随机偏移 (dithering)，打破规律性，消除伪影。
 * 
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │                           使用说明                                      │
 * └─────────────────────────────────────────────────────────────────────────┘
 * 
 * 1. 基本使用流程：
 *    a) 创建配置：FFRayMarchConfig config = FFCreateDefaultRayMarchConfig();
 *    b) 设置参数：config.stepCount = 8; config.maxDistance = 20.0;
 *    c) 调用计算：float3 scatter = FFRayMarchVolumeScattering(...);
 * 
 * 2. 配置参数说明：
 *    - stepCount      : 步进次数 (1-16)，越多越精确但越慢
 *    - expFactor      : 指数因子 (默认3.0)，控制采样密度分布
 *    - maxDistance    : 最大步进距离，限制计算范围
 *    - jitterStrength : 抖动强度 (0-1)，消除带状伪影
 * 
 * 3. 性能建议：
 *    - 移动端：stepCount = 4-6
 *    - PC端：stepCount = 8-12
 *    - 高质量：stepCount = 16+
 * 
 * 4. 函数选择指南：
 *    - FFRayMarchVolumeScattering()     : 完整版，指数步进，推荐使用
 *    - FFRayMarchVolumeScatteringLinear(): 线性步进，简单但效果一般
 *    - FFFastVolumeScattering()         : 快速近似，无迭代，性能最佳
 *    - FFRayMarchDeepWater()            : 深水专用，自动设置光线方向
 * 
 * 5. 与主Shader集成示例：
 *    #ifdef _USE_RAY_MARCHING
 *        FFRayMarchConfig rmConfig = FFCreateDefaultRayMarchConfig();
 *        rmConfig.stepCount = (int)_RayMarchSteps;
 *        rmConfig.maxDistance = min(waterDepth, _RayMarchMaxDistance);
 *        
 *        float3 rayDir = -viewDirWS;
 *        rayDir.y = -abs(rayDir.y);
 *        rayDir = normalize(rayDir);
 *        
 *        bsdfScattering = FFRayMarchVolumeScattering(
 *            worldPos, rayDir, rmConfig.maxDistance,
 *            extinctionCoeff, scatterAlbedo,
 *            lightDir, viewDirWS, lightColor,
 *            _PhaseG, 0.0, rmConfig
 *        );
 *    #endif
 * 
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │                           依赖关系                                      │
 * └─────────────────────────────────────────────────────────────────────────┘
 * 
 * ff_WaterRayMarching.hlsl
 *     ├── ff_WaterCommon.hlsl    (基础工具函数、常量定义)
 *     └── ff_WaterPhase.hlsl     (相位函数计算)
 * 
 * 被以下文件引用：
 *     └── water.shader          (主着色器)
 * 
 * ═══════════════════════════════════════════════════════════════════════════
 */

#ifndef FF_WATER_RAY_MARCHING_INCLUDED
#define FF_WATER_RAY_MARCHING_INCLUDED

#include "ff_WaterCommon.hlsl"
#include "ff_WaterPhase.hlsl"

// ═══════════════════════════════════════════════════════════════════════════
// 常量定义
// ═══════════════════════════════════════════════════════════════════════════

#define FF_RAY_MARCH_STEPS_DEFAULT 6    // 默认步进次数
#define FF_EXP_FACTOR_DEFAULT 3.0       // 默认指数因子

// ═══════════════════════════════════════════════════════════════════════════
// 结构体定义
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFRayMarchConfig - 光线步进配置结构体
 * 
 * 用于控制光线步进算法的各项参数，平衡质量与性能。
 */
struct FFRayMarchConfig
{
    int stepCount;          // 步进次数，影响精度和性能
    float expFactor;        // 指数因子，控制采样点分布密度
    float maxDistance;      // 最大步进距离，限制计算范围
    float jitterStrength;   // 抖动强度，用于消除带状伪影
};

/*
 * FFCreateDefaultRayMarchConfig - 创建默认配置
 * 
 * 返回一个预设合理默认值的配置结构体。
 * 可根据需要修改个别参数。
 */
FFRayMarchConfig FFCreateDefaultRayMarchConfig()
{
    FFRayMarchConfig config;
    config.stepCount = FF_RAY_MARCH_STEPS_DEFAULT;
    config.expFactor = FF_EXP_FACTOR_DEFAULT;
    config.maxDistance = 100.0;
    config.jitterStrength = 1.0;
    return config;
}

// ═══════════════════════════════════════════════════════════════════════════
// 步进位置计算函数
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFGetExponentialStepPosition - 计算指数步进位置
 * 
 * 将线性参数t映射到指数分布的位置，实现近密远疏的采样。
 * 
 * 参数：
 *   t - 归一化参数 [0, 1]，表示第i步占总步数的比例
 *   k - 指数因子，控制曲线形状
 *   n - 总步数（当前未使用，保留用于扩展）
 * 
 * 返回：
 *   归一化位置 [0, 1]，乘以maxDistance得到实际距离
 * 
 * 数学原理：
 *   pos(t) = (e^(k*t) - 1) / (e^k - 1)
 * 
 * 当k=0时退化为线性分布，k越大近处越密集
 */
float FFGetExponentialStepPosition(float t, float k, float n)
{
    float denom = exp(k) - 1.0;
    return (exp(k * t) - 1.0) / denom;
}

/*
 * FFGetExponentialStepSize - 计算当前步的步长
 * 
 * 根据指数分布计算当前采样点到下一个采样点的距离。
 * 
 * 参数：
 *   t           - 归一化参数
 *   k           - 指数因子
 *   n           - 总步数
 *   maxDistance - 最大距离
 * 
 * 返回：
 *   当前步的实际步长
 */
float FFGetExponentialStepSize(float t, float k, float n, float maxDistance)
{
    // 计算当前位置和下一位置
    float posCurrent = FFGetExponentialStepPosition(t, k, n);
    float posNext = FFGetExponentialStepPosition(t + 1.0 / n, k, n);
    // 步长 = 位置差 * 最大距离
    return (posNext - posCurrent) * maxDistance;
}

/*
 * FFGetLinearStepSize - 计算线性步长
 * 
 * 简单的均匀步进，每步距离相同。
 * 
 * 参数：
 *   maxDistance - 最大距离
 *   stepCount   - 总步数
 * 
 * 返回：
 *   每步的固定步长
 */
float FFGetLinearStepSize(float maxDistance, int stepCount)
{
    return maxDistance / float(stepCount);
}

// ═══════════════════════════════════════════════════════════════════════════
// 散射累积函数
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFAccumulateScattering - 累积单步散射贡献
 * 
 * 计算一个步进区间内的散射贡献并累积到总散射中。
 * 
 * 参数：
 *   accumulatedScatter     - 已累积的散射值
 *   accumulatedTransmittance - 已累积的透射率
 *   lightColor             - 光源颜色
 *   extinctionCoeff        - 消光系数 σ_t
 *   scatterAlbedo          - 散射反照率 ω = σ_s / σ_t
 *   stepDistance           - 当前步长
 *   phaseValue             - 相位函数值
 *   shadowValue            - 阴影值 (0=无阴影, 1=完全阴影)
 * 
 * 返回：
 *   更新后的累积散射值
 * 
 * 物理原理：
 *   每步的散射贡献 = 入射光 * 被散射的比例 * 散射方向概率 * 透射率
 */
float3 FFAccumulateScattering(
    float3 accumulatedScatter,
    float3 accumulatedTransmittance,
    float3 lightColor,
    float3 extinctionCoeff,
    float3 scatterAlbedo,
    float stepDistance,
    float phaseValue,
    float shadowValue)
{
    // 计算当前步的透射率 (Beer-Lambert定律)
    float3 stepTransmittance = exp(-extinctionCoeff * stepDistance);
    // 消光因子：光线被散射或吸收的比例
    float3 extinctionFactor = 1.0 - stepTransmittance;
    
    // 散射贡献 = 光颜色 * 消光因子 * 散射反照率 * 相位函数 * (1-阴影)
    float3 scatterContribution = lightColor * extinctionFactor * scatterAlbedo * phaseValue * (1.0 - shadowValue);
    
    // 累积散射，乘以累积透射率考虑之前路径的衰减
    return accumulatedScatter + scatterContribution * accumulatedTransmittance;
}

// ═══════════════════════════════════════════════════════════════════════════
// 核心光线步进函数
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFRayMarchVolumeScattering - 指数步进体积散射（主函数）
 * 
 * 使用指数步进算法计算体积散射效果。
 * 这是最常用的光线步进函数，平衡了质量和性能。
 * 
 * 参数：
 *   rayOrigin      - 光线起点（水面位置）
 *   rayDirection   - 光线方向（通常指向水下）
 *   maxDistance    - 最大步进距离
 *   extinctionCoeff - 消光系数 σ_t = σ_s + σ_a
 *   scatterAlbedo  - 散射反照率 ω = σ_s / σ_t
 *   lightDir       - 光源方向
 *   viewDir        - 视线方向
 *   lightColor     - 光源颜色
 *   phaseG         - Henyey-Greenstein相位函数参数g
 *   shadowValue    - 阴影值
 *   config         - 步进配置
 * 
 * 返回：
 *   累积的散射颜色
 * 
 * 算法流程：
 *   1. 初始化累积变量
 *   2. 计算抖动偏移消除伪影
 *   3. 预计算相位函数参数
 *   4. 循环步进：
 *      a. 计算当前步位置和步长
 *      b. 计算透射率和消光因子
 *      c. 计算散射贡献并累积
 *      d. 更新累积透射率
 *   5. 返回总散射值
 */
float3 FFRayMarchVolumeScattering(
    float3 rayOrigin,
    float3 rayDirection,
    float maxDistance,
    float3 extinctionCoeff,
    float3 scatterAlbedo,
    float3 lightDir,
    float3 viewDir,
    float3 lightColor,
    float phaseG,
    float shadowValue,
    FFRayMarchConfig config)
{
    // 初始化累积变量
    float3 totalScatter = 0;            // 总散射
    float3 accumulatedTransmittance = 1; // 累积透射率，初始为1（无衰减）
    
    // 计算抖动值，消除带状伪影
    // 使用屏幕位置和时间作为随机种子
    float dither = FFSampleDither(rayOrigin.xy, _Time.y) * config.jitterStrength;
    
    // 预计算相位函数参数
    // cosTheta = cos(视线方向与光线方向的夹角)
    float cosTheta = FFComputePhaseCosTheta(viewDir, lightDir);
    
    // 步进循环
    [loop]
    for (int i = 0; i < config.stepCount; i++)
    {
        // 计算归一化参数t，加入抖动偏移
        float t = (float(i) + dither) / float(config.stepCount);
        
        // 计算当前位置的归一化距离（指数分布）
        float normalizedDistance = FFGetExponentialStepPosition(t, config.expFactor, config.stepCount);
        float currentDistance = normalizedDistance * maxDistance;
        
        // 计算当前步长
        float stepSize = FFGetExponentialStepSize(t, config.expFactor, config.stepCount, maxDistance);
        
        // 计算当前步的透射率
        float3 stepTransmittance = exp(-extinctionCoeff * stepSize);
        
        // 计算相位函数值
        float phaseValue = FFWaterPhaseFunctionFast(phaseG, cosTheta);
        
        // 计算消光因子和散射贡献
        float3 extinctionFactor = 1.0 - stepTransmittance;
        float3 scatterContribution = lightColor * extinctionFactor * scatterAlbedo * phaseValue * (1.0 - shadowValue);
        
        // 累积散射
        totalScatter += scatterContribution * accumulatedTransmittance;
        
        // 更新累积透射率
        accumulatedTransmittance *= stepTransmittance;
    }
    
    return totalScatter;
}

/*
 * FFRayMarchVolumeScatteringLinear - 线性步进体积散射
 * 
 * 使用均匀步进的简化版本，计算量相同但效果不如指数步进。
 * 适用于需要简单实现或调试的场景。
 * 
 * 参数与 FFRayMarchVolumeScattering 类似，区别在于：
 *   - 使用固定步长而非指数分布
 *   - 相位函数在循环外预计算（假设各处相同）
 */
float3 FFRayMarchVolumeScatteringLinear(
    float3 rayOrigin,
    float3 rayDirection,
    float maxDistance,
    float3 extinctionCoeff,
    float3 scatterAlbedo,
    float3 lightDir,
    float3 viewDir,
    float3 lightColor,
    float phaseG,
    float shadowValue,
    int stepCount)
{
    // 初始化累积变量
    float3 totalScatter = 0;
    float3 accumulatedTransmittance = 1;
    
    // 固定步长
    float stepSize = maxDistance / float(stepCount);
    // 抖动值
    float dither = FFSampleDither(rayOrigin.xy, _Time.y);
    
    // 预计算相位函数（线性步进假设各处相位相同）
    float cosTheta = FFComputePhaseCosTheta(viewDir, lightDir);
    float phaseValue = FFWaterPhaseFunctionFast(phaseG, cosTheta);
    
    // 步进循环
    [loop]
    for (int i = 0; i < stepCount; i++)
    {
        // 计算当前位置
        float t = (float(i) + dither) / float(stepCount);
        float currentDistance = t * maxDistance;
        
        // 计算透射率和消光因子
        float3 stepTransmittance = exp(-extinctionCoeff * stepSize);
        float3 extinctionFactor = 1.0 - stepTransmittance;
        
        // 计算散射贡献
        float3 scatterContribution = lightColor * extinctionFactor * scatterAlbedo * phaseValue * (1.0 - shadowValue);
        
        // 累积
        totalScatter += scatterContribution * accumulatedTransmittance;
        accumulatedTransmittance *= stepTransmittance;
    }
    
    return totalScatter;
}

// ═══════════════════════════════════════════════════════════════════════════
// 高级光线步进函数
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFRayMarchWithSceneColor - 带场景颜色的光线步进
 * 
 * 在体积散射基础上，考虑场景背景颜色的贡献。
 * 适用于半透明水体，可以看到水下物体的场景。
 * 
 * 参数：
 *   sceneColor - 场景背景颜色（折射后的颜色）
 *   其他参数同 FFRayMarchVolumeScattering
 * 
 * 返回：
 *   体积散射 + 场景散射的综合结果
 */
float3 FFRayMarchWithSceneColor(
    float3 rayOrigin,
    float3 rayDirection,
    float maxDistance,
    float3 extinctionCoeff,
    float3 scatterCoeff,
    float3 scatterAlbedo,
    float3 lightDir,
    float3 viewDir,
    float3 lightColor,
    float3 sceneColor,
    float phaseG,
    float shadowValue,
    FFRayMarchConfig config)
{
    // 计算体积散射
    float3 volumeScatter = FFRayMarchVolumeScattering(
        rayOrigin, rayDirection, maxDistance,
        extinctionCoeff, scatterAlbedo,
        lightDir, viewDir, lightColor,
        phaseG, shadowValue, config
    );
    
    // 计算到场景的总透射率
    float3 totalTransmittance = exp(-extinctionCoeff * maxDistance);
    
    // 计算场景颜色的散射贡献
    // 这是一个简化模型，假设场景颜色经过水体时被部分散射
    float3 sceneScatter = sceneColor * 
        totalTransmittance * 
        scatterCoeff * 
        maxDistance * 
        FFLuminance(lightColor) * 
        0.3;
    
    return volumeScatter + sceneScatter;
}

/*
 * FFRayMarchDeepWater - 深水区域光线步进
 * 
 * 专门为深水区域优化的光线步进函数。
 * 自动设置光线方向向下，适合海洋等深水场景。
 * 
 * 参数：
 *   surfacePos  - 水面位置
 *   viewDir     - 视线方向
 *   waterDepth  - 水深
 *   其他参数同上
 * 
 * 特点：
 *   - 光线方向自动向下（y分量为负）
 *   - 最大步进距离限制为水深的2倍
 */
float3 FFRayMarchDeepWater(
    float3 surfacePos,
    float3 viewDir,
    float waterDepth,
    float3 extinctionCoeff,
    float3 scatterAlbedo,
    float3 lightDir,
    float3 lightColor,
    float phaseG,
    float shadowValue,
    int stepCount)
{
    // 创建配置
    FFRayMarchConfig config = FFCreateDefaultRayMarchConfig();
    config.stepCount = stepCount;
    config.maxDistance = waterDepth;
    
    // 计算光线方向：反转视线方向并确保向下
    float3 rayDir = -viewDir;
    rayDir.y = -abs(rayDir.y);  // 确保y分量为负（向下）
    rayDir = normalize(rayDir);
    
    // 限制最大步进距离
    float maxMarchDistance = min(waterDepth * 2.0, config.maxDistance);
    
    return FFRayMarchVolumeScattering(
        surfacePos, rayDir, maxMarchDistance,
        extinctionCoeff, scatterAlbedo,
        lightDir, viewDir, lightColor,
        phaseG, shadowValue, config
    );
}

// ═══════════════════════════════════════════════════════════════════════════
// 快速近似函数
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFFastVolumeScattering - 快速体积散射近似
 * 
 * 无迭代的快速近似方法，适用于性能敏感场景。
 * 使用单次计算代替步进循环，精度较低但速度极快。
 * 
 * 参数：
 *   waterDepth      - 水深
 *   extinctionCoeff - 消光系数
 *   scatterAlbedo   - 散射反照率
 *   lightDir        - 光源方向
 *   viewDir         - 视线方向
 *   lightColor      - 光源颜色
 *   phaseG          - 相位参数
 * 
 * 返回：
 *   近似的散射颜色
 * 
 * 原理：
 *   假设整个水深范围内的散射均匀分布，
 *   直接计算总透射率和总散射。
 */
float3 FFFastVolumeScattering(
    float waterDepth,
    float3 extinctionCoeff,
    float3 scatterAlbedo,
    float3 lightDir,
    float3 viewDir,
    float3 lightColor,
    float phaseG)
{
    // 计算光学深度
    float opticalDepth = FFLuminance(extinctionCoeff) * waterDepth;
    // 计算总透射率
    float3 transmittance = exp(-extinctionCoeff * waterDepth);
    
    // 计算相位函数
    float cosTheta = FFComputePhaseCosTheta(viewDir, lightDir);
    float phaseValue = FFWaterPhaseFunctionFast(phaseG, cosTheta);
    
    // 计算消光因子和散射
    float3 extinctionFactor = 1.0 - transmittance;
    float3 scatter = lightColor * extinctionFactor * scatterAlbedo * phaseValue;
    
    return scatter;
}

// ═══════════════════════════════════════════════════════════════════════════
// 辅助函数
// ═══════════════════════════════════════════════════════════════════════════

/*
 * FFEstimateWaterDepthFromScene - 从场景深度估算水深
 * 
 * 根据场景深度缓冲和水面的高度差计算水深。
 * 
 * 参数：
 *   screenUV       - 屏幕UV坐标
 *   linearEyeDepth - 线性眼空间深度（从深度缓冲读取）
 *   surfaceHeight  - 水面高度
 * 
 * 返回：
 *   水深值
 */
float3 FFEstimateWaterDepthFromScene(
    float2 screenUV,
    float linearEyeDepth,
    float surfaceHeight)
{
    float sceneDepth = linearEyeDepth;
    float waterSurfaceDepth = surfaceHeight;
    // 水深 = 场景深度 - 水面深度
    float waterDepth = max(0, sceneDepth - waterSurfaceDepth);
    
    return waterDepth;
}

#endif
