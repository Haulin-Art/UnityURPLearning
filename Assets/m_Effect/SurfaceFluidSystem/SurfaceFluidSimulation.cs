using UnityEngine;
using UnityEngine.Rendering;

/// <summary>
/// 调试模式枚举
/// </summary>
public enum FluidDebugMode
{
    None,               // 正常模式
    ShowUVJumpMap,      // 显示UV跳跃图
    ShowBacktracedUV,   // 显示回溯UV
    ShowJumpedUV,       // 显示跳跃后UV
    ShowVelocityField,  // 显示速度场
    ShowSourcePosition, // 显示源位置
    ShowGravityMap      // 显示重力图
}

/// <summary>
/// 表面流体模拟脚本
/// 基于纳维斯托克斯方程的流体模拟，通过射线检测获取源位置
/// 支持UV岛跳跃功能，实现跨UV岛的流体传输
/// 支持重力方向图，实现基于贴图的重力效果
/// </summary>
public class SurfaceFluidSimulation : MonoBehaviour
{
    [Header("文件输入")]
    [Tooltip("流体计算着色器")]
    public ComputeShader computeShader;
    
    [Tooltip("用于展示流体效果的材质")]
    public Material displayMaterial;
    
    [Tooltip("输出贴图")]
    public RenderTexture outputTexture;

    [Header("射线检测源")]
    [Tooltip("射线检测器组件，用于获取UV位置")]
    public RaycastTargetDetector raycastDetector;

    [Space(10)]
    [Header("UV跳跃设置")]
    [Tooltip("UV跳跃贴图（RG通道存储跳跃目标UV）")]
    public Texture2D uvJumpMap;
    
    [Tooltip("是否启用UV跳跃功能")]
    public bool useUVJump = false;

    [Space(10)]
    [Header("重力方向设置")]
    [Tooltip("重力方向贴图（RG通道存储方向，范围0~1，会映射到-1~1）")]
    public Texture2D gravityMap;
    
    [Tooltip("是否启用重力图")]
    public bool useGravityMap = false;
    
    [Tooltip("重力强度")]
    [Range(0.0f, 10.0f)]
    public float gravityStrength = 1.0f;

    [Space(10)]
    [Header("调试设置")]
    [Tooltip("调试模式")]
    public FluidDebugMode debugMode = FluidDebugMode.None;
    
    [Tooltip("调试输出贴图（用于查看调试信息）")]
    public RenderTexture debugOutputTexture;

    [Space(10)]
    [Header("模拟参数设置")]
    [Tooltip("模拟网格大小")]
    public int size = 256;
    
    [Tooltip("帧步长")]
    [Range(0.0f, 1.0f)]
    public float dt = 0.15f;
    
    [Tooltip("画笔半径")]
    [Range(0.0f, 0.5f)]
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

    // Compute Buffer
    private RTHandle vBuffer1;  // 速度缓存1，用于读取
    private RTHandle vBuffer2;  // 速度缓存2，用于写入
    private RTHandle pBuffer1;  // 压力缓存1，用于读取
    private RTHandle pBuffer2;  // 压力缓存2，用于写入
    private RTHandle dBuffer1;  // 染料缓存1，用于读取
    private RTHandle dBuffer2;  // 染料缓存2，用于写入
    private RTHandle debugBuffer;  // 调试输出缓存

    // Kernels
    private int advectionKernel;
    private int pressureKernel;
    private int projectionKernel;
    private int dyeKernel;
    private int debugKernel;

    // 射线检测数据缓存
    private bool isHit = false;
    private Vector2 hitUV = Vector2.zero;
    private Vector2 uvDelta = Vector2.zero;

    // 上一帧的调试模式（用于检测变化）
    private FluidDebugMode previousDebugMode = FluidDebugMode.None;

    private void Start()
    {
        if (computeShader == null)
        {
            Debug.LogError("SurfaceFluidSimulation: 请指定计算着色器！");
            return;
        }

        if (displayMaterial == null)
        {
            Debug.LogWarning("SurfaceFluidSimulation: 展示材质未设置，将无法看到效果");
        }

        if (raycastDetector == null)
        {
            Debug.LogWarning("SurfaceFluidSimulation: 射线检测器未设置，将无法添加流体源");
        }

        // 检查UV跳跃贴图
        if (useUVJump && uvJumpMap == null)
        {
            Debug.LogWarning("SurfaceFluidSimulation: 启用了UV跳跃功能但未设置UV跳跃贴图！");
        }

        // 检查重力图
        if (useGravityMap && gravityMap == null)
        {
            Debug.LogWarning("SurfaceFluidSimulation: 启用了重力图功能但未设置重力方向贴图！");
        }

        InitializeKernels();
        InitializeRTHandles();
    }

    private void Update()
    {
        if (computeShader == null) return;

        // 从射线检测器获取数据
        UpdateRaycastData();

        // 执行流体模拟
        SimulateFluid();

        // 执行调试输出
        if (debugMode != FluidDebugMode.None)
        {
            ExecuteDebugOutput();
        }

        // 更新输出贴图
        if (outputTexture != null)
        {
            Graphics.Blit(dBuffer1, outputTexture);
        }

        // 更新展示材质
        if (displayMaterial != null)
        {
            displayMaterial.SetTexture("_MainTex", dBuffer1);
        }

        // 检测调试模式变化并输出Log
        if (debugMode != previousDebugMode)
        {
            Debug.Log($"<color=cyan>SurfaceFluidSimulation: 调试模式切换为 {debugMode}</color>");
            previousDebugMode = debugMode;
        }
    }

    private void OnDestroy()
    {
        ReleaseRTHandles();
    }

    /// <summary>
    /// 从射线检测器获取数据
    /// </summary>
    private void UpdateRaycastData()
    {
        if (raycastDetector == null)
        {
            isHit = false;
            uvDelta = Vector2.zero;
            return;
        }

        raycastDetector.GetRaycastData(out isHit, out hitUV, out uvDelta);

        // 调试输出：命中状态变化时输出Log
        if (isHit && debugMode == FluidDebugMode.ShowSourcePosition)
        {
            Debug.Log($"<color=green>SurfaceFluidSimulation: 命中UV={hitUV}, Delta={uvDelta}</color>");
        }
    }

    #region 模拟函数区域 
    /// <summary>
    /// 初始化核序号
    /// </summary>
    private void InitializeKernels()
    {
        advectionKernel = computeShader.FindKernel("AdvectionKernel");
        pressureKernel = computeShader.FindKernel("PressureKernel");
        projectionKernel = computeShader.FindKernel("ProjectionKernel");
        dyeKernel = computeShader.FindKernel("DyeKernel");
        debugKernel = computeShader.FindKernel("DebugKernel");
    }

    /// <summary>
    /// 初始化RTHandles
    /// </summary>
    private void InitializeRTHandles()
    {
        ReleaseRTHandles();

        // 速度场：RG两个通道 (x, y)
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

        // 染料场：用于可视化，三个通道
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

        // 调试输出缓存
        debugBuffer = RTHandles.Alloc(
            size, size,
            colorFormat: UnityEngine.Experimental.Rendering.GraphicsFormat.R16G16B16A16_UNorm,
            enableRandomWrite: true,
            name: "DebugOutput"
        );
    }

    /// <summary>
    /// 释放RTHandles
    /// </summary>
    private void ReleaseRTHandles()
    {
        vBuffer1?.Release();
        vBuffer2?.Release();
        pBuffer1?.Release();
        pBuffer2?.Release();
        dBuffer1?.Release();
        dBuffer2?.Release();
        debugBuffer?.Release();
    }

    /// <summary>
    /// 主模拟函数
    /// </summary>
    private void SimulateFluid()
    {
        // 计算线程组数量
        int threadGroups = Mathf.CeilToInt(size / 8.0f);

        // 设置通用参数
        computeShader.SetFloat("dt", dt);
        computeShader.SetFloat("advectSpeed", advectSpeed);
        computeShader.SetFloat("texSize", size);
        computeShader.SetVector("attenuation", new Vector2(speedAttenuation, colorAttenuation));

        // 设置射线检测源参数
        computeShader.SetVector("sourceUV", hitUV);
        computeShader.SetInt("isHit", isHit ? 1 : 0);
        computeShader.SetVector("sourceDelta", uvDelta);
        computeShader.SetFloat("forceScale", forceScale);
        computeShader.SetFloat("radius", penRadius);

        // 设置UV跳跃参数
        computeShader.SetInt("useUVJump", useUVJump ? 1 : 0);
        if (useUVJump && uvJumpMap != null)
        {
            computeShader.SetTexture(advectionKernel, "UVJumpMap", uvJumpMap);
            computeShader.SetTexture(dyeKernel, "UVJumpMap", uvJumpMap);
            computeShader.SetTexture(debugKernel, "UVJumpMap", uvJumpMap);
        }

        // 设置重力图参数
        computeShader.SetInt("useGravityMap", useGravityMap ? 1 : 0);
        computeShader.SetFloat("gravityStrength", gravityStrength);
        if (useGravityMap && gravityMap != null)
        {
            computeShader.SetTexture(advectionKernel, "GravityMap", gravityMap);
            computeShader.SetTexture(debugKernel, "GravityMap", gravityMap);
        }

        // ========================= 平流项 ==============================
        computeShader.SetTexture(advectionKernel, "VelocityRead", vBuffer1);
        computeShader.SetTexture(advectionKernel, "VelocityWrite", vBuffer2);
        computeShader.SetTexture(advectionKernel, "VelocityTex", vBuffer1);
        computeShader.Dispatch(advectionKernel, threadGroups, threadGroups, 1);
        Swap(ref vBuffer1, ref vBuffer2);

        // ======================== 压力项 ==============================
        computeShader.SetTexture(pressureKernel, "VelocityTex", vBuffer1);
        // 使用雅可比迭代法，循环迭代压力项
        for (int i = 0; i < pressureIterations; i++)
        {
            computeShader.SetTexture(pressureKernel, "PressureRead", pBuffer1);
            computeShader.SetTexture(pressureKernel, "PressureWrite", pBuffer2);
            computeShader.SetTexture(pressureKernel, "PressureTex", pBuffer1);
            computeShader.Dispatch(pressureKernel, threadGroups, threadGroups, 1);
            Swap(ref pBuffer1, ref pBuffer2);
        }

        // ======================== 投影项 ==============================
        computeShader.SetTexture(projectionKernel, "VelocityRead", vBuffer1);
        computeShader.SetTexture(projectionKernel, "VelocityWrite", vBuffer2);
        computeShader.SetTexture(projectionKernel, "VelocityTex", vBuffer1);
        computeShader.SetTexture(projectionKernel, "PressureTex", pBuffer1);
        computeShader.Dispatch(projectionKernel, threadGroups, threadGroups, 1);
        Swap(ref vBuffer1, ref vBuffer2);

        // ======================== 染料项 ===============================
        computeShader.SetTexture(dyeKernel, "DyeRead", dBuffer1);
        computeShader.SetTexture(dyeKernel, "DyeWrite", dBuffer2);
        computeShader.SetTexture(dyeKernel, "VelocityTex", vBuffer1);
        computeShader.SetTexture(dyeKernel, "DyeTex", dBuffer1);
        computeShader.Dispatch(dyeKernel, threadGroups, threadGroups, 1);
        Swap(ref dBuffer1, ref dBuffer2);
    }

    /// <summary>
    /// 执行调试输出
    /// </summary>
    private void ExecuteDebugOutput()
    {
        int threadGroups = Mathf.CeilToInt(size / 8.0f);

        // 设置调试参数
        computeShader.SetInt("debugMode", (int)debugMode);
        computeShader.SetTexture(debugKernel, "VelocityTex", vBuffer1);
        computeShader.SetTexture(debugKernel, "DyeTex", dBuffer1);
        computeShader.SetTexture(debugKernel, "DebugOutput", debugBuffer);

        // 执行调试核
        computeShader.Dispatch(debugKernel, threadGroups, threadGroups, 1);

        // 输出到调试贴图
        if (debugOutputTexture != null)
        {
            Graphics.Blit(debugBuffer, debugOutputTexture);
        }
    }

    /// <summary>
    /// 缓存交换函数
    /// </summary>
    private void Swap(ref RTHandle a, ref RTHandle b)
    {
        RTHandle temp = a;
        a = b;
        b = temp;
    }
    #endregion
}
