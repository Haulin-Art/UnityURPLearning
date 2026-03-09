using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace FluidFlux.Caustics
{
    /// <summary>
    /// 水下焦散渲染特性
    /// 提供两个主要功能：
    /// 1. 生成带Mipmap的降采样不透明纹理，用于水体散射模糊效果
    /// 2. 全屏焦散效果，根据水面高度和光线角度在水下物体上叠加焦散
    /// </summary>
    public class CausticsRendererFeature : ScriptableRendererFeature
    {
        [System.Serializable]
        public class CausticsSettings
        {
            [Header("不透明纹理设置")]
            [Tooltip("启用带Mipmap的降采样不透明纹理")]
            public bool enableOpaqueTextureMipmap = true;
            [Range(0.25f, 1f), Tooltip("不透明纹理的降采样比例，值越小性能越好但质量越低")]
            public float opaqueTextureScale = 0.5f;
            [Range(1, 8), Tooltip("Mipmap层级数，层级越多模糊效果越平滑")]
            public int mipmapLevels = 4;

            [Header("焦散效果设置")]
            [Tooltip("启用焦散效果")]
            public bool enableCaustics = true;
            [Tooltip("焦散纹理贴图，可使用生成器创建或自定义")]
            public Texture2D causticsTexture;
            [Tooltip("焦散着色器，必须指定为 Hidden/FluidFlux/CausticsEffect")]
            public Shader causticsShader;

            [Header("焦散参数")]
            [Tooltip("水面高度（世界坐标Y值），用于判断水下区域")]
            public float waterSurfaceHeight = 0f;
            [Range(0f, 50f), Tooltip("焦散可见的最大深度，超过此深度焦散逐渐消失")]
            public float maxCausticsDepth = 20f;
            [Range(0f, 5f), Tooltip("焦散亮度强度")]
            public float causticsIntensity = 1f;
            [Range(0.1f, 50f), Tooltip("焦散纹理的世界空间缩放，值越大焦散图案越大")]
            public float causticsScale = 5f;
            [Range(0f, 2f), Tooltip("焦散动画播放速度")]
            public float causticsSpeed = 0.5f;
            [Range(0f, 1f), Tooltip("焦散模糊程度，值越大焦散越柔和")]
            public float causticsBlur = 0.3f;

            [Header("光照设置")]
            [Tooltip("使用场景主光源方向计算焦散投影")]
            public bool useMainLightDirection = true;
            [Tooltip("自定义光源方向（当不使用主光源时生效）")]
            public Vector3 customLightDirection = new Vector3(0.5f, -0.7f, 0.3f);
            [Tooltip("焦散颜色，通常使用浅蓝或青色调")]
            public Color causticsColor = new Color(0.8f, 0.9f, 1f, 1f);

            [Header("渲染设置")]
            [Tooltip("渲染Pass的执行时机，默认在透明物体渲染前")]
            public RenderPassEvent renderPassEvent = RenderPassEvent.BeforeRenderingTransparents;
        }

        public CausticsSettings settings = new CausticsSettings();

        private CausticsOpaquePass m_OpaquePass;
        private CausticsEffectPass m_CausticsPass;
        private Material m_CausticsMaterial;

        public override void Create()
        {
            m_OpaquePass = new CausticsOpaquePass(settings);
            m_OpaquePass.renderPassEvent = RenderPassEvent.AfterRenderingOpaques;

            m_CausticsPass = new CausticsEffectPass(settings);
            m_CausticsPass.renderPassEvent = settings.renderPassEvent;

            if (settings.causticsShader != null)
            {
                m_CausticsMaterial = CoreUtils.CreateEngineMaterial(settings.causticsShader);
            }
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            if (renderingData.cameraData.cameraType == CameraType.Preview)
                return;

            if (settings.enableOpaqueTextureMipmap)
            {
                renderer.EnqueuePass(m_OpaquePass);
            }

            if (settings.enableCaustics && m_CausticsMaterial != null)
            {
                m_CausticsPass.Setup(m_CausticsMaterial, m_OpaquePass.OpaqueTexture);
                renderer.EnqueuePass(m_CausticsPass);
            }
        }

        protected override void Dispose(bool disposing)
        {
            CoreUtils.Destroy(m_CausticsMaterial);
            m_OpaquePass?.Dispose();
            m_CausticsPass?.Dispose();
        }
    }
}
