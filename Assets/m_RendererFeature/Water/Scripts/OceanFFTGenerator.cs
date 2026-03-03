using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

[ExecuteInEditMode]
public class OceanFFTGenerator : MonoBehaviour
{
    [Header("Ocean Parameters")]
    [Range(64, 2048)] public int resolution = 256;
    [Range(100, 5000)] public float oceanSize = 1000f;
    [Range(0.1f, 50f)] public float windSpeed = 10f;
    [Range(0f, 360f)] public float windAngle = 45f;
    [Range(0.1f, 5f)] public float waveScale = 1f;
    [Range(0f, 2f)] public float choppiness = 1f;
    [Range(0.1f, 10f)] public float timeScale = 1f;
    
    [Header("Output")]
    public RenderTexture heightMap;
    public RenderTexture normalMap;
    
    [Header("Compute Shader")]
    public ComputeShader oceanCompute;
    
    [Header("Debug")]
    public bool autoUpdate = true;
    public bool drawGizmos = true;
    
    // 私有变量
    private RenderTexture displacementBuffer;
    private RenderTexture tmpBuffer;
    private RenderTexture h0Buffer;
    private RenderTexture twiddleIndices;
    private float simulationTime = 0f;
    private bool isInitialized = false;
    
    // 核函数ID
    private int kernelInitSpectrum;
    private int kernelUpdateWaves;
    private int kernelHorizontalFFT;
    private int kernelVerticalFFT;
    private int kernelCombine;
    
    // 属性ID
    private int propOceanSize;
    private int propWindSpeed;
    private int propWindDir;
    private int propWaveScale;
    private int propChoppiness;
    private int propTimeParam;
    private int propResolution;
    private int propOceanParams;
    
    private void OnValidate()
    {
        // 确保分辨率是2的幂
        resolution = Mathf.ClosestPowerOfTwo(resolution);
    }
    
    private void Start()
    {
        Initialize();
    }
    
    private void Update()
    {
        if (!isInitialized) return;
        
        simulationTime += Time.deltaTime * timeScale;
        
        if (autoUpdate)
        {
            GenerateHeightMap();
        }
    }
    
    private void OnDestroy()
    {
        ReleaseResources();
    }
    
    [ContextMenu("Initialize")]
    public void Initialize()
    {
        if (oceanCompute == null)
        {
            Debug.LogError("Compute Shader is not assigned!");
            return;
        }
        
        ReleaseResources();
        
        // 获取核函数ID
        kernelInitSpectrum = oceanCompute.FindKernel("InitSpectrum");
        kernelUpdateWaves = oceanCompute.FindKernel("UpdateWaves");
        kernelHorizontalFFT = oceanCompute.FindKernel("HorizontalFFT");
        kernelVerticalFFT = oceanCompute.FindKernel("VerticalFFT");
        kernelCombine = oceanCompute.FindKernel("Combine");
        
        // 获取属性ID
        propOceanSize = Shader.PropertyToID("_OceanSize");
        propWindSpeed = Shader.PropertyToID("_WindSpeed");
        propWindDir = Shader.PropertyToID("_WindDir");
        propWaveScale = Shader.PropertyToID("_WaveScale");
        propChoppiness = Shader.PropertyToID("_Choppiness");
        propTimeParam = Shader.PropertyToID("_TimeParam");
        propResolution = Shader.PropertyToID("_Resolution");
        propOceanParams = Shader.PropertyToID("_OceanParams");
        
        // 创建RenderTexture
        CreateBuffers();
        
        // 生成初始频谱
        GenerateInitialSpectrum();
        
        // 生成Twiddle因子
        GenerateTwiddleIndices();
        
        isInitialized = true;
        
        Debug.Log("Ocean FFT initialized with resolution: " + resolution);
    }
    
    [ContextMenu("Generate Height Map")]
    public void GenerateHeightMap()
    {
        if (!isInitialized)
        {
            Debug.LogWarning("Not initialized. Call Initialize() first.");
            return;
        }
        
        // 设置参数
        Vector2 windDir = new Vector2(
            Mathf.Cos(windAngle * Mathf.Deg2Rad),
            Mathf.Sin(windAngle * Mathf.Deg2Rad)
        );
        
        oceanCompute.SetFloat(propOceanSize, oceanSize);
        oceanCompute.SetFloat(propWindSpeed, windSpeed);
        oceanCompute.SetVector(propWindDir, windDir);
        oceanCompute.SetFloat(propWaveScale, waveScale);
        oceanCompute.SetFloat(propChoppiness, choppiness);
        oceanCompute.SetFloat(propTimeParam, simulationTime);
        oceanCompute.SetInt(propResolution, resolution);
        oceanCompute.SetVector(propOceanParams, new Vector4(oceanSize, windSpeed, waveScale, choppiness));
        
        // 更新波形
        oceanCompute.SetTexture(kernelUpdateWaves, "_DisplacementBuffer", displacementBuffer);
        oceanCompute.SetTexture(kernelUpdateWaves, "_H0Buffer", h0Buffer);
        
        uint threadsX, threadsY, threadsZ;
        oceanCompute.GetKernelThreadGroupSizes(kernelUpdateWaves, out threadsX, out threadsY, out threadsZ);
        int groupsX = Mathf.CeilToInt(resolution / threadsX);
        int groupsY = Mathf.CeilToInt(resolution / threadsY);
        
        oceanCompute.Dispatch(kernelUpdateWaves, groupsX, groupsY, 1);
        
        // 水平FFT
        oceanCompute.SetTexture(kernelHorizontalFFT, "_DisplacementBuffer", displacementBuffer);
        oceanCompute.SetTexture(kernelHorizontalFFT, "_TmpBuffer", tmpBuffer);
        oceanCompute.SetTexture(kernelHorizontalFFT, "_TwiddleIndices", twiddleIndices);
        
        oceanCompute.Dispatch(kernelHorizontalFFT, groupsY, 1, 1);
        
        // 垂直FFT
        oceanCompute.SetTexture(kernelVerticalFFT, "_TmpBuffer", tmpBuffer);
        oceanCompute.SetTexture(kernelVerticalFFT, "_OutputBuffer", displacementBuffer);
        oceanCompute.SetTexture(kernelVerticalFFT, "_TwiddleIndices", twiddleIndices);
        
        oceanCompute.Dispatch(kernelVerticalFFT, groupsX, 1, 1);
        
        // 合并结果
        if (heightMap == null)
        {
            CreateOutputTextures();
        }
        
        oceanCompute.SetTexture(kernelCombine, "_DisplacementBuffer", displacementBuffer);
        oceanCompute.SetTexture(kernelCombine, "_OutputBuffer", heightMap);
        
        oceanCompute.Dispatch(kernelCombine, groupsX, groupsY, 1);
        
        // 如果需要，复制到Normal Map
        if (normalMap != null)
        {
            Graphics.CopyTexture(heightMap, normalMap);
        }
    }
    
    private void CreateBuffers()
    {
        // 创建位移缓冲区
        displacementBuffer = CreateRenderTexture(resolution, RenderTextureFormat.ARGBFloat, "Displacement Buffer");
        
        // 创建临时缓冲区
        tmpBuffer = CreateRenderTexture(resolution, RenderTextureFormat.ARGBFloat, "Temp Buffer");
        
        // 创建初始频谱缓冲区
        h0Buffer = CreateRenderTexture(resolution, RenderTextureFormat.ARGBFloat, "H0 Buffer");
        
        // 创建输出纹理
        CreateOutputTextures();
    }
    
    private void CreateOutputTextures()
    {
        if (heightMap == null)
        {
            heightMap = CreateRenderTexture(resolution, RenderTextureFormat.ARGBFloat, "Ocean Height Map");
            heightMap.wrapMode = TextureWrapMode.Repeat;
            heightMap.filterMode = FilterMode.Bilinear;
        }
        
        if (normalMap == null)
        {
            normalMap = CreateRenderTexture(resolution, RenderTextureFormat.ARGBFloat, "Ocean Normal Map");
            normalMap.wrapMode = TextureWrapMode.Repeat;
            normalMap.filterMode = FilterMode.Bilinear;
        }
    }
    
    private RenderTexture CreateRenderTexture(int size, RenderTextureFormat format, string name = "")
    {
        var rt = new RenderTexture(size, size, 0, format)
        {
            enableRandomWrite = true,
            autoGenerateMips = false,
            useMipMap = false,
            name = name
        };
        rt.Create();
        return rt;
    }
    
    private void GenerateInitialSpectrum()
    {
        oceanCompute.SetTexture(kernelInitSpectrum, "_DisplacementBuffer", displacementBuffer);
        oceanCompute.SetTexture(kernelInitSpectrum, "_H0Buffer", h0Buffer);
        
        uint threadsX, threadsY, threadsZ;
        oceanCompute.GetKernelThreadGroupSizes(kernelInitSpectrum, out threadsX, out threadsY, out threadsZ);
        int groupsX = Mathf.CeilToInt(resolution / threadsX);
        int groupsY = Mathf.CeilToInt(resolution / threadsY);
        
        oceanCompute.Dispatch(kernelInitSpectrum, groupsX, groupsY, 1);
    }
    
    private void GenerateTwiddleIndices()
    {
        int N = resolution;
        twiddleIndices = CreateRenderTexture(N, RenderTextureFormat.RGFloat, "Twiddle Indices");
        
        ComputeBuffer twiddleBuffer = new ComputeBuffer(N * N, sizeof(float) * 2);
        Vector2[] twiddleData = new Vector2[N * N];
        
        for (int x = 0; x < N; x++)
        {
            for (int y = 0; y < N; y++)
            {
                int idx = x + y * N;
                float angle = 2.0f * Mathf.PI * x * y / N;
                twiddleData[idx] = new Vector2(
                    Mathf.Cos(angle),
                    Mathf.Sin(angle)
                );
            }
        }
        
        twiddleBuffer.SetData(twiddleData);
        
        // 创建临时Compute Shader来填充纹理
        ComputeShader fillShader = (ComputeShader)Resources.Load("OceanFFT_Twiddle");
        if (fillShader != null)
        {
            int kernel = fillShader.FindKernel("FillTwiddle");
            fillShader.SetBuffer(kernel, "_TwiddleBuffer", twiddleBuffer);
            fillShader.SetTexture(kernel, "_TwiddleTexture", twiddleIndices);
            fillShader.SetInt("_Resolution", N);
            
            uint tx, ty, tz;
            fillShader.GetKernelThreadGroupSizes(kernel, out tx, out ty, out tz);
            int gx = Mathf.CeilToInt(N / tx);
            int gy = Mathf.CeilToInt(N / ty);
            
            fillShader.Dispatch(kernel, gx, gy, 1);
        }
        
        twiddleBuffer.Release();
    }
    
    private void ReleaseResources()
    {
        if (displacementBuffer != null) displacementBuffer.Release();
        if (tmpBuffer != null) tmpBuffer.Release();
        if (h0Buffer != null) h0Buffer.Release();
        if (twiddleIndices != null) twiddleIndices.Release();
        
        displacementBuffer = null;
        tmpBuffer = null;
        h0Buffer = null;
        twiddleIndices = null;
        
        isInitialized = false;
    }
    
    public RenderTexture GetHeightMap()
    {
        return heightMap;
    }
    
    public RenderTexture GetNormalMap()
    {
        return normalMap;
    }
    
    private void OnDrawGizmos()
    {
        if (!drawGizmos) return;
        
        Gizmos.color = Color.cyan;
        Gizmos.DrawWireCube(transform.position, new Vector3(oceanSize, 1, oceanSize));
        
        Gizmos.color = Color.blue;
        Vector3 windDir = new Vector3(
            Mathf.Cos(windAngle * Mathf.Deg2Rad),
            0,
            Mathf.Sin(windAngle * Mathf.Deg2Rad)
        ) * 50f;
        Gizmos.DrawRay(transform.position, windDir);
    }
}