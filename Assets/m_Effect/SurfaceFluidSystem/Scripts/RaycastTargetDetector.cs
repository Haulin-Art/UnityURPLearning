using UnityEngine;

/// <summary>
/// 射线检测目标物体并获取UV坐标的脚本
/// 通过射线检测获取目标物体表面的UV坐标，供其他系统使用
/// 支持多物体检测
/// </summary>
public class RaycastTargetDetector : MonoBehaviour
{
    [Header("目标设置")]
    [Tooltip("需要进行射线检测的目标物体数组")]
    public Transform[] targetObjects;

    [Header("射线设置")]
    [Tooltip("射线检测的层级")]
    public LayerMask raycastLayer = -1;

    [Tooltip("是否使用屏幕中心作为射线起点")]
    public bool useScreenCenter = true;

    [Tooltip("自定义射线起点（当useScreenCenter为false时使用）")]
    public Vector2 customScreenPoint = Vector2.zero;

    [Tooltip("是否输出调试信息")]
    public bool debugInfo;

    // 射线检测结果
    private bool isHit = false;
    private Vector2 hitUV = Vector2.zero;
    private Vector2 previousHitUV = Vector2.zero;
    private bool previousIsHit = false;
    private Transform hitTarget = null;  // 当前命中的目标物体

    private Camera mainCamera;

    /// <summary>
    /// 当前是否命中目标物体
    /// </summary>
    public bool IsHit => isHit;

    /// <summary>
    /// 当前命中的UV坐标
    /// </summary>
    public Vector2 HitUV => hitUV;

    /// <summary>
    /// 上一帧是否命中
    /// </summary>
    public bool PreviousIsHit => previousIsHit;

    /// <summary>
    /// 上一帧命中的UV坐标
    /// </summary>
    public Vector2 PreviousHitUV => previousHitUV;

    /// <summary>
    /// 当前帧与上一帧UV的差值（用于计算力的方向）
    /// </summary>
    public Vector2 UVDelta => isHit && previousIsHit ? (hitUV - previousHitUV) : Vector2.zero;

    /// <summary>
    /// 当前命中的目标物体
    /// </summary>
    public Transform HitTarget => hitTarget;

    private void Start()
    {
        mainCamera = Camera.main;

        if (mainCamera == null)
        {
            Debug.LogError("RaycastTargetDetector: 未找到主相机！");
        }
    }

    private void Update()
    {
        // 保存上一帧的数据
        previousIsHit = isHit;
        previousHitUV = hitUV;

        // 持续检测射线命中
        PerformRaycast();

        if (debugInfo)
        {
            Debug.Log("是否击中:" + IsHit + " && 击中UV位置:" + HitUV + (hitTarget != null ? " && 命中物体:" + hitTarget.name : ""));
        }
    }

    /// <summary>
    /// 执行射线检测
    /// </summary>
    private void PerformRaycast()
    {
        if (mainCamera == null) return;

        // 确定射线起点
        Vector2 screenPoint = useScreenCenter 
            ? new Vector2(Screen.width * 0.5f, Screen.height * 0.5f) 
            //: customScreenPoint;
            : new Vector2(Screen.width * customScreenPoint.x, Screen.height * customScreenPoint.y) ;

        Ray ray = mainCamera.ScreenPointToRay(screenPoint);

        if (Physics.Raycast(ray, out RaycastHit hit, Mathf.Infinity, raycastLayer))
        {
            // 检查是否命中了目标物体数组中的任意一个
            bool foundTarget = false;
            if (targetObjects != null && targetObjects.Length > 0)
            {
                foreach (Transform target in targetObjects)
                {
                    if (target != null && hit.transform == target)
                    {
                        isHit = true;
                        hitUV = hit.textureCoord;
                        hitTarget = target;
                        foundTarget = true;
                        break;
                    }
                }
            }

            if (!foundTarget)
            {
                isHit = false;
                hitTarget = null;
            }
        }
        else
        {
            isHit = false;
            hitTarget = null;
        }
    }

    /// <summary>
    /// 获取射线检测数据（供外部调用）
    /// </summary>
    /// <param name="hit">是否命中</param>
    /// <param name="uv">命中的UV坐标</param>
    /// <param name="delta">UV变化量</param>
    public void GetRaycastData(out bool hit, out Vector2 uv, out Vector2 delta)
    {
        hit = isHit;
        uv = hitUV;
        delta = UVDelta;
    }

    /// <summary>
    /// 获取射线检测数据（包含命中目标）
    /// </summary>
    /// <param name="hit">是否命中</param>
    /// <param name="uv">命中的UV坐标</param>
    /// <param name="delta">UV变化量</param>
    /// <param name="target">命中的目标物体</param>
    public void GetRaycastData(out bool hit, out Vector2 uv, out Vector2 delta, out Transform target)
    {
        hit = isHit;
        uv = hitUV;
        delta = UVDelta;
        target = hitTarget;
    }

    /// <summary>
    /// 在Scene视图中绘制调试信息
    /// </summary>
    private void OnDrawGizmos()
    {
        if (mainCamera == null) return;

        Vector2 screenPoint = useScreenCenter 
            ? new Vector2(Screen.width * 0.5f, Screen.height * 0.5f) 
            : customScreenPoint;
        
        Ray ray = mainCamera.ScreenPointToRay(screenPoint);

        Gizmos.color = Color.yellow;
        Gizmos.DrawRay(ray.origin, ray.direction * 100f);
    }
}
