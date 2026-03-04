using UnityEngine;
using UnityEditor;

public class BruteForceSDFBaker : MonoBehaviour
{
    [Header("Compute Shader")]
    public ComputeShader computeShader;

    [Header("Input Texture (Binary - White is inside/land)")]
    [Tooltip("白色区域表示陆地/内部，黑色区域表示水域/外部")]
    public Texture2D binaryTexture;

    [Header("Output Settings")]
    [Tooltip("是否保存为资产文件")]
    public bool saveAsAsset = true;
    
    [Tooltip("输出文件夹路径（相对于Assets）")]
    public string outputFolder = "SDFOutput";

    [Header("Baking Settings")]
    [Tooltip("最大边界点数量，0表示自动计算")]
    public int maxBoundaryPoints = 0;
    
    [Tooltip("模糊半径（像素），用于平滑SDF梯度")]
    [Range(1f, 50f)]
    public float blurRadius = 10f;
    
    [Tooltip("模糊迭代次数")]
    [Range(1, 5)]
    public int blurIterations = 2;

    private ComputeBuffer boundaryCountBuffer;
    private ComputeBuffer boundaryPointsBuffer;
    private RenderTexture inputRT;
    private RenderTexture sdfOutput;
    private RenderTexture sdfBlurred;
    private RenderTexture directionOutput;

    private int kernelCollectBoundary;
    private int kernelComputeSDF;
    private int kernelBlurSDF;
    private int kernelComputeGradient;

    private int width;
    private int height;

    [ContextMenu("Bake SDF")]
    public void BakeSDF()
    {
        if (computeShader == null)
        {
            Debug.LogError("请指定Compute Shader!");
            return;
        }

        if (binaryTexture == null)
        {
            Debug.LogError("请指定输入纹理!");
            return;
        }

        kernelCollectBoundary = computeShader.FindKernel("CollectBoundaryPoints");
        kernelComputeSDF = computeShader.FindKernel("ComputeSDF");
        kernelBlurSDF = computeShader.FindKernel("BlurSDF");
        kernelComputeGradient = computeShader.FindKernel("ComputeGradient");

        width = binaryTexture.width;
        height = binaryTexture.height;

        Debug.Log($"开始暴力法SDF烘焙，分辨率: {width}x{height}");

        InitializeResources();
        CollectBoundaryPoints();
        ComputeSDFBruteForce();
        BlurSDF();
        ComputeGradient();
        
        if (saveAsAsset)
        {
            SaveTexturesToAsset();
        }

        CleanupResources();
        Debug.Log("SDF烘焙完成!");
    }

    private void InitializeResources()
    {
        inputRT = new RenderTexture(width, height, 0, RenderTextureFormat.ARGBFloat);
        inputRT.enableRandomWrite = true;
        inputRT.filterMode = FilterMode.Point;
        inputRT.wrapMode = TextureWrapMode.Clamp;
        inputRT.Create();
        Graphics.Blit(binaryTexture, inputRT);

        sdfOutput = new RenderTexture(width, height, 0, RenderTextureFormat.RFloat);
        sdfOutput.enableRandomWrite = true;
        sdfOutput.filterMode = FilterMode.Point;
        sdfOutput.wrapMode = TextureWrapMode.Clamp;
        sdfOutput.Create();

        sdfBlurred = new RenderTexture(width, height, 0, RenderTextureFormat.RFloat);
        sdfBlurred.enableRandomWrite = true;
        sdfBlurred.filterMode = FilterMode.Point;
        sdfBlurred.wrapMode = TextureWrapMode.Clamp;
        sdfBlurred.Create();

        directionOutput = new RenderTexture(width, height, 0, RenderTextureFormat.ARGBFloat);
        directionOutput.enableRandomWrite = true;
        directionOutput.filterMode = FilterMode.Bilinear;
        directionOutput.wrapMode = TextureWrapMode.Clamp;
        directionOutput.Create();

        int estimatedBoundaryPoints = Mathf.Max(1, (int)(width * height * 0.1f));
        if (maxBoundaryPoints > 0)
        {
            estimatedBoundaryPoints = maxBoundaryPoints;
        }
        
        boundaryCountBuffer = new ComputeBuffer(1, sizeof(uint), ComputeBufferType.Raw);
        boundaryPointsBuffer = new ComputeBuffer(estimatedBoundaryPoints, sizeof(float) * 2);
        
        uint[] zeroCount = new uint[1] { 0 };
        boundaryCountBuffer.SetData(zeroCount);

        Debug.Log($"分配边界点缓冲区，最大容量: {estimatedBoundaryPoints}");
    }

    private void CollectBoundaryPoints()
    {
        computeShader.SetTexture(kernelCollectBoundary, "SourceTexture", inputRT);
        computeShader.SetBuffer(kernelCollectBoundary, "BoundaryCount", boundaryCountBuffer);
        computeShader.SetBuffer(kernelCollectBoundary, "BoundaryPoints", boundaryPointsBuffer);
        computeShader.SetInt("MaxBoundaryPoints", boundaryPointsBuffer.count);
        computeShader.SetInts("TextureSize", width, height);

        int threadGroupsX = Mathf.CeilToInt(width / 8f);
        int threadGroupsY = Mathf.CeilToInt(height / 8f);
        computeShader.Dispatch(kernelCollectBoundary, threadGroupsX, threadGroupsY, 1);

        uint[] countData = new uint[1];
        boundaryCountBuffer.GetData(countData);
        uint boundaryCount = countData[0];
        
        Debug.Log($"检测到边界点数量: {boundaryCount}");

        if (boundaryCount > boundaryPointsBuffer.count)
        {
            Debug.LogWarning($"边界点数量({boundaryCount})超过缓冲区容量({boundaryPointsBuffer.count})，部分点将被忽略!");
        }
    }

    private void ComputeSDFBruteForce()
    {
        computeShader.SetTexture(kernelComputeSDF, "SourceTexture", inputRT);
        computeShader.SetTexture(kernelComputeSDF, "Result", sdfOutput);
        computeShader.SetBuffer(kernelComputeSDF, "BoundaryCount", boundaryCountBuffer);
        computeShader.SetBuffer(kernelComputeSDF, "BoundaryPoints", boundaryPointsBuffer);
        computeShader.SetInt("MaxBoundaryPoints", boundaryPointsBuffer.count);
        computeShader.SetInts("TextureSize", width, height);

        int threadGroupsX = Mathf.CeilToInt(width / 8f);
        int threadGroupsY = Mathf.CeilToInt(height / 8f);
        
        Debug.Log($"开始计算SDF...");
        
        computeShader.Dispatch(kernelComputeSDF, threadGroupsX, threadGroupsY, 1);
    }

    private void BlurSDF()
    {
        int threadGroupsX = Mathf.CeilToInt(width / 8f);
        int threadGroupsY = Mathf.CeilToInt(height / 8f);
        
        computeShader.SetInts("TextureSize", width, height);
        computeShader.SetFloat("BlurRadius", blurRadius);
        
        RenderTexture source = sdfOutput;
        RenderTexture dest = sdfBlurred;
        
        for (int i = 0; i < blurIterations; i++)
        {
            computeShader.SetTexture(kernelBlurSDF, "SDFTexture", source);
            computeShader.SetTexture(kernelBlurSDF, "Result", dest);
            
            computeShader.Dispatch(kernelBlurSDF, threadGroupsX, threadGroupsY, 1);
            
            RenderTexture temp = source;
            source = dest;
            dest = temp;
        }
        
        if (source != sdfBlurred)
        {
            Graphics.Blit(source, sdfBlurred);
        }
        
        Debug.Log($"模糊SDF，半径: {blurRadius}，迭代: {blurIterations}");
    }

    private void ComputeGradient()
    {
        computeShader.SetTexture(kernelComputeGradient, "SDFTexture", sdfBlurred);
        computeShader.SetTexture(kernelComputeGradient, "Result", sdfOutput);
        computeShader.SetTexture(kernelComputeGradient, "DirectionResult", directionOutput);
        computeShader.SetInts("TextureSize", width, height);

        int threadGroupsX = Mathf.CeilToInt(width / 8f);
        int threadGroupsY = Mathf.CeilToInt(height / 8f);
        
        Debug.Log($"计算梯度...");
        
        computeShader.Dispatch(kernelComputeGradient, threadGroupsX, threadGroupsY, 1);
    }

    private void SaveTexturesToAsset()
    {
        if (!System.IO.Directory.Exists(System.IO.Path.Combine(Application.dataPath, outputFolder)))
        {
            System.IO.Directory.CreateDirectory(System.IO.Path.Combine(Application.dataPath, outputFolder));
        }

        string baseName = binaryTexture.name;
        
        Texture2D sdfTex = new Texture2D(width, height, TextureFormat.RFloat, false, true);
        RenderTexture.active = sdfOutput;
        sdfTex.ReadPixels(new Rect(0, 0, width, height), 0, 0);
        sdfTex.Apply();
        RenderTexture.active = null;

        string sdfPath = System.IO.Path.Combine("Assets", outputFolder, $"{baseName}_SDF.asset");
        AssetDatabase.CreateAsset(sdfTex, sdfPath);
        Debug.Log($"SDF纹理已保存到: {sdfPath}");

        Texture2D dirTex = new Texture2D(width, height, TextureFormat.RGBAFloat, false, true);
        RenderTexture.active = directionOutput;
        dirTex.ReadPixels(new Rect(0, 0, width, height), 0, 0);
        dirTex.Apply();
        RenderTexture.active = null;

        string dirPath = System.IO.Path.Combine("Assets", outputFolder, $"{baseName}_Direction.asset");
        AssetDatabase.CreateAsset(dirTex, dirPath);
        Debug.Log($"方向纹理已保存到: {dirPath}");

        AssetDatabase.SaveAssets();
        AssetDatabase.Refresh();
    }

    private void CleanupResources()
    {
        if (boundaryCountBuffer != null)
        {
            boundaryCountBuffer.Release();
            boundaryCountBuffer = null;
        }

        if (boundaryPointsBuffer != null)
        {
            boundaryPointsBuffer.Release();
            boundaryPointsBuffer = null;
        }

        if (inputRT != null)
        {
            inputRT.Release();
            inputRT = null;
        }

        if (sdfOutput != null)
        {
            sdfOutput.Release();
            sdfOutput = null;
        }

        if (sdfBlurred != null)
        {
            sdfBlurred.Release();
            sdfBlurred = null;
        }

        if (directionOutput != null)
        {
            directionOutput.Release();
            directionOutput = null;
        }
    }

    private void OnDestroy()
    {
        CleanupResources();
    }

    private void OnDisable()
    {
        CleanupResources();
    }

    public RenderTexture GetSDFTexture()
    {
        return sdfOutput;
    }

    public RenderTexture GetDirectionTexture()
    {
        return directionOutput;
    }
}
