using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace FrequencyHighlight
{
    /// <summary>
    /// 频域高光Renderer Feature
    /// 使用FFT实现自定义形状的高光效果
    /// </summary>
    public class FrequencyHighlightFeature : ScriptableRendererFeature
    {
        [System.Serializable]
        public class Settings
        {
            [Header("降采样设置")]
            [Tooltip("工作分辨率（必须是2的幂次）")]
            public int resolution = 256;
            
            [Header("高光提取设置")]
            [Tooltip("高光阈值")]
            [Range(0f, 1f)]
            public float threshold = 0.7f;
            [Tooltip("过渡柔和度")]
            [Range(0.01f, 1f)]
            public float softness = 0.1f;
            
            [Header("距离限制")]
            [Tooltip("最小距离（世界单位）")]
            public float distanceMin = 1.0f;
            [Tooltip("最大距离（世界单位），超过此距离的高光会被忽略")]
            public float distanceMax = 50.0f;
            
            [Header("高光形状")]
            [Tooltip("时域高光形状图（原始图片），图片需要设置为Clamp模式，且宽高相等，建议使用黑底白图")]
            public Texture2D highlightShapeSource;
            [Tooltip("高光形状缩放")]
            public Vector2 highlightShapeScale = new Vector2(1.0f, 1.0f);
            [Tooltip("屏幕宽高比（用于预处理校正）")]
            public float aspectRatio = 1.0f;
            [Tooltip("高光形状的频域图（复数格式，R=实部，G=虚部）- 自动生成")]
            public RenderTexture highlightKernelFrequencyRT;
            [Tooltip("是否需要更新高光形状频谱图")]
            public bool needUpdateHighlightKernel = false;
            
            [Header("高光效果")]
            [Tooltip("高光强度")]
            [Range(0f, 5f)]
            public float intensity = 1.0f;
            [Tooltip("高光颜色")]
            public Color highlightColor = Color.white;
            [Tooltip("边界淡出范围（防止FFT周期性边界问题）")]
            [Range(0f, 0.5f)]
            public float borderFade = 0.1f;
            
            [Header("FFT设置")]
            [Tooltip("FFT Compute Shader")]
            public ComputeShader fftComputeShader;
            
            [Header("调试")]
            [Tooltip("显示中间结果")]
            public bool debugMode = false;
            [Tooltip("调试显示阶段")]
            public DebugStage debugStage = DebugStage.HighlightExtract;
        }

        public enum DebugStage
        {
            HighlightExtract,   // 显示高光提取结果
            FFT,                // 显示FFT结果
            Multiply,           // 显示频域相乘结果
            IFFT                // 显示IFFT结果（最终高光）
        }

        public Settings settings = new Settings();
        
        private FrequencyHighlightPass m_Pass;
        private HighlightKernelGenerator m_KernelGenerator;

        public override void Create()
        {
            m_Pass = new FrequencyHighlightPass(settings);
            m_Pass.renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
            
            m_KernelGenerator = new HighlightKernelGenerator(settings);
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            // 检查是否需要更新高光形状频谱图
            // 如果频谱图为空但源图存在，自动生成
            if (settings.needUpdateHighlightKernel || 
                (settings.highlightKernelFrequencyRT == null && settings.highlightShapeSource != null))
            {
                settings.aspectRatio = (float)renderingData.cameraData.cameraTargetDescriptor.width / renderingData.cameraData.cameraTargetDescriptor.height;
                m_KernelGenerator?.GenerateKernel();
                settings.needUpdateHighlightKernel = false;
            }
            
            // 使用自动生成的频谱图或手动指定的频谱图
            if (settings.highlightKernelFrequencyRT == null && !settings.debugMode)
                return;
                
            renderer.EnqueuePass(m_Pass);
        }

        protected override void Dispose(bool disposing)
        {
            m_Pass?.Dispose();
            m_KernelGenerator?.Dispose();
        }
        
        /// <summary>
        /// 触发更新高光形状频谱图
        /// </summary>
        public void UpdateHighlightKernel()
        {
            settings.needUpdateHighlightKernel = true;
        }
    }

    /// <summary>
    /// 频域高光渲染Pass
    /// </summary>
    public class FrequencyHighlightPass : ScriptableRenderPass
    {
        private FrequencyHighlightFeature.Settings m_Settings;
        private Shader m_HighlightExtractShader;
        private Material m_HighlightExtractMaterial;
        private Shader m_FFTVisualizeShader;
        private Material m_FFTVisualizeMaterial;

        private Shader m_HighlightShapeShader;
        private Material m_HighlightShapeMaterial;
        private Shader m_CompositeShader;
        private Material m_CompositeMaterial;
        
        // RenderTexture IDs
        private int m_HighlightTextureID;
        private int m_FFTTextureAID;
        private int m_FFTTextureBID;
        private int m_MultipliedTextureID;
        private int m_ResultTextureID;
        
        // Compute Shader
        private ComputeShader m_FFTCompute;
        private int m_KernelBitReverseReal;
        private int m_KernelBitReverseComplex;
        private int m_KernelFFTH;
        private int m_KernelFFTV;
        private int m_KernelIFFTH;
        private int m_KernelIFFTV;
        private int m_KernelFFTShift;
        private int m_KernelNormalize;
        private int m_KernelMultiplyComplex;

        public FrequencyHighlightPass(FrequencyHighlightFeature.Settings settings)
        {
            m_Settings = settings;
            
            // 初始化高光提取Shader
            m_HighlightExtractShader = Shader.Find("Hidden/FrequencyHighlight/HighlightExtract");
            if (m_HighlightExtractShader != null)
            {
                m_HighlightExtractMaterial = new Material(m_HighlightExtractShader);
            }
            
            // 初始化FFT可视化Shader
            m_FFTVisualizeShader = Shader.Find("Hidden/FrequencyHighlight/FFTVisualize");
            if (m_FFTVisualizeShader != null)
            {
                m_FFTVisualizeMaterial = new Material(m_FFTVisualizeShader);
            }
            // 初始化处理高光形状的Shader
            m_HighlightShapeShader = Shader.Find("Hidden/FrequencyHighlight/HighLightPreProcess");
            if (m_HighlightShapeShader != null)
            {
                m_HighlightShapeMaterial = new Material(m_HighlightShapeShader);
            }
            // 初始化合成Shader,这个是用来将高光效果叠加到原始画面上的Shader
            m_CompositeShader = Shader.Find("Hidden/FrequencyHighlight/Composite");
            if (m_CompositeShader != null)
            {
                m_CompositeMaterial = new Material(m_CompositeShader);
            }
            
            // 使用Settings中的FFT Compute Shader
            m_FFTCompute = settings.fftComputeShader;
            if (m_FFTCompute != null)
            {
                InitFFTKernels();
            }
            
            // 初始化RenderTarget IDs
            m_HighlightTextureID = Shader.PropertyToID("_HighlightTexture");
            m_FFTTextureAID = Shader.PropertyToID("_FFTTextureA");
            m_FFTTextureBID = Shader.PropertyToID("_FFTTextureB");
            m_MultipliedTextureID = Shader.PropertyToID("_MultipliedTexture");
            m_ResultTextureID = Shader.PropertyToID("_ResultTexture");
        }

        private void InitFFTKernels()
        {
            m_KernelBitReverseReal = m_FFTCompute.FindKernel("BitReverseCopyReal");
            m_KernelBitReverseComplex = m_FFTCompute.FindKernel("BitReverseCopyComplex");
            m_KernelFFTH = m_FFTCompute.FindKernel("FFTStepHorizontal");
            m_KernelFFTV = m_FFTCompute.FindKernel("FFTStepVertical");
            m_KernelIFFTH = m_FFTCompute.FindKernel("IFFTStepHorizontal");
            m_KernelIFFTV = m_FFTCompute.FindKernel("IFFTStepVertical");
            m_KernelFFTShift = m_FFTCompute.FindKernel("FFTShift");
            m_KernelNormalize = m_FFTCompute.FindKernel("Normalize");
            m_KernelMultiplyComplex = m_FFTCompute.FindKernel("MultiplyComplex");
        }

        public void Dispose()
        {
            if (m_HighlightExtractMaterial != null)
            {
                Object.DestroyImmediate(m_HighlightExtractMaterial);
            }
            if (m_FFTVisualizeMaterial != null)
            {
                Object.DestroyImmediate(m_FFTVisualizeMaterial);
            }
            if (m_CompositeMaterial != null)
            {
                Object.DestroyImmediate(m_CompositeMaterial);
            }
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            // 创建降采样后的渲染纹理描述符
            RenderTextureDescriptor descriptor = renderingData.cameraData.cameraTargetDescriptor;
            descriptor.width = m_Settings.resolution;
            descriptor.height = m_Settings.resolution;
            descriptor.colorFormat = RenderTextureFormat.ARGBFloat;
            descriptor.enableRandomWrite = true;
            descriptor.depthBufferBits = 0;
            descriptor.msaaSamples = 1; // 禁用MSAA，因为与enableRandomWrite不兼容
            
            // 分配临时渲染纹理
            cmd.GetTemporaryRT(m_HighlightTextureID, descriptor, FilterMode.Bilinear);
            cmd.GetTemporaryRT(m_FFTTextureAID, descriptor, FilterMode.Bilinear);
            cmd.GetTemporaryRT(m_FFTTextureBID, descriptor, FilterMode.Bilinear);
            cmd.GetTemporaryRT(m_MultipliedTextureID, descriptor, FilterMode.Bilinear);
            cmd.GetTemporaryRT(m_ResultTextureID, descriptor, FilterMode.Bilinear);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (m_HighlightExtractMaterial == null)
                return;

            CommandBuffer cmd = CommandBufferPool.Get("Frequency Highlight");
            
            RenderTargetIdentifier source = renderingData.cameraData.renderer.cameraColorTargetHandle;
            int size = m_Settings.resolution;
            
            // ========================================
            // 第一步：降采样并提取高光区域
            // ========================================
            Pass_HighlightExtract(cmd, source, size);
            
            // 调试模式：显示高光提取结果
            if (m_Settings.debugMode && m_Settings.debugStage == FrequencyHighlightFeature.DebugStage.HighlightExtract)
            {
                cmd.Blit(m_HighlightTextureID, source);
                context.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
                return;
            }
            
            // ========================================
            // 第二步：FFT变换
            // ========================================
            Pass_FFT(cmd, m_HighlightTextureID, m_FFTTextureAID, size);
            
            // 调试模式：显示FFT结果（需要转换为幅度谱）
            if (m_Settings.debugMode && m_Settings.debugStage == FrequencyHighlightFeature.DebugStage.FFT)
            {
                Pass_VisualizeFFT(cmd, m_FFTTextureAID, source, size);
                context.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
                return;
            }
            
            // ========================================
            // 第三步：频域相乘
            // 场景高光频域图 × 高光形状频域图 = 卷积结果频域图
            // ========================================
            if (m_Settings.highlightKernelFrequencyRT == null)
            {
                context.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
                return;
            }
            
            Pass_MultiplyFrequency(cmd, m_FFTTextureAID, m_Settings.highlightKernelFrequencyRT, m_MultipliedTextureID, size);
            
            // 调试模式：显示频域相乘结果
            if (m_Settings.debugMode && m_Settings.debugStage == FrequencyHighlightFeature.DebugStage.Multiply)
            {
                Pass_VisualizeFFT(cmd, m_MultipliedTextureID, source, size);
                context.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
                return;
            }
            
            // ========================================
            // 第四步：IFFT变换
            // 将频域图转换回时域图（得到卷积结果）
            // ========================================
            Pass_IFFT(cmd, m_MultipliedTextureID, m_ResultTextureID, size);
            
            // 调试模式：显示IFFT结果（最终高光效果）
            if (m_Settings.debugMode && m_Settings.debugStage == FrequencyHighlightFeature.DebugStage.IFFT)
            {
                cmd.Blit(m_ResultTextureID, source);
                context.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
                return;
            }
            
            // ========================================
            // 第五步：合成到屏幕
            // 将高光效果叠加到原始画面上
            // ========================================
            Pass_Composite(cmd, source, m_ResultTextureID, renderingData);
            
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            cmd.ReleaseTemporaryRT(m_HighlightTextureID);
            cmd.ReleaseTemporaryRT(m_FFTTextureAID);
            cmd.ReleaseTemporaryRT(m_FFTTextureBID);
            cmd.ReleaseTemporaryRT(m_MultipliedTextureID);
            cmd.ReleaseTemporaryRT(m_ResultTextureID);
        }

        /// <summary>
        /// 第一步：降采样并提取高光区域
        /// 将屏幕画面转换为灰度，使用smoothstep提取高光区域
        /// </summary>
        private void Pass_HighlightExtract(CommandBuffer cmd, RenderTargetIdentifier source, int size)
        {
            // 设置材质参数
            m_HighlightExtractMaterial.SetFloat("_Threshold", m_Settings.threshold);
            m_HighlightExtractMaterial.SetFloat("_Softness", m_Settings.softness);
            m_HighlightExtractMaterial.SetFloat("_DistanceMin", m_Settings.distanceMin);
            m_HighlightExtractMaterial.SetFloat("_DistanceMax", m_Settings.distanceMax);
            
            // 执行Blit：降采样 + 高光提取
            cmd.Blit(source, m_HighlightTextureID, m_HighlightExtractMaterial);
        }

        /// <summary>
        /// 第二步：FFT变换
        /// 将时域高光图转换为频域图
        /// </summary>
        private void Pass_FFT(CommandBuffer cmd, RenderTargetIdentifier input, RenderTargetIdentifier output, int size)
        {
            if (m_FFTCompute == null)
                return;

            // 使用双缓冲进行乒乓操作
            RenderTextureDescriptor desc = new RenderTextureDescriptor(size, size, RenderTextureFormat.ARGBFloat, 0);
            desc.enableRandomWrite = true;
            desc.depthBufferBits = 0;
            desc.msaaSamples = 1; // 禁用MSAA，因为与enableRandomWrite不兼容
            
            // 创建临时纹理用于乒乓操作
            int tempA = Shader.PropertyToID("_TempFFTA");
            int tempB = Shader.PropertyToID("_TempFFTB");
            cmd.GetTemporaryRT(tempA, desc, FilterMode.Point);
            cmd.GetTemporaryRT(tempB, desc, FilterMode.Point);
            
            // ========================================
            // 步骤1：位反转重排（DIT-FFT的第一步）
            // ========================================
            cmd.SetComputeTextureParam(m_FFTCompute, m_KernelBitReverseReal, "SourceTexture", input);
            cmd.SetComputeTextureParam(m_FFTCompute, m_KernelBitReverseReal, "OutputTexture", tempA);
            cmd.SetComputeIntParam(m_FFTCompute, "Size", size);
            cmd.DispatchCompute(m_FFTCompute, m_KernelBitReverseReal, (size + 7) / 8, (size + 7) / 8, 1);
            
            // 乒乓操作：交换纹理
            int currentInput = tempA;
            int currentOutput = tempB;
            
            // ========================================
            // 步骤2：蝶形运算（step从2到size，每次翻倍）
            // ========================================
            for (int step = 2; step <= size; step *= 2)
            {
                // 水平方向FFT
                cmd.SetComputeTextureParam(m_FFTCompute, m_KernelFFTH, "InputTexture", currentInput);
                cmd.SetComputeTextureParam(m_FFTCompute, m_KernelFFTH, "OutputTexture", currentOutput);
                cmd.SetComputeIntParam(m_FFTCompute, "Size", size);
                cmd.SetComputeIntParam(m_FFTCompute, "Step", step);
                cmd.DispatchCompute(m_FFTCompute, m_KernelFFTH, (size + 7) / 8, (size + 7) / 8, 1);
                
                // 交换
                Swap(ref currentInput, ref currentOutput);
                
                // 垂直方向FFT
                cmd.SetComputeTextureParam(m_FFTCompute, m_KernelFFTV, "InputTexture", currentInput);
                cmd.SetComputeTextureParam(m_FFTCompute, m_KernelFFTV, "OutputTexture", currentOutput);
                cmd.SetComputeIntParam(m_FFTCompute, "Size", size);
                cmd.SetComputeIntParam(m_FFTCompute, "Step", step);
                cmd.DispatchCompute(m_FFTCompute, m_KernelFFTV, (size + 7) / 8, (size + 7) / 8, 1);
                
                // 交换
                Swap(ref currentInput, ref currentOutput);
            }
            
            // ========================================
            // 步骤3：FFTShift - 将低频移到中心，便于可视化
            // ========================================
            cmd.SetComputeTextureParam(m_FFTCompute, m_KernelFFTShift, "InputTexture", currentInput);
            cmd.SetComputeTextureParam(m_FFTCompute, m_KernelFFTShift, "OutputTexture", currentOutput);
            cmd.SetComputeIntParam(m_FFTCompute, "Size", size);
            cmd.DispatchCompute(m_FFTCompute, m_KernelFFTShift, (size + 7) / 8, (size + 7) / 8, 1);
            
            // 交换
            Swap(ref currentInput, ref currentOutput);
            
            // 复制结果到输出纹理
            cmd.Blit(currentInput, output);
            
            // 释放临时纹理
            cmd.ReleaseTemporaryRT(tempA);
            cmd.ReleaseTemporaryRT(tempB);
        }
        
        private void Swap(ref int a, ref int b)
        {
            int temp = a;
            a = b;
            b = temp;
        }
        
        /// <summary>
        /// FFT结果可视化
        /// 将复数频域数据转换为幅度谱并显示
        /// </summary>
        private void Pass_VisualizeFFT(CommandBuffer cmd, RenderTargetIdentifier input, RenderTargetIdentifier output, int size)
        {
            if (m_FFTVisualizeMaterial == null)
            {
                // 如果没有可视化材质，直接复制
                cmd.Blit(input, output);
                return;
            }
            
            // 使用可视化Shader将复数转换为幅度谱
            cmd.Blit(input, output, m_FFTVisualizeMaterial);
        }
        
        /// <summary>
        /// 第三步：频域相乘
        /// 场景高光频域图 × 高光形状频域图 = 卷积结果频域图
        /// </summary>
        private void Pass_MultiplyFrequency(CommandBuffer cmd, RenderTargetIdentifier input, Texture kernelTexture, RenderTargetIdentifier output, int size)
        {
            if (m_FFTCompute == null || kernelTexture == null)
                return;

            // 创建临时纹理用于输出
            int tempOutput = Shader.PropertyToID("_TempMultiplyOutput");
            RenderTextureDescriptor desc = new RenderTextureDescriptor(size, size, RenderTextureFormat.ARGBFloat, 0);
            desc.enableRandomWrite = true;
            desc.depthBufferBits = 0;
            desc.msaaSamples = 1; // 禁用MSAA，因为与enableRandomWrite不兼容
            cmd.GetTemporaryRT(tempOutput, desc, FilterMode.Point);
            
            // 设置Compute Shader参数
            cmd.SetComputeTextureParam(m_FFTCompute, m_KernelMultiplyComplex, "InputTexture", input);
            cmd.SetComputeTextureParam(m_FFTCompute, m_KernelMultiplyComplex, "KernelTexture", kernelTexture);
            cmd.SetComputeTextureParam(m_FFTCompute, m_KernelMultiplyComplex, "OutputTexture", tempOutput);
            cmd.SetComputeIntParam(m_FFTCompute, "Size", size);
            
            // 执行复数乘法
            cmd.DispatchCompute(m_FFTCompute, m_KernelMultiplyComplex, (size + 7) / 8, (size + 7) / 8, 1);
            
            // 复制结果到输出纹理
            cmd.Blit(tempOutput, output);
            
            // 释放临时纹理
            cmd.ReleaseTemporaryRT(tempOutput);
        }
        
        /// <summary>
        /// 第四步：IFFT变换
        /// 将频域图转换回时域图（得到卷积结果）
        /// </summary>
        private void Pass_IFFT(CommandBuffer cmd, RenderTargetIdentifier input, RenderTargetIdentifier output, int size)
        {
            if (m_FFTCompute == null)
                return;

            // 使用双缓冲进行乒乓操作
            RenderTextureDescriptor desc = new RenderTextureDescriptor(size, size, RenderTextureFormat.ARGBFloat, 0);
            desc.enableRandomWrite = true;
            desc.depthBufferBits = 0;
            desc.msaaSamples = 1; // 禁用MSAA，因为与enableRandomWrite不兼容
            
            // 创建临时纹理用于乒乓操作
            int tempA = Shader.PropertyToID("_TempIFFTA");
            int tempB = Shader.PropertyToID("_TempIFFTB");
            cmd.GetTemporaryRT(tempA, desc, FilterMode.Point);
            cmd.GetTemporaryRT(tempB, desc, FilterMode.Point);
            
            // ========================================
            // 步骤1：IFFTShift - 还原中心化的频谱
            // ========================================
            cmd.SetComputeTextureParam(m_FFTCompute, m_KernelFFTShift, "InputTexture", input);
            cmd.SetComputeTextureParam(m_FFTCompute, m_KernelFFTShift, "OutputTexture", tempA);
            cmd.SetComputeIntParam(m_FFTCompute, "Size", size);
            cmd.DispatchCompute(m_FFTCompute, m_KernelFFTShift, (size + 7) / 8, (size + 7) / 8, 1);
            
            // 乒乓操作：交换纹理
            int currentInput = tempA;
            int currentOutput = tempB;
            
            // ========================================
            // 步骤2：位反转重排（DIT-IFFT的第一步）
            // ========================================
            cmd.SetComputeTextureParam(m_FFTCompute, m_KernelBitReverseComplex, "SourceTexture", currentInput);
            cmd.SetComputeTextureParam(m_FFTCompute, m_KernelBitReverseComplex, "OutputTexture", currentOutput);
            cmd.SetComputeIntParam(m_FFTCompute, "Size", size);
            cmd.DispatchCompute(m_FFTCompute, m_KernelBitReverseComplex, (size + 7) / 8, (size + 7) / 8, 1);
            
            // 交换
            Swap(ref currentInput, ref currentOutput);
            
            // ========================================
            // 步骤3：蝶形运算（旋转因子使用正角度）
            // ========================================
            for (int step = 2; step <= size; step *= 2)
            {
                // 水平方向IFFT
                cmd.SetComputeTextureParam(m_FFTCompute, m_KernelIFFTH, "InputTexture", currentInput);
                cmd.SetComputeTextureParam(m_FFTCompute, m_KernelIFFTH, "OutputTexture", currentOutput);
                cmd.SetComputeIntParam(m_FFTCompute, "Size", size);
                cmd.SetComputeIntParam(m_FFTCompute, "Step", step);
                cmd.DispatchCompute(m_FFTCompute, m_KernelIFFTH, (size + 7) / 8, (size + 7) / 8, 1);
                
                // 交换
                Swap(ref currentInput, ref currentOutput);
                
                // 垂直方向IFFT
                cmd.SetComputeTextureParam(m_FFTCompute, m_KernelIFFTV, "InputTexture", currentInput);
                cmd.SetComputeTextureParam(m_FFTCompute, m_KernelIFFTV, "OutputTexture", currentOutput);
                cmd.SetComputeIntParam(m_FFTCompute, "Size", size);
                cmd.SetComputeIntParam(m_FFTCompute, "Step", step);
                cmd.DispatchCompute(m_FFTCompute, m_KernelIFFTV, (size + 7) / 8, (size + 7) / 8, 1);
                
                // 交换
                Swap(ref currentInput, ref currentOutput);
            }
            
            // ========================================
            // 步骤4：归一化（除以N²）
            // ========================================
            cmd.SetComputeTextureParam(m_FFTCompute, m_KernelNormalize, "InputTexture", currentInput);
            cmd.SetComputeTextureParam(m_FFTCompute, m_KernelNormalize, "OutputTexture", currentOutput);
            cmd.SetComputeIntParam(m_FFTCompute, "Size", size);
            cmd.DispatchCompute(m_FFTCompute, m_KernelNormalize, (size + 7) / 8, (size + 7) / 8, 1);
            
            // 交换
            Swap(ref currentInput, ref currentOutput);
            
            // 复制结果到输出纹理
            cmd.Blit(currentInput, output);
            
            // 释放临时纹理
            cmd.ReleaseTemporaryRT(tempA);
            cmd.ReleaseTemporaryRT(tempB);
        }
        
        /// <summary>
        /// 第五步：合成到屏幕
        /// 将高光效果叠加到原始画面上
        /// </summary>
        private void Pass_Composite(CommandBuffer cmd, RenderTargetIdentifier source, RenderTargetIdentifier highlightTexture, RenderingData renderingData)
        {
            if (m_CompositeMaterial == null)
            {
                // 如果没有合成材质，直接复制高光结果
                cmd.Blit(highlightTexture, source);
                return;
            }
            
            // 获取原始屏幕分辨率
            RenderTextureDescriptor screenDescriptor = renderingData.cameraData.cameraTargetDescriptor;
            screenDescriptor.colorFormat = RenderTextureFormat.ARGBFloat;
            screenDescriptor.enableRandomWrite = true;
            screenDescriptor.depthBufferBits = 0;
            screenDescriptor.msaaSamples = 1; // 禁用MSAA，因为与enableRandomWrite不兼容
            
            // 创建全分辨率的临时纹理（用于放大后的高光）
            int fullScreenHighlightRT = Shader.PropertyToID("_FullScreenHighlightRT");
            cmd.GetTemporaryRT(fullScreenHighlightRT, screenDescriptor, FilterMode.Bilinear);
            
            // 将降采样后的高光图放大到全分辨率
            cmd.Blit(highlightTexture, fullScreenHighlightRT);
            
            // 创建临时输出纹理（用于合成结果）
            int compositeOutputRT = Shader.PropertyToID("_CompositeOutputRT");
            cmd.GetTemporaryRT(compositeOutputRT, screenDescriptor, FilterMode.Bilinear);
            
            // 设置合成材质参数
            m_CompositeMaterial.SetFloat("_Intensity", m_Settings.intensity);
            m_CompositeMaterial.SetColor("_HighlightColor", m_Settings.highlightColor);
            m_CompositeMaterial.SetFloat("_BorderFade", m_Settings.borderFade);
            
            // 设置高光纹理（使用全局纹理，因为fullScreenHighlightRT是临时渲染纹理ID）
            //m_CompositeMaterial.SetTexture("_HighlightTex", fullScreenHighlightRT);
            cmd.SetGlobalTexture("_HighlightTex", fullScreenHighlightRT);
            
            // 执行Blit：source -> compositeOutputRT，使用材质进行合成
            cmd.Blit(source, compositeOutputRT, m_CompositeMaterial);
            
            // 将合成结果复制回屏幕
            cmd.Blit(compositeOutputRT, source);
            
            // 释放临时纹理
            cmd.ReleaseTemporaryRT(fullScreenHighlightRT);
            cmd.ReleaseTemporaryRT(compositeOutputRT);
        }
    }
    
    /// <summary>
    /// 高光形状频谱图生成器
    /// 在编辑器中将时域高光形状图转换为频域图
    /// </summary>
    public class HighlightKernelGenerator
    {
        private FrequencyHighlightFeature.Settings m_Settings;
        private Shader m_HighlightPreProcessShader;
        private Material m_HighlightPreProcessMaterial;
        private ComputeShader m_FFTCompute;
        private int m_KernelBitReverseReal;
        private int m_KernelFFTH;
        private int m_KernelFFTV;
        private int m_KernelFFTShift;

        public HighlightKernelGenerator(FrequencyHighlightFeature.Settings settings)
        {
            m_Settings = settings;
            
            // 初始化预处理Shader
            m_HighlightPreProcessShader = Shader.Find("Hidden/FrequencyHighlight/HighLightPreProcess");
            if (m_HighlightPreProcessShader != null)
            {
                m_HighlightPreProcessMaterial = new Material(m_HighlightPreProcessShader);
            }
            
            // 初始化FFT Compute Shader
            m_FFTCompute = settings.fftComputeShader;
            if (m_FFTCompute != null)
            {
                InitFFTKernels();
            }
        }

        private void InitFFTKernels()
        {
            m_KernelBitReverseReal = m_FFTCompute.FindKernel("BitReverseCopyReal");
            m_KernelFFTH = m_FFTCompute.FindKernel("FFTStepHorizontal");
            m_KernelFFTV = m_FFTCompute.FindKernel("FFTStepVertical");
            m_KernelFFTShift = m_FFTCompute.FindKernel("FFTShift");
        }

        public void Dispose()
        {
            if (m_HighlightPreProcessMaterial != null)
            {
                Object.DestroyImmediate(m_HighlightPreProcessMaterial);
            }
        }

        /// <summary>
        /// 生成高光形状的频谱图
        /// </summary>
        public void GenerateKernel()
        {
            if (m_Settings.highlightShapeSource == null)
            {
                Debug.LogWarning("HighlightKernelGenerator: 未设置时域高光形状图");
                return;
            }
            
            if (m_FFTCompute == null)
            {
                Debug.LogWarning("HighlightKernelGenerator: 未设置FFT Compute Shader");
                return;
            }
            
            if (m_HighlightPreProcessMaterial == null)
            {
                Debug.LogWarning("HighlightKernelGenerator: 未找到HighLightPreProcess Shader");
                return;
            }
            
            int size = m_Settings.resolution;
            
            // 创建或更新频谱图RenderTexture
            if (m_Settings.highlightKernelFrequencyRT == null || 
                m_Settings.highlightKernelFrequencyRT.width != size || 
                m_Settings.highlightKernelFrequencyRT.height != size)
            {
                if (m_Settings.highlightKernelFrequencyRT != null)
                {
                    m_Settings.highlightKernelFrequencyRT.Release();
                }
                
                m_Settings.highlightKernelFrequencyRT = new RenderTexture(size, size, 0, RenderTextureFormat.ARGBFloat);
                m_Settings.highlightKernelFrequencyRT.enableRandomWrite = true;
                m_Settings.highlightKernelFrequencyRT.wrapMode = TextureWrapMode.Clamp;
                m_Settings.highlightKernelFrequencyRT.filterMode = FilterMode.Point;
                m_Settings.highlightKernelFrequencyRT.Create();
            }
            
            // 创建临时RenderTexture用于预处理
            RenderTexture preProcessRT = RenderTexture.GetTemporary(size, size, 0, RenderTextureFormat.ARGBFloat);
            preProcessRT.enableRandomWrite = true;
            
            // 创建临时RenderTexture用于FFT中间结果
            RenderTexture tempA = RenderTexture.GetTemporary(size, size, 0, RenderTextureFormat.ARGBFloat);
            tempA.enableRandomWrite = true;
            RenderTexture tempB = RenderTexture.GetTemporary(size, size, 0, RenderTextureFormat.ARGBFloat);
            tempB.enableRandomWrite = true;
            
            try
            {
                // ========================================
                // 步骤1：预处理高光形状图（四角布局转换 + 宽高比校正）
                // ========================================
                m_HighlightPreProcessMaterial.SetVector("_Scale", m_Settings.highlightShapeScale);
                m_HighlightPreProcessMaterial.SetFloat("_AspectRatio", m_Settings.aspectRatio);
                Graphics.Blit(m_Settings.highlightShapeSource, preProcessRT, m_HighlightPreProcessMaterial);
                
                // ========================================
                // 步骤2：FFT变换
                // ========================================
                PerformFFT(preProcessRT, tempA, tempB, size);
                
                // ========================================
                // 步骤3：FFTShift
                // ========================================
                PerformFFTShift(tempA, m_Settings.highlightKernelFrequencyRT, size);
                
                //Debug.Log("HighlightKernelGenerator: 高光形状频谱图已生成");
            }
            finally
            {
                RenderTexture.ReleaseTemporary(preProcessRT);
                RenderTexture.ReleaseTemporary(tempA);
                RenderTexture.ReleaseTemporary(tempB);
            }
        }

        private void PerformFFT(RenderTexture input, RenderTexture tempA, RenderTexture tempB, int size)
        {
            // 位反转重排
            m_FFTCompute.SetTexture(m_KernelBitReverseReal, "SourceTexture", input);
            m_FFTCompute.SetTexture(m_KernelBitReverseReal, "OutputTexture", tempA);
            m_FFTCompute.SetInt("Size", size);
            m_FFTCompute.Dispatch(m_KernelBitReverseReal, (size + 7) / 8, (size + 7) / 8, 1);
            
            RenderTexture currentInput = tempA;
            RenderTexture currentOutput = tempB;
            
            // 蝶形运算
            for (int step = 2; step <= size; step *= 2)
            {
                // 水平方向FFT
                m_FFTCompute.SetTexture(m_KernelFFTH, "InputTexture", currentInput);
                m_FFTCompute.SetTexture(m_KernelFFTH, "OutputTexture", currentOutput);
                m_FFTCompute.SetInt("Size", size);
                m_FFTCompute.SetInt("Step", step);
                m_FFTCompute.Dispatch(m_KernelFFTH, (size + 7) / 8, (size + 7) / 8, 1);
                
                Swap(ref currentInput, ref currentOutput);
                
                // 垂直方向FFT
                m_FFTCompute.SetTexture(m_KernelFFTV, "InputTexture", currentInput);
                m_FFTCompute.SetTexture(m_KernelFFTV, "OutputTexture", currentOutput);
                m_FFTCompute.SetInt("Size", size);
                m_FFTCompute.SetInt("Step", step);
                m_FFTCompute.Dispatch(m_KernelFFTV, (size + 7) / 8, (size + 7) / 8, 1);
                
                Swap(ref currentInput, ref currentOutput);
            }
        }

        private void PerformFFTShift(RenderTexture input, RenderTexture output, int size)
        {
            m_FFTCompute.SetTexture(m_KernelFFTShift, "InputTexture", input);
            m_FFTCompute.SetTexture(m_KernelFFTShift, "OutputTexture", output);
            m_FFTCompute.SetInt("Size", size);
            m_FFTCompute.Dispatch(m_KernelFFTShift, (size + 7) / 8, (size + 7) / 8, 1);
        }

        private void Swap(ref RenderTexture a, ref RenderTexture b)
        {
            RenderTexture temp = a;
            a = b;
            b = temp;
        }
    }
}
