using UnityEngine;

/// <summary>
/// 大气散射全景天空贴图生成器
/// 使用Compute Shader计算大气散射并输出到指定的RenderTexture
/// </summary>
[ExecuteInEditMode]
public class AtmosScatteringPanoramaGenerator : MonoBehaviour
{
    [Header("输出设置")]
    [Tooltip("输出的RenderTexture，必须是启用随机写入的ARGBFloat或ARGBHalf格式")]
    public RenderTexture outputTexture;

    [Header("Compute Shader")]
    [Tooltip("大气散射Compute Shader")]
    public ComputeShader atmosComputeShader;

    [Header("大气参数")]
    [Tooltip("整体缩放")]
    public float totalScale = 1f;
    [Tooltip("行星半径(米)")]
    public float planetRadius = 6371000f;
    [Tooltip("大气层厚度(米)")]
    public float atmosphereHeight = 100000f;
    [Tooltip("海拔高度(千米)")]
    public float altitude = 0f;

    [Header("大气密度参数")]
    [Tooltip("瑞利散射高度(米)")]
    public float rayleighScaleHeight = 8000f;
    [Tooltip("米氏散射高度(米)")]
    public float mieScaleHeight = 1200f;
    [Tooltip("臭氧层高度(米)")]
    public float ozoneScaleHeight = 25000f;
    [Tooltip("臭氧层中心高度(米)")]
    public float ozoneCenterHeight = 25000f;
    [Tooltip("大气密度强度")]
    [Range(0f, 3f)]
    public float atmosIntensity = 1f;

    [Header("散射系数")]
    [Tooltip("散射强度 (X:瑞利, Y:米氏)")]
    public Vector2 scatterScale = new Vector2(1f, 1f);
    [Tooltip("米氏消光系数")]
    public float mieExtinction = 0.0000025f;

    [Header("相位函数参数")]
    [Tooltip("米氏相位函数G值")]
    [Range(0f, 0.99f)]
    public float mieG = 0.76f;
    [Tooltip("太阳米氏相位函数G值")]
    [Range(0f, 0.999f)]
    public float sunMieG = 0.98f;
    [Tooltip("太阳米氏散射强度")]
    [Range(0f, 10f)]
    public float sunMieIntensity = 1f;

    [Header("太阳参数")]
    [Tooltip("太阳大小")]
    [Range(0.00001f, 0.005f)]
    public float sunSize = 0.001f;
    [Tooltip("太阳颜色")]
    public Color sunColor = Color.white;
    [Tooltip("太阳亮度")]
    public float sunBrightness = 1f;
    [Tooltip("太阳方向（自动从主光源获取，或手动设置）")]
    public Vector3 sunDirection = new Vector3(0f, 1f, 0f);
    [Tooltip("是否自动从主光源获取太阳方向")]
    public bool autoSunDirection = true;

    [Header("采样参数")]
    [Tooltip("视线采样数")]
    [Range(4, 64)]
    public int numSamples = 32;
    [Tooltip("太阳光采样数")]
    [Range(1, 16)]
    public int numSamplesLight = 8;

    [Header("运行设置")]
    [Tooltip("是否每帧更新")]
    public bool updateEveryFrame = false;
    [Tooltip("是否在Start时生成一次")]
    public bool generateOnStart = true;

    private int kernelIndex = -1;
    private bool needsUpdate = true;

    void Start()
    {
        if (generateOnStart)
        {
            Generate();
        }
    }

    void Update()
    {
        // 如果需要每帧更新，或者标记为需要更新
        if (updateEveryFrame || needsUpdate)
        {
            Generate();
            needsUpdate = false;
        }

        // 自动获取太阳方向
        if (autoSunDirection)
        {
            Light mainLight = RenderSettings.sun;
            if (mainLight != null)
            {
                // GetMainLight().direction 返回从物体指向光源的方向
                // 而 transform.forward 是从光源指向物体的方向，需要取反
                sunDirection = -mainLight.transform.forward;
            }
        }
    }

    void OnValidate()
    {
        // 参数改变时标记需要更新
        needsUpdate = true;
    }

    /// <summary>
    /// 手动触发生成
    /// </summary>
    [ContextMenu("Generate")]
    public void Generate()
    {
        // 检查必要资源
        if (outputTexture == null)
        {
            Debug.LogError("输出纹理未设置！");
            return;
        }

        if (atmosComputeShader == null)
        {
            Debug.LogError("Compute Shader未设置！");
            return;
        }

        // 检查输出纹理格式
        if (!outputTexture.enableRandomWrite)
        {
            Debug.LogWarning("输出纹理未启用随机写入，正在自动启用...");
            outputTexture.enableRandomWrite = true;
        }

        // 获取kernel索引
        if (kernelIndex < 0)
        {
            kernelIndex = atmosComputeShader.FindKernel("CSMain");
        }

        // 设置Compute Shader参数
        SetComputeShaderParameters();

        // 计算线程组数量
        int threadGroupsX = Mathf.CeilToInt((float)outputTexture.width / 8f);
        int threadGroupsY = Mathf.CeilToInt((float)outputTexture.height / 8f);

        // 执行Compute Shader
        atmosComputeShader.Dispatch(kernelIndex, threadGroupsX, threadGroupsY, 1);
    }

    /// <summary>
    /// 设置Compute Shader参数
    /// </summary>
    private void SetComputeShaderParameters()
    {
        // 输出纹理
        atmosComputeShader.SetTexture(kernelIndex, "_OutputTex", outputTexture);

        // 大气参数
        atmosComputeShader.SetFloat("_TotalScale", totalScale);
        atmosComputeShader.SetFloat("_PlanetRadius", planetRadius);
        atmosComputeShader.SetFloat("_AtmosphereHeight", atmosphereHeight);
        atmosComputeShader.SetFloat("_Altitude", altitude);

        // 大气密度参数
        atmosComputeShader.SetFloat("_RayleighScaleHeight", rayleighScaleHeight);
        atmosComputeShader.SetFloat("_MieScaleHeight", mieScaleHeight);
        atmosComputeShader.SetFloat("_OzoneScaleHeight", ozoneScaleHeight);
        atmosComputeShader.SetFloat("_OzoneCenterHeight", ozoneCenterHeight);
        atmosComputeShader.SetFloat("_AtmosIntensity", atmosIntensity);

        // 散射系数
        atmosComputeShader.SetVector("_ScatterScale", scatterScale);
        atmosComputeShader.SetFloat("_MieExtinction", mieExtinction);

        // 相位函数参数
        atmosComputeShader.SetFloat("_MieG", mieG);
        atmosComputeShader.SetFloat("_SunMieG", sunMieG);
        atmosComputeShader.SetFloat("_SunMieIntensity", sunMieIntensity);

        // 太阳参数
        atmosComputeShader.SetFloat("_SunSize", sunSize);
        atmosComputeShader.SetVector("_SunColor", new Vector3(sunColor.r, sunColor.g, sunColor.b));
        atmosComputeShader.SetFloat("_SunBrightness", sunBrightness);
        atmosComputeShader.SetVector("_SunDirection", sunDirection.normalized);

        // 采样参数
        atmosComputeShader.SetInt("_NumSamples", numSamples);
        atmosComputeShader.SetInt("_NumSamplesLight", numSamplesLight);

        // 纹理尺寸
        atmosComputeShader.SetInt("_TexWidth", outputTexture.width);
        atmosComputeShader.SetInt("_TexHeight", outputTexture.height);
    }

    /// <summary>
    /// 创建默认的输出纹理
    /// </summary>
    [ContextMenu("Create Default Output Texture")]
    public void CreateDefaultOutputTexture()
    {
        outputTexture = new RenderTexture(2048, 1024, 0, RenderTextureFormat.ARGBHalf);
        outputTexture.enableRandomWrite = true;
        outputTexture.name = "AtmosScatteringPanorama";
        outputTexture.wrapMode = TextureWrapMode.Repeat;
        outputTexture.filterMode = FilterMode.Bilinear;
        outputTexture.Create();
    }
}
