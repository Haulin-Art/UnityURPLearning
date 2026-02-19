using UnityEngine;

public static class QuadMeshGenerator
{
    private static Mesh _unitQuad;
    
    public static Mesh GetUnitQuad()
    {
        if (_unitQuad != null) return _unitQuad;
        
        _unitQuad = new Mesh();
        _unitQuad.name = "UnitQuad";
        
        // 四个顶点（中心在原点，边长1）
        Vector3[] vertices = new Vector3[4]
        {
            new Vector3(-0.5f, -0.5f, 0), // 左下
            new Vector3(0.5f, -0.5f, 0),  // 右下
            new Vector3(-0.5f, 0.5f, 0),  // 左上
            new Vector3(0.5f, 0.5f, 0)    // 右上
        };
        
        // 三角形索引（两个三角形组成一个四边形）
        int[] triangles = new int[6]
        {
            0, 2, 1, // 第一个三角形
            1, 2, 3  // 第二个三角形
        };
        
        // 法线（全部朝前）
        Vector3[] normals = new Vector3[4]
        {
            Vector3.forward,
            Vector3.forward,
            Vector3.forward,
            Vector3.forward
        };
        
        // UV坐标
        Vector2[] uv = new Vector2[4]
        {
            new Vector2(0, 0),
            new Vector2(1, 0),
            new Vector2(0, 1),
            new Vector2(1, 1)
        };
        
        _unitQuad.vertices = vertices;
        _unitQuad.triangles = triangles;
        _unitQuad.normals = normals;
        _unitQuad.uv = uv;
        
        return _unitQuad;
    }
    
    public static void ClearCache()
    {
        if (_unitQuad != null)
        {
            Object.DestroyImmediate(_unitQuad);
            _unitQuad = null;
        }
    }
}