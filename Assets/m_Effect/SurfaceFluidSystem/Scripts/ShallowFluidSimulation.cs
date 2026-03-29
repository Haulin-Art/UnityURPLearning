using UnityEngine;
using UnityEngine.Rendering;

/// <summary>
/// 调试模式枚举
/// </summary>

/// <summary>
/// 浅水方程流体模拟脚本
/// 基于浅水方程的流体模拟，通过射线检测获取源位置
/// 支持UV岛跳跃功能，实现跨UV岛的流体传输
/// 支持重力方向图，实现基于贴图的重力效果
/// 支持床底高度图，实现水流成股效果
/// 
/// 纹理格式：RG=速度(xy), B=高度
/// 优化：合并速度和高度纹理，采样次数从12次减少到6次
/// 
/// 输出：
/// - 流体纹理：RG=速度, B=高度
/// - 法线图：RG=法线xy, B=法线z（根据水高梯度计算）
/// </summary>
public class ShallowFluidSimulation : MonoBehaviour
{
    [Header("文件输入")]
    [Tooltip("浅水方程计算着色器")]
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
    [Tooltip("UV跳跃贴图（RG:跳跃目标UV, Z:跳跃边缘, A:UV范围），支持Texture2D和RenderTexture")]
    public Texture uvJumpMap;
    
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
    [Header("床底高度设置")]
    [Tooltip("床底高度贴图（噪波地形，用于水流成股效果）")]
    public Texture2D bedHeightMap;
    
    [Tooltip("是否启用床底高度图")]
    public bool useBedHeight = false;
    
    [Tooltip("床底高度缩放系数")]
    [Range(0.0f, 5.0f)]
    public float bedHeightScale = 0.1f;
    
    [Tooltip("床底高度图平铺次数")]
    [Range(1.0f, 32.0f)]
    public float bedTiling = 8.0f;
    
    [Tooltip("床底衰减系数（用于形成小股水流）")]
    [Range(0.0f, 20.0f)]
    public float bedAttenFactor = 5.0f;
    
    [Tooltip("接缝处衰减增强系数")]
    [Range(1.0f, 20.0f)]
    public float gapAttenuationEnhancement = 10.0f;

    [Space(10)]
    [Header("物理参数")]
    [Tooltip("表面张力系数（控制水面的聚拢程度）")]
    [Range(0.0f, 1.0f)]
    public float surfaceTension = 0.01f;
    
    [Tooltip("额外重力系数（控制重力方向力的强度）")]
    [Range(0.0f, 2.0f)]
    public float extraGravityStrength = 0.3f;
    
    [Tooltip("摩擦力系数（控制水流减速）")]
    [Range(0.0f, 0.1f)]
    public float friction = 0.002f;

    [Space(10)]
    [Header("法线图输出")]
    [Tooltip("法线图输出贴图（RG=法线xy, B=法线z）")]
    public RenderTexture normalOutputTexture;

    [Space(10)]
    [Header("流体数据输出")]
    [Tooltip("流体数据输出贴图（RG=速度, B=高度）")]
    public RenderTexture dataOuputTexture;

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
    
    [Tooltip("流体平流项速度")]
    [Range(0.0f, 1.0f)]
    public float advectSpeed = 0.25f;
    
    [Tooltip("速度衰减系数")]
    [Range(0.0f, 0.2f)]
    public float velocityAttenuation = 0.005f;
    
    [Tooltip("高度衰减系数")]
    [Range(0.0f, 0.2f)]
    public float heightAttenuation = 0.005f;

    // Compute Buffer - 合并速度(RG)和高度(B)为一个三通道纹理
    private RTHandle fluidBuffer1;  // 流体缓存1，用于读取
    private RTHandle fluidBuffer2;  // 流体缓存2，用于写入
    private RTHandle normalBuffer;  // 法线图缓存
    private RTHandle debugBuffer;   // 调试输出缓存

    // Kernel
    private int shallowWaterKernel;

    // 射线检测数据缓存
    private bool isHit = false;
    private Vector2 hitUV = Vector2.zero;

    private void Start()
    {
        if (computeShader == null)
        {
            Debug.LogError("ShallowFluidSimulation: 请指定计算着色器！");
            return;
        }

        if (displayMaterial == null)
        {
            Debug.LogWarning("ShallowFluidSimulation: 展示材质未设置，将无法看到效果");
        }

        if (raycastDetector == null)
        {
            Debug.LogWarning("ShallowFluidSimulation: 射线检测器未设置，将无法添加流体源");
        }

        // 检查UV跳跃贴图
        if (useUVJump && uvJumpMap == null)
        {
            Debug.LogWarning("ShallowFluidSimulation: 启用了UV跳跃功能但未设置UV跳跃贴图！");
        }

        // 检查重力图
        if (useGravityMap && gravityMap == null)
        {
            Debug.LogWarning("ShallowFluidSimulation: 启用了重力图功能但未设置重力方向贴图！");
        }

        // 检查床底高度图
        if (useBedHeight && bedHeightMap == null)
        {
            Debug.LogWarning("ShallowFluidSimulation: 启用了床底高度图功能但未设置床底高度贴图！");
        }

        InitializeKernels();
        InitializeRTHandles();
    }

    private void Update()
    {
        if (computeShader == null) return;

        // 从射线检测器获取数据
        UpdateRaycastData();

        // 执行浅水方程模拟
        SimulateShallowWater();

        // 更新输出贴图
        if (outputTexture != null)
        {
            Graphics.Blit(fluidBuffer1, outputTexture);
        }

        // 更新法线图输出贴图
        if (normalOutputTexture != null)
        {
            Graphics.Blit(normalBuffer, normalOutputTexture);
        }

        // 更新展示材质
        if (displayMaterial != null)
        {
            displayMaterial.SetTexture("_MainTex", fluidBuffer1);
            displayMaterial.SetTexture("_NormalMap", normalBuffer);
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
            return;
        }

        Vector2 uvDelta;
        raycastDetector.GetRaycastData(out isHit, out hitUV, out uvDelta);

    }

    /// <summary>
    /// 初始化核序号
    /// </summary>
    private void InitializeKernels()
    {
        shallowWaterKernel = computeShader.FindKernel("ShallowWaterKernel");
    }

    /// <summary>
    /// 初始化RTHandles
    /// </summary>
    private void InitializeRTHandles()
    {
        ReleaseRTHandles();

        // 流体场：RGB三通道 (RG=速度, B=高度)
        fluidBuffer1 = RTHandles.Alloc(
            size, size,
            colorFormat: UnityEngine.Experimental.Rendering.GraphicsFormat.R16G16B16A16_SFloat,
            enableRandomWrite: true,
            name: "Fluid1"
        );
        fluidBuffer2 = RTHandles.Alloc(
            size, size,
            colorFormat: UnityEngine.Experimental.Rendering.GraphicsFormat.R16G16B16A16_SFloat,
            enableRandomWrite: true,
            name: "Fluid2"
        );

        // 法线图缓存：RGB三通道 (RG=法线xy, B=法线z)
        normalBuffer = RTHandles.Alloc(
            size, size,
            colorFormat: UnityEngine.Experimental.Rendering.GraphicsFormat.R16G16B16A16_SFloat,
            enableRandomWrite: true,
            name: "NormalOutput"
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
        fluidBuffer1?.Release();
        fluidBuffer2?.Release();
        normalBuffer?.Release();
        debugBuffer?.Release();
    }

    /// <summary>
    /// 主模拟函数 - 浅水方程
    /// </summary>
    private void SimulateShallowWater()
    {
        // 计算线程组数量
        int threadGroups = Mathf.CeilToInt(size / 8.0f);

        // 设置通用参数
        computeShader.SetFloat("dt", Time.deltaTime * 100.0f * dt);
        computeShader.SetFloat("advectSpeed", advectSpeed);
        computeShader.SetFloat("texSize", size);
        computeShader.SetVector("attenuation", new Vector2(velocityAttenuation, heightAttenuation));

        // 设置射线检测源参数
        computeShader.SetVector("sourceUV", hitUV);
        computeShader.SetInt("isHit", isHit ? 1 : 0);
        computeShader.SetFloat("radius", penRadius);

        // 设置UV跳跃参数
        computeShader.SetInt("useUVJump", useUVJump ? 1 : 0);
        if (useUVJump && uvJumpMap != null)
        {
            computeShader.SetTexture(shallowWaterKernel, "UVJumpMap", uvJumpMap);
        }

        // 设置重力图参数
        computeShader.SetInt("useGravityMap", useGravityMap ? 1 : 0);
        computeShader.SetFloat("gravityStrength", gravityStrength);
        if (useGravityMap && gravityMap != null)
        {
            computeShader.SetTexture(shallowWaterKernel, "GravityMap", gravityMap);
        }

        // 设置床底高度图参数
        computeShader.SetInt("useBedHeight", useBedHeight ? 1 : 0);
        computeShader.SetFloat("bedHeightScale", bedHeightScale);
        computeShader.SetFloat("bedTiling", bedTiling);
        computeShader.SetFloat("bedAttenFactor", bedAttenFactor);
        computeShader.SetFloat("gapAttenuationEnhancement", gapAttenuationEnhancement);
        if (useBedHeight && bedHeightMap != null)
        {
            computeShader.SetTexture(shallowWaterKernel, "BedHeightMap", bedHeightMap);
        }

        // 设置物理参数
        computeShader.SetFloat("surfaceTension", surfaceTension);
        computeShader.SetFloat("extraGravityStrength", extraGravityStrength);
        computeShader.SetFloat("friction", friction);


        // ======================== 浅水方程核 ==============================
        // 设置读取纹理（合并的速度+高度）
        computeShader.SetTexture(shallowWaterKernel, "FluidTex", fluidBuffer1);
        
        // 设置写入纹理
        computeShader.SetTexture(shallowWaterKernel, "FluidWrite", fluidBuffer2);
        
        // 设置法线图输出纹理
        computeShader.SetTexture(shallowWaterKernel, "NormalOutput", normalBuffer);

        // 执行计算
        computeShader.Dispatch(shallowWaterKernel, threadGroups, threadGroups, 1);

        // 交换缓冲区
        Swap(ref fluidBuffer1, ref fluidBuffer2);
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

    /// <summary>
    /// 手动添加源（供外部调用）
    /// </summary>
    /// <param name="uv">UV坐标</param>
    public void AddSource(Vector2 uv)
    {
        hitUV = uv;
        isHit = true;
    }

    /// <summary>
    /// 手动清除源（供外部调用）
    /// </summary>
    public void ClearSource()
    {
        isHit = false;
    }

    /// <summary>
    /// 获取当前流体纹理（供外部使用）
    /// RG=速度, B=高度
    /// </summary>
    public RenderTexture GetFluidTexture()
    {
        return fluidBuffer1?.rt;
    }

    /// <summary>
    /// 获取当前法线图纹理（供外部使用）
    /// RG=法线xy, B=法线z
    /// </summary>
    public RenderTexture GetNormalTexture()
    {
        return normalBuffer?.rt;
    }
}
