using System.Collections;
using System.Collections.Generic;
using Unity.VisualScripting;
using UnityEditor.EditorTools;
using UnityEditor.ShaderGraph;
using UnityEngine;
using UnityEngine.Rendering;

public class NSFluidSimulation : MonoBehaviour
{
    [Header("文件输入")]
    public ComputeShader computeShader;
    public Material mat; //用于展示的材质

    [Space(10)]
    [Header("模拟参数设置")]
    public int size = 256; // 模拟网格大小
    [Range(0.0f,1.0f)]public float dt = 0.15f; // 帧步长
    [Range(0.0f,0.5f)]public float penRadius = 0.015f; // 画笔的半径
    [Range(0.0f,10.0f)]public float SpeedScale = 2.5f; // 施加力的大小
    [Range(0.0f,1.0f)]public float advectSpeed = 0.25f; // 流体平流项速度
    [Range(2,20)]public int pressureIterations = 10; // 雅可比迭代次数
    [Range(0.0f,0.2f)]public float speedAttenuation = 0.005f; // 速度衰减系数
    [Range(0.0f,0.2f)]public float colorAttenuation = 0.005f; // 染料衰减系数
    
    // 隐藏参数
    private Vector2 pos = new Vector2(0.5f,0.5f); // 当前位置
    private Vector2 prePos; // 上一帧位置
    private Vector2 force; // 速度方向
    private bool keyDown = false; // 是否按下

    // Compute Buffer
    private RTHandle vBuffer1; // 速度缓存1，用于储存
    private RTHandle vBuffer2; // 速度缓存2，用于写入
    private RTHandle pBuffer1; // 压力缓存1，用于存储
    private RTHandle pBuffer2; // 压力缓存2，用于写入
    private RTHandle dBuffer1; // 颜料缓存1，用于读取
    private RTHandle dBuffer2; // 颜料缓存2，用于储存

    // Kernels
    private int advectionKernel;
    private int pressureKernel;
    private int projectionKernel;
    private int dyeKernel;

    // Start is called before the first frame update
    void Start()
    {
        if(computeShader == null && mat == null)
        {
            Debug.Log("请指定计算着色器与展示材质");
            return;
        }

        force = new Vector2(0f,0f); // 初始化力
        prePos = pos;

        InitializeKernels(); // 获取 Compute Shader 当中的 Kernel ID
        InitializeRTHandles(); // 初始化 RTHandles
    }

    // Update is called once per frame
    void Update()
    {
        if(computeShader == null && mat == null)
        {
            Debug.Log("请指定计算着色器与展示材质");
            return;
        }

        // 当且仅当位置发生变化的时候添加新的力
        pos =new Vector2(1.0f,1.0f) -  new Vector2(Input.mousePosition.x,Input.mousePosition.y)/500f;

        if (pos != prePos && Input.GetMouseButton(0))
        {
            force = (pos-prePos)*50f;
            keyDown = true;
        }
        else
        {
            //force = new Vector2(0f,0f);
            keyDown = false;
        }

        // 执行模拟
        SimulateFluid();
        // 展示测试
        mat.SetTexture("_VelocityTex",dBuffer1);
        
        prePos = pos;
    }

    // 初始化核序号
    void InitializeKernels()
    {
        advectionKernel = computeShader.FindKernel("AdvectionKernel");
        pressureKernel = computeShader.FindKernel("PressureKernel");
        projectionKernel = computeShader.FindKernel("ProjectionKernel");
        dyeKernel = computeShader.FindKernel("DyeKernel");
    }
    // 用于设置 RTHandle 的格式大小之类的
    void InitializeRTHandles()
    {
        ReleaseRTHandles();
        // 这里需要区分一下不同格式
        // SFloat:有符号浮点(-65504~65504，支持小数)，SInt:有符号整数(-32768~32767，不支持小数)
        // SNorm：有符号归一化整数(-1.0~1.0，有小数)，UInt：无符号整数(0~65532，无小数)
        // UNorm：无符号归一化整数(0.0~1.0，有小数)
        // 速度场：只需要RG两个通道 (x, y) - 64位
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
        // 压力场，一个通道
        pBuffer1 = RTHandles.Alloc(
            size, size,
            colorFormat: UnityEngine.Experimental.Rendering.GraphicsFormat.R16_SFloat,
            enableRandomWrite: true,
            name: "Pressure1"
        );
        pBuffer2 = RTHandles.Alloc(size,size,
            colorFormat: UnityEngine.Experimental.Rendering.GraphicsFormat.R16_SFloat,
            enableRandomWrite: true,
            name: "Pressure2"
        );
        // 颜料场，用于可视化，需要三个通道
        dBuffer1 = RTHandles.Alloc(
            size,size,
            colorFormat:UnityEngine.Experimental.Rendering.GraphicsFormat.R16G16B16A16_UNorm,
            enableRandomWrite: true,
            name: "Dye1"
        );
        dBuffer2 = RTHandles.Alloc(
            size,size,
            colorFormat:UnityEngine.Experimental.Rendering.GraphicsFormat.R16G16B16A16_UNorm,
            enableRandomWrite: true,
            name: "Dye2"
        );
    }
    // 释放之前的 RTHandle
    void ReleaseRTHandles()
    {
        vBuffer1?.Release();
        vBuffer2?.Release();
        pBuffer1?.Release();
        pBuffer2?.Release();
        dBuffer1?.Release();
        dBuffer2?.Release();
    }
    // 主模拟函数
    void SimulateFluid()
    {
        // 计算线程组数量
        int threadGroups = Mathf.CeilToInt(size / 8.0f);

        // 设置通用参数
        computeShader.SetFloat("dt",dt);
        computeShader.SetFloat("advectSpeed",advectSpeed);
        computeShader.SetFloat("texSize",size);
        //computeShader.SetVector("pos",pos);
        computeShader.SetVector("penPos",new Vector4(pos.x,pos.y,prePos.x,prePos.y));
        //computeShader.SetVector("prePos",prePos);
        computeShader.SetVector("attenuation",new Vector2(speedAttenuation,colorAttenuation));
        computeShader.SetVector("Force",new Vector3(force.x,force.y,SpeedScale));
        computeShader.SetFloat("radius",penRadius);
        computeShader.SetBool("keyDown",keyDown);

        // ========================= 平流项 ==============================
        // 设置平流项参数
        computeShader.SetTexture(advectionKernel,"VelocityRead",vBuffer1);
        computeShader.SetTexture(advectionKernel,"VelocityWrite",vBuffer2);
        computeShader.SetTexture(advectionKernel,"VelocityTex",vBuffer1);
        // 执行平流项目
        computeShader.Dispatch(advectionKernel,threadGroups,threadGroups,1);
        // 交换速度缓存区
        Swap(ref vBuffer1,ref vBuffer2);
        
        // ======================== 压力项 ==============================
        computeShader.SetTexture(pressureKernel,"VelocityTex",vBuffer1);
        // 使用雅可比迭代法，循环迭代压力项
        for (int i = 0 ; i < pressureIterations ; i++)
        {
            computeShader.SetTexture(pressureKernel,"PressureRead",pBuffer1);
            computeShader.SetTexture(pressureKernel,"PressureWrite",pBuffer2);
            computeShader.SetTexture(pressureKernel,"PressureTex",pBuffer1);
            computeShader.Dispatch(pressureKernel,threadGroups,threadGroups,1);
            Swap(ref pBuffer1,ref pBuffer2);
        }
        
        // ======================== 投影项 ==============================
        computeShader.SetTexture(projectionKernel,"VelocityRead",vBuffer1);
        computeShader.SetTexture(projectionKernel,"VelocityWrite",vBuffer2);
        computeShader.SetTexture(projectionKernel,"VelocityTex",vBuffer1);
        computeShader.SetTexture(projectionKernel,"PressureTex",pBuffer1);
        computeShader.Dispatch(projectionKernel,threadGroups,threadGroups,1);
        Swap(ref vBuffer1,ref vBuffer2);
        
        // ======================== 染料项 ===============================
        computeShader.SetTexture(dyeKernel,"DyeRead",dBuffer1);
        computeShader.SetTexture(dyeKernel,"DyeWrite",dBuffer2);
        computeShader.SetTexture(dyeKernel,"VelocityTex",vBuffer1);
        computeShader.SetTexture(dyeKernel,"DyeTex",dBuffer1);
        computeShader.Dispatch(dyeKernel,threadGroups,threadGroups,1);
        Swap(ref dBuffer1,ref dBuffer2);
        
    }
    // 缓存交换函数
    void Swap(ref RTHandle a,ref RTHandle b)
    {
        RTHandle temp = a;
        a = b;
        b = temp;
    }
}
