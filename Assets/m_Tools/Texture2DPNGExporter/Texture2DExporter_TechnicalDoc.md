# Texture2D 导出工具技术分析文档

## 一、概述

Texture2D 导出工具是一个 Unity Editor 扩展工具，用于将 Unity 内部的纹理资源（Texture2D 和 RenderTexture）导出为各种常见的图像格式文件。该工具提供了丰富的格式支持、通道操作和分辨率调整功能。

---

## 二、核心架构

### 2.1 整体流程图

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              导出流程                                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌──────────────┐    ┌──────────────────┐    ┌─────────────────┐           │
│  │ 输入纹理     │───▶│ 获取可读纹理     │───▶│ 通道操作处理    │           │
│  │ (Texture)    │    │ (Texture2D)      │    │ (可选)          │           │
│  └──────────────┘    └──────────────────┘    └─────────────────┘           │
│         │                                            │                      │
│         ▼                                            ▼                      │
│  ┌──────────────┐    ┌──────────────────┐    ┌─────────────────┐           │
│  │ Texture2D    │    │ RenderTexture    │    │ 其他Texture     │           │
│  │ 直接读取     │    │ GPU→CPU回读      │    │ RT中转读取      │           │
│  └──────────────┘    └──────────────────┘    └─────────────────┘           │
│                                                     │                      │
│                                                     ▼                      │
│                              ┌─────────────────────────────────┐            │
│                              │ 规格化处理 (可选)               │            │
│                              │ [-1,1] → [0,1]                  │            │
│                              └─────────────────────────────────┘            │
│                                                     │                      │
│                                                     ▼                      │
│                              ┌─────────────────────────────────┐            │
│                              │ 分辨率调整 (可选)               │            │
│                              │ 原始/自定义/缩放                │            │
│                              └─────────────────────────────────┘            │
│                                                     │                      │
│                                                     ▼                      │
│                              ┌─────────────────────────────────┐            │
│                              │ 格式编码                        │            │
│                              │ PNG/JPG/TGA/WebP/EXR/TIF        │            │
│                              └─────────────────────────────────┘            │
│                                                     │                      │
│                                                     ▼                      │
│                              ┌─────────────────────────────────┐            │
│                              │ 文件写入                        │            │
│                              └─────────────────────────────────┘            │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 模块划分

| 模块 | 功能 | 关键方法 |
|------|------|----------|
| **输入处理** | 支持多种纹理类型输入 | `GetReadableTextureFromSource()` |
| **通道操作** | 单通道提取/通道重组 | `ProcessChannels()` |
| **规格化** | 值域映射 | `NormalizeTexture()` |
| **分辨率调整** | 缩放/自定义尺寸 | `ResizeTexture()` |
| **格式编码** | 多格式文件编码 | `EncodeTexture()` |

---

## 三、输入处理原理

### 3.1 支持的输入类型

```csharp
// 输入字段使用 Texture 基类
private Texture sourceTexture;
```

工具支持三种输入类型的处理：

#### 3.1.1 Texture2D 输入

```
┌─────────────────────────────────────────────────────────────┐
│                    Texture2D 输入处理                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   Texture2D                                                 │
│       │                                                     │
│       ▼                                                     │
│   ┌─────────────────┐                                       │
│   │ isReadable?     │                                       │
│   └────────┬────────┘                                       │
│            │                                                │
│      ┌─────┴─────┐                                          │
│      ▼           ▼                                          │
│    Yes          No                                          │
│      │           │                                          │
│      ▼           ▼                                          │
│   直接使用    RenderTexture中转                             │
│   GetPixels()  Graphics.Blit → ReadPixels                   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**关键代码逻辑：**

```csharp
private Texture2D GetReadableTexture(Texture2D source)
{
    // 检查是否为项目资源
    string assetPath = AssetDatabase.GetAssetPath(source);
    
    if (!string.IsNullOrEmpty(assetPath))
    {
        // 获取导入设置
        TextureImporter importer = AssetImporter.GetAtPath(assetPath) as TextureImporter;
        
        // 如果未开启 Read/Write，需要通过 RenderTexture 中转
        if (importer != null && !importer.isReadable)
        {
            // 创建临时 RenderTexture
            RenderTexture rt = RenderTexture.GetTemporary(width, height, 0, format);
            
            // GPU Blit 操作
            Graphics.Blit(source, rt);
            
            // 回读到 CPU
            RenderTexture.active = rt;
            readableTexture.ReadPixels(rect, 0, 0);
            readableTexture.Apply();
            
            // 清理
            RenderTexture.active = null;
            RenderTexture.ReleaseTemporary(rt);
            
            return readableTexture;
        }
    }
    
    return source;  // 已可读，直接返回
}
```

#### 3.1.2 RenderTexture 输入

```
┌─────────────────────────────────────────────────────────────┐
│                  RenderTexture 输入处理                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   RenderTexture (GPU 显存)                                  │
│       │                                                     │
│       ▼                                                     │
│   ┌─────────────────────────────────────┐                   │
│   │ RenderTexture.active = rt           │  设置激活RT       │
│   └─────────────────────────────────────┘                   │
│       │                                                     │
│       ▼                                                     │
│   ┌─────────────────────────────────────┐                   │
│   │ Texture2D.ReadPixels()              │  GPU→CPU 回读     │
│   └─────────────────────────────────────┘                   │
│       │                                                     │
│       ▼                                                     │
│   ┌─────────────────────────────────────┐                   │
│   │ Texture2D.Apply()                   │  应用更改         │
│   └─────────────────────────────────────┘                   │
│       │                                                     │
│       ▼                                                     │
│   Texture2D (CPU 内存)                                      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**GPU → CPU 数据传输原理：**

```csharp
private Texture2D ReadFromRenderTexture(RenderTexture rt, bool needHDR)
{
    // 1. 创建目标 Texture2D
    TextureFormat format = needHDR ? TextureFormat.RGBAFloat : TextureFormat.RGBA32;
    Texture2D result = new Texture2D(width, height, format, false);

    // 2. 保存当前激活状态（重要：避免破坏渲染状态）
    RenderTexture prevActive = RenderTexture.active;

    try
    {
        // 3. 设置目标 RT 为激活状态
        RenderTexture.active = rt;
        
        // 4. 从激活的 RT 读取像素到 Texture2D
        //    这是 GPU → CPU 的关键传输步骤
        result.ReadPixels(new Rect(0, 0, width, height), 0, 0);
        result.Apply();
    }
    finally
    {
        // 5. 恢复之前的激活状态
        RenderTexture.active = prevActive;
    }

    return result;
}
```

#### 3.1.3 HDR 格式检测

```csharp
private bool IsHDRFormat(RenderTextureFormat format)
{
    return format == RenderTextureFormat.ARGBFloat ||    // 128位浮点 (32位×4)
           format == RenderTextureFormat.ARGBHalf ||     // 64位浮点 (16位×4)
           format == RenderTextureFormat.RFloat ||       // 32位单通道浮点
           format == RenderTextureFormat.RGFloat ||      // 64位双通道浮点
           format == RenderTextureFormat.RHalf ||        // 16位单通道浮点
           format == RenderTextureFormat.RGHalf ||       // 32位双通道浮点
           format == RenderTextureFormat.RGB111110Float; // 32位打包RGB浮点
}
```

---

## 四、通道操作原理

### 4.1 通道操作模式

```
┌─────────────────────────────────────────────────────────────┐
│                      通道操作模式                            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────┐        │
│  │ All (默认)  │   │ Single      │   │ Remap       │        │
│  │ 保留所有通道│   │ 单通道提取  │   │ 通道重组    │        │
│  └─────────────┘   └─────────────┘   └─────────────┘        │
│                                                             │
│  RGBA → RGBA       R → RGB              R → 新R             │
│                    G → RGB              G → 新G             │
│                    B → RGB              B → 新B             │
│                    A → RGB              A → 新A             │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 4.2 单通道提取

**应用场景：** 提取 Alpha 通道作为灰度图、提取法线贴图的某个分量

```csharp
// 单通道导出：将选定通道输出到 RGB，Alpha 设为 1
for (int i = 0; i < pixels.Length; i++)
{
    float channelValue = GetChannelValue(pixels[i], singleChannel);
    pixels[i] = new Color(channelValue, channelValue, channelValue, 1f);
}
```

**效果示意：**

```
原始 RGBA          提取 R 通道后
┌────────────┐     ┌────────────┐
│ R: 0.8     │     │ R: 0.8     │
│ G: 0.3     │ ──▶ │ G: 0.8     │
│ B: 0.5     │     │ B: 0.8     │
│ A: 1.0     │     │ A: 1.0     │
└────────────┘     └────────────┘
```

### 4.3 通道重组

**应用场景：** 将多张纹理的通道合并到一张、设置固定值

```csharp
// 通道重组
for (int i = 0; i < pixels.Length; i++)
{
    float r = GetChannelSourceValue(pixels[i], remapR);
    float g = GetChannelSourceValue(pixels[i], remapG);
    float b = GetChannelSourceValue(pixels[i], remapB);
    float a = GetChannelSourceValue(pixels[i], remapA);
    pixels[i] = new Color(r, g, b, a);
}
```

**通道源选项：**

| 源 | 说明 |
|---|------|
| R/G/B/A | 从对应通道取值 |
| One | 固定值 1.0（白色） |
| Zero | 固定值 0.0（黑色） |

---

## 五、分辨率调整原理

### 5.1 缩放流程

```
┌─────────────────────────────────────────────────────────────┐
│                      分辨率调整流程                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   原始纹理 (W×H)                                            │
│       │                                                     │
│       ▼                                                     │
│   ┌─────────────────────────────────────┐                   │
│   │ 创建目标尺寸的临时 RenderTexture    │                   │
│   └─────────────────────────────────────┘                   │
│       │                                                     │
│       ▼                                                     │
│   ┌─────────────────────────────────────┐                   │
│   │ 设置 FilterMode                     │                   │
│   │ Point: 像素风格，保持锐利           │                   │
│   │ Bilinear: 平滑缩放                  │                   │
│   └─────────────────────────────────────┘                   │
│       │                                                     │
│       ▼                                                     │
│   ┌─────────────────────────────────────┐                   │
│   │ Graphics.Blit(source, targetRT)    │  GPU 缩放         │
│   └─────────────────────────────────────┘                   │
│       │                                                     │
│       ▼                                                     │
│   ┌─────────────────────────────────────┐                   │
│   │ ReadPixels 回读到 Texture2D         │                   │
│   └─────────────────────────────────────┘                   │
│       │                                                     │
│       ▼                                                     │
│   目标纹理 (NewW × NewH)                                    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 5.2 采样模式对比

```
Point 采样 (FilterMode.Point):
┌───┬───┬───┐     ┌───────┬───────┐
│ A │ B │ C │     │ A │ A │ B │ B │
├───┼───┼───┤ ──▶ ├───┼───┼───┼───┤
│ D │ E │ F │     │ D │ D │ E │ E │
└───┴───┴───┘     └───────┴───────┘
  3×3 原始           6×4 放大
  (像素复制，锐利边缘)

Bilinear 采样 (FilterMode.Bilinear):
┌───┬───┬───┐     ┌───────────────┐
│ A │ B │ C │     │ A │   │   │ B │
├───┼───┼───┤ ──▶ │   │   │   │   │  (双线性插值)
│ D │ E │ F │     │   │   │   │   │
└───┴───┴───┘     │ D │   │   │ E │
                    └───────────────┘
  3×3 原始           6×4 放大
  (平滑过渡)
```

---

## 六、图像格式编码原理

### 6.1 支持格式总览

| 格式 | 位深 | 压缩 | Alpha | 编码方式 |
|------|------|------|-------|----------|
| PNG | 8位 | 无损 | ✅ | Unity 原生 |
| JPG | 8位 | 有损 | ❌ | Unity 原生 |
| TGA | 8位 | 无 | ✅ | 手动实现 |
| WebP | 8位 | 无损/有损 | ✅ | Unity 2021.2+ |
| EXR | 32位浮点 | 可选ZIP | ✅ | Unity 原生 |
| TIF | 8/16位 | 无 | ✅ | 手动实现 |

### 6.2 TGA 格式编码

**TGA 文件结构：**

```
┌─────────────────────────────────────────────────────────────┐
│                      TGA 文件结构                            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   ┌─────────────────────────────────────────────────────┐   │
│   │ Header (18 字节)                                    │   │
│   ├─────────────────────────────────────────────────────┤   │
│   │ Offset  Size  Description                           │   │
│   │ 0       1     ID length (0)                         │   │
│   │ 1       1     Color map type (0)                    │   │
│   │ 2       1     Image type (2 = 未压缩真彩色)         │   │
│   │ 3       5     Color map specification (忽略)        │   │
│   │ 8       2     X origin (0)                          │   │
│   │ 10      2     Y origin (0)                          │   │
│   │ 12      2     Width                                 │   │
│   │ 14      2     Height                                │   │
│   │ 16      1     Pixel depth (32 = RGBA)               │   │
│   │ 17      1     Image descriptor (0x28 = 从上到下)    │   │
│   └─────────────────────────────────────────────────────┘   │
│                                                             │
│   ┌─────────────────────────────────────────────────────┐   │
│   │ Pixel Data (Width × Height × 4 字节)               │   │
│   ├─────────────────────────────────────────────────────┤   │
│   │ 每像素 4 字节，顺序为 BGRA                          │   │
│   │ B: 蓝色通道                                         │   │
│   │ G: 绿色通道                                         │   │
│   │ R: 红色通道                                         │   │
│   │ A: Alpha 通道                                       │   │
│   └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**关键编码代码：**

```csharp
private byte[] EncodeToTGA(Texture2D texture)
{
    // 文件头
    byte[] header = new byte[18];
    header[2] = 2;      // 图像类型：未压缩真彩色
    header[12] = (byte)(width & 0xFF);
    header[13] = (byte)((width >> 8) & 0xFF);
    header[14] = (byte)(height & 0xFF);
    header[15] = (byte)((height >> 8) & 0xFF);
    header[16] = 32;    // 32位 = RGBA
    header[17] = 0x28;  // 从上到下存储

    // 像素数据（注意 BGRA 顺序）
    for (int i = 0; i < pixels.Length; i++)
    {
        pixelData[idx + 0] = (byte)(pixels[i].b * 255);  // B
        pixelData[idx + 1] = (byte)(pixels[i].g * 255);  // G
        pixelData[idx + 2] = (byte)(pixels[i].r * 255);  // R
        pixelData[idx + 3] = (byte)(pixels[i].a * 255);  // A
    }
}
```

### 6.3 TIFF 格式编码

**TIFF 文件结构：**

```
┌─────────────────────────────────────────────────────────────┐
│                      TIFF 文件结构                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   ┌─────────────────────────────────────────────────────┐   │
│   │ Header (8 字节)                                     │   │
│   ├─────────────────────────────────────────────────────┤   │
│   │ Byte 0-1: 字节顺序标识 ("II" = Little-endian)      │   │
│   │ Byte 2-3: TIFF 标识 (42)                           │   │
│   │ Byte 4-7: 第一个 IFD 的偏移量                       │   │
│   └─────────────────────────────────────────────────────┘   │
│                                                             │
│   ┌─────────────────────────────────────────────────────┐   │
│   │ IFD (Image File Directory)                          │   │
│   ├─────────────────────────────────────────────────────┤   │
│   │ Entry 格式 (每条 12 字节):                          │   │
│   │ ┌─────────┬─────────┬─────────┬─────────┐          │   │
│   │ │ Tag(2)  │ Type(2) │Count(4) │Value/   │          │   │
│   │ │         │         │         │Offset(4)│          │   │
│   │ └─────────┴─────────┴─────────┴─────────┘          │   │
│   │                                                     │   │
│   │ 主要 Tags:                                          │   │
│   │ 256: ImageWidth                                     │   │
│   │ 257: ImageLength                                    │   │
│   │ 258: BitsPerSample                                  │   │
│   │ 259: Compression (1=无压缩)                         │   │
│   │ 262: PhotometricInterpretation (2=RGB)              │   │
│   │ 273: StripOffsets                                   │   │
│   │ 277: SamplesPerPixel                                │   │
│   │ 278: RowsPerStrip                                   │   │
│   │ 279: StripByteCounts                                │   │
│   │ 282: XResolution                                    │   │
│   │ 283: YResolution                                    │   │
│   │ 296: ResolutionUnit                                 │   │
│   └─────────────────────────────────────────────────────┘   │
│                                                             │
│   ┌─────────────────────────────────────────────────────┐   │
│   │ 像素数据                                            │   │
│   ├─────────────────────────────────────────────────────┤   │
│   │ 8位模式: 每通道 1 字节 (0-255)                      │   │
│   │ 16位模式: 每通道 2 字节 (0-65535)                   │   │
│   │ 顺序: RGBA (从上到下，从左到右)                     │   │
│   └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**TIFF 数据类型：**

| Type | 名称 | 大小 |
|------|------|------|
| 1 | BYTE | 1 字节 |
| 2 | ASCII | 1 字节 |
| 3 | SHORT | 2 字节 |
| 4 | LONG | 4 字节 |
| 5 | RATIONAL | 8 字节 (两个 LONG) |

### 6.4 EXR 格式（HDR）

**EXR 特点：**

- 32位浮点精度，支持 HDR 内容
- 可选 ZIP 压缩
- 适合法线贴图、深度贴图、高动态范围纹理

```csharp
// EXR 编码
Texture2D.EXRFlags exrFlags = exrCompress 
    ? Texture2D.EXRFlags.CompressZIP 
    : Texture2D.EXRFlags.None;
byte[] data = texture.EncodeToEXR(exrFlags);
```

---

## 七、规格化处理

### 7.1 规格化原理

```
规格化公式: value = value * 0.5 + 0.5

原始范围 [-1, 1]  ───────────────▶  目标范围 [0, 1]

输入值    输出值
───────────────────
 -1.0  →   0.0
 -0.5  →   0.25
  0.0  →   0.5
  0.5  →   0.75
  1.0  →   1.0
```

### 7.2 应用场景

- **法线贴图导出**：Unity 法线贴图存储在 [-1, 1] 范围，导出为 PNG 需要映射到 [0, 1]
- **深度贴图导出**：深度值可能有负值，需要规格化后才能正确显示

```csharp
private Texture2D NormalizeTexture(Texture2D source, bool isHDR)
{
    Color[] pixels = source.GetPixels();
    
    for (int i = 0; i < pixels.Length; i++)
    {
        // 只对 RGB 通道进行规格化，保留 Alpha
        pixels[i].r = pixels[i].r * 0.5f + 0.5f;
        pixels[i].g = pixels[i].g * 0.5f + 0.5f;
        pixels[i].b = pixels[i].b * 0.5f + 0.5f;
    }
    
    normalizedTexture.SetPixels(pixels);
    normalizedTexture.Apply();
    
    return normalizedTexture;
}
```

---

## 八、内存管理

### 8.1 临时资源清理

```csharp
// 导出流程中的内存管理
private void ExportTexture()
{
    Texture2D exportTexture = GetReadableTextureFromSource(needHDR);
    
    try
    {
        // 处理纹理...
        
        // 编码并写入文件
        byte[] textureData = EncodeTexture(exportTexture);
        File.WriteAllBytes(filePath, textureData);
    }
    finally
    {
        // 清理临时纹理
        if (exportTexture != sourceTexture)
        {
            DestroyImmediate(exportTexture);
        }
    }
}
```

### 8.2 RenderTexture 管理

```csharp
// 使用临时 RT 并确保释放
RenderTexture rt = RenderTexture.GetTemporary(width, height, 0, format);
try
{
    // 使用 RT...
}
finally
{
    RenderTexture.ReleaseTemporary(rt);
}

// 恢复激活状态
RenderTexture prevActive = RenderTexture.active;
try
{
    RenderTexture.active = rt;
    // 操作...
}
finally
{
    RenderTexture.active = prevActive;
}
```

---

## 九、性能优化建议

### 9.1 大纹理处理

- 对于大尺寸纹理，通道操作和规格化是 CPU 密集型操作
- 考虑使用 Compute Shader 进行 GPU 加速处理

### 9.2 批量导出

- 避免频繁的内存分配/释放
- 可以复用 Texture2D 对象进行多次导出

### 9.3 格式选择

| 场景 | 推荐格式 | 原因 |
|------|----------|------|
| 普通贴图预览 | PNG | 无损、通用性好 |
| 照片类贴图 | JPG | 文件小、有损压缩可接受 |
| 法线贴图 | EXR/TIF 16bit | 保留精度 |
| 深度贴图 | EXR | HDR 支持 |
| 后期处理输出 | TIF 16bit | 专业工作流兼容 |

---

## 十、扩展性

### 10.1 添加新格式

要添加新的导出格式，需要：

1. 在 `ExportFormat` 枚举中添加新格式
2. 在 `GetFileExtension()` 中添加扩展名映射
3. 在 `EncodeTexture()` 中添加编码逻辑
4. 在 `DrawFormatSpecificOptions()` 中添加 UI 选项

### 10.2 自定义处理管线

可以通过修改处理流程顺序或添加新的处理步骤来扩展功能：

```
输入 → [通道操作] → [颜色校正] → [规格化] → [分辨率调整] → 编码 → 输出
         ↑              ↑            ↑            ↑
      可扩展步骤     可扩展步骤    可扩展步骤    可扩展步骤
```

---

## 十一、总结

本工具通过以下核心技术实现了强大的纹理导出功能：

1. **多源输入支持**：统一处理 Texture2D 和 RenderTexture
2. **GPU-CPU 协作**：利用 RenderTexture 进行格式转换和缩放
3. **手动格式编码**：实现 TGA、TIFF 等格式的二进制编码
4. **灵活的处理管线**：模块化的通道操作、规格化、分辨率调整
5. **完善的内存管理**：确保临时资源正确释放

这些技术的组合使得工具能够满足从简单的纹理导出到专业的 HDR 内容处理等多种需求。
