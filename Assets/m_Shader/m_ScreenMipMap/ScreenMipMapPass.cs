using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

/// <summary>
/// 屏幕Mipmap渲染Pass
/// 直接在降采样分辨率下渲染不透明物体，并生成Mipmap层级
/// 同时生成深度Mipmap（View Space Z）
/// </summary>
public class ScreenMipMapPass : ScriptableRenderPass
{
    private ScreenMipMapRendererFeature.DownSampleQuality downSampleQuality;
    private int mipLevelCount;
    private RenderTextureFormat rtFormat;
    private FilterMode filterMode;
    
    private RTHandle screenMipMapRT;
    private RTHandle screenMipMapDepthRT;
    private RTHandle tempDepthRT;
    
    private List<ShaderTagId> shaderTagIds = new List<ShaderTagId>();
    private Material depthOverrideMaterial;
    
    /// <summary>
    /// 构造函数：初始化Pass参数和Shader标签列表
    /// </summary>
    public ScreenMipMapPass(ScreenMipMapRendererFeature.DownSampleQuality quality, int mipCount, 
        RenderTextureFormat format, FilterMode filter, Material depthOverrideMat)
    {
        downSampleQuality = quality;
        mipLevelCount = mipCount;
        rtFormat = format;
        filterMode = filter;
        depthOverrideMaterial = depthOverrideMat;
        
        shaderTagIds.Add(new ShaderTagId("SRPDefaultUnlit"));
        shaderTagIds.Add(new ShaderTagId("UniversalForward"));
        shaderTagIds.Add(new ShaderTagId("UniversalForwardOnly"));
        shaderTagIds.Add(new ShaderTagId("LightweightForward"));
    }
    
    /// <summary>
    /// 相机设置：创建降分辨率的Color RT和Depth RT
    /// RT配置为支持Mipmap，但不自动生成（手动调用GenerateMips）
    /// </summary>
    public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
    {
        int screenWidth = renderingData.cameraData.camera.pixelWidth;
        int screenHeight = renderingData.cameraData.camera.pixelHeight;
        
        int downSampleFactor = (int)downSampleQuality;
        int downSampledWidth = Mathf.Max(1, screenWidth / downSampleFactor);
        int downSampledHeight = Mathf.Max(1, screenHeight / downSampleFactor);
        
        RenderTextureDescriptor colorDesc = new RenderTextureDescriptor(
            downSampledWidth, 
            downSampledHeight, 
            rtFormat, 
            0
        )
        {
            useMipMap = true,
            autoGenerateMips = false,
            mipCount = mipLevelCount,
            depthBufferBits = 0
        };
        RenderingUtils.ReAllocateIfNeeded(ref screenMipMapRT, colorDesc, filterMode, TextureWrapMode.Clamp, name: "_ScreenMipMapRT");
        
        RenderTextureDescriptor depthDesc = new RenderTextureDescriptor(
            downSampledWidth, 
            downSampledHeight, 
            RenderTextureFormat.RFloat, 
            0
        )
        {
            useMipMap = true,
            autoGenerateMips = false,
            mipCount = mipLevelCount,
            depthBufferBits = 0
        };
        RenderingUtils.ReAllocateIfNeeded(ref screenMipMapDepthRT, depthDesc, filterMode, TextureWrapMode.Clamp, name: "_ScreenMipMapDepthRT");
        
        RenderTextureDescriptor tempDepthDesc = new RenderTextureDescriptor(
            downSampledWidth, 
            downSampledHeight, 
            RenderTextureFormat.Depth, 
            24
        )
        {
            depthBufferBits = 24
        };
        RenderingUtils.ReAllocateIfNeeded(ref tempDepthRT, tempDepthDesc, filterMode, TextureWrapMode.Clamp, name: "_TempDepthRT");
        
        ConfigureTarget(screenMipMapRT, tempDepthRT);
        ConfigureClear(ClearFlag.All, Color.black);
    }
    
    /// <summary>
    /// 执行渲染：
    /// 1. 渲染不透明物体到颜色Mipmap RT
    /// 2. 使用覆盖材质渲染深度到深度Mipmap RT
    /// 3. 生成所有Mipmap层级并设置为全局纹理
    /// </summary>
    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        if (screenMipMapRT == null || screenMipMapDepthRT == null || tempDepthRT == null)
            return;
        
        CommandBuffer cmd = CommandBufferPool.Get("ScreenMipMap");
        
        using (new ProfilingScope(cmd, new ProfilingSampler("ScreenMipMap Color")))
        {
            cmd.SetRenderTarget(screenMipMapRT, tempDepthRT);
            cmd.ClearRenderTarget(true, true, Color.black);
            
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            
            DrawingSettings drawingSettings = CreateDrawingSettings(shaderTagIds, ref renderingData, 
                renderingData.cameraData.defaultOpaqueSortFlags);
            
            FilteringSettings filteringSettings = new FilteringSettings(RenderQueueRange.opaque);
            
            context.DrawRenderers(renderingData.cullResults, ref drawingSettings, ref filteringSettings);
            
            cmd.GenerateMips(screenMipMapRT);
            cmd.SetGlobalTexture("_ScreenMipMapRT", screenMipMapRT);
        }
        
        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
        
        /*
        if (depthOverrideMaterial == null)
            return;
        
        cmd = CommandBufferPool.Get("ScreenMipMapDepth");
        
        using (new ProfilingScope(cmd, new ProfilingSampler("ScreenMipMap Depth")))
        {
            cmd.SetRenderTarget(screenMipMapDepthRT, tempDepthRT);
            cmd.ClearRenderTarget(true, true, Color.black);
            
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            
            DrawingSettings depthDrawingSettings = CreateDrawingSettings(shaderTagIds, ref renderingData, 
                renderingData.cameraData.defaultOpaqueSortFlags);
            depthDrawingSettings.overrideMaterial = depthOverrideMaterial;
            
            FilteringSettings filteringSettings = new FilteringSettings(RenderQueueRange.opaque);
            
            context.DrawRenderers(renderingData.cullResults, ref depthDrawingSettings, ref filteringSettings);
            
            cmd.GenerateMips(screenMipMapDepthRT);
            cmd.SetGlobalTexture("_ScreenMipMapDepthRT", screenMipMapDepthRT);
        }
        /*
        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
        */
    }
    
    public override void OnCameraCleanup(CommandBuffer cmd)
    {
    }
    
    /// <summary>
    /// 释放RT资源
    /// </summary>
    public void Dispose()
    {
        screenMipMapRT?.Release();
        screenMipMapDepthRT?.Release();
        tempDepthRT?.Release();
    }
    
    /// <summary>
    /// 获取生成的屏幕Mipmap RT，供其他Shader使用
    /// </summary>
    public RTHandle GetScreenMipMapRT()
    {
        return screenMipMapRT;
    }
    
    /// <summary>
    /// 获取生成的屏幕深度Mipmap RT，供其他Shader使用
    /// </summary>
    public RTHandle GetScreenMipMapDepthRT()
    {
        return screenMipMapDepthRT;
    }
}
