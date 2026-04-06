using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

// 体积云渲染的Volume Component
// 用于在Post-Processing Volume中配置体积云参数
public class AtmosphereVolume : VolumeComponent
{
    [Header("大气参数")]
    [Tooltip("整体缩放比例")]
    public ClampedFloatParameter totalScale = new ClampedFloatParameter(1f, 0.1f, 100f);
    
    [Tooltip("行星半径(米)")]
    public ClampedFloatParameter planetRadius = new ClampedFloatParameter(6371000f, 1000f, 100000000f);
    
    [Tooltip("海拔高度(千米)")]
    public ClampedFloatParameter altitude = new ClampedFloatParameter(0f, 0f, 100f);

    [Header("太阳参数")]
    [Tooltip("太阳亮度")]
    public ClampedFloatParameter sunBrightness = new ClampedFloatParameter(1f, 0f, 10f);

    [Header("采样参数")]
    [Tooltip("视线采样数量")]
    public ClampedIntParameter numSamples = new ClampedIntParameter(32, 4, 64);
    
    [Tooltip("太阳光采样数量")]
    public ClampedIntParameter numSamplesLight = new ClampedIntParameter(8, 1, 16);

    [Header("环境参数")]
    [Tooltip("全景贴图旋转角度")]
    public ClampedFloatParameter panoramicRotation = new ClampedFloatParameter(0f, 0f, 1f);

    [Header("云参数")]
    [Tooltip("云底高度(米)")]
    public ClampedFloatParameter cloudBaseHeight = new ClampedFloatParameter(2000f, 100f, 10000f);
    
    [Tooltip("云厚度(米)")]
    public ClampedFloatParameter cloudThickness = new ClampedFloatParameter(1000f, 100f, 5000f);
    
    [Tooltip("云透明度")]
    public ClampedFloatParameter cloudAlpha = new ClampedFloatParameter(0.5f, 0f, 1f);
    
    [Tooltip("云散射系数")]
    public ClampedFloatParameter cloudScatterCoeff = new ClampedFloatParameter(1f, 0f, 10f);
    
    [Tooltip("云消光系数")]
    public ClampedFloatParameter cloudExtinctionCoeff = new ClampedFloatParameter(0.05f, 0f, 1f);
    
    [Tooltip("云相位函数G值")]
    public ClampedFloatParameter cloudPhaseG = new ClampedFloatParameter(0.8f, 0f, 0.99f);
    
    [Tooltip("云密度阈值")]
    public ClampedFloatParameter cloudDensityThreshold = new ClampedFloatParameter(0.1f, 0f, 1f);
    
    [Tooltip("云边缘锐度")]
    public ClampedFloatParameter cloudEdgeSharpness = new ClampedFloatParameter(0.5f, 0f, 1f);
    
    [Tooltip("云密度乘数")]
    public ClampedFloatParameter cloudDensityMultiplier = new ClampedFloatParameter(0.1f, 0.001f, 30f);

    [Header("双边滤波参数")]
    [Tooltip("滤波半径")]
    public ClampedFloatParameter filterRadius = new ClampedFloatParameter(3f, 1f, 10f);
    
    [Tooltip("空间域Sigma值")]
    public ClampedFloatParameter sigmaSpace = new ClampedFloatParameter(1.5f, 0.1f, 10f);
    
    [Tooltip("值域Sigma值")]
    public ClampedFloatParameter sigmaRange = new ClampedFloatParameter(0.1f, 0.01f, 1f);

    [Header("纹理资源")]
    [Tooltip("云纹理(3D纹理)")]
    public Texture3DParameter cloudTex = new Texture3DParameter(null);
    
    [Tooltip("蓝噪声纹理")]
    public Texture2DParameter blueNoise = new Texture2DParameter(null);
    
    [Tooltip("环境全景贴图")]
    public Texture2DParameter envPanoramic = new Texture2DParameter(null);

    // ==================== 大气散射参数 ====================
    [Header("大气散射参数")]
    [Tooltip("大气层厚度(米)")]
    public ClampedFloatParameter atmosphereHeight = new ClampedFloatParameter(100000f, 10000f, 500000f);
    
    [Tooltip("瑞利散射高度(米)")]
    public ClampedFloatParameter rayleighScaleHeight = new ClampedFloatParameter(8000f, 1000f, 20000f);
    
    [Tooltip("米氏散射高度(米)")]
    public ClampedFloatParameter mieScaleHeight = new ClampedFloatParameter(1200f, 100f, 5000f);
    
    [Tooltip("臭氧层高度(米)")]
    public ClampedFloatParameter ozoneScaleHeight = new ClampedFloatParameter(25000f, 5000f, 50000f);
    
    [Tooltip("臭氧层中心高度(米)")]
    public ClampedFloatParameter ozoneCenterHeight = new ClampedFloatParameter(25000f, 5000f, 50000f);
    
    [Tooltip("大气密度强度")]
    public ClampedFloatParameter atmosIntensity = new ClampedFloatParameter(1f, 0f, 3f);

    [Header("大气散射系数")]
    [Tooltip("瑞利散射强度")]
    public ClampedFloatParameter rayleighScatterScale = new ClampedFloatParameter(1f, 0f, 5f);
    
    [Tooltip("米氏散射强度")]
    public ClampedFloatParameter mieScatterScale = new ClampedFloatParameter(1f, 0f, 5f);
    
    [Tooltip("米氏消光系数")]
    public ClampedFloatParameter mieExtinctionCoeff = new ClampedFloatParameter(0.0000025f, 0f, 0.0001f);

    [Header("大气相位函数参数")]
    [Tooltip("米氏相位函数G值")]
    public ClampedFloatParameter atmosMieG = new ClampedFloatParameter(0.76f, 0f, 0.99f);
    
    [Tooltip("太阳米氏相位函数G值")]
    public ClampedFloatParameter sunMieG = new ClampedFloatParameter(0.98f, 0f, 0.999f);
    
    [Tooltip("太阳米氏散射强度")]
    public ClampedFloatParameter sunMieIntensity = new ClampedFloatParameter(1f, 0f, 10f);

    [Header("太阳圆盘参数")]
    [Tooltip("太阳大小")]
    public ClampedFloatParameter sunSize = new ClampedFloatParameter(0.001f, 0.00001f, 0.005f);
    
    [Tooltip("太阳颜色")]
    public ColorParameter sunColor = new ColorParameter(Color.white);
}
