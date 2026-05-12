using UnityEngine;

/// <summary>
/// 弹性膜撕裂模拟控制器
/// 基于弹性膜+连续损伤场模型，通过 RaycastTargetDetector 获取 UV 输入
/// 模拟管线：ElasticRelaxation(×N) → DamageEvolution → SourceInput
/// </summary>
public class ElasticTearingController : MonoBehaviour
{
    // ================================================================
    // 文件输入
    // ================================================================
    [Header("文件输入")]
    [Tooltip("弹性撕裂计算着色器 (ElasticTearing.compute)")]
    public ComputeShader computeShader;

    [Tooltip("展示材质（需支持 _DamageTex / _DispTex / _MainTex）")]
    public Material displayMaterial;

    [Tooltip("输出贴图（损伤场）")]
    public RenderTexture outputTexture;

    // ================================================================
    // 交互输入
    // ================================================================
    [Header("交互输入")]
    [Tooltip("射线检测器，获取 UV 位置")]
    public RaycastTargetDetector raycastDetector;

    [Space(10)]
    [Header("流体着色设置")]
    public Material fluidMaterial;
    public Color fluidColor = Color.blue;
    [Range(0.0f, 10.0f)]
    public float fluidTransScale = 1.0f;

    // ================================================================
    // 弹性参数
    // ================================================================
    [Space(10)]
    [Header("弹性参数")]
    [Tooltip("弹簧刚度，越大面料越硬")]
    [Range(1f, 500f)]
    public float stiffness = 80f;

    [Tooltip("松弛因子，影响收敛速度")]
    [Range(0.1f, 1f)]
    public float relaxFactor = 0.5f;

    [Tooltip("回缩强度：控制破洞扩张速度")]
    [Range(0f, 200f)]
    public float retractStrength = 60f;

    [Tooltip("弹性松弛迭代次数")]
    [Range(10, 200)]
    public int relaxIterations = 40;

    // ================================================================
    // 损伤参数
    // ================================================================
    [Space(10)]
    [Header("损伤参数")]
    [Tooltip("应变阈值，超此值开始撕裂")]
    [Range(0.01f, 5f)]
    public float strainThreshold = 0.3f;

    [Tooltip("损伤增长速率")]
    [Range(0f, 200f)]
    public float damageRate = 15f;

    [Tooltip("损伤扩散系数，防边界过锐")]
    [Range(0f, 0.1f)]
    public float damageDiffusion = 0.01f;

    // ================================================================
    // 模拟设置
    // ================================================================
    [Space(10)]
    [Header("模拟设置")]
    [Tooltip("网格分辨率")]
    public int size = 256;

    [Tooltip("时间步长缩放")]
    [Range(0.1f, 2f)]
    public float timeScale = 1f;

    [Tooltip("画笔半径")]
    [Range(0.005f, 0.1f)]
    public float penRadius = 0.02f;

    // ================================================================
    // 内核索引
    // ================================================================
    private int elasticRelaxationKernel;
    private int damageEvolutionKernel;
    private int sourceInputKernel;

    // ================================================================
    // 渲染纹理 (ping-pong)
    // ================================================================
    // 位移场: 2 通道 RGHalf (float2)
    private RenderTexture dispRead;
    private RenderTexture dispWrite;

    // 损伤场: 1 通道 RHalf (float)
    private RenderTexture damageRead;
    private RenderTexture damageWrite;

    // ================================================================
    // 射线检测缓存
    // ================================================================
    private bool isHit = false;
    private Vector2 hitUV = Vector2.zero;
    private Vector2 previousHitUV = Vector2.zero;
    private bool previousIsHit = false;

    // ================================================================
    // Unity 生命周期
    // ================================================================
    private void Start()
    {
        if (computeShader == null)
        {
            Debug.LogError("ElasticTearing: 请指定 ComputeShader！");
            return;
        }

        if (displayMaterial == null)
            Debug.LogWarning("ElasticTearing: 展示材质未设置");

        if (raycastDetector == null)
            Debug.LogWarning("ElasticTearing: 射线检测器未设置");

        FindKernels();
        CreateRenderTextures();
    }

    private void Update()
    {
        SetFluidMat();

        if (computeShader == null) return;

        UpdateRaycastData();
        Simulate();

        if (outputTexture != null)
            Graphics.Blit(damageRead, outputTexture);

        if (displayMaterial != null)
        {
            displayMaterial.SetTexture("_HoleTex", damageRead);
            displayMaterial.SetTexture("_DamageTex", damageRead);
            displayMaterial.SetTexture("_DispTex", dispRead);
            displayMaterial.SetFloat("_TexSize", size);
        }
    }

    private void OnDestroy()
    {
        ReleaseRenderTextures();
    }

    // ================================================================
    // 初始化
    // ================================================================
    private void FindKernels()
    {
        elasticRelaxationKernel = computeShader.FindKernel("ElasticRelaxationKernel");
        damageEvolutionKernel  = computeShader.FindKernel("DamageEvolutionKernel");
        sourceInputKernel      = computeShader.FindKernel("SourceInputKernel");
    }

    private void CreateRenderTextures()
    {
        ReleaseRenderTextures();

        var dispDesc = new RenderTextureDescriptor(size, size, RenderTextureFormat.RGHalf, 0)
        {
            enableRandomWrite = true
        };

        var damageDesc = new RenderTextureDescriptor(size, size, RenderTextureFormat.RHalf, 0)
        {
            enableRandomWrite = true
        };

        dispRead = new RenderTexture(dispDesc) { name = "DispRead" };
        dispRead.Create();
        dispWrite = new RenderTexture(dispDesc) { name = "DispWrite" };
        dispWrite.Create();

        damageRead = new RenderTexture(damageDesc) { name = "DamageRead" };
        damageRead.Create();
        damageWrite = new RenderTexture(damageDesc) { name = "DamageWrite" };
        damageWrite.Create();
    }

    private void ReleaseRenderTextures()
    {
        if (dispRead != null)   { dispRead.Release(); Destroy(dispRead); }
        if (dispWrite != null)  { dispWrite.Release(); Destroy(dispWrite); }
        if (damageRead != null) { damageRead.Release(); Destroy(damageRead); }
        if (damageWrite != null){ damageWrite.Release(); Destroy(damageWrite); }
    }

    // ================================================================
    // 输入
    // ================================================================
    private void UpdateRaycastData()
    {
        previousIsHit = isHit;
        previousHitUV = hitUV;

        if (raycastDetector != null)
            raycastDetector.GetRaycastData(out isHit, out hitUV, out _);
        else
            isHit = false;
    }

    // ================================================================
    // 模拟主循环
    // ================================================================
    private void Simulate()
    {
        int threadGroups = Mathf.CeilToInt(size / 8.0f);
        float scaledDt = Time.deltaTime * timeScale;

        // ── 共享参数 ──
        computeShader.SetFloat("texSize", size);
        computeShader.SetFloat("dt", scaledDt);
        computeShader.SetFloat("stiffness", stiffness);
        computeShader.SetFloat("relaxFactor", relaxFactor);
        computeShader.SetFloat("retractStrength", retractStrength);
        computeShader.SetFloat("strainThreshold", strainThreshold / size); // 归一化到像素单位
        computeShader.SetFloat("damageRate", damageRate);
        computeShader.SetFloat("damageDiffusion", damageDiffusion);

        // ── 画笔输入 ──
        bool pressing = Input.GetMouseButton(0) && isHit;
        computeShader.SetBool("keyDown", pressing);
        computeShader.SetFloat("radius", penRadius);

        Vector2 curUV  = isHit ? hitUV : Vector2.one * -1f;
        Vector2 prevUV = previousIsHit ? previousHitUV : curUV + Vector2.one * 1e-4f;
        computeShader.SetVector("penPos", new Vector4(curUV.x, curUV.y, prevUV.x, prevUV.y));

        // ── ① ElasticRelaxation × N ──
        for (int i = 0; i < relaxIterations; i++)
        {
            computeShader.SetTexture(elasticRelaxationKernel, "DispTex", dispRead);
            computeShader.SetTexture(elasticRelaxationKernel, "DamageTex", damageRead);
            computeShader.SetTexture(elasticRelaxationKernel, "DispWrite", dispWrite);
            computeShader.Dispatch(elasticRelaxationKernel, threadGroups, threadGroups, 1);
            Swap(ref dispRead, ref dispWrite);
        }

        // ── ② DamageEvolution ──
        computeShader.SetTexture(damageEvolutionKernel, "DispTex", dispRead);
        computeShader.SetTexture(damageEvolutionKernel, "DamageTex", damageRead);
        computeShader.SetTexture(damageEvolutionKernel, "DamageWrite", damageWrite);
        computeShader.Dispatch(damageEvolutionKernel, threadGroups, threadGroups, 1);
        Swap(ref damageRead, ref damageWrite);

        // ── ③ SourceInput（同时写 DispWrite 和 DamageWrite） ──
        computeShader.SetTexture(sourceInputKernel, "DispTex", dispRead);
        computeShader.SetTexture(sourceInputKernel, "DamageTex", damageRead);
        computeShader.SetTexture(sourceInputKernel, "DispWrite", dispWrite);
        computeShader.SetTexture(sourceInputKernel, "DamageWrite", damageWrite);
        computeShader.Dispatch(sourceInputKernel, threadGroups, threadGroups, 1);

        // ③ 完成后交换两对缓冲
        Swap(ref dispRead, ref dispWrite);
        Swap(ref damageRead, ref damageWrite);
    }

    // ================================================================
    // 工具
    // ================================================================
    private static void Swap<T>(ref T a, ref T b)
    {
        T temp = a;
        a = b;
        b = temp;
    }

    private void SetFluidMat()
    {
        if (fluidMaterial != null)
        {
            fluidMaterial.SetColor("_FluidColor", fluidColor);
            fluidMaterial.SetFloat("_FluidThickness", fluidTransScale);
        }
    }

    // ================================================================
    // 公开接口
    // ================================================================
    public RenderTexture GetDamageTexture() => damageRead;
    public RenderTexture GetDispTexture()     => dispRead;

    public void AddSource(Vector2 uv)
    {
        hitUV = uv;
        previousHitUV = uv;
        isHit = true;
        previousIsHit = true;
    }

    public void ClearSource()
    {
        isHit = false;
        previousIsHit = false;
    }
}
