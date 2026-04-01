using UnityEngine;

[RequireComponent(typeof(Light))]
[ExecuteInEditMode]
public class DynamicLightColor : MonoBehaviour
{
    [Header("颜色渐变")]
    [Tooltip("根据太阳高度采样的颜色渐变。0=完全地平线以下，0.5=地平线，1=天顶")]
    public Gradient colorGradient = new Gradient();

    [Header("强度曲线")]
    [Tooltip("根据太阳高度控制灯光强度的曲线。X轴:太阳高度(0-1)，Y轴:灯光强度(0-2)")]
    public AnimationCurve intensityCurve = AnimationCurve.EaseInOut(0f, 0f, 1f, 1f);

    [Header("调试信息")]
    [SerializeField] private float currentSunHeight = 0.5f;
    [SerializeField] private float currentIntensity = 1f;
    
    private Light _light;
    
    void Start()
    {
        _light = GetComponent<Light>();
        if (_light == null)
        {
            Debug.LogError("未找到Light组件！");
        }
        
        // 设置默认曲线（如果没有设置）
        if (intensityCurve.length == 0)
        {
            SetDefaultIntensityCurve();
        }
    }
    
    void Update()
    {
        if (_light == null) return;
        
        // 计算太阳高度
        currentSunHeight = CalculateSunHeightFromDotProduct();
        
        // 采样颜色
        Color sampledColor = colorGradient.Evaluate(currentSunHeight);
        _light.color = sampledColor;
        
        // 用曲线采样强度
        currentIntensity = intensityCurve.Evaluate(Mathf.Abs((1.0f-currentSunHeight*2.0f)));
        _light.intensity = Mathf.Max(0.01f,currentIntensity);
    }
    
    private float CalculateSunHeightFromDotProduct()
    {
        // 计算向上方向与太阳方向的点积
        // 当太阳在天顶时：Vector3.up · transform.forward = 0? (实际上是-1或0或1，取决于方向)
        // 实际上，对于定向光，太阳方向是transform.forward
        
        // 更好的方法：计算太阳方向与水平面的夹角
        Vector3 sunDir = transform.forward;
        Vector3 horizonDir = new Vector3(sunDir.x, 0, sunDir.z).normalized;
        
        if (horizonDir.magnitude < 0.0001f)
        {
            // 太阳在天顶或天底
            return (sunDir.y > 0) ? 1f : 0f;
        }
        
        // 计算太阳方向与水平面的角度
        float angle = Vector3.Angle(horizonDir, sunDir);
        
        if (sunDir.y < 0) 
        {
            // 太阳在地平线以下
            angle = -angle;
        }
        
        // 归一化：-90到90度 => 0到1
        return (angle + 90f) / 180f;
    }
    
    // 设置默认的强度曲线
    private void SetDefaultIntensityCurve()
    {
        // 创建一个模拟真实太阳强度的曲线：
        // 0.0以下：完全黑暗 (高度<0表示太阳在地平线下)
        // 0.0-0.1：日出/日落，强度从0快速增加到0.5
        // 0.1-0.5：早晨/傍晚，强度缓慢增加
        // 0.5-1.0：白天，强度达到最大值1.0
        
        intensityCurve = new AnimationCurve();
        
        // 太阳在地平线以下 (0.0以下)
        intensityCurve.AddKey(new Keyframe(0.0f, 0.0f));
        intensityCurve.AddKey(new Keyframe(0.05f, 0.1f));
        
        // 日出/日落时刻 (0.0-0.1)
        intensityCurve.AddKey(new Keyframe(0.1f, 0.5f));
        
        // 早晨/傍晚 (0.1-0.3)
        intensityCurve.AddKey(new Keyframe(0.3f, 0.8f));
        
        // 白天 (0.3-0.7)
        intensityCurve.AddKey(new Keyframe(0.7f, 1.0f));
        
        // 正午 (0.7-1.0)
        intensityCurve.AddKey(new Keyframe(1.0f, 1.2f));
        
        // 平滑曲线
        for (int i = 0; i < intensityCurve.length; i++)
        {
            intensityCurve.SmoothTangents(i, 0.5f); // 0.5f是平滑权重
        }
    }
    
    // 在编辑器中显示曲线预览
    #if UNITY_EDITOR
    private void OnValidate()
    {
        // 确保曲线在有效范围内
        if (intensityCurve != null)
        {
            // 可以在这里添加对曲线的验证
        }
    }
    #endif
}