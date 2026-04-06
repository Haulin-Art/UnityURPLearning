# 体积云渲染系统使用说明

## 系统概述

本系统是一个基于URP的体积云渲染Renderer Feature，主要功能包括：

- 渲染体积云到RGFloat格式的RenderTexture
- 通过双边滤波消除云渲染中的噪点
- 输出到用户指定的RenderTexture
- 提供多种Debug模式用于调试

## 目录结构

```
AtmosphereSystem/
├── RendererFeature/        # Renderer Feature代码
│   └── AtmosphereSystem.cs
├── Shaders/                # 着色器文件
│   ├── VolumetricCloudRT.shader    # 体积云渲染Shader
│   └── BilateralFilter.compute     # 双边滤波Compute Shader
├── Materials/              # 材质文件
├── TechnicalPlan.md        # 技术规划文档
└── README.md               # 本说明文件
```

## 使用步骤

### 1. 创建必要的资源

1. **创建云纹理**：
   - 创建一个3D纹理作为云纹理，推荐分辨率为128x128x128
   - 创建或导入一张蓝噪声纹理用于采样

2. **创建材质**：
   - 在`Materials`目录下创建一个新材质
   - 选择`Custom/VolumetricCloudRT`着色器
   - 配置云纹理、蓝噪声纹理和其他云参数

3. **创建输出RenderTexture**：
   - 创建一个新的RenderTexture
   - 设置格式为`RGFloat`
   - 分辨率根据需要设置（推荐1024x1024或更高）

### 2. 添加Renderer Feature到URP管线

1. 在Project窗口中找到你的URP Asset（通常在`Settings`目录下）
2. 双击打开URP Asset
3. 在`Renderer Features`部分点击`+`按钮
4. 选择`AtmosphereSystem`
5. 在Inspector中配置以下参数：
   - `Cloud Material`：选择你创建的体积云材质
   - `Cloud RT Resolution`：设置云渲染的分辨率
   - `Bilateral Filter CS`：选择`BilateralFilter.compute`文件
   - `Filter Radius`：滤波半径，影响模糊程度
   - `Sigma Space`：空间域sigma值
   - `Sigma Range`：值域sigma值
   - `Output RT`：选择你创建的输出RenderTexture
   - `Debug Mode`：选择调试模式（可选）

### 3. 配置参数

#### 云参数
- `整体缩放`：调整整个云系统的缩放比例
- `行星半径`：行星的半径，影响云的分布
- `海拔(km)`：相机的海拔高度
- `太阳亮度`：太阳的亮度
- `视线采样数`：视线方向的采样数量，影响云的细节和性能
- `太阳光采样数`：太阳光方向的采样数量，影响云阴影的质量
- `云底高度`：云的底部高度
- `云厚度`：云的厚度
- `云散射系数`：云的散射系数
- `云消光系数`：云的消光系数
- `云相位函数G值`：云的相位函数参数，影响云的前向散射特性
- `云密度阈值`：云密度的阈值，控制云的透明度
- `云密度乘数`：云密度的乘数，控制云的浓密程度

#### 滤波参数
- `Filter Radius`：滤波半径，越大模糊效果越明显
- `Sigma Space`：空间域sigma值，控制空间距离的权重
- `Sigma Range`：值域sigma值，控制颜色相似性的权重

### 4. Debug模式

系统提供以下Debug模式：
- `None`：正常渲染，不显示调试信息
- `CloudRT`：显示原始的云渲染结果
- `FilteredRT`：显示滤波后的云渲染结果
- `Performance`：显示性能统计信息

## 性能优化

1. **调整采样数量**：减少采样数量可以提高性能，但会降低云的质量
2. **调整云RT分辨率**：降低分辨率可以提高性能，但会降低云的细节
3. **调整滤波参数**：减小滤波半径可以提高性能
4. **使用合适的硬件**：体积云渲染对GPU性能要求较高，建议使用高性能GPU

## 注意事项

1. 确保输出RenderTexture的格式为`RGFloat`，否则可能会导致渲染错误
2. 云纹理和蓝噪声纹理的质量会直接影响云的渲染效果
3. 采样数量和滤波参数需要根据具体场景和硬件性能进行调整
4. 本系统只渲染体积云，不包括天空盒背景，需要单独设置天空盒

## 故障排除

1. **云不显示**：
   - 检查云材质的参数设置
   - 确保云纹理和蓝噪声纹理正确设置
   - 检查相机位置是否在云的范围内

2. **云渲染速度慢**：
   - 减少采样数量
   - 降低云RT分辨率
   - 减小滤波半径

3. **云有噪点**：
   - 增加采样数量
   - 调整滤波参数，增大滤波半径或sigma值

4. **输出RT没有内容**：
   - 检查输出RT的格式是否为`RGFloat`
   - 检查Renderer Feature的配置是否正确
   - 检查URP管线是否正确添加了Renderer Feature