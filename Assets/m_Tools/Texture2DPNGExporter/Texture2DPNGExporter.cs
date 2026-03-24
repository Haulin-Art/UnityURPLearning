using UnityEngine;
using UnityEditor;
using System.IO;

// 导出格式枚举
public enum ExportFormat
{
    PNG,    // PNG格式（8位，LDR）
    EXR     // EXR格式（浮点，HDR）
}

public class Texture2DPNGExporter : EditorWindow
{
    [MenuItem("Tools/Texture2D PNG Exporter")]
    public static void ShowWindow()
    {
        GetWindow<Texture2DPNGExporter>("Texture2D Exporter");
    }

    private Texture2D sourceTexture;
    private string exportPath = "Exports";
    private string fileName = "";
    private bool enableNormalize = false;
    private ExportFormat exportFormat = ExportFormat.PNG;  // 导出格式
    private bool exrCompress = false;  // EXR压缩选项

    private void OnGUI()
    {
        EditorGUILayout.Space(10);

        EditorGUILayout.HelpBox(
            "Texture2D PNG 导出工具\n\n" +
            "使用方法:\n" +
            "1. 选择要导出的 Texture2D\n" +
            "2. 设置导出路径和文件名\n" +
            "3. 点击导出按钮\n\n" +
            "注意: 如果纹理未开启 Read/Write，将自动创建可读副本",
            MessageType.Info
        );

        EditorGUILayout.Space(10);

        sourceTexture = (Texture2D)EditorGUILayout.ObjectField("Source Texture", sourceTexture, typeof(Texture2D), false);

        EditorGUILayout.Space(5);

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
        
        // EXR特有选项
        if (exportFormat == ExportFormat.EXR)
        {
            exrCompress = EditorGUILayout.Toggle("EXR Compress", exrCompress);
            EditorGUILayout.HelpBox("EXR格式支持HDR/浮点纹理\n适合导出法线贴图、深度贴图等高精度纹理", MessageType.Info);
        }

        EditorGUILayout.Space(5);

        enableNormalize = EditorGUILayout.Toggle("Enable Normalize", enableNormalize);
        if (enableNormalize)
        {
            EditorGUILayout.HelpBox("规格化: 值 = 原值 * 0.5 + 0.5\n将 [-1, 1] 范围映射到 [0, 1] 范围", MessageType.Info);
        }

        EditorGUILayout.Space(10);

        EditorGUI.BeginDisabledGroup(sourceTexture == null);
        string buttonText = exportFormat == ExportFormat.PNG ? "Export to PNG" : "Export to EXR";
        if (GUILayout.Button(buttonText, GUILayout.Height(40)))
        {
            ExportTexture();
        }
        EditorGUI.EndDisabledGroup();

        if (sourceTexture != null && string.IsNullOrEmpty(fileName))
        {
            fileName = sourceTexture.name;
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
        string extension = exportFormat == ExportFormat.PNG ? "png" : "exr";
        string filePath = Path.Combine(fullPath, $"{fileName}.{extension}");

        // 根据格式获取合适的纹理
        Texture2D exportTexture = exportFormat == ExportFormat.EXR 
            ? GetReadableTextureHDR(sourceTexture) 
            : GetReadableTexture(sourceTexture);

        if (enableNormalize)
        {
            Texture2D normalizedTexture = NormalizeTexture(exportTexture, exportFormat == ExportFormat.EXR);
            if (exportTexture != sourceTexture)
            {
                DestroyImmediate(exportTexture);
            }
            exportTexture = normalizedTexture;
        }

        // 根据格式编码
        byte[] textureData = null;
        if (exportFormat == ExportFormat.PNG)
        {
            textureData = exportTexture.EncodeToPNG();
        }
        else
        {
            // EXR格式支持压缩选项
            Texture2D.EXRFlags exrFlags = exrCompress ? Texture2D.EXRFlags.CompressZIP : Texture2D.EXRFlags.None;
            textureData = exportTexture.EncodeToEXR(exrFlags);
        }
        
        if (textureData == null)
        {
            Debug.LogError($"编码{exportFormat}失败! 纹理格式可能不支持。");
            return;
        }

        File.WriteAllBytes(filePath, textureData);

        if (exportTexture != sourceTexture)
        {
            DestroyImmediate(exportTexture);
        }

        Debug.Log($"{exportFormat}已导出到: {filePath}");
        
        AssetDatabase.Refresh();

        EditorUtility.RevealInFinder(filePath);
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
        
        // 创建浮点格式的纹理用于HDR数据
        Texture2D readableTexture = new Texture2D(source.width, source.height, TextureFormat.RGBAFloat, false);
        
        if (!string.IsNullOrEmpty(assetPath))
        {
            TextureImporter importer = AssetImporter.GetAtPath(assetPath) as TextureImporter;
            if (importer != null && !importer.isReadable)
            {
                // 使用HDR RenderTexture来保留浮点精度
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

        // 如果源纹理可读，直接复制像素数据
        if (source.isReadable)
        {
            Color[] pixels = source.GetPixels();
            readableTexture.SetPixels(pixels);
            readableTexture.Apply();
            return readableTexture;
        }

        // 默认情况：通过RenderTexture复制
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
        // 根据是否HDR选择合适的纹理格式
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
