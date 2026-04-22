using UnityEngine;
using UnityEngine.Rendering.Universal;

public class PlanarReflectionRendererFeature : ScriptableRendererFeature
{
    // 序列化字段，用于在 Inspector 中配置
    [System.Serializable]
    public class Settings
    {
        public string profilerTag = "Planar Reflection";
        public LayerMask reflectionLayerMask = -1; // 默认渲染所有层
        public int reflectionTextureResolution = 512; // 反射纹理分辨率
        public float updateInterval = 1.0f; // 反射更新间隔（秒）
        public float clipPlaneOffset = 0.07f; // 裁剪平面偏移
        public bool debugView = false; // 调试视图开关
        public float planeHeight = 0f; // 反射平面高度（水面高度）
    }

    public Settings settings = new Settings();
    private PlanarReflectionPass reflectionPass;

    // 全局反射纹理名称
    public static readonly string ReflectionTextureName = "_PlanarReflectionTexture";

    /// <summary>
    /// 创建渲染通道
    /// </summary>
    public override void Create()
    {
        // 创建反射渲染通道
        reflectionPass = new PlanarReflectionPass(
            settings.profilerTag,
            settings.reflectionLayerMask,
            settings.reflectionTextureResolution,
            settings.updateInterval,
            settings.clipPlaneOffset,
            settings.debugView,
            settings.planeHeight
        );

        // 设置渲染通道的事件
        reflectionPass.renderPassEvent = RenderPassEvent.BeforeRenderingOpaques;

        Debug.Log("PlanarReflectionRendererFeature created");
    }

    /// <summary>
    /// 添加渲染通道到渲染队列
    /// </summary>
    /// <param name="renderer">渲染器</param>
    /// <param name="renderingData">渲染数据</param>
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        // 只在主相机上执行反射渲染
        if (renderingData.cameraData.cameraType == CameraType.Game)
        {
            renderer.EnqueuePass(reflectionPass);
        }
    }
}
