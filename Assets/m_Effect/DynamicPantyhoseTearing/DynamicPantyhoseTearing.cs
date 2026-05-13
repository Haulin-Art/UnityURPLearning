using Unity.Profiling;
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


    /// ********* 粒子数据信息 *********************** 
    /// 粒子位置信息，xy是当前的位置，zw是上一帧的位置
    private RenderTexture particlePosRead;    
    private RenderTexture particlePosWrite;
    // 粒子状态信息，x是记录当前粒子是否激活
    private RenderTexture particleStateRead;
    private RenderTexture particleStateWrite;
    private int initParticleKernel;    // 用于将粒子位置纹理初始化为uv
    private int updateParticleKernel;  // 用于更新粒子位置和状态
    private float particleGridSize = 60.0f;


    // 射线检测缓存
    private bool isHit = false;
    private Vector2 hitUV = Vector2.zero;
    private Vector2 previousHitUV = Vector2.zero;
    private bool previousIsHit = false;




    // 性能检测
    // 静态化避免重复构造，内部使用完整命名空间路径方便在Profiler中折叠分类
    static readonly ProfilerMarker s_MyUpdateLogic = new ProfilerMarker("MySystem.UpdateLogic");



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

        /// ********* 粒子数据信息 *********************** 
        /// 初始化粒子位置（仅运行一次）
        initParticleKernel = computeShader.FindKernel("InitParticleKernel");
        updateParticleKernel = computeShader.FindKernel("UpdateParticleKernel");

        CreateRenderTextures();

        // 初始化位移场（仅运行一次）
        InitDispField();

        // 初始化粒子位置（仅运行一次）
        InitParticlePos();
    }

    private void Update()
    {
        if (computeShader == null) return;

        
        s_MyUpdateLogic.Begin();

        UpdateRaycastData();
        Simulate();

        /// 更新粒子位置
        UpdateParticlePos();



        if (outputTexture != null)
            Graphics.Blit(holeRead, outputTexture);

        if (displayMaterial != null)
        {
            displayMaterial.SetTexture("_Particle", holeRead);
            displayMaterial.SetTexture("_DispTex", dispRead);
            displayMaterial.SetTexture("_ParticlePos", particlePosRead);
            displayMaterial.SetTexture("_ParticleState", particleStateRead);
            displayMaterial.SetTexture("_MinDisPos", dispRead);
        }

        s_MyUpdateLogic.End();
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


        /// ********* 粒子数据信息 *********************** 
        /// 粒子位置信息，xy是当前的位置，zw是上一帧的位置
        /// 大小设定为最终纹理的1/16，以减少内存占用和计算量
        var particlePosDesc = new RenderTextureDescriptor((int)particleGridSize, (int)particleGridSize, RenderTextureFormat.ARGBFloat, 0)
        {
            enableRandomWrite = true
        };
        particlePosRead = new RenderTexture(particlePosDesc) { name = "ParticlePosRead" };
        particlePosRead.Create();
        particlePosWrite = new RenderTexture(particlePosDesc) { name = "ParticlePosWrite" };
        particlePosWrite.Create();
        
        var particleStateDesc = new RenderTextureDescriptor((int)particleGridSize, (int)particleGridSize, RenderTextureFormat.RFloat, 0)
        {
            enableRandomWrite = true
        };
        particleStateRead = new RenderTexture(particleStateDesc) { name = "ParticleStateRead" };
        particleStateRead.Create();
        particleStateWrite = new RenderTexture(particleStateDesc) { name = "ParticleStateWrite" };
        particleStateWrite.Create();
    }

    private void ReleaseRenderTextures()
    {
        if (holeRead != null)  { holeRead.Release(); Destroy(holeRead); }
        if (holeWrite != null) { holeWrite.Release(); Destroy(holeWrite); }
        if (dispRead != null)  { dispRead.Release(); Destroy(dispRead); }
        if (dispWrite != null) { dispWrite.Release(); Destroy(dispWrite); }

        /// ********* 粒子数据信息 *********************** 
        /// 粒子位置信息，xy是当前的位置，zw是上一帧的位置
        if (particlePosRead != null)  { particlePosRead.Release(); Destroy(particlePosRead); }
        if (particlePosWrite != null) { particlePosWrite.Release(); Destroy(particlePosWrite); }
    }

    private void InitDispField()
    {
        int threadGroups = Mathf.CeilToInt(size / 8.0f);

        computeShader.SetFloat("_TexSize", size);
        computeShader.SetFloat("_ParticleGridSize", particleGridSize);
        computeShader.SetTexture(initKernel, "_DispWrite", dispWrite);
        computeShader.SetTexture(initKernel, "_HoleWrite", holeWrite);
        computeShader.Dispatch(initKernel, threadGroups, threadGroups, 1);

        // Swap 后将初始化数据放入读缓冲
        Swap(ref dispRead, ref dispWrite);
        Swap(ref holeRead, ref holeWrite);
    }

    private void InitParticlePos()
    {
        int threadGroups = Mathf.CeilToInt((int)particleGridSize / 8.0f);

        computeShader.SetFloat("_ParticleGridSize", particleGridSize);
        computeShader.SetTexture(initParticleKernel, "_ParticlePosWrite", particlePosWrite);
        computeShader.SetTexture(initParticleKernel, "_ParticleStateWrite", particleStateWrite);
        computeShader.Dispatch(initParticleKernel, threadGroups, threadGroups, 1);

        // Swap 后将初始化数据放入读缓冲
        //Graphics.Blit(particlePosWrite, particlePosRead);
        Swap(ref particlePosRead, ref particlePosWrite);
        //Graphics.Blit(particleStateWrite, particleStateRead);
        Swap(ref particleStateRead, ref particleStateWrite);
    }
    private void UpdateParticlePos()
    {
        int threadGroups = Mathf.CeilToInt((int)particleGridSize / 8.0f);

        // 画笔输入
        bool pressed = Input.GetMouseButton(0) && isHit;
        computeShader.SetFloat("_KeyDown", pressed ? 1.0f : 0.0f);

        Vector2 curUV = isHit ? hitUV : Vector2.one * -1.0f;
        Vector2 prevUV = previousIsHit ? previousHitUV : curUV + Vector2.one * 1e-4f;
        computeShader.SetVector("_PenPos", new Vector4(curUV.x, curUV.y, prevUV.x, prevUV.y));

        computeShader.SetFloat("_Radius", penRadius);

        computeShader.SetFloat("_ParticleGridSize", particleGridSize);
        computeShader.SetFloat("_DT", dt);
        computeShader.SetTexture(updateParticleKernel, "_ParticlePosRead", particlePosRead);
        computeShader.SetTexture(updateParticleKernel, "_ParticlePosWrite", particlePosWrite);
        computeShader.SetTexture(updateParticleKernel, "_ParticleStateRead", particleStateRead);
        computeShader.SetTexture(updateParticleKernel, "_ParticleStateWrite", particleStateWrite);
        
        computeShader.Dispatch(updateParticleKernel, threadGroups, threadGroups, 1);

        // Swap 后将更新数据放入读缓冲
        //Graphics.Blit(particlePosWrite, particlePosRead);
        Swap(ref particlePosRead, ref particlePosWrite);
        //Graphics.Blit(particleStateWrite, particleStateRead);
        //Swap(ref particleStateRead, ref particleStateWrite);
        
    }


    private void Simulate()
    {
        int threadGroups = Mathf.CeilToInt(size / 8.0f);

        // 共享参数
        computeShader.SetFloat("_TexSize", size);

        computeShader.SetFloat("_ParticleGridSize", particleGridSize);

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

        // 绑定粒子读缓冲
        computeShader.SetTexture(tearingKernel, "_ParticlePosRead", particlePosRead);
        computeShader.SetTexture(tearingKernel, "_ParticleStateRead", particleStateRead);
        // 绑定粒子状态写缓冲
        computeShader.SetTexture(tearingKernel, "_ParticleStateWrite", particleStateWrite);
        //computeShader.SetTexture(tearingKernel, "_ParticleStateRead", particleStateRead);

        // 绑定可写缓冲
        computeShader.SetTexture(tearingKernel, "_HoleWrite", holeWrite);
        computeShader.SetTexture(tearingKernel, "_DispWrite", dispWrite);

        // 单次 Dispatch
        computeShader.Dispatch(tearingKernel, threadGroups, threadGroups, 1);

        // Ping-pong swap
        Swap(ref holeRead, ref holeWrite);
        Swap(ref dispRead, ref dispWrite);
        Swap(ref particleStateRead, ref particleStateWrite);

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
