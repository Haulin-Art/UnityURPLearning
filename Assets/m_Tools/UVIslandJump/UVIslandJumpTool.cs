using UnityEngine;
using UnityEditor;

public class UVIslandJumpTool : EditorWindow
{
    [MenuItem("Tools/UV Island Jump Tool")]
    public static void ShowWindow()
    {
        GetWindow<UVIslandJumpTool>("UV Island Jump Tool");
    }

    private Texture2D uvTexture;
    private Texture2D worldPosTexture;
    private Texture2D sdfTexture;
    private Texture2D directionTexture;
    private Texture2D discriminantTexture;
    private int borderSize = 2;
    private float minDistance = 5f;
    private float discriminantThreshold = 0.1f;
    private int blurRadius = 3;
    private ComputeShader jumpComputeShader;

    private RenderTexture jumpTextureRT;
    private RenderTexture blurTempRT;
    private Texture2D jumpTexture2D;

    private Vector2 scrollPosition;

    private void OnGUI()
    {
        scrollPosition = EditorGUILayout.BeginScrollView(scrollPosition);

        EditorGUILayout.Space(10);

        EditorGUILayout.HelpBox(
            "UV岛跳跃工具\n\n" +
            "输入贴图:\n" +
            "- 世界位置贴图\n" +
            "- SDF贴图\n" +
            "- 指向图\n" +
            "- 区分图\n\n" +
            "输出: UV岛桥接贴图",
            MessageType.Info
        );

        EditorGUILayout.Space(10);

        EditorGUILayout.LabelField("输入贴图", EditorStyles.boldLabel);
        uvTexture = (Texture2D)EditorGUILayout.ObjectField("UV贴图", uvTexture, typeof(Texture2D), false);
        worldPosTexture = (Texture2D)EditorGUILayout.ObjectField("世界位置贴图", worldPosTexture, typeof(Texture2D), false);
        sdfTexture = (Texture2D)EditorGUILayout.ObjectField("SDF贴图", sdfTexture, typeof(Texture2D), false);
        directionTexture = (Texture2D)EditorGUILayout.ObjectField("指向图", directionTexture, typeof(Texture2D), false);
        discriminantTexture = (Texture2D)EditorGUILayout.ObjectField("区分图", discriminantTexture, typeof(Texture2D), false);

        EditorGUILayout.Space(10);

        EditorGUILayout.LabelField("设置", EditorStyles.boldLabel);
        borderSize = EditorGUILayout.IntSlider("边界宽度(像素)", borderSize, 1, 20);
        minDistance = EditorGUILayout.FloatField("最小距离", minDistance);
        discriminantThreshold = EditorGUILayout.FloatField("区分阈值", discriminantThreshold);
        blurRadius = EditorGUILayout.IntSlider("模糊半径", blurRadius, 1, 10);

        EditorGUILayout.Space(10);

        EditorGUILayout.LabelField("Compute Shader", EditorStyles.boldLabel);
        jumpComputeShader = (ComputeShader)EditorGUILayout.ObjectField("桥接计算Shader", jumpComputeShader, typeof(ComputeShader), false);

        EditorGUILayout.Space(10);

        EditorGUILayout.LabelField("桥接贴图输出", EditorStyles.boldLabel);
        if (jumpTexture2D != null)
        {
            GUILayout.Label(jumpTexture2D, GUILayout.MaxWidth(256), GUILayout.MaxHeight(256));
        }
        else
        {
            EditorGUILayout.HelpBox("尚未生成桥接贴图", MessageType.Warning);
        }

        EditorGUILayout.Space(10);

        EditorGUI.BeginDisabledGroup(worldPosTexture == null || sdfTexture == null || directionTexture == null || discriminantTexture == null || jumpComputeShader == null);
        if (GUILayout.Button("生成UV岛桥接贴图", GUILayout.Height(40)))
        {
            GenerateJumpTexture();
        }
        EditorGUI.EndDisabledGroup();

        EditorGUILayout.EndScrollView();
    }

    private void GenerateJumpTexture()
    {
        if (worldPosTexture == null || sdfTexture == null || directionTexture == null || discriminantTexture == null || jumpComputeShader == null)
        {
            Debug.LogError("请确保所有贴图和桥接计算Shader已设置!");
            return;
        }

        int width = sdfTexture.width;
        int height = sdfTexture.height;

        Texture2D readableWorldPos = GetReadableTexture(worldPosTexture);
        Texture2D readableSDF = GetReadableTexture(sdfTexture);
        Texture2D readableDirection = GetReadableTexture(directionTexture);
        Texture2D readableDiscriminant = GetReadableTexture(discriminantTexture);

        RenderTexture worldPosRT = new RenderTexture(width, height, 0, RenderTextureFormat.ARGBFloat);
        worldPosRT.enableRandomWrite = true;
        worldPosRT.Create();
        Graphics.Blit(readableWorldPos, worldPosRT);

        RenderTexture sdfRT = new RenderTexture(width, height, 0, RenderTextureFormat.ARGBFloat);
        sdfRT.enableRandomWrite = true;
        sdfRT.Create();
        Graphics.Blit(readableSDF, sdfRT);

        RenderTexture directionRT = new RenderTexture(width, height, 0, RenderTextureFormat.ARGBFloat);
        directionRT.enableRandomWrite = true;
        directionRT.Create();
        Graphics.Blit(readableDirection, directionRT);

        RenderTexture discriminantRT = new RenderTexture(width, height, 0, RenderTextureFormat.ARGBFloat);
        discriminantRT.enableRandomWrite = true;
        discriminantRT.Create();
        Graphics.Blit(readableDiscriminant, discriminantRT);

        RenderTexture outputRT = new RenderTexture(width, height, 0, RenderTextureFormat.ARGBFloat);
        outputRT.enableRandomWrite = true;
        outputRT.Create();

        RenderTexture tempRT = new RenderTexture(width, height, 0, RenderTextureFormat.ARGBFloat);
        tempRT.enableRandomWrite = true;
        tempRT.Create();

        int kernelIndex = jumpComputeShader.FindKernel("CSMain");

        jumpComputeShader.SetTexture(kernelIndex, "WorldPosTexture", worldPosRT);
        jumpComputeShader.SetTexture(kernelIndex, "SDFTexture", sdfRT);
        jumpComputeShader.SetTexture(kernelIndex, "DirectionTexture", directionRT);
        jumpComputeShader.SetTexture(kernelIndex, "DiscriminantTexture", discriminantRT);
        jumpComputeShader.SetTexture(kernelIndex, "OutputTexture", outputRT);
        jumpComputeShader.SetInt("_Width", width);
        jumpComputeShader.SetInt("_Height", height);
        jumpComputeShader.SetInt("_BorderSize", borderSize);
        jumpComputeShader.SetFloat("_MinDistance", minDistance);
        jumpComputeShader.SetFloat("_DiscriminantThreshold", discriminantThreshold);

        int threadGroupsX = Mathf.CeilToInt(width / 8.0f);
        int threadGroupsY = Mathf.CeilToInt(height / 8.0f);

        jumpComputeShader.Dispatch(kernelIndex, threadGroupsX, threadGroupsY, 1);

        int blurKernelIndex = jumpComputeShader.FindKernel("CSBlur");

        jumpComputeShader.SetTexture(blurKernelIndex, "SDFTexture", sdfRT);
        jumpComputeShader.SetTexture(blurKernelIndex, "InputTexture", outputRT);
        jumpComputeShader.SetTexture(blurKernelIndex, "OutputTexture", tempRT);
        jumpComputeShader.SetInt("_Width", width);
        jumpComputeShader.SetInt("_Height", height);
        jumpComputeShader.SetInt("_BorderSize", borderSize);
        jumpComputeShader.SetInt("_BlurRadius", blurRadius);

        jumpComputeShader.Dispatch(blurKernelIndex, threadGroupsX, threadGroupsY, 1);

        jumpComputeShader.SetTexture(blurKernelIndex, "InputTexture", tempRT);
        jumpComputeShader.SetTexture(blurKernelIndex, "OutputTexture", outputRT);

        jumpComputeShader.Dispatch(blurKernelIndex, threadGroupsX, threadGroupsY, 1);

        jumpTexture2D = new Texture2D(width, height, TextureFormat.RGBA32, false);
        RenderTexture.active = outputRT;
        jumpTexture2D.ReadPixels(new Rect(0, 0, width, height), 0, 0);
        jumpTexture2D.Apply();
        RenderTexture.active = null;

        if (jumpTextureRT != null)
        {
            jumpTextureRT.Release();
        }
        jumpTextureRT = outputRT;

        if (blurTempRT != null)
        {
            blurTempRT.Release();
        }
        blurTempRT = tempRT;

        worldPosRT.Release();
        sdfRT.Release();
        directionRT.Release();
        discriminantRT.Release();

        if (readableWorldPos != worldPosTexture)
        {
            DestroyImmediate(readableWorldPos);
        }
        if (readableSDF != sdfTexture)
        {
            DestroyImmediate(readableSDF);
        }
        if (readableDirection != directionTexture)
        {
            DestroyImmediate(readableDirection);
        }
        if (readableDiscriminant != discriminantTexture)
        {
            DestroyImmediate(readableDiscriminant);
        }

        SaveJumpTextureToUVDirectory();

        Debug.Log("UV岛桥接贴图生成完成!");
    }

    private Texture2D GetReadableTexture(Texture2D source)
    {
        string assetPath = AssetDatabase.GetAssetPath(source);

        if (!string.IsNullOrEmpty(assetPath))
        {
            TextureImporter importer = AssetImporter.GetAtPath(assetPath) as TextureImporter;
            if (importer != null && importer.isReadable)
            {
                return source;
            }
        }

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

    private void SaveJumpTextureToUVDirectory()
    {
        if (jumpTexture2D == null || sdfTexture == null)
        {
            Debug.LogError("没有可保存的桥接贴图!");
            return;
        }

        string sdfPath = AssetDatabase.GetAssetPath(sdfTexture);
        if (string.IsNullOrEmpty(sdfPath))
        {
            Debug.LogError("无法获取SDF贴图路径!");
            return;
        }

        string directory = System.IO.Path.GetDirectoryName(sdfPath);
        string fileName = System.IO.Path.GetFileNameWithoutExtension(sdfPath);
        string savePath = $"{directory}/{fileName}_Jump.png";

        byte[] pngData = jumpTexture2D.EncodeToPNG();
        System.IO.File.WriteAllBytes(savePath, pngData);
        AssetDatabase.Refresh();

        Debug.Log($"桥接贴图已保存到: {savePath}");
    }

    private void OnDestroy()
    {
        if (jumpTextureRT != null)
        {
            jumpTextureRT.Release();
            jumpTextureRT = null;
        }
        if (blurTempRT != null)
        {
            blurTempRT.Release();
            blurTempRT = null;
        }
        if (jumpTexture2D != null)
        {
            DestroyImmediate(jumpTexture2D);
        }
    }
}
