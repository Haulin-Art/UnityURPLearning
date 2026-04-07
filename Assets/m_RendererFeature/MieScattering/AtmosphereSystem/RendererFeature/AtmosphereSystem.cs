using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class AtmosphereSystem : ScriptableRendererFeature
{
    public RenderPassEvent renderPassEvent = RenderPassEvent.AfterRenderingPostProcessing; // 定义执行的时机
    public Material featureMaterial; // 定义使用的Pass的材质
    public ComputeShader computeShader; // 双边滤波Compute Shader引用
    public ComputeShader atmosComputeShader; // 大气散射Compute Shader引用
    public RenderTexture atmosOutput; // 输出纹理引用
    public RenderTexture cloudDataOutput; // 云数据输出纹理引用
    AtmosphereSystemPass m_ScriptablePass;

    /// <inheritdoc/>
    public override void Create()
    {
        // 创建一个可编程渲染管线
        m_ScriptablePass = new AtmosphereSystemPass();
        // 将可编程RendererFeature中的值传递给执行者
        m_ScriptablePass.material = featureMaterial;
        m_ScriptablePass.computeShader = computeShader;
        m_ScriptablePass.atmosComputeShader = atmosComputeShader;
        m_ScriptablePass.renderPassEvent = renderPassEvent;
        m_ScriptablePass.atmosOutput = atmosOutput;
        m_ScriptablePass.cloudDataOutput = cloudDataOutput;

    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        // 判空后再入队，避免空状态传递
        if (m_ScriptablePass != null && featureMaterial != null)
        {
            // 将绘制命令每帧添加进渲染队列
            renderer.EnqueuePass(m_ScriptablePass);
        }
    }


    class AtmosphereSystemPass : ScriptableRenderPass // 真正执行绘制命令的自定义Pass脚本
    {
        const string ProfilerTag = "AtmosphereSystemPass"; // 定义一个名字标签 
        public RenderTexture atmosOutput; // 输出纹理引用
        public RenderTexture cloudDataOutput; // 云数据输出纹理引用
        RTHandle _cameraColorTgt; // RTHandle是2021年后封装的一个高级RenderTexture管理类
        RTHandle _cameraDepthTgt;
        int shaderID = Shader.PropertyToID("_Temp_RT"); // 定义用于申请临时RT的ID
        int filteringID = Shader.PropertyToID("_Filtering"); // 定义用于申请临时RT的ID
        int atmosID = Shader.PropertyToID("_AtmosRT"); // 大气散射RT的ID
        public Material material;
        public ComputeShader computeShader; // 双边滤波Compute Shader引用
        public ComputeShader atmosComputeShader; // 大气散射Compute Shader引用
        //public 
        private bool start; // 是否启用
        private Light ld; // 主光源
        
        // Volume参数缓存
        private AtmosphereVolume atmosphereVolume;
        
        // Pass开始前调用，提前设置当前Pass要用的信息
        public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
            //base.Configure(cmd, cameraTextureDescriptor);
            ConfigureInput(ScriptableRenderPassInput.Depth | ScriptableRenderPassInput.Normal);
        }

        // 从Volume中获取参数
        private void GetVolumeParameters()
        {
            // 从VolumeManager获取当前的AtmosphereVolume
            var stack = VolumeManager.instance.stack;
            atmosphereVolume = stack.GetComponent<AtmosphereVolume>();
        }

        // 每帧 渲染相机前调用
        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            // 获取Volume参数
            GetVolumeParameters();
            
            // 查看场景当中有没有主光源，以及获取主光源
            start = true;
            if (!renderingData.shadowData.supportsMainLightShadows)start = false;
            
            // 获取主光源在可见光源中的索引
            int shadowLightIndex = renderingData.lightData.mainLightIndex;
            // 索引为-1说明没有找到主光源，设置为不启用
            if(shadowLightIndex==-1)start = false;
            // 根据索引从见可见光源列表当中获取主光源的可见数据
            VisibleLight shadowLight = renderingData.lightData.visibleLights[shadowLightIndex];
            ld = shadowLight.light; // 从可见光源数据当中获取Unity的Light组件引用
            // 检查灯光设置，如果灯光组件没有开启阴影，或者灯光数据的灯光类型不是平行光
            if(shadowLight.lightType != LightType.Directional)start = false;
            // 没开启立刻返回
            if(!start)return;
            
            
            if (material == null || computeShader == null) return;
            
            // 设置相机和光照参数
            var camera = renderingData.cameraData.camera;
            material.SetVector("_CameraWorldPos", camera.transform.position);
            material.SetVector("_SunDirection", -ld.transform.forward);
            // 传递逆视投影矩阵（用于Shader中转世界空间）
            Matrix4x4 viewProjMatrix = camera.projectionMatrix * camera.worldToCameraMatrix;
            Matrix4x4 invViewProjMatrix = viewProjMatrix.inverse;
            material.SetMatrix("_InvViewProj", invViewProjMatrix);
            
            // 如果存在Volume参数，则传递给材质
            if (atmosphereVolume != null && false)
            {
                // 大气参数
                material.SetFloat("_TotalScale", atmosphereVolume.totalScale.value);
                material.SetFloat("_PlanetRadius", atmosphereVolume.planetRadius.value);
                material.SetFloat("_Altitude", atmosphereVolume.altitude.value);
                
                // 太阳参数
                material.SetFloat("_SunBrightness", atmosphereVolume.sunBrightness.value);
                
                // 采样参数
                material.SetInt("_NumSamples", atmosphereVolume.numSamples.value);
                material.SetInt("_NumSamplesLight", atmosphereVolume.numSamplesLight.value);
                
                // 环境参数
                material.SetFloat("_PanoramicRotation", atmosphereVolume.panoramicRotation.value);
                
                // 云参数
                material.SetFloat("_CloudBaseHeight", atmosphereVolume.cloudBaseHeight.value);
                material.SetFloat("_CloudThickness", atmosphereVolume.cloudThickness.value);
                material.SetFloat("_CloudAlpha", atmosphereVolume.cloudAlpha.value);
                material.SetFloat("_CloudScatterCoeff", atmosphereVolume.cloudScatterCoeff.value);
                material.SetFloat("_CloudExtinctionCoeff", atmosphereVolume.cloudExtinctionCoeff.value);
                material.SetFloat("_CloudPhaseG", atmosphereVolume.cloudPhaseG.value);
                material.SetFloat("_CloudDensityThreshold", atmosphereVolume.cloudDensityThreshold.value);
                material.SetFloat("_CloudEdgeSharpness", atmosphereVolume.cloudEdgeSharpness.value);
                material.SetFloat("_CloudDensityMultiplier", atmosphereVolume.cloudDensityMultiplier.value);
                
                // 纹理参数
                if (atmosphereVolume.cloudTex.value != null)
                    material.SetTexture("_CloudTex", atmosphereVolume.cloudTex.value);
                if (atmosphereVolume.blueNoise.value != null)
                    material.SetTexture("_BlueNoise", atmosphereVolume.blueNoise.value);
                if (atmosphereVolume.envPanoramic.value != null)
                    material.SetTexture("_EnvPanoramic", atmosphereVolume.envPanoramic.value);
                
                // ==================== 大气散射参数 ====================
                // 大气层参数
                material.SetFloat("_AtmosphereHeight", atmosphereVolume.atmosphereHeight.value);
                material.SetFloat("_RayleighScaleHeight", atmosphereVolume.rayleighScaleHeight.value);
                material.SetFloat("_MieScaleHeight", atmosphereVolume.mieScaleHeight.value);
                material.SetFloat("_OzoneScaleHeight", atmosphereVolume.ozoneScaleHeight.value);
                material.SetFloat("_OzoneCenterHeight", atmosphereVolume.ozoneCenterHeight.value);
                material.SetFloat("_AtmosIntensity", atmosphereVolume.atmosIntensity.value);
                
                // 散射系数
                material.SetFloat("_RayleighScatterScale", atmosphereVolume.rayleighScatterScale.value);
                material.SetFloat("_MieScatterScale", atmosphereVolume.mieScatterScale.value);
                material.SetFloat("_MieExtinctionCoeff", atmosphereVolume.mieExtinctionCoeff.value);
                
                // 相位函数参数
                material.SetFloat("_AtmosMieG", atmosphereVolume.atmosMieG.value);
                material.SetFloat("_SunMieG", atmosphereVolume.sunMieG.value);
                material.SetFloat("_SunMieIntensity", atmosphereVolume.sunMieIntensity.value);
                
                // 太阳圆盘参数
                material.SetFloat("_SunSize", atmosphereVolume.sunSize.value);
                material.SetColor("_SunColor", atmosphereVolume.sunColor.value);
            }
        }

        // 具体渲染逻辑代码
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if(material == null) return;
            // 定义Pass的名字，该名字会在FrameDebug的窗口显示对应的Pass
            CommandBuffer cmd = CommandBufferPool.Get(ProfilerTag);
            // 用于临时申请GPU渲染纹理的方法
            // 后续可以根据shaderID获得此临时RT的引用
            using (new ProfilingScope(cmd, new ProfilingSampler("AtmosphereSystemPass")))
            {
                var descriptor = renderingData.cameraData.cameraTargetDescriptor;
                descriptor.msaaSamples = 1;  // 关键：禁用多重采样
                descriptor.depthBufferBits = 0; // 禁用深度
                descriptor.enableRandomWrite = true;
                descriptor.colorFormat = RenderTextureFormat.RGFloat;
                descriptor.width = renderingData.cameraData.cameraTargetDescriptor.width/2;
                descriptor.height = renderingData.cameraData.cameraTargetDescriptor.height/2;
                
                // 创建临时RT并启用UAV标志
                cmd.GetTemporaryRT(shaderID, descriptor, FilterMode.Bilinear );
                cmd.GetTemporaryRT(filteringID, descriptor, FilterMode.Bilinear);
                
                // 创建大气散射RT（全景图分辨率）
                var atmosDescriptor = new RenderTextureDescriptor(512, 512, RenderTextureFormat.ARGBHalf, 0);
                atmosDescriptor.enableRandomWrite = true;
                cmd.GetTemporaryRT(atmosID, atmosDescriptor, FilterMode.Bilinear);
                
                // 获得相机当前的RT
                _cameraColorTgt = renderingData.cameraData.renderer.cameraColorTargetHandle;
                
                // =========================== 大气散射Compute Shader区域 ===========================
                /*
                if (atmosComputeShader != null && atmosphereVolume != null)
                {
                    // 设置大气散射Compute Shader参数
                    int atmosKernelIndex = atmosComputeShader.FindKernel("CSMain");
                    
                    // 设置输出纹理
                    cmd.SetComputeTextureParam(atmosComputeShader, atmosKernelIndex, "_OutputTex", atmosID);
                    
                    // 大气参数
                    cmd.SetComputeFloatParam(atmosComputeShader, "_TotalScale", atmosphereVolume.totalScale.value);
                    cmd.SetComputeFloatParam(atmosComputeShader, "_PlanetRadius", atmosphereVolume.planetRadius.value);
                    cmd.SetComputeFloatParam(atmosComputeShader, "_AtmosphereHeight", atmosphereVolume.atmosphereHeight.value);
                    cmd.SetComputeFloatParam(atmosComputeShader, "_Altitude", atmosphereVolume.altitude.value);
                    
                    // 大气密度参数
                    cmd.SetComputeFloatParam(atmosComputeShader, "_RayleighScaleHeight", atmosphereVolume.rayleighScaleHeight.value);
                    cmd.SetComputeFloatParam(atmosComputeShader, "_MieScaleHeight", atmosphereVolume.mieScaleHeight.value);
                    cmd.SetComputeFloatParam(atmosComputeShader, "_OzoneScaleHeight", atmosphereVolume.ozoneScaleHeight.value);
                    cmd.SetComputeFloatParam(atmosComputeShader, "_OzoneCenterHeight", atmosphereVolume.ozoneCenterHeight.value);
                    cmd.SetComputeFloatParam(atmosComputeShader, "_AtmosIntensity", atmosphereVolume.atmosIntensity.value);
                    
                    // 散射系数
                    cmd.SetComputeVectorParam(atmosComputeShader, "_ScatterScale", new Vector2(atmosphereVolume.rayleighScatterScale.value, atmosphereVolume.mieScatterScale.value));
                    cmd.SetComputeFloatParam(atmosComputeShader, "_MieExtinction", atmosphereVolume.mieExtinctionCoeff.value);
                    
                    // 相位函数参数
                    cmd.SetComputeFloatParam(atmosComputeShader, "_MieG", atmosphereVolume.atmosMieG.value);
                    cmd.SetComputeFloatParam(atmosComputeShader, "_SunMieG", atmosphereVolume.sunMieG.value);
                    cmd.SetComputeFloatParam(atmosComputeShader, "_SunMieIntensity", atmosphereVolume.sunMieIntensity.value);
                    
                    // 太阳参数
                    cmd.SetComputeFloatParam(atmosComputeShader, "_SunSize", atmosphereVolume.sunSize.value);
                    cmd.SetComputeVectorParam(atmosComputeShader, "_SunColor", new Vector3(atmosphereVolume.sunColor.value.r, atmosphereVolume.sunColor.value.g, atmosphereVolume.sunColor.value.b));
                    cmd.SetComputeFloatParam(atmosComputeShader, "_SunBrightness", atmosphereVolume.sunBrightness.value);
                    cmd.SetComputeVectorParam(atmosComputeShader, "_SunDirection", ld != null ? -ld.transform.forward : Vector3.up);
                    
                    // 采样参数
                    cmd.SetComputeIntParam(atmosComputeShader, "_NumSamples", atmosphereVolume.numSamples.value);
                    cmd.SetComputeIntParam(atmosComputeShader, "_NumSamplesLight", atmosphereVolume.numSamplesLight.value);
                    
                    // 纹理尺寸
                    cmd.SetComputeIntParam(atmosComputeShader, "_TexWidth", 2048);
                    cmd.SetComputeIntParam(atmosComputeShader, "_TexHeight", 1024);
                    
                    // 调度大气散射Compute Shader
                    int atmosThreadGroupsX = Mathf.CeilToInt(2048 / 8.0f);
                    int atmosThreadGroupsY = Mathf.CeilToInt(1024 / 8.0f);
                    cmd.DispatchCompute(atmosComputeShader, atmosKernelIndex, atmosThreadGroupsX, atmosThreadGroupsY, 1);
                }
                */
                // 渲染体积云
                cmd.Blit(_cameraColorTgt.nameID, shaderID, material);
                
                // =========================== 双边滤波区域 ================================================
                // 设置Compute Shader参数
                int kernelIndex = computeShader.FindKernel("CSMain");
                
                // 设置输入输出纹理
                cmd.SetComputeTextureParam(computeShader, kernelIndex, "_MainTex", shaderID);
                cmd.SetComputeTextureParam(computeShader, kernelIndex, "_OutputTex", filteringID);
                
                // 从Volume中读取滤波参数，如果没有Volume则使用默认值
                float filterRadius = atmosphereVolume != null ? atmosphereVolume.filterRadius.value : 5.0f;
                float sigmaSpace = atmosphereVolume != null ? atmosphereVolume.sigmaSpace.value : 5.0f;
                float sigmaRange = atmosphereVolume != null ? atmosphereVolume.sigmaRange.value : 0.7f;
                
                // 设置滤波参数
                cmd.SetComputeFloatParam(computeShader, "_Radius", filterRadius);
                cmd.SetComputeFloatParam(computeShader, "_SigmaSpace", sigmaSpace);
                cmd.SetComputeFloatParam(computeShader, "_SigmaRange", sigmaRange);
                
                // 设置纹理尺寸
                cmd.SetComputeVectorParam(computeShader, "_MainTex_TexelSize", new Vector4(1.0f / descriptor.width, 1.0f / descriptor.height, descriptor.width, descriptor.height));
                
                // 计算线程组数量
                int threadGroupsX = Mathf.CeilToInt(descriptor.width / 8.0f);
                int threadGroupsY = Mathf.CeilToInt(descriptor.height / 8.0f);
                
                // 调度Compute Shader
                cmd.DispatchCompute(computeShader, kernelIndex, threadGroupsX, threadGroupsY, 1);



                // ==================================== 测试输出 ================================================
                //cmd.SetGlobalTexture("_CloudData",filteringID);
                //cmd.Blit(filteringID, _cameraColorTgt.nameID);
                //cmd.Blit(filteringID, _cameraColorTgt.nameID);
                //cmd.Blit(atmosID, _cameraColorTgt.nameID);
                // 将CommandBuffer录制的所有渲染命令提交给GPU执行
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();

                if (cloudDataOutput != null)
                {
                    cmd.Blit(filteringID, cloudDataOutput);
                }
                if (atmosOutput != null)
                {
                    cmd.Blit(atmosID, atmosOutput);
                }
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();
            }
            
            // 释放CommandBuffer
            CommandBufferPool.Release(cmd);
            // 截图功能
            
        }
        // 释放资源
        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            if (cmd != null)
            {
                cmd.ReleaseTemporaryRT(shaderID);
                cmd.ReleaseTemporaryRT(filteringID);
                cmd.ReleaseTemporaryRT(atmosID);
                //_cameraColorTgt?.Release();
                //_cameraDepthTgt?.Release();
            }
        }
    }
}