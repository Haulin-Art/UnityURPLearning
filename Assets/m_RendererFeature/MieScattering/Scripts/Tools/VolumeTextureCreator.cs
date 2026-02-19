using UnityEngine;
using UnityEditor;
using System.IO;
using System.Collections.Generic;

public class VolumeTextureCreator : EditorWindow
{
    private string inputFolderPath = "Assets/Textures/Sequence";
    private string outputTextureName = "VolumeTexture";
    private int textureSize = 128;
    private TextureFormat textureFormat = TextureFormat.RGBA32;
    
    [MenuItem("Tools/Volume Texture Creator")]
    public static void ShowWindow()
    {
        GetWindow<VolumeTextureCreator>("Volume Texture Creator");
    }

    private void OnGUI()
    {
        GUILayout.Label("体积纹理创建工具", EditorStyles.boldLabel);
        EditorGUILayout.Space();
        
        // 输入文件夹路径
        EditorGUILayout.LabelField("输入设置", EditorStyles.boldLabel);
        EditorGUILayout.BeginHorizontal();
        inputFolderPath = EditorGUILayout.TextField("图片文件夹", inputFolderPath);
        if (GUILayout.Button("浏览", GUILayout.Width(60)))
        {
            string selectedPath = EditorUtility.OpenFolderPanel("选择图片文件夹", Application.dataPath, "");
            if (!string.IsNullOrEmpty(selectedPath))
            {
                inputFolderPath = "Assets" + selectedPath.Replace(Application.dataPath, "");
            }
        }
        EditorGUILayout.EndHorizontal();
        
        // 输出设置
        EditorGUILayout.LabelField("输出设置", EditorStyles.boldLabel);
        outputTextureName = EditorGUILayout.TextField("纹理名称", outputTextureName);
        textureSize = EditorGUILayout.IntField("图片尺寸", textureSize);
        textureFormat = (TextureFormat)EditorGUILayout.EnumPopup("纹理格式", textureFormat);
        
        EditorGUILayout.Space();
        
        // 创建按钮
        GUI.enabled = Directory.Exists(inputFolderPath);
        if (GUILayout.Button("创建体积纹理", GUILayout.Height(30)))
        {
            CreateVolumeTexture();
        }
        GUI.enabled = true;
        
        // 状态信息
        EditorGUILayout.HelpBox($"将把 {inputFolderPath} 中的图片序列合并为体积纹理", MessageType.Info);
    }

    private void CreateVolumeTexture()
    {
        try
        {
            // 获取所有PNG文件
            string[] pngFiles = Directory.GetFiles(inputFolderPath, "*.png");
            if (pngFiles.Length == 0)
            {
                EditorUtility.DisplayDialog("错误", "文件夹中没有找到PNG图片", "确定");
                return;
            }

            // 分析文件名，按名称分组
            Dictionary<string, List<SequenceImage>> imageGroups = AnalyzeImageFiles(pngFiles);
            
            if (imageGroups.Count == 0)
            {
                EditorUtility.DisplayDialog("错误", "未找到符合命名规则（名称_序号）的图片文件", "确定");
                return;
            }

            // 显示选择对话框让用户选择要处理哪个序列
            string[] groupNames = new string[imageGroups.Count];
            imageGroups.Keys.CopyTo(groupNames, 0);

            int selectedGroup = 0;
            if (groupNames.Length > 1)
            {
                // 修正：DisplayDialogComplex返回的是int，不是数组
                selectedGroup = EditorUtility.DisplayDialogComplex(
                    "选择序列", 
                    "找到多个图片序列，请选择要处理的一个：",
                    groupNames[0],
                    groupNames.Length > 1 ? groupNames[1] : "",
                    groupNames.Length > 2 ? "更多..." : "");

                // 如果用户点击了"更多..."，可能需要更复杂的选择逻辑
                // 这里简单处理，如果有更多选项，可以扩展
            }

            string selectedName = groupNames[selectedGroup];
            List<SequenceImage> selectedSequence = imageGroups[selectedName];
            
            // 按序号排序
            selectedSequence.Sort((a, b) => a.sequenceNumber.CompareTo(b.sequenceNumber));
            
            EditorUtility.DisplayProgressBar("处理中", "正在创建体积纹理...", 0.1f);
            
            // 创建3D纹理
            Texture3D volumeTexture = GenerateVolumeTexture(selectedSequence);
            
            EditorUtility.DisplayProgressBar("处理中", "正在保存纹理...", 0.8f);
            
            // 保存纹理
            SaveVolumeTexture(volumeTexture, selectedName);
            
            EditorUtility.ClearProgressBar();
            EditorUtility.DisplayDialog("完成", $"体积纹理创建成功！\n切片数量: {selectedSequence.Count}", "确定");
        }
        catch (System.Exception e)
        {
            EditorUtility.ClearProgressBar();
            Debug.LogError($"创建失败: {e.Message}\n{e.StackTrace}");
            EditorUtility.DisplayDialog("错误", $"创建失败: {e.Message}", "确定");
        }
    }

    private Dictionary<string, List<SequenceImage>> AnalyzeImageFiles(string[] filePaths)
    {
        Dictionary<string, List<SequenceImage>> groups = new Dictionary<string, List<SequenceImage>>();
        
        foreach (string filePath in filePaths)
        {
            string fileName = Path.GetFileNameWithoutExtension(filePath);
            
            // 解析文件名格式：名称_序号
            int lastUnderscoreIndex = fileName.LastIndexOf('_');
            if (lastUnderscoreIndex == -1) continue;
            
            string namePart = fileName.Substring(0, lastUnderscoreIndex);
            string numberPart = fileName.Substring(lastUnderscoreIndex + 1);
            
            // 检查序号是否为数字
            if (int.TryParse(numberPart, out int sequenceNumber))
            {
                if (!groups.ContainsKey(namePart))
                {
                    groups[namePart] = new List<SequenceImage>();
                }
                
                groups[namePart].Add(new SequenceImage
                {
                    filePath = filePath,
                    name = namePart,
                    sequenceNumber = sequenceNumber
                });
            }
        }
        
        return groups;
    }

    private Texture3D GenerateVolumeTexture(List<SequenceImage> imageSequence)
    {
        int sliceCount = imageSequence.Count;
        int width = textureSize;
        int height = textureSize;
        
        // 创建3D纹理
        Texture3D volumeTexture = new Texture3D(width, height, sliceCount, textureFormat, false);
        volumeTexture.wrapMode = TextureWrapMode.Clamp;
        volumeTexture.filterMode = FilterMode.Bilinear;
        
        // 准备颜色数组
        Color[] volumeColors = new Color[width * height * sliceCount];
        
        for (int slice = 0; slice < sliceCount; slice++)
        {
            EditorUtility.DisplayProgressBar("处理中", $"正在处理图片 {slice + 1}/{sliceCount}", (float)slice / sliceCount);
            
            string imagePath = imageSequence[slice].filePath;
            Texture2D sliceTexture = LoadTexture(imagePath);
            
            if (sliceTexture.width != width || sliceTexture.height != height)
            {
                // 调整图片尺寸
                sliceTexture = ResizeTexture(sliceTexture, width, height);
            }
            
            // 获取当前切片的像素数据
            Color[] sliceColors = sliceTexture.GetPixels();
            
            // 将切片数据复制到体积纹理的对应位置
            for (int y = 0; y < height; y++)
            {
                for (int x = 0; x < width; x++)
                {
                    int sliceIndex = y * width + x;
                    int volumeIndex = slice * (width * height) + sliceIndex;
                    volumeColors[volumeIndex] = sliceColors[sliceIndex];
                }
            }
            
            // 销毁临时纹理
            DestroyImmediate(sliceTexture);
        }
        
        // 应用像素数据到3D纹理
        volumeTexture.SetPixels(volumeColors);
        volumeTexture.Apply();
        
        return volumeTexture;
    }

    private Texture2D LoadTexture(string filePath)
    {
        byte[] fileData = File.ReadAllBytes(filePath);
        Texture2D texture = new Texture2D(2, 2, TextureFormat.RGBA32, false);
        
        // 加载图片数据
        if (!texture.LoadImage(fileData))
        {
            throw new System.Exception($"无法加载纹理: {filePath}");
        }
        
        return texture;
    }

    private Texture2D ResizeTexture(Texture2D source, int newWidth, int newHeight)
    {
        RenderTexture rt = RenderTexture.GetTemporary(newWidth, newHeight, 0, RenderTextureFormat.ARGB32);
        RenderTexture.active = rt;
        
        // 使用Graphics.Blit进行高质量缩放
        Graphics.Blit(source, rt);
        
        Texture2D resizedTexture = new Texture2D(newWidth, newHeight, TextureFormat.ARGB32, false);
        resizedTexture.ReadPixels(new Rect(0, 0, newWidth, newHeight), 0, 0);
        resizedTexture.Apply();
        
        RenderTexture.active = null;
        RenderTexture.ReleaseTemporary(rt);
        
        return resizedTexture;
    }

    private void SaveVolumeTexture(Texture3D volumeTexture, string textureName)
    {
        string outputPath = Path.GetDirectoryName(inputFolderPath);
        string fullOutputPath = Path.Combine(outputPath, $"{outputTextureName}_{textureName}.asset");
        
        // 确保路径存在
        Directory.CreateDirectory(Path.GetDirectoryName(fullOutputPath));
        
        // 保存为Asset
        AssetDatabase.CreateAsset(volumeTexture, fullOutputPath);
        AssetDatabase.SaveAssets();
        AssetDatabase.Refresh();
        
        // 选择新创建的纹理
        EditorUtility.FocusProjectWindow();
        Selection.activeObject = volumeTexture;
    }

    private class SequenceImage
    {
        public string filePath;
        public string name;
        public int sequenceNumber;
    }
}