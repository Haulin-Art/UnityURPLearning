using System.Collections;
using System.Collections.Generic;
using Unity.Mathematics;
using UnityEngine;
using UnityEngine.Rendering;

/// <summary>
/// 浅水方程流体模拟 - 用于角色的跟随流体场
/// Shallow Water Equations (SWE) Fluid Simulation
/// 基于 Saint-Venant 方程组实现，使用稳定的有限体积法
/// </summary>
public class kn_ChaSWEFluidSimulation : MonoBehaviour
{
    [Header("文件输入")]
    public ComputeShader computeShader;
    public Material mat; // 用于展示的材质

    [Space(10)]
    [Header("跟随设置")]
    public GameObject root; // 跟踪根部
    public bool useFoot = true;
    public GameObject foot_1;
    public GameObject foot_2;
    [Range(0.0f, 20.0f)] public float offsetScale = 10.0f;
    [Range(0.0f, 1.0f)] public float footHeight = 0.05f; // 脚踝落地高度

    [Space(10)]
    [Header("模拟参数设置")]
    public int size = 256; // 模拟网格大小
    [Range(0.001f, 0.1f)] public float dt = 0.016f; // 时间步长 (减小以保证稳定性)
    [Range(0.0f, 0.2f)] public float penRadius = 0.05f; // 画笔半径
    [Range(0.0f, 10.0f)] public float SpeedScale = 2.0f; // 施加力的大小
    [Range(0.0f, 0.05f)] public float speedAttenuation = 0.01f; // 速度衰减系数
    [Range(0.0f, 0.05f)] public float heightAttenuation = 0.005f; // 高度衰减系数

    [Space(10)]
    [Header("浅水方程参数")]
    [Range(1.0f, 50.0f)] public float gravity = 9.8f; // 重力加速度 (标准重力)
    [Range(0.5f, 5.0f)] public float baseWaterLevel = 1.0f; // 基准水位
    [Range(0.0f, 0.01f)] public float bedFriction = 0.001f; // 河床摩擦系数
    [Range(0.0f, 0.1f)] public float viscosity = 0.01f; // 粘性系数

    // 隐藏参数
    private Vector4 footPos; // 脚步位置
    private int2 footDrop; // 脚步是否落地
    private Vector2 pos = new Vector2(0.5f, 0.5f); // 当前根位置
    private Vector2 prePos; // 上一帧根位置
    private Vector2 force; // 速度方向
    private bool keyDown = false; // 是否按下

    // Compute Buffer
    // State: RG = velocity (u,v), B = water height (h), A = terrain height
    private RTHandle stateBuffer1; // 状态缓存1，用于读取
    private RTHandle stateBuffer2; // 状态缓存2，用于写入

    // Kernels
    private int advectionKernel; // 平流核
    private int sweUpdateKernel; // 浅水方程更新核
    private int boundaryKernel; // 边界处理核

    void Start()
    {
        if (computeShader == null && mat == null)
        {
            Debug.Log("请指定计算着色器与展示材质");
            return;
        }

        force = new Vector2(0f, 0f);
        pos = new Vector2(root.transform.position.x, root.transform.position.z);
        prePos = pos;

        InitializeKernels();
        InitializeRTHandles();
        InitializeTerrain();
    }

    void Update()
    {
        if (computeShader == null && mat == null)
        {
            Debug.Log("请指定计算着色器与展示材质");
            return;
        }
        if (root == null && foot_1 == null && foot_2 == null)
        {
            Debug.Log("请指定追踪root与脚踝骨骼");
            return;
        }

        // 跟随根节点
        gameObject.transform.position = new Vector3(root.transform.position.x, 0.05f, root.transform.position.z);

        // 当前根位置
        pos = new Vector2(root.transform.position.x, root.transform.position.z);

        // 计算移动方向
        force = (prePos - pos);
        keyDown = (pos != prePos);

        // 脚步是否落地
        footDrop.x = (foot_1.transform.position.y - root.transform.position.y < footHeight) ? 1 : 0;
        footDrop.y = (foot_2.transform.position.y - root.transform.position.y < footHeight) ? 1 : 0;

        // 足部位置（相对于root的偏移，归一化到0-1范围）
        footPos = new Vector4(
            foot_1.transform.position.x - root.transform.position.x,
            foot_1.transform.position.z - root.transform.position.z,
            foot_2.transform.position.x - root.transform.position.x,
            foot_2.transform.position.z - root.transform.position.z
        ) / offsetScale;

        if (!useFoot) footPos = new Vector4(0, 0, 0, 0);

        // 执行模拟
        SimulateFluid();

        // 展示
        mat.SetTexture("_StateTex", stateBuffer1);

        prePos = pos;

        // 设置全局参数
        Shader.SetGlobalTexture("_kn_SWEStateTex", stateBuffer1.rt);
        Shader.SetGlobalVector("_kn_SWEParams", new Vector4(
            root.transform.position.x,
            root.transform.position.z,
            10.0f,
            baseWaterLevel
        ));
    }

    void InitializeKernels()
    {
        advectionKernel = computeShader.FindKernel("kn_AdvectionKernel");
        sweUpdateKernel = computeShader.FindKernel("kn_SWEUpdateKernel");
        boundaryKernel = computeShader.FindKernel("kn_BoundaryKernel");
    }

    void InitializeRTHandles()
    {
        ReleaseRTHandles();

        // State: RG = velocity (u,v), B = water height (h), A = terrain height
        stateBuffer1 = RTHandles.Alloc(
            size, size,
            colorFormat: UnityEngine.Experimental.Rendering.GraphicsFormat.R16G16B16A16_SFloat,
            enableRandomWrite: true,
            name: "kn_StateBuffer1"
        );
        stateBuffer2 = RTHandles.Alloc(
            size, size,
            colorFormat: UnityEngine.Experimental.Rendering.GraphicsFormat.R16G16B16A16_SFloat,
            enableRandomWrite: true,
            name: "kn_StateBuffer2"
        );
    }

    // 初始化地形和初始水位
    void InitializeTerrain()
    {
        // 这里可以初始化地形，目前使用平坦地形
        // 地形存储在 state.a 通道
        // 如果需要复杂地形，可以在 compute shader 中初始化
    }

    void ReleaseRTHandles()
    {
        stateBuffer1?.Release();
        stateBuffer2?.Release();
    }

    void SimulateFluid()
    {
        int threadGroups = Mathf.CeilToInt(size / 8.0f);

        // 设置通用参数
        computeShader.SetFloat("dt", dt);
        computeShader.SetFloat("texSize", size);
        computeShader.SetVector("footPos", footPos);
        computeShader.SetInts("footDrop", footDrop.x, footDrop.y);
        computeShader.SetVector("attenuation", new Vector2(speedAttenuation, heightAttenuation));
        computeShader.SetVector("Force", new Vector3(force.x, force.y, SpeedScale));
        computeShader.SetFloat("radius", penRadius);
        computeShader.SetBool("keyDown", keyDown);
        computeShader.SetFloat("gravity", gravity);
        computeShader.SetFloat("baseWaterLevel", baseWaterLevel);
        computeShader.SetFloat("bedFriction", bedFriction);
        computeShader.SetFloat("viscosity", viscosity);

        // ========================= 平流步（跟随移动 + 添加外力和水源）=========================
        computeShader.SetTexture(advectionKernel, "StateRead", stateBuffer1);
        computeShader.SetTexture(advectionKernel, "StateWrite", stateBuffer2);
        computeShader.SetTexture(advectionKernel, "StateTex", stateBuffer1);

        computeShader.Dispatch(advectionKernel, threadGroups, threadGroups, 1);
        Swap(ref stateBuffer1, ref stateBuffer2);

        // ========================= 浅水方程更新步 =========================
        computeShader.SetTexture(sweUpdateKernel, "StateRead", stateBuffer1);
        computeShader.SetTexture(sweUpdateKernel, "StateWrite", stateBuffer2);
        computeShader.SetTexture(sweUpdateKernel, "StateTex", stateBuffer1);

        computeShader.Dispatch(sweUpdateKernel, threadGroups, threadGroups, 1);
        Swap(ref stateBuffer1, ref stateBuffer2);

        // ========================= 边界处理 =========================
        computeShader.SetTexture(boundaryKernel, "StateRead", stateBuffer1);
        computeShader.SetTexture(boundaryKernel, "StateWrite", stateBuffer2);
        computeShader.SetTexture(boundaryKernel, "StateTex", stateBuffer1);

        computeShader.Dispatch(boundaryKernel, threadGroups, threadGroups, 1);
        Swap(ref stateBuffer1, ref stateBuffer2);
    }

    void Swap(ref RTHandle a, ref RTHandle b)
    {
        RTHandle temp = a;
        a = b;
        b = temp;
    }

    private void OnDestroy()
    {
        ReleaseRTHandles();
    }

    private void OnDisable()
    {
        ReleaseRTHandles();
    }
}
