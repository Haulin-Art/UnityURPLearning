using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.UI;

public class SimpleWaveController : MonoBehaviour
{
    [Header("资源引入")]
    public ComputeShader computeShader;

    [Header("纹理设置")]
    public int textureSize = 512;
    
    [Header("公式参数")]
    [Range(0f, 0.5f)] public float alpha = 0.25f;     // SWE constant
    [Range(0.5f, 2f)] public float beta = 1.0f;       // ViscosityConstant
    [Range(0.9f, 1f)] public float damping = 0.99f;   // 阻尼
    
    [Header("扰动参数")]
    [Range(0f, 10f)] public float strength = 2.0f;
    [Range(0.01f, 0.2f)] public float radius = 0.05f;
    
    [Header("目标物体")]
    public Transform target;
    public bool followTarget = true;
    public bool followYAxis = false;
    
    [Header("调试")]
    public Material debugMaterial;
    public RenderTexture debugRT;
    
    private RTHandle[] heightBuffers = new RTHandle[3]; // 0:curr, 1:prev, 2:prevprev

    private int simKernel;

    // 记录位置,仅仅当移动的时候才会增加扰动
    private Vector3 lastTargetPos;
    private Vector2 movementDelta;
    
    void Start()
    {
        simKernel = computeShader.FindKernel("WaveKernel");
        
        var desc = new RenderTextureDescriptor(textureSize, textureSize, RenderTextureFormat.RFloat, 0)
        {
            enableRandomWrite = true
        };
        
        for (int i = 0; i < 3; i++)
        {
            heightBuffers[i] = RTHandles.Alloc(desc, FilterMode.Bilinear, TextureWrapMode.Clamp, 
                name: $"HeightBuffer_{i}");
            heightBuffers[i].rt.Create();
        }
    }
    
    void Update()
    {
        Vector2 uv = Vector2.zero;

        // 世界坐标转UV（假设水面是10x10单位）
        Vector3 pos = target.position;
        uv = new Vector2(
            (transform.position.x - pos.x) / 10f + 0.5f,
            (transform.position.z - pos.z) / 10f + 0.5f
        );

        if (target != null)
        {
            movementDelta = target.position - lastTargetPos;
        }
        

        if (target != null && followTarget)
        {

            transform.position = new Vector3(
                target.position.x,
                followYAxis ? target.position.y : transform.position.y,
                target.position.z
            );
        }
        Debug.Log("Movement Delta: " + movementDelta + " | Length: " + movementDelta.magnitude);
        
        // 仅仅当目标存在且位置发生变化时才增加扰动
        float finalStrength =  movementDelta.magnitude > 0.001f ? strength : 0f;
        lastTargetPos = target.position;

        // 设置参数
        computeShader.SetFloat("texSize", textureSize);
        computeShader.SetFloat("dt", Time.deltaTime);
        computeShader.SetFloat("alpha", alpha);
        computeShader.SetFloat("beta", beta);
        computeShader.SetFloat("damping", damping);
        computeShader.SetFloat("strength", target != null ? finalStrength : 0f);
        computeShader.SetFloat("radius", radius);
        computeShader.SetVector("sourceUV", uv);
        computeShader.SetVector("movementDelta", followTarget ?  movementDelta/10.0f : Vector2.zero);

        // 设置纹理
        computeShader.SetTexture(simKernel, "CurrHeight", heightBuffers[0].rt);
        computeShader.SetTexture(simKernel, "PrevHeight", heightBuffers[1].rt);
        computeShader.SetTexture(simKernel, "PrevPrevHeight", heightBuffers[2].rt);
        
        // 调度
        int groups = Mathf.CeilToInt(textureSize / 8f);
        computeShader.Dispatch(simKernel, groups, groups, 1);
        
        // 交换缓冲区
        RotateBuffers();
        
        // 调试
        if (debugMaterial != null)
        {
            debugMaterial.SetTexture("_MainTex", heightBuffers[0].rt);
        }
        //debugRT = heightBuffers[0].rt;
        Graphics.Blit(heightBuffers[0].rt, debugRT);
    }
    
    void RotateBuffers()
    {
        // prevprev = prev
        // prev = curr
        // curr 将用于下一帧写入
        var temp = heightBuffers[2]; // 临时存储 prevprev，上上一帧
        heightBuffers[2] = heightBuffers[1]; // prevprev = prev，上上一帧 = 上一帧
        heightBuffers[1] = heightBuffers[0]; // prev = curr，上一帧 = 当前帧
        heightBuffers[0] = temp; // curr = temp，当前帧 = 上上一帧（将被覆盖）
    }
    
    void OnDestroy()
    {
        foreach (var buffer in heightBuffers)
        {
            if (buffer != null)
                RTHandles.Release(buffer);
        }
    }
}