using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class Atmosphere : ScriptableRendererFeature
{
    class AtmospherePass : ScriptableRenderPass // 真正执行绘制命令的自定义Pass脚本
    {
        const string ProfilerTag = "AtmospherePass"; // 定义一个名字标签 
        RTHandle _cameraColorTgt; // RTHandle是2021年后封装的一个高级RenderTexture管理类
        int shaderID = Shader.PropertyToID("_Temp_RT"); // 定义用于申请临时RT的ID
        public Material material;

        // Pass开始前调用，提前设置当前Pass要用的信息kkk
        public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
            //base.Configure(cmd, cameraTextureDescriptor);
            ConfigureInput(ScriptableRenderPassInput.Depth | ScriptableRenderPassInput.Normal);
        }
        
        // 每帧 渲染相机前调用
        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            if (material == null) return;
            // 在这里给材质传入数据，好进行计算
            //material.SetColor("",);
            Camera camera = renderingData.cameraData.camera;
            // 1. 传递ro：相机世界空间位置
            material.SetVector("_CameraWorldPos", camera.transform.position);
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
            cmd.GetTemporaryRT(shaderID, Camera.main.pixelWidth, Camera.main.pixelHeight, 0, FilterMode.Bilinear, RenderTextureFormat.Default);
            // 获得相机当前的RT
            _cameraColorTgt = renderingData.cameraData.renderer.cameraColorTargetHandle;
            // 将相机获取到的RT图，通过material材质的计算，输出到临时RT（Blit方法里通过ID获得RT的引用）
            cmd.Blit(_cameraColorTgt.nameID,shaderID,material);
            // 将上一步的RT重新写回到相机
            cmd.Blit(shaderID, _cameraColorTgt.nameID);
            // 将CommandBuffer录制的所有渲染命令提交给GPU执行
            context.ExecuteCommandBuffer(cmd);
        }
        // 释放资源
        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            if (cmd != null)
            {
                cmd.ReleaseTemporaryRT(shaderID);
                //cmd.Clear();
            }
        }
    }
    
    public RenderPassEvent renderPassEvent = RenderPassEvent.AfterRenderingPostProcessing; // 定义执行的时机
    public Material featureMaterial; // 定义使用的Pass的材质

    AtmospherePass m_ScriptablePass;

    public override void Create()
    {
        // 创建一个可编程渲染管线
        m_ScriptablePass = new AtmospherePass();
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
}