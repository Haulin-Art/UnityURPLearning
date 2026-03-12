using UnityEngine;

/// <summary>
/// 阵列分布组件
/// 在XYZ三个方向上生成网格实例阵列，使用GPU Instancing进行高效渲染
/// </summary>
[ExecuteAlways]
public class ArrayDistribution : MonoBehaviour
{
    [Header("网格与材质")]
    [Tooltip("要绘制的网格")]
    [SerializeField] private Mesh mesh;
    [Tooltip("使用的材质（必须开启GPU Instancing）")]
    [SerializeField] private Material material;

    [Header("阵列设置")]
    [Tooltip("各方向上的实例数量")]
    [SerializeField] private Vector3Int count = new Vector3Int(5, 5, 1);
    [Tooltip("实例之间的间距")]
    [SerializeField] private Vector3 spacing = Vector3.one;
    [Tooltip("阵列起始点（本地坐标）")]
    [SerializeField] private Vector3 startPoint = Vector3.zero;
    [Tooltip("整体偏移量")]
    [SerializeField] private Vector3 globalOffset = Vector3.zero;
    [Tooltip("单个实例的缩放比例")]
    [SerializeField] private Vector3 instanceScale = Vector3.one;

    [Header("渲染选项")]
    [Tooltip("是否在编辑器中绘制Gizmos")]
    [SerializeField] private bool drawInEditor = true;
    [Tooltip("是否投射阴影")]
    [SerializeField] private bool castShadows = true;
    [Tooltip("是否接收阴影")]
    [SerializeField] private bool receiveShadows = true;
    [Tooltip("渲染层级")]
    [SerializeField] private int layer = 0;

    private Matrix4x4[] matrices;
    private MaterialPropertyBlock propertyBlock;

    private void Update()
    {
        if (mesh == null || material == null)
            return;

        UpdateMatrices();

        Graphics.DrawMeshInstanced(mesh, 0, material, matrices, matrices.Length, propertyBlock,
            castShadows ? UnityEngine.Rendering.ShadowCastingMode.On : UnityEngine.Rendering.ShadowCastingMode.Off,
            receiveShadows, layer);
    }

    /// <summary>
    /// 更新所有实例的变换矩阵
    /// </summary>
    private void UpdateMatrices()
    {
        int total = count.x * count.y * count.z;

        if (matrices == null || matrices.Length != total)
        {
            matrices = new Matrix4x4[total];
        }

        int index = 0;
        for (int x = 0; x < count.x; x++)
        {
            for (int y = 0; y < count.y; y++)
            {
                for (int z = 0; z < count.z; z++)
                {
                    Vector3 position = startPoint + new Vector3(x * spacing.x, y * spacing.y, z * spacing.z) + globalOffset;
                    position = transform.TransformPoint(position);

                    Quaternion rotation = transform.rotation;
                    Vector3 scale = Vector3.Scale(instanceScale, transform.lossyScale);

                    matrices[index] = Matrix4x4.TRS(position, rotation, scale);
                    index++;
                }
            }
        }
    }

    /// <summary>
    /// 获取实例总数
    /// </summary>
    public int GetTotalCount()
    {
        return count.x * count.y * count.z;
    }

    /// <summary>
    /// 获取阵列的实际尺寸（不含间距）
    /// </summary>
    public Vector3 GetArraySize()
    {
        return new Vector3(
            (count.x - 1) * spacing.x,
            (count.y - 1) * spacing.y,
            (count.z - 1) * spacing.z
        );
    }

    /// <summary>
    /// 手动刷新矩阵数据
    /// </summary>
    public void RefreshMatrices()
    {
        UpdateMatrices();
    }

#if UNITY_EDITOR
    /// <summary>
    /// 在编辑器中绘制可视化辅助线
    /// </summary>
    private void OnDrawGizmosSelected()
    {
        if (!drawInEditor || mesh == null)
            return;

        Gizmos.color = Color.cyan;
        Vector3 arraySize = GetArraySize();
        Vector3 center = transform.TransformPoint(startPoint + arraySize * 0.5f + globalOffset);
        Gizmos.matrix = Matrix4x4.TRS(center, transform.rotation, transform.lossyScale);
        Gizmos.DrawWireCube(Vector3.zero, arraySize + spacing);

        Gizmos.color = Color.yellow;
        Gizmos.matrix = Matrix4x4.identity;
        for (int x = 0; x < count.x; x++)
        {
            for (int y = 0; y < count.y; y++)
            {
                for (int z = 0; z < count.z; z++)
                {
                    Vector3 position = startPoint + new Vector3(x * spacing.x, y * spacing.y, z * spacing.z) + globalOffset;
                    position = transform.TransformPoint(position);
                    Gizmos.DrawWireSphere(position, 0.05f);
                }
            }
        }
    }
#endif
}
