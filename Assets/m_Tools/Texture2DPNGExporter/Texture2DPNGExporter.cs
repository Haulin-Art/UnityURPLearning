using UnityEngine;
using UnityEditor;
using System.IO;

public class Texture2DPNGExporter : EditorWindow
{
    [MenuItem("Tools/Texture2D PNG Exporter")]
    public static void ShowWindow()
    {
        GetWindow<Texture2DPNGExporter>("Texture2D PNG Exporter");
    }

    private Texture2D sourceTexture;
    private string exportPath = "Exports";
    private string fileName = "";

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

        EditorGUILayout.Space(10);

        EditorGUI.BeginDisabledGroup(sourceTexture == null);
        if (GUILayout.Button("Export to PNG", GUILayout.Height(40)))
        {
            ExportToPNG();
        }
        EditorGUI.EndDisabledGroup();

        if (sourceTexture != null && string.IsNullOrEmpty(fileName))
        {
            fileName = sourceTexture.name;
        }
    }

    private void ExportToPNG()
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

        string filePath = Path.Combine(fullPath, $"{fileName}.png");

        Texture2D exportTexture = GetReadableTexture(sourceTexture);

        byte[] pngData = exportTexture.EncodeToPNG();
        
        if (pngData == null)
        {
            Debug.LogError("编码PNG失败! 纹理格式可能不支持。");
            return;
        }

        File.WriteAllBytes(filePath, pngData);

        if (exportTexture != sourceTexture)
        {
            DestroyImmediate(exportTexture);
        }

        Debug.Log($"PNG已导出到: {filePath}");
        
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
}
