# Planar Reflection Renderer Feature

## 概述

这是一个基于 Unity URP (Universal Render Pipeline) 的平面反射渲染功能，用于生成水面、镜面等平面物体的反射效果。

## 功能特点

- 实时生成平面反射效果
- 可配置的反射纹理分辨率
- 支持更新频率控制，优化性能
- 支持层掩码控制，只渲染需要反射的物体
- 自动将反射纹理设置为全局纹理，供材质使用
- 提供示例 shader 和材质

## 安装方法

1. 将整个 `PlanarReflection` 文件夹复制到你的 Unity 项目的 `Assets` 目录中
2. 在 URP 渲染器资产中添加 `PlanarReflectionRendererFeature`

## 配置步骤

1. **添加 Renderer Feature**
   - 打开 Project 窗口，找到你的 URP 渲染器资产（通常在 `Assets/Settings` 目录下）
   - 双击打开渲染器资产
   - 在 Inspector 窗口中，点击 "Add Renderer Feature" 按钮
   - 选择 "PlanarReflectionRendererFeature"

2. **配置参数**
   - `Profiler Tag`：性能分析标签，默认为 "Planar Reflection"
   - `Reflection Layer Mask`：反射层掩码，控制哪些层的物体会被反射
   - `Reflection Texture Resolution`：反射纹理分辨率，默认为 512
   - `Update Interval`：反射更新间隔（秒），默认为 1.0
   - `Clip Plane Offset`：裁剪平面偏移，默认为 0.07
   - `Debug View`：调试视图开关，开启后会在控制台输出调试信息

3. **使用反射纹理**
   - 在材质 shader 中，使用 `_PlanarReflectionTexture` 采样反射纹理
   - 示例 shader 已提供：`PlanarReflectionShader.shader`
   - 示例材质已提供：`PlanarReflectionMaterial.mat`

## 示例用法

1. 创建一个平面物体（如地面或水面）
2. 将 `PlanarReflectionMaterial` 材质应用到该物体上
3. 调整材质参数：
   - `Color`：物体本身的颜色
   - `Reflection Strength`：反射强度
   - `Fresnel Power`：菲涅尔效应强度

## 性能优化

1. **降低分辨率**：根据场景需求，适当降低反射纹理分辨率
2. **增加更新间隔**：对于静态场景，可以增加更新间隔以提高性能
3. **限制反射层**：只反射必要的物体层
4. **调整相机参数**：合理设置反射相机的远裁剪平面

## 注意事项

1. 当前实现使用 Y=0 平面作为反射平面，实际项目中可能需要根据具体需求调整反射平面的位置和法线
2. 反射效果的质量和性能取决于反射纹理的分辨率和更新频率
3. 对于复杂场景，建议使用较低的分辨率和较长的更新间隔

## 技术原理

1. **反射矩阵**：基于平面方程计算反射矩阵，用于将相机位置和方向反射到对称位置
2. **斜投影矩阵**：确保反射相机只渲染平面上方的物体，避免看到平面背后的物体
3. **URP 渲染流程**：通过 ScriptableRendererFeature 和 ScriptableRenderPass 集成到 URP 渲染管线中
4. **全局纹理**：将反射纹理设置为全局纹理，供材质 shader 使用

## 调试方法

1. 开启 `Debug View` 选项，查看控制台输出的调试信息
2. 检查反射相机的位置和视角（反射相机名称为 "PlanarReflectionCamera"）
3. 使用 RenderTexture 预览工具查看反射纹理的内容
4. 调整参数，观察反射效果的变化

## 版本要求

- Unity 2020.3 或更高版本
- Universal Render Pipeline 10.0 或更高版本
