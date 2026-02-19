using UnityEngine;
using UnityEditor;
using System.IO;
using System.Collections.Generic;
/*
public class SDFAtlasToVolumeTexture : EditorWindow
{
    private Texture2D inputAtlas;
    private int gridRows = 16;
    private int gridColumns = 16;
    private string outputTextureName = "SDF_Volume";
    private FilterMode filterMode = FilterMode.Bilinear;
    private TextureWrapMode wrapMode = TextureWrapMode.Clamp;
    
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
        
        // 输出设置
        EditorGUILayout.LabelField("输出设置", EditorStyles.boldLabel);
        outputTextureName = EditorGUILayout.TextField("纹理名称", outputTextureName);
        filterMode = (FilterMode)EditorGUILayout.EnumPopup("滤波模式", filterMode);
        wrapMode = (TextureWrapMode)EditorGUILayout.EnumPopup("环绕模式", wrapMode);
        
        EditorGUILayout.Space();
        
        // 创建按钮
        GUI.enabled = inputAtlas != null && gridRows > 0 && gridColumns > 0;
        if (GUILayout.Button("转换SDF图集到体积纹理", GUILayout.Height(30)))
        {
            ConvertAtlasToVolume();
        }
        GUI.enabled = true;
        
        // 预览信息
        if (inputAtlas != null)
        {
            EditorGUILayout.Space();
            EditorGUILayout.LabelField("图集信息", EditorStyles.boldLabel);
            EditorGUILayout.LabelField($"尺寸: {inputAtlas.width}×{inputAtlas.height}");
            EditorGUILayout.LabelField($"总切片数: {gridRows * gridColumns}");
            
            int sliceWidth = inputAtlas.width / gridColumns;
            int sliceHeight = inputAtlas.height / gridRows;
            EditorGUILayout.LabelField($"单切片尺寸: {sliceWidth}×{sliceHeight}");
        }
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
            
            // 计算每个切片的尺寸
            int sliceWidth = inputAtlas.width / gridColumns;
            int sliceHeight = inputAtlas.height / gridRows;
            int totalSlices = gridRows * gridColumns;
            
            Debug.Log($"图集尺寸: {inputAtlas.width}×{inputAtlas.height}");
            Debug.Log($"切片尺寸: {sliceWidth}×{sliceHeight}");
            Debug.Log($"总切片数: {totalSlices}");
            
            if (sliceWidth <= 0 || sliceHeight <= 0)
            {
                EditorUtility.ClearProgressBar();
                EditorUtility.DisplayDialog("错误", "图集尺寸与行列数不匹配", "确定");
                return;
            }
            
            // 创建3D纹理
            Texture3D volumeTexture = new Texture3D(sliceWidth, sliceHeight, totalSlices, TextureFormat.RGBA32, false);
            volumeTexture.filterMode = filterMode;
            volumeTexture.wrapMode = wrapMode;
            
            // 准备颜色数组
            Color[] volumeColors = new Color[sliceWidth * sliceHeight * totalSlices];
            
            // 获取图集的所有像素
            Color[] atlasPixels = inputAtlas.GetPixels();
            
            // 按从左到右、从上到下的顺序提取切片
            for (int row = 0; row < gridRows; row++)
            {
                for (int col = 0; col < gridColumns; col++)
                {
                    int sliceIndex = row * gridColumns + col;
                    float progress = 0.1f + 0.8f * ((float)sliceIndex / totalSlices);
                    EditorUtility.DisplayProgressBar("处理中", $"正在提取切片 {sliceIndex + 1}/{totalSlices}...", progress);
                    
                    // 提取当前切片的像素
                    Color[] slicePixels = ExtractSlicePixels(atlasPixels, col, row, sliceWidth, sliceHeight, inputAtlas.width, inputAtlas.height);
                    
                    // 将切片数据复制到体积纹理
                    for (int y = 0; y < sliceHeight; y++)
                    {
                        for (int x = 0; x < sliceWidth; x++)
                        {
                            int pixelIndex = y * sliceWidth + x;
                            int volumeIndex = sliceIndex * (sliceWidth * sliceHeight) + pixelIndex;
                            volumeColors[volumeIndex] = slicePixels[pixelIndex];
                        }
                    }
                }
            }
            
            // 应用像素数据
            volumeTexture.SetPixels(volumeColors);
            volumeTexture.Apply();
            
            EditorUtility.DisplayProgressBar("处理中", "正在保存纹理...", 0.9f);
            
            // 保存纹理
            SaveVolumeTexture(volumeTexture);
            
            // 恢复纹理设置
            if (!wasReadable)
            {
                importer.isReadable = false;
                AssetDatabase.ImportAsset(assetPath, ImportAssetOptions.ForceUpdate);
            }
            
            EditorUtility.ClearProgressBar();
            EditorUtility.DisplayDialog("完成", 
                $"SDF图集转换完成！\n" +
                $"体积纹理尺寸: {sliceWidth}×{sliceHeight}×{totalSlices}\n" +
                $"切片数: {totalSlices}", 
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
            for (int x = 0; x < sliceWidth; x++)  // 修正：这里应该是x++，不是y++
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

    private void SaveVolumeTexture(Texture3D volumeTexture)
    {
        // 选择保存位置
        string defaultName = outputTextureName;
        if (inputAtlas != null)
        {
            string atlasName = inputAtlas.name;
            defaultName = $"{atlasName}_Volume";
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
        
        // 选择新创建的纹理
        EditorUtility.FocusProjectWindow();
        Selection.activeObject = volumeTexture;
        
        // 在Project窗口中选择并聚焦
        EditorGUIUtility.PingObject(volumeTexture);
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
*/