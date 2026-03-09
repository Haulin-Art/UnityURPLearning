using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace FluidFlux.Caustics
{
    public class CausticsOpaquePass : ScriptableRenderPass, System.IDisposable
    {
        private CausticsRendererFeature.CausticsSettings m_Settings;
        private RenderTextureDescriptor m_OpaqueDescriptor;
        private RTHandle m_OpaqueTexture;
        private int m_MipmapLevels;

        public RTHandle OpaqueTexture => m_OpaqueTexture;

        public CausticsOpaquePass(CausticsRendererFeature.CausticsSettings settings)
        {
            m_Settings = settings;
            m_MipmapLevels = settings.mipmapLevels;
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            var cameraData = renderingData.cameraData;
            var descriptor = cameraData.cameraTargetDescriptor;

            descriptor.width = Mathf.RoundToInt(descriptor.width * m_Settings.opaqueTextureScale);
            descriptor.height = Mathf.RoundToInt(descriptor.height * m_Settings.opaqueTextureScale);
            descriptor.colorFormat = RenderTextureFormat.ARGBHalf;
            descriptor.depthBufferBits = 0;
            descriptor.useMipMap = true;
            descriptor.autoGenerateMips = false;
            descriptor.mipCount = m_MipmapLevels;

            m_OpaqueDescriptor = descriptor;

            RenderingUtils.ReAllocateIfNeeded(ref m_OpaqueTexture, descriptor, FilterMode.Bilinear, 
                TextureWrapMode.Clamp, name: "_CausticsOpaqueTexture");
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (m_OpaqueTexture == null)
                return;

            CommandBuffer cmd = CommandBufferPool.Get("Caustics Opaque Texture");

            var cameraData = renderingData.cameraData;
            var source = cameraData.renderer.cameraColorTargetHandle;

            Blitter.BlitCameraTexture(cmd, source, m_OpaqueTexture);

            GenerateMipmaps(cmd, m_OpaqueTexture);

            cmd.SetGlobalTexture("_CausticsOpaqueTexture", m_OpaqueTexture);
            cmd.SetGlobalVector("_CausticsOpaqueTexture_TexelSize", 
                new Vector4(1.0f / m_OpaqueDescriptor.width, 1.0f / m_OpaqueDescriptor.height,
                    m_OpaqueDescriptor.width, m_OpaqueDescriptor.height));

            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        private void GenerateMipmaps(CommandBuffer cmd, RTHandle texture)
        {
            for (int i = 1; i < m_MipmapLevels; i++)
            {
                cmd.CopyTexture(texture, i - 1, 0, texture, i, 0);
            }
        }

        public void Dispose()
        {
            m_OpaqueTexture?.Release();
        }

        public override void OnCameraCleanup(CommandBuffer cmd)
        {
        }
    }
}
