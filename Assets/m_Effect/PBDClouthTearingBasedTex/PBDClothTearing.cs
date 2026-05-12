using UnityEngine;

/// <summary>
/// PBD (Position-Based Dynamics) 布料撕裂模拟
/// 基于纹理网格，每个像素为一个质点，4邻域距离约束
/// 预张力 + 破洞后约束释放 → 自然边缘回缩
///
/// PBD cloth tearing simulation on texture grid.
/// Each pixel is a particle with 4-neighbor distance constraints.
/// Pre-tension + constraint release at holes → natural edge retraction.
/// </summary>
public class PBDClothTearing : MonoBehaviour
{
    [Header("File Input / 文件输入")]
    [Tooltip("PBD compute shader (PBDClothTearing.compute)")]
    public ComputeShader computeShader;

    [Tooltip("Display material (sampling _HoleTex / _PosTex)")]
    public Material displayMaterial;

    [Tooltip("Output texture (hole map)")]
    public RenderTexture outputTexture;

    /////////////////////////////////////////////////////////////////////
    [Header("Raycast Source / 射线检测源")]
    [Tooltip("Raycast detector component for UV input")]
    public RaycastTargetDetector raycastDetector;

    /////////////////////////////////////////////////////////////////////
    [Space(10)]
    [Header("Simulation / 模拟参数")]
    [Tooltip("Grid resolution / 网格分辨率")]
    public int size = 256;

    [Tooltip("Time step / 时间步长")]
    [Range(0.0f, 1.0f)]
    public float dt = 0.15f;

    [Tooltip("Pen radius in UV space / 画笔半径")]
    [Range(0.0f, 0.05f)]
    public float penRadius = 0.02f;

    /////////////////////////////////////////////////////////////////////
    [Space(10)]
    [Header("PBD Parameters / PBD 参数")]
    [Tooltip("Rest distance factor (< 1 = pre-tension) / 静止距离因子（<1=预张力）")]
    [Range(0.8f, 1.0f)]
    public float pretensionFactor = 0.92f;

    [Tooltip("Constraint stiffness per iteration / 每次迭代约束刚度")]
    [Range(0.1f, 1.0f)]
    public float stiffness = 0.5f;

    [Tooltip("Hole-edge retraction strength / 破洞边缘回缩强度")]
    [Range(0.0f, 5.0f)]
    public float retractionStrength = 0.5f;

    [Tooltip("Number of constraint iterations / 约束迭代次数")]
    [Range(1, 10)]
    public int constraintIterations = 4;

    [Tooltip("Velocity damping (higher = less bouncy) / 速度阻尼（越大越不回弹）")]
    [Range(0.0f, 0.2f)]
    public float damping = 0.005f;

    [Tooltip("Max velocity clamp / 最大速度截断")]
    [Range(0.0f, 1.0f)]
    public float maxVel = 0.5f;

    // Kernel indices / Kernel 索引
    private int initKernel;
    private int predictKernel;
    private int constraintKernel;
    private int velocityKernel;
    private int holeAdvectionKernel;

    // Position buffers (3 for ping-pong + saved stable) / 位置缓冲（3张：ping-pong + 稳定态）
    private RenderTexture posA;      // 稳定位置 / stable position
    private RenderTexture posB;      // 预测位置 / predicted position
    private RenderTexture posC;      // 约束求解临时缓冲 / constraint temp buffer

    // Velocity buffer / 速度缓冲
    private RenderTexture velTex;

    // Inverse mass buffer / 逆质量缓冲
    private RenderTexture invMassTex;

    // Hole map buffers (ping-pong) / 空洞图缓冲
    private RenderTexture holeA;
    private RenderTexture holeB;

    // Raycast state / 射线检测状态
    private bool isHit = false;
    private Vector2 hitUV = Vector2.zero;
    private Vector2 previousHitUV = Vector2.zero;
    private bool previousIsHit = false;

    // ── Unity Lifecycle / Unity 生命周期 ──

    private void Start()
    {
        if (!ValidateInputs()) return;

        FindKernels();
        CreateRenderTextures();

        // 仅运行一次：初始化所有纹理
        InitAllTextures();
    }

    private void Update()
    {
        if (computeShader == null) return;

        UpdateRaycastData();
        Simulate();

        // 输出到指定纹理 / output to designated texture
        if (outputTexture != null)
            Graphics.Blit(holeA, outputTexture);

        // 设置展示材质 / set display material
        if (displayMaterial != null)
        {
            displayMaterial.SetTexture("_HoleTex", holeA);
            displayMaterial.SetTexture("_PosTex", posA);
            displayMaterial.SetFloat("_TexSize", size);
        }
    }

    private void OnDestroy()
    {
        ReleaseRenderTextures();
    }

    // ── Initialization / 初始化 ──

    private bool ValidateInputs()
    {
        if (computeShader == null)
        {
            Debug.LogError("PBDClothTearing: Please assign the compute shader!");
            return false;
        }
        if (displayMaterial == null)
            Debug.LogWarning("PBDClothTearing: Display material not assigned.");
        if (raycastDetector == null)
            Debug.LogWarning("PBDClothTearing: Raycast detector not assigned.");
        return true;
    }

    private void FindKernels()
    {
        initKernel        = computeShader.FindKernel("InitKernel");
        predictKernel     = computeShader.FindKernel("PredictAndSourceKernel");
        constraintKernel  = computeShader.FindKernel("ConstraintKernel");
        velocityKernel    = computeShader.FindKernel("VelocityUpdateKernel");
        holeAdvectionKernel = computeShader.FindKernel("HoleAdvectionKernel");
    }

    private void CreateRenderTextures()
    {
        ReleaseRenderTextures();

        var posDesc = new RenderTextureDescriptor(size, size, RenderTextureFormat.RGFloat, 0)
        {
            enableRandomWrite = true
        };

        var velDesc = new RenderTextureDescriptor(size, size, RenderTextureFormat.RGFloat, 0)
        {
            enableRandomWrite = true
        };

        var massDesc = new RenderTextureDescriptor(size, size, RenderTextureFormat.RFloat, 0)
        {
            enableRandomWrite = true
        };

        var holeDesc = new RenderTextureDescriptor(size, size, RenderTextureFormat.RGFloat, 0)
        {
            enableRandomWrite = true
        };

        posA = new RenderTexture(posDesc) { name = "PosA_Stable" }; posA.Create();
        posB = new RenderTexture(posDesc) { name = "PosB_Predict" }; posB.Create();
        posC = new RenderTexture(posDesc) { name = "PosC_Temp" };    posC.Create();

        velTex     = new RenderTexture(velDesc)  { name = "Velocity" };  velTex.Create();
        invMassTex = new RenderTexture(massDesc) { name = "InvMass" };   invMassTex.Create();

        holeA = new RenderTexture(holeDesc) { name = "HoleA" }; holeA.Create();
        holeB = new RenderTexture(holeDesc) { name = "HoleB" }; holeB.Create();
    }

    private void ReleaseRenderTextures()
    {
        if (posA != null)      { posA.Release(); Destroy(posA); }
        if (posB != null)      { posB.Release(); Destroy(posB); }
        if (posC != null)      { posC.Release(); Destroy(posC); }
        if (velTex != null)    { velTex.Release(); Destroy(velTex); }
        if (invMassTex != null){ invMassTex.Release(); Destroy(invMassTex); }
        if (holeA != null)     { holeA.Release(); Destroy(holeA); }
        if (holeB != null)     { holeB.Release(); Destroy(holeB); }
    }

    private void InitAllTextures()
    {
        int threadGroups = Mathf.CeilToInt(size / 8.0f);

        computeShader.SetFloat("_TexSize", size);
        computeShader.SetTexture(initKernel, "_PosWriteBuf", posA);
        computeShader.SetTexture(initKernel, "_VelBuf",      velTex);
        computeShader.SetTexture(initKernel, "_InvMassBuf",   invMassTex);
        computeShader.SetTexture(initKernel, "_HoleWriteBuf", holeA);

        computeShader.Dispatch(initKernel, threadGroups, threadGroups, 1);

        // holeB 也需要初始化为0 / holeB also needs init to 0
        Graphics.Blit(holeA, holeB);
    }

    // ── Raycast Input / 射线输入 ──

    private void UpdateRaycastData()
    {
        previousIsHit = isHit;
        previousHitUV = hitUV;

        if (raycastDetector != null)
            raycastDetector.GetRaycastData(out isHit, out hitUV, out _);
        else
            isHit = false;
    }

    // ── Main Simulation / 主模拟 ──

    private void Simulate()
    {
        int threadGroups = Mathf.CeilToInt(size / 8.0f);

        // ── 共享参数 / shared parameters ──
        SetSharedParams();

        // ── Step 1: 预测 + 破洞输入 / Predict + hole input ──
        // posA = 稳定位置(stable), posB = 预测输出(pred)
        computeShader.SetTexture(predictKernel, "_PosReadBuf",  posA);
        computeShader.SetTexture(predictKernel, "_PosWriteBuf", posB);
        computeShader.SetTexture(predictKernel, "_VelBuf",      velTex);
        computeShader.SetTexture(predictKernel, "_InvMassBuf",   invMassTex);
        computeShader.SetTexture(predictKernel, "_HoleWriteBuf", holeB);
        computeShader.Dispatch(predictKernel, threadGroups, threadGroups, 1);

        // 现在: posA = stable(旧), posB = pred, holeB = 新破洞
        // Now: posA = stable(old), posB = pred, holeB = new holes

        // 保存旧稳定位置引用（速度更新时需要）/ save old stable ref for velocity update
        RenderTexture oldStable = posA;

        // ── Step 2-3: 约束迭代 / Constraint iterations ──
        // ping-pong: posB ↔ posC
        RenderTexture readBuf  = posB;  // 初始读取预测位置
        RenderTexture writeBuf = posC;  // 初始写入临时缓冲

        for (int i = 0; i < constraintIterations; i++)
        {
            computeShader.SetTexture(constraintKernel, "_PosReadBuf",  readBuf);
            computeShader.SetTexture(constraintKernel, "_PosWriteBuf", writeBuf);
            computeShader.SetTexture(constraintKernel, "_InvMassBuf",   invMassTex);
            computeShader.Dispatch(constraintKernel, threadGroups, threadGroups, 1);

            // 交换读写缓冲 / swap read/write buffers
            RenderTexture temp = readBuf;
            readBuf = writeBuf;
            writeBuf = temp;
        }

        // 迭代结束：readBuf=最终约束结果, writeBuf=中间结果(废弃)
        // After loop: readBuf=final constraint result, writeBuf=stale intermediate
        RenderTexture finalPos = readBuf;

        // ── Step 4: 速度更新 / Velocity update ──
        // _PosReadBuf  = oldStable (预测前稳定位置 / pre-predict stable pos)
        // _PosWriteBuf = finalPos (约束求解后位置 / post-constraint pos)
        computeShader.SetTexture(velocityKernel, "_PosReadBuf",  oldStable);
        computeShader.SetTexture(velocityKernel, "_PosWriteBuf", finalPos);
        computeShader.SetTexture(velocityKernel, "_VelBuf",      velTex);
        computeShader.Dispatch(velocityKernel, threadGroups, threadGroups, 1);

        // ── 重新分配缓冲引用 / reassign buffer references ──
        // 三个缓冲分属: finalPos(新稳定), oldStable(已废弃), writeBuf(已废弃)
        // Three buffers: finalPos(new stable), oldStable(freed), writeBuf(freed)
        posA = finalPos;    // 下帧的稳定位置 / next frame's stable position
        posB = oldStable;   // 下帧的预测写入目标 / next frame's predict write target
        posC = writeBuf;    // 下帧的约束临时缓冲 / next frame's constraint temp buffer

        // ── Step 5: 空洞平流 / Hole advection ──
        computeShader.SetTexture(holeAdvectionKernel, "_HoleTex",      holeA);
        computeShader.SetTexture(holeAdvectionKernel, "_HoleWriteBuf", holeB);
        computeShader.SetTexture(holeAdvectionKernel, "_VelBuf",       velTex);
        computeShader.Dispatch(holeAdvectionKernel, threadGroups, threadGroups, 1);

        // 交换空洞缓冲 / swap hole buffers
        Swap(ref holeA, ref holeB);
    }

    // ── Helpers / 辅助函数 ──

    private void SetSharedParams()
    {
        computeShader.SetFloat("_TexSize",          size);
        computeShader.SetFloat("_DT",               dt);
        computeShader.SetFloat("_PretensionFactor", pretensionFactor);
        computeShader.SetFloat("_Stiffness",        stiffness);
        computeShader.SetFloat("_Damping",          damping);
        computeShader.SetFloat("_RetractionStrength", retractionStrength);
        computeShader.SetFloat("_Radius",           penRadius);
        computeShader.SetFloat("_MaxVel",           maxVel);

        bool pressed = Input.GetMouseButton(0) && isHit;
        computeShader.SetFloat("_KeyDown", pressed ? 1.0f : 0.0f);

        Vector2 curUV = isHit ? hitUV : Vector2.one * -1.0f;
        Vector2 prevUV = previousIsHit ? previousHitUV : curUV + Vector2.one * 1e-4f;
        computeShader.SetVector("_PenPos", new Vector4(curUV.x, curUV.y, prevUV.x, prevUV.y));
    }

    private static void Swap<T>(ref T a, ref T b)
    {
        T temp = a;
        a = b;
        b = temp;
    }

    // ── Public API / 公共接口 ──

    /// <summary>
    /// Get current hole texture / 获取当前空洞纹理
    /// </summary>
    public RenderTexture GetHoleTexture() => holeA;

    /// <summary>
    /// Get current position texture / 获取当前位置纹理
    /// </summary>
    public RenderTexture GetPositionTexture() => posA;

    /// <summary>
    /// Add external hole source at UV / 从外部在UV处添加破洞
    /// </summary>
    public void AddSource(Vector2 uv)
    {
        hitUV = uv;
        previousHitUV = uv;
        isHit = true;
        previousIsHit = true;
    }

    /// <summary>
    /// Clear hole source / 清除破洞源
    /// </summary>
    public void ClearSource()
    {
        isHit = false;
        previousIsHit = false;
    }
}
