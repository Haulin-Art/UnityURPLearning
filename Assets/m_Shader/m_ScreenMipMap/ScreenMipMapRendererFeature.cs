using UnityEngine;
using UnityEngine.Rendering.Universal;
using System.Collections.Generic;
using UnityEngine.Rendering;

/// <summary>
/// 屏幕Mipmap渲染器特性
/// 用于生成带有Mipmap层级的降采样屏幕不透明物体纹理
/// </summary>
[ExecuteAlways]
public class ScreenMipMapRendererFeature : ScriptableRendererFeature
{
    [SerializeField]
    [Tooltip("降采样质量：Low=不降采样，Medium=2倍降采样，High=4倍降采样")]
    private DownSampleQuality downSampleQuality = DownSampleQuality.Medium;
    
    [SerializeField]
    [Range(1, 8)]
    [Tooltip("Mipmap层级数量，层级越多越模糊，但占用更多内存")]
    private int mipLevelCount = 4;
    
    [SerializeField]
    [Tooltip("渲染纹理格式，ARGBHalf提供较好的质量，也可选择其他格式以优化性能")]
    private RenderTextureFormat rtFormat = RenderTextureFormat.ARGBHalf;
    
    [SerializeField]
    [Tooltip("纹理过滤模式：Point=最近邻采样，Bilinear=双线性插值，Trilinear=三线性插值")]
    private FilterMode filterMode = FilterMode.Bilinear;
    
    [SerializeField]
    [Tooltip("是否启用预处理：在生成Mipmap前对纹理进行自定义处理")]
    private bool enablePreProcess = false;
    
    [SerializeField]
    [Tooltip("预处理材质：用于在生成Mipmap前对纹理进行自定义处理")]
    private Material preProcessMaterial;
    
    private ScreenMipMapPass screenMipMapPass;
    
    /// <summary>
    /// 降采样质量枚举
    /// </summary>
    public enum DownSampleQuality
    {
        Low = 1,
        Medium = 2,
        High = 4
    }
    
    /// <summary>
    /// 创建渲染Pass
    /// 设置Pass在不透明物体渲染后执行
    /// </summary>
    public override void Create()
    {
        screenMipMapPass = new ScreenMipMapPass(downSampleQuality, mipLevelCount, rtFormat, filterMode, enablePreProcess, preProcessMaterial);
        screenMipMapPass.renderPassEvent = RenderPassEvent.AfterRenderingOpaques;
    }
    
    /// <summary>
    /// 将Pass添加到渲染队列
    /// </summary>
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(screenMipMapPass);
    }
    
    /// <summary>
    /// 清理资源
    /// </summary>
    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            screenMipMapPass?.Dispose();
        }
    }
    
    /// <summary>
    /// 获取生成的屏幕Mipmap RT
    /// 可供其他Shader通过全局纹理变量使用
    /// </summary>
    public RTHandle GetScreenMipMapRT()
    {
        return screenMipMapPass?.GetScreenMipMapRT();
    }
    
    /// <summary>
    /// 获取Mipmap层级数量
    /// </summary>
    public int GetMipLevelCount()
    {
        return mipLevelCount;
    }
}
