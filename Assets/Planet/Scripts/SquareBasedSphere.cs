using UnityEngine;
using System.Collections.Generic;

[ExecuteInEditMode]
public class SimpleCubedSphere : MonoBehaviour
{
    [Header("球体设置")]
    [Range(0.5f, 50f)] public float radius = 5f;
    [Range(1, 5)] public int chunkLevel = 2;
    
    [Header("渲染")]
    public Material quadMaterial;
    
    [Header("调试")]
    public bool showWireframe = true;
    public Color quadColor = new Color(0.8f, 0.4f, 0.6f, 1f);
    
    private List<GameObject> _quads = new List<GameObject>();
    private Mesh _quadMesh;
    
    void Start()
    {
        GenerateSphere();
    }
    
    void OnValidate()
    {
        #if UNITY_EDITOR
        if (!Application.isPlaying && enabled && gameObject.activeInHierarchy)
        {
            ClearSphere();
            GenerateSphere();
        }
        #endif
    }
    
    [ContextMenu("生成球体")]
    public void GenerateSphere()
    {
        ClearSphere();
        
        // 获取单位正方形网格
        _quadMesh = CreateQuadMesh();
        
        // 计算分块数
        int chunksPerFace = (int)Mathf.Pow(4, chunkLevel - 1);
        int chunksPerSide = (int)Mathf.Sqrt(chunksPerFace);
        float faceSize = 2f;
        float chunkSize = faceSize / chunksPerSide;
        
        Debug.Log($"生成球体: 分块等级={chunkLevel}, 每面{chunksPerFace}块, 总共{6 * chunksPerFace}块");
        
        // 六个面
        Vector3[] faceNormals = 
        {
            Vector3.forward,  // 前
            Vector3.back,     // 后
            Vector3.right,    // 右
            Vector3.left,     // 左
            Vector3.up,       // 上
            Vector3.down      // 下
        };
        
        // 生成所有正方形
        for (int face = 0; face < 6; face++)
        {
            Vector3 normal = faceNormals[face];
            Vector3 right, up;
            GetFaceAxes(normal, out right, out up);
            
            for (int y = 0; y < chunksPerSide; y++)
            {
                for (int x = 0; x < chunksPerSide; x++)
                {
                    // 计算位置
                    float u = (x + 0.5f) * chunkSize - 1f;
                    float v = (y + 0.5f) * chunkSize - 1f;
                    
                    // 立方体坐标
                    Vector3 cubePos = normal + right * u + up * v;
                    
                    // 映射到球面
                    Vector3 spherePos = cubePos.normalized * radius;
                    
                    // 计算旋转（使正方形垂直于球面）
                    Vector3 forward = cubePos.normalized;
                    Vector3 tangent = Vector3.ProjectOnPlane(right, forward).normalized;
                    if (tangent.magnitude < 0.001f)
                        tangent = Vector3.Cross(forward, Vector3.up).normalized;
                    
                    Vector3 binormal = Vector3.Cross(forward, tangent).normalized;
                    Quaternion rotation = Quaternion.LookRotation(forward, binormal);
                    
                    // 计算缩放
                    float scale = chunkSize * radius * 0.5f;
                    
                    // 创建正方形
                    GameObject quad = new GameObject($"Quad_F{face}_{x}_{y}");
                    quad.transform.SetParent(transform, false);
                    quad.transform.localPosition = spherePos;
                    quad.transform.localRotation = rotation;
                    quad.transform.localScale = new Vector3(scale, scale, 1f);
                    
                    // 添加网格组件
                    MeshFilter filter = quad.AddComponent<MeshFilter>();
                    MeshRenderer renderer = quad.AddComponent<MeshRenderer>();
                    
                    filter.mesh = _quadMesh;
                    
                    // 设置材质
                    if (quadMaterial != null)
                    {
                        renderer.sharedMaterial = quadMaterial;
                    }
                    else
                    {
                        // 创建默认材质
                        Material mat = new Material(Shader.Find("Standard"));
                        mat.color = quadColor;
                        renderer.sharedMaterial = mat;
                    }
                    
                    _quads.Add(quad);
                }
            }
        }
        
        Debug.Log($"生成了 {_quads.Count} 个正方形");
    }
    
    [ContextMenu("清除球体")]
    public void ClearSphere()
    {
        foreach (GameObject quad in _quads)
        {
            if (quad != null)
            {
                if (Application.isPlaying)
                    Destroy(quad);
                else
                    DestroyImmediate(quad);
            }
        }
        _quads.Clear();
        
        if (_quadMesh != null)
        {
            if (Application.isPlaying)
                Destroy(_quadMesh);
            else
                DestroyImmediate(_quadMesh);
            _quadMesh = null;
        }
    }
    
    private Mesh CreateQuadMesh()
    {
        Mesh mesh = new Mesh();
        mesh.name = "Quad";
        
        Vector3[] vertices = 
        {
            new Vector3(-0.5f, -0.5f, 0),
            new Vector3(0.5f, -0.5f, 0),
            new Vector3(-0.5f, 0.5f, 0),
            new Vector3(0.5f, 0.5f, 0)
        };
        
        int[] triangles = { 0, 2, 1, 1, 2, 3 };
        Vector3[] normals = { Vector3.forward, Vector3.forward, Vector3.forward, Vector3.forward };
        Vector2[] uv = { new Vector2(0,0), new Vector2(1,0), new Vector2(0,1), new Vector2(1,1) };
        
        mesh.vertices = vertices;
        mesh.triangles = triangles;
        mesh.normals = normals;
        mesh.uv = uv;
        
        return mesh;
    }
    
    private void GetFaceAxes(Vector3 normal, out Vector3 right, out Vector3 up)
    {
        if (Mathf.Abs(normal.y) > 0.707f) // 上下面
        {
            right = Vector3.right;
            up = (normal.y > 0) ? Vector3.forward : Vector3.back;
        }
        else if (Mathf.Abs(normal.z) > 0.707f) // 前后面
        {
            right = (normal.z > 0) ? Vector3.right : Vector3.left;
            up = Vector3.up;
        }
        else // 左右面
        {
            right = (normal.x > 0) ? Vector3.forward : Vector3.back;
            up = Vector3.up;
        }
    }
    
    void OnDestroy()
    {
        ClearSphere();
    }
    
    void OnDrawGizmosSelected()
    {
        if (!showWireframe) return;
        
        Gizmos.color = Color.cyan;
        Gizmos.matrix = transform.localToWorldMatrix;
        Gizmos.DrawWireSphere(Vector3.zero, radius);
        Gizmos.matrix = Matrix4x4.identity;
    }
}