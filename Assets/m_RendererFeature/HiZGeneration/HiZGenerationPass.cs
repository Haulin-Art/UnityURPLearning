using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

/// <summary>
/// Hi-Z（Hierarchical Z-Buffer）生成渲染Pass
/// 用于生成层次化深度缓冲，支持遮挡剔除等优化技术
/// </summary>
public class HiZGenerationPass : ScriptableRenderPass
{
    private HiZGenerationFeature.DebugStep debugStep;
    private int debugMipLevel;
    private int maxMipCount;
    private int downsampleFactor;
    private RenderTextureFormat depthFormat;
    private FilterMode filterMode;
    private TextureWrapMode wrapMode;
    private ComputeShader hiZComputeShader;
    private Material debugMaterial;

    private RTHandle hiZDepthRT;
    private RTHandle[] hiZMipRTs;
    private int mipCount;
    
    private int kernelGenerateMip;

    private const string PROFILER_TAG = "HiZ Generation";

    /// <summary>
    /// 构造函数：初始化Hi-Z生成Pass
    /// </summary>
    public HiZGenerationPass(
        HiZGenerationFeature.DebugStep step, 
        int debugMip, 
        int maxMip,
        int downsample,
        RenderTextureFormat format, 
        FilterMode filter,
        TextureWrapMode wrap,
        ComputeShader cs, 
        Material debugMat)
    {
        debugStep = step;
        debugMipLevel = debugMip;
        maxMipCount = maxMip;
        downsampleFactor = downsample;
        depthFormat = format;
        filterMode = filter;
        wrapMode = wrap;
        hiZComputeShader = cs;
        debugMaterial = debugMat;

        hiZMipRTs = new RTHandle[maxMipCount];

        if (hiZComputeShader != null)
        {
            kernelGenerateMip = hiZComputeShader.FindKernel("GenerateMip");
        }
    }

    /// <summary>
    /// 相机设置时调用：分配和初始化渲染纹理资源
    /// </summary>
    public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
    {
        int screenWidth = renderingData.cameraData.camera.pixelWidth;
        int screenHeight = renderingData.cameraData.camera.pixelHeight;

        int width = Mathf.Max(1, screenWidth / downsampleFactor);
        int height = Mathf.Max(1, screenHeight / downsampleFactor);

        RenderTextureDescriptor depthDesc = new RenderTextureDescriptor(
            width, height, depthFormat, 0
        )
        {
            enableRandomWrite = true,
            useMipMap = true,
            autoGenerateMips = false,
            depthBufferBits = 0
        };

        RenderingUtils.ReAllocateIfNeeded(ref hiZDepthRT, depthDesc, 
            filterMode, wrapMode, name: "_HiZDepthRT");

        mipCount = Mathf.CeilToInt(Mathf.Log(Mathf.Max(width, height), 2)) + 1;
        mipCount = Mathf.Min(mipCount, maxMipCount);

        int currentWidth = width;
        int currentHeight = height;

        for (int i = 0; i < mipCount; i++)
        {
            currentWidth = Mathf.Max(1, currentWidth / 2);
            currentHeight = Mathf.Max(1, currentHeight / 2);

            RenderTextureDescriptor mipDesc = new RenderTextureDescriptor(
                currentWidth, currentHeight, depthFormat, 0
            )
            {
                enableRandomWrite = true,
                depthBufferBits = 0
            };

            RenderingUtils.ReAllocateIfNeeded(ref hiZMipRTs[i], mipDesc, 
                filterMode, wrapMode, name: $"_HiZMip{i}RT");
        }
    }

    /// <summary>
    /// 执行渲染Pass：根据调试步骤执行不同的Hi-Z生成流程
    /// </summary>
    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        if (hiZDepthRT == null || hiZComputeShader == null)
            return;

        CommandBuffer cmd = CommandBufferPool.Get(PROFILER_TAG);

        using (new ProfilingScope(cmd, new ProfilingSampler("HiZ Generation")))
        {
            switch (debugStep)
            {
                case HiZGenerationFeature.DebugStep.CopyDepth:
                    ExecuteCopyDepth(cmd, ref renderingData);
                    break;
                case HiZGenerationFeature.DebugStep.ShowCopiedDepth:
                    ExecuteCopyDepth(cmd, ref renderingData);
                    ExecuteDebugShow(cmd, ref renderingData, hiZDepthRT);
                    break;
                case HiZGenerationFeature.DebugStep.GenerateAllMips:
                    ExecuteCopyDepth(cmd, ref renderingData);
                    ExecuteGenerateAllMips(cmd, ref renderingData);
                    SetGlobalTextures(cmd);
                    break;
                case HiZGenerationFeature.DebugStep.ShowMipLevel:
                    ExecuteCopyDepth(cmd, ref renderingData);
                    ExecuteGenerateAllMips(cmd, ref renderingData);
                    SetGlobalTextures(cmd);
                    int mipIndex = Mathf.Clamp(debugMipLevel, 0, mipCount - 1);
                    ExecuteDebugShow(cmd, ref renderingData, hiZMipRTs[mipIndex]);
                    break;
            }
        }

        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
    }

    /// <summary>
    /// 复制相机深度缓冲到Hi-Z深度纹理
    /// </summary>
    private void ExecuteCopyDepth(CommandBuffer cmd, ref RenderingData renderingData)
    {
        RTHandle cameraDepth = renderingData.cameraData.renderer.cameraDepthTargetHandle;
        cmd.Blit(cameraDepth, hiZDepthRT);
    }

    /// <summary>
    /// 生成所有Hi-Z Mip层级
    /// 每个层级取上一层级2x2像素的最大深度值，形成层次化深度结构
    /// </summary>
    private void ExecuteGenerateAllMips(CommandBuffer cmd, ref RenderingData renderingData)
    {
        int screenWidth = renderingData.cameraData.camera.pixelWidth;
        int screenHeight = renderingData.cameraData.camera.pixelHeight;

        int width = Mathf.Max(1, screenWidth / downsampleFactor);
        int height = Mathf.Max(1, screenHeight / downsampleFactor);

        RTHandle sourceRT = hiZDepthRT;
        int srcWidth = width;
        int srcHeight = height;

        for (int i = 0; i < mipCount; i++)
        {
            int mipWidth = Mathf.Max(1, srcWidth / 2);
            int mipHeight = Mathf.Max(1, srcHeight / 2);

            cmd.SetComputeTextureParam(hiZComputeShader, kernelGenerateMip, "_Result", hiZMipRTs[i]);
            cmd.SetComputeTextureParam(hiZComputeShader, kernelGenerateMip, "_HiZSource", sourceRT);
            cmd.SetComputeIntParam(hiZComputeShader, "_SourceWidth", srcWidth);
            cmd.SetComputeIntParam(hiZComputeShader, "_SourceHeight", srcHeight);

            int threadGroupsX = Mathf.CeilToInt(mipWidth / 8.0f);
            int threadGroupsY = Mathf.CeilToInt(mipHeight / 8.0f);

            cmd.DispatchCompute(hiZComputeShader, kernelGenerateMip, threadGroupsX, threadGroupsY, 1);

            sourceRT = hiZMipRTs[i];
            srcWidth = mipWidth;
            srcHeight = mipHeight;
        }
    }

    /// <summary>
    /// 将Hi-Z纹理注册为全局Shader变量，供其他Pass或Shader使用
    /// _HiZDepthTexture: 原始深度副本
    /// _HiZMip0Texture ~ _HiZMipNTexture: 各级下采样深度纹理
    /// </summary>
    private void SetGlobalTextures(CommandBuffer cmd)
    {
        cmd.SetGlobalTexture("_HiZDepthTexture", hiZDepthRT);
        for (int i = 0; i < mipCount; i++)
        {
            cmd.SetGlobalTexture($"_HiZMip{i}Texture", hiZMipRTs[i]);
        }
    }

    /// <summary>
    /// 调试显示：将指定的Hi-Z纹理Blit到屏幕
    /// </summary>
    private void ExecuteDebugShow(CommandBuffer cmd, ref RenderingData renderingData, RTHandle sourceRT)
    {
        if (debugMaterial == null || sourceRT == null)
            return;

        RTHandle cameraTarget = renderingData.cameraData.renderer.cameraColorTargetHandle;
        
        debugMaterial.SetTexture("_HiZDepthTex", sourceRT);
        cmd.Blit(sourceRT, cameraTarget, debugMaterial);
    }

    public override void OnCameraCleanup(CommandBuffer cmd)
    {
    }

    /// <summary>
    /// 释放渲染纹理资源
    /// </summary>
    public void Dispose()
    {
        hiZDepthRT?.Release();
        for (int i = 0; i < hiZMipRTs.Length; i++)
        {
            hiZMipRTs[i]?.Release();
        }
    }

    /// <summary>
    /// 获取Hi-Z深度纹理（原始副本）
    /// </summary>
    public RTHandle GetHiZDepthRT()
    {
        return hiZDepthRT;
    }

    /// <summary>
    /// 获取指定层级的Hi-Z Mip纹理
    /// </summary>
    public RTHandle GetHiZMipRT(int level)
    {
        if (level >= 0 && level < hiZMipRTs.Length)
            return hiZMipRTs[level];
        return null;
    }

    /// <summary>
    /// 获取实际生成的Mip层级数量
    /// </summary>
    public int GetMipCount()
    {
        return mipCount;
    }
}
