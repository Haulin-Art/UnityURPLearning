using UnityEngine;

/// <summary>
/// 纯弹性回缩 + 拉伸极限 —— 丝袜撕裂模拟
/// 单 kernel，单 Dispatch，空洞仅来自鼠标，无自主撕裂
/// 通过 RaycastTargetDetector 获取 UV 位置作为画笔输入
/// </summary>
public class DynamicPantyhoseTearingNS : MonoBehaviour
{
    [Header("文件输入")]
    [Tooltip("撕裂计算着色器 (TearingKernel.compute)")]
    public ComputeShader computeShader;

    [Tooltip("用于展示效果的材质（采样 _HoleTex / _DispTex）")]
    public Material displayMaterial;

    [Tooltip("输出贴图（空洞场）")]
    public RenderTexture outputTexture;

    /////////////////////////////////////////////////////////////////////
    [Header("射线检测源")]
    [Tooltip("射线检测器组件，用于获取 UV 位置")]
    public RaycastTargetDetector raycastDetector;

    /////////////////////////////////////////////////////////////////////
    [Space(10)]
    [Header("模拟参数")]
    [Tooltip("模拟网格大小")]
    public int size = 256;

    [Tooltip("时间步长")]
    [Range(0.0f, 1.0f)]
    public float dt = 0.15f;

    [Tooltip("画笔半径（UV 空间）")]
    [Range(0.0f, 0.05f)]
    public float penRadius = 0.02f;

    /////////////////////////////////////////////////////////////////////
    [Space(10)]
    [Header("回缩参数")]
    [Tooltip("空洞差→回缩力的转换系数（UV单位）")]
    [Range(0.0f, 5.0f)]
    public float retractionStrength = 0.5f;

    [Tooltip("位移向原点回归的速率（弹性记忆，越大回弹越快）")]
    [Range(0.0f, 0.2f)]
    public float damping = 0.02f;

    /////////////////////////////////////////////////////////////////////
    [Space(10)]
    [Header("拉伸参数")]
    [Tooltip("拉伸刚度：越大越难拉伸，avgExcess为UV单位的超限均值")]
    [Range(0.0f, 2000f)]
    public float stretchStiffness = 250f;

    // Kernel
    private int initKernel;
    private int tearingKernel;

    // 空洞场 ping-pong
    private RenderTexture holeRead;
    private RenderTexture holeWrite;

    // 位移场 ping-pong
    private RenderTexture dispRead;
    private RenderTexture dispWrite;

    // 射线检测缓存
    private bool isHit = false;
    private Vector2 hitUV = Vector2.zero;
    private Vector2 previousHitUV = Vector2.zero;
    private bool previousIsHit = false;

    private void Start()
    {
        if (computeShader == null)
        {
            Debug.LogError("DynamicPantyhoseTearingNS: 请指定 TearingKernel.compute！");
            return;
        }

        if (displayMaterial == null)
            Debug.LogWarning("DynamicPantyhoseTearingNS: 展示材质未设置");

        if (raycastDetector == null)
            Debug.LogWarning("DynamicPantyhoseTearingNS: 射线检测器未设置");

        initKernel = computeShader.FindKernel("InitKernel");
        tearingKernel = computeShader.FindKernel("TearingKernel");
        CreateRenderTextures();

        // 初始化位移场（仅运行一次）
        InitDispField();
    }

    private void Update()
    {
        if (computeShader == null) return;

        UpdateRaycastData();
        Simulate();

        if (outputTexture != null)
            Graphics.Blit(holeRead, outputTexture);

        if (displayMaterial != null)
        {
            displayMaterial.SetTexture("_HoleTex", holeRead);
            displayMaterial.SetTexture("_DispTex", dispRead);
        }
    }

    private void OnDestroy()
    {
        ReleaseRenderTextures();
    }

    private void UpdateRaycastData()
    {
        previousIsHit = isHit;
        previousHitUV = hitUV;

        if (raycastDetector != null)
            raycastDetector.GetRaycastData(out isHit, out hitUV, out _);
        else
            isHit = false;
    }

    private void CreateRenderTextures()
    {
        ReleaseRenderTextures();

        var holeDesc = new RenderTextureDescriptor(size, size, RenderTextureFormat.RGFloat, 0)
        {
            enableRandomWrite = true
        };

        var dispDesc = new RenderTextureDescriptor(size, size, RenderTextureFormat.ARGBFloat, 0)
        {
            enableRandomWrite = true
        };

        holeRead = new RenderTexture(holeDesc) { name = "HoleRead" };
        holeRead.Create();
        holeWrite = new RenderTexture(holeDesc) { name = "HoleWrite" };
        holeWrite.Create();

        dispRead = new RenderTexture(dispDesc) { name = "DispRead" };
        dispRead.Create();
        dispWrite = new RenderTexture(dispDesc) { name = "DispWrite" };
        dispWrite.Create();
    }

    private void ReleaseRenderTextures()
    {
        if (holeRead != null)  { holeRead.Release(); Destroy(holeRead); }
        if (holeWrite != null) { holeWrite.Release(); Destroy(holeWrite); }
        if (dispRead != null)  { dispRead.Release(); Destroy(dispRead); }
        if (dispWrite != null) { dispWrite.Release(); Destroy(dispWrite); }
    }

    private void InitDispField()
    {
        int threadGroups = Mathf.CeilToInt(size / 8.0f);

        computeShader.SetFloat("_TexSize", size);
        computeShader.SetTexture(initKernel, "_DispWrite", dispWrite);
        computeShader.SetTexture(initKernel, "_HoleWrite", holeWrite);
        computeShader.Dispatch(initKernel, threadGroups, threadGroups, 1);

        // Swap 后将初始化数据放入读缓冲
        Swap(ref dispRead, ref dispWrite);
        Swap(ref holeRead, ref holeWrite);
    }

    private void Simulate()
    {
        int threadGroups = Mathf.CeilToInt(size / 8.0f);

        // 共享参数
        computeShader.SetFloat("_TexSize", size);
        computeShader.SetFloat("_DT", dt);
        computeShader.SetFloat("_Radius", penRadius);
        computeShader.SetFloat("_RetractionStrength", retractionStrength);
        computeShader.SetFloat("_Damping", damping);
        computeShader.SetFloat("_StretchStiffness", stretchStiffness);

        // 画笔输入
        bool pressed = Input.GetMouseButton(0) && isHit;
        computeShader.SetFloat("_KeyDown", pressed ? 1.0f : 0.0f);

        Vector2 curUV = isHit ? hitUV : Vector2.one * -1.0f;
        Vector2 prevUV = previousIsHit ? previousHitUV : curUV + Vector2.one * 1e-4f;
        computeShader.SetVector("_PenPos", new Vector4(curUV.x, curUV.y, prevUV.x, prevUV.y));

        // 绑定只读纹理（用于 SampleLevel 线性采样）
        computeShader.SetTexture(tearingKernel, "_HoleTex", holeRead);
        computeShader.SetTexture(tearingKernel, "_DispTex", dispRead);

        // 绑定可写缓冲
        computeShader.SetTexture(tearingKernel, "_HoleWrite", holeWrite);
        computeShader.SetTexture(tearingKernel, "_DispWrite", dispWrite);

        // 单次 Dispatch
        computeShader.Dispatch(tearingKernel, threadGroups, threadGroups, 1);

        // Ping-pong swap
        Swap(ref holeRead, ref holeWrite);
        Swap(ref dispRead, ref dispWrite);
    }

    private static void Swap<T>(ref T a, ref T b)
    {
        T temp = a;
        a = b;
        b = temp;
    }

    /// <summary>
    /// 获取当前帧空洞纹理
    /// </summary>
    public RenderTexture GetHoleTexture() => holeRead;

    /// <summary>
    /// 获取当前帧位移纹理
    /// </summary>
    public RenderTexture GetDispTexture() => dispRead;

    /// <summary>
    /// 从外部添加破洞
    /// </summary>
    public void AddSource(Vector2 uv)
    {
        hitUV = uv;
        previousHitUV = uv;
        isHit = true;
        previousIsHit = true;
    }

    /// <summary>
    /// 清除源
    /// </summary>
    public void ClearSource()
    {
        isHit = false;
        previousIsHit = false;
    }
}
