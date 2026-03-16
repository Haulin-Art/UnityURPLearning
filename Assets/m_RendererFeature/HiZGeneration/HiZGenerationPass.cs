using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

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
    
    private int kernelCopyDepth;
    private int kernelGenerateMip;

    private const string PROFILER_TAG = "HiZ Generation";

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
            kernelCopyDepth = hiZComputeShader.FindKernel("CopyDepth");
            kernelGenerateMip = hiZComputeShader.FindKernel("GenerateMip");
        }
    }

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
                    break;
                case HiZGenerationFeature.DebugStep.ShowMipLevel:
                    ExecuteCopyDepth(cmd, ref renderingData);
                    ExecuteGenerateAllMips(cmd, ref renderingData);
                    int mipIndex = Mathf.Clamp(debugMipLevel, 0, mipCount - 1);
                    ExecuteDebugShow(cmd, ref renderingData, hiZMipRTs[mipIndex]);
                    break;
            }
        }

        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
    }

    private void ExecuteCopyDepth(CommandBuffer cmd, ref RenderingData renderingData)
    {
        int screenWidth = renderingData.cameraData.camera.pixelWidth;
        int screenHeight = renderingData.cameraData.camera.pixelHeight;

        int width = Mathf.Max(1, screenWidth / downsampleFactor);
        int height = Mathf.Max(1, screenHeight / downsampleFactor);

        cmd.SetComputeTextureParam(hiZComputeShader, kernelCopyDepth, "_Result", hiZDepthRT);
        cmd.SetComputeTextureParam(hiZComputeShader, kernelCopyDepth, "_CameraDepthTexture", 
            renderingData.cameraData.renderer.cameraDepthTargetHandle);
        cmd.SetComputeIntParam(hiZComputeShader, "_SourceWidth", width);
        cmd.SetComputeIntParam(hiZComputeShader, "_SourceHeight", height);
        cmd.SetComputeIntParam(hiZComputeShader, "_DownsampleFactor", downsampleFactor);

        int threadGroupsX = Mathf.CeilToInt(width / 8.0f);
        int threadGroupsY = Mathf.CeilToInt(height / 8.0f);

        cmd.DispatchCompute(hiZComputeShader, kernelCopyDepth, threadGroupsX, threadGroupsY, 1);
    }

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

    public void Dispose()
    {
        hiZDepthRT?.Release();
        for (int i = 0; i < hiZMipRTs.Length; i++)
        {
            hiZMipRTs[i]?.Release();
        }
    }

    public RTHandle GetHiZDepthRT()
    {
        return hiZDepthRT;
    }

    public RTHandle GetHiZMipRT(int level)
    {
        if (level >= 0 && level < hiZMipRTs.Length)
            return hiZMipRTs[level];
        return null;
    }

    public int GetMipCount()
    {
        return mipCount;
    }
}
