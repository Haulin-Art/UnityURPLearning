using UnityEngine;
using UnityEngine.Rendering;

/// <summary>
/// Navier-Stokes 流体模拟脚本
/// 基于不可压缩 NS 方程，通过 RaycastTargetDetector 获取源位置
/// 模拟管线：Advection → Pressure(雅可比迭代×N) → Projection → Dye
///
/// 纹理格式：速度场(RG=SignedFloat), 压力场(R=SignedFloat), 染料场(RGB=UNorm)
/// </summary>
public class NSFluidController : MonoBehaviour
{
    // ================================================================
    // 文件输入
    // ================================================================
    [Header("文件输入")]
    [Tooltip("NS 流体计算着色器 (NSFluid.compute)")]
    public ComputeShader computeShader;


    // ================================================================
    // 交互输入
    // ================================================================
    [Header("射线检测源")]
    [Tooltip("射线检测器组件，用于获取 UV 位置")]
    public RaycastTargetDetector raycastDetector;

    // ================================================================
    // 流体着色设置
    // ================================================================
    [Space(10)]
    [Header("流体着色设置")]
    [Tooltip("用于展示流体效果的材质，得包含_VelocityTex、_DyeTex、_PressureTex、_FluidColor、_FluidThickness")]
    public Material displayMaterial;
    public Color fluidColor = Color.blue;
    [Range(0.0f, 10.0f)]
    public float fluidTransScale = 1.0f;

    // ================================================================
    // 模拟参数
    // ================================================================
    [Space(10)]
    [Header("模拟参数设置")]
    [Tooltip("模拟网格大小")]
    public int size = 256;

    [Tooltip("时间步长")]
    [Range(0.0f, 1.0f)]
    public float dt = 0.15f;

    [Tooltip("画笔半径")]
    [Range(0.0f, 0.05f)]
    public float penRadius = 0.015f;

    [Tooltip("施加力的大小")]
    [Range(0.0f, 10.0f)]
    public float forceScale = 2.5f;

    [Tooltip("流体平流项速度")]
    [Range(0.0f, 1.0f)]
    public float advectSpeed = 0.25f;

    [Tooltip("雅可比迭代次数")]
    [Range(2, 20)]
    public int pressureIterations = 10;

    [Tooltip("速度衰减系数")]
    [Range(0.0f, 0.2f)]
    public float speedAttenuation = 0.005f;

    [Tooltip("染料衰减系数")]
    [Range(0.0f, 0.2f)]
    public float colorAttenuation = 0.005f;

    // ================================================================
    // Kernels
    // ================================================================
    private int advectionKernel;
    private int pressureKernel;
    private int projectionKernel;
    private int dyeKernel;

    // ================================================================
    // Compute Buffers (RTHandles)
    // ================================================================
    private RTHandle vBuffer1; // 速度缓存1
    private RTHandle vBuffer2; // 速度缓存2
    private RTHandle pBuffer1; // 压力缓存1
    private RTHandle pBuffer2; // 压力缓存2
    private RTHandle dBuffer1; // 染料缓存1
    private RTHandle dBuffer2; // 染料缓存2

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
            Debug.LogError("NSFluidController: 请指定计算着色器！");
            return;
        }

        if (displayMaterial == null)
            Debug.LogWarning("NSFluidController: 展示材质未设置，将无法看到效果");

        if (raycastDetector == null)
            Debug.LogWarning("NSFluidController: 射线检测器未设置，将无法添加流体源");

        InitializeKernels();
        InitializeRTHandles();
    }

    private void Update()
    {
        SetFluidMat();

        if (computeShader == null)
            return;

        // 从射线检测器获取数据
        UpdateRaycastData();

        // 执行 NS 流体模拟
        SimulateFluid();

        // 更新展示材质
        if (displayMaterial != null)
        {
            displayMaterial.SetTexture("_VelocityTex", vBuffer1);
            displayMaterial.SetTexture("_DyeTex", dBuffer1);
            displayMaterial.SetTexture("_PressureTex", pBuffer1);
        }

        // 设置全局贴图和参数
        Shader.SetGlobalTexture("_NSVelocityTex", vBuffer1.rt);
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
        advectionKernel = computeShader.FindKernel("AdvectionKernel");
        pressureKernel = computeShader.FindKernel("PressureKernel");
        projectionKernel = computeShader.FindKernel("ProjectionKernel");
        dyeKernel = computeShader.FindKernel("DyeKernel");
    }

    private void InitializeRTHandles()
    {
        ReleaseRTHandles();

        // 速度场：RG 双通道 (x, y) - 有符号浮点
        vBuffer1 = RTHandles.Alloc(
            size, size,
            colorFormat: UnityEngine.Experimental.Rendering.GraphicsFormat.R16G16_SFloat,
            enableRandomWrite: true,
            name: "Velocity1"
        );
        vBuffer2 = RTHandles.Alloc(
            size, size,
            colorFormat: UnityEngine.Experimental.Rendering.GraphicsFormat.R16G16_SFloat,
            enableRandomWrite: true,
            name: "Velocity2"
        );

        // 压力场：单通道
        pBuffer1 = RTHandles.Alloc(
            size, size,
            colorFormat: UnityEngine.Experimental.Rendering.GraphicsFormat.R16_SFloat,
            enableRandomWrite: true,
            name: "Pressure1"
        );
        pBuffer2 = RTHandles.Alloc(
            size, size,
            colorFormat: UnityEngine.Experimental.Rendering.GraphicsFormat.R16_SFloat,
            enableRandomWrite: true,
            name: "Pressure2"
        );

        // 染料场：RGB 三通道，用于可视化
        dBuffer1 = RTHandles.Alloc(
            size, size,
            colorFormat: UnityEngine.Experimental.Rendering.GraphicsFormat.R16G16B16A16_UNorm,
            enableRandomWrite: true,
            name: "Dye1"
        );
        dBuffer2 = RTHandles.Alloc(
            size, size,
            colorFormat: UnityEngine.Experimental.Rendering.GraphicsFormat.R16G16B16A16_UNorm,
            enableRandomWrite: true,
            name: "Dye2"
        );
    }

    private void ReleaseRTHandles()
    {
        vBuffer1?.Release();
        vBuffer2?.Release();
        pBuffer1?.Release();
        pBuffer2?.Release();
        dBuffer1?.Release();
        dBuffer2?.Release();
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
    private void SimulateFluid()
    {
        int threadGroups = Mathf.CeilToInt(size / 8.0f);

        // 确定当前是否按下（鼠标按下 + 射线命中）
        bool pressing = Input.GetMouseButton(0) && isHit;

        // 当前 UV 与上一帧 UV 的差值（用于施加方向力）
        Vector2 uvDelta = (isHit && previousIsHit) ? (hitUV - previousHitUV) : Vector2.zero;

        // ── 通用参数 ──
        computeShader.SetFloat("texSize", size);
        computeShader.SetFloat("dt", dt);
        computeShader.SetFloat("advectSpeed", advectSpeed);
        computeShader.SetFloat("forceScale", forceScale);
        computeShader.SetFloat("radius", penRadius);
        computeShader.SetBool("isHit", pressing);
        computeShader.SetVector("sourceUV", pressing ? hitUV : Vector2.one * -1f);
        computeShader.SetVector("sourceDelta", uvDelta);
        computeShader.SetVector("attenuation", new Vector2(speedAttenuation, colorAttenuation));

        // ======================== ① 平流项 ========================
        computeShader.SetTexture(advectionKernel, "VelocityRead", vBuffer1);
        computeShader.SetTexture(advectionKernel, "VelocityWrite", vBuffer2);
        computeShader.SetTexture(advectionKernel, "VelocityTex", vBuffer1);
        computeShader.Dispatch(advectionKernel, threadGroups, threadGroups, 1);
        Swap(ref vBuffer1, ref vBuffer2);

        // ======================== ② 压力项（雅可比迭代） ========================
        for (int i = 0; i < pressureIterations; i++)
        {
            computeShader.SetTexture(pressureKernel, "VelocityTex", vBuffer1);
            computeShader.SetTexture(pressureKernel, "PressureRead", pBuffer1);
            computeShader.SetTexture(pressureKernel, "PressureWrite", pBuffer2);
            computeShader.SetTexture(pressureKernel, "PressureTex", pBuffer1);
            computeShader.Dispatch(pressureKernel, threadGroups, threadGroups, 1);
            Swap(ref pBuffer1, ref pBuffer2);
        }

        // ======================== ③ 投影项 ========================
        computeShader.SetTexture(projectionKernel, "VelocityRead", vBuffer1);
        computeShader.SetTexture(projectionKernel, "VelocityWrite", vBuffer2);
        computeShader.SetTexture(projectionKernel, "VelocityTex", vBuffer1);
        computeShader.SetTexture(projectionKernel, "PressureTex", pBuffer1);
        computeShader.Dispatch(projectionKernel, threadGroups, threadGroups, 1);
        Swap(ref vBuffer1, ref vBuffer2);

        // ======================== ④ 染料项 ========================
        computeShader.SetTexture(dyeKernel, "DyeRead", dBuffer1);
        computeShader.SetTexture(dyeKernel, "DyeWrite", dBuffer2);
        computeShader.SetTexture(dyeKernel, "VelocityTex", vBuffer1);
        computeShader.SetTexture(dyeKernel, "DyeTex", dBuffer1);
        computeShader.Dispatch(dyeKernel, threadGroups, threadGroups, 1);
        Swap(ref dBuffer1, ref dBuffer2);
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
        if (displayMaterial != null)
        {
            displayMaterial.SetColor("_FluidColor", fluidColor);
            displayMaterial.SetFloat("_FluidThickness", fluidTransScale);
        }
    }

    // ================================================================
    // 公开接口
    // ================================================================

    /// <summary>
    /// 获取当前速度纹理（供外部使用）
    /// </summary>
    public RenderTexture GetVelocityTexture()
    {
        return vBuffer1?.rt;
    }

    /// <summary>
    /// 获取当前染料纹理（供外部使用）
    /// </summary>
    public RenderTexture GetDyeTexture()
    {
        return dBuffer1?.rt;
    }

    /// <summary>
    /// 手动添加源（供外部调用）
    /// </summary>
    public void AddSource(Vector2 uv)
    {
        hitUV = uv;
        previousHitUV = uv;
        isHit = true;
        previousIsHit = true;
    }

    /// <summary>
    /// 手动清除源（供外部调用）
    /// </summary>
    public void ClearSource()
    {
        isHit = false;
        previousIsHit = false;
    }
}
