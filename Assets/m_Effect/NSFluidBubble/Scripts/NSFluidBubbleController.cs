using UnityEngine;
using UnityEngine.Rendering;

/// <summary>
/// 弹性泡泡流体模拟（弹性位移场模型）
///
/// 物理类比：有预应力的弹性膜上扎洞
/// - 位移场 S 记录材料偏离静止态的位移
/// - ElasticRelaxation（Jacobi迭代×N）：邻居拉拽 + 弹性回复 → 自然收缩成圆
/// - 两个洞时位移场叠加竞争 → 中间自动挤出挤压线
/// - 染料被位移场驱动向外流动，视觉上 = 泡泡扩张
///
/// 管线：ElasticRelaxation(×N) → SourceInput → DyeAdvection
/// 纹理：位移场(RGHalf) 染料场(RGBA UNorm)
/// </summary>
public class NSFluidBubbleController : MonoBehaviour
{
    // ================================================================
    // 文件输入
    // ================================================================
    [Header("文件输入")]
    [Tooltip("弹性泡泡计算着色器 (NSFluidBubble.compute)")]
    public ComputeShader computeShader;

    // ================================================================
    // 交互输入
    // ================================================================
    [Header("射线检测源")]
    [Tooltip("射线检测器组件，用于获取 UV 位置")]
    public RaycastTargetDetector raycastDetector;

    // ================================================================
    // 展示设置
    // ================================================================
    [Space(10)]
    [Header("展示设置")]
    [Tooltip("展示材质，支持 _DyeTex, _DispTex, _FluidColor, _FluidThickness")]
    public Material displayMaterial;
    public Color fluidColor = Color.blue;
    [Range(0.0f, 10.0f)]
    public float fluidTransScale = 1.0f;

    // ================================================================
    // 基础参数
    // ================================================================
    [Space(10)]
    [Header("基础参数")]
    [Tooltip("模拟网格大小")]
    public int size = 256;

    [Tooltip("画笔半径（UV空间）")]
    [Range(0.0f, 0.05f)]
    public float penRadius = 0.015f;

    [Tooltip("源点径向推力：hole 扩张的初始动力")]
    [Range(0.0f, 1.0f)]
    public float pushStrength = 0.3f;

    // ================================================================
    // 弹性参数
    // ================================================================
    [Space(10)]
    [Header("弹性参数")]
    [Tooltip("松弛因子：每次迭代向邻居平均混合的比例。高值 = hole收缩更快更圆")]
    [Range(0.0f, 1.0f)]
    public float relaxFactor = 0.3f;

    [Tooltip("弹性刚度：位移回弹力度。高值 = hole更小，扩张距离更短")]
    [Range(0.0f, 1.0f)]
    public float stiffness = 0.1f;

    [Tooltip("弹性松弛迭代次数。高值 = 更圆润、边界更光滑")]
    [Range(5, 200)]
    public int relaxIterations = 40;

    // ================================================================
    // 染料参数
    // ================================================================
    [Space(10)]
    [Header("染料参数")]
    [Tooltip("染料平流速度")]
    [Range(0.0f, 2.0f)]
    public float advectSpeed = 0.5f;

    [Tooltip("染料衰减系数")]
    [Range(0.0f, 0.2f)]
    public float colorAttenuation = 0.002f;

    // ================================================================
    // Kernels
    // ================================================================
    private int elasticRelaxationKernel;
    private int sourceInputKernel;
    private int dyeAdvectionKernel;

    // ================================================================
    // Buffers
    // ================================================================
    private RTHandle dispRead;
    private RTHandle dispWrite;
    private RTHandle dyeRead;
    private RTHandle dyeWrite;

    // ================================================================
    // 射线检测缓存
    // ================================================================
    private bool isHit = false;
    private Vector2 hitUV = Vector2.zero;

    // ================================================================
    // Unity 生命周期
    // ================================================================
    private void Start()
    {
        if (computeShader == null)
        {
            Debug.LogError("NSFluidBubbleController: 请指定计算着色器！");
            return;
        }

        if (displayMaterial == null)
            Debug.LogWarning("NSFluidBubbleController: 展示材质未设置");

        if (raycastDetector == null)
            Debug.LogWarning("NSFluidBubbleController: 射线检测器未设置");

        InitializeKernels();
        InitializeRTHandles();
    }

    private void Update()
    {
        if (computeShader == null)
            return;

        UpdateRaycastData();
        Simulate();

        if (displayMaterial != null)
        {
            displayMaterial.SetTexture("_DyeTex", dyeRead);
            displayMaterial.SetTexture("_DispTex", dispRead);
            displayMaterial.SetColor("_FluidColor", fluidColor);
            displayMaterial.SetFloat("_FluidThickness", fluidTransScale);
        }

        Shader.SetGlobalTexture("_NSDispTex", dispRead.rt);
        Shader.SetGlobalTexture("_NSDyeTex", dyeRead.rt);
        Shader.SetGlobalFloat("_NSTexSize", size);
    }

    private void OnDestroy()
    {
        ReleaseRTHandles();
    }

    // ================================================================
    // 初始化
    // ================================================================
    private void InitializeKernels()
    {
        elasticRelaxationKernel = computeShader.FindKernel("ElasticRelaxationKernel");
        sourceInputKernel = computeShader.FindKernel("SourceInputKernel");
        dyeAdvectionKernel = computeShader.FindKernel("DyeAdvectionKernel");
    }

    private void InitializeRTHandles()
    {
        ReleaseRTHandles();

        // 位移场：2通道有符号浮点
        dispRead = RTHandles.Alloc(
            size, size,
            colorFormat: UnityEngine.Experimental.Rendering.GraphicsFormat.R16G16_SFloat,
            enableRandomWrite: true,
            name: "DispRead"
        );
        dispWrite = RTHandles.Alloc(
            size, size,
            colorFormat: UnityEngine.Experimental.Rendering.GraphicsFormat.R16G16_SFloat,
            enableRandomWrite: true,
            name: "DispWrite"
        );

        // 染料场：RGBA UNorm
        dyeRead = RTHandles.Alloc(
            size, size,
            colorFormat: UnityEngine.Experimental.Rendering.GraphicsFormat.R16G16B16A16_UNorm,
            enableRandomWrite: true,
            name: "DyeRead"
        );
        dyeWrite = RTHandles.Alloc(
            size, size,
            colorFormat: UnityEngine.Experimental.Rendering.GraphicsFormat.R16G16B16A16_UNorm,
            enableRandomWrite: true,
            name: "DyeWrite"
        );
    }

    private void ReleaseRTHandles()
    {
        dispRead?.Release();
        dispWrite?.Release();
        dyeRead?.Release();
        dyeWrite?.Release();
    }

    // ================================================================
    // 输入
    // ================================================================
    private void UpdateRaycastData()
    {
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

        bool pressing = Input.GetMouseButton(0) && isHit;

        // ── 通用参数 ──
        computeShader.SetFloat("texSize", size);
        computeShader.SetFloat("dt", Time.deltaTime);
        computeShader.SetFloat("radius", penRadius);
        computeShader.SetFloat("pushStrength", pushStrength);
        computeShader.SetBool("isHit", pressing);
        computeShader.SetVector("sourceUV", pressing ? hitUV : Vector2.one * -1f);

        computeShader.SetFloat("relaxFactor", relaxFactor);
        computeShader.SetFloat("stiffness", stiffness);

        computeShader.SetFloat("advectSpeed", advectSpeed);
        computeShader.SetFloat("colorAttenuation", colorAttenuation);

        // ====== ① ElasticRelaxation × N ======
        for (int i = 0; i < relaxIterations; i++)
        {
            computeShader.SetTexture(elasticRelaxationKernel, "DispTex", dispRead);
            computeShader.SetTexture(elasticRelaxationKernel, "DispWrite", dispWrite);
            computeShader.Dispatch(elasticRelaxationKernel, threadGroups, threadGroups, 1);
            Swap(ref dispRead, ref dispWrite);
        }

        // ====== ② SourceInput ======
        computeShader.SetTexture(sourceInputKernel, "DispTex", dispRead);
        computeShader.SetTexture(sourceInputKernel, "DispWrite", dispWrite);
        computeShader.Dispatch(sourceInputKernel, threadGroups, threadGroups, 1);
        Swap(ref dispRead, ref dispWrite);

        // ====== ③ DyeAdvection ======
        computeShader.SetTexture(dyeAdvectionKernel, "DispTex", dispRead);
        computeShader.SetTexture(dyeAdvectionKernel, "DyeTex", dyeRead);
        computeShader.SetTexture(dyeAdvectionKernel, "DyeWrite", dyeWrite);
        computeShader.Dispatch(dyeAdvectionKernel, threadGroups, threadGroups, 1);
        Swap(ref dyeRead, ref dyeWrite);
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

    // ================================================================
    // 公开接口
    // ================================================================
    public RenderTexture GetDispTexture() => dispRead?.rt;
    public RenderTexture GetDyeTexture() => dyeRead?.rt;

    public void AddSource(Vector2 uv)
    {
        hitUV = uv;
        isHit = true;
    }

    public void ClearSource()
    {
        isHit = false;
    }
}
