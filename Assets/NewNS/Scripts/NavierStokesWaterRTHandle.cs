using UnityEngine;
using UnityEngine.Rendering;

[ExecuteAlways]
public class NavierStokesWaterWithDye : MonoBehaviour
{
    [Header("Compute Shader")]
    public ComputeShader navierStokesCompute;
    
    [Header("Simulation Parameters")]
    [Range(128, 2048)] public int resolution = 512;
    [Range(0.1f, 5.0f)] public float timeScale = 1.0f;
    [Range(0.0f, 1.0f)] public float viscosity = 0.1f;
    [Range(0.0f, 0.5f)] public float damping = 0.05f;
    [Range(0.0f, 0.1f)] public float dyeDiffusion = 0.01f;
    
    [Header("Water Source")]
    [Range(0.0f, 1.0f)] public float sourceIntensity = 0.3f;
    [Range(0.0f, 0.3f)] public float sourceRadius = 0.1f;
    public Vector2 sourcePosition = new Vector2(0.5f, 0.5f);
    public Vector2 sourceVelocity = new Vector2(0.5f, 0.0f);
    
    [Header("Dye Settings")]
    public Color dyeColor = new Color(0.1f, 0.8f, 0.3f, 1.0f);
    [Range(0.0f, 1.0f)] public float dyeIntensity = 0.5f;
    public bool continuousDye = true;
    
    [Header("Visualization")]
    public Material waterMaterial;
    [Range(0.0f, 5.0f)] public float waveHeight = 2.0f;
    
    // RTHandles - 优化格式
    private RTHandle velocityRT;           // 速度场：RG通道 (x, y) - 64位
    private RTHandle velocityRTPrev;       // 速度场前一帧
    private RTHandle dyeRT;                // 染料场：RGB通道 - 96位（或RGBA 128位）
    private RTHandle dyeRTPrev;            // 染料场前一帧
    private RTHandle divergenceRT;         // 散度场：单通道 - 32位
    private RTHandle pressureRT;           // 压力场：单通道 - 32位
    private RTHandle pressureRTPrev;       // 压力场前一帧
    
    // Kernel IDs
    private int clearKernel;
    private int advectVelocityKernel;
    private int advectDyeKernel;
    private int addForceKernel;
    private int addDyeKernel;
    private int computeDivergenceKernel;
    private int computePressureKernel;
    private int applyPressureKernel;
    private int applyDampingKernel;
    private int diffusionKernel;
    
    // Property IDs
    private static readonly int velocityTexID = Shader.PropertyToID("_VelocityTex");
    private static readonly int dyeTexID = Shader.PropertyToID("_DyeTex");
    private static readonly int waveHeightID = Shader.PropertyToID("_WaveHeight");
    private static readonly int resolutionID = Shader.PropertyToID("_Resolution");

    void Start()
    {
        InitializeSimulation();
    }
    
    void InitializeSimulation()
    {
        if (navierStokesCompute == null)
        {
            Debug.LogError("Compute Shader is not assigned!");
            return;
        }
        
        // Get kernel IDs
        clearKernel = navierStokesCompute.FindKernel("Clear");
        advectVelocityKernel = navierStokesCompute.FindKernel("AdvectVelocity");
        advectDyeKernel = navierStokesCompute.FindKernel("AdvectDye");
        addForceKernel = navierStokesCompute.FindKernel("AddForce");
        addDyeKernel = navierStokesCompute.FindKernel("AddDye");
        computeDivergenceKernel = navierStokesCompute.FindKernel("ComputeDivergence");
        computePressureKernel = navierStokesCompute.FindKernel("ComputePressure");
        applyPressureKernel = navierStokesCompute.FindKernel("ApplyPressure");
        applyDampingKernel = navierStokesCompute.FindKernel("ApplyDamping");
        diffusionKernel = navierStokesCompute.FindKernel("Diffusion");
        
        // Create RTHandles
        CreateRTHandles();
        
        // Set initial values
        UpdateMaterialProperties();
    }
    
    void CreateRTHandles()
    {
        // Release old RTHandles
        ReleaseRTHandles();
        
        // 速度场：只需要RG两个通道 (x, y) - 64位
        velocityRT = RTHandles.Alloc(
            resolution, resolution,
            colorFormat: UnityEngine.Experimental.Rendering.GraphicsFormat.R32G32_SFloat,
            enableRandomWrite: true,
            name: "Velocity"
        );
        
        velocityRTPrev = RTHandles.Alloc(
            resolution, resolution,
            colorFormat: UnityEngine.Experimental.Rendering.GraphicsFormat.R32G32_SFloat,
            enableRandomWrite: true,
            name: "VelocityPrev"
        );
        
        // 染料场：需要RGB三个通道 - 96位（比RGBA少一个通道）
        // 或者使用RGBA 128位，如果需要有透明度控制的话
        dyeRT = RTHandles.Alloc(
            resolution, resolution,
            colorFormat: UnityEngine.Experimental.Rendering.GraphicsFormat.R32G32B32A32_SFloat,
            enableRandomWrite: true,
            name: "Dye"
        );
        
        dyeRTPrev = RTHandles.Alloc(
            resolution, resolution,
            colorFormat: UnityEngine.Experimental.Rendering.GraphicsFormat.R32G32B32A32_SFloat,
            enableRandomWrite: true,
            name: "DyePrev"
        );
        
        // 散度场：只需要单通道 - 32位
        divergenceRT = RTHandles.Alloc(
            resolution, resolution,
            colorFormat: UnityEngine.Experimental.Rendering.GraphicsFormat.R32_SFloat,
            enableRandomWrite: true,
            name: "Divergence"
        );
        
        // 压力场：只需要单通道 - 32位
        pressureRT = RTHandles.Alloc(
            resolution, resolution,
            colorFormat: UnityEngine.Experimental.Rendering.GraphicsFormat.R32_SFloat,
            enableRandomWrite: true,
            name: "Pressure"
        );
        
        pressureRTPrev = RTHandles.Alloc(
            resolution, resolution,
            colorFormat: UnityEngine.Experimental.Rendering.GraphicsFormat.R32_SFloat,
            enableRandomWrite: true,
            name: "PressurePrev"
        );
        
        SetComputeTextures();
        
        // 初始清除缓冲区
        ClearBuffers();
    }
    
    void SetComputeTextures()
    {
        // 设置Compute Shader纹理参数
        navierStokesCompute.SetTexture(clearKernel, "Velocity", velocityRT);
        navierStokesCompute.SetTexture(clearKernel, "Dye", dyeRT);
        navierStokesCompute.SetTexture(clearKernel, "Pressure", pressureRT);
        
        navierStokesCompute.SetTexture(advectVelocityKernel, "Velocity", velocityRT);
        navierStokesCompute.SetTexture(advectVelocityKernel, "VelocityPrev", velocityRTPrev);
        
        navierStokesCompute.SetTexture(advectDyeKernel, "Velocity", velocityRT);
        navierStokesCompute.SetTexture(advectDyeKernel, "Dye", dyeRT);
        navierStokesCompute.SetTexture(advectDyeKernel, "DyePrev", dyeRTPrev);
        
        navierStokesCompute.SetTexture(addForceKernel, "Velocity", velocityRT);
        navierStokesCompute.SetTexture(addForceKernel, "VelocityPrev", velocityRTPrev);
        
        navierStokesCompute.SetTexture(addDyeKernel, "Dye", dyeRT);
        navierStokesCompute.SetTexture(addDyeKernel, "DyePrev", dyeRTPrev);
        
        navierStokesCompute.SetTexture(computeDivergenceKernel, "Velocity", velocityRT);
        navierStokesCompute.SetTexture(computeDivergenceKernel, "Divergence", divergenceRT);
        navierStokesCompute.SetTexture(computeDivergenceKernel, "Pressure", pressureRT);
        
        navierStokesCompute.SetTexture(computePressureKernel, "Pressure", pressureRT);
        navierStokesCompute.SetTexture(computePressureKernel, "PressurePrev", pressureRTPrev);
        navierStokesCompute.SetTexture(computePressureKernel, "Divergence", divergenceRT);
        
        navierStokesCompute.SetTexture(applyPressureKernel, "Velocity", velocityRT);
        navierStokesCompute.SetTexture(applyPressureKernel, "VelocityPrev", velocityRTPrev);
        navierStokesCompute.SetTexture(applyPressureKernel, "Pressure", pressureRT);
        
        navierStokesCompute.SetTexture(applyDampingKernel, "Velocity", velocityRT);
        
        navierStokesCompute.SetTexture(diffusionKernel, "Dye", dyeRT);
        navierStokesCompute.SetTexture(diffusionKernel, "DyePrev", dyeRTPrev);
    }
    
    void ClearBuffers()
    {
        int threadGroups = Mathf.CeilToInt(resolution / 8.0f);
        navierStokesCompute.Dispatch(clearKernel, threadGroups, threadGroups, 1);
    }
    
    void Update()
    {
        if (navierStokesCompute == null || velocityRT == null) return;
        
        UpdateComputeParams();
        RunSimulation();
        UpdateMaterialProperties();
    }
    
    void UpdateComputeParams()
    {
        float dt = Time.deltaTime * timeScale;
        
        navierStokesCompute.SetFloat("DeltaTime", dt);
        navierStokesCompute.SetFloat("Viscosity", viscosity);
        navierStokesCompute.SetFloat("Damping", damping);
        navierStokesCompute.SetFloat("DyeDiffusion", dyeDiffusion);
        navierStokesCompute.SetInt("Resolution", resolution);
        
        // Water source
        navierStokesCompute.SetVector("SourcePosition", sourcePosition);
        navierStokesCompute.SetVector("SourceVelocity", sourceVelocity);
        navierStokesCompute.SetFloat("SourceIntensity", sourceIntensity);
        navierStokesCompute.SetFloat("SourceRadius", sourceRadius);
        
        // Dye source
        navierStokesCompute.SetVector("DyeColor", dyeColor);
        navierStokesCompute.SetVector("DyePosition", sourcePosition); // 可以在水源位置加染料
        navierStokesCompute.SetFloat("DyeIntensity", dyeIntensity);
        navierStokesCompute.SetFloat("DyeRadius", sourceRadius);
    }
    
    void RunSimulation()
    {
        int threadGroups = Mathf.CeilToInt(resolution / 8.0f);
        
        // 1. 平流速度（基于纳维斯托克斯方程）
        navierStokesCompute.Dispatch(advectVelocityKernel, threadGroups, threadGroups, 1);
        SwapRTHandle(ref velocityRT, ref velocityRTPrev);
        UpdateVelocityTextures();
        
        // 2. 添加力（水源）
        navierStokesCompute.Dispatch(addForceKernel, threadGroups, threadGroups, 1);
        SwapRTHandle(ref velocityRT, ref velocityRTPrev);
        UpdateForceTextures();
        
        // 3. 计算散度
        navierStokesCompute.Dispatch(computeDivergenceKernel, threadGroups, threadGroups, 1);
        
        // 4. 求解压力（雅可比迭代）
        for (int i = 0; i < 20; i++)
        {
            navierStokesCompute.Dispatch(computePressureKernel, threadGroups, threadGroups, 1);
            SwapRTHandle(ref pressureRT, ref pressureRTPrev);
            UpdatePressureTextures();
        }
        
        // 5. 应用压力
        navierStokesCompute.Dispatch(applyPressureKernel, threadGroups, threadGroups, 1);
        SwapRTHandle(ref velocityRT, ref velocityRTPrev);
        UpdatePressureApplyTextures();
        
        // 6. 应用阻尼
        navierStokesCompute.Dispatch(applyDampingKernel, threadGroups, threadGroups, 1);
        
        // 7. 平流染料（关键步骤！这才是真正的流体可视化）
        navierStokesCompute.Dispatch(advectDyeKernel, threadGroups, threadGroups, 1);
        SwapRTHandle(ref dyeRT, ref dyeRTPrev);
        UpdateDyeTextures();
        
        // 8. 添加染料源（如果开启连续添加）
        if (continuousDye)
        {
            navierStokesCompute.Dispatch(addDyeKernel, threadGroups, threadGroups, 1);
            SwapRTHandle(ref dyeRT, ref dyeRTPrev);
            UpdateDyeAddTextures();
        }
        
        // 9. 染料扩散（可选，模拟染料本身的扩散）
        if (dyeDiffusion > 0)
        {
            navierStokesCompute.Dispatch(diffusionKernel, threadGroups, threadGroups, 1);
            SwapRTHandle(ref dyeRT, ref dyeRTPrev);
            UpdateDiffusionTextures();
        }
    }
    
    void UpdateVelocityTextures()
    {
        navierStokesCompute.SetTexture(advectVelocityKernel, "Velocity", velocityRT);
        navierStokesCompute.SetTexture(advectVelocityKernel, "VelocityPrev", velocityRTPrev);
    }
    
    void UpdateForceTextures()
    {
        navierStokesCompute.SetTexture(addForceKernel, "Velocity", velocityRT);
        navierStokesCompute.SetTexture(addForceKernel, "VelocityPrev", velocityRTPrev);
    }
    
    void UpdatePressureTextures()
    {
        navierStokesCompute.SetTexture(computePressureKernel, "Pressure", pressureRT);
        navierStokesCompute.SetTexture(computePressureKernel, "PressurePrev", pressureRTPrev);
    }
    
    void UpdatePressureApplyTextures()
    {
        navierStokesCompute.SetTexture(applyPressureKernel, "Velocity", velocityRT);
        navierStokesCompute.SetTexture(applyPressureKernel, "VelocityPrev", velocityRTPrev);
        navierStokesCompute.SetTexture(applyPressureKernel, "Pressure", pressureRT);
    }
    
    void UpdateDyeTextures()
    {
        navierStokesCompute.SetTexture(advectDyeKernel, "Velocity", velocityRT);
        navierStokesCompute.SetTexture(advectDyeKernel, "Dye", dyeRT);
        navierStokesCompute.SetTexture(advectDyeKernel, "DyePrev", dyeRTPrev);
    }
    
    void UpdateDyeAddTextures()
    {
        navierStokesCompute.SetTexture(addDyeKernel, "Dye", dyeRT);
        navierStokesCompute.SetTexture(addDyeKernel, "DyePrev", dyeRTPrev);
    }
    
    void UpdateDiffusionTextures()
    {
        navierStokesCompute.SetTexture(diffusionKernel, "Dye", dyeRT);
        navierStokesCompute.SetTexture(diffusionKernel, "DyePrev", dyeRTPrev);
    }
    
    void SwapRTHandle(ref RTHandle a, ref RTHandle b)
    {
        RTHandle temp = a;
        a = b;
        b = temp;
    }
    
    void UpdateMaterialProperties()
    {
        if (waterMaterial != null)
        {
            waterMaterial.SetTexture(velocityTexID, velocityRT);
            waterMaterial.SetTexture(dyeTexID, dyeRT);  // 关键：使用染料场作为颜色源
            waterMaterial.SetFloat(waveHeightID, waveHeight);
            waterMaterial.SetFloat(resolutionID, resolution);
        }
    }
    
    public void AddDyeImpulse(Vector2 position, Color color, float intensity, float radius)
    {
        // 临时设置染料参数
        navierStokesCompute.SetVector("DyePosition", position);
        navierStokesCompute.SetVector("DyeColor", color);
        navierStokesCompute.SetFloat("DyeIntensity", intensity);
        navierStokesCompute.SetFloat("DyeRadius", radius);
        
        int threadGroups = Mathf.CeilToInt(resolution / 8.0f);
        navierStokesCompute.Dispatch(addDyeKernel, threadGroups, threadGroups, 1);
        
        SwapRTHandle(ref dyeRT, ref dyeRTPrev);
        UpdateDyeAddTextures();
    }
    
    void ReleaseRTHandles()
    {
        if (velocityRT != null) 
        {
            velocityRT.Release();
            velocityRT = null;
        }
        if (velocityRTPrev != null) 
        {
            velocityRTPrev.Release();
            velocityRTPrev = null;
        }
        if (dyeRT != null) 
        {
            dyeRT.Release();
            dyeRT = null;
        }
        if (dyeRTPrev != null) 
        {
            dyeRTPrev.Release();
            dyeRTPrev = null;
        }
        if (divergenceRT != null) 
        {
            divergenceRT.Release();
            divergenceRT = null;
        }
        if (pressureRT != null) 
        {
            pressureRT.Release();
            pressureRT = null;
        }
        if (pressureRTPrev != null) 
        {
            pressureRTPrev.Release();
            pressureRTPrev = null;
        }
    }
    
    void OnDestroy()
    {
        ReleaseRTHandles();
    }
    
    void OnValidate()
    {
        if (Application.isPlaying && navierStokesCompute != null)
        {
            bool needsRecreate = velocityRT == null || velocityRT.rt.width != resolution;
            if (needsRecreate)
            {
                CreateRTHandles();
            }
            
            UpdateMaterialProperties();
        }
    }
}