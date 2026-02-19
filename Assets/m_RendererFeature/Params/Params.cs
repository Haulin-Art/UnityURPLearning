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
        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
        }
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get("CreatParams");

            _cameraColorTgt = renderingData.cameraData.renderer.cameraColorTargetHandle;
            _cameraDepthTgt = renderingData.cameraData.renderer.cameraDepthTargetHandle;
            
            
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


