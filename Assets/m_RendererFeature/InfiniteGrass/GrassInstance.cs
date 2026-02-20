using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using System.Linq;
using UnityEngine.UIElements;
[ExecuteAlways]
public class GrassInstance : MonoBehaviour
{
    public int textureSize = 2048;
    public float drawDistance = 10.0f;
    public float textureUpdateThreshold = 10.0f;
    public float spacing = 1.0f;
    public float maxBufferCount = 1.0f;
    [SerializeField]private Mesh cacheMesh;

    // 间接渲染参数缓冲区：存储DrawMeshInstancedIndirect所需的参数（索引数、实例数等）
    public ComputeBuffer argsBuffer;
    // 临时缓冲区：用于预览可见草叶数量（调试用，性能开销大）
    public ComputeBuffer grassPosBuffer;
    // 草叶渲染材质（关联前文的GrassBladeShader）
    public Material grassMaterial;
    [HideInInspector] public static GrassInstance instance;
    void OnEnable()
    {
        instance = this;
    }
    void OnDisable()
    {
        instance = null;
        // 释放缓冲区：?. 避免空引用异常
        argsBuffer?.Release();
    }

    void LateUpdate()
    {
        //perTypeInstance = new ComputeBuffer[meshArray.Length];
        // 先释放旧的缓冲区（每帧重建，避免缓冲区大小不匹配）
        argsBuffer?.Release();
        grassPosBuffer?.Release();
        // 安全检查：间距为0或材质为空时，直接返回（避免无效操作）
        if (spacing == 0 || grassMaterial == null || cacheMesh == null) return;
        // 1. 计算相机的包围盒（基于绘制距离，确定草叶的渲染范围）
        Bounds cameraBounds = CalCamBounds(Camera.main, drawDistance);
        // 2. 计算纹理更新的中心位置（步进式，对齐到阈值的整数倍）
        Vector2 centerPos = new Vector2(
            Mathf.Floor(Camera.main.transform.position.x / textureUpdateThreshold) * textureUpdateThreshold,
            Mathf.Floor(Camera.main.transform.position.z / textureUpdateThreshold) * textureUpdateThreshold
        );
        // 3. 初始化间接渲染参数缓冲区（argsBuffer）
        // 缓冲区大小：1个元素，每个元素包含5个uint（间接渲染的5个参数）
        // 缓冲区类型：IndirectArguments（专门用于间接渲染的参数缓冲区）
        argsBuffer = new ComputeBuffer(1, 5 * sizeof(uint), ComputeBufferType.IndirectArguments);
    
        // 4. 填充间接渲染参数数组
        uint[] args = new uint[5];
        // args[0]：网格的索引数量（每个草叶Mesh的三角形索引数）
        args[0] = (uint)cacheMesh.GetIndexCount(0);
        // args[1]：最大实例数（缓冲区容量，实际实例数由ComputeShader的计数器覆盖）
        args[1] = (uint)(maxBufferCount * 100000);
        // args[2]：索引起始位置（默认0）
        args[2] = (uint)cacheMesh.GetIndexStart(0);
        // args[3]：基础顶点位置（默认0）
        args[3] = (uint)cacheMesh.GetBaseVertex(0);
        // args[4]：实际渲染的实例数（由ComputeShader的计数器更新，初始为0）
        args[4] = 0;
        // 将参数写入缓冲区
        argsBuffer.SetData(args);
        // 7. 执行GPU实例化间接渲染（核心：百万级草叶渲染）
        // 参数：草叶网格、子网格索引、材质、渲染范围包围盒、间接参数缓冲区
        //grassMaterial.SetBuffer("_InstancePosition",grassPosBuffer);
        Graphics.DrawMeshInstancedIndirect(cacheMesh, 0, grassMaterial, cameraBounds, argsBuffer);
    }
    
    public Bounds camBounds;
    Bounds CalCamBounds(Camera camera,float drawDistance)
    {
        // 计算摄像机近平面的四个顶点
        Vector3 nTL = camera.ViewportToWorldPoint(new Vector3(0,1,camera.nearClipPlane));
        Vector3 nTR = camera.ViewportToWorldPoint(new Vector3(1,1,camera.nearClipPlane));
        Vector3 nBL = camera.ViewportToWorldPoint(new Vector3(0,0,camera.nearClipPlane));
        Vector3 nBR = camera.ViewportToWorldPoint(new Vector3(1,0,camera.nearClipPlane));
        // 计算设定的远平面的四个顶点
        Vector3 fTL = camera.ViewportToWorldPoint(new Vector3(0,1,drawDistance));
        Vector3 fTR = camera.ViewportToWorldPoint(new Vector3(1,1,drawDistance));
        Vector3 fBL = camera.ViewportToWorldPoint(new Vector3(0,0,drawDistance));
        Vector3 fBR = camera.ViewportToWorldPoint(new Vector3(1,0,drawDistance));
        // 得x轴得最大/最小值
        float[] xValues = new float[]
        {
            nTL.x,nTR.x,nBL.x,nBR.x,fTL.x,fTR.x,fBL.x,fBR.x
        };
        float startX = xValues.Max();
        float endX = xValues.Min();
        // 得y轴得最大/最小值
        float[] yValues = new float[]
        {
            nTL.y,nTR.y,nBL.y,nBR.y,fTL.y,fTR.y,fBL.y,fBR.y
        };
        float startY = yValues.Max();
        float endY = yValues.Min();
        // 得z轴得最大/最小值
        float[] zValues = new float[]
        {
            nTL.z,nTR.z,nBL.z,nBR.z,fTL.z,fTR.z,fBL.z,fBR.z
        };
        float startZ = zValues.Max();
        float endZ = zValues.Min();
        // ========== 步骤3：计算包围盒的中心和大小 ==========
        Vector3 center = new Vector3(
            (startX + endX) / 2,   // X轴中心
            (startY + endY) / 2,   // Y轴中心
            (startZ + endZ) / 2    // Z轴中心
        );
        Vector3 size = new Vector3(
            Mathf.Abs(startX - endX), // X轴长度（最大-最小的绝对值）
            Mathf.Abs(startY - endY), // Y轴长度
            Mathf.Abs(startZ - endZ)  // Z轴长度
        );
        // ========== 步骤4：创建并返回包围盒 ==========
        Bounds bounds = new Bounds(center, size);
        bounds.Expand(1);
        return bounds;
    }
}
