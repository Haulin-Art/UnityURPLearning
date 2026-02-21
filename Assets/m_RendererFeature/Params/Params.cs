using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class Params : ScriptableRendererFeature
{
    ParamsRenderPass m_ScriptablePass;

    /// <inheritdoc/>
    public override void Create()
    {
        m_ScriptablePass = new ParamsRenderPass();

        // Configures where the render pass should be injected.
        m_ScriptablePass.renderPassEvent = RenderPassEvent.AfterRenderingOpaques;
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(m_ScriptablePass);
    }
    class ParamsRenderPass : ScriptableRenderPass
    {
        RTHandle _cameraColorTgt; 
        RTHandle _cameraDepthTgt;
        public int unsampleInt = 1;
        private readonly List<ShaderTagId> shaderTagIds = new List<ShaderTagId>();
        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            shaderTagIds.Add(new ShaderTagId("SRPDefaultUnlit"));
            shaderTagIds.Add(new ShaderTagId("UniversalForward"));
            shaderTagIds.Add(new ShaderTagId("UniversalForwardOnly"));
            
            
            RenderingUtils.ReAllocateIfNeeded( ref _cameraColorTgt,
                new RenderTextureDescriptor( (int)(Camera.main.pixelWidth / unsampleInt) , 
                (int)Camera.main.pixelHeight / unsampleInt, RenderTextureFormat.ARGBFloat,0),
                FilterMode.Bilinear
            );
            RenderingUtils.ReAllocateIfNeeded( ref _cameraDepthTgt,
                new RenderTextureDescriptor( (int)(Camera.main.pixelWidth / unsampleInt) , 
                (int)Camera.main.pixelHeight / unsampleInt, RenderTextureFormat.RFloat,0),
                FilterMode.Bilinear
            );
            ConfigureTarget(_cameraColorTgt,_cameraDepthTgt);
            ConfigureClear(ClearFlag.All, Color.white);
        }
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get("CreatParams");

            //_cameraColorTgt = renderingData.cameraData.renderer.cameraColorTargetHandle;
            //_cameraDepthTgt = renderingData.cameraData.renderer.cameraDepthTargetHandle;
            // 绘制到RT，灯光空间的深度图
            using (new ProfilingScope(cmd, new ProfilingSampler("LS Depth RT")))
            {
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();
                var drawSetting = CreateDrawingSettings(shaderTagIds, ref renderingData, renderingData.cameraData.defaultOpaqueSortFlags);
                //drawSetting.overrideMaterial = POMat;
                var filterSetting = new FilteringSettings(RenderQueueRange.all);
                context.DrawRenderers(renderingData.cullResults, ref drawSetting, ref filterSetting);
            }
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            
            cmd.SetGlobalTexture("_CameraDepthTexture",_cameraDepthTgt.rt);
            cmd.SetGlobalTexture("_CameraOpaqueTexture",_cameraColorTgt.rt);

            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            CommandBufferPool.Release(cmd);
        }
        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            
        }
    }
}


