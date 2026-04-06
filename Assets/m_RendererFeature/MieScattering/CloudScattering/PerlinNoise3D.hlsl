// 3D Perlin Noise Functions
// 用于生成基础的云噪波效果

#ifndef PERLIN_NOISE_3D_HLSL
#define PERLIN_NOISE_3D_HLSL

// 伪随机数生成（仅用于哈希）
float hash(float3 p)
{
    p = frac(p * 0.3183099 + 0.1);
    p *= 17.0;
    return frac(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// 梯度向量表 - 固定的12个梯度向量
static const float3 grad3[12] = {
    float3(1,1,0), float3(-1,1,0), float3(1,-1,0), float3(-1,-1,0),
    float3(1,0,1), float3(-1,0,1), float3(1,0,-1), float3(-1,0,-1),
    float3(0,1,1), float3(0,-1,1), float3(0,1,-1), float3(0,-1,-1)
};

// 从哈希值选择梯度向量
float3 grad(int3 p)
{
    uint h = (uint)(p.x + p.y * 57 + p.z * 113) % 12;
    return grad3[h];
}

// 线性插值
float lerp(float a, float b, float t)
{
    return a + t * (b - a);
}

// 平滑步进函数
float smoothstep(float edge0, float edge1, float x)
{
    float t = saturate((x - edge0) / (edge1 - edge0));
    return t * t * (3.0 - 2.0 * t);
}

// 3D Perlin噪声
float perlinNoise3D(float3 p)
{
    int3 i = (int3)floor(p);
    float3 f = frac(p);
    
    float3 u = smoothstep(0.0, 1.0, f);
    
    // 计算8个角点的梯度贡献
    float a = dot(grad(i + int3(0,0,0)), f - float3(0,0,0));
    float b = dot(grad(i + int3(1,0,0)), f - float3(1,0,0));
    float c = dot(grad(i + int3(0,1,0)), f - float3(0,1,0));
    float d = dot(grad(i + int3(1,1,0)), f - float3(1,1,0));
    
    float e = dot(grad(i + int3(0,0,1)), f - float3(0,0,1));
    float g = dot(grad(i + int3(1,0,1)), f - float3(1,0,1));
    float h = dot(grad(i + int3(0,1,1)), f - float3(0,1,1));
    float j = dot(grad(i + int3(1,1,1)), f - float3(1,1,1));
    
    // 三线性插值
    float x1 = lerp(a, b, u.x);
    float x2 = lerp(c, d, u.x);
    float y1 = lerp(x1, x2, u.y);
    
    float x3 = lerp(e, g, u.x);
    float x4 = lerp(h, j, u.x);
    float y2 = lerp(x3, x4, u.y);
    
    float result = lerp(y1, y2, u.z);
    
    return result;  // 结果在[-1, 1]范围内
}

// 分形噪声（多层Perlin噪声叠加）
float fractalNoise3D(float3 p, int octaves, float persistence, float lacunarity = 2.0)
{
    float total = 0.0;
    float frequency = 1.0;
    float amplitude = 1.0;
    float maxAmplitude = 0.0;
    
    for (int i = 0; i < octaves; i++)
    {
        total += perlinNoise3D(p * frequency) * amplitude;
        maxAmplitude += amplitude;
        frequency *= lacunarity;
        amplitude *= persistence;
    }
    
    // 归一化到[-1, 1]范围
    return total / maxAmplitude;
}

// 云噪声生成函数
float cloudNoise3D(float3 p, float scale, int octaves = 4, float persistence = 0.5)
{
    float3 scaledP = p * scale;
    float noise = fractalNoise3D(scaledP, octaves, persistence, 2.0);
    
    // 调整噪声范围到[0, 1]
    return (noise + 1.0) * 0.5;
}

#endif // PERLIN_NOISE_3D_HLSL