using System.Collections;
using System.Collections.Generic;
using UnityEngine;

// 这个是最初可用版本，生成的网格是一个整体
public class bu_01_ChunkedSphereGenerator : MonoBehaviour
{
    [Header("球体设置")]
    [Range(1, 6)] public int chunkLevel = 1;
    [Range(0, 5)] public int subdivisionLevel = 1;
    [Range(0.5f, 5f)] public float radius = 1f;
    
    [Header("控制")]
    [SerializeField] private bool generateOnStart = true;
    [SerializeField] private bool autoUpdate = false; // 是否在编辑器模式下自动更新
    
    private Mesh mesh;
    
    // 记录上次的参数值，用于检测变化
    private int lastChunkLevel = 1;
    private int lastSubdivisionLevel = 1;
    private float lastRadius = 1f;
    
    void Start()
    {
        if (generateOnStart)
        {
            GenerateSphere();
        }
    }
    
    void OnValidate()
    {
        // 检查参数是否有变化
        bool parametersChanged = 
            chunkLevel != lastChunkLevel || 
            subdivisionLevel != lastSubdivisionLevel || 
            Mathf.Abs(radius - lastRadius) > 0.001f;
        
        if (parametersChanged && autoUpdate)
        {
            // 更新记录的值
            lastChunkLevel = chunkLevel;
            lastSubdivisionLevel = subdivisionLevel;
            lastRadius = radius;
            
            // 重新生成球体
            GenerateSphere();
        }
    }
    
    [ContextMenu("生成球体")]
    public void GenerateSphere()
    {
        // 更新记录的值
        lastChunkLevel = chunkLevel;
        lastSubdivisionLevel = subdivisionLevel;
        lastRadius = radius;
        
        // 确保有必要的组件
        if (GetComponent<MeshFilter>() == null) gameObject.AddComponent<MeshFilter>();
        if (GetComponent<MeshRenderer>() == null) gameObject.AddComponent<MeshRenderer>();
        
        mesh = new Mesh();
        mesh.name = "Chunked Sphere";
        
        // 计算顶点和三角形
        var (vertices, triangles) = GenerateSphereData();
        
        // 设置网格数据
        mesh.vertices = vertices;
        mesh.triangles = triangles;
        
        // 计算法线
        mesh.RecalculateNormals();
        mesh.RecalculateBounds();
        
        // 应用网格
        GetComponent<MeshFilter>().mesh = mesh;
        
        Debug.Log($"球体已生成: 分块等级={chunkLevel}, 细分等级={subdivisionLevel}, 顶点数={vertices.Length}");
    }
    
    private (Vector3[] vertices, int[] triangles) GenerateSphereData()
    {
        List<Vector3> vertices = new List<Vector3>();
        List<int> triangles = new List<int>();
        
        // 六个基本方向
        Vector3[] directions = {
            Vector3.up, Vector3.down, Vector3.left, Vector3.right, Vector3.forward, Vector3.back
        };
        
        int chunksPerSide = (int)Mathf.Pow(2, chunkLevel - 1);
        int subDivisions = (int)Mathf.Pow(2, subdivisionLevel);
        
        foreach (var dir in directions)
        {
            GenerateFace(dir, vertices, triangles, chunksPerSide, subDivisions);
        }
        
        return (vertices.ToArray(), triangles.ToArray());
    }
    
    private void GenerateFace(Vector3 normal, List<Vector3> vertices, List<int> triangles, 
                               int chunksPerSide, int subDivisions)
    {
        Vector3 axisA = new Vector3(normal.y, normal.z, normal.x);
        Vector3 axisB = Vector3.Cross(normal, axisA);
        
        for (int y = 0; y < chunksPerSide; y++)
        {
            for (int x = 0; x < chunksPerSide; x++)
            {
                int vertexIndex = vertices.Count;
                
                float chunkSize = 2f / chunksPerSide;
                float startX = -1f + x * chunkSize;
                float startY = -1f + y * chunkSize;
                
                // 生成顶点
                for (int sy = 0; sy <= subDivisions; sy++)
                {
                    for (int sx = 0; sx <= subDivisions; sx++)
                    {
                        float u = startX + (float)sx / subDivisions * chunkSize;
                        float v = startY + (float)sy / subDivisions * chunkSize;
                        
                        Vector3 pointOnCube = normal + axisA * u + axisB * v;
                        Vector3 pointOnSphere = pointOnCube.normalized * radius;
                        
                        vertices.Add(pointOnSphere);
                    }
                }
                
                // 生成三角形
                for (int sy = 0; sy < subDivisions; sy++)
                {
                    for (int sx = 0; sx < subDivisions; sx++)
                    {
                        int i = vertexIndex + sy * (subDivisions + 1) + sx;
                        
                        triangles.Add(i);
                        triangles.Add(i + subDivisions + 2);
                        triangles.Add(i + subDivisions + 1);
                        
                        triangles.Add(i);
                        triangles.Add(i + 1);
                        triangles.Add(i + subDivisions + 2);
                    }
                }
            }
        }
    }
    
    [ContextMenu("应用默认材质")]
    public void ApplyDefaultMaterial()
    {
        MeshRenderer renderer = GetComponent<MeshRenderer>();
        if (renderer != null)
        {
            // 创建默认材质
            Material defaultMaterial = new Material(Shader.Find("Standard"));
            defaultMaterial.color = Color.blue;
            renderer.material = defaultMaterial;
        }
    }
    
    private void OnDrawGizmos()
    {
        if (mesh != null)
        {
            Gizmos.color = Color.white;
            Gizmos.DrawWireMesh(mesh, transform.position, transform.rotation, transform.localScale);
        }
    }
}
