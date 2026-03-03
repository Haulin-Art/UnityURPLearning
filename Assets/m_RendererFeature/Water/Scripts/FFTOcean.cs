using UnityEngine;

[ExecuteAlways]
public class FFTOcean : MonoBehaviour
{
    [Header("General")]
    public int N = 512; // must be power of two
    public float amplitude = 1.0f;
    public Vector2 windDirection = new Vector2(1.0f, 1.0f);
    public float windSpeed = 30.0f;
    public float choppiness = 1.0f;
    public float gravity = 9.81f;

    [Header("Shaders")]
    public ComputeShader spectrumCS; // OceanSpectrum.compute
    public ComputeShader fftCS;      // FFT.compute
    public ComputeShader finalizeCS; // HeightNormal.compute

    [Header("Outputs")]
    public RenderTexture HeightRT;   // RFloat or R32 format (stores height)
    public RenderTexture NormalRT;   // RGBA32 or ARGBFloat (stores normals)
    public bool autoRun = true;

    // internals
    private RenderTexture h0RT; // initial complex spectrum h0(k)
    private RenderTexture hT_RT; // complex spectrum at time t
    private RenderTexture pingRT; // ping-pong for FFT (complex)
    private RenderTexture pongRT; // pong

    private int log2N;
    private int initKernel, timeKernel;
    private int fftKernel;
    private int finalizeKernel;

    void Start()
    {
        Init();
    }

    void OnValidate()
    {
        if (N <= 0) N = 512;
        if ((N & (N - 1)) != 0)
        {
            Debug.LogError("N must be power of two");
            N = Mathf.NextPowerOfTwo(N);
        }
    }

    void Init()
    {
        if (!Application.isPlaying && !autoRun) return;

        log2N = (int)Mathf.Log(N, 2);

        ReleaseTextures();
        CreateTextures();

        // kernels
        initKernel = spectrumCS.FindKernel("InitSpectrum");
        timeKernel = spectrumCS.FindKernel("SpectrumTime");
        fftKernel = fftCS.FindKernel("FFTStage");
        finalizeKernel = finalizeCS.FindKernel("HeightNormal");

        // init h0
        spectrumCS.SetInt("_N", N);
        spectrumCS.SetFloat("_L", N); // physical size scale (you can change to world size)
        spectrumCS.SetVector("_Wind", new Vector4(windDirection.x, windDirection.y, windSpeed, 0));
        spectrumCS.SetFloat("_A", amplitude);
        spectrumCS.SetFloat("_G", gravity);

        spectrumCS.SetTexture(initKernel, "_H0", h0RT);
        int thread = Mathf.Max(1, N / 8);
        spectrumCS.Dispatch(initKernel, N / 8, N / 8, 1);

        // prepare initial copy into ping
        Graphics.Blit(h0RT, pingRT);

        // create output RTs if not provided
        if (HeightRT == null)
        {
            HeightRT = CreateRT("Ocean_Height", N, N, RenderTextureFormat.RFloat);
        }
        if (NormalRT == null)
        {
            NormalRT = CreateRT("Ocean_Normal", N, N, RenderTextureFormat.ARGB32);
        }
    }

    void Update()
    {
        if (!autoRun) return;
        if (spectrumCS == null || fftCS == null || finalizeCS == null) return;

        RunSpectrumTime();
        RunFFTInverse();
        FinalizeToHeightAndNormal();
    }

    void RunSpectrumTime()
    {
        spectrumCS.SetInt("_N", N);
        spectrumCS.SetFloat("_Time", Time.time);
        spectrumCS.SetTexture(timeKernel, "_H0", h0RT);
        spectrumCS.SetTexture(timeKernel, "_HT", hT_RT);
        spectrumCS.Dispatch(timeKernel, N / 8, N / 8, 1);
    }

void RunFFTInverse()
{
    // copy spectrum (complex) into pingRT
    //Graphics.Blit(hT_RT, pingRT);
    Graphics.CopyTexture(hT_RT, pingRT);

    int halfN = N / 2;
    int threadsX = 8, threadsY = 8;

    for (int stage = 1; stage <= log2N; stage++)
    {
        int span = 1 << stage;

        // --- HORIZONTAL pass ---
        fftCS.SetInt("_N", N);
        fftCS.SetInt("_Stage", stage);
        fftCS.SetBool("_Horizontal", true);
        fftCS.SetInt("_Direction", 1); // inverse

        fftCS.SetTexture(fftKernel, "_Input", pingRT);
        fftCS.SetTexture(fftKernel, "_Output", pongRT);

        int dispatchX = Mathf.CeilToInt((N / 2.0f) / threadsX); // N/2 threads in X
        int dispatchY = Mathf.CeilToInt(N / (float)threadsY);
        fftCS.Dispatch(fftKernel, dispatchX, dispatchY, 1);

        // swap
        SwapRT(ref pingRT, ref pongRT);

        // --- VERTICAL pass ---
        fftCS.SetBool("_Horizontal", false);
        fftCS.SetTexture(fftKernel, "_Input", pingRT);
        fftCS.SetTexture(fftKernel, "_Output", pongRT);

        dispatchX = Mathf.CeilToInt(N / (float)threadsX);
        dispatchY = Mathf.CeilToInt((N / 2.0f) / threadsY); // N/2 threads in Y
        fftCS.Dispatch(fftKernel, dispatchX, dispatchY, 1);

        SwapRT(ref pingRT, ref pongRT);
    }

    // After loop: pingRT holds the spatial-domain complex texture (real in .x)
}

    void FinalizeToHeightAndNormal()
    {
        finalizeCS.SetInt("_N", N);
        finalizeCS.SetFloat("_Amplitude", amplitude);
        finalizeCS.SetFloat("_Choppiness", choppiness);
        finalizeCS.SetTexture(finalizeKernel, "_ComplexSpatial", pingRT);
        finalizeCS.SetTexture(finalizeKernel, "_HeightOut", HeightRT);
        finalizeCS.SetTexture(finalizeKernel, "_NormalOut", NormalRT);

        int tg = Mathf.Max(1, N / 8);
        finalizeCS.Dispatch(finalizeKernel, N / 8, N / 8, 1);
    }

    private RenderTexture CreateRT(string name, int w, int h, RenderTextureFormat fmt)
    {
        RenderTexture rt = new RenderTexture(w, h, 0, fmt);
        rt.enableRandomWrite = true;
        rt.wrapMode = TextureWrapMode.Repeat;
        rt.filterMode = FilterMode.Bilinear;
        rt.name = name;
        rt.Create();
        return rt;
    }

    void CreateTextures()
    {
        h0RT = CreateRT("H0", N, N, RenderTextureFormat.RGFloat);
        h0RT.filterMode = FilterMode.Point;
        h0RT.wrapMode = TextureWrapMode.Repeat; // 改为 Repeat
        hT_RT = CreateRT("HT", N, N, RenderTextureFormat.RGFloat);
        hT_RT.filterMode = FilterMode.Point;
        hT_RT.wrapMode = TextureWrapMode.Repeat; // 改为 Repeat
        pingRT = CreateRT("Ping", N, N, RenderTextureFormat.RGFloat);
        pingRT.filterMode = FilterMode.Point;
        pingRT.wrapMode = TextureWrapMode.Repeat; // 改为 Repeat
        pongRT = CreateRT("Pong", N, N, RenderTextureFormat.RGFloat);
        pongRT.filterMode = FilterMode.Point;
        pongRT.wrapMode = TextureWrapMode.Repeat; // 改为 Repeat
    }

    void ReleaseTextures()
    {
        void SafeRelease(RenderTexture r) { if (r != null) { r.Release(); DestroyImmediate(r); } }
        SafeRelease(h0RT);
        SafeRelease(hT_RT);
        SafeRelease(pingRT);
        SafeRelease(pongRT);
        // keep user-provided HeightRT/NormalRT intact
    }

    void OnDisable()
    {
        ReleaseTextures();
    }

    void SwapRT(ref RenderTexture a, ref RenderTexture b)
    {
        var t = a; a = b; b = t;
    }
}