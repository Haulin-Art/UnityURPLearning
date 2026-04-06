# 体积云渲染Renderer Feature技术规划

## 1. 项目概述

本项目旨在创建一个URP Renderer Feature，用于渲染体积云到RGFloat格式的RenderTexture，并通过双边滤波模糊消除噪点，最终输出到用户指定的RT。

## 2. 实现步骤

### 步骤1：创建体积云专用Shader
- **目标**：创建一个专门用于渲染体积云到RGFloat格式的Shader
- **实现**：
  - 基于现有的VolumetricCloudSkybox.shader修改
  - 输出格式改为RGFloat，R通道存储云密度，G通道存储viewTransmittance.x
  - 移除环境贴图混合，只渲染云
- **Debug方法**：
  - 添加Debug模式，可选择只显示R通道或G通道
  - 在Scene视图中实时预览渲染结果

### 步骤2：创建双边滤波Compute Shader
- **目标**：实现双边滤波算法，消除云渲染中的噪点
- **实现**：
  - 创建Compute Shader文件
  - 实现双边滤波算法，考虑空间距离和颜色相似性
  - 支持可调的滤波参数（半径、sigma等）
- **Debug方法**：
  - 添加Debug选项，可查看滤波前后的对比
  - 输出中间结果到临时RT

### 步骤3：创建Renderer Feature
- **目标**：创建URP Renderer Feature，管理整个渲染流程
- **实现**：
  - 创建AtmosphereSystem.cs文件
  - 实现ScriptableRendererFeature和ScriptableRenderPass
  - 管理临时RT的创建和释放
  - 实现渲染管线：体积云渲染 → 双边滤波 → 输出到用户指定RT
- **Debug方法**：
  - 添加Debug模式枚举，可选择不同的调试视图
  - 在Inspector中显示性能统计信息

### 步骤4：集成到URP管线
- **目标**：将Renderer Feature添加到URP渲染管线中
- **实现**：
  - 在URP Asset中添加该Renderer Feature
  - 配置参数和RT输出
- **Debug方法**：
  - 验证渲染顺序是否正确
  - 检查RT分辨率和格式设置

## 3. 技术细节

### 3.1 体积云Shader修改
- 保留现有的云散射计算逻辑
- 修改输出通道：
  - R通道：云密度/颜色
  - G通道：viewTransmittance.x
  - B和A通道：未使用
- 移除环境贴图采样和混合逻辑

### 3.2 双边滤波算法
- 空间域滤波：考虑像素间的距离
- 值域滤波：考虑像素值的差异
- 可调节参数：
  - 滤波半径
  - 空间sigma
  - 值域sigma

### 3.3 Renderer Feature架构
- **ScriptableRendererFeature**：管理Feature的整体配置
- **ScriptableRenderPass**：执行具体的渲染操作
- **资源管理**：
  - 临时RT的创建和释放
  - Shader和Compute Shader的引用
  - 材质的创建和更新

## 4. 性能优化

- 使用适当分辨率的临时RT
- 实现Compute Shader的线程组优化
- 避免不必要的纹理采样和计算
- 考虑使用多级渲染目标(MRT)减少渲染通道

## 5. 预期效果

- 体积云渲染质量提升（无噪点）
- 可调节的滤波参数
- 灵活的RT输出配置
- 良好的性能表现

## 6. 测试计划

- 在不同场景下测试云渲染质量
- 测试不同分辨率和滤波参数的性能影响
- 验证与其他渲染Feature的兼容性
- 测试在不同硬件上的表现