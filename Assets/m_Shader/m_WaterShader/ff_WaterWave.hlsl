/*
 * ============================================
 * FluidFlux Water Wave - 程序化水波纹函数库
 * ============================================
 */

#ifndef FLUID_FLUX_WATER_WAVE.hlsl
#define FLUID_FLUX_WATER_WAVE.hlsl

// ============================================
// 一、基础数学常量
// ============================================

#define PI 3.14159265359
#define TWO_PI 6.28318530718
#define HALF_PI 1.57079632679

// ============================================
// 二、基础波形函数
// ============================================

// 基础正弦波
// uv: 纹理坐标
// amplitude: 振幅（波峰到波谷的高度）
// wavelength: 波长（一个波的长度）
// speed: 传播速度
// direction: 传播方向（归一化2D向量）
float3 SineWave(float3 position, float amplitude, float wavelength, float speed, float2 direction)
{
    float k = TWO_PI / wavelength;  // 波数
    float omega = speed * k;       // 角频率
    float phase = k * dot(direction, position.xz) - omega * _Time.y;

    float height = amplitude * sin(phase);
    float slopeX = amplitude * k * direction.x * cos(phase);
    float slopeZ = amplitude * k * direction.y * cos(phase);

    return float3(height, slopeX, slopeZ);
}

// 方向正弦波族
float3 DirectionalSineWaves(float3 position, float4 waveParams[4], float2 directions[4])
{
    float3 totalDisplacement = float3(0.0, 0.0, 0.0);

    for (int i = 0; i < 4; i++)
    {
        float amplitude = waveParams[i].x;
        float wavelength = waveParams[i].y;
        float speed = waveParams[i].z;
        float phaseOffset = waveParams[i].w;

        float k = TWO_PI / wavelength;
        float omega = speed * k;
        float phase = k * dot(directions[i], position.xz) - omega * _Time.y + phaseOffset;

        float height = amplitude * sin(phase);
        float slopeX = amplitude * k * directions[i].x * cos(phase);
        float slopeZ = amplitude * k * directions[i].y * cos(phase);

        totalDisplacement += float3(height, slopeX, slopeZ);
    }

    return totalDisplacement;
}

// ============================================
// 三、Gerstner 波（深水波浪）
// ============================================

// 单个Gerstner波
// Gerstner波是一种深水波浪模型，波的峰较尖，谷较宽，更接近真实海浪
// position: 世界位置
// amplitude: 振幅
// wavelength: 波长
// speed: 传播速度
// direction: 传播方向（归一化）
// steepness: 陡峭度 (0-1)，控制波的尖锐程度
// name: 波的名称标识
struct GerstnerWaveResult
{
    float3 displacement;    // 位移 (x, y, z)
    float3 tangent;         // 切线方向
    float3 binormal;         // 次法线方向
    float3 normal;          // 法线方向
};

// 单个Gerstner波计算
GerstnerWaveResult GerstnerWave(float3 position, float amplitude, float wavelength, float speed, float2 direction, float steepness)
{
    GerstnerWaveResult result;

    float k = TWO_PI / wavelength;
    float omega = sqrt(9.8 * k);  // 深水色散关系: omega = sqrt(g * k)
    float phase = k * dot(direction, position.xz) - omega * speed * _Time.y;

    // 根据Steepness计算水平振幅衰减（保持波形在合理范围）
    float steepnessFactor = steepness / (k * amplitude);
    steepnessFactor = clamp(steepnessFactor, 0.0, 1.0);

    float amplitudeX = steepnessFactor * amplitude * direction.x;
    float amplitudeZ = steepnessFactor * amplitude * direction.y;

    float sinPhase = sin(phase);
    float cosPhase = cos(phase);

    // 位移计算
    result.displacement.x = amplitudeX * cosPhase;
    result.displacement.y = amplitude * sinPhase;
    result.displacement.z = amplitudeZ * cosPhase;

    // 切线和次法线（用于计算法线）
    result.tangent = float3(
        1.0 - k * amplitudeX * sinPhase,
        k * amplitude * direction.x * cosPhase,
        -k * amplitudeZ * sinPhase
    );

    result.binormal = float3(
        -k * amplitudeX * sinPhase,
        k * amplitude * direction.y * cosPhase,
        1.0 - k * amplitudeZ * sinPhase
    );

    // 法线 = 切线 × 次法线
    result.normal = normalize(cross(result.binormal, result.tangent));

    return result;
}

// 多个Gerstner波叠加
GerstnerWaveResult GerstnerWaves(float3 position, int waveCount, float4 waveParams[8], float2 directions[8], float4 steepnessParams[8])
{
    GerstnerWaveResult totalResult;
    totalResult.displacement = float3(0.0, 0.0, 0.0);
    totalResult.tangent = float3(1.0, 0.0, 0.0);
    totalResult.binormal = float3(0.0, 0.0, 1.0);
    totalResult.normal = float3(0.0, 1.0, 0.0);

    for (int i = 0; i < waveCount && i < 8; i++)
    {
        float amplitude = waveParams[i].x;
        float wavelength = waveParams[i].y;
        float speed = waveParams[i].z;
        float steepness = steepnessParams[i].x;

        GerstnerWaveResult wave = GerstnerWave(position, amplitude, wavelength, speed, directions[i], steepness);

        totalResult.displacement += wave.displacement;
        totalResult.tangent += wave.tangent - float3(1.0, 0.0, 0.0);
        totalResult.binormal += wave.binormal - float3(0.0, 0.0, 1.0);
    }

    // 重新计算法线
    totalResult.tangent = normalize(totalResult.tangent);
    totalResult.binormal = normalize(totalResult.binormal);
    totalResult.normal = normalize(cross(totalResult.binormal, totalResult.tangent));

    return totalResult;
}

// ============================================
// 四、涟漪波（Ripple）
// ============================================

// 单个涟漪
// center: 涟漪中心点
// currentPos: 当前计算点位置
// amplitude: 振幅
// wavelength: 波长
// speed: 传播速度
// startTime: 涟漪开始时间（用于控制多个涟漪的时序）
float3 SingleRipple(float3 center, float3 currentPos, float amplitude, float wavelength, float speed, float startTime)
{
    float3 offset = currentPos - center;
    float dist = length(offset.xz);

    float elapsedTime = max(0.0, _Time.y - startTime);
    float radius = speed * elapsedTime;

    float k = TWO_PI / wavelength;
    float phase = k * (dist - radius);

    float decay = exp(-3.0 * elapsedTime);  // 时间衰减
    float spatialDecay = exp(-0.5 * dist);   // 空间衰减

    float height = amplitude * decay * spatialDecay * sin(phase);

    // 涟漪的法线斜率
    float slope = amplitude * decay * k * spatialDecay * cos(phase) * exp(-0.1 * dist);

    return float3(height, slope, 0.0);
}

// 多个涟漪叠加
float3 MultipleRipples(float3 position, int rippleCount, float4 rippleParams[8], float3 rippleCenters[8])
{
    float3 totalRipple = float3(0.0, 0.0, 0.0);

    for (int i = 0; i < rippleCount && i < 8; i++)
    {
        float amplitude = rippleParams[i].x;
        float wavelength = rippleParams[i].y;
        float speed = rippleParams[i].z;
        float startTime = rippleParams[i].w;

        totalRipple += SingleRipple(rippleCenters[i], position, amplitude, wavelength, speed, startTime);
    }

    return totalRipple;
}

// ============================================
// 五、程序化波浪噪声
// ============================================

// 波浪噪声基函数
// 使用FBM (Fractional Brownian Motion) 增强的波浪噪声
struct WaveNoiseResult
{
    float height;      // 高度
    float2 gradient;   // 梯度（用于法线计算）
};

// 基础2D波浪噪声
WaveNoiseResult WaveNoise(float2 uv, float amplitude, float frequency, float speed, int octaves, float persistence, float lacunarity)
{
    WaveNoiseResult result;
    result.height = 0.0;
    result.gradient = float2(0.0, 0.0);

    float amp = amplitude;
    float freq = frequency;
    float maxAmplitude = 0.0;

    for (int i = 0; i < octaves; i++)
    {
        // 使用多个正弦波的组合模拟噪声
        float2 uv1 = uv * freq + _Time.y * speed * float2(0.3, 0.7);
        float2 uv2 = uv * freq * 1.37 + _Time.y * speed * float2(0.5, 0.3);

        float noise1 = sin(uv1.x) * sin(uv1.y);
        float noise2 = sin(uv2.x + noise1) * cos(uv2.y - noise1);

        float noiseValue = (noise1 + noise2) * 0.5;

        result.height += noiseValue * amp;
        result.gradient += float2(
            cos(uv1.x) * sin(uv1.y) * freq + cos(uv2.x + noise1) * freq * 1.37,
            sin(uv1.x) * cos(uv1.y) * freq + cos(uv2.y - noise1) * freq * 1.37
        ) * amp;

        maxAmplitude += amp;
        amp *= persistence;
        freq *= lacunarity;
    }

    // 归一化
    if (maxAmplitude > 0.0)
    {
        result.height /= maxAmplitude;
    }

    return result;
}

// 流向波浪噪声（考虑方向性）
WaveNoiseResult DirectionalWaveNoise(float2 uv, float amplitude, float frequency, float speed, float2 direction, int octaves, float persistence, float lacunarity)
{
    WaveNoiseResult result;
    result.height = 0.0;
    result.gradient = float2(0.0, 0.0);

    // 旋转UV坐标到主方向
    float angle = atan2(direction.y, direction.x);
    float cosA = cos(angle);
    float sinA = sin(angle);
    float2 rotatedUV = float2(
        uv.x * cosA - uv.y * sinA,
        uv.x * sinA + uv.y * cosA
    );

    float amp = amplitude;
    float freq = frequency;
    float maxAmplitude = 0.0;

    for (int i = 0; i < octaves; i++)
    {
        float2 uv1 = rotatedUV * freq + _Time.y * speed * direction;
        float2 uv2 = rotatedUV * freq * 1.5 + _Time.y * speed * float2(-direction.y, direction.x);

        float wave1 = sin(uv1.x) * sin(uv1.y * 0.7);
        float wave2 = sin(uv2.x + wave1) * cos(uv2.y * 0.5);

        float noiseValue = (wave1 + wave2) * 0.5;

        result.height += noiseValue * amp;

        maxAmplitude += amp;
        amp *= persistence;
        freq *= lacunarity;
    }

    if (maxAmplitude > 0.0)
    {
        result.height /= maxAmplitude;
    }

    return result;
}

// ============================================
// 六、波峰和波谷检测
// ============================================

// 检测波浪的波峰和波谷
// 返回: x = 波峰强度, y = 波谷强度
float2 WavePeaksAndValleys(float3 position, float threshold)
{
    // 采样周围四个点
    float offset = 0.1;
    float centerHeight = position.y;
    float leftHeight = centerHeight;   // 实际计算时需要重新采样
    float rightHeight = centerHeight;  // 实际计算时需要重新采样
    float frontHeight = centerHeight; // 实际计算时需要重新采样
    float backHeight = centerHeight;  // 实际计算时需要重新采样

    // 波峰: 当前点比周围点都高
    float peakStrength = max(0.0, centerHeight - max(max(leftHeight, rightHeight), max(frontHeight, backHeight)));
    peakStrength = smoothstep(0.0, threshold, peakStrength);

    // 波谷: 当前点比周围点都低
    float valleyStrength = max(0.0, min(min(leftHeight, rightHeight), min(frontHeight, backHeight)) - centerHeight);
    valleyStrength = smoothstep(0.0, threshold, valleyStrength);

    return float2(peakStrength, valleyStrength);
}

// ============================================
// 七、波浪法线计算
// ============================================

// 从波浪位移计算法线
float3 CalculateWaveNormal(float3 position, float amplitude, float wavelength)
{
    float eps = wavelength * 0.1;

    // 采样周围高度
    float hL = SineWave(position + float3(-eps, 0, 0), amplitude, wavelength, 1.0, float2(1, 0)).x;
    float hR = SineWave(position + float3(eps, 0, 0), amplitude, wavelength, 1.0, float2(1, 0)).x;
    float hD = SineWave(position + float3(0, 0, -eps), amplitude, wavelength, 1.0, float2(1, 0)).x;
    float hU = SineWave(position + float3(0, 0, eps), amplitude, wavelength, 1.0, float2(1, 0)).x;

    float3 normal = normalize(float3(hL - hR, 2.0 * eps, hD - hU));
    return normal;
}

// 从Gerstner波组计算法线
float3 CalculateGerstnerNormal(float3 position, int waveCount, float4 waveParams[8], float2 directions[8], float4 steepnessParams[8])
{
    float3 tangent = float3(1.0, 0.0, 0.0);
    float3 binormal = float3(0.0, 0.0, 1.0);

    for (int i = 0; i < waveCount && i < 8; i++)
    {
        float amplitude = waveParams[i].x;
        float wavelength = waveParams[i].y;
        float speed = waveParams[i].z;
        float steepness = steepnessParams[i].x;

        float k = TWO_PI / wavelength;
        float omega = sqrt(9.8 * k);
        float phase = k * dot(directions[i], position.xz) - omega * speed * _Time.y;

        float steepnessFactor = steepness / (k * amplitude);
        steepnessFactor = clamp(steepnessFactor, 0.0, 1.0);

        float amplitudeX = steepnessFactor * amplitude * directions[i].x;
        float amplitudeZ = steepnessFactor * amplitude * directions[i].y;

        float sinPhase = sin(phase);
        float cosPhase = cos(phase);

        tangent += float3(
            -k * amplitudeX * sinPhase,
            k * amplitude * directions[i].x * cosPhase,
            -k * amplitudeZ * sinPhase
        );

        binormal += float3(
            -k * amplitudeX * sinPhase,
            k * amplitude * directions[i].y * cosPhase,
            -k * amplitudeZ * sinPhase
        );
    }

    return normalize(cross(binormal, tangent));
}

// ============================================
// 八、波浪高度场
// ============================================

// 综合波浪高度场计算
// 整合Gerstner波、涟漪和噪声
struct WaveFieldResult
{
    float height;              // 总高度
    float3 normal;              // 法线
    float2 dxy;                 // 梯度（用于TBN计算）
    float peakIntensity;        // 波峰强度
    float valleyIntensity;      // 波谷强度
};

WaveFieldResult CalculateWaveField(float3 position,
                                   int gerstnerWaveCount, float4 gerstnerParams[8], float2 gerstnerDirections[8], float4 gerstnerSteepness[8],
                                   int rippleCount, float4 rippleParams[8], float3 rippleCenters[8],
                                   float noiseAmplitude, float noiseFrequency, float noiseSpeed,
                                   int noiseOctaves, float noisePersistence, float noiseLacunarity)
{
    WaveFieldResult result;
    result.height = 0.0;
    result.normal = float3(0.0, 1.0, 0.0);
    result.dxy = float2(0.0, 0.0);
    result.peakIntensity = 0.0;
    result.valleyIntensity = 0.0;

    float3 gerstnerResult = GerstnerWaves(position, gerstnerWaveCount, gerstnerParams, gerstnerDirections, gerstnerSteepness).displacement;
    float3 rippleResult = MultipleRipples(position, rippleCount, rippleParams, rippleCenters);
    WaveNoiseResult noiseResult = WaveNoise(position.xz, noiseAmplitude, noiseFrequency, noiseSpeed, noiseOctaves, noisePersistence, noiseLacunarity);

    result.height = gerstnerResult.y + rippleResult.x + noiseResult.height;
    result.dxy = float2(gerstnerResult.y + noiseResult.gradient.x, gerstnerResult.z + noiseResult.gradient.y);

    // 计算法线
    float3 normal = float3(-result.dxy.x, 1.0, -result.dxy.y);
    result.normal = normalize(normal);

    // 波峰波谷检测
    float2 peaksValleys = WavePeaksAndValleys(position + float3(0, result.height, 0), 0.5);
    result.peakIntensity = peaksValleys.x;
    result.valleyIntensity = peaksValleys.y;

    return result;
}

// ============================================
// 九、波浪破碎检测
// ============================================

// 基于陡峭度判断波浪是否破碎
// 当波形过于陡峭时会发生破碎
// steepnessThreshold: 破碎阈值 (通常 0.3-0.6)
bool IsWaveBreaking(float3 position, float steepnessThreshold)
{
    // 通过曲率估算破碎
    float eps = 0.5;
    float hCenter = SineWave(position, 1.0, 5.0, 1.0, float2(1, 0)).x;
    float hL = SineWave(position + float3(-eps, 0, 0), 1.0, 5.0, 1.0, float2(1, 0)).x;
    float hR = SineWave(position + float3(eps, 0, 0), 1.0, 5.0, 1.0, float2(1, 0)).x;

    float curvature = abs(hL + hR - 2 * hCenter) / (eps * eps);

    return curvature > steepnessThreshold;
}

// 基于高度梯度判断波浪破碎
float CalculateBreakingIntensity(float3 position, float threshold)
{
    float eps = 0.1;

    float hL = SineWave(position + float3(-eps, 0, 0), 1.0, 5.0, 1.0, float2(1, 0)).x;
    float hR = SineWave(position + float3(eps, 0, 0), 1.0, 5.0, 1.0, float2(1, 0)).x;
    float hD = SineWave(position + float3(0, 0, -eps), 1.0, 5.0, 1.0, float2(1, 0)).x;
    float hU = SineWave(position + float3(0, 0, eps), 1.0, 5.0, 1.0, float2(1, 0)).x;

    float gradientMagnitude = length(float2(hR - hL, hU - hD)) / (2.0 * eps);

    return smoothstep(threshold * 0.5, threshold, gradientMagnitude);
}

// ============================================
// 十、波浪与水体BSDF的接口
// ============================================

// 为水体BSDF准备波浪数据
struct WaterWaveSurfaceData
{
    float3 position;           // 表面位置
    float3 normal;              // 表面法线
    float3 tangent;             // 切线方向
    float3 bitangent;           // 次切线方向
    float height;              // 波浪高度
    float3 velocity;           // 表面速度（用于动画）
    float peakIntensity;       // 波峰强度（用于泡沫生成）
    float3 _unused;            // 对齐填充
};

// 生成水体表面数据
WaterWaveSurfaceData GenerateWaterWaveSurface(float3 worldPosition,
                                              int gerstnerWaveCount, float4 gerstnerParams[8], float2 gerstnerDirections[8], float4 gerstnerSteepness[8])
{
    WaterWaveSurfaceData surfaceData;

    // 基础位置
    float3 basePosition = worldPosition;

    // 计算Gerstner波
    GerstnerWaveResult gerstner = GerstnerWaves(basePosition, gerstnerWaveCount, gerstnerParams, gerstnerDirections, gerstnerSteepness);

    // 最终位置 = 基础位置 + 波浪位移
    surfaceData.position = basePosition + gerstner.displacement;
    surfaceData.normal = gerstner.normal;
    surfaceData.tangent = gerstner.tangent;
    surfaceData.bitangent = gerstner.binormal;
    surfaceData.height = gerstner.displacement.y;

    // 速度估算（用于后续动画效果）
    float eps = 0.01;
    float3 posNext = basePosition + float3(eps, 0, 0);
    GerstnerWaveResult gerstnerNext = GerstnerWaves(posNext, gerstnerWaveCount, gerstnerParams, gerstnerDirections, gerstnerSteepness);
    surfaceData.velocity = (gerstnerNext.displacement - gerstner.displacement) / eps;

    // 波峰强度（用于泡沫）
    float2 peaksValleys = WavePeaksAndValleys(surfaceData.position, 0.3);
    surfaceData.peakIntensity = peaksValleys.x;

    return surfaceData;
}

#endif // FLUID_FLUX_WATER_WAVE.hlsl
