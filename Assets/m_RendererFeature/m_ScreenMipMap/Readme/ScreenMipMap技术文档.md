# ScreenMipMap 技术解释文档

## 1. 功能概述

ScreenMipMap 是一个用于 Unity URP 的渲染器特性，主要功能是：
- 在降采样分辨率下渲染不透明物体
- 生成带有 Mipmap 层级的屏幕纹理
- 支持自定义预处理效果
- 提供全局纹理供其他 Shader 使用

## 2. 架构分析

### 2.1 核心组件

| 文件 | 功能描述 |
|------|----------|
| [ScreenMipMapRendererFeature.cs](file:///d:/Document/GitHub/UnityURPLearning/Assets/m_RendererFeature/m_ScreenMipMap/ScreenMipMapRendererFeature.cs) | 渲染器特性，负责配置和创建渲染Pass |
| [ScreenMipMapPass.cs](file:///d:/Document/GitHub/UnityURPLearning/Assets/m_RendererFeature/m_ScreenMipMap/ScreenMipMapPass.cs) | 渲染Pass，执行实际的渲染逻辑 |
| [ScreenMipMapPreProcess.shader](file:///d:/Document/GitHub/UnityURPLearning/Assets/m_RendererFeature/m_ScreenMipMap/ScreenMipMapPreProcess.shader) | 预处理Shader，支持焦散等自定义效果 |
| [ScreenMipMapUsageExample.shader](file:///d:/Document/GitHub/UnityURPLearning/Assets/m_RendererFeature/m_ScreenMipMap/ScreenMipMapUsageExample.shader) | 使用示例Shader |

### 2.2 渲染流程

```
┌─────────────────────────────────────────────────────────────┐
│                    渲染管线流程                              │
├─────────────────────────────────────────────────────────────┤
│  1. OnCameraSetup                                           │
│     ├── 根据降采样质量计算目标分辨率                          │
│     ├── 创建 Color RT (支持Mipmap)                          │
│     ├── 创建 Depth RT                                       │
│     └── 创建临时 Color RT (如果启用预处理)                    │
│                                                             │
│  2. Execute                                                 │
│     ├── 设置渲染目标                                         │
│     ├── 清空RT                                              │
│     ├── 绘制不透明物体到降采样RT                             │
│     ├── 预处理 (如果启用)                                    │
│     │   ├── Pass 0: 预处理效果                              │
│     │   └── Pass 1: 复制回原RT                              │
│     ├── 生成Mipmap                                          │
│     └── 设置全局纹理 _ScreenMipMapRT                        │
└─────────────────────────────────────────────────────────────┘
```

### 2.3 关键参数说明

| 参数 | 类型 | 说明 |
|------|------|------|
| downSampleQuality | enum | 降采样质量 (1x/2x/4x) |
| mipLevelCount | int | Mipmap层级数量 (1-8) |
| rtFormat | enum | 渲染纹理格式 |
| filterMode | enum | 纹理过滤模式 |
| enablePreProcess | bool | 是否启用预处理 |
| preProcessMaterial | Material | 预处理材质 |

## 3. 技术实现细节

### 3.1 Mipmap生成机制

当前实现使用 Unity 内置的 `cmd.GenerateMips()` 方法生成 Mipmap：

```csharp
cmd.GenerateMips(screenMipMapRT);
```

这种方式使用硬件双线性插值进行降采样，会产生以下问题：
- **方块状伪影**：简单的双线性插值会导致方块状或棋盘格图案
- **频域混叠**：高频信息在降采样时折叠到低频区域

### 3.2 预处理Shader分析

预处理Shader包含两个Pass：

**Pass 0 - PreProcess**：
- 调整亮度、对比度、饱和度
- 根据深度重建世界坐标
- 计算阴影遮罩
- 在灯光空间采样3D焦散纹理
- 将焦散效果叠加到颜色上

**Pass 1 - Copy**：
- 简单复制纹理，不做任何处理

## 4. 模糊技术扩展规划

基于 [DualBlueFiltering.md](file:///d:/Document/GitHub/UnityURPLearning/Assets/m_RendererFeature/m_ScreenMipMap/Readme/DualBlueFiltering.md) 的技术分析，规划添加可切换的模糊技术。

### 4.1 模糊模式设计

```csharp
/// <summary>
/// 模糊模式枚举
/// </summary>
public enum BlurMode
{
    None,           // 不模糊，仅使用硬件Mipmap
    Simple,         // 简单降采样升采样模糊
    DualBlur        // 双重模糊（高质量圆形光晕）
}
```

### 4.2 技术对比

| 模式 | 采样策略 | 效果 | 性能 | 适用场景 |
|------|----------|------|------|----------|
| None | 硬件双线性插值 | 方块状伪影 | 最高 | 快速预览 |
| Simple | 降采样+升采样 | 轻微方块感 | 高 | 性能优先场景 |
| DualBlur | 各向同性采样模板 | 圆滑光晕 | 中 | 高质量Bloom/景深 |

### 4.3 实现步骤规划

#### 步骤1：扩展枚举和参数

**修改文件**：`ScreenMipMapRendererFeature.cs`

**添加内容**：
```csharp
[SerializeField]
[Tooltip("模糊模式：None=仅Mipmap，Simple=简单模糊，DualBlur=双重模糊")]
private BlurMode blurMode = BlurMode.None;

[SerializeField]
[Range(1, 4)]
[Tooltip("模糊迭代次数，次数越多越模糊")]
private int blurIterations = 2;
```

**Debug方法**：
- 在Inspector中添加 `DebugMode` 枚举，可选择显示：
  - `None`：正常显示
  - `ShowMipLevel`：显示指定Mip层级
  - `ShowBlurIntermediate`：显示模糊中间结果

---

#### 步骤2：创建模糊Shader

**新建文件**：`ScreenMipMapBlur.shader`

**Shader结构**：
```hlsl
Shader "Hidden/ScreenMipMap/Blur"
{
    Properties {}
    
    HLSLINCLUDE
        // 降采样Pass
        float4 FragDownsample(Varyings input) : SV_Target
        {
            // 中心点采样，权重4
            float4 sum = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv) * 4.0;
            
            // 四个角点采样
            float2 uv;
            uv = input.uv + float2(-_HalfPixelX, -_HalfPixelY);
            sum += SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv);
            
            uv = input.uv + float2(_HalfPixelX, _HalfPixelY);
            sum += SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv);
            
            uv = input.uv + float2(_HalfPixelX, -_HalfPixelY);
            sum += SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv);
            
            uv = input.uv + float2(-_HalfPixelX, _HalfPixelY);
            sum += SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv);
            
            return sum * 0.125; // sum / 8.0
        }
        
        // 升采样Pass
        float4 FragUpsample(Varyings input) : SV_Target
        {
            float4 sum = 0;
            float2 uv;
            
            // 十字形采样（权重1）
            uv = input.uv + float2(-_HalfPixelX * 2.0, 0);
            sum += SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv);
            
            uv = input.uv + float2(0, _HalfPixelY * 2.0);
            sum += SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv);
            
            uv = input.uv + float2(_HalfPixelX * 2.0, 0);
            sum += SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv);
            
            uv = input.uv + float2(0, -_HalfPixelY * 2.0);
            sum += SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv);
            
            // 四个对角采样（权重2）
            uv = input.uv + float2(-_HalfPixelX, _HalfPixelY);
            sum += SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv) * 2.0;
            
            uv = input.uv + float2(_HalfPixelX, _HalfPixelY);
            sum += SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv) * 2.0;
            
            uv = input.uv + float2(_HalfPixelX, -_HalfPixelY);
            sum += SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv) * 2.0;
            
            uv = input.uv + float2(-_HalfPixelX, -_HalfPixelY);
            sum += SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv) * 2.0;
            
            return sum / 12.0;
        }
        
        // 简单降采样Pass
        float4 FragSimpleDownsample(Varyings input) : SV_Target
        {
            return SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv);
        }
        
        // 简单升采样Pass
        float4 FragSimpleUpsample(Varyings input) : SV_Target
        {
            return SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv);
        }
    ENDHLSL
    
    SubShader
    {
        Pass { Name "Downsample" ... }
        Pass { Name "Upsample" ... }
        Pass { Name "SimpleDownsample" ... }
        Pass { Name "SimpleUpsample" ... }
    }
}
```

**Debug方法**：
- 每个Pass输出到单独的RT，通过Debug模式可选择显示
- 在Shader中添加 `_DebugShowIntermediate` 关键字

---

#### 步骤3：修改Pass支持模糊模式

**修改文件**：`ScreenMipMapPass.cs`

**添加成员变量**：
```csharp
private BlurMode blurMode;
private int blurIterations;
private Material blurMaterial;
private List<RTHandle> blurRTChain = new List<RTHandle>();
```

**修改Execute方法**：
```csharp
public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
{
    // ... 原有渲染不透明物体代码 ...
    
    switch (blurMode)
    {
        case BlurMode.None:
            // 使用硬件Mipmap
            cmd.GenerateMips(screenMipMapRT);
            break;
            
        case BlurMode.Simple:
            // 简单降采样升采样
            ExecuteSimpleBlur(cmd, context);
            break;
            
        case BlurMode.DualBlur:
            // 双重模糊
            ExecuteDualBlur(cmd, context);
            break;
    }
    
    cmd.SetGlobalTexture("_ScreenMipMapRT", screenMipMapRT);
}
```

**添加模糊执行方法**：
```csharp
private void ExecuteSimpleBlur(CommandBuffer cmd, ScriptableRenderContext context)
{
    // 创建降采样链
    // 简单降采样 -> 简单升采样
}

private void ExecuteDualBlur(CommandBuffer cmd, ScriptableRenderContext context)
{
    // 降采样阶段：使用Downsample Pass
    // 升采样阶段：使用Upsample Pass
}
```

**Debug方法**：
- 在Execute中添加条件日志输出
- 通过 `Debug.Log()` 输出当前模糊模式和迭代次数
- 支持将中间RT输出到文件进行对比

---

#### 步骤4：添加调试功能

**修改文件**：`ScreenMipMapRendererFeature.cs`

**添加调试枚举**：
```csharp
public enum DebugMode
{
    None,                   // 正常渲染
    ShowMipLevel,          // 显示指定Mip层级
    ShowBlurIntermediate,  // 显示模糊中间结果
    ShowComparison         // 左右对比显示
}

[SerializeField]
private DebugMode debugMode = DebugMode.None;

[SerializeField]
[Range(0, 7)]
private int debugMipLevel = 0;
```

**修改文件**：`ScreenMipMapUsageExample.shader`

**添加调试显示**：
```hlsl
// 在Fragment Shader中添加
#ifdef _DEBUG_SHOW_MIP_LEVEL
    return SAMPLE_TEXTURE2D_LOD(_ScreenMipMapRT, sampler_ScreenMipMapRT, input.uv, _DebugMipLevel);
#endif

#ifdef _DEBUG_SHOW_BLUR_INTERMEDIATE
    return SAMPLE_TEXTURE2D(_DebugIntermediateRT, sampler_DebugIntermediateRT, input.uv);
#endif
```

---

#### 步骤5：创建调试显示材质

**新建文件**：`ScreenMipMapDebug.shader`

**功能**：
- 支持显示指定Mip层级
- 支持显示模糊中间结果
- 支持左右对比显示不同模糊模式

---

### 4.4 完整实现流程图

```
┌────────────────────────────────────────────────────────────────────┐
│                        模糊模式选择                                 │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────────────────┐  │
│  │ BlurMode    │   │ BlurMode    │   │ BlurMode                │  │
│  │ None        │   │ Simple      │   │ DualBlur                │  │
│  └──────┬──────┘   └──────┬──────┘   └────────────┬────────────┘  │
│         │                 │                       │                │
│         ▼                 ▼                       ▼                │
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────────────────┐  │
│  │ 硬件Mipmap  │   │ 简单降采样  │   │ Dual Blur               │  │
│  │             │   │     +       │   │                         │  │
│  │             │   │ 简单升采样  │   │ 降采样链 + 升采样链      │  │
│  └─────────────┘   └─────────────┘   └─────────────────────────┘  │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

### 4.5 Dual Blur 详细流程

```
降采样阶段（金字塔构建）：
┌──────────────────────────────────────────────────────────────┐
│  Level 0 (原图)                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                                                        │ │
│  │  ┌──────────────────────────────────────────────────┐ │ │
│  │  │ Level 1 (1/2)                                    │ │ │
│  │  │  ┌────────────────────────────────────────────┐ │ │ │
│  │  │  │ Level 2 (1/4)                              │ │ │ │
│  │  │  │  ┌──────────────────────────────────────┐ │ │ │ │
│  │  │  │  │ Level 3 (1/8)                        │ │ │ │ │
│  │  │  │  │                                      │ │ │ │ │
│  │  │  │  └──────────────────────────────────────┘ │ │ │ │
│  │  │  └────────────────────────────────────────────┘ │ │ │
│  │  └──────────────────────────────────────────────────┘ │ │
│  └────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘

升采样阶段（金字塔重建）：
┌──────────────────────────────────────────────────────────────┐
│  Level 3 (1/8)                                               │
│  └──────────────────────────────────────────────────────────┐ │
│  Level 2 (1/4) ← Upsample(Level 3) + Blend                  │ │
│  └────────────────────────────────────────────────────────┐ │ │
│  Level 1 (1/2) ← Upsample(Level 2) + Blend                │ │ │
│  └──────────────────────────────────────────────────────┐ │ │ │
│  Level 0 (原图) ← Upsample(Level 1) + Blend             │ │ │ │
│  └────────────────────────────────────────────────────┘ │ │ │
└────────────────────────────────────────────────────────┘ │ │
└──────────────────────────────────────────────────────────┘
```

## 5. 使用示例

### 5.1 基本使用

```csharp
// 在Shader中使用全局纹理
TEXTURE2D(_ScreenMipMapRT);
SAMPLER(sampler_ScreenMipMapRT);

// 采样指定Mip层级
float4 color = SAMPLE_TEXTURE2D_LOD(_ScreenMipMapRT, sampler_ScreenMipMapRT, uv, mipLevel);
```

### 5.2 配置建议

| 场景 | 降采样质量 | Mip层级 | 模糊模式 | 迭代次数 |
|------|------------|---------|----------|----------|
| 快速预览 | High (4x) | 2 | None | - |
| 标准Bloom | Medium (2x) | 4 | DualBlur | 2 |
| 高质量景深 | Low (1x) | 6 | DualBlur | 3 |
| 移动端优化 | High (4x) | 3 | Simple | 1 |

## 6. 性能优化建议

1. **降采样质量选择**：
   - 移动端建议使用 High (4x) 降采样
   - PC端可使用 Medium (2x) 或 Low (1x)

2. **Mip层级控制**：
   - 层级越多越模糊，但内存占用增加
   - 建议不超过 6 层

3. **模糊模式选择**：
   - 性能优先：Simple 模式
   - 质量优先：DualBlur 模式

4. **迭代次数**：
   - DualBlur 建议 2-3 次迭代
   - 过多迭代会显著增加GPU开销

## 7. 已知问题和限制

1. 当前预处理Shader依赖主光源阴影，需要正确配置阴影设置
2. 焦散效果需要3D纹理资源
3. Mipmap生成在GPU上执行，可能有轻微延迟

## 8. 参考资源

- [DualBlueFiltering.md](file:///d:/Document/GitHub/UnityURPLearning/Assets/m_RendererFeature/m_ScreenMipMap/Readme/DualBlueFiltering.md) - Dual Blur技术详解
- [Unity URP文档](https://docs.unity3d.com/Packages/com.unity.render-pipelines.universal@latest)
