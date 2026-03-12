using UnityEngine;
using UnityEditor;
using UnityEngine.Rendering;

namespace FrequencyDomainHighlight
{
    /// <summary>
    /// 高光卷积核转换器 - Editor窗口工具
    /// 用于时域图片与频域图片之间的相互转换
    /// 支持FFT(时域->频域)和IFFT(频域->时域)操作
    /// </summary>
    public class HighlightKernelConverter : EditorWindow
    {
        /// <summary>
        /// 转换模式枚举
        /// </summary>
        private enum ConvertMode
        {
            TimeToFrequency,    // 时域转频域
            FrequencyToTime,    // 频域转时域
            VerifyRoundTrip,    // 验证FFT正确性(FFT->IFFT)
            MultiplyFrequency   // 频域相乘（卷积）
        }

        private ConvertMode mode = ConvertMode.TimeToFrequency;
        private Texture2D sourceTexture;                               // 源纹理
        private Texture2D secondTexture;                               // 第二个纹理（用于频域相乘）
        private ComputeShader fftCompute;                              // FFT计算着色器
        private string outputFileName = "FrequencyDomainHighlightKernel"; // 输出文件名
        private int outputSize = 256;                                  // 输出尺寸(必须为2的幂次)
        private bool enableReadWrite = true;                           // 是否启用读写
        private bool visualizeMagnitude = true;                        // 是否可视化幅度谱

        [MenuItem("Tools/Frequency Domain/Highlight Kernel Converter")]
        public static void ShowWindow()
        {
            GetWindow<HighlightKernelConverter>("Highlight Kernel Converter");
        }

        private void OnGUI()
        {
            GUILayout.Label("频域/时域转换工具", EditorStyles.boldLabel);
            GUILayout.Space(10);

            mode = (ConvertMode)EditorGUILayout.EnumPopup("转换模式", mode);
            
            // 根据模式显示不同的输入字段
            if (mode == ConvertMode.MultiplyFrequency)
            {
                sourceTexture = (Texture2D)EditorGUILayout.ObjectField("频域图A", sourceTexture, typeof(Texture2D), false);
                secondTexture = (Texture2D)EditorGUILayout.ObjectField("频域图B", secondTexture, typeof(Texture2D), false);
            }
            else
            {
                sourceTexture = (Texture2D)EditorGUILayout.ObjectField("源图片", sourceTexture, typeof(Texture2D), false);
            }
            
            fftCompute = (ComputeShader)EditorGUILayout.ObjectField("FFT Compute Shader", fftCompute, typeof(ComputeShader), false);
            
            GUILayout.Space(10);
            outputSize = EditorGUILayout.IntPopup("输出尺寸", outputSize, new string[] { "64", "128", "256", "512", "1024" }, new int[] { 64, 128, 256, 512, 1024 });
            outputFileName = EditorGUILayout.TextField("输出文件名", outputFileName);
            enableReadWrite = EditorGUILayout.Toggle("启用读写", enableReadWrite);
            
            if (mode == ConvertMode.FrequencyToTime)
            {
                visualizeMagnitude = EditorGUILayout.Toggle("可视化幅度谱", visualizeMagnitude);
            }

            GUILayout.Space(20);

            // 根据模式设置不同的启用条件
            bool canExecute = mode == ConvertMode.MultiplyFrequency
                ? sourceTexture != null && secondTexture != null && fftCompute != null
                : sourceTexture != null && fftCompute != null;
            
            EditorGUI.BeginDisabledGroup(!canExecute);
            
            string buttonText = mode switch
            {
                ConvertMode.TimeToFrequency => "转换为频域图片 (FFT)",
                ConvertMode.FrequencyToTime => "转换为时域图片 (IFFT)",
                ConvertMode.VerifyRoundTrip => "验证FFT正确性 (FFT->IFFT)",
                ConvertMode.MultiplyFrequency => "频域相乘 (卷积)",
                _ => "转换"
            };
            
            if (GUILayout.Button(buttonText, GUILayout.Height(40)))
            {
                switch (mode)
                {
                    case ConvertMode.TimeToFrequency:
                        ConvertToFrequencyDomain();
                        break;
                    case ConvertMode.FrequencyToTime:
                        ConvertToTimeDomain();
                        break;
                    case ConvertMode.VerifyRoundTrip:
                        VerifyRoundTrip();
                        break;
                    case ConvertMode.MultiplyFrequency:
                        MultiplyFrequencyDomains();
                        break;
                }
            }
            EditorGUI.EndDisabledGroup();

            GUILayout.Space(10);
            if (GUILayout.Button("自动查找FFT Compute Shader"))
            {
                FindFFTComputeShader();
            }

            GUILayout.Space(20);
            DrawHelpBox();
        }

        /// <summary>
        /// 绘制帮助信息框
        /// </summary>
        private void DrawHelpBox()
        {
            string helpText = mode switch
            {
                ConvertMode.TimeToFrequency => 
                    "时域 -> 频域 (FFT)\n\n" +
                    "将时域的高光形状图片转换为频域图片。\n" +
                    "白色区域为高光形状。\n\n" +
                    "输出：复数形式存储的频域数据\n" +
                    "- R通道: 实部\n" +
                    "- G通道: 虚部",
                    
                ConvertMode.FrequencyToTime => 
                    "频域 -> 时域 (IFFT)\n\n" +
                    "将频域图片转换回时域图片，用于验证FFT结果。\n\n" +
                    "如果'可视化幅度谱'开启，会输出幅度谱的可视化图片。\n" +
                    "正确的幅度谱应该在中心有最亮的区域（低频），\n" +
                    "边缘较暗（高频）。",
                    
                ConvertMode.VerifyRoundTrip => 
                    "验证FFT正确性\n\n" +
                    "执行: 时域 -> FFT -> IFFT -> 时域\n\n" +
                    "如果FFT实现正确，输出图片应该与原图一致。\n" +
                    "会输出三张图片：\n" +
                    "1. 原始时域图\n" +
                    "2. 频域图（幅度谱可视化）\n" +
                    "3. 还原后的时域图",
                    
                ConvertMode.MultiplyFrequency => 
                    "频域相乘（卷积定理）\n\n" +
                    "根据卷积定理：时域卷积 = 频域相乘\n\n" +
                    "输入两张频域图（复数格式），逐像素进行复数乘法。\n" +
                    "结果可用于IFFT得到时域卷积结果。\n\n" +
                    "应用场景：\n" +
                    "- 高光形状频域 × 屏幕亮度频域 = 自定义高光效果\n\n" +
                    "注意：输入必须是原始频域数据（未shift），\n" +
                    "而非可视化后的幅度谱图片。",
                    
                _ => ""
            };
            
            EditorGUILayout.HelpBox(helpText, MessageType.Info);
        }

        /// <summary>
        /// 自动查找FFT Compute Shader
        /// </summary>
        private void FindFFTComputeShader()
        {
            string[] guids = AssetDatabase.FindAssets("FFT t:ComputeShader");
            if (guids.Length > 0)
            {
                string path = AssetDatabase.GUIDToAssetPath(guids[0]);
                fftCompute = AssetDatabase.LoadAssetAtPath<ComputeShader>(path);
                Debug.Log($"Found FFT Compute Shader at: {path}");
            }
            else
            {
                Debug.LogWarning("FFT Compute Shader not found. Please assign manually.");
            }
        }

        /// <summary>
        /// 转换为频域图片
        /// 执行FFT变换：时域 -> 频域
        /// </summary>
        private void ConvertToFrequencyDomain()
        {
            if (sourceTexture == null || fftCompute == null)
            {
                Debug.LogError("Source texture or FFT compute shader is null!");
                return;
            }

            RenderTexture rtResult = PerformFFT(sourceTexture, outputSize, true);
            
            Texture2D resultTexture = ReadRenderTexture(rtResult, outputSize);
            
            string sourcePath = AssetDatabase.GetAssetPath(sourceTexture);
            string directory = System.IO.Path.GetDirectoryName(sourcePath);
            string outputPath = System.IO.Path.Combine(directory, outputFileName + "_Frequency.asset");
            
            Texture2D savedTexture = SaveTextureAsAsset(resultTexture, outputPath, enableReadWrite);
            
            rtResult.Release();
            DestroyImmediate(resultTexture);
            
            Debug.Log($"Frequency domain texture saved to: {outputPath}");
            EditorGUIUtility.PingObject(savedTexture);
        }

        /// <summary>
        /// 转换为时域图片
        /// 执行IFFT变换：频域 -> 时域
        /// </summary>
        private void ConvertToTimeDomain()
        {
            if (sourceTexture == null || fftCompute == null)
            {
                Debug.LogError("Source texture or FFT compute shader is null!");
                return;
            }

            RenderTexture rtResult = PerformIFFT(sourceTexture, outputSize);
            
            Texture2D resultTexture = ReadRenderTexture(rtResult, outputSize);
            
            if (visualizeMagnitude)
            {
                NormalizeAndVisualize(resultTexture);
            }
            
            string sourcePath = AssetDatabase.GetAssetPath(sourceTexture);
            string directory = System.IO.Path.GetDirectoryName(sourcePath);
            string outputPath = System.IO.Path.Combine(directory, outputFileName + "_TimeDomain.asset");
            
            Texture2D savedTexture = SaveTextureAsAsset(resultTexture, outputPath, enableReadWrite);
            
            rtResult.Release();
            DestroyImmediate(resultTexture);
            
            Debug.Log($"Time domain texture saved to: {outputPath}");
            EditorGUIUtility.PingObject(savedTexture);
        }

        /// <summary>
        /// 验证FFT正确性
        /// 执行完整的FFT->IFFT循环，验证结果是否与原图一致
        /// </summary>
        private void VerifyRoundTrip()
        {
            if (sourceTexture == null || fftCompute == null)
            {
                Debug.LogError("Source texture or FFT compute shader is null!");
                return;
            }

            string sourcePath = AssetDatabase.GetAssetPath(sourceTexture);
            string directory = System.IO.Path.GetDirectoryName(sourcePath);
            
            // 保存原始图片（调整尺寸后）
            Texture2D resizedSource = ResizeTexture(sourceTexture, outputSize, outputSize);
            string originalPath = System.IO.Path.Combine(directory, outputFileName + "_Original.asset");
            SaveTextureAsAsset(resizedSource, originalPath, enableReadWrite);
            
            // 执行FFT
            RenderTexture rtFrequency = PerformFFT(resizedSource, outputSize, true);
            Texture2D frequencyTexture = ReadRenderTexture(rtFrequency, outputSize);
            
            // 创建频域可视化图片（对数缩放的幅度谱）
            Texture2D frequencyVisual = new Texture2D(outputSize, outputSize, TextureFormat.RGBAFloat, false);
            Color[] freqPixels = frequencyTexture.GetPixels();
            float maxFreqMag = 0f;
            
            // 找到最大幅度值
            for (int i = 0; i < freqPixels.Length; i++)
            {
                float mag = Mathf.Sqrt(freqPixels[i].r * freqPixels[i].r + freqPixels[i].g * freqPixels[i].g);
                maxFreqMag = Mathf.Max(maxFreqMag, mag);
            }
            
            // 归一化并应用对数缩放，便于可视化
            for (int i = 0; i < freqPixels.Length; i++)
            {
                float mag = Mathf.Sqrt(freqPixels[i].r * freqPixels[i].r + freqPixels[i].g * freqPixels[i].g);
                float normalizedMag = maxFreqMag > 0 ? mag / maxFreqMag : 0;
                // 对数缩放: log(1 + 9*x) / log(10)，使低频细节更清晰
                normalizedMag = Mathf.Log(1 + normalizedMag * 9) / Mathf.Log(10);
                freqPixels[i] = new Color(normalizedMag, normalizedMag, normalizedMag, 1);
            }
            frequencyVisual.SetPixels(freqPixels);
            frequencyVisual.Apply();
            
            string frequencyPath = System.IO.Path.Combine(directory, outputFileName + "_Frequency.asset");
            SaveTextureAsAsset(frequencyVisual, frequencyPath, enableReadWrite);
            
            // 执行IFFT（使用原始复数数据，而非可视化数据）
            RenderTexture rtTimeDomain = PerformIFFT(frequencyTexture, outputSize);
            Texture2D timeDomainTexture = ReadRenderTexture(rtTimeDomain, outputSize);
            
            string timeDomainPath = System.IO.Path.Combine(directory, outputFileName + "_Restored.asset");
            Texture2D savedTexture = SaveTextureAsAsset(timeDomainTexture, timeDomainPath, enableReadWrite);
            
            // 比较原图和还原后的图片
            float maxDiff = CompareTextures(resizedSource, timeDomainTexture);
            Debug.Log($"FFT Round-trip verification complete. Max difference: {maxDiff:F6}");
            
            if (maxDiff < 0.05f)
            {
                Debug.Log("<color=green>FFT verification PASSED! The round-trip result matches the original.</color>");
            }
            else
            {
                Debug.LogWarning($"FFT verification shows differences. Max diff: {maxDiff:F6}");
            }
            
            // 清理资源
            rtFrequency.Release();
            rtTimeDomain.Release();
            DestroyImmediate(frequencyTexture);
            DestroyImmediate(frequencyVisual);
            DestroyImmediate(timeDomainTexture);
            
            EditorGUIUtility.PingObject(savedTexture);
        }

        /// <summary>
        /// 频域相乘
        /// 根据卷积定理：时域卷积 = 频域相乘
        /// 对两个频域图进行逐像素复数乘法
        /// </summary>
        private void MultiplyFrequencyDomains()
        {
            if (sourceTexture == null || secondTexture == null || fftCompute == null)
            {
                Debug.LogError("Source textures or FFT compute shader is null!");
                return;
            }

            int kernelMultiply = fftCompute.FindKernel("MultiplyComplex");

            // 创建输入和输出纹理
            RenderTexture rtInput = new RenderTexture(outputSize, outputSize, 0, RenderTextureFormat.ARGBFloat);
            rtInput.enableRandomWrite = true;
            rtInput.Create();

            RenderTexture rtOutput = new RenderTexture(outputSize, outputSize, 0, RenderTextureFormat.ARGBFloat);
            rtOutput.enableRandomWrite = true;
            rtOutput.Create();

            // 将频域图A复制到输入纹理
            Graphics.Blit(sourceTexture, rtInput);

            // 设置计算着色器参数
            fftCompute.SetTexture(kernelMultiply, "InputTexture", rtInput);
            fftCompute.SetTexture(kernelMultiply, "KernelTexture", secondTexture);
            fftCompute.SetTexture(kernelMultiply, "OutputTexture", rtOutput);
            fftCompute.SetInt("Size", outputSize);

            // 执行复数乘法
            fftCompute.Dispatch(kernelMultiply, (outputSize + 7) / 8, (outputSize + 7) / 8, 1);

            // 读取结果
            Texture2D resultTexture = ReadRenderTexture(rtOutput, outputSize);

            // 保存结果
            string sourcePath = AssetDatabase.GetAssetPath(sourceTexture);
            string directory = System.IO.Path.GetDirectoryName(sourcePath);
            string outputPath = System.IO.Path.Combine(directory, outputFileName + "_Multiplied.asset");
            
            Texture2D savedTexture = SaveTextureAsAsset(resultTexture, outputPath, enableReadWrite);

            // 创建可视化版本（幅度谱）
            Texture2D visualTexture = new Texture2D(outputSize, outputSize, TextureFormat.RGBAFloat, false);
            Color[] pixels = resultTexture.GetPixels();
            float maxMag = 0f;
            
            for (int i = 0; i < pixels.Length; i++)
            {
                float mag = Mathf.Sqrt(pixels[i].r * pixels[i].r + pixels[i].g * pixels[i].g);
                maxMag = Mathf.Max(maxMag, mag);
            }
            
            for (int i = 0; i < pixels.Length; i++)
            {
                float mag = Mathf.Sqrt(pixels[i].r * pixels[i].r + pixels[i].g * pixels[i].g);
                float normalizedMag = maxMag > 0 ? mag / maxMag : 0;
                normalizedMag = Mathf.Log(1 + normalizedMag * 9) / Mathf.Log(10);
                pixels[i] = new Color(normalizedMag, normalizedMag, normalizedMag, 1);
            }
            visualTexture.SetPixels(pixels);
            visualTexture.Apply();
            
            string visualPath = System.IO.Path.Combine(directory, outputFileName + "_Multiplied_Visual.asset");
            SaveTextureAsAsset(visualTexture, visualPath, enableReadWrite);

            // 清理资源
            rtInput.Release();
            rtOutput.Release();
            DestroyImmediate(resultTexture);
            DestroyImmediate(visualTexture);

            Debug.Log($"Frequency multiplication complete.\n" +
                      $"Result saved to: {outputPath}\n" +
                      $"Visualization saved to: {visualPath}");
            EditorGUIUtility.PingObject(savedTexture);
        }

        /// <summary>
        /// 执行FFT变换
        /// 使用DIT(时间抽取)算法
        /// </summary>
        /// <param name="source">源纹理</param>
        /// <param name="size">纹理尺寸（必须为2的幂次）</param>
        /// <param name="isRealInput">是否为实数输入（true=时域灰度图，false=复数数据）</param>
        /// <returns>FFT结果（复数格式，R=实部，G=虚部）</returns>
        private RenderTexture PerformFFT(Texture source, int size, bool isRealInput)
        {
            int kernelBitReverse = fftCompute.FindKernel(isRealInput ? "BitReverseCopyReal" : "BitReverseCopyComplex");
            int kernelFFTH = fftCompute.FindKernel("FFTStepHorizontal");
            int kernelFFTV = fftCompute.FindKernel("FFTStepVertical");
            int kernelFFTShift = fftCompute.FindKernel("FFTShift");

            // 创建双缓冲用于乒乓操作
            RenderTexture rtInput = new RenderTexture(size, size, 0, RenderTextureFormat.ARGBFloat);
            rtInput.enableRandomWrite = true;
            rtInput.Create();

            RenderTexture rtOutput = new RenderTexture(size, size, 0, RenderTextureFormat.ARGBFloat);
            rtOutput.enableRandomWrite = true;
            rtOutput.Create();

            // 步骤1: 位反转重排（DIT-FFT的第一步）
            fftCompute.SetTexture(kernelBitReverse, "SourceTexture", source);
            fftCompute.SetTexture(kernelBitReverse, "OutputTexture", rtOutput);
            fftCompute.SetInt("Size", size);
            fftCompute.Dispatch(kernelBitReverse, (size + 7) / 8, (size + 7) / 8, 1);

            Swap(ref rtInput, ref rtOutput);

            // 步骤2: 蝶形运算（step从2到size，每次翻倍）
            for (int step = 2; step <= size; step *= 2)
            {
                // 水平方向FFT
                fftCompute.SetTexture(kernelFFTH, "InputTexture", rtInput);
                fftCompute.SetTexture(kernelFFTH, "OutputTexture", rtOutput);
                fftCompute.SetInt("Size", size);
                fftCompute.SetInt("Step", step);
                fftCompute.Dispatch(kernelFFTH, (size + 7) / 8, (size + 7) / 8, 1);

                Swap(ref rtInput, ref rtOutput);

                // 垂直方向FFT
                fftCompute.SetTexture(kernelFFTV, "InputTexture", rtInput);
                fftCompute.SetTexture(kernelFFTV, "OutputTexture", rtOutput);
                fftCompute.SetInt("Size", size);
                fftCompute.SetInt("Step", step);
                fftCompute.Dispatch(kernelFFTV, (size + 7) / 8, (size + 7) / 8, 1);

                Swap(ref rtInput, ref rtOutput);
            }

            // 步骤3: FFTShift - 将低频移到中心，便于可视化
            fftCompute.SetTexture(kernelFFTShift, "InputTexture", rtInput);
            fftCompute.SetTexture(kernelFFTShift, "OutputTexture", rtOutput);
            fftCompute.SetInt("Size", size);
            fftCompute.Dispatch(kernelFFTShift, (size + 7) / 8, (size + 7) / 8, 1);

            Swap(ref rtInput, ref rtOutput);

            rtOutput.Release();
            return rtInput;
        }

        /// <summary>
        /// 执行IFFT变换
        /// 使用DIT(时间抽取)算法
        /// </summary>
        /// <param name="source">源纹理（复数格式频域数据）</param>
        /// <param name="size">纹理尺寸</param>
        /// <returns>IFFT结果（时域实数数据）</returns>
        private RenderTexture PerformIFFT(Texture source, int size)
        {
            int kernelFFTH = fftCompute.FindKernel("IFFTStepHorizontal");
            int kernelFFTV = fftCompute.FindKernel("IFFTStepVertical");
            int kernelBitReverseInput = fftCompute.FindKernel("BitReverseCopyComplex");
            int kernelNormalize = fftCompute.FindKernel("Normalize");
            int kernelFFTShift = fftCompute.FindKernel("FFTShift");

            RenderTexture rtInput = new RenderTexture(size, size, 0, RenderTextureFormat.ARGBFloat);
            rtInput.enableRandomWrite = true;
            rtInput.Create();

            RenderTexture rtOutput = new RenderTexture(size, size, 0, RenderTextureFormat.ARGBFloat);
            rtOutput.enableRandomWrite = true;
            rtOutput.Create();

            Graphics.Blit(source, rtInput);

            // 步骤1: IFFTShift - 还原中心化的频谱
            fftCompute.SetTexture(kernelFFTShift, "InputTexture", rtInput);
            fftCompute.SetTexture(kernelFFTShift, "OutputTexture", rtOutput);
            fftCompute.SetInt("Size", size);
            fftCompute.Dispatch(kernelFFTShift, (size + 7) / 8, (size + 7) / 8, 1);

            Swap(ref rtInput, ref rtOutput);

            // 步骤2: 位反转重排（DIT-IFFT的第一步）
            fftCompute.SetTexture(kernelBitReverseInput, "SourceTexture", rtInput);
            fftCompute.SetTexture(kernelBitReverseInput, "OutputTexture", rtOutput);
            fftCompute.SetInt("Size", size);
            fftCompute.Dispatch(kernelBitReverseInput, (size + 7) / 8, (size + 7) / 8, 1);

            Swap(ref rtInput, ref rtOutput);

            // 步骤3: 蝶形运算（旋转因子使用正角度）
            for (int step = 2; step <= size; step *= 2)
            {
                // 水平方向IFFT
                fftCompute.SetTexture(kernelFFTH, "InputTexture", rtInput);
                fftCompute.SetTexture(kernelFFTH, "OutputTexture", rtOutput);
                fftCompute.SetInt("Size", size);
                fftCompute.SetInt("Step", step);
                fftCompute.Dispatch(kernelFFTH, (size + 7) / 8, (size + 7) / 8, 1);

                Swap(ref rtInput, ref rtOutput);

                // 垂直方向IFFT
                fftCompute.SetTexture(kernelFFTV, "InputTexture", rtInput);
                fftCompute.SetTexture(kernelFFTV, "OutputTexture", rtOutput);
                fftCompute.SetInt("Size", size);
                fftCompute.SetInt("Step", step);
                fftCompute.Dispatch(kernelFFTV, (size + 7) / 8, (size + 7) / 8, 1);

                Swap(ref rtInput, ref rtOutput);
            }

            // 步骤4: 归一化（除以N²）
            fftCompute.SetTexture(kernelNormalize, "InputTexture", rtInput);
            fftCompute.SetTexture(kernelNormalize, "OutputTexture", rtOutput);
            fftCompute.SetInt("Size", size);
            fftCompute.Dispatch(kernelNormalize, (size + 7) / 8, (size + 7) / 8, 1);

            Swap(ref rtInput, ref rtOutput);

            rtOutput.Release();
            return rtInput;
        }

        /// <summary>
        /// 从RenderTexture读取像素数据到Texture2D
        /// </summary>
        private Texture2D ReadRenderTexture(RenderTexture rt, int size)
        {
            Texture2D result = new Texture2D(size, size, TextureFormat.RGBAFloat, false);
            RenderTexture.active = rt;
            result.ReadPixels(new Rect(0, 0, size, size), 0, 0);
            result.Apply();
            RenderTexture.active = null;
            return result;
        }

        /// <summary>
        /// 归一化并可视化复数数据
        /// 将复数转换为幅度谱（灰度图）
        /// </summary>
        private void NormalizeAndVisualize(Texture2D texture)
        {
            int size = texture.width;
            
            Color[] pixels = texture.GetPixels();
            float maxValue = 0f;
            
            // 找到最大幅度值
            for (int i = 0; i < pixels.Length; i++)
            {
                float magnitude = Mathf.Sqrt(pixels[i].r * pixels[i].r + pixels[i].g * pixels[i].g);
                maxValue = Mathf.Max(maxValue, magnitude);
            }
            
            // 归一化
            for (int i = 0; i < pixels.Length; i++)
            {
                float magnitude = Mathf.Sqrt(pixels[i].r * pixels[i].r + pixels[i].g * pixels[i].g);
                
                float normalizedMagnitude = maxValue > 0 ? magnitude / maxValue : 0;
                pixels[i] = new Color(normalizedMagnitude, normalizedMagnitude, normalizedMagnitude, 1);
            }
            
            texture.SetPixels(pixels);
            texture.Apply();
        }

        /// <summary>
        /// 比较两张纹理的差异
        /// 返回最大像素差异值
        /// </summary>
        private float CompareTextures(Texture2D a, Texture2D b)
        {
            Color[] pixelsA = a.GetPixels();
            Color[] pixelsB = b.GetPixels();
            
            float maxDiff = 0f;
            for (int i = 0; i < pixelsA.Length; i++)
            {
                float diff = Mathf.Abs(pixelsA[i].r - pixelsB[i].r);
                maxDiff = Mathf.Max(maxDiff, diff);
            }
            
            return maxDiff;
        }

        /// <summary>
        /// 调整纹理尺寸
        /// </summary>
        private Texture2D ResizeTexture(Texture2D source, int width, int height)
        {
            RenderTexture rt = RenderTexture.GetTemporary(width, height, 0, RenderTextureFormat.ARGBFloat);
            Graphics.Blit(source, rt);
            
            Texture2D result = new Texture2D(width, height, TextureFormat.RGBAFloat, false);
            RenderTexture.active = rt;
            result.ReadPixels(new Rect(0, 0, width, height), 0, 0);
            result.Apply();
            RenderTexture.active = null;
            RenderTexture.ReleaseTemporary(rt);
            
            return result;
        }

        /// <summary>
        /// 交换两个RenderTexture引用（用于乒乓操作）
        /// </summary>
        private void Swap(ref RenderTexture a, ref RenderTexture b)
        {
            RenderTexture temp = a;
            a = b;
            b = temp;
        }

        /// <summary>
        /// 将Texture2D保存为Asset文件
        /// </summary>
        private Texture2D SaveTextureAsAsset(Texture2D texture, string path, bool readWrite)
        {
            // 如果已存在同名资源，先删除
            Texture2D existingTexture = AssetDatabase.LoadAssetAtPath<Texture2D>(path);
            
            if (existingTexture != null)
            {
                DestroyImmediate(existingTexture, true);
            }

            AssetDatabase.CreateAsset(texture, path);

            // 配置纹理导入设置
            TextureImporter importer = AssetImporter.GetAtPath(path) as TextureImporter;
            if (importer != null)
            {
                importer.textureType = TextureImporterType.Default;
                importer.textureShape = TextureImporterShape.Texture2D;
                importer.sRGBTexture = false;  // 线性颜色空间，避免gamma校正
                importer.isReadable = readWrite;
                importer.SaveAndReimport();
            }

            return AssetDatabase.LoadAssetAtPath<Texture2D>(path);
        }
    }
}
