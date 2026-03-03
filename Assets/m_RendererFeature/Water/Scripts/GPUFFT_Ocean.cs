using System;
using UnityEngine;

[ExecuteAlways]
public class GPUFFT_Ocean : MonoBehaviour
{
    [Header("Compute / Resources")]
    public ComputeShader fftCompute; // OceanFFT.compute
    [Tooltip("分辨率 (必须是 2 的幂)，生成 NxN 频谱/高度")]
    public int resolution = 512;

    [Header("Ocean Parameters")]
    public float patchSize = 1000f;    // 海面贴图对应的物理大小 (米)
    public Vector2 windDirection = new Vector2(1f, 1f);
    public float windSpeed = 20f;
    public float waveAmplitude = 1f;   // 控制总体高度
    public float gravity = 9.81f;
    public float timeScale = 1f;

    [Header("Outputs (可拖入已有的 RT)")]
    [Tooltip("输出高度图（RFloat）—— 如果为空本脚本会自动创建与管理")]
    public RenderTexture HeightRT;

    [Header("Debug / Misc")]
    [Tooltip("是否在编辑器也更新")]
    public bool runInEditMode = false;

    // 内部资源
    private int log2N;
    private RenderTexture h0Tex;          // 初始频谱 h0(k) (complex -> RGFloat)
    private RenderTexture spectrumTex;    // 当前频谱 H(k,t) (complex -> RGFloat)
    private RenderTexture pingTex;        // FFT 用 ping
    private RenderTexture pongTex;        // FFT 用 pong
    private ComputeBuffer h0Buffer;       // CPU 生成 h0 后上传 (float4 per texel: re,im,unused,unused)
    private ComputeBuffer omegaBuffer;    // 每个 k 的角频率 omega (float per texel)

    // kernels
    private int kernelUploadH0;
    private int kernelUpdateSpectrum;
    private int kernelFFTStageH;
    private int kernelFFTStageV;
    private int kernelSpectrumToHeight;

    // dispatch sizes
    private const int THREADS = 8; // numthreads in compute shader is [8,8,1]
    private int groups; // = resolution / THREADS

    private bool inited = false;

    void OnEnable() { InitIfNeeded(); }
    void OnDisable() { ReleaseAll(); }

    void Update()
    {
        if (!Application.isPlaying && !runInEditMode) return;
        if (!inited) InitIfNeeded();

        // update time & dispatch
        float t = Time.time * timeScale;
        UpdateSpectrumOnGPU(t);
        RunInverseFFT();
        ConvertSpectrumToHeight();
    }

    void InitIfNeeded()
    {
        if (fftCompute == null)
        {
            Debug.LogError("[GPUFFT_Ocean] 请把 OceanFFT.compute 拖入 fftCompute 字段。");
            return;
        }

        // check resolution power of 2
        if (resolution <= 0 || (resolution & (resolution - 1)) != 0)
        {
            Debug.LogError("[GPUFFT_Ocean] resolution 必须为 2 的幂 (例如 256,512,1024)。");
            return;
        }

        log2N = (int)Mathf.Log(resolution, 2);
        groups = Mathf.CeilToInt((float)resolution / THREADS);

        // kernels
        kernelUploadH0 = fftCompute.FindKernel("UploadH0");
        kernelUpdateSpectrum = fftCompute.FindKernel("UpdateSpectrum");
        kernelFFTStageH = fftCompute.FindKernel("FFTStageHorizontal");
        kernelFFTStageV = fftCompute.FindKernel("FFTStageVertical");
        kernelSpectrumToHeight = fftCompute.FindKernel("SpectrumToHeight");

        // create RTs (complex = RGFloat -> float2)
        h0Tex = CreateFloat2RT("H0Tex");
        spectrumTex = CreateFloat2RT("SpectrumTex");
        pingTex = CreateFloat2RT("PingTex");
        pongTex = CreateFloat2RT("PongTex");

        // create or ensure HeightRT
        if (HeightRT == null)
        {
            HeightRT = new RenderTexture(resolution, resolution, 0, RenderTextureFormat.RFloat);
            HeightRT.enableRandomWrite = true;
            HeightRT.Create();
        }
        else
        {
            // validate size/format
            if (HeightRT.width != resolution || HeightRT.height != resolution)
            {
                Debug.LogWarning("[GPUFFT_Ocean] 你拖入的 HeightRT 与 resolution 不匹配，脚本会忽略并在运行时重建。");
                HeightRT.Release();
                HeightRT.width = resolution;
                HeightRT.height = resolution;
                HeightRT.Create();
            }
        }

        // create CPU buffers and fill h0 / omega
        int count = resolution * resolution;
        if (h0Buffer != null) { h0Buffer.Release(); h0Buffer = null; }
        if (omegaBuffer != null) { omegaBuffer.Release(); omegaBuffer = null; }

        h0Buffer = new ComputeBuffer(count, sizeof(float) * 4, ComputeBufferType.Structured);
        omegaBuffer = new ComputeBuffer(count, sizeof(float), ComputeBufferType.Structured);

        GenerateH0AndOmegaOnCPU();

        inited = true;
    }

    // 创建供 RWTexture2D<float2> 使用的 RenderTexture
    private RenderTexture CreateFloat2RT(string name)
    {
        var rt = new RenderTexture(resolution, resolution, 0, RenderTextureFormat.RGFloat);
        rt.enableRandomWrite = true;
        rt.wrapMode = TextureWrapMode.Repeat;
        rt.filterMode = FilterMode.Bilinear;
        rt.name = name;
        rt.Create();
        return rt;
    }

    // 生成 h0(k) 与 omega(k) 在 CPU，再上传到 GPU buffer
    private void GenerateH0AndOmegaOnCPU()
    {
        int N = resolution;
        int idx = 0;
        var h0data = new Vector4[N * N];
        var omegaData = new float[N * N];

        // normalize wind dir
        Vector2 w = windDirection.normalized;
        float A = waveAmplitude;
        float L = windSpeed * windSpeed / gravity; // “风相关尺度” (常用)
        float PI2 = Mathf.PI * 2f;
        System.Random rng = new System.Random(12345); // 固定种子方便复现

        for (int y = 0; y < N; y++)
        {
            float ky = ( (y + 0.0f) - N/2 ) * (PI2 / patchSize);
            for (int x = 0; x < N; x++)
            {
                float kx = ( (x + 0.0f) - N/2 ) * (PI2 / patchSize);
                Vector2 k = new Vector2(kx, ky);
                float kLen = k.magnitude;

                // Omega
                float omega = Mathf.Sqrt(Mathf.Max(0.0f, gravity * kLen)); // simplified dispersion
                omegaData[idx] = omega;

                // Phillips spectrum (简化版)
                float phillips = 0f;
                if (kLen > 1e-6f)
                {
                    Vector2 kN = k / kLen;
                    float kDotW = Vector2.Dot(kN, w);
                    float kDotW2 = kDotW * kDotW;

                    float L2 = L * L;
                    float k2 = kLen * kLen;
                    float damping = 0.001f;
                    float l2 = Mathf.Pow(damping, 2f);

                    // Phillips spectrum formula (常用简化)
                    phillips = A * Mathf.Exp(-1f/(k2 * L2)) / (k2 * k2) * kDotW2 * Mathf.Exp(-k2 * l2);
                }

                // Gaussian random (Box-Muller)
                float u1 = (float)rng.NextDouble();
                float u2 = (float)rng.NextDouble();
                float mag = Mathf.Sqrt(-2f * Mathf.Log(Mathf.Max(1e-9f, u1)));
                float gaussR = mag * Mathf.Cos(2f * Mathf.PI * u2);
                float gaussI = mag * Mathf.Sin(2f * Mathf.PI * u2);

                float sqrtP = Mathf.Sqrt(Mathf.Max(0f, phillips) / 2f);
                float real = gaussR * sqrtP;
                float imag = gaussI * sqrtP;

                h0data[idx] = new Vector4(real, imag, 0f, 0f);
                idx++;
            }
        }

        // upload to GPU compute buffers
        h0Buffer.SetData(h0data);
        omegaBuffer.SetData(omegaData);

        // Bind buffers and dispatch UploadH0 kernel to write h0Buffer -> h0Tex
        fftCompute.SetInt("_N", resolution);
        fftCompute.SetBuffer(kernelUploadH0, "_H0Buffer", h0Buffer);
        fftCompute.SetTexture(kernelUploadH0, "_H0Tex", h0Tex);
        fftCompute.SetBuffer(kernelUploadH0, "_OmegaBuffer", omegaBuffer); // optional if you want to store per-k omega into a texture; not required

        int groups2D = Mathf.CeilToInt((float)resolution / THREADS);
        fftCompute.Dispatch(kernelUploadH0, groups2D, groups2D, 1);

        // Initially copy h0Tex into spectrumTex to have something; UpdateSpectrum will overwrite each frame.
        Graphics.CopyTexture(h0Tex, spectrumTex);
    }

    // 在 GPU 上根据 h0(k) 与 omega(k) 计算 H(k,t)
    private void UpdateSpectrumOnGPU(float t)
    {
        fftCompute.SetInt("_N", resolution);
        fftCompute.SetFloat("_Time", t);
        fftCompute.SetFloat("_PatchSize", patchSize);
        fftCompute.SetFloat("_Amplitude", waveAmplitude);
        fftCompute.SetFloats("_WindDir", new float[] { windDirection.x, windDirection.y });
        fftCompute.SetFloat("_Gravity", gravity);

        fftCompute.SetTexture(kernelUpdateSpectrum, "_H0Tex", h0Tex);
        fftCompute.SetTexture(kernelUpdateSpectrum, "_SpectrumOut", spectrumTex);
        fftCompute.SetBuffer(kernelUpdateSpectrum, "_OmegaBuffer", omegaBuffer);

        int groups2D = Mathf.CeilToInt((float)resolution / THREADS);
        fftCompute.Dispatch(kernelUpdateSpectrum, groups2D, groups2D, 1);
    }

    // 执行 2D iFFT：对每一行做 logN 个阶段，再对每一列做 logN 个阶段（Stockham 风格）
    private void RunInverseFFT()
    {
        // We'll use ping/pong: 输入 spectrumTex -> ping/pong -> 最终结果写回 pingTex
        // copy current spectrum into pingTex as starting source
        Graphics.CopyTexture(spectrumTex, pingTex);

        int N = resolution;
        fftCompute.SetInt("_N", N);

        // 设置 sign = +1 表示逆变换 (这里约定：逆 FFT 用 +1，最终结果会被除以 N*N)
        fftCompute.SetInt("_Sign", 1);

        for (int stage = 1; stage <= log2N; stage++)
        {
            fftCompute.SetInt("_Stage", stage);

            // Horizontal stage: read from pingTex -> write into pongTex
            fftCompute.SetTexture(kernelFFTStageH, "_SrcTex", pingTex);
            fftCompute.SetTexture(kernelFFTStageH, "_DstTex", pongTex);
            fftCompute.Dispatch(kernelFFTStageH, groups, groups, 1);

            // swap
            SwapRT(ref pingTex, ref pongTex);
        }

        // now do columns (vertical)
        for (int stage = 1; stage <= log2N; stage++)
        {
            fftCompute.SetInt("_Stage", stage);

            fftCompute.SetTexture(kernelFFTStageV, "_SrcTex", pingTex);
            fftCompute.SetTexture(kernelFFTStageV, "_DstTex", pongTex);
            fftCompute.Dispatch(kernelFFTStageV, groups, groups, 1);

            SwapRT(ref pingTex, ref pongTex);
        }

        // result is in pingTex now (spatial domain complex)
        // We'll keep it as the source for SpectrumToHeight
        // (no copy needed)
    }

    private void ConvertSpectrumToHeight()
    {
        fftCompute.SetInt("_N", resolution);
        fftCompute.SetTexture(kernelSpectrumToHeight, "_SpatialComplex", pingTex);
        fftCompute.SetTexture(kernelSpectrumToHeight, "_HeightOut", HeightRT);
        fftCompute.Dispatch(kernelSpectrumToHeight, groups, groups, 1);
    }

    void SwapRT(ref RenderTexture a, ref RenderTexture b) { var t = a; a = b; b = t; }

    void ReleaseAll()
    {
        inited = false;
        if (h0Tex) { h0Tex.Release(); DestroyImmediate(h0Tex); h0Tex = null; }
        if (spectrumTex) { spectrumTex.Release(); DestroyImmediate(spectrumTex); spectrumTex = null; }
        if (pingTex) { pingTex.Release(); DestroyImmediate(pingTex); pingTex = null; }
        if (pongTex) { pongTex.Release(); DestroyImmediate(pongTex); pongTex = null; }
        if (h0Buffer != null) { h0Buffer.Release(); h0Buffer = null; }
        if (omegaBuffer != null) { omegaBuffer.Release(); omegaBuffer = null; }
        // NOTE: HeightRT 如果是用户拖入的，不要释放；如果是脚本自动创建（当前实现始终创建或覆盖），我们不会destroy，以避免破坏用户资源.
    }

    void OnDestroy() { ReleaseAll(); }
}