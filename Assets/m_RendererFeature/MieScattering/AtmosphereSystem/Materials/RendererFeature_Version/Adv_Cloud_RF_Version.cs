using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class AdvCloudFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class Settings
    {
        public LayerMask layerMask = -1;
        public RenderPassEvent renderPassEvent = RenderPassEvent.AfterRenderingOpaques;
        public string passName = "PlanarReflection Render Pass";
        public Material AdvanceCloudRFVersionMat;
    }

    public Settings settings = new Settings();
    private AdvCloudPass m_Pass;

    public override void Create()
    {
        m_Pass = new AdvCloudPass(settings);
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(m_Pass);
    }

    class AdvCloudPass : ScriptableRenderPass
    {
        private Settings m_Settings;
        private FilteringSettings m_FilteringSettings;
        private readonly List<ShaderTagId> m_ShaderTagIds = new List<ShaderTagId>();

        private RTHandle _AtmosRFCloudTex;

        public AdvCloudPass(Settings settings)
        {
            m_Settings = settings;
            renderPassEvent = settings.renderPassEvent;
            m_FilteringSettings = new FilteringSettings(RenderQueueRange.opaque, settings.layerMask);

            // 添加默认的URP着色器标签
            m_ShaderTagIds.Add(new ShaderTagId("UniversalForward"));
            m_ShaderTagIds.Add(new ShaderTagId("UniversalForwardOnly"));
            m_ShaderTagIds.Add(new ShaderTagId("SRPDefaultUnlit"));
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {

            if (m_Settings.AdvanceCloudRFVersionMat == null) return;

            // 可选：设置RTHandle
            int width = renderingData.cameraData.camera.pixelWidth/2;
            int height = renderingData.cameraData.camera.pixelHeight/2;
            RenderingUtils.ReAllocateIfNeeded(ref _AtmosRFCloudTex,new RenderTextureDescriptor(width, height, RenderTextureFormat.ARGBFloat, 0),FilterMode.Bilinear);

            // 在这里给材质传入数据，好进行计算
            //material.SetColor("",);
            Camera camera = renderingData.cameraData.camera;
            // 1. 传递ro：相机世界空间位置
            m_Settings.AdvanceCloudRFVersionMat.SetVector("_CameraWorldPos", camera.transform.position);
            // 2. 传递逆视投影矩阵（用于Shader中转世界空间）
            Matrix4x4 viewProjMatrix = camera.projectionMatrix * camera.worldToCameraMatrix;
            Matrix4x4 invViewProjMatrix = viewProjMatrix.inverse;
            m_Settings.AdvanceCloudRFVersionMat.SetMatrix("_InvViewProj", invViewProjMatrix);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (renderingData.cameraData.camera.cameraType == CameraType.Preview)
                return;
            if (m_Settings.AdvanceCloudRFVersionMat == null) return;

            CommandBuffer cmd = CommandBufferPool.Get(m_Settings.passName);

            // 可选：当前摄像机的画面
            RenderTargetIdentifier cameraColorTarget = renderingData.cameraData.renderer.cameraColorTargetHandle;
            //RenderTargetIdentifier cameraDepthTarget = renderingData.cameraData.renderer.cameraDepthTargetHandle;

            cmd.Blit(null,_AtmosRFCloudTex,m_Settings.AdvanceCloudRFVersionMat);
            //cmd.Blit(_AtmosRFCloudTex,cameraColorTarget);

            cmd.SetGlobalTexture("_AtmosRFCloudTex",_AtmosRFCloudTex);

            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }
    }
}