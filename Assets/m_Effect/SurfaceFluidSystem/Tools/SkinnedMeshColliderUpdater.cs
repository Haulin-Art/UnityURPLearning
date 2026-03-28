using UnityEngine;

/// <summary>
/// 让 Mesh Collider 跟随骨骼动画变形
/// </summary>
[ExecuteInEditMode]
[RequireComponent(typeof(SkinnedMeshRenderer), typeof(MeshCollider))]
public class SkinnedMeshColliderUpdater : MonoBehaviour
{
    private SkinnedMeshRenderer skinnedMeshRenderer;
    private MeshCollider meshCollider;
    private Mesh bakedMesh;

    [Header("更新设置")]
    [Tooltip("是否每帧更新（性能消耗较大）")]
    public bool updateEveryFrame = false;
    
    [Tooltip("是否立即更新一次碰撞体网格")]
    public bool updateRightNow = false;

    [Header("坐标修正")]
    [Tooltip("碰撞体旋转偏移（用于修正坐标系差异）")]
    public Vector3 rotationOffset = Vector3.zero;
    
    [Tooltip("常用预设：X轴旋转90度（Z轴向上的模型）")]
    public bool presetRotateX90 = false;

    [Header("调试")]
    [Tooltip("是否显示调试信息")]
    public bool debugMode = true;
    
    [Tooltip("是否在Scene视图中绘制碰撞体线框")]
    public bool drawWireframe = true;

    private bool isInitialized = false;
    private Quaternion cachedRotationOffset = Quaternion.identity;

    private void Awake()
    {
        Initialize();
    }

    private void OnEnable()
    {
        Initialize();
    }

    private void OnValidate()
    {
        // 预设：X轴旋转90度
        if (presetRotateX90)
        {
            rotationOffset = new Vector3(90f, 0f, 0f);
            presetRotateX90 = false;
        }
        
        cachedRotationOffset = Quaternion.Euler(rotationOffset);
    }

    /// <summary>
    /// 初始化组件引用
    /// </summary>
    private void Initialize()
    {
        skinnedMeshRenderer = GetComponent<SkinnedMeshRenderer>();
        meshCollider = GetComponent<MeshCollider>();

        if (skinnedMeshRenderer == null)
        {
            Debug.LogError($"[{nameof(SkinnedMeshColliderUpdater)}] 未找到 SkinnedMeshRenderer 组件！");
            return;
        }

        if (meshCollider == null)
        {
            Debug.LogError($"[{nameof(SkinnedMeshColliderUpdater)}] 未找到 MeshCollider 组件！");
            return;
        }

        if (skinnedMeshRenderer.sharedMesh == null)
        {
            Debug.LogError($"[{nameof(SkinnedMeshColliderUpdater)}] SkinnedMeshRenderer 的 mesh 为空！");
            return;
        }

        bakedMesh = new Mesh();
        bakedMesh.name = "BakedMesh";

        cachedRotationOffset = Quaternion.Euler(rotationOffset);

        isInitialized = true;

        if (debugMode)
        {
            Debug.Log($"[{nameof(SkinnedMeshColliderUpdater)}] 初始化成功！原始网格顶点数: {skinnedMeshRenderer.sharedMesh.vertexCount}");
        }

        UpdateCollider();
    }

    private void Update()
    {
        if (!isInitialized) return;

        if (updateEveryFrame)
        {
            UpdateCollider();
        }
    }

    /// <summary>
    /// 更新碰撞体网格
    /// </summary>
    public void UpdateCollider()
    {
        if (!isInitialized || skinnedMeshRenderer == null || meshCollider == null)
        {
            if (debugMode) Debug.LogWarning($"[{nameof(SkinnedMeshColliderUpdater)}] 组件未正确初始化，无法更新碰撞体");
            return;
        }

        skinnedMeshRenderer.BakeMesh(bakedMesh);

        if (bakedMesh.vertexCount == 0)
        {
            if (debugMode) Debug.LogWarning($"[{nameof(SkinnedMeshColliderUpdater)}] 烘焙的网格顶点数为0！");
            return;
        }

        Vector3[] vertices = bakedMesh.vertices;
        Matrix4x4 worldToLocal = transform.worldToLocalMatrix;
        
        for (int i = 0; i < vertices.Length; i++)
        {
            // 先转换到局部空间
            vertices[i] = worldToLocal.MultiplyPoint3x4(vertices[i]);
            // 应用旋转偏移修正坐标系
            vertices[i] = cachedRotationOffset * vertices[i];
        }
        
        bakedMesh.vertices = vertices;
        bakedMesh.RecalculateBounds();
        bakedMesh.RecalculateNormals();

        meshCollider.sharedMesh = null;
        meshCollider.sharedMesh = bakedMesh;

        if (debugMode)
        {
            Debug.Log($"[{nameof(SkinnedMeshColliderUpdater)}] 碰撞体已更新！顶点数: {bakedMesh.vertexCount}, 旋转偏移: {rotationOffset}");
        }
    }

    private void LateUpdate()
    {
        if (!isInitialized) return;

        if (!updateEveryFrame)
        {
            UpdateCollider();
        }

        if (updateRightNow)
        {
            UpdateCollider();
            updateRightNow = false;
        }
    }

    /// <summary>
    /// 在Scene视图中绘制碰撞体线框用于调试
    /// </summary>
    private void OnDrawGizmos()
    {
        if (!drawWireframe || bakedMesh == null || bakedMesh.vertexCount == 0) return;

        Gizmos.color = Color.green;
        Gizmos.matrix = transform.localToWorldMatrix * Matrix4x4.Rotate(cachedRotationOffset);
        Gizmos.DrawWireMesh(bakedMesh);
    }
}
