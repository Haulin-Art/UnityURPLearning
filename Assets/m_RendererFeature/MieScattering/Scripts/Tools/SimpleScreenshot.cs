using UnityEngine;
using System.Collections;
using System.IO;
using System;

public class SimpleScreenshot : MonoBehaviour
{
    [Header("截图设置")]
    [Tooltip("在Assets文件夹下的相对路径，例如: 'm_RendererFeature/MieScattering/ScreenShots'")]
    public string folderPath = "ScreenShots";
    
    [Tooltip("截图分辨率缩放")]
    [Range(1, 4)]
    public int resolutionScale = 1;
    
    [Tooltip("截图格式")]
    public ScreenshotFormat format = ScreenshotFormat.PNG;
    
    [Header("触发方式")]
    [Tooltip("勾选后立即截图")]
    public bool captureScreenshot = false;

    [Header("可选设置")]
    public Camera targetCamera;
    public bool hideUI = false;

    private bool isTakingScreenshot = false;
    private string actualSavePath;

    public enum ScreenshotFormat
    {
        PNG,
        JPG
    }

    void Start()
    {
        // 关键修复：正确处理路径
        SetupSavePath();
    }

    void Update()
    {
        if (captureScreenshot && !isTakingScreenshot)
        {
            captureScreenshot = false;
            StartCoroutine(TakeScreenshotCoroutine());
        }
    }

    /// <summary>
    /// 设置正确的保存路径
    /// </summary>
    private void SetupSavePath()
    {
        try
        {
            // 1. 清理路径：移除开头的"Assets/"和多余斜杠
            string cleanPath = folderPath.Trim();
            
            // 移除开头的"Assets/"或"Assets\"
            if (cleanPath.StartsWith("Assets/", StringComparison.OrdinalIgnoreCase) || 
                cleanPath.StartsWith("Assets\\", StringComparison.OrdinalIgnoreCase))
            {
                cleanPath = cleanPath.Substring(7); // 移除"Assets/"（7个字符）
            }
            
            // 2. 使用Path.Combine构建路径，避免重复的"Assets"
            // Application.dataPath 已经是 ".../YourProject/Assets"
            actualSavePath = Path.Combine(Application.dataPath, cleanPath);
            
            // 3. 规范化路径（统一斜杠方向）
            actualSavePath = Path.GetFullPath(actualSavePath);
            
            // 4. 创建目录（如果不存在）
            if (!Directory.Exists(actualSavePath))
            {
                Directory.CreateDirectory(actualSavePath);
                Debug.Log($"创建截图目录: {actualSavePath}");
            }
            
            // 5. 显示正确的路径
            Debug.Log($"截图将保存到: {actualSavePath}");
        }
        catch (Exception e)
        {
            Debug.LogError($"路径设置失败: {e.Message}");
            // 如果出错，使用默认位置
            actualSavePath = Application.dataPath;
        }
    }

    /// <summary>
    /// 手动触发截图
    /// </summary>
    public void TakeScreenshot()
    {
        if (!isTakingScreenshot)
        {
            StartCoroutine(TakeScreenshotCoroutine());
        }
    }

    private IEnumerator TakeScreenshotCoroutine()
    {
        isTakingScreenshot = true;
        
        // 隐藏UI逻辑
        GameObject[] uiElements = null;
        if (hideUI)
        {
            uiElements = GameObject.FindGameObjectsWithTag("UI");
            foreach (var ui in uiElements) ui.SetActive(false);
            yield return null;
        }

        yield return new WaitForEndOfFrame();

        Camera cameraToUse = targetCamera != null ? targetCamera : Camera.main;
        if (cameraToUse == null)
        {
            Debug.LogError("未找到可用相机！");
            isTakingScreenshot = false;
            yield break;
        }

        try
        {
            int width = Screen.width * resolutionScale;
            int height = Screen.height * resolutionScale;
            
            RenderTexture rt = new RenderTexture(width, height, 24);
            cameraToUse.targetTexture = rt;
            cameraToUse.Render();
            
            RenderTexture.active = rt;
            Texture2D screenshot = new Texture2D(width, height, TextureFormat.RGB24, false);
            screenshot.ReadPixels(new Rect(0, 0, width, height), 0, 0);
            screenshot.Apply();
            
            cameraToUse.targetTexture = null;
            RenderTexture.active = null;
            Destroy(rt);

            // 生成文件名
            string filename = GenerateFilename();
            
            // 保存文件
            byte[] bytes = format == ScreenshotFormat.PNG ? 
                screenshot.EncodeToPNG() : screenshot.EncodeToJPG();
            
            File.WriteAllBytes(filename, bytes);
            Destroy(screenshot);

            Debug.Log($"截图已保存: {filename}");
            
            // 在编辑器中刷新项目窗口
            #if UNITY_EDITOR
            UnityEditor.AssetDatabase.Refresh();
            #endif
        }
        catch (Exception e)
        {
            Debug.LogError($"截图失败: {e.Message}");
        }

        // 恢复UI显示
        if (hideUI && uiElements != null)
        {
            foreach (var ui in uiElements) ui.SetActive(true);
        }

        isTakingScreenshot = false;
    }

    private string GenerateFilename()
    {
        string timestamp = DateTime.Now.ToString("yyyyMMdd_HHmmss");
        string extension = format == ScreenshotFormat.PNG ? "png" : "jpg";
        string filename = $"Screenshot_{timestamp}.{extension}";
        
        // 使用正确的路径
        return Path.Combine(actualSavePath, filename);
    }
}