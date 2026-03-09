using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace FluidFlux.Caustics
{
    public class CausticsEffectPass : ScriptableRenderPass, System.IDisposable
    {
        private CausticsRendererFeature.CausticsSettings m_Settings;
        private Material m_CausticsMaterial;
        private RTHandle m_OpaqueTexture;
        private RTHandle m_TempTexture;

        private static readonly int s_WaterSurfaceHeightID = Shader.PropertyToID("_WaterSurfaceHeight");
        private static readonly int s_MaxCausticsDepthID = Shader.PropertyToID("_MaxCausticsDepth");
        private static readonly int s_CausticsIntensityID = Shader.PropertyToID("_CausticsIntensity");
        private static readonly int s_CausticsScaleID = Shader.PropertyToID("_CausticsScale");
        private static readonly int s_CausticsSpeedID = Shader.PropertyToID("_CausticsSpeed");
        private static readonly int s_CausticsBlurID = Shader.PropertyToID("_CausticsBlur");
        private static readonly int s_LightDirectionID = Shader.PropertyToID("_CausticsLightDirection");
        private static readonly int s_CausticsColorID = Shader.PropertyToID("_CausticsColor");
        private static readonly int s_CausticsTextureID = Shader.PropertyToID("_CausticsTexture");
        private static readonly int s_TimeID = Shader.PropertyToID("_CausticsTime");

        public CausticsEffectPass(CausticsRendererFeature.CausticsSettings settings)
        {
            m_Settings = settings;
        }

        public void Setup(Material material, RTHandle opaqueTexture)
        {
            m_CausticsMaterial = material;
            m_OpaqueTexture = opaqueTexture;
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            var descriptor = renderingData.cameraData.cameraTargetDescriptor;
            descriptor.depthBufferBits = 0;

            RenderingUtils.ReAllocateIfNeeded(ref m_TempTexture, descriptor, FilterMode.Bilinear, 
                TextureWrapMode.Clamp, name: "_CausticsTempTexture");
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (m_CausticsMaterial == null || m_OpaqueTexture == null)
                return;

            CommandBuffer cmd = CommandBufferPool.Get("Caustics Effect");

            var cameraData = renderingData.cameraData;
            var source = cameraData.renderer.cameraColorTargetHandle;

            UpdateMaterialProperties(ref renderingData);

            Blitter.BlitCameraTexture(cmd, source, m_TempTexture, m_CausticsMaterial, 0);
            Blitter.BlitCameraTexture(cmd, m_TempTexture, source);

            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        private void UpdateMaterialProperties(ref RenderingData renderingData)
        {
            m_CausticsMaterial.SetFloat(s_WaterSurfaceHeightID, m_Settings.waterSurfaceHeight);
            m_CausticsMaterial.SetFloat(s_MaxCausticsDepthID, m_Settings.maxCausticsDepth);
            m_CausticsMaterial.SetFloat(s_CausticsIntensityID, m_Settings.causticsIntensity);
            m_CausticsMaterial.SetFloat(s_CausticsScaleID, m_Settings.causticsScale);
            m_CausticsMaterial.SetFloat(s_CausticsSpeedID, m_Settings.causticsSpeed);
            m_CausticsMaterial.SetFloat(s_CausticsBlurID, m_Settings.causticsBlur);
            m_CausticsMaterial.SetColor(s_CausticsColorID, m_Settings.causticsColor);
            m_CausticsMaterial.SetFloat(s_TimeID, Time.time);

            Vector3 lightDir;
            if (m_Settings.useMainLightDirection)
            {
                Light mainLight = RenderSettings.sun;
                if (mainLight != null && mainLight.isActiveAndEnabled)
                {
                    lightDir = -mainLight.transform.forward;
                }
                else
                {
                    lightDir = new Vector3(0.5f, -0.7f, 0.3f);
                }
            }
            else
            {
                lightDir = m_Settings.customLightDirection.normalized;
            }
            m_CausticsMaterial.SetVector(s_LightDirectionID, lightDir);

            if (m_Settings.causticsTexture != null)
            {
                m_CausticsMaterial.SetTexture(s_CausticsTextureID, m_Settings.causticsTexture);
            }
        }

        public void Dispose()
        {
            m_TempTexture?.Release();
        }
    }
}
