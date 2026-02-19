using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class AtmosScatteringFeature : ScriptableRendererFeature
{
    public RenderPassEvent renderPassEvent = RenderPassEvent.AfterRenderingPostProcessing; // 定义执行的时机
    public Material featureMaterial; // 定义使用的Pass的材质

    AtmosScatteringFeaturePass m_ScriptablePass;

    /// <inheritdoc/>
    public override void Create()
    {
        // 创建一个可编程渲染管线
        m_ScriptablePass = new AtmosScatteringFeaturePass();
        // 将可编程RendererFeature中的值传递给执行者
        m_ScriptablePass.material = featureMaterial;
        //var strack = VolumeManager.instance.stack;
        //volume = strack.GetComponent<自定义的类>();
        //m_ScriptablePass.volume = volume;
        m_ScriptablePass.renderPassEvent = renderPassEvent;

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


    class AtmosScatteringFeaturePass : ScriptableRenderPass // 真正执行绘制命令的自定义Pass脚本
    {
        const string ProfilerTag = "AtmosScatteringFeaturePass"; // 定义一个名字标签 
        RTHandle _cameraColorTgt; // RTHandle是2021年后封装的一个高级RenderTexture管理类
        RTHandle _cameraDepthTgt;
        int shaderID = Shader.PropertyToID("_Temp_RT"); // 定义用于申请临时RT的ID
        public Material material;
        //public 
        private bool start; // 是否启用
        private Light ld; // 主光源
        // Pass开始前调用，提前设置当前Pass要用的信息
        public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
            //base.Configure(cmd, cameraTextureDescriptor);
            ConfigureInput(ScriptableRenderPassInput.Depth | ScriptableRenderPassInput.Normal);
        }

        // 每帧 渲染相机前调用
        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
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
            //if(ld.shadows == LightShadows.None || shadowLight.lightType != LightType.Directional)start = false;
            if(shadowLight.lightType != LightType.Directional)start = false;
            // 没开启立刻返回
            if(!start)return;
            
            
            if (material == null) return;
            // 在这里给材质传入数据，好进行计算
            // 设置太阳方向
            // 设置相机和光照参数
            var camera = renderingData.cameraData.camera;
            material.SetVector("_CameraWorldPos", camera.transform.position);
            material.SetVector("_SunDirection", -ld.transform.forward);
            // 2. 传递逆视投影矩阵（用于Shader中转世界空间）
            Matrix4x4 viewProjMatrix = camera.projectionMatrix * camera.worldToCameraMatrix;
            Matrix4x4 invViewProjMatrix = viewProjMatrix.inverse;
            material.SetMatrix("_InvViewProj", invViewProjMatrix);
        }

        // 具体渲染逻辑代码
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if(material == null) return;
            // 定义Pass的名字，该名字会在FrameDebug的窗口显示对应的Pass
            CommandBuffer cmd = CommandBufferPool.Get(ProfilerTag);
            // 用于临时申请GPU渲染纹理的方法
            // 后续可以根据shaderID获得此临时RT的引用
            using (new ProfilingScope(cmd, new ProfilingSampler("AtmosScatteringFeaturePass")))
            {
                var descriptor = renderingData.cameraData.cameraTargetDescriptor;
                descriptor.msaaSamples = 1;  // 关键：禁用多重采样
                descriptor.depthBufferBits = 0; // 禁用深度
                cmd.GetTemporaryRT(shaderID, descriptor, FilterMode.Bilinear);
                // 获得相机当前的RT
                _cameraColorTgt = renderingData.cameraData.renderer.cameraColorTargetHandle;


                cmd.Blit(_cameraColorTgt.nameID,shaderID,material);
                // 将上一步的RT重新写回到相机
                cmd.Blit(shaderID, _cameraColorTgt.nameID);
                // 将CommandBuffer录制的所有渲染命令提交给GPU执行
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();
                CommandBufferPool.Release(cmd);
            }
            // 截图功能
            
        }
        // 释放资源
        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            if (cmd != null)
            {
                cmd.ReleaseTemporaryRT(shaderID);
                //_cameraColorTgt?.Release();
                //_cameraDepthTgt?.Release();
            }
        }
    }
}