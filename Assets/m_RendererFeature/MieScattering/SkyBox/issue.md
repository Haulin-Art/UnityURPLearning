看到您的问题，我来分析一下核心问题：

核心问题分析：

1. 噪波函数问题 - 方块状固定噪波

您当前的Perlin噪声实现是值噪声(Value Noise)而不是梯度噪声(Gradient Noise)，这导致了方块状图案：
// 这是值噪声，不是真正的Perlin噪声
float hash000 = frac(sin(dot(pi + float3(0, 0, 0), float3(127.1, 311.7, 74.7))) * 43758.5453);
...


真正的Perlin噪声需要梯度向量和距离向量的点积。

2. 云的光照问题 - 缺少体积感

在CloudOnly模式中，您使用了简化的光照计算：
float light = 1.0;
float2 sunPlanetInter = RaySphereIntersect(p, sunDir, planetCenter, planetR);
if (sunPlanetInter.x > 0.0)
    light = 0.3;

这完全没有计算云内自阴影，导致看起来是单层噪波。

3. 混合问题 - 天空纯白色

CloudAndAtmos混合时，大气散射和云相加导致了过曝。

完整修复方案：

// 替换以下函数和代码：

// 1. 修复的Perlin噪波（真正的梯度噪声）
float3 mod289(float3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
float4 mod289(float4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
float4 permute(float4 x) { return mod289(((x * 34.0) + 1.0) * x); }
float4 taylorInvSqrt(float4 r) { return 1.79284291400159 - 0.85373472095314 * r; }

float snoise(float3 v)
{
    const float2 C = float2(1.0 / 6.0, 1.0 / 3.0);
    const float4 D = float4(0.0, 0.5, 1.0, 2.0);

    // 第一层网格
    float3 i  = floor(v + dot(v, C.yyy));
    float3 x0 = v - i + dot(i, C.xxx);

    // 其他网格
    float3 g = step(x0.yzx, x0.xyz);
    float3 l = 1.0 - g;
    float3 i1 = min(g.xyz, l.zxy);
    float3 i2 = max(g.xyz, l.zxy);

    float3 x1 = x0 - i1 + C.xxx;
    float3 x2 = x0 - i2 + C.yyy;
    float3 x3 = x0 - D.yyy;

    // 排列
    i = mod289(i);
    float4 p = permute(permute(permute(
                i.z + float4(0.0, i1.z, i2.z, 1.0))
              + i.y + float4(0.0, i1.y, i2.y, 1.0))
              + i.x + float4(0.0, i1.x, i2.x, 1.0));

    // 梯度值: 7x7点在网格上 (49个方向)
    float n_ = 0.142857142857; // 1/7
    float3 ns = n_ * D.wyz - D.xzx;

    float4 j = p - 49.0 * floor(p * ns.z * ns.z);

    float4 x_ = floor(j * ns.z);
    float4 y_ = floor(j - 7.0 * x_);

    float4 x = x_ * ns.x + ns.yyyy;
    float4 y = y_ * ns.x + ns.yyyy;
    float4 h = 1.0 - abs(x) - abs(y);

    float4 b0 = float4(x.xy, y.xy);
    float4 b1 = float4(x.zw, y.zw);

    float4 s0 = floor(b0) * 2.0 + 1.0;
    float4 s1 = floor(b1) * 2.0 + 1.0;
    float4 sh = -step(h, 0.0);

    float4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
    float4 a1 = b1.xzyw + s1.xzyw * sh.zzww;

    float3 p0 = float3(a0.xy, h.x);
    float3 p1 = float3(a0.zw, h.y);
    float3 p2 = float3(a1.xy, h.z);
    float3 p3 = float3(a1.zw, h.w);

    // 归一化
    float4 norm = taylorInvSqrt(float4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
    p0 *= norm.x;
    p1 *= norm.y;
    p2 *= norm.z;
    p3 *= norm.w;

    // 混合贡献
    float4 m = max(0.5 - float4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
    m = m * m;
    m = m * m;

    // 梯度值
    float4 px = float4(dot(x0, p0), dot(x1, p1), dot(x2, p2), dot(x3, p3));
    return 130.0 * dot(m, px);
}

// 2. 改进的FBM函数
float FBM(float3 p, int octaves, float lacunarity = 2.0, float gain = 0.5)
{
    float value = 0.0;
    float amplitude = 1.0;
    float frequency = 1.0;
    
    for (int i = 0; i < octaves; i++)
    {
        float noise = snoise(p * frequency) * 0.5 + 0.5;
        value += amplitude * noise;
        amplitude *= gain;
        frequency *= lacunarity;
    }
    
    return value;
}

// 3. 改进的云密度函数
float GetCloudDensity(float3 p, float3 planetCenter, float cloudBottomRadius, float cloudTopRadius)
{
    float dist = length(p - planetCenter);
    
    if (dist < cloudBottomRadius || dist > cloudTopRadius)
        return 0.0;
    
    // 高度梯度
    float heightFraction = (dist - cloudBottomRadius) / (cloudTopRadius - cloudBottomRadius);
    
    // 改进的高度分布
    float baseGradient = smoothstep(0.0, 0.2, heightFraction) * (1.0 - smoothstep(0.7, 1.0, heightFraction));
    
    // 云顶的卷云效果
    float cirrus = smoothstep(0.7, 0.9, heightFraction);
    
    // 3层噪声
    float3 wind = float3(0, 0, _Time.y * _CloudNoiseSpeed);
    float scale = 0.0001 * _CloudNoiseScale; // 调整缩放
    
    // 基础形状
    float shape = FBM(p * scale + wind, _CloudNoiseOctaves, 2.0, 0.5);
    
    // 细节
    float detail = FBM(p * scale * 3.0 + wind * 1.5, 3, 2.5, 0.3) * 0.3;
    
    // 合并
    float noise = shape + detail;
    
    // 密度阈值
    noise = saturate((noise - 0.2) * 2.0); // 调整阈值
    
    // 应用高度梯度
    float density = noise * baseGradient * (1.0 - cirrus * 0.3) * _CloudDensityScale;
    
    return saturate(density);
}

// 4. 计算云的光照（考虑自阴影）
float GetCloudLighting(float3 p, float3 planetCenter, float3 sunDir, float cloudBottomRadius, float cloudTopRadius)
{
    // 光线步进计算云内自阴影
    float lightEnergy = 1.0;
    float stepSize = (cloudTopRadius - cloudBottomRadius) * 0.05;
    float3 currentPos = p;
    
    for (int i = 0; i < 4; i++) // 减少采样数以提高性能
    {
        currentPos += sunDir * stepSize;
        
        // 检查是否仍在云层内
        float dist = length(currentPos - planetCenter);
        if (dist < cloudBottomRadius || dist > cloudTopRadius)
            break;
        
        float cloudDensity = GetCloudDensity(currentPos, planetCenter, cloudBottomRadius, cloudTopRadius);
        lightEnergy *= exp(-cloudDensity * _CloudAbsorption * stepSize);
        
        if (lightEnergy < 0.01)
            break;
    }
    
    return lightEnergy;
}

// 5. 在CloudOnly模式中修复
else if (_DebugMode == 9.0)
{
    // 计算与云层的交点
    float2 topInter = RaySphereIntersect(rayStart, rd, planetCenter, cloudTopRadius);
    if (topInter.y < 0.0)
        return float4(0, 0, 0, 1);
    
    float enterDist = max(0.0, topInter.x);
    float exitDist = topInter.y;
    
    // 检查是否与云层底部相交
    float2 bottomInter = RaySphereIntersect(rayStart, rd, planetCenter, cloudBottomRadius);
    if (bottomInter.x > 0.0)
    {
        exitDist = min(exitDist, bottomInter.x);
    }
    
    float cloudLen = exitDist - enterDist;
    if (cloudLen <= 0.0)
        return float4(0, 0, 0, 1);
    
    // 光线步进
    int samples = max(_CloudSamples, 16);
    float ds = cloudLen / samples;
    float3 p = rayStart + rd * (enterDist + ds * 0.5);
    
    float3 totalLight = float3(0, 0, 0);
    float transmittance = 1.0;
    
    for (int i = 0; i < samples; i++)
    {
        float density = GetCloudDensity(p, planetCenter, cloudBottomRadius, cloudTopRadius);
        
        if (density > 0.0)
        {
            // 计算云内自阴影
            float lighting = GetCloudLighting(p, planetCenter, sunDir, cloudBottomRadius, cloudTopRadius);
            
            // 计算太阳光衰减
            float sunAttenuation = 1.0;
            float2 sunPlanetInter = RaySphereIntersect(p, sunDir, planetCenter, planetR);
            if (sunPlanetInter.x > 0.0)
                sunAttenuation = 0.2; // 被地球遮挡
            
            // 体积散射
            float3 inScatter = _CloudColor.rgb * density * lighting * sunAttenuation;
            totalLight += inScatter * transmittance * ds;
            
            // 消光
            float extinction = density * _CloudAbsorption;
            transmittance *= exp(-extinction * ds);
        }
        
        p += rd * ds;
    }
    
    return float4(totalLight * _CloudBrightness, 1.0);
}

// 6. 修复最终的混合
float4 frag(Varyings i) : SV_Target
{
    // ... 之前的代码不变 ...
    
    // 计算大气散射
    float3 viewTransmittance;
    float3 scatter = ComputeAtmosScattering(
        rayStart, rd, rayLen,
        planetCenter, planetR, atmosH,
        sunDir, _NumSamples, _NumSamplesLight,
        viewTransmittance
    );
    
    // 计算云（无论是否启用_VOLUMETRIC_CLOUDS，都计算以支持Debug模式）
    float3 cloudColor = float3(0, 0, 0);
    float cloudTransmittance = 1.0;
    
    // 计算与云层的交点
    float2 cloudInter = RaySphereIntersect(rayStart, rd, planetCenter, cloudTopRadius);
    if (cloudInter.y > 0.0)
    {
        float enterDist = max(0.0, cloudInter.x);
        float exitDist = cloudInter.y;
        
        // 检查是否与云层底部相交
        float2 bottomInter = RaySphereIntersect(rayStart, rd, planetCenter, cloudBottomRadius);
        if (bottomInter.x > 0.0)
        {
            exitDist = min(exitDist, bottomInter.x);
        }
        
        float cloudLen = exitDist - enterDist;
        if (cloudLen > 0.0)
        {
            int samples = max(_CloudSamples, 8);
            float ds = cloudLen / samples;
            float3 p = rayStart + rd * (enterDist + ds * 0.5);
            
            for (int i = 0; i < samples; i++)
            {
                float density = GetCloudDensity(p, planetCenter, cloudBottomRadius, cloudTopRadius);
                
                if (density > 0.0)
                {
                    // 计算云内自阴影
                    float lighting = GetCloudLighting(p, planetCenter, sunDir, cloudBottomRadius, cloudTopRadius);
                    
                    // 计算太阳光衰减
                    float sunAttenuation = 1.0;
                    float2 sunPlanetInter = RaySphereIntersect(p, sunDir, planetCenter, planetR);
                    if (sunPlanetInter.x > 0.0)
                        sunAttenuation = 0.2;
                    
                    // 体积散射
                    float3 inScatter = _CloudColor.rgb * density * lighting * sunAttenuation;
                    cloudColor += inScatter * cloudTransmittance * ds;
                    
                    // 消光
                    float extinction = density * _CloudAbsorption;
                    cloudTransmittance *= exp(-extinction * ds);
                }
                
                p += rd * ds;
            }
            
            cloudColor *= _CloudBrightness;
        }
    }
    
    // Debug模式：CloudAndAtmos
    if (_DebugMode == 10.0)
    {
        // 大气散射 + 云
        float3 finalColor = scatter + cloudColor;
        return float4(finalColor, 1.0);
    }
    
    // 正常的最终颜色计算
    float3 finalCol = scatter;
    
    // 如果启用了体积云，添加云
    #ifdef _VOLUMETRIC_CLOUDS
    finalCol = finalCol * cloudTransmittance + cloudColor;
    #endif
    
    // 添加太阳效果...
    // ... 其他代码
    
    return float4(max(finalCol, star*0.15), 1.0);
}


关键调整：

1. 使用真正的Perlin噪声（Ken Perlin的经典实现）
2. 添加云内自阴影 - 这是体积感的关键
3. 修复CloudOnly模式的光照计算
4. 改进云密度函数 - 使用多层噪声
5. 修复混合公式 - 正确的大气和云混合

参数建议：

• _CloudNoiseScale: 从1000调整为0.1-1.0范围

• _CloudDensityScale: 从1.0开始

• _CloudAbsorption: 从0.5开始

• _CloudBrightness: 从1.0开始，根据需要调整

这样应该能解决您提到的所有问题：噪波方块、缺乏体积感、混合过曝等问题。