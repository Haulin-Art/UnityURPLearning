using UnityEngine;

public class JFASDFController : MonoBehaviour
{
    [Header("Compute Shader")]
    public ComputeShader computeShader;

    [Header("Input Texture (Binary - White is shape)")]
    public Texture2D binaryTexture;

    [Header("Output Render Texture (Auto-created if null)")]
    public RenderTexture outputTexture;

    [Header("Gradient Output Render Texture (Auto-created if null)")]
    public RenderTexture gradientTexture;

    [Header("Settings")]
    [Tooltip("Maximum iterations, 0 for auto calculation")]
    public int maxIterations = 0;

    private RenderTexture tempResult;
    private RenderTexture pingPongResult;
    private RenderTexture inputRT;
    private RenderTexture autoCreatedOutput;
    private RenderTexture autoCreatedGradient;

    private int kernelInit;
    private int kernelJump;
    private int kernelFinalize;
    private int kernelGradient;

    private int width;
    private int height;

    private void Start()
    {
        ComputeSDF();
    }

    [ContextMenu("Compute SDF")]
    public void ComputeSDF()
    {
        if (computeShader == null)
        {
            Debug.LogError("Please assign a Compute Shader!");
            return;
        }

        if (binaryTexture == null)
        {
            Debug.LogError("Please assign a binary input texture!");
            return;
        }

        kernelInit = computeShader.FindKernel("JFAInit");
        kernelJump = computeShader.FindKernel("JFAJump");
        kernelFinalize = computeShader.FindKernel("JFAFinalize");
        kernelGradient = computeShader.FindKernel("ComputeGradient");

        width = binaryTexture.width;
        height = binaryTexture.height;

        InitializeRenderTextures();
        RunJFA();
    }

    private void InitializeRenderTextures()
    {
        if (tempResult != null) tempResult.Release();
        if (pingPongResult != null) pingPongResult.Release();
        if (inputRT != null) inputRT.Release();

        tempResult = new RenderTexture(width, height, 0, RenderTextureFormat.ARGBFloat);
        tempResult.enableRandomWrite = true;
        tempResult.filterMode = FilterMode.Point;
        tempResult.wrapMode = TextureWrapMode.Clamp;
        tempResult.Create();

        pingPongResult = new RenderTexture(width, height, 0, RenderTextureFormat.ARGBFloat);
        pingPongResult.enableRandomWrite = true;
        pingPongResult.filterMode = FilterMode.Point;
        pingPongResult.wrapMode = TextureWrapMode.Clamp;
        pingPongResult.Create();

        inputRT = new RenderTexture(width, height, 0, RenderTextureFormat.ARGB32);
        inputRT.enableRandomWrite = true;
        inputRT.filterMode = FilterMode.Point;
        inputRT.wrapMode = TextureWrapMode.Clamp;
        inputRT.Create();

        Graphics.Blit(binaryTexture, inputRT);

        if (outputTexture == null || outputTexture.width != width || outputTexture.height != height)
        {
            if (autoCreatedOutput != null)
            {
                autoCreatedOutput.Release();
            }

            autoCreatedOutput = new RenderTexture(width, height, 0, RenderTextureFormat.ARGBFloat);
            autoCreatedOutput.enableRandomWrite = true;
            autoCreatedOutput.filterMode = FilterMode.Bilinear;
            autoCreatedOutput.wrapMode = TextureWrapMode.Clamp;
            autoCreatedOutput.Create();
            outputTexture = autoCreatedOutput;

            Debug.Log($"Auto-created output RenderTexture with size {width}x{height}");
        }

        if (gradientTexture == null || gradientTexture.width != width || gradientTexture.height != height)
        {
            if (autoCreatedGradient != null)
            {
                autoCreatedGradient.Release();
            }

            autoCreatedGradient = new RenderTexture(width, height, 0, RenderTextureFormat.ARGBFloat);
            autoCreatedGradient.enableRandomWrite = true;
            autoCreatedGradient.filterMode = FilterMode.Bilinear;
            autoCreatedGradient.wrapMode = TextureWrapMode.Clamp;
            autoCreatedGradient.Create();
            gradientTexture = autoCreatedGradient;

            Debug.Log($"Auto-created gradient RenderTexture with size {width}x{height}");
        }
    }

    private void RunJFA()
    {
        computeShader.SetTexture(kernelInit, "SourceTexture", inputRT);
        computeShader.SetTexture(kernelInit, "Result", tempResult);
        computeShader.SetVector("TextureSize", new Vector2(width, height));

        int threadGroupsX = Mathf.CeilToInt(width / 8f);
        int threadGroupsY = Mathf.CeilToInt(height / 8f);

        computeShader.Dispatch(kernelInit, threadGroupsX, threadGroupsY, 1);

        int numIterations = Mathf.CeilToInt(Mathf.Log(Mathf.Max(width, height), 2f));
        if (maxIterations > 0)
        {
            numIterations = Mathf.Min(numIterations, maxIterations);
        }

        for (int i = numIterations - 1; i >= 0; i--)
        {
            computeShader.SetTexture(kernelJump, "PreviousResult", tempResult);
            computeShader.SetTexture(kernelJump, "Result", pingPongResult);
            computeShader.SetVector("TextureSize", new Vector2(width, height));
            computeShader.SetInt("PassIndex", i);

            computeShader.Dispatch(kernelJump, threadGroupsX, threadGroupsY, 1);

            RenderTexture swap = tempResult;
            tempResult = pingPongResult;
            pingPongResult = swap;
        }

        computeShader.SetTexture(kernelFinalize, "PreviousResult", tempResult);
        computeShader.SetTexture(kernelFinalize, "Result", outputTexture);
        computeShader.SetVector("TextureSize", new Vector2(width, height));

        computeShader.Dispatch(kernelFinalize, threadGroupsX, threadGroupsY, 1);

        computeShader.SetTexture(kernelGradient, "SDFTexture", outputTexture);
        computeShader.SetTexture(kernelGradient, "GradientResult", gradientTexture);
        computeShader.SetVector("TextureSize", new Vector2(width, height));
        computeShader.SetVector("InverseTextureSize", new Vector2(1f / width, 1f / height));

        computeShader.Dispatch(kernelGradient, threadGroupsX, threadGroupsY, 1);

        Debug.Log($"JFA SDF computation completed! Resolution: {width}x{height}, Iterations: {numIterations}");
    }

    private void OnDestroy()
    {
        ReleaseResources();
    }

    private void OnDisable()
    {
        ReleaseResources();
    }

    private void ReleaseResources()
    {
        if (tempResult != null)
        {
            tempResult.Release();
            tempResult = null;
        }

        if (pingPongResult != null)
        {
            pingPongResult.Release();
            pingPongResult = null;
        }

        if (inputRT != null)
        {
            inputRT.Release();
            inputRT = null;
        }

        if (autoCreatedOutput != null)
        {
            autoCreatedOutput.Release();
            autoCreatedOutput = null;
        }

        if (autoCreatedGradient != null)
        {
            autoCreatedGradient.Release();
            autoCreatedGradient = null;
        }
    }
}
