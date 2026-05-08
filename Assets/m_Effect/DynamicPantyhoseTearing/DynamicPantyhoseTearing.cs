using UnityEngine;
using UnityEngine.Rendering;

/// <summary>
/// 纯粹浅水方程流体模拟
/// 基于浅水方程(SWE)的流体模拟，通过射线检测获取源位置
///
/// 纹理格式: RG=速度(xy), B=高度
/// 输出:
/// - 流体纹理: RG=速度, B=高度
/// - 法线图:   RG=法线xy, B=法线z
/// </summary>
public class DynamicPantyhoseTearing : MonoBehaviour
{
    [Header("文件输入")]
    [Tooltip("浅水方程计算着色器")]
    public ComputeShader computeShader;

    [Tooltip("用于展示流体效果的材质")]
    public Material displayMaterial;

    [Tooltip("输出贴图")]
    public RenderTexture outputTexture;

    /////////////////////////////////////////////////////////////////////
    [Header("射线检测源")]
    [Tooltip("射线检测器组件，用于获取UV位置")]
    public RaycastTargetDetector raycastDetector;

    /////////////////////////////////////////////////////////////////////
    [Space(10)]
    [Header("流体着色设置")]
    public Material fluidMaterial;
    public Color fluidColor = Color.blue;
    [Range(0.0f, 10.0f)]
    public float fluidTransScale = 1.0f;

    /////////////////////////////////////////////////////////////////////
    [Space(10)]
    [Header("物理参数")]
    [Tooltip("表面张力系数")]
    [Range(0.0f, 1.0f)]
    public float surfaceTension = 0.01f;

    [Tooltip("重力加速度")]
    [Range(0.0f, 10.0f)]
    public float gravityStrength = 1.0f;

    [Tooltip("摩擦力系数")]
    [Range(0.0f, 0.1f)]
    public float friction = 0.002f;

    /////////////////////////////////////////////////////////////////////
    [Space(10)]
    [Header("法线图输出")]
    [Tooltip("法线图输出贴图（RG=法线xy, B=法线z）")]
    public RenderTexture normalOutputTexture;

    /////////////////////////////////////////////////////////////////////
    [Space(10)]
    [Header("模拟参数设置")]
    [Tooltip("模拟网格大小")]
    public int size = 256;

    [Tooltip("帧步长")]
    [Range(0.0f, 1.0f)]
    public float dt = 0.15f;

    [Tooltip("画笔半径")]
    [Range(0.0f, 0.05f)]
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

    // 流体缓存
    private RTHandle fluidBuffer1;
    private RTHandle fluidBuffer2;
    private RTHandle normalBuffer;

    // Kernel
    private int shallowWaterKernel;

    // 射线检测数据缓存
    private bool isHit = false;
    private Vector2 hitUV = Vector2.zero;

    private void Start()
    {
        if (computeShader == null)
        {
            Debug.LogError("DynamicPantyhoseTearing: 请指定计算着色器！");
            return;
        }

        if (displayMaterial == null)
            Debug.LogWarning("DynamicPantyhoseTearing: 展示材质未设置，将无法看到效果");

        if (raycastDetector == null)
            Debug.LogWarning("DynamicPantyhoseTearing: 射线检测器未设置，将无法添加流体源");

        InitializeKernels();
        InitializeRTHandles();
    }

    private void Update()
    {
        SetFluidMat();

        if (computeShader == null) return;

        UpdateRaycastData();
        SimulateShallowWater();

        if (outputTexture != null)
            Graphics.Blit(fluidBuffer1, outputTexture);

        if (normalOutputTexture != null)
            Graphics.Blit(normalBuffer, normalOutputTexture);

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

    private void UpdateRaycastData()
    {
        if (raycastDetector == null)
        {
            isHit = false;
            return;
        }

        raycastDetector.GetRaycastData(out isHit, out hitUV, out _);
    }

    private void InitializeKernels()
    {
        shallowWaterKernel = computeShader.FindKernel("ShallowWaterKernel");
    }

    private void InitializeRTHandles()
    {
        ReleaseRTHandles();

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

        normalBuffer = RTHandles.Alloc(
            size, size,
            colorFormat: UnityEngine.Experimental.Rendering.GraphicsFormat.R16G16B16A16_SFloat,
            enableRandomWrite: true,
            name: "NormalOutput"
        );
    }

    private void ReleaseRTHandles()
    {
        fluidBuffer1?.Release();
        fluidBuffer2?.Release();
        normalBuffer?.Release();
    }

    private void SimulateShallowWater()
    {
        int threadGroups = Mathf.CeilToInt(size / 8.0f);

        computeShader.SetFloat("dt", Time.deltaTime * 100.0f * dt);
        computeShader.SetFloat("advectSpeed", advectSpeed);
        computeShader.SetFloat("texSize", size);
        computeShader.SetVector("attenuation", new Vector2(velocityAttenuation, heightAttenuation));

        computeShader.SetVector("sourceUV", hitUV);
        computeShader.SetInt("isHit", isHit ? 1 : 0);
        computeShader.SetFloat("radius", penRadius);

        computeShader.SetFloat("surfaceTension", surfaceTension);
        computeShader.SetFloat("gravityStrength", gravityStrength);
        computeShader.SetFloat("friction", friction);

        computeShader.SetTexture(shallowWaterKernel, "FluidTex", fluidBuffer1);
        computeShader.SetTexture(shallowWaterKernel, "FluidWrite", fluidBuffer2);
        computeShader.SetTexture(shallowWaterKernel, "NormalOutput", normalBuffer);

        computeShader.Dispatch(shallowWaterKernel, threadGroups, threadGroups, 1);

        Swap(ref fluidBuffer1, ref fluidBuffer2);
    }

    private void Swap(ref RTHandle a, ref RTHandle b)
    {
        RTHandle temp = a;
        a = b;
        b = temp;
    }

    public void AddSource(Vector2 uv)
    {
        hitUV = uv;
        isHit = true;
    }

    public void ClearSource()
    {
        isHit = false;
    }

    public RenderTexture GetFluidTexture()
    {
        return fluidBuffer1?.rt;
    }

    public RenderTexture GetNormalTexture()
    {
        return normalBuffer?.rt;
    }

    public void SetFluidMat()
    {
        if (fluidMaterial != null)
        {
            fluidMaterial.SetColor("_FluidColor", fluidColor);
            fluidMaterial.SetFloat("_FluidThickness", fluidTransScale);
        }
    }
}
