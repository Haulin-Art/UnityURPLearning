using System.Collections;
using System.Collections.Generic;
using Unity.Mathematics;
using UnityEngine;
using UnityEngine.Rendering;

public class DouBaoActorSWE : MonoBehaviour
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
    [Range(0.0f,20.0f)]public float offsetScale = 10.0f;
    [Range(0.0f,1.0f)]public float footHeight = 0.05f;

    [Space(10)]
    [Header("模拟参数设置")]
    public int size = 256;
    [Range(0.0f,1.0f)]public float dt = 0.1f;
    [Range(0.0f,0.1f)]public float penRadius = 0.03f;
    [Range(0.0f,20.0f)]public float forceScale = 5.0f;
    [Range(0.0f,2.0f)]public float gravity = 0.98f;
    [Range(0.0f,0.1f)]public float damping = 0.005f;
    [Range(0.0f,2.0f)]public float baselineDepth = 1.0f;

    private Vector4 footPos;
    private int2 footDrop;
    private Vector2 pos = new Vector2(0.5f,0.5f);
    private Vector2 prePos;
    private Vector2 force;
    private bool keyDown = false;

    private RTHandle hBuffer1;
    private RTHandle hBuffer2;
    private RTHandle huBuffer1;
    private RTHandle huBuffer2;

    private int updateKernel;
    private int sourceKernel;

    void Start()
    {
        if(computeShader == null && mat == null)
        {
            Debug.Log("请指定计算着色器与展示材质");
            return;
        }

        force = new Vector2(0f,0f);
        pos = new Vector2(root.transform.position.x,root.transform.position.z);
        prePos = pos;

        InitializeKernels();
        InitializeRTHandles();
    }

    void Update()
    {
        if(computeShader == null && mat == null)
        {
            Debug.Log("请指定计算着色器与展示材质");
            return;
        }
        if(root == null && foot_1 == null && foot_2 == null)
        {
            Debug.Log("请指定追踪root与脚踝骨骼");
            return;
        }

        gameObject.transform.position = root.transform.position;
        gameObject.transform.position = new Vector3(root.transform.position.x,0.05f,root.transform.position.z);

        pos = new Vector2(root.transform.position.x,root.transform.position.z);

        force = (prePos-pos);
        if (pos != prePos)
        {
            keyDown = true;
        }
        else
        {
            keyDown = false;
        }

        if(foot_1.transform.position.y-root.transform.position.y < footHeight)
        {
            footDrop.x = 1;
        }else{footDrop.x = 0;}
        if(foot_2.transform.position.y-root.transform.position.y < footHeight)
        {
            footDrop.y = 1;
        }else{footDrop.y = 0;}

        footPos = new Vector4(foot_1.transform.position.x-root.transform.position.x,
            foot_1.transform.position.z-root.transform.position.z,
            foot_2.transform.position.x-root.transform.position.x,
            foot_2.transform.position.z-root.transform.position.z
        ) / offsetScale ;
        if (!useFoot) footPos = new Vector4(0,0,0,0);

        SimulateFluid();
        mat.SetTexture("_HeightTex",hBuffer1);
        mat.SetTexture("_HuTex",huBuffer1);
        
        prePos = pos;

        Shader.SetGlobalTexture("_SWEHeightTex" , hBuffer1.rt);
        Shader.SetGlobalVector("_SWEHeightParams",new Vector4(root.transform.position.x,
            root.transform.position.z,
            10.0f,0.0f));
    }

    void InitializeKernels()
    {
        updateKernel = computeShader.FindKernel("UpdateKernel");
        sourceKernel = computeShader.FindKernel("SourceKernel");
    }

    void InitializeRTHandles()
    {
        ReleaseRTHandles();
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
        huBuffer1 = RTHandles.Alloc(
            size, size,
            colorFormat: UnityEngine.Experimental.Rendering.GraphicsFormat.R16G16_SFloat,
            enableRandomWrite: true,
            name: "Hu1"
        );
        huBuffer2 = RTHandles.Alloc(
            size, size,
            colorFormat: UnityEngine.Experimental.Rendering.GraphicsFormat.R16G16_SFloat,
            enableRandomWrite: true,
            name: "Hu2"
        );
    }

    void ReleaseRTHandles()
    {
        hBuffer1?.Release();
        hBuffer2?.Release();
        huBuffer1?.Release();
        huBuffer2?.Release();
    }

    void SimulateFluid()
    {
        int threadGroups = Mathf.CeilToInt(size / 8.0f);

        computeShader.SetFloat("dt",dt);
        computeShader.SetFloat("texSize",size);
        computeShader.SetFloat("gravity",gravity);
        computeShader.SetFloat("damping",damping);
        computeShader.SetFloat("baselineDepth",baselineDepth);
        computeShader.SetVector("footPos",footPos);
        computeShader.SetInts("footDrop",footDrop.x,footDrop.y);
        computeShader.SetVector("Force",new Vector3(force.x,force.y,forceScale));
        computeShader.SetFloat("radius",penRadius);
        computeShader.SetBool("keyDown",keyDown);

        computeShader.SetTexture(updateKernel,"HeightRead",hBuffer1);
        computeShader.SetTexture(updateKernel,"HeightWrite",hBuffer2);
        computeShader.SetTexture(updateKernel,"HuRead",huBuffer1);
        computeShader.SetTexture(updateKernel,"HuWrite",huBuffer2);
        computeShader.SetTexture(updateKernel,"HeightTex",hBuffer1);
        computeShader.SetTexture(updateKernel,"HuTex",huBuffer1);
        computeShader.Dispatch(updateKernel,threadGroups,threadGroups,1);
        Swap(ref hBuffer1,ref hBuffer2);
        Swap(ref huBuffer1,ref huBuffer2);

        computeShader.SetTexture(sourceKernel,"HeightRead",hBuffer1);
        computeShader.SetTexture(sourceKernel,"HeightWrite",hBuffer2);
        computeShader.SetTexture(sourceKernel,"HuRead",huBuffer1);
        computeShader.SetTexture(sourceKernel,"HuWrite",huBuffer2);
        computeShader.Dispatch(sourceKernel,threadGroups,threadGroups,1);
        Swap(ref hBuffer1,ref hBuffer2);
        Swap(ref huBuffer1,ref huBuffer2);
    }

    void Swap(ref RTHandle a,ref RTHandle b)
    {
        RTHandle temp = a;
        a = b;
        b = temp;
    }
}
