using UnityEngine;
using UnityEngine.Rendering;

/// <summary>
/// 浅水方程模拟控制器
/// 步骤1：速度场平流
/// 步骤2：高度场平流
/// </summary>
public class ShallowWaterSimulation : MonoBehaviour
{
    /// <summary>
    /// 输出类型枚举
    /// </summary>
    public enum OutputType
    {
        Velocity,   // 速度场
        Height,     // 高度场
        Pressure    // 压力场（高度梯度）
    }

    [Header("输出设置")]
    [Tooltip("输出贴图（用于Debug查看）")]
    public RenderTexture outputTexture;

    [Tooltip("输出类型")]
    public OutputType outputType = OutputType.Velocity;

    [Header("贴图设置")]
    [Tooltip("模拟分辨率")]
    public int size = 256;

    [Tooltip("是否输出Debug信息")]
    public bool debugInfo = false;

    [Header("Compute Shader")]
    public ComputeShader computeShader;

    [Header("模拟参数")]
    public bool enableSimulation = true;
    public float dt = 0.016f;
    public float advectSpeed = 1.0f;
    public float damping = 0.01f;

    [Tooltip("压力强度（高度梯度对速度的影响）")]
    public float pressureStrength = 0.5f;

    [Header("源参数")]
    public bool enableSource = true;
    public Vector2 sourcePos = new Vector2(0.5f, 0.5f);
    public float sourceRadius = 0.05f;
    public float velocityStrength = 1.0f;
    public float heightStrength = 1.0f;

    [Header("控制参数")]
    [Tooltip("WASD移动速度")]
    public float moveSpeed = 0.5f;

    // RTHandle 缓冲区
    private RTHandle vBuffer1;  // 速度缓冲1
    private RTHandle vBuffer2;  // 速度缓冲2
    private RTHandle hBuffer1;  // 高度缓冲1
    private RTHandle hBuffer2;  // 高度缓冲2
    private RTHandle pBuffer;   // 压力场缓冲（用于Debug可视化）

    // Kernel 索引
    private int kernelAdvection;

    // 状态
    private bool isInitialized = false;

    private void Start()
    {
        Initialize();
    }

    private void OnDestroy()
    {
        ReleaseRTHandles();
    }

    private void Initialize()
    {
        if (computeShader == null)
        {
            Debug.LogError("ShallowWaterSimulation: Compute Shader未设置！");
            return;
        }

        InitializeKernels();
        InitializeRTHandles();
        ClearBuffers();

        isInitialized = true;
        Debug.Log("ShallowWaterSimulation: 初始化完成");
    }

    private void InitializeKernels()
    {
        kernelAdvection = computeShader.FindKernel("AdvectionKernel");
    }

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

        // 高度场：单通道
        hBuffer1 = RTHandles.Alloc(
            size, size,
            colorFormat: UnityEngine.Experimental.Rendering.GraphicsFormat.R16_SFloat,
            enableRandomWrite: true,
            name: "Height1"
        );
        hBuffer2 = RTHandles.Alloc(
            size, size,
            colorFormat: UnityEngine.Experimental.Rendering.GraphicsFormat.R16_SFloat,
            enableRandomWrite: true,
            name: "Height2"
        );

        // 压力场：RG两个通道（梯度向量）
        pBuffer = RTHandles.Alloc(
            size, size,
            colorFormat: UnityEngine.Experimental.Rendering.GraphicsFormat.R16G16_SFloat,
            enableRandomWrite: true,
            name: "Pressure"
        );
    }

    private void ReleaseRTHandles()
    {
        vBuffer1?.Release();
        vBuffer2?.Release();
        hBuffer1?.Release();
        hBuffer2?.Release();
        pBuffer?.Release();
    }

    private void Update()
    {
        HandleInput();

        if (enableSimulation)
        {
            StepSimulation();
        }

        // 输出到debug贴图
        UpdateOutputTexture();

        if (Input.GetKeyDown(KeyCode.P))
        {
            enableSimulation = !enableSimulation;
        }

        if (Input.GetKeyDown(KeyCode.R))
        {
            ClearBuffers();
        }
    }

    private void HandleInput()
    {
        Vector2 moveDir = Vector2.zero;

        if (Input.GetKey(KeyCode.W)) moveDir.y += 1.0f;
        if (Input.GetKey(KeyCode.S)) moveDir.y -= 1.0f;
        if (Input.GetKey(KeyCode.A)) moveDir.x -= 1.0f;
        if (Input.GetKey(KeyCode.D)) moveDir.x += 1.0f;

        if (moveDir != Vector2.zero)
        {
            moveDir.Normalize();
            sourcePos += moveDir * moveSpeed * Time.deltaTime;
            sourcePos = new Vector2(
                Mathf.Clamp01(sourcePos.x),
                Mathf.Clamp01(sourcePos.y)
            );
        }
    }

    private void StepSimulation()
    {
        if (!isInitialized) return;

        int threadGroups = Mathf.CeilToInt(size / 8.0f);

        // 设置通用参数
        computeShader.SetFloat("texSize", size);
        computeShader.SetFloat("dt", dt);
        computeShader.SetFloat("advectSpeed", advectSpeed);
        computeShader.SetFloat("damping", damping);
        computeShader.SetFloat("pressureStrength", pressureStrength);
        computeShader.SetBool("enableSource", enableSource);
        computeShader.SetVector("sourcePos", sourcePos);
        computeShader.SetFloat("sourceRadius", sourceRadius);
        computeShader.SetFloat("velocityStrength", velocityStrength);
        computeShader.SetFloat("heightStrength", heightStrength);

        // 平流项（速度场 + 高度场）
        computeShader.SetTexture(kernelAdvection, "VelocityRead", vBuffer1);
        computeShader.SetTexture(kernelAdvection, "VelocityWrite", vBuffer2);
        computeShader.SetTexture(kernelAdvection, "HeightRead", hBuffer1);
        computeShader.SetTexture(kernelAdvection, "HeightWrite", hBuffer2);
        computeShader.SetTexture(kernelAdvection, "PressureWrite", pBuffer);
        computeShader.Dispatch(kernelAdvection, threadGroups, threadGroups, 1);

        // 交换缓冲区
        Swap(ref vBuffer1, ref vBuffer2);
        Swap(ref hBuffer1, ref hBuffer2);

        // Debug输出
        if (debugInfo && Time.frameCount % 60 == 0)
        {
            Debug.Log($"[ShallowWater] sourcePos: {sourcePos}");
        }
    }

    private void UpdateOutputTexture()
    {
        if (outputTexture == null) return;

        RenderTexture sourceRT = null;
        switch (outputType)
        {
            case OutputType.Velocity:
                sourceRT = vBuffer1;
                break;
            case OutputType.Height:
                sourceRT = hBuffer1;
                break;
            case OutputType.Pressure:
                sourceRT = pBuffer;
                break;
        }

        if (sourceRT != null)
        {
            Graphics.Blit(sourceRT, outputTexture);
        }
    }

    private void ClearBuffers()
    {
        if (!isInitialized) return;

        RenderTexture.active = vBuffer1;
        GL.Clear(true, true, Color.clear);
        RenderTexture.active = vBuffer2;
        GL.Clear(true, true, Color.clear);
        RenderTexture.active = hBuffer1;
        GL.Clear(true, true, Color.clear);
        RenderTexture.active = hBuffer2;
        GL.Clear(true, true, Color.clear);
        RenderTexture.active = null;
    }

    private void Swap(ref RTHandle a, ref RTHandle b)
    {
        RTHandle temp = a;
        a = b;
        b = temp;
    }

    /// <summary>
    /// 获取当前速度场贴图
    /// </summary>
    public RenderTexture GetVelocityTexture()
    {
        return vBuffer1;
    }

    /// <summary>
    /// 获取当前高度场贴图
    /// </summary>
    public RenderTexture GetHeightTexture()
    {
        return hBuffer1;
    }
}
