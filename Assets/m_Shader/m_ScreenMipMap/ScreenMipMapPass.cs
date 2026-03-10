using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

/// <summary>
/// 屏幕Mipmap渲染Pass
/// 直接在降采样分辨率下渲染不透明物体，并生成Mipmap层级
/// </summary>
public class ScreenMipMapPass : ScriptableRenderPass
{
    private ScreenMipMapRendererFeature.DownSampleQuality downSampleQuality;
    private int mipLevelCount;
    private RenderTextureFormat rtFormat;
    private FilterMode filterMode;
    private bool enablePreProcess;
    private Material preProcessMaterial;
    
    private RTHandle screenMipMapRT;
    private RTHandle tempDepthRT;
    private RTHandle tempColorRT;
    
    private List<ShaderTagId> shaderTagIds = new List<ShaderTagId>();
    
    /// <summary>
    /// 构造函数：初始化Pass参数和Shader标签列表
    /// </summary>
    public ScreenMipMapPass(ScreenMipMapRendererFeature.DownSampleQuality quality, int mipCount, 
        RenderTextureFormat format, FilterMode filter, bool enablePreProcess, Material preProcessMat)
    {
        downSampleQuality = quality;
        mipLevelCount = mipCount;
        rtFormat = format;
        filterMode = filter;
        this.enablePreProcess = enablePreProcess;
        preProcessMaterial = preProcessMat;
        
        shaderTagIds.Add(new ShaderTagId("SRPDefaultUnlit"));
        shaderTagIds.Add(new ShaderTagId("UniversalForward"));
        shaderTagIds.Add(new ShaderTagId("UniversalForwardOnly"));
        shaderTagIds.Add(new ShaderTagId("LightweightForward"));
    }
    
    /// <summary>
    /// 相机设置：创建降分辨率的Color RT和临时Depth RT
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
        
        if (enablePreProcess && preProcessMaterial != null)
        {
            RenderTextureDescriptor tempColorDesc = new RenderTextureDescriptor(
                downSampledWidth, 
                downSampledHeight, 
                rtFormat, 
                0
            )
            {
                depthBufferBits = 0
            };
            RenderingUtils.ReAllocateIfNeeded(ref tempColorRT, tempColorDesc, filterMode, TextureWrapMode.Clamp, name: "_TempColorRT");
        }
        
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


        Camera camera = renderingData.cameraData.camera;
        // 1. 传递ro：相机世界空间位置
        preProcessMaterial.SetVector("_CameraWorldPos", camera.transform.position);
        // 2. 传递逆视投影矩阵（用于Shader中转世界空间）
        Matrix4x4 viewProjMatrix = camera.projectionMatrix * camera.worldToCameraMatrix;
        Matrix4x4 invViewProjMatrix = viewProjMatrix.inverse;
        preProcessMaterial.SetMatrix("_InvViewProj", invViewProjMatrix);        
    }
    
    /// <summary>
    /// 执行渲染：
    /// 1. 渲染不透明物体到颜色Mipmap RT
    /// 2. 如果启用预处理，使用材质对纹理进行Blit处理
    /// 3. 生成所有Mipmap层级并设置为全局纹理
    /// </summary>
    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        if (screenMipMapRT == null || tempDepthRT == null)
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
        }
        
        context.ExecuteCommandBuffer(cmd);
        cmd.Clear();
        
        if (enablePreProcess && preProcessMaterial != null && tempColorRT != null)
        {
            using (new ProfilingScope(cmd, new ProfilingSampler("ScreenMipMap PreProcess")))
            {
                // 必须得都指定Mat以及Pass Index，不然会报错，就是材质的关键字空间不一致，可以在shader当中写两个Pass
                // 第一个Pass用于预处理，第二个Pass只用于采样_MainTex，不进行任何处理
                // 而且_MainTex必须得指定，不然会报错，就是材质的关键字空间不一致，可以在shader当中写两个Pass
                // 还有_MainTex不能写在Properties当中，不然会报错，就是材质的关键字空间不一致
                preProcessMaterial.SetTexture("_MainTex", screenMipMapRT);
                preProcessMaterial.SetTexture("_CameraDepthTexture", tempDepthRT);
                cmd.Blit(screenMipMapRT, tempColorRT, preProcessMaterial, 0);
                cmd.Blit(tempColorRT, screenMipMapRT, preProcessMaterial, 1);
            }
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
        }
        
        using (new ProfilingScope(cmd, new ProfilingSampler("ScreenMipMap GenerateMips")))
        {
            cmd.GenerateMips(screenMipMapRT);
            cmd.SetGlobalTexture("_ScreenMipMapRT", screenMipMapRT);
        }
        
        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
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
        tempDepthRT?.Release();
        tempColorRT?.Release();
    }
    
    /// <summary>
    /// 获取生成的屏幕Mipmap RT，供其他Shader使用
    /// </summary>
    public RTHandle GetScreenMipMapRT()
    {
        return screenMipMapRT;
    }
}
