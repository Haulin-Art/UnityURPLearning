using UnityEngine;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering;

[ExecuteAlways]
public class HiZGenerationFeature : ScriptableRendererFeature
{
    [Header("Hi-Z Settings")]
    [SerializeField]
    [Tooltip("降采样级别：1=无降采样，2=2x2降采样，4=4x4降采样")]
    private DownsampleLevel downsampleLevel = DownsampleLevel.x2;

    [SerializeField]
    [Range(1, 10)]
    [Tooltip("最大Mip层级数量")]
    private int maxMipCount = 10;

    [SerializeField]
    [Tooltip("深度纹理格式")]
    private RenderTextureFormat depthFormat = RenderTextureFormat.RFloat;

    [SerializeField]
    [Tooltip("纹理过滤模式")]
    private FilterMode filterMode = FilterMode.Point;

    [SerializeField]
    [Tooltip("纹理包裹模式")]
    private TextureWrapMode wrapMode = TextureWrapMode.Clamp;

    [SerializeField]
    [Tooltip("渲染Pass执行时机")]
    private RenderPassEvent renderPassEvent = RenderPassEvent.AfterRenderingTransparents;

    [Header("Resources")]
    [SerializeField]
    [Tooltip("Compute Shader用于深度复制和Hi-Z生成")]
    private ComputeShader hiZComputeShader;

    [SerializeField]
    [Tooltip("调试显示材质")]
    private Material debugMaterial;

    [Header("Debug")]
    [SerializeField]
    [Tooltip("调试步骤：用于逐步检查Hi-Z生成流程")]
    private DebugStep debugStep = DebugStep.CopyDepth;

    [SerializeField]
    [Range(0, 9)]
    [Tooltip("调试显示的Mip层级（仅在ShowMipLevel模式下有效）")]
    private int debugMipLevel = 0;

    private HiZGenerationPass hiZPass;

    public enum DownsampleLevel
    {
        x1 = 1,
        x2 = 2,
        x4 = 4,
    }

    public enum DebugStep
    {
        CopyDepth,
        ShowCopiedDepth,
        GenerateAllMips,
        ShowMipLevel,
    }

    public override void Create()
    {
        hiZPass = new HiZGenerationPass(
            debugStep, 
            debugMipLevel, 
            maxMipCount,
            (int)downsampleLevel,
            depthFormat, 
            filterMode,
            wrapMode,
            hiZComputeShader, 
            debugMaterial
        );
        hiZPass.renderPassEvent = renderPassEvent;
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(hiZPass);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            hiZPass?.Dispose();
        }
    }

    public RTHandle GetHiZDepthRT()
    {
        return hiZPass?.GetHiZDepthRT();
    }

    public RTHandle GetHiZMipRT(int level)
    {
        return hiZPass?.GetHiZMipRT(level);
    }

    public int GetMipCount()
    {
        return hiZPass?.GetMipCount() ?? 0;
    }

    public int GetMaxMipCount()
    {
        return maxMipCount;
    }

    public int GetDownsampleFactor()
    {
        return (int)downsampleLevel;
    }
}
