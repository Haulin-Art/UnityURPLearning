using UnityEngine;
using UnityEditor;
using System.IO;
using System.Collections.Generic;

public class SDFAtlasToVolumeTexture : EditorWindow
{
    private Texture2D inputAtlas;
    private int gridRows = 16;
    private int gridColumns = 16;
    private string outputTextureName = "SDF_Volume";
    private FilterMode filterMode = FilterMode.Bilinear;
    private TextureWrapMode wrapMode = TextureWrapMode.Clamp;
    
    // 新添加的：输出分辨率控制
    private enum ResolutionMode
    {
        UseOriginal,    // 使用原始切片尺寸
        Custom          // 自定义分辨率
    }
    
    private ResolutionMode resolutionMode = ResolutionMode.UseOriginal;
    private int customWidth = 256;
    private int customHeight = 256;
    
    // 新添加：切片数量控制
    private int targetSliceCount = 256;
    private bool enableSliceControl = false;
    
    [MenuItem("Tools/SDF Atlas to Volume Texture")]
    public static void ShowWindow()
    {
        GetWindow<SDFAtlasToVolumeTexture>("SDF Atlas to Volume");
    }

    private void OnGUI()
    {
        GUILayout.Label("SDF图集转体积纹理工具", EditorStyles.boldLabel);
        EditorGUILayout.HelpBox("此工具将16×16的SDF图集转换为体积纹理。\n图集从左到右、从上到下排列，每个切片包含完整的UV。", MessageType.Info);
        EditorGUILayout.Space();
        
        // 输入设置
        EditorGUILayout.LabelField("输入设置", EditorStyles.boldLabel);
        inputAtlas = (Texture2D)EditorGUILayout.ObjectField("SDF图集", inputAtlas, typeof(Texture2D), false);
        
        EditorGUILayout.BeginHorizontal();
        gridColumns = EditorGUILayout.IntField("列数", gridColumns);
        gridRows = EditorGUILayout.IntField("行数", gridRows);
        EditorGUILayout.EndHorizontal();
        
        // 计算原始切片尺寸和总数
        int originalSliceWidth = 0;
        int originalSliceHeight = 0;
        int totalOriginalSlices = 0;
        if (inputAtlas != null)
        {
            originalSliceWidth = inputAtlas.width / gridColumns;
            originalSliceHeight = inputAtlas.height / gridRows;
            totalOriginalSlices = gridRows * gridColumns;
        }
        
        // 输出设置
        EditorGUILayout.LabelField("输出设置", EditorStyles.boldLabel);
        outputTextureName = EditorGUILayout.TextField("纹理名称", outputTextureName);
        
        // 新添加：切片数量控制
        EditorGUILayout.Space();
        EditorGUILayout.LabelField("切片数量控制", EditorStyles.boldLabel);
        enableSliceControl = EditorGUILayout.ToggleLeft("控制最终切片数量", enableSliceControl);
        
        if (enableSliceControl)
        {
            EditorGUI.indentLevel++;
            targetSliceCount = EditorGUILayout.IntSlider("目标切片数", targetSliceCount, 1, totalOriginalSlices);
            
            // 计算采样间隔
            float sampleInterval = (float)totalOriginalSlices / targetSliceCount;
            EditorGUILayout.LabelField($"采样间隔: {sampleInterval:F2} (每{totalOriginalSlices}张中取{targetSliceCount}张)");
            
            // 给出建议的切片数量（2的幂次方）
            string recommendedSizes = "";
            int[] powerOfTwo = { 16, 32, 64, 128, 256, 512 };
            foreach (int size in powerOfTwo)
            {
                if (size <= totalOriginalSlices)
                    recommendedSizes += size + " ";
            }
            EditorGUILayout.HelpBox($"建议的切片数量（2的幂次）: {recommendedSizes}", MessageType.Info);
            EditorGUI.indentLevel--;
        }
        
        // 分辨率控制
        EditorGUILayout.Space();
        EditorGUILayout.LabelField("输出分辨率控制", EditorStyles.boldLabel);
        
        resolutionMode = (ResolutionMode)EditorGUILayout.EnumPopup("分辨率模式", resolutionMode);
        
        if (resolutionMode == ResolutionMode.UseOriginal)
        {
            EditorGUILayout.HelpBox($"将使用原始切片尺寸: {originalSliceWidth}×{originalSliceHeight}", MessageType.Info);
        }
        else
        {
            EditorGUILayout.BeginHorizontal();
            customWidth = EditorGUILayout.IntField("宽度", customWidth);
            customHeight = EditorGUILayout.IntField("高度", customHeight);
            EditorGUILayout.EndHorizontal();
            
            if (originalSliceWidth > 0 && originalSliceHeight > 0)
            {
                float scaleX = (float)customWidth / originalSliceWidth;
                float scaleY = (float)customHeight / originalSliceHeight;
                EditorGUILayout.LabelField($"缩放比例: {scaleX:F2}×{scaleY:F2}", EditorStyles.miniLabel);
                
                if (customWidth != originalSliceWidth || customHeight != originalSliceHeight)
                {
                    string qualityHint = GetScalingQualityHint(scaleX, scaleY);
                    EditorGUILayout.HelpBox($"注意: 将进行缩放。原始切片: {originalSliceWidth}×{originalSliceHeight} → 目标: {customWidth}×{customHeight}\n{qualityHint}", MessageType.Warning);
                }
            }
        }
        
        filterMode = (FilterMode)EditorGUILayout.EnumPopup("滤波模式", filterMode);
        wrapMode = (TextureWrapMode)EditorGUILayout.EnumPopup("环绕模式", wrapMode);
        
        EditorGUILayout.Space();
        
        // 预览信息
        if (inputAtlas != null)
        {
            EditorGUILayout.Space();
            EditorGUILayout.LabelField("图集信息", EditorStyles.boldLabel);
            EditorGUILayout.LabelField($"图集尺寸: {inputAtlas.width}×{inputAtlas.height}");
            EditorGUILayout.LabelField($"原始切片数: {totalOriginalSlices}");
            EditorGUILayout.LabelField($"原始切片尺寸: {originalSliceWidth}×{originalSliceHeight}");
            
            // 显示输出体积纹理的尺寸
            int outputWidth = resolutionMode == ResolutionMode.UseOriginal ? originalSliceWidth : customWidth;
            int outputHeight = resolutionMode == ResolutionMode.UseOriginal ? originalSliceHeight : customHeight;
            int outputDepth = enableSliceControl ? targetSliceCount : totalOriginalSlices;
            
            EditorGUILayout.LabelField($"输出体积纹理尺寸: {outputWidth}×{outputHeight}×{outputDepth}");
            EditorGUILayout.LabelField($"体积纹理总像素: {outputWidth * outputHeight * outputDepth:N0}");
            
            // 计算内存占用
            float memoryMB = (outputWidth * outputHeight * outputDepth * 4) / (1024f * 1024f); // 4 bytes per pixel for RGBA32
            EditorGUILayout.LabelField($"内存占用: {memoryMB:F2} MB (RGBA32格式)");
        }
        
        // 创建按钮
        GUI.enabled = inputAtlas != null && gridRows > 0 && gridColumns > 0;
        if (GUILayout.Button("转换SDF图集到体积纹理", GUILayout.Height(30)))
        {
            ConvertAtlasToVolume();
        }
        GUI.enabled = true;
    }
    
    private string GetScalingQualityHint(float scaleX, float scaleY)
    {
        if (scaleX < 1.0f || scaleY < 1.0f)
            return "⚠️ 缩小操作可能导致细节丢失，建议使用三线性滤波";
        else if (scaleX > 1.0f || scaleY > 1.0f)
            return "⚠️ 放大操作会降低质量，建议保持原始尺寸";
        else
            return "保持原始尺寸";
    }

    private void ConvertAtlasToVolume()
    {
        if (inputAtlas == null)
        {
            EditorUtility.DisplayDialog("错误", "请先选择一个SDF图集", "确定");
            return;
        }
        
        try
        {
            // 确保纹理可读
            string assetPath = AssetDatabase.GetAssetPath(inputAtlas);
            TextureImporter importer = AssetImporter.GetAtPath(assetPath) as TextureImporter;
            bool wasReadable = importer.isReadable;
            
            if (!wasReadable)
            {
                importer.isReadable = true;
                AssetDatabase.ImportAsset(assetPath, ImportAssetOptions.ForceUpdate);
            }
            
            EditorUtility.DisplayProgressBar("处理中", "正在读取图集...", 0.1f);
            
            // 计算原始切片尺寸
            int originalSliceWidth = inputAtlas.width / gridColumns;
            int originalSliceHeight = inputAtlas.height / gridRows;
            int totalOriginalSlices = gridRows * gridColumns;
            
            // 确定输出尺寸和深度
            int outputWidth, outputHeight, outputDepth;
            if (resolutionMode == ResolutionMode.UseOriginal)
            {
                outputWidth = originalSliceWidth;
                outputHeight = originalSliceHeight;
            }
            else
            {
                outputWidth = Mathf.Max(1, customWidth);
                outputHeight = Mathf.Max(1, customHeight);
            }
            
            outputDepth = enableSliceControl ? Mathf.Clamp(targetSliceCount, 1, totalOriginalSlices) : totalOriginalSlices;
            
            Debug.Log($"图集尺寸: {inputAtlas.width}×{inputAtlas.height}");
            Debug.Log($"原始切片尺寸: {originalSliceWidth}×{originalSliceHeight}");
            Debug.Log($"原始切片总数: {totalOriginalSlices}");
            Debug.Log($"输出切片尺寸: {outputWidth}×{outputHeight}");
            Debug.Log($"输出切片数量: {outputDepth}");
            
            if (originalSliceWidth <= 0 || originalSliceHeight <= 0)
            {
                EditorUtility.ClearProgressBar();
                EditorUtility.DisplayDialog("错误", "图集尺寸与行列数不匹配", "确定");
                return;
            }
            
            // 计算采样间隔
            float sampleStep = (float)totalOriginalSlices / outputDepth;
            
            // 创建3D纹理（使用输出尺寸和深度）
            Texture3D volumeTexture = new Texture3D(outputWidth, outputHeight, outputDepth, TextureFormat.RGBA32, false);
            volumeTexture.filterMode = filterMode;
            volumeTexture.wrapMode = wrapMode;
            
            // 准备颜色数组
            Color[] volumeColors = new Color[outputWidth * outputHeight * outputDepth];
            
            // 获取图集的所有像素
            Color[] atlasPixels = inputAtlas.GetPixels();
            
            // 按采样间隔处理切片
            for (int slice = 0; slice < outputDepth; slice++)
            {
                // 计算原始切片索引（使用线性插值采样）
                float originalSliceIndexF = slice * sampleStep;
                int originalSliceIndex = Mathf.Clamp(Mathf.RoundToInt(originalSliceIndexF), 0, totalOriginalSlices - 1);
                
                // 计算原始切片的行列位置
                int row = originalSliceIndex / gridColumns;
                int col = originalSliceIndex % gridColumns;
                
                float progress = 0.1f + 0.8f * ((float)slice / outputDepth);
                EditorUtility.DisplayProgressBar("处理中", $"正在采样切片 {slice + 1}/{outputDepth} (来自原始切片 {originalSliceIndex + 1}/{totalOriginalSlices})...", progress);
                
                // 提取原始切片像素
                Color[] originalSlicePixels = ExtractSlicePixels(atlasPixels, col, row, originalSliceWidth, originalSliceHeight, inputAtlas.width, inputAtlas.height);
                
                // 如果需要缩放，则进行缩放
                Color[] finalSlicePixels;
                if (outputWidth == originalSliceWidth && outputHeight == originalSliceHeight)
                {
                    // 尺寸相同，直接使用
                    finalSlicePixels = originalSlicePixels;
                }
                else
                {
                    // 进行缩放
                    finalSlicePixels = ResizeSlicePixels(originalSlicePixels, originalSliceWidth, originalSliceHeight, outputWidth, outputHeight);
                }
                
                // 将切片数据复制到体积纹理
                for (int y = 0; y < outputHeight; y++)
                {
                    for (int x = 0; x < outputWidth; x++)
                    {
                        int pixelIndex = y * outputWidth + x;
                        int volumeIndex = slice * (outputWidth * outputHeight) + pixelIndex;
                        volumeColors[volumeIndex] = finalSlicePixels[pixelIndex];
                    }
                }
            }
            
            // 应用像素数据
            volumeTexture.SetPixels(volumeColors);
            volumeTexture.Apply();
            
            EditorUtility.DisplayProgressBar("处理中", "正在保存纹理...", 0.9f);
            
            // 保存纹理
            SaveVolumeTexture(volumeTexture, outputWidth, outputHeight, outputDepth);
            
            // 恢复纹理设置
            if (!wasReadable)
            {
                importer.isReadable = false;
                AssetDatabase.ImportAsset(assetPath, ImportAssetOptions.ForceUpdate);
            }
            
            EditorUtility.ClearProgressBar();
            EditorUtility.DisplayDialog("完成", 
                $"SDF图集转换完成！\n" +
                $"体积纹理尺寸: {outputWidth}×{outputHeight}×{outputDepth}\n" +
                $"原始切片: {originalSliceWidth}×{originalSliceHeight} × {totalOriginalSlices}\n" +
                $"输出切片: {outputWidth}×{outputHeight} × {outputDepth}\n" +
                $"采样间隔: {sampleStep:F2}", 
                "确定");
        }
        catch (System.Exception e)
        {
            EditorUtility.ClearProgressBar();
            Debug.LogError($"转换失败: {e.Message}\n{e.StackTrace}");
            EditorUtility.DisplayDialog("错误", $"转换失败: {e.Message}", "确定");
        }
    }
    
    private Color[] ExtractSlicePixels(Color[] atlasPixels, int col, int row, int sliceWidth, int sliceHeight, int atlasWidth, int atlasHeight)
    {
        Color[] slicePixels = new Color[sliceWidth * sliceHeight];
        
        // 在原始图集中的起始位置
        int startX = col * sliceWidth;
        int startY = row * sliceHeight;
        
        for (int y = 0; y < sliceHeight; y++)
        {
            for (int x = 0; x < sliceWidth; x++)
            {
                // 计算在原始图集中的位置
                int atlasX = startX + x;
                int atlasY = startY + y;
                
                // 在Unity中，纹理的Y坐标是自下而上的，但图集通常是从上到下的
                // 所以我们翻转Y轴
                int atlasPixelIndex = (atlasHeight - 1 - atlasY) * atlasWidth + atlasX;
                
                // 切片中的位置
                int slicePixelIndex = y * sliceWidth + x;
                
                slicePixels[slicePixelIndex] = atlasPixels[atlasPixelIndex];
            }
        }
        
        return slicePixels;
    }
    
    private Color[] ResizeSlicePixels(Color[] originalPixels, int originalWidth, int originalHeight, int targetWidth, int targetHeight)
    {
        // 创建临时纹理
        Texture2D originalTexture = new Texture2D(originalWidth, originalHeight, TextureFormat.RGBA32, false);
        originalTexture.SetPixels(originalPixels);
        originalTexture.Apply();
        
        // 使用RenderTexture进行高质量缩放
        RenderTexture rt = RenderTexture.GetTemporary(targetWidth, targetHeight, 0, RenderTextureFormat.ARGB32);
        RenderTexture.active = rt;
        
        // 使用双线性滤波进行缩放
        Graphics.Blit(originalTexture, rt);
        
        // 创建目标纹理
        Texture2D resizedTexture = new Texture2D(targetWidth, targetHeight, TextureFormat.RGBA32, false);
        resizedTexture.ReadPixels(new Rect(0, 0, targetWidth, targetHeight), 0, 0);
        resizedTexture.Apply();
        
        // 获取缩放后的像素
        Color[] resizedPixels = resizedTexture.GetPixels();
        
        // 清理临时资源
        RenderTexture.active = null;
        RenderTexture.ReleaseTemporary(rt);
        DestroyImmediate(originalTexture);
        DestroyImmediate(resizedTexture);
        
        return resizedPixels;
    }
    
    private void SaveVolumeTexture(Texture3D volumeTexture, int width, int height, int depth)
    {
        // 选择保存位置
        string defaultName = outputTextureName;
        if (inputAtlas != null)
        {
            string atlasName = inputAtlas.name;
            defaultName = $"{atlasName}_Volume_{width}x{height}x{depth}";
        }
        
        string savePath = EditorUtility.SaveFilePanelInProject(
            "保存体积纹理",
            defaultName,
            "asset",
            "请选择保存体积纹理的位置"
        );
        
        if (string.IsNullOrEmpty(savePath))
            return;
        
        // 保存纹理
        AssetDatabase.CreateAsset(volumeTexture, savePath);
        AssetDatabase.SaveAssets();
        AssetDatabase.Refresh();
        
        // 设置体积纹理的导入参数
        TextureImporter importer = AssetImporter.GetAtPath(savePath) as TextureImporter;
        if (importer != null)
        {
            // 设置纹理类型为3D
            importer.textureShape = TextureImporterShape.Texture3D;
            
            // 对于SDF数据，禁用sRGB转换（线性数据）
            importer.sRGBTexture = false;
            
            // 确保可读（如果需要后续处理）
            importer.isReadable = true;
            
            // 设置滤波模式
            importer.filterMode = filterMode;
            importer.wrapMode = wrapMode;
            
            // 设置平台特定的导入设置，禁用压缩以保持精度
            TextureImporterPlatformSettings platformSettings = importer.GetDefaultPlatformTextureSettings();
            platformSettings.overridden = true;
            platformSettings.maxTextureSize = Mathf.Max(width, height, depth) * 2; // 设置足够大的最大尺寸
            platformSettings.format = TextureImporterFormat.RGBA32;
            platformSettings.textureCompression = TextureImporterCompression.Uncompressed;
            
            // 设置所有平台的设置
            importer.SetPlatformTextureSettings(platformSettings);
            
            // 保存设置
            importer.SaveAndReimport();
        }
        
        // 选择新创建的纹理
        EditorUtility.FocusProjectWindow();
        Selection.activeObject = volumeTexture;
        
        // 在Project窗口中选择并聚焦
        EditorGUIUtility.PingObject(volumeTexture);
        
        Debug.Log($"体积纹理已保存: {savePath}");
        Debug.Log($"尺寸: {volumeTexture.width}×{volumeTexture.height}×{volumeTexture.depth}");
    }

    // 工具方法：验证图集尺寸是否匹配指定的行列数
    [MenuItem("Tools/验证SDF图集")]
    public static void ValidateAtlas()
    {
        Texture2D atlas = Selection.activeObject as Texture2D;
        if (atlas == null)
        {
            EditorUtility.DisplayDialog("错误", "请先选择一个纹理", "确定");
            return;
        }
        
        int width = atlas.width;
        int height = atlas.height;
        
        // 尝试猜测最佳的行列数
        List<string> results = new List<string>();
        
        for (int rows = 8; rows <= 32; rows *= 2)
        {
            for (int cols = 8; cols <= 32; cols *= 2)
            {
                if (width % cols == 0 && height % rows == 0)
                {
                    int sliceWidth = width / cols;
                    int sliceHeight = height / rows;
                    results.Add($"{cols}×{rows} -> 每个切片 {sliceWidth}×{sliceHeight}");
                }
            }
        }
        
        if (results.Count > 0)
        {
            string message = $"纹理 {atlas.name} ({width}×{height}) 可能的分割方式:\n\n";
            foreach (string result in results)
            {
                message += result + "\n";
            }
            EditorUtility.DisplayDialog("图集验证", message, "确定");
        }
        else
        {
            EditorUtility.DisplayDialog("图集验证", 
                $"纹理 {atlas.name} 尺寸为 {width}×{height}\n" +
                "未找到明显的16×16分割方式。", 
                "确定");
        }
    }
}