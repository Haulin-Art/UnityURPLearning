using System.Collections;
using System.Collections.Generic;
using Unity.Mathematics;
using UnityEngine;
using UnityEngine.Rendering;

/// 浅水方程流体模拟 - 真正的波浪传播
/// 基于波动方程: ∂²h/∂t² = c² * ∇²h
public class Kimi_ChaSWEFluidSimulation : MonoBehaviour
{
    [Header("文件输入")]
    public ComputeShader computeShader;
    public Material mat;

    [Space(10)]
    [Header("跟随设置")]
    public GameObject root;
    public bool useFoot = true;
    public GameObject foot_1;
    public GameObject foot_2;
    [Range(0.0f, 20.0f)] public float offsetScale = 10.0f;
    [Range(0.0f, 1.0f)] public float footHeight = 0.05f;

    [Space(10)]
    [Header("模拟参数设置")]
    public int size = 256;
    [Range(0.001f, 0.05f)] public float dt = 0.02f;
    [Range(0.0f, 0.5f)] public float penRadius = 0.08f;
    [Range(0.0f, 5.0f)] public float waveStrength = 1.0f;
    [Range(0.95f, 1.0f)] public float damping = 0.99f;
    [Range(1.0f, 100.0f)] public float gravity = 50.0f;
    [Range(0.1f, 5.0f)] public float waterDepth = 2.0f;

    // 隐藏参数
    private Vector4 footPos;
    private int2 footDrop;
    private Vector2 pos = new Vector2(0.5f, 0.5f);
    private Vector2 prePos;
    private Vector2 velocity;

    // Compute Buffer - 使用三缓冲实现波动方程
    private RTHandle hBufferCurrent;  // 当前帧高度
    private RTHandle hBufferNext;     // 下一帧高度
    private RTHandle hBufferPrev;     // 上一帧高度
    private RTHandle normalBuffer;    // 法线贴图

    // Kernels
    private int initKernel;
    private int waveKernel;
    private int normalKernel;

    void Start()
    {
        if (computeShader == null)
        {
            Debug.LogError("请指定计算着色器");
            return;
        }

        velocity = new Vector2(0f, 0f);
        
        if (root != null)
        {
            pos = new Vector2(root.transform.position.x, root.transform.position.z);
            prePos = pos;
        }

        InitializeKernels();
        InitializeRTHandles();
        InitializeFluid();
        
        Debug.Log("SWE Wave Simulation Initialized");
    }

    void Update()
    {
        if (computeShader == null)
        {
            Debug.LogError("请指定计算着色器");
            return;
        }
        if (root == null || foot_1 == null || foot_2 == null)
        {
            return;
        }

        // 跟随根节点
        gameObject.transform.position = new Vector3(root.transform.position.x, 0.05f, root.transform.position.z);

        // 当前根位置
        pos = new Vector2(root.transform.position.x, root.transform.position.z);
        velocity = pos - prePos;

        // 脚步是否落地
        float foot1Height = foot_1.transform.position.y - root.transform.position.y;
        float foot2Height = foot_2.transform.position.y - root.transform.position.y;
        
        footDrop.x = (foot1Height < footHeight) ? 1 : 0;
        footDrop.y = (foot2Height < footHeight) ? 1 : 0;

        // 足部位置（相对于root的局部坐标，归一化到UV空间）
        footPos = new Vector4(
            foot_1.transform.position.x - root.transform.position.x,
            foot_1.transform.position.z - root.transform.position.z,
            foot_2.transform.position.x - root.transform.position.x,
            foot_2.transform.position.z - root.transform.position.z
        ) / offsetScale;

        if (!useFoot) footPos = Vector4.zero;

        // 执行模拟
        SimulateFluid();

        // 设置材质
        if (mat != null)
        {
            mat.SetTexture("_HeightTex", hBufferCurrent);
            mat.SetTexture("_NormalTex", normalBuffer);
            mat.SetFloat("_WaterDepth", waterDepth);
            mat.SetFloat("_WaveHeightScale", 0.2f);
        }

        // 设置全局参数供其他Shader使用
        Shader.SetGlobalTexture("_SWEHeightTex", hBufferCurrent);
        Shader.SetGlobalTexture("_SWENormalTex", normalBuffer);
        Shader.SetGlobalVector("_SWEParams", new Vector4(
            root.transform.position.x,
            root.transform.position.z,
            offsetScale,
            waterDepth
        ));

        prePos = pos;
    }

    void InitializeKernels()
    {
        initKernel = computeShader.FindKernel("InitKernel");
        waveKernel = computeShader.FindKernel("WaveKernel");
        normalKernel = computeShader.FindKernel("NormalKernel");
    }

    void InitializeRTHandles()
    {
        ReleaseRTHandles();

        // 当前高度
        hBufferCurrent = RTHandles.Alloc(
            size, size,
            colorFormat: UnityEngine.Experimental.Rendering.GraphicsFormat.R32_SFloat,
            enableRandomWrite: true,
            name: "HeightCurrent"
        );
        
        // 下一帧高度
        hBufferNext = RTHandles.Alloc(
            size, size,
            colorFormat: UnityEngine.Experimental.Rendering.GraphicsFormat.R32_SFloat,
            enableRandomWrite: true,
            name: "HeightNext"
        );
        
        // 上一帧高度
        hBufferPrev = RTHandles.Alloc(
            size, size,
            colorFormat: UnityEngine.Experimental.Rendering.GraphicsFormat.R32_SFloat,
            enableRandomWrite: true,
            name: "HeightPrev"
        );

        // 法线贴图
        normalBuffer = RTHandles.Alloc(
            size, size,
            colorFormat: UnityEngine.Experimental.Rendering.GraphicsFormat.R16G16B16A16_SFloat,
            enableRandomWrite: true,
            name: "NormalBuffer"
        );
    }

    void InitializeFluid()
    {
        int threadGroups = Mathf.CeilToInt(size / 8.0f);

        computeShader.SetFloat("texSize", size);
        computeShader.SetFloat("waterDepth", waterDepth);

        computeShader.SetTexture(initKernel, "HeightCurrent", hBufferCurrent);
        computeShader.SetTexture(initKernel, "HeightPrev", hBufferPrev);
        computeShader.SetTexture(initKernel, "HeightNext", hBufferNext);

        computeShader.Dispatch(initKernel, threadGroups, threadGroups, 1);
    }

    void ReleaseRTHandles()
    {
        hBufferCurrent?.Release();
        hBufferNext?.Release();
        hBufferPrev?.Release();
        normalBuffer?.Release();
    }

    void SimulateFluid()
    {
        int threadGroups = Mathf.CeilToInt(size / 8.0f);

        // 设置通用参数
        computeShader.SetFloat("dt", dt);
        computeShader.SetFloat("texSize", size);
        computeShader.SetVector("footPos", footPos);
        computeShader.SetInts("footDrop", footDrop.x, footDrop.y);
        computeShader.SetFloat("radius", penRadius);
        computeShader.SetFloat("waveStrength", waveStrength);
        computeShader.SetFloat("damping", damping);
        computeShader.SetFloat("gravity", gravity);
        computeShader.SetFloat("waterDepth", waterDepth);

        // ========================= 波浪传播步 ==============================
        // HeightCurrent: 读取当前帧
        // HeightPrev: 读取上一帧
        // HeightTex: 采样邻居（绑定为HeightCurrent）
        // HeightNext: 写入下一帧
        computeShader.SetTexture(waveKernel, "HeightCurrent", hBufferCurrent);
        computeShader.SetTexture(waveKernel, "HeightPrev", hBufferPrev);
        computeShader.SetTexture(waveKernel, "HeightNext", hBufferNext);
        computeShader.SetTexture(waveKernel, "HeightTex", hBufferCurrent);

        computeShader.Dispatch(waveKernel, threadGroups, threadGroups, 1);

        // 三缓冲交换: prev <- current, current <- next
        // 这样下一轮：current是刚计算的，prev是上一轮current
        RTHandle temp = hBufferPrev;
        hBufferPrev = hBufferCurrent;
        hBufferCurrent = hBufferNext;
        hBufferNext = temp;

        // ========================= 法线计算 =============================
        computeShader.SetTexture(normalKernel, "HeightTex", hBufferCurrent);
        computeShader.SetTexture(normalKernel, "NormalWrite", normalBuffer);

        computeShader.Dispatch(normalKernel, threadGroups, threadGroups, 1);
    }

    void OnDestroy()
    {
        ReleaseRTHandles();
    }
}
