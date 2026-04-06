看了您修改后的Shader代码，我发现了几个关键问题导致看不到云。主要问题出现在**步进区间计算**和**云层坐标系统**上。以下是详细分析和修复方案：

## 一、核心问题分析

### 1. **地球中心计算错误**
您的地球中心设置为原点`(0,0,0)`，但云层半径直接用高度值计算，这会导致：
- 云层球体中心在地心（原点）
- 但实际上云层应该位于地球表面上方
- 这导致步进区间计算逻辑混乱

### 2. **密度计算中的高度计算错误**
```hlsl
// 问题代码
float height = length(worldPos);  // 这是从地心到点的距离，不是海拔高度！
```

### 3. **步进区间逻辑过于复杂且有误**
您的步进区间判断逻辑（hitBottom、hitTop的组合）存在多个边界条件问题。

## 二、修复方案

### 第一步：简化并修正坐标系统

```hlsl
CBUFFER_START(UnityPerMaterial)
    // ... 现有参数 ...
    float _EarthRadius;        // 添加地球半径
CBUFFER_END
```

在Properties中添加：
```hlsl
[Header(Planet Settings)]
_EarthRadius ("Earth Radius", Float) = 6371000.0
```

### 第二步：重写密度计算函数

```hlsl
// 采样云密度场（修复版）
float SampleCloudDensity(float3 worldPos)
{
    // 计算海拔高度（从地球表面算起）
    float altitude = length(worldPos) - _EarthRadius;
    
    // 检查是否在云层高度范围内
    if (altitude < _CloudBottomHeight || altitude > _CloudTopHeight)
        return 0.0;
    
    // 计算归一化高度 (0=云底, 1=云顶)
    float heightPercent = (altitude - _CloudBottomHeight) / (_CloudTopHeight - _CloudBottomHeight);
    
    // 采样3D噪声
    float3 noiseUV = worldPos * _NoiseScale;
    float4 noise = tex3D(_ShapeNoise, noiseUV);
    float baseDensity = noise.r;
    
    // 应用高度梯度（三次缓动函数，更自然）
    float heightGradient = heightPercent * heightPercent * (3.0 - 2.0 * heightPercent);
    baseDensity *= heightGradient;
    
    // 应用密度和阈值
    baseDensity *= _CloudDensity;
    baseDensity = saturate((baseDensity - _CloudThreshold) / (1.0 - _CloudThreshold));
    
    return baseDensity;
}
```

### 第三步：简化并修正步进区间计算

```hlsl
// 修正的步进区间计算
float2 GetCloudMarchRange(float3 rayOrigin, float3 rayDir)
{
    // 地球中心和云层半径
    float3 earthCenter = float3(0, 0, 0);
    float cloudBottomRadius = _EarthRadius + _CloudBottomHeight;
    float cloudTopRadius = _EarthRadius + _CloudTopHeight;
    
    // 计算与底部和顶部球体的交点
    float tBottom0, tBottom1, tTop0, tTop1;
    bool hitBottom = RaySphereIntersect(rayOrigin, rayDir, earthCenter, cloudBottomRadius, tBottom0, tBottom1);
    bool hitTop = RaySphereIntersect(rayOrigin, rayDir, earthCenter, cloudTopRadius, tTop0, tTop1);
    
    // 简单逻辑：如果相机在云下，从进入底部球体到离开顶部球体
    // 如果相机在云中，从当前位置到离开顶部球体
    // 如果相机在云上，看不到云
    float cameraHeight = length(rayOrigin) - _EarthRadius;
    float startT = 0.0;
    float endT = 0.0;
    
    if (cameraHeight < _CloudBottomHeight)
    {
        // 相机在云下方
        if (hitBottom) startT = max(tBottom0, 0.0);
        if (hitTop) endT = tTop1;
    }
    else if (cameraHeight <= _CloudTopHeight)
    {
        // 相机在云层中
        startT = 0.0;
        if (hitTop) endT = tTop1;
    }
    else
    {
        // 相机在云上方，看不到云
        return float2(0.0, 0.0);
    }
    
    return float2(startT, endT - startT);
}
```

### 第四步：简化frag函数中的云渲染部分

```hlsl
half4 frag(Varyings i) : SV_Target
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
    
    // 获取光源
    Light mainLight = GetMainLight();
    float3 sunDir = mainLight.direction;
    float3 sunColor = mainLight.color;
    
    // 视图方向
    float3 viewDir = normalize(i.viewDir);
    
    // 1. 采样天空背景
    // ... 原有全景图采样代码 ...
    
    // 2. 计算云层
    float3 rayOrigin = _WorldSpaceCameraPos;
    float3 rayDir = viewDir;
    
    // 获取步进范围
    float2 marchRange = GetCloudMarchRange(rayOrigin, rayDir);
    float startT = marchRange.x;
    float marchDistance = marchRange.y;
    
    // 如果没有有效范围，直接返回天空
    if (marchDistance <= 0.0)
    {
        return half4(skyColor, 1.0);
    }
    
    // 3. RayMarching
    const int MAX_STEPS = 32;
    float stepSize = marchDistance / MAX_STEPS;
    
    float totalDensity = 0.0;
    float3 totalLight = float3(0, 0, 0);
    float transmittance = 1.0;
    
    // 起始点
    float3 pos = rayOrigin + rayDir * startT;
    
    [unroll(8)]
    for (int i = 0; i < MAX_STEPS; i++)
    {
        // 采样密度
        float density = SampleCloudDensity(pos);
        
        if (density > 0.0)
        {
            // 计算光照
            float3 light = CalculateCloudLighting(pos, sunDir, sunColor);
            
            // 累加贡献
            totalLight += light * density * transmittance;
            totalDensity += density;
            
            // 更新透射率
            transmittance *= exp(-density * _ExtinctionCoefficient);
            
            // 提前退出
            if (transmittance < 0.01) break;
        }
        
        // 步进
        pos += rayDir * stepSize;
    }
    
    // 4. 合成最终颜色
    float3 finalColor = skyColor * transmittance + totalLight;
    return half4(finalColor, 1.0);
}
```

## 三、调试建议

### 1. 添加调试视图
在frag函数中添加调试代码，检查密度是否被正确计算：

```hlsl
// 调试：直接显示密度
// return half4(totalDensity.xxx, 1.0);

// 调试：显示步进区间
// return half4(marchRange.x, marchRange.y, 0, 1.0);

// 调试：显示相机高度
// float cameraHeight = length(_WorldSpaceCameraPos) - _EarthRadius;
// return half4(cameraHeight / 10000.0, 0, 0, 1.0);
```

### 2. 推荐的初始参数设置
在Unity材质面板中设置：

```hlsl
_EarthRadius = 6371000.0
_CloudBottomHeight = 1500.0
_CloudTopHeight = 4000.0
_CloudDensity = 0.3
_CloudThreshold = 0.2
_NoiseScale = 0.0001
```

### 3. 快速测试步骤
1. 将相机Y轴位置设为0（地面）
2. 确保太阳方向有合理角度（如Y=0.5, X=1.0）
3. 逐步增加`_CloudDensity`从0到0.5
4. 调整`_NoiseScale`从0.00001到0.001

## 四、常见问题排查

1. **如果还是看不到云**：
   - 检查3D噪声纹理是否已正确赋值
   - 检查相机是否在云层下方（Y轴低于1500）
   - 尝试将`_CloudThreshold`设为0

2. **如果云是全黑的**：
   - 检查太阳方向和颜色
   - 尝试简化光照计算，先只返回密度值

3. **如果云是纯白的**：
   - 可能是光照过强，降低`_SunColor`亮度
   - 或增加`_ExtinctionCoefficient`

按照上述修改，您的体积云应该能够正常显示。如果仍有问题，可以逐步启用调试代码来定位问题所在。