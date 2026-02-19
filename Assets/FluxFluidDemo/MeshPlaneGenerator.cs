using UnityEngine;

[RequireComponent(typeof(MeshFilter), typeof(MeshRenderer))]
[ExecuteInEditMode]
public class MeshPlaneGenerator : MonoBehaviour
{
    [Header("平面参数")]
    public float planeWidth = 10f;
    public float planeLength = 10f;
    [Min(1)] public int subdivisionsWidth = 10;
    [Min(1)] public int subdivisionsLength = 10;

    [Header("材质设置")]
    public Material planeMaterial;

    private Mesh _planeMesh;
    private MeshFilter _meshFilter;
    private MeshRenderer _meshRenderer;

    private float _lastWidth;
    private float _lastLength;
    private int _lastSubdivisionsWidth;
    private int _lastSubdivisionsLength;

    private void Awake()
    {
        _meshFilter = GetComponent<MeshFilter>();
        _meshRenderer = GetComponent<MeshRenderer>();

        _planeMesh = new Mesh();
        _planeMesh.name = "GeneratedPlaneMesh";
        _meshFilter.mesh = _planeMesh;

        if (planeMaterial == null)
        {
            planeMaterial = new Material(Shader.Find("Standard"));
        }
        _meshRenderer.material = planeMaterial;
    }

    private void Update()
    {
        if (HasParametersChanged())
        {
            GeneratePlaneMesh();
            UpdateLastParameters();
        }
    }

    private bool HasParametersChanged()
    {
        return planeWidth != _lastWidth ||
               planeLength != _lastLength ||
               subdivisionsWidth != _lastSubdivisionsWidth ||
               subdivisionsLength != _lastSubdivisionsLength;
    }

    private void UpdateLastParameters()
    {
        _lastWidth = planeWidth;
        _lastLength = planeLength;
        _lastSubdivisionsWidth = subdivisionsWidth;
        _lastSubdivisionsLength = subdivisionsLength;
    }

    private void GeneratePlaneMesh()
    {
        _planeMesh.Clear();

        // 顶点数量：(宽度细分+1) * (长度细分+1)
        int vertexCount = (subdivisionsWidth + 1) * (subdivisionsLength + 1);
        Vector3[] vertices = new Vector3[vertexCount];
        Vector2[] uv = new Vector2[vertexCount];
        Vector3[] normals = new Vector3[vertexCount];
        // 新增：切线数组（Vector4：xyz为切线方向，w为副切线方向控制）
        Vector4[] tangents = new Vector4[vertexCount];

        // 细分步长
        float stepX = planeWidth / subdivisionsWidth;
        float stepZ = planeLength / subdivisionsLength;

        // 中心偏移
        float offsetX = -planeWidth / 2f;
        float offsetZ = -planeLength / 2f;

        // 生成顶点、UV、法线、切线
        int vertexIndex = 0;
        for (int z = 0; z <= subdivisionsLength; z++)
        {
            for (int x = 0; x <= subdivisionsWidth; x++)
            {
                // 顶点位置（XZ平面，Y轴为0）
                float posX = offsetX + x * stepX;
                float posZ = offsetZ + z * stepZ;
                vertices[vertexIndex] = new Vector3(posX, 0f, posZ);

                // UV坐标（0-1范围）
                uv[vertexIndex] = new Vector2((float)x / subdivisionsWidth, (float)z / subdivisionsLength);

                // 法线：Y轴正方向
                normals[vertexIndex] = Vector3.up;

                // 切线：X轴正方向（xyz），w=1（控制副切线方向为切线×法线的正方向）
                // 这是XZ平面的标准切线设置，与UV的x轴对齐
                tangents[vertexIndex] = new Vector4(1f, 0f, 0f, 1f);

                vertexIndex++;
            }
        }

        // 生成三角面索引
        int triangleCount = subdivisionsWidth * subdivisionsLength * 2;
        int[] triangles = new int[triangleCount * 3];
        int triangleIndex = 0;

        for (int z = 0; z < subdivisionsLength; z++)
        {
            for (int x = 0; x < subdivisionsWidth; x++)
            {
                int topLeft = z * (subdivisionsWidth + 1) + x;
                int topRight = topLeft + 1;
                int bottomLeft = (z + 1) * (subdivisionsWidth + 1) + x;
                int bottomRight = bottomLeft + 1;

                // 第一个三角形：左上 -> 左下 -> 右下
                triangles[triangleIndex++] = topLeft;
                triangles[triangleIndex++] = bottomLeft;
                triangles[triangleIndex++] = bottomRight;

                // 第二个三角形：左上 -> 右下 -> 右上
                triangles[triangleIndex++] = topLeft;
                triangles[triangleIndex++] = bottomRight;
                triangles[triangleIndex++] = topRight;
            }
        }

        // 赋值网格数据
        _planeMesh.vertices = vertices;
        _planeMesh.uv = uv;
        _planeMesh.normals = normals;
        _planeMesh.triangles = triangles;
        // 新增：赋值切线数据（关键修复点）
        _planeMesh.tangents = tangents;

        // 可选：优化网格（重建边界、切线，确保数据正确）
        _planeMesh.RecalculateBounds();
        // 注意：不要调用RecalculateTangents()，否则会覆盖我们手动设置的切线
    }

    // 可选：Gizmos绘制平面范围
    /*
    private void OnDrawGizmosSelected()
    {
        Gizmos.color = Color.yellow;
        Gizmos.DrawWireCube(transform.position, new Vector3(planeWidth, 0.1f, planeLength));
    }
    */
}