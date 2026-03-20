using UnityEngine;

/// <summary>
/// 在贴图上绘制圆形的脚本
/// 通过射线检测获取UV坐标，使用Compute Shader在RenderTexture上绘制实心圆
/// </summary>
public class DrawCircleOnTexture : MonoBehaviour
{
    [Header("目标设置")]
    [Tooltip("需要进行射线检测的目标物体")]
    public Transform targetObject;

    [Header("贴图设置")]
    [Tooltip("用于绘制圆形的RenderTexture")]
    public RenderTexture targetTexture;

    [Header("Compute Shader")]
    [Tooltip("用于绘制圆形的Compute Shader")]
    public ComputeShader drawCircleCompute;

    [Header("圆形参数")]
    [Tooltip("圆形的半径（像素）")]
    public float circleRadius = 20f;

    [Tooltip("圆形的颜色")]
    public Color circleColor = Color.red;

    [Header("射线设置")]
    [Tooltip("射线检测的层级")]
    public LayerMask raycastLayer = -1;

    private Camera mainCamera;

    // Compute Shader相关
    private int kernelDrawCircle;
    private int kernelClear;
    private bool isInitialized = false;

    private void Start()
    {
        mainCamera = Camera.main;

        if (mainCamera == null)
        {
            Debug.LogError("DrawCircleOnTexture: 未找到主相机！");
            return;
        }

        InitializeComputeShader();
    }

    /// <summary>
    /// 初始化Compute Shader
    /// </summary>
    private void InitializeComputeShader()
    {
        if (drawCircleCompute == null)
        {
            Debug.LogError("DrawCircleOnTexture: Compute Shader未设置！");
            return;
        }

        if (targetTexture == null)
        {
            Debug.LogError("DrawCircleOnTexture: 目标贴图未设置！");
            return;
        }

        // 获取kernel索引
        kernelDrawCircle = drawCircleCompute.FindKernel("CSDrawCircle");
        kernelClear = drawCircleCompute.FindKernel("CSClear");

        // 确保RenderTexture支持随机写入
        if (!targetTexture.enableRandomWrite)
        {
            targetTexture.enableRandomWrite = true;
            Debug.Log("DrawCircleOnTexture: 已启用RenderTexture的随机写入功能");
        }

        isInitialized = true;
        Debug.Log("DrawCircleOnTexture: Compute Shader初始化完成");
    }

    private void Update()
    {
        if (Input.GetMouseButtonDown(0))
        {
            PerformRaycast();
        }

        // 按R键清空贴图（调试用）
        if (Input.GetKeyDown(KeyCode.R))
        {
            ClearTexture();
        }
    }

    /// <summary>
    /// 执行射线检测
    /// </summary>
    private void PerformRaycast()
    {
        if (mainCamera == null) return;

        // 从屏幕中心发射射线
        Vector2 screenCenter = new Vector2(Screen.width * 0.5f, Screen.height * 0.5f);
        Ray ray = mainCamera.ScreenPointToRay(screenCenter);

        if (Physics.Raycast(ray, out RaycastHit hit, Mathf.Infinity, raycastLayer))
        {
            // 检查是否命中了目标物体
            if (targetObject != null && hit.transform == targetObject)
            {
                Vector2 uv = hit.textureCoord;

                Debug.Log($"<color=green>DrawCircleOnTexture: 命中目标物体！</color>");
                Debug.Log($"<color=green>  - 命中点UV坐标: {uv}</color>");

                // 调用Compute Shader绘制圆形
                DrawCircle(uv);
            }
            else
            {
                Debug.Log($"DrawCircleOnTexture: 射线命中了物体 '{hit.transform.name}'，但不是目标物体");
            }
        }
        else
        {
            Debug.Log("DrawCircleOnTexture: 射线未命中任何物体");
        }
    }

    /// <summary>
    /// 在指定UV坐标绘制圆形
    /// </summary>
    /// <param name="uv">UV坐标（0-1范围）</param>
    private void DrawCircle(Vector2 uv)
    {
        if (!isInitialized)
        {
            Debug.LogWarning("DrawCircleOnTexture: Compute Shader未初始化！");
            return;
        }

        if (targetTexture == null) return;

        // 设置Compute Shader参数
        drawCircleCompute.SetInt("_Width", targetTexture.width);
        drawCircleCompute.SetInt("_Height", targetTexture.height);
        drawCircleCompute.SetVector("_CenterUV", new Vector2(uv.x, uv.y));
        drawCircleCompute.SetFloat("_Radius", circleRadius);
        drawCircleCompute.SetVector("_CircleColor", new Vector4(circleColor.r, circleColor.g, circleColor.b, circleColor.a));

        // 设置输出贴图
        drawCircleCompute.SetTexture(kernelDrawCircle, "ResultTexture", targetTexture);

        // 计算线程组数量（每个线程组8x8个线程）
        int threadGroupsX = Mathf.CeilToInt(targetTexture.width / 8.0f);
        int threadGroupsY = Mathf.CeilToInt(targetTexture.height / 8.0f);

        // 执行Compute Shader
        drawCircleCompute.Dispatch(kernelDrawCircle, threadGroupsX, threadGroupsY, 1);

        Debug.Log($"<color=cyan>DrawCircleOnTexture: 已在UV({uv.x:F3}, {uv.y:F3})处绘制圆形</color>");
    }

    /// <summary>
    /// 清空贴图
    /// </summary>
    public void ClearTexture()
    {
        if (!isInitialized || targetTexture == null) return;

        drawCircleCompute.SetInt("_Width", targetTexture.width);
        drawCircleCompute.SetInt("_Height", targetTexture.height);
        drawCircleCompute.SetTexture(kernelClear, "ResultTexture", targetTexture);

        int threadGroupsX = Mathf.CeilToInt(targetTexture.width / 8.0f);
        int threadGroupsY = Mathf.CeilToInt(targetTexture.height / 8.0f);

        drawCircleCompute.Dispatch(kernelClear, threadGroupsX, threadGroupsY, 1);

        Debug.Log("<color=yellow>DrawCircleOnTexture: 贴图已清空</color>");
    }

    /// <summary>
    /// 在Scene视图中绘制调试信息
    /// </summary>
    private void OnDrawGizmos()
    {
        if (mainCamera == null) return;

        // 绘制射线方向
        Vector2 screenCenter = new Vector2(Screen.width * 0.5f, Screen.height * 0.5f);
        Ray ray = mainCamera.ScreenPointToRay(screenCenter);

        Gizmos.color = Color.yellow;
        Gizmos.DrawRay(ray.origin, ray.direction * 100f);
    }
}
