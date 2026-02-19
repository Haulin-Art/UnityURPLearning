// 防重复包含（必加，避免多次引入报错）
#ifndef MY_SHADER_LIB_HLSL
#define MY_SHADER_LIB_HLSL

// 1. 亮度调整函数
float3 AdjustBrightness(float3 color, float brightness)
{
    return color * brightness;
}
// 2. RGB 转灰度函数
float RGBToGrayscale(float3 color)
{
    return dot(color, float3(0.299, 0.587, 0.114));
}

// ========== 三维云噪波核心实现 ==========
// 1. 哈希函数（生成伪随机梯度）
uint aHash(uint n)
{
    n = (n << 13U) ^ n;
    n = n * (n * n * 15731U + 789221U) + 1376312589U;
    return n;
}

// 2. 浮点哈希（返回0~1的伪随机值）
float aHashFloat(float3 p)
{
    uint3 i = uint3(p * 1000.0); // 缩放位置，避免精度问题
    uint h = aHash(i.x + aHash(i.y + aHash(i.z)));
    return float(h) / float(0xffffffffU);
}

// 3. 三维梯度函数（Perlin噪波的核心梯度）
float3 Gradient(uint aHash, float3 p)
{
    // 12个基础梯度方向（Perlin标准）
    const float3 grads[12] =
    {
        float3(1, 1, 0), float3(-1, 1, 0), float3(1, -1, 0), float3(-1, -1, 0),
        float3(1, 0, 1), float3(-1, 0, 1), float3(1, 0, -1), float3(-1, 0, -1),
        float3(0, 1, 1), float3(0, -1, 1), float3(0, 1, -1), float3(0, -1, -1)
    };
    uint idx = aHash % 12U;
    return grads[idx];
}

// 4. 平滑插值函数（Perlin噪波用，比线性插值更自然）
float SmoothStep(float t)
{
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0); // 6t^5-15t^4+10t^3
}

// 5. 基础三维Perlin噪波（返回-1~1的噪声值）
float PerlinNoise3D(float3 p)
{
    // 1. 获取当前格子的整数坐标
    float3 pi = floor(p);
    float3 pf = frac(p);

    // 2. 计算8个顶点的哈希值
    uint3 i = uint3(pi);
    uint h000 = aHash(i.x + aHash(i.y + aHash(i.z)));
    uint h100 = aHash(i.x + 1U + aHash(i.y + aHash(i.z)));
    uint h010 = aHash(i.x + aHash(i.y + 1U + aHash(i.z)));
    uint h110 = aHash(i.x + 1U + aHash(i.y + 1U + aHash(i.z)));
    uint h001 = aHash(i.x + aHash(i.y + aHash(i.z + 1U)));
    uint h101 = aHash(i.x + 1U + aHash(i.y + aHash(i.z + 1U)));
    uint h011 = aHash(i.x + aHash(i.y + 1U + aHash(i.z + 1U)));
    uint h111 = aHash(i.x + 1U + aHash(i.y + 1U + aHash(i.z + 1U)));

    // 3. 计算每个顶点到采样点的向量
    float3 v000 = pf - float3(0, 0, 0);
    float3 v100 = pf - float3(1, 0, 0);
    float3 v010 = pf - float3(0, 1, 0);
    float3 v110 = pf - float3(1, 1, 0);
    float3 v001 = pf - float3(0, 0, 1);
    float3 v101 = pf - float3(1, 0, 1);
    float3 v011 = pf - float3(0, 1, 1);
    float3 v111 = pf - float3(1, 1, 1);

    // 4. 计算梯度点积（噪波值）
    float d000 = dot(Gradient(h000, p), v000);
    float d100 = dot(Gradient(h100, p), v100);
    float d010 = dot(Gradient(h010, p), v010);
    float d110 = dot(Gradient(h110, p), v110);
    float d001 = dot(Gradient(h001, p), v001);
    float d101 = dot(Gradient(h101, p), v101);
    float d011 = dot(Gradient(h011, p), v011);
    float d111 = dot(Gradient(h111, p), v111);

    // 5. 三维平滑插值
    float tx = SmoothStep(pf.x);
    float ty = SmoothStep(pf.y);
    float tz = SmoothStep(pf.z);

    float x00 = lerp(d000, d100, tx);
    float x01 = lerp(d001, d101, tx);
    float x10 = lerp(d010, d110, tx);
    float x11 = lerp(d011, d111, tx);

    float y0 = lerp(x00, x10, ty);
    float y1 = lerp(x01, x11, ty);

    float z = lerp(y0, y1, tz);

    // 归一化到0~1范围（原Perlin是-1~1）
    return (z + 1.0) * 0.5;
}

// 6. 分形布朗运动（FBM）：叠加多层Perlin噪波，模拟云的层次
float FBM3D(float3 p, int octaves, float lacunarity, float gain)
{
    float total = 0.0;
    float amplitude = 1.0;
    float frequency = 1.0;
    float maxValue = 0.0; // 归一化用

    for (int i = 0; i < octaves; i++)
    {
        total += PerlinNoise3D(p * frequency) * amplitude;
        maxValue += amplitude;
        amplitude *= gain; // 振幅衰减（高频贡献更小）
        frequency *= lacunarity; // 频率提升（高频细节）
    }

    // 归一化到0~1
    return total / maxValue;
}

// 7. 云噪波核心函数（基于FBM，加入云的物理特性）
float CloudNoise(float3 worldPos, float scale = 0.01, int octaves = 4)
{
    // Step1：缩放采样位置（控制云的大小，scale越小云越大）
    float3 samplePos = worldPos * scale;

    // Step2：可选扭曲（让云更不规则，模拟气流扰动）
    float distortStrength = 0.1;
    float3 distort = float3(
        PerlinNoise3D(samplePos + float3(123.4, 456.7, 789.8)),
        PerlinNoise3D(samplePos + float3(234.5, 567.8, 890.1)),
        PerlinNoise3D(samplePos + float3(345.6, 678.9, 901.2))
    ) * distortStrength;
    samplePos += distort;

    // Step3：FBM分形噪波（云的核心纹理）
    // lacunarity=2.0（经典分形参数），gain=0.5（振幅减半）
    float fbm = FBM3D(samplePos, octaves, 2.0, 0.5);

    // Step4：高度衰减（模拟云：高空稀疏，低空密集）
    //float heightNorm = saturate((worldPos.y - _AABBMin.y) / (_AABBMax.y - _AABBMin.y));
    //float heightAttenuation = 1.0 - pow(heightNorm, 2.0); // 平方衰减，更贴合云的高度分布

    // Step5：阈值过滤（让云有清晰的边缘，模拟云朵的蓬松感）
    float threshold = 0.4; // 低于阈值的区域无云
    //float cloudDensity = smoothstep(threshold, threshold + 0.2, fbm * heightAttenuation);
    float cloudDensity = smoothstep(threshold, threshold + 0.2, fbm);

    return cloudDensity;
}


// 3. 自定义宏
#define MAX_BRIGHTNESS 2.0

#endif // MY_SHADER_LIB_HLSL