# 表面流体系统 - 技术规划文档

## 1. 功能概述

### 1.1 UV岛跳跃功能
在流体模拟的平流项中，当使用半拉格朗日法回溯UV时，通过UV跳跃图实现跨UV岛的流体传输。这使得流体可以在不同UV岛之间"跳跃"，模拟无缝的表面流体效果。

### 1.2 重力方向图功能
通过重力方向贴图，为流体添加始终作用的重力效果。重力方向由贴图的RG通道决定，可以模拟复杂曲面上的重力流动效果。

## 2. UV跳跃图

### 2.1 贴图格式
- **RG通道**：存储跳跃目标UV坐标 (x, y)
- **边界区域**：记录跳跃目标UV（当流体到达边界时，跳转到该UV位置）
- **非边界区域**：存储(0,0)或当前像素自身UV坐标

### 2.2 核心逻辑
```hlsl
// 采样UV跳跃图
float2 jumpUV = UVJumpMap.SampleLevel(samplerLinearClamp, backtracedUV, 0).xy;

// 判断是否需要跳跃（RG通道值不为0表示需要跳跃）
float jumpMask = step(0.001, length(jumpUV));

// 如果跳跃UV有效，则使用跳跃UV，否则使用原UV
float2 finalUV = lerp(backtracedUV, jumpUV, jumpMask);
```

## 3. 重力方向图

### 3.1 贴图格式
- **RG通道**：存储重力方向向量 (x, y)
- **范围**：原始数据为0~1，在Shader中映射到-1~1
- **作用**：始终作用于流体，模拟重力效果

### 3.2 核心逻辑
```hlsl
// 采样重力图（RG通道范围0~1）
float2 gravityDir = GravityMap.SampleLevel(samplerLinearClamp, uv, 0).xy;

// 映射到-1~1范围
gravityDir = gravityDir * 2.0 - 1.0;

// 应用重力
velocity += gravityDir * gravityStrength * dt;
```

### 3.3 调试方法
- 通过 `ShowGravityMap` 调试模式查看重力图
- 调整 `gravityStrength` 参数控制重力强度

## 4. 调试模式系统

### 4.1 调试枚举
```csharp
public enum FluidDebugMode
{
    None,               // 正常模式
    ShowUVJumpMap,      // 显示UV跳跃图
    ShowBacktracedUV,   // 显示回溯UV
    ShowJumpedUV,       // 显示跳跃后UV
    ShowVelocityField,  // 显示速度场
    ShowSourcePosition, // 显示源位置
    ShowGravityMap      // 显示重力图
}
```

### 4.2 各调试模式说明

| 调试模式 | 输出内容 | 用途 |
|---------|---------|-----|
| ShowUVJumpMap | UV跳跃图RG通道 | 检查跳跃图是否正确生成 |
| ShowBacktracedUV | 回溯UV坐标 | 检查半拉格朗日回溯是否正确 |
| ShowJumpedUV | 跳跃后UV坐标 | 检查UV跳跃是否生效 |
| ShowVelocityField | 速度场可视化 | 检查流体速度分布 |
| ShowSourcePosition | 源位置标记 | 检查射线检测是否正确 |
| ShowGravityMap | 重力图RG通道 | 检查重力方向是否正确 |

## 5. 文件清单

| 文件 | 说明 |
|-----|-----|
| SurfaceFluid.compute | 流体计算着色器 |
| SurfaceFluidSimulation.cs | 流体驱动脚本 |
| RaycastTargetDetector.cs | 射线检测脚本 |
| SurfaceFluidSystem_TechPlan.md | 本技术规划文档 |

## 6. 使用方法

### 6.1 基础设置
1. 创建物体并添加 `RaycastTargetDetector` 组件
2. 创建物体并添加 `SurfaceFluidSimulation` 组件
3. 设置 `computeShader` 为 `SurfaceFluid.compute`

### 6.2 UV跳跃功能
1. 使用 `Tools > UV Island Jump Tool` 生成UV跳跃贴图
2. 在 `SurfaceFluidSimulation` 组件中设置 `uvJumpMap`
3. 勾选 `useUVJump` 启用功能

### 6.3 重力图功能
1. 准备重力方向贴图（RG通道存储方向，范围0~1）
2. 在 `SurfaceFluidSimulation` 组件中设置 `gravityMap`
3. 勾选 `useGravityMap` 启用功能
4. 调整 `gravityStrength` 控制重力强度

### 6.4 调试步骤
1. 创建一个 `RenderTexture` 作为 `debugOutputTexture`
2. 切换 `debugMode` 查看不同的调试信息
3. 通过 `debugOutputTexture` 查看输出结果

## 7. 注意事项

1. UV跳跃图需要预先通过 `UVIslandJumpTool` 生成
2. UV跳跃图和重力图的尺寸应与流体模拟尺寸一致
3. 重力图的方向是始终作用的力，会持续影响流体
4. 调试模式会额外执行一个Compute Shader Kernel，可能影响性能
