using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class AdvCloudFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public enum debugMode
    {
        None,
        CloudView,
        TindalView
    }

    [System.Serializable]
    public class Settings
    {
        [Header("基础设置")]
        public LayerMask layerMask = -1;
        public string passName = "PlanarReflection Render Pass";
        
        [Space(5)]
        [Header("体积云材质设置")]
        public RenderPassEvent cloud_renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
        public Material AdvanceCloudRFVersionMat;

        [Space(5)]
        [Header("体积云丁达尔光设置")]
        public RenderPassEvent tindal_renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
        public bool enableCloudTindal = false;
        public Material CloudTindalMat;

        [Space(5)]
        [Header("调试用")]
        public debugMode DebugMode;
    }

    public Settings settings = new Settings();
    private AdvCloudPass m_Pass; // 体积云屏幕纹理Pass

    private CloudTindalPass m_Tindal_Pass; // 体积云丁达尔的屏幕纹理Pass

    public override void Create()
    {
        m_Pass = new AdvCloudPass(settings);
        m_Tindal_Pass = new CloudTindalPass(settings);
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(m_Pass);

        if (settings.enableCloudTindal)
        {
            renderer.EnqueuePass(m_Tindal_Pass);
        }
    }


    // 体积云屏幕纹理Pass
    class AdvCloudPass : ScriptableRenderPass
    {
        private Settings m_Settings;
        private FilteringSettings m_FilteringSettings;
        private readonly List<ShaderTagId> m_ShaderTagIds = new List<ShaderTagId>();

        private RTHandle _AtmosRFCloudTex;

        public AdvCloudPass(Settings settings)
        {
            m_Settings = settings;
            renderPassEvent = settings.cloud_renderPassEvent;
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


            RenderTargetIdentifier cameraColorTarget = renderingData.cameraData.renderer.cameraColorTargetHandle;
            //RenderTargetIdentifier cameraDepthTarget = renderingData.cameraData.renderer.cameraDepthTargetHandle;

            // 计算体积云的屏幕纹理，其中a通道为云层透射率
            cmd.Blit(null,_AtmosRFCloudTex,m_Settings.AdvanceCloudRFVersionMat);
            cmd.SetGlobalTexture("_AtmosRFCloudTex",_AtmosRFCloudTex);

            if (m_Settings.DebugMode == debugMode.CloudView)
            {
                cmd.Blit(_AtmosRFCloudTex,cameraColorTarget);
            }

            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }
    }

    // 云层丁达尔光的Pass
    class CloudTindalPass : ScriptableRenderPass
    {
        private Settings m_Settings;
        private FilteringSettings m_FilteringSettings;
        private readonly List<ShaderTagId> m_ShaderTagIds = new List<ShaderTagId>();

        private RTHandle _TindalCloudTex;
        public CloudTindalPass(Settings settings)
        {
            m_Settings = settings;
            renderPassEvent = settings.tindal_renderPassEvent;
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
            RenderingUtils.ReAllocateIfNeeded(ref _TindalCloudTex,new RenderTextureDescriptor(width, height, RenderTextureFormat.ARGBFloat, 0),FilterMode.Bilinear);

            // 在这里给材质传入数据，好进行计算
            //material.SetColor("",);
            Camera camera = renderingData.cameraData.camera;
            // 1. 传递ro：相机世界空间位置
            m_Settings.CloudTindalMat.SetVector("_CameraWorldPos", camera.transform.position);
            // 2. 传递逆视投影矩阵（用于Shader中转世界空间）
            Matrix4x4 viewProjMatrix = camera.projectionMatrix * camera.worldToCameraMatrix;
            Matrix4x4 invViewProjMatrix = viewProjMatrix.inverse;
            m_Settings.CloudTindalMat.SetMatrix("_InvViewProj", invViewProjMatrix);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (renderingData.cameraData.camera.cameraType == CameraType.Preview)
                return;
            if (m_Settings.CloudTindalMat == null) return;

            CommandBuffer cmd = CommandBufferPool.Get(m_Settings.passName);

            RenderTargetIdentifier cameraColorTarget = renderingData.cameraData.renderer.cameraColorTargetHandle;
            //RenderTargetIdentifier cameraDepthTarget = renderingData.cameraData.renderer.cameraDepthTargetHandle;

            // 计算体积云的屏幕纹理，其中a通道为云层透射率
            cmd.Blit(cameraColorTarget,_TindalCloudTex,m_Settings.CloudTindalMat);
            //cmd.SetGlobalTexture("_AtmosRFCloudTex",_AtmosRFCloudTex);

            if (m_Settings.DebugMode == debugMode.TindalView)
            {
                cmd.Blit(_TindalCloudTex,cameraColorTarget);
            }

            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

    }

}