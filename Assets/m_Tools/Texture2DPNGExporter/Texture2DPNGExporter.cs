using UnityEngine;
using UnityEditor;
using System.IO;

// 导出格式枚举
public enum ExportFormat
{
    PNG,    // PNG格式（8位，LDR，无损压缩）
    JPG,    // JPG格式（8位，LDR，有损压缩）
    TGA,    // TGA格式（8位，LDR，无压缩）
    WebP,   // WebP格式（8位，LDR，现代格式）
    EXR,    // EXR格式（浮点，HDR）
    TIF     // TIF格式（8位/16位，LDR/HDR，无压缩）
}

// 通道操作模式
public enum ChannelMode
{
    All,        // 保留所有通道（默认）
    Single,     // 单通道导出
    Remap       // 通道重组
}

// 单通道选择
public enum SingleChannel
{
    R,  // 红色通道
    G,  // 绿色通道
    B,  // 蓝色通道
    A   // Alpha通道
}

// 通道源选择（用于重组）
public enum ChannelSource
{
    R,      // 取自R通道
    G,      // 取自G通道
    B,      // 取自B通道
    A,      // 取自A通道
    One,    // 填充1
    Zero    // 填充0
}

// 分辨率调整模式
public enum ResolutionMode
{
    Original,       // 原始分辨率
    CustomSize,     // 自定义尺寸
    Scale           // 缩放比例
}

// 缩放采样模式
public enum ScaleFilterMode
{
    Point,      // 点采样（像素风格）
    Bilinear,   // 双线性（平滑）
    Trilinear   // 三线性（更平滑）
}

// TIF位深度
public enum TifBitDepth
{
    Bit8,   // 8位每通道
    Bit16   // 16位每通道（更高精度）
}

public class Texture2DPNGExporter : EditorWindow
{
    [MenuItem("Tools/Texture2D PNG Exporter")]
    public static void ShowWindow()
    {
        GetWindow<Texture2DPNGExporter>("Texture2D Exporter");
    }

    // 基础设置 - 支持Texture基类（包括Texture2D和RenderTexture）
    private Texture sourceTexture;
    private string exportPath = "Exports";
    private string fileName = "";
    private bool enableNormalize = false;
    private ExportFormat exportFormat = ExportFormat.PNG;

    // 格式特有设置
    private int jpgQuality = 80;            // JPG质量（1-100）
    private bool exrCompress = false;       // EXR压缩选项
    private TifBitDepth tifBitDepth = TifBitDepth.Bit8;  // TIF位深度

    // 通道操作设置
    private ChannelMode channelMode = ChannelMode.All;
    private SingleChannel singleChannel = SingleChannel.R;
    private ChannelSource remapR = ChannelSource.R;
    private ChannelSource remapG = ChannelSource.G;
    private ChannelSource remapB = ChannelSource.B;
    private ChannelSource remapA = ChannelSource.A;

    // 分辨率设置
    private ResolutionMode resolutionMode = ResolutionMode.Original;
    private int customWidth = 512;
    private int customHeight = 512;
    private float scaleFactor = 1.0f;
    private ScaleFilterMode scaleFilter = ScaleFilterMode.Bilinear;

    // 显示原始尺寸信息
    private Vector2Int originalSize;

    private void OnGUI()
    {
        EditorGUILayout.Space(10);

        EditorGUILayout.HelpBox(
            "Texture 导出工具\n\n" +
            "支持输入类型:\n" +
            "- Texture2D (普通纹理)\n" +
            "- RenderTexture (渲染纹理)\n\n" +
            "使用方法:\n" +
            "1. 选择要导出的纹理\n" +
            "2. 设置导出路径和文件名\n" +
            "3. 配置通道操作和分辨率\n" +
            "4. 点击导出按钮",
            MessageType.Info
        );

        EditorGUILayout.Space(10);

        // 源纹理选择 - 支持Texture基类
        sourceTexture = (Texture)EditorGUILayout.ObjectField("Source Texture", sourceTexture, typeof(Texture), false);

        // 显示纹理类型信息
        if (sourceTexture != null)
        {
            originalSize = new Vector2Int(sourceTexture.width, sourceTexture.height);
            
            string textureType = sourceTexture is RenderTexture ? "RenderTexture" : "Texture2D";
            EditorGUILayout.LabelField($"Type: {textureType}");
            
            // RenderTexture格式信息
            if (sourceTexture is RenderTexture rt)
            {
                EditorGUILayout.LabelField($"RT Format: {rt.format}");
            }
        }

        EditorGUILayout.Space(5);

        // ==================== 导出设置 ====================
        EditorGUILayout.LabelField("Export Settings", EditorStyles.boldLabel);
        
        EditorGUILayout.BeginHorizontal();
        EditorGUILayout.TextField("Export Path", exportPath);
        if (GUILayout.Button("Browse", GUILayout.Width(60)))
        {
            string selectedPath = EditorUtility.OpenFolderPanel("Select Export Folder", Application.dataPath, "");
            if (!string.IsNullOrEmpty(selectedPath))
            {
                if (selectedPath.StartsWith(Application.dataPath))
                {
                    exportPath = "Assets" + selectedPath.Substring(Application.dataPath.Length);
                }
                else
                {
                    exportPath = selectedPath;
                }
            }
        }
        EditorGUILayout.EndHorizontal();

        fileName = EditorGUILayout.TextField("File Name", fileName);

        EditorGUILayout.Space(5);

        // 导出格式选择
        exportFormat = (ExportFormat)EditorGUILayout.EnumPopup("Export Format", exportFormat);
        
        // 格式特有选项
        DrawFormatSpecificOptions();

        EditorGUILayout.Space(5);

        enableNormalize = EditorGUILayout.Toggle("Enable Normalize", enableNormalize);
        if (enableNormalize)
        {
            EditorGUILayout.HelpBox("规格化: 值 = 原值 * 0.5 + 0.5\n将 [-1, 1] 范围映射到 [0, 1] 范围", MessageType.Info);
        }

        EditorGUILayout.Space(10);

        // ==================== 通道操作 ====================
        EditorGUILayout.LabelField("Channel Operations", EditorStyles.boldLabel);
        
        channelMode = (ChannelMode)EditorGUILayout.EnumPopup("Channel Mode", channelMode);

        if (channelMode == ChannelMode.Single)
        {
            // 单通道导出
            singleChannel = (SingleChannel)EditorGUILayout.EnumPopup("Export Channel", singleChannel);
            EditorGUILayout.HelpBox("将选定通道输出到RGB，Alpha设为1", MessageType.Info);
        }
        else if (channelMode == ChannelMode.Remap)
        {
            // 通道重组
            EditorGUILayout.LabelField("Channel Remapping:", EditorStyles.miniLabel);
            remapR = (ChannelSource)EditorGUILayout.EnumPopup("  R →", remapR);
            remapG = (ChannelSource)EditorGUILayout.EnumPopup("  G →", remapG);
            remapB = (ChannelSource)EditorGUILayout.EnumPopup("  B →", remapB);
            remapA = (ChannelSource)EditorGUILayout.EnumPopup("  A →", remapA);
        }

        EditorGUILayout.Space(10);

        // ==================== 分辨率设置 ====================
        EditorGUILayout.LabelField("Resolution Settings", EditorStyles.boldLabel);

        // 显示原始尺寸
        if (sourceTexture != null)
        {
            EditorGUILayout.LabelField($"Original Size: {originalSize.x} x {originalSize.y}");
        }

        resolutionMode = (ResolutionMode)EditorGUILayout.EnumPopup("Resolution Mode", resolutionMode);

        if (resolutionMode == ResolutionMode.CustomSize)
        {
            // 自定义尺寸
            customWidth = EditorGUILayout.IntField("Width", customWidth);
            customHeight = EditorGUILayout.IntField("Height", customHeight);
            // 约束尺寸范围
            customWidth = Mathf.Max(1, customWidth);
            customHeight = Mathf.Max(1, customHeight);
        }
        else if (resolutionMode == ResolutionMode.Scale)
        {
            // 缩放比例
            scaleFactor = EditorGUILayout.Slider("Scale Factor", scaleFactor, 0.1f, 4.0f);
            if (sourceTexture != null)
            {
                int newW = Mathf.RoundToInt(originalSize.x * scaleFactor);
                int newH = Mathf.RoundToInt(originalSize.y * scaleFactor);
                EditorGUILayout.LabelField($"Result Size: {newW} x {newH}");
            }
        }

        // 缩放时选择采样模式
        if (resolutionMode != ResolutionMode.Original)
        {
            scaleFilter = (ScaleFilterMode)EditorGUILayout.EnumPopup("Filter Mode", scaleFilter);
            if (scaleFilter == ScaleFilterMode.Point)
            {
                EditorGUILayout.HelpBox("Point: 保持锐利边缘，适合像素艺术", MessageType.Info);
            }
            else
            {
                EditorGUILayout.HelpBox("Bilinear/Trilinear: 平滑缩放，适合普通贴图", MessageType.Info);
            }
        }

        EditorGUILayout.Space(10);

        // ==================== 导出按钮 ====================
        EditorGUI.BeginDisabledGroup(sourceTexture == null);
        string buttonText = $"Export to {exportFormat}";
        if (GUILayout.Button(buttonText, GUILayout.Height(40)))
        {
            ExportTexture();
        }
        EditorGUI.EndDisabledGroup();

        // 自动填充文件名
        if (sourceTexture != null && string.IsNullOrEmpty(fileName))
        {
            fileName = sourceTexture.name;
        }
    }

    // 绘制格式特有选项
    private void DrawFormatSpecificOptions()
    {
        switch (exportFormat)
        {
            case ExportFormat.JPG:
                jpgQuality = EditorGUILayout.IntSlider("Quality", jpgQuality, 1, 100);
                EditorGUILayout.HelpBox("JPG: 有损压缩格式\n适合照片类贴图，不支持Alpha通道", MessageType.Info);
                break;

            case ExportFormat.TGA:
                EditorGUILayout.HelpBox("TGA: 无压缩格式\n支持Alpha通道，兼容性好", MessageType.Info);
                break;

            case ExportFormat.WebP:
                EditorGUILayout.HelpBox("WebP: 现代格式\n高压缩比，支持Alpha通道\n需要Unity 2021.2+", MessageType.Info);
                break;

            case ExportFormat.EXR:
                exrCompress = EditorGUILayout.Toggle("EXR Compress", exrCompress);
                EditorGUILayout.HelpBox("EXR: HDR浮点格式\n支持高动态范围，适合法线贴图、深度贴图", MessageType.Info);
                break;

            case ExportFormat.TIF:
                tifBitDepth = (TifBitDepth)EditorGUILayout.EnumPopup("Bit Depth", tifBitDepth);
                EditorGUILayout.HelpBox("TIF: 专业格式\n支持8/16位精度，无压缩\n适合后期处理和专业工作流", MessageType.Info);
                break;

            case ExportFormat.PNG:
            default:
                EditorGUILayout.HelpBox("PNG: 无损压缩格式\n支持Alpha通道，通用性最强", MessageType.Info);
                break;
        }
    }

    private void ExportTexture()
    {
        if (sourceTexture == null)
        {
            Debug.LogError("请选择要导出的纹理!");
            return;
        }

        string fullPath = Path.IsPathRooted(exportPath) 
            ? exportPath 
            : Path.Combine(Application.dataPath, "..", exportPath);

        if (!Directory.Exists(fullPath))
        {
            Directory.CreateDirectory(fullPath);
        }

        // 根据格式确定文件扩展名
        string extension = GetFileExtension(exportFormat);
        string filePath = Path.Combine(fullPath, $"{fileName}.{extension}");

        // 判断是否需要HDR格式
        bool needHDR = ShouldUseHDR();

        // 根据输入类型获取可读纹理
        Texture2D exportTexture = GetReadableTextureFromSource(needHDR);

        if (exportTexture == null)
        {
            Debug.LogError("无法读取纹理数据!");
            return;
        }

        // 应用通道操作
        if (channelMode != ChannelMode.All)
        {
            Texture2D channelProcessed = ProcessChannels(exportTexture, needHDR);
            DestroyImmediate(exportTexture);
            exportTexture = channelProcessed;
        }

        // 应用规格化
        if (enableNormalize)
        {
            Texture2D normalizedTexture = NormalizeTexture(exportTexture, needHDR);
            DestroyImmediate(exportTexture);
            exportTexture = normalizedTexture;
        }

        // 应用分辨率调整
        if (resolutionMode != ResolutionMode.Original)
        {
            Texture2D resizedTexture = ResizeTexture(exportTexture, needHDR);
            DestroyImmediate(exportTexture);
            exportTexture = resizedTexture;
        }

        // 根据格式编码
        byte[] textureData = EncodeTexture(exportTexture);
        
        if (textureData == null)
        {
            Debug.LogError($"编码{exportFormat}失败! 纹理格式可能不支持。");
            DestroyImmediate(exportTexture);
            return;
        }

        File.WriteAllBytes(filePath, textureData);

        DestroyImmediate(exportTexture);

        Debug.Log($"{exportFormat}已导出到: {filePath}");
        
        AssetDatabase.Refresh();

        EditorUtility.RevealInFinder(filePath);
    }

    // 判断是否应该使用HDR格式
    private bool ShouldUseHDR()
    {
        // 如果导出格式是EXR或TIF 16位，使用HDR
        if (exportFormat == ExportFormat.EXR)
            return true;
        if (exportFormat == ExportFormat.TIF && tifBitDepth == TifBitDepth.Bit16)
            return true;

        // 如果输入是HDR格式的RenderTexture，建议使用HDR
        if (sourceTexture is RenderTexture rt)
        {
            if (IsHDRFormat(rt.format))
                return true;
        }

        return false;
    }

    // 判断RenderTexture格式是否为HDR
    private bool IsHDRFormat(RenderTextureFormat format)
    {
        return format == RenderTextureFormat.ARGBFloat ||
               format == RenderTextureFormat.ARGBHalf ||
               format == RenderTextureFormat.RFloat ||
               format == RenderTextureFormat.RGFloat ||
               format == RenderTextureFormat.RHalf ||
               format == RenderTextureFormat.RGHalf ||
               format == RenderTextureFormat.RGB111110Float;
    }

    // 从源纹理获取可读的Texture2D
    private Texture2D GetReadableTextureFromSource(bool needHDR)
    {
        // RenderTexture输入
        if (sourceTexture is RenderTexture rt)
        {
            return ReadFromRenderTexture(rt, needHDR);
        }
        
        // Texture2D输入
        if (sourceTexture is Texture2D tex2D)
        {
            return needHDR ? GetReadableTextureHDR(tex2D) : GetReadableTexture(tex2D);
        }

        // 其他Texture类型（如Texture2DArray等），通过RenderTexture中转
        return ReadFromGenericTexture(sourceTexture, needHDR);
    }

    // 从RenderTexture读取像素数据
    private Texture2D ReadFromRenderTexture(RenderTexture rt, bool needHDR)
    {
        int width = rt.width;
        int height = rt.height;

        // 根据是否需要HDR选择纹理格式
        TextureFormat texFormat = needHDR ? TextureFormat.RGBAFloat : TextureFormat.RGBA32;
        
        Texture2D result = new Texture2D(width, height, texFormat, false);

        // 保存当前激活的RenderTexture
        RenderTexture prevActive = RenderTexture.active;

        try
        {
            // 设置目标RenderTexture为激活状态
            RenderTexture.active = rt;
            
            // 读取像素数据
            result.ReadPixels(new Rect(0, 0, width, height), 0, 0);
            result.Apply();
        }
        finally
        {
            // 恢复之前的激活状态
            RenderTexture.active = prevActive;
        }

        return result;
    }

    // 从通用Texture读取（通过临时RenderTexture中转）
    private Texture2D ReadFromGenericTexture(Texture source, bool needHDR)
    {
        int width = source.width;
        int height = source.height;

        TextureFormat texFormat = needHDR ? TextureFormat.RGBAFloat : TextureFormat.RGBA32;
        RenderTextureFormat rtFormat = needHDR ? RenderTextureFormat.ARGBFloat : RenderTextureFormat.ARGB32;

        Texture2D result = new Texture2D(width, height, texFormat, false);

        // 创建临时RenderTexture
        RenderTexture tempRT = RenderTexture.GetTemporary(width, height, 0, rtFormat);
        RenderTexture prevActive = RenderTexture.active;

        try
        {
            Graphics.Blit(source, tempRT);
            RenderTexture.active = tempRT;
            result.ReadPixels(new Rect(0, 0, width, height), 0, 0);
            result.Apply();
        }
        finally
        {
            RenderTexture.active = prevActive;
            RenderTexture.ReleaseTemporary(tempRT);
        }

        return result;
    }

    // 获取文件扩展名
    private string GetFileExtension(ExportFormat format)
    {
        switch (format)
        {
            case ExportFormat.PNG: return "png";
            case ExportFormat.JPG: return "jpg";
            case ExportFormat.TGA: return "tga";
            case ExportFormat.WebP: return "webp";
            case ExportFormat.EXR: return "exr";
            case ExportFormat.TIF: return "tif";
            default: return "png";
        }
    }

    // 根据格式编码纹理
    private byte[] EncodeTexture(Texture2D texture)
    {
        switch (exportFormat)
        {
            case ExportFormat.PNG:
                return texture.EncodeToPNG();

            case ExportFormat.JPG:
                return texture.EncodeToJPG(jpgQuality);

            case ExportFormat.TGA:
                return EncodeToTGA(texture);

            case ExportFormat.WebP:
                return EncodeToWebP(texture);

            case ExportFormat.EXR:
                Texture2D.EXRFlags exrFlags = exrCompress ? Texture2D.EXRFlags.CompressZIP : Texture2D.EXRFlags.None;
                return texture.EncodeToEXR(exrFlags);

            case ExportFormat.TIF:
                return EncodeToTIF(texture, tifBitDepth == TifBitDepth.Bit16);

            default:
                return texture.EncodeToPNG();
        }
    }

    // TGA编码
    private byte[] EncodeToTGA(Texture2D texture)
    {
        int width = texture.width;
        int height = texture.height;
        Color[] pixels = texture.GetPixels();

        // TGA文件头（18字节）
        byte[] header = new byte[18];
        header[2] = 2;  // 图像类型：未压缩真彩色
        header[12] = (byte)(width & 0xFF);
        header[13] = (byte)((width >> 8) & 0xFF);
        header[14] = (byte)(height & 0xFF);
        header[15] = (byte)((height >> 8) & 0xFF);
        header[16] = 32;  // 每像素位数（32位 = RGBA）
        header[17] = 0x28;  // 图像描述符（从上到下）

        // 像素数据（BGRA顺序）
        byte[] pixelData = new byte[width * height * 4];
        for (int i = 0; i < pixels.Length; i++)
        {
            int idx = i * 4;
            pixelData[idx + 0] = (byte)(pixels[i].b * 255);  // B
            pixelData[idx + 1] = (byte)(pixels[i].g * 255);  // G
            pixelData[idx + 2] = (byte)(pixels[i].r * 255);  // R
            pixelData[idx + 3] = (byte)(pixels[i].a * 255);  // A
        }

        // 合并头部和像素数据
        byte[] result = new byte[header.Length + pixelData.Length];
        System.Buffer.BlockCopy(header, 0, result, 0, header.Length);
        System.Buffer.BlockCopy(pixelData, 0, result, header.Length, pixelData.Length);

        return result;
    }

    // WebP编码
    private byte[] EncodeToWebP(Texture2D texture)
    {
        // Unity 2021.2+ 支持原生WebP编码
        var method = typeof(Texture2D).GetMethod("EncodeToWebP", System.Type.EmptyTypes);
        if (method != null)
        {
            return method.Invoke(texture, null) as byte[];
        }

        // 如果不支持WebP，回退到PNG并警告
        Debug.LogWarning("当前Unity版本不支持WebP编码，已回退到PNG格式。需要Unity 2021.2+");
        exportFormat = ExportFormat.PNG;
        return texture.EncodeToPNG();
    }

    // TIF编码（TIFF格式）
    private byte[] EncodeToTIF(Texture2D texture, bool use16Bit)
    {
        int width = texture.width;
        int height = texture.height;
        Color[] pixels = texture.GetPixels();

        // 每通道位数
        int bitsPerSample = use16Bit ? 16 : 8;
        int bytesPerSample = use16Bit ? 2 : 1;
        int samplesPerPixel = 4;  // RGBA
        int bytesPerPixel = bytesPerSample * samplesPerPixel;

        // 计算像素数据大小
        int pixelDataSize = width * height * bytesPerPixel;

        // TIFF文件结构：
        // - Header (8字节)
        // - IFD (Image File Directory)
        // - 像素数据

        using (MemoryStream ms = new MemoryStream())
        using (BinaryWriter writer = new BinaryWriter(ms))
        {
            // ===== TIFF Header =====
            writer.Write((byte)'I');  // 字节顺序：Little-endian (Intel)
            writer.Write((byte)'I');
            writer.Write((ushort)42);  // TIFF标识
            writer.Write((uint)8);      // 第一个IFD的偏移量（紧跟header）

            // ===== IFD (Image File Directory) =====
            ushort numEntries = 12;  // IFD条目数量
            writer.Write(numEntries);

            // 计算各数据的偏移量
            uint ifdEndOffset = 8 + 2 + (uint)(numEntries * 12) + 4;  // header + numEntries + entries + nextIFD
            uint stripOffset = ifdEndOffset;  // 像素数据起始位置

            // 计算额外数据的偏移量
            uint bitsPerSampleOffset = stripOffset + (uint)pixelDataSize;
            uint extraDataOffset = bitsPerSampleOffset + 8;  // BitsPerSample数据（4个ushort = 8字节）

            // IFD Entry格式：Tag(2) + Type(2) + Count(4) + Value/Offset(4) = 12字节

            // ImageWidth (Tag 256)
            WriteIFDEntry(writer, 256, 3, 1, (uint)width);  // Type 3 = SHORT

            // ImageLength (Tag 257)
            WriteIFDEntry(writer, 257, 3, 1, (uint)height);

            // BitsPerSample (Tag 258) - 需要额外存储4个值
            WriteIFDEntry(writer, 258, 3, 4, bitsPerSampleOffset);

            // Compression (Tag 259) - 1 = 无压缩
            WriteIFDEntry(writer, 259, 3, 1, 1);

            // PhotometricInterpretation (Tag 262) - 2 = RGB
            WriteIFDEntry(writer, 262, 3, 1, 2);

            // StripOffsets (Tag 273) - 像素数据起始位置
            WriteIFDEntry(writer, 273, 4, 1, stripOffset);  // Type 4 = LONG

            // SamplesPerPixel (Tag 277)
            WriteIFDEntry(writer, 277, 3, 1, (uint)samplesPerPixel);

            // RowsPerStrip (Tag 278) - 每条带行数（整个图像为一条带）
            WriteIFDEntry(writer, 278, 3, 1, (uint)height);

            // StripByteCounts (Tag 279) - 像素数据字节数
            WriteIFDEntry(writer, 279, 4, 1, (uint)pixelDataSize);

            // XResolution (Tag 282) - 需要额外存储
            WriteIFDEntry(writer, 282, 5, 1, extraDataOffset);  // Type 5 = RATIONAL

            // YResolution (Tag 283)
            WriteIFDEntry(writer, 283, 5, 1, extraDataOffset + 8);

            // ResolutionUnit (Tag 296) - 2 = 英寸
            WriteIFDEntry(writer, 296, 3, 1, 2);

            // 下一个IFD偏移量（0表示没有更多IFD）
            writer.Write((uint)0);

            // ===== 像素数据 =====
            // TIFF像素顺序：从上到下，从左到右，RGBA
            if (use16Bit)
            {
                for (int i = 0; i < pixels.Length; i++)
                {
                    // 16位每通道
                    writer.Write((ushort)(pixels[i].r * 65535));
                    writer.Write((ushort)(pixels[i].g * 65535));
                    writer.Write((ushort)(pixels[i].b * 65535));
                    writer.Write((ushort)(pixels[i].a * 65535));
                }
            }
            else
            {
                for (int i = 0; i < pixels.Length; i++)
                {
                    // 8位每通道
                    writer.Write((byte)(pixels[i].r * 255));
                    writer.Write((byte)(pixels[i].g * 255));
                    writer.Write((byte)(pixels[i].b * 255));
                    writer.Write((byte)(pixels[i].a * 255));
                }
            }

            // ===== BitsPerSample数据 =====
            for (int i = 0; i < 4; i++)
            {
                writer.Write((ushort)bitsPerSample);
            }

            // ===== Resolution数据 =====
            // XResolution: 72/1
            writer.Write((uint)72);
            writer.Write((uint)1);
            // YResolution: 72/1
            writer.Write((uint)72);
            writer.Write((uint)1);

            return ms.ToArray();
        }
    }

    // 写入IFD条目
    private void WriteIFDEntry(BinaryWriter writer, ushort tag, ushort type, uint count, uint valueOrOffset)
    {
        writer.Write(tag);
        writer.Write(type);
        writer.Write(count);
        writer.Write(valueOrOffset);
    }

    // 处理通道操作
    private Texture2D ProcessChannels(Texture2D source, bool isHDR)
    {
        TextureFormat format = isHDR ? TextureFormat.RGBAFloat : TextureFormat.RGBA32;
        Texture2D result = new Texture2D(source.width, source.height, format, false);
        Color[] pixels = source.GetPixels();

        if (channelMode == ChannelMode.Single)
        {
            // 单通道导出：将选定通道输出到RGB
            for (int i = 0; i < pixels.Length; i++)
            {
                float channelValue = GetChannelValue(pixels[i], singleChannel);
                pixels[i] = new Color(channelValue, channelValue, channelValue, 1f);
            }
        }
        else if (channelMode == ChannelMode.Remap)
        {
            // 通道重组
            for (int i = 0; i < pixels.Length; i++)
            {
                float r = GetChannelSourceValue(pixels[i], remapR);
                float g = GetChannelSourceValue(pixels[i], remapG);
                float b = GetChannelSourceValue(pixels[i], remapB);
                float a = GetChannelSourceValue(pixels[i], remapA);
                pixels[i] = new Color(r, g, b, a);
            }
        }

        result.SetPixels(pixels);
        result.Apply();
        return result;
    }

    // 获取单个通道的值
    private float GetChannelValue(Color c, SingleChannel channel)
    {
        switch (channel)
        {
            case SingleChannel.R: return c.r;
            case SingleChannel.G: return c.g;
            case SingleChannel.B: return c.b;
            case SingleChannel.A: return c.a;
            default: return c.r;
        }
    }

    // 获取通道源的值
    private float GetChannelSourceValue(Color c, ChannelSource source)
    {
        switch (source)
        {
            case ChannelSource.R: return c.r;
            case ChannelSource.G: return c.g;
            case ChannelSource.B: return c.b;
            case ChannelSource.A: return c.a;
            case ChannelSource.One: return 1f;
            case ChannelSource.Zero: return 0f;
            default: return c.r;
        }
    }

    // 分辨率调整
    private Texture2D ResizeTexture(Texture2D source, bool isHDR)
    {
        int newWidth, newHeight;

        if (resolutionMode == ResolutionMode.CustomSize)
        {
            newWidth = customWidth;
            newHeight = customHeight;
        }
        else if (resolutionMode == ResolutionMode.Scale)
        {
            newWidth = Mathf.RoundToInt(source.width * scaleFactor);
            newHeight = Mathf.RoundToInt(source.height * scaleFactor);
        }
        else
        {
            return source;
        }

        // 确保尺寸至少为1
        newWidth = Mathf.Max(1, newWidth);
        newHeight = Mathf.Max(1, newHeight);

        // 使用RenderTexture进行缩放
        RenderTextureFormat rtFormat = isHDR ? RenderTextureFormat.ARGBFloat : RenderTextureFormat.ARGB32;
        TextureFormat texFormat = isHDR ? TextureFormat.RGBAFloat : TextureFormat.RGBA32;

        RenderTexture rt = RenderTexture.GetTemporary(newWidth, newHeight, 0, rtFormat);
        
        // 设置采样模式
        FilterMode filterMode = scaleFilter == ScaleFilterMode.Point ? FilterMode.Point : FilterMode.Bilinear;
        source.filterMode = filterMode;

        Graphics.Blit(source, rt);
        
        Texture2D result = new Texture2D(newWidth, newHeight, texFormat, false);
        RenderTexture.active = rt;
        result.ReadPixels(new Rect(0, 0, newWidth, newHeight), 0, 0);
        result.Apply();
        RenderTexture.active = null;
        RenderTexture.ReleaseTemporary(rt);

        return result;
    }

    private Texture2D GetReadableTexture(Texture2D source)
    {
        string assetPath = AssetDatabase.GetAssetPath(source);
        
        if (!string.IsNullOrEmpty(assetPath))
        {
            TextureImporter importer = AssetImporter.GetAtPath(assetPath) as TextureImporter;
            if (importer != null && !importer.isReadable)
            {
                Texture2D readableTexture = new Texture2D(source.width, source.height, TextureFormat.RGBA32, false);
                RenderTexture rt = RenderTexture.GetTemporary(source.width, source.height, 0, RenderTextureFormat.ARGB32);
                Graphics.Blit(source, rt);
                RenderTexture.active = rt;
                readableTexture.ReadPixels(new Rect(0, 0, source.width, source.height), 0, 0);
                readableTexture.Apply();
                RenderTexture.active = null;
                RenderTexture.ReleaseTemporary(rt);
                return readableTexture;
            }
        }

        return source;
    }

    // 获取可读的HDR纹理（用于EXR导出）
    private Texture2D GetReadableTextureHDR(Texture2D source)
    {
        string assetPath = AssetDatabase.GetAssetPath(source);
        
        Texture2D readableTexture = new Texture2D(source.width, source.height, TextureFormat.RGBAFloat, false);
        
        if (!string.IsNullOrEmpty(assetPath))
        {
            TextureImporter importer = AssetImporter.GetAtPath(assetPath) as TextureImporter;
            if (importer != null && !importer.isReadable)
            {
                RenderTexture rt = RenderTexture.GetTemporary(source.width, source.height, 0, RenderTextureFormat.ARGBFloat);
                Graphics.Blit(source, rt);
                RenderTexture.active = rt;
                readableTexture.ReadPixels(new Rect(0, 0, source.width, source.height), 0, 0);
                readableTexture.Apply();
                RenderTexture.active = null;
                RenderTexture.ReleaseTemporary(rt);
                return readableTexture;
            }
        }

        if (source.isReadable)
        {
            Color[] pixels = source.GetPixels();
            readableTexture.SetPixels(pixels);
            readableTexture.Apply();
            return readableTexture;
        }

        RenderTexture rtDefault = RenderTexture.GetTemporary(source.width, source.height, 0, RenderTextureFormat.ARGBFloat);
        Graphics.Blit(source, rtDefault);
        RenderTexture.active = rtDefault;
        readableTexture.ReadPixels(new Rect(0, 0, source.width, source.height), 0, 0);
        readableTexture.Apply();
        RenderTexture.active = null;
        RenderTexture.ReleaseTemporary(rtDefault);
        
        return readableTexture;
    }

    private Texture2D NormalizeTexture(Texture2D source, bool isHDR = false)
    {
        TextureFormat format = isHDR ? TextureFormat.RGBAFloat : TextureFormat.RGBA32;
        Texture2D normalizedTexture = new Texture2D(source.width, source.height, format, false);
        Color[] pixels = source.GetPixels();
        
        for (int i = 0; i < pixels.Length; i++)
        {
            pixels[i].r = pixels[i].r * 0.5f + 0.5f;
            pixels[i].g = pixels[i].g * 0.5f + 0.5f;
            pixels[i].b = pixels[i].b * 0.5f + 0.5f;
        }
        
        normalizedTexture.SetPixels(pixels);
        normalizedTexture.Apply();
        
        return normalizedTexture;
    }
}
