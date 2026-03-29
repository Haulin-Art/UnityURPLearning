using UnityEngine;

/// <summary>
/// 目标物体配置
/// 用于配置每个目标物体使用的UV通道
/// </summary>
[System.Serializable]
public class TargetObjectConfig
{
    [Tooltip("目标物体Transform")]
    public Transform target;
    
    [Tooltip("使用的UV通道索引（0=UV0, 1=UV1, 2=UV2）")]
    [Range(0, 2)]
    public int uvChannel = 0;
}

/// <summary>
/// 射线检测目标物体并获取UV坐标的脚本
/// 通过射线检测获取目标物体表面的UV坐标，供其他系统使用
/// 支持多物体检测，每个物体可单独配置UV通道
/// </summary>
public class RaycastTargetDetector : MonoBehaviour
{
    [Header("目标设置")]
    [Tooltip("需要进行射线检测的目标物体配置数组，每个物体可单独设置UV通道")]
    public TargetObjectConfig[] targetConfigs;

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
    private Transform hitTarget = null;
    private int hitUVChannel = 0;

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

    /// <summary>
    /// 当前命中使用的UV通道
    /// </summary>
    public int HitUVChannel => hitUVChannel;

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
        previousIsHit = isHit;
        previousHitUV = hitUV;

        if (Input.GetMouseButton(0))
        {
            PerformRaycast();
        }
        else
        {
            isHit = false;
            hitTarget = null;
        }

        if (debugInfo)
        {
            Debug.Log("是否击中:" + IsHit + " && 击中UV位置:" + HitUV + " && UV通道:" + hitUVChannel + (hitTarget != null ? " && 命中物体:" + hitTarget.name : ""));
        }
    }

    /// <summary>
    /// 执行射线检测
    /// </summary>
    private void PerformRaycast()
    {
        if (mainCamera == null) return;

        Vector2 screenPoint = useScreenCenter 
            ? new Vector2(Screen.width * 0.5f, Screen.height * 0.5f) 
            : new Vector2(Screen.width * customScreenPoint.x, Screen.height * customScreenPoint.y);

        Ray ray = mainCamera.ScreenPointToRay(screenPoint);

        if (Physics.Raycast(ray, out RaycastHit hit, Mathf.Infinity, raycastLayer))
        {
            bool foundTarget = false;
            if (targetConfigs != null && targetConfigs.Length > 0)
            {
                foreach (TargetObjectConfig config in targetConfigs)
                {
                    if (config.target != null && hit.transform == config.target)
                    {
                        isHit = true;
                        hitTarget = config.target;
                        hitUVChannel = config.uvChannel;
                        hitUV = GetUVFromHit(hit, config.uvChannel);
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
    /// 根据UV通道索引从RaycastHit获取UV坐标
    /// </summary>
    /// <param name="hit">射线命中信息</param>
    /// <param name="uvChannel">UV通道索引（0=UV0, 1=UV1, 2=UV2）</param>
    /// <returns>UV坐标</returns>
    private Vector2 GetUVFromHit(RaycastHit hit, int uvChannel)
    {
        switch (uvChannel)
        {
            case 0:
                // UV0 - Unity内置支持
                return hit.textureCoord;
            
            case 1:
                // UV1 - 需要通过Mesh获取
                return GetUVFromMesh(hit, 1);
            
            case 2:
                // UV2 - Unity内置支持
                return hit.textureCoord2;
            
            default:
                return hit.textureCoord;
        }
    }

    /// <summary>
    /// 从Mesh获取指定UV通道的坐标
    /// 用于获取UV1等非内置支持的UV通道
    /// </summary>
    /// <param name="hit">射线命中信息</param>
    /// <param name="uvChannel">UV通道索引</param>
    /// <returns>UV坐标</returns>
    private Vector2 GetUVFromMesh(RaycastHit hit, int uvChannel)
    {
        MeshCollider meshCollider = hit.collider as MeshCollider;
        if (meshCollider == null)
        {
            Debug.LogWarning("RaycastTargetDetector: 目标物体没有MeshCollider，无法获取UV" + uvChannel);
            return hit.textureCoord;
        }

        Mesh mesh = meshCollider.sharedMesh;
        if (mesh == null)
        {
            return hit.textureCoord;
        }

        // 获取三角形索引
        int triangleIndex = hit.triangleIndex * 3;
        
        // 获取顶点索引
        int[] triangles = mesh.triangles;
        if (triangleIndex + 2 >= triangles.Length)
        {
            return hit.textureCoord;
        }

        int v0 = triangles[triangleIndex];
        int v1 = triangles[triangleIndex + 1];
        int v2 = triangles[triangleIndex + 2];

        // 获取UV坐标
        Vector2[] uvs = null;
        switch (uvChannel)
        {
            case 0:
                uvs = mesh.uv;
                break;
            case 1:
                uvs = mesh.uv2;
                break;
            case 2:
                uvs = mesh.uv3;
                break;
            case 3:
                uvs = mesh.uv4;
                break;
            default:
                uvs = mesh.uv;
                break;
        }

        if (uvs == null || uvs.Length == 0)
        {
            Debug.LogWarning("RaycastTargetDetector: Mesh没有UV" + uvChannel + "数据");
            return hit.textureCoord;
        }

        // 使用重心坐标插值获取精确的UV
        Vector2 uv0 = uvs[v0];
        Vector2 uv1 = uvs[v1];
        Vector2 uv2 = uvs[v2];

        // 计算重心坐标
        Vector3 barycentric = hit.barycentricCoordinate;

        // 插值计算UV
        Vector2 interpolatedUV = uv0 * barycentric.x + uv1 * barycentric.y + uv2 * barycentric.z;
        
        return interpolatedUV;
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
    /// 获取射线检测数据（包含命中目标和UV通道）
    /// </summary>
    /// <param name="hit">是否命中</param>
    /// <param name="uv">命中的UV坐标</param>
    /// <param name="delta">UV变化量</param>
    /// <param name="target">命中的目标物体</param>
    /// <param name="uvChannel">使用的UV通道</param>
    public void GetRaycastData(out bool hit, out Vector2 uv, out Vector2 delta, out Transform target, out int uvChannel)
    {
        hit = isHit;
        uv = hitUV;
        delta = UVDelta;
        target = hitTarget;
        uvChannel = hitUVChannel;
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
