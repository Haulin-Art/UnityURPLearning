using System.Collections;
using System.Collections.Generic;
using Unity.Mathematics;
using UnityEngine;
using UnityEngine.Rendering;

/// <summary>
/// 浅水方程流体模拟 - 用于角色的跟随流体场
/// Shallow Water Equations (SWE) Fluid Simulation
/// 
/// 浅水方程相比NS方程的特点：
/// 1. 追踪水位高度h和水平速度场(u,v)
/// 2. 不需要单独的压力求解步骤，水位高度自然产生压力梯度
/// 3. 更适合模拟河流、海洋表层等薄层流体
/// </summary>
public class ChaSWEFluidSimulation : MonoBehaviour
{
    [Header("文件输入")]
    public ComputeShader computeShader;
    public Material mat; //用于展示的材质

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
    [Range(0.0f, 0.5f)] public float dt = 0.05f; // 时间步长
    [Range(0.0f, 0.5f)] public float penRadius = 0.015f; // 画笔的半径 - 恢复默认值
    [Range(0.0f, 50.0f)] public float SpeedScale = 3.0f; // 施加力的大小 - 适中值
    [Range(0.0f, 2.0f)] public float advectSpeed = 0.1f; // 流体平流项速度
    [Range(0.0f, 0.05f)] public float speedAttenuation = 0.001f; // 速度衰减系数
    [Range(0.0f, 0.05f)] public float heightAttenuation = 0.001f; // 水位衰减系数
    
    [Space(10)]
    [Header("浅水方程参数")]
    [Range(1.0f, 100.0f)] public float gravity = 20.0f; // 重力加速度 - 适中值让波浪自然传播
    [Range(0.1f, 10.0f)] public float baseWaterLevel = 1.0f; // 基础水位
    [Range(0.0f, 0.1f)] public float bedFriction = 0.001f; // 河床摩擦系数 - 适中让波浪自然衰减
    
    // 隐藏参数
    private Vector4 footPos; // 脚踝位置
    private int2 footDrop; // 脚步是否落地
    private Vector2 pos = new Vector2(0.5f, 0.5f); // 当前根位置
    private Vector2 prePos; // 上一帧根位置
    private Vector2 force; // 速度方向
    private bool keyDown = false; // 是否按下

    // Compute Buffer - 浅水方程需要的场
    // 状态场：RG = 速度(u,v), B = 水位高度h, A = 地形高度b
    private RTHandle stateBuffer1; // 状态缓存1，用于读取
    private RTHandle stateBuffer2; // 状态缓存2，用于写入
    // 水位高度单独存储用于可视化
    private RTHandle heightBuffer1;
    private RTHandle heightBuffer2;

    // Kernels
    private int advectionKernel;
    private int updateKernel;
    private int boundaryKernel;

    // Start is called before the first frame update
    void Start()
    {
        if (computeShader == null && mat == null)
        {
            Debug.Log("请指定计算着色器与展示材质");
            return;
        }

        force = new Vector2(0f, 0f); // 初始化力
        pos = new Vector2(root.transform.position.x, root.transform.position.z);
        prePos = pos;

        InitializeKernels(); // 获取 Compute Shader 当中的 Kernel ID
        InitializeRTHandles(); // 初始化 RTHandles
    }

    // Update is called once per frame
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

        // 跟随 根节点
        gameObject.transform.position = root.transform.position;
        gameObject.transform.position = new Vector3(root.transform.position.x, 0.05f, root.transform.position.z);

        // 当前的跟位置
        pos = new Vector2(root.transform.position.x, root.transform.position.z);

        force = (prePos - pos);
        if (pos != prePos)
        {
            keyDown = true;
        }
        else
        {
            keyDown = false;
        }
        
        // 脚步是否落地
        if (foot_1.transform.position.y - root.transform.position.y < footHeight)
        {
            footDrop.x = 1;
        }
        else { footDrop.x = 0; }
        
        if (foot_2.transform.position.y - root.transform.position.y < footHeight)
        {
            footDrop.y = 1;
        }
        else { footDrop.y = 0; }
        
        // 足部位置
        footPos = new Vector4(
            foot_1.transform.position.x - root.transform.position.x,
            foot_1.transform.position.z - root.transform.position.z,
            foot_2.transform.position.x - root.transform.position.x,
            foot_2.transform.position.z - root.transform.position.z
        ) / offsetScale;
        
        if (!useFoot) footPos = new Vector4(0, 0, 0, 0);

        // 执行模拟
        SimulateFluid();
        
        // 展示测试 - 使用水位高度作为可视化
        mat.SetTexture("_HeightTex", heightBuffer1);

        prePos = pos;

        // 设置成全局贴图，以及全局参数
        // SWE输出：RG = 速度，B = 水位高度
        Shader.SetGlobalTexture("_SWEVelocityTex", stateBuffer1.rt);
        Shader.SetGlobalVector("_SWEVelocityParams", new Vector4(
            root.transform.position.x,
            root.transform.position.z,
            10.0f, // 模拟区域大小
            baseWaterLevel
        ));
    }

    // 初始化核序号
    void InitializeKernels()
    {
        advectionKernel = computeShader.FindKernel("AdvectionKernel");
        updateKernel = computeShader.FindKernel("UpdateKernel");
        boundaryKernel = computeShader.FindKernel("BoundaryKernel");
    }

    // 用于设置 RTHandle 的格式大小之类的
    void InitializeRTHandles()
    {
        ReleaseRTHandles();
        
        // 状态场：R = u(水平x速度), G = v(水平y速度), B = h(水位高度), A = b(地形高度)
        // 使用RGBA16_SFloat格式，支持正负值和小数
        stateBuffer1 = RTHandles.Alloc(
            size, size,
            colorFormat: UnityEngine.Experimental.Rendering.GraphicsFormat.R16G16B16A16_SFloat,
            enableRandomWrite: true,
            name: "StateBuffer1"
        );
        stateBuffer2 = RTHandles.Alloc(
            size, size,
            colorFormat: UnityEngine.Experimental.Rendering.GraphicsFormat.R16G16B16A16_SFloat,
            enableRandomWrite: true,
            name: "StateBuffer2"
        );
        
        // 水位高度单独存储用于可视化
        heightBuffer1 = RTHandles.Alloc(
            size, size,
            colorFormat: UnityEngine.Experimental.Rendering.GraphicsFormat.R16_SFloat,
            enableRandomWrite: true,
            name: "HeightBuffer1"
        );
        heightBuffer2 = RTHandles.Alloc(
            size, size,
            colorFormat: UnityEngine.Experimental.Rendering.GraphicsFormat.R16_SFloat,
            enableRandomWrite: true,
            name: "HeightBuffer2"
        );
    }

    // 释放之前的 RTHandle
    void ReleaseRTHandles()
    {
        stateBuffer1?.Release();
        stateBuffer2?.Release();
        heightBuffer1?.Release();
        heightBuffer2?.Release();
    }

    // 主模拟函数
    void SimulateFluid()
    {
        // 计算线程组数量
        int threadGroups = Mathf.CeilToInt(size / 8.0f);

        // 设置通用参数
        computeShader.SetFloat("dt", dt);
        computeShader.SetFloat("advectSpeed", advectSpeed);
        computeShader.SetFloat("texSize", size);
        computeShader.SetVector("footPos", footPos);
        computeShader.SetInts("footDrop", footDrop.x, footDrop.y);
        computeShader.SetVector("attenuation", new Vector2(speedAttenuation, heightAttenuation));
        computeShader.SetVector("Force", new Vector3(force.x, force.y, SpeedScale));
        computeShader.SetFloat("radius", penRadius);
        computeShader.SetBool("keyDown", keyDown);
        
        // 浅水方程特有参数
        computeShader.SetFloat("gravity", gravity);
        computeShader.SetFloat("baseWaterLevel", baseWaterLevel);
        computeShader.SetFloat("bedFriction", bedFriction);

        // ========================= 平流步 ==============================
        computeShader.SetTexture(advectionKernel, "StateRead", stateBuffer1);
        computeShader.SetTexture(advectionKernel, "StateWrite", stateBuffer2);
        computeShader.SetTexture(advectionKernel, "StateTex", stateBuffer1);
        computeShader.SetTexture(advectionKernel, "HeightRead", heightBuffer1);
        computeShader.SetTexture(advectionKernel, "HeightWrite", heightBuffer2);
        
        computeShader.Dispatch(advectionKernel, threadGroups, threadGroups, 1);
        
        Swap(ref stateBuffer1, ref stateBuffer2);
        Swap(ref heightBuffer1, ref heightBuffer2);

        // ========================= 更新步 ==============================
        computeShader.SetTexture(updateKernel, "StateRead", stateBuffer1);
        computeShader.SetTexture(updateKernel, "StateWrite", stateBuffer2);
        computeShader.SetTexture(updateKernel, "HeightRead", heightBuffer1);
        computeShader.SetTexture(updateKernel, "HeightWrite", heightBuffer2);
        
        computeShader.Dispatch(updateKernel, threadGroups, threadGroups, 1);
        
        Swap(ref stateBuffer1, ref stateBuffer2);
        Swap(ref heightBuffer1, ref heightBuffer2);

        // ========================= 边界处理 ==============================
        computeShader.SetTexture(boundaryKernel, "StateRead", stateBuffer1);
        computeShader.SetTexture(boundaryKernel, "StateWrite", stateBuffer2);
        computeShader.SetTexture(boundaryKernel, "HeightRead", heightBuffer1);
        computeShader.SetTexture(boundaryKernel, "HeightWrite", heightBuffer2);
        
        // 执行边界处理
        computeShader.Dispatch(boundaryKernel, threadGroups, threadGroups, 1);
        
        // 交换缓冲区
        Swap(ref stateBuffer1, ref stateBuffer2);
        Swap(ref heightBuffer1, ref heightBuffer2);
    }

    // 缓存交换函数
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
