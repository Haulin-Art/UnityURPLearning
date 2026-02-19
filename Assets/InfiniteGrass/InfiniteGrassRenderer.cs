using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using System.Linq;
[ExecuteAlways] // 让它在编辑器中也运行
public class InfiniteGrassRenderer : MonoBehaviour
{
    public Texture2D densityTex;
    // 单例实例：全局唯一的草渲染管理器
    // 相当于在这个类当中增加了一个这个类的静态字段，使得可以直接通过类名.字段名就可以访问，使得可以在全局方便地访问这个类的功能
    [HideInInspector]public static InfiniteGrassRenderer instance; 
    [Header("Internal")]// 编辑器分组：内部资源（不建议手动修改）
    public Material grassMat;
    public ComputeBuffer argsBuffer;
    public ComputeBuffer tBuffer;

    [Header("Grass Properties")] // 编辑器分组：草的核心属性
    public float spacing = 0.5f; // 草株之间的间距（不要设太小，否则性能爆炸）
    public float drawDistance = 300; // 草的最大绘制距离（超过此距离不渲染草）
    public float fullDensityDistance = 50; // 超过此距离后，开始减少草的数量（性能优化）
    [Range(0, 10)]
    public int grassMeshSubdivision = 5; // 草模型的分段数（0=三角形，分段越多越精细但越耗性能）
    public float textureUpdateThreshold = 10.0f; // 相机移动超过此距离，才更新草的数据纹理（减少更新频率→优化性能）

    [Header("Max Buffer Count (Millions)")] // 编辑器分组：缓冲区最大容量（百万级）
    public float maxBufferCount = 2; // 草位置缓冲区的初始化容量（不要太大/太小：大→占显存，小→频繁扩容耗性能，默认2足够）

    [Header("Debug (Enabling this will make the performance drop a lot)")] // 编辑器分组：调试选项（开启会大幅掉帧）
    public bool previewVisibleGrassCount = false; // 是否预览“可见草的数量”（仅调试用）

    private Mesh cachedGrassMesh; // 缓存的草模型（避免重复获取→优化性能）

    // 生命周期函数：脚本启用时调用
    private void OnEnable()
    {
        // 单例赋值：将当前实例设为全局唯一的instance
        // 意思就是每有一个挂载这个脚本的对象，就会有个对应实例，这个是唯一的，即this
        // - 访问方式：直接写 InfiniteGrassRenderer.instance.spacing 即可调用属性
        // - 建议在LateUpdate里调用DrawMeshInstancedIndirect（避免和其他渲染逻辑冲突）
        // - 草的参数（密度、距离等）直接在Inspector调，不用改代码
        // - 静态类无法挂载到场景物体，所以用“MonoBehaviour+单例”模式
        instance = this;
    }

    // Update is called once per frameis
    private void OnDisable()
    {
        // 单例置空：避免后续调用时出现空引用
        instance = null;
        // 释放计算缓冲区资源（避免显存泄漏）
        argsBuffer?.Release();
        tBuffer?.Release();
    }
    // 生命周期函数：在Update之后、渲染之前调用（确保草的参数已更新，避免渲染错误）
    private void LateUpdate()
    {
        argsBuffer?.Release();
        tBuffer?.Release();

        if (spacing == 0 || grassMat == null)
            return;
        
        Bounds cameraBounds = CalCamBounds(Camera.main,drawDistance);
        Vector2 centerPos = new Vector2(
            Mathf.Floor(Camera.main.transform.position.x / textureUpdateThreshold) * textureUpdateThreshold,
            Mathf.Floor(Camera.main.transform.position.z / textureUpdateThreshold) * textureUpdateThreshold
        );
        // argsBuffer：Indirect渲染专用缓冲区（存储渲染参数，类型是IndirectArguments）
        // 参数：count=1（仅1组参数），stride=5*sizeof(uint)（Indirect需要5个uint参数）
        argsBuffer = new ComputeBuffer(1, 5 * sizeof(uint), ComputeBufferType.IndirectArguments);
        // tBuffer：临时缓冲区（仅调试用，存储可见草数量）
        tBuffer = new ComputeBuffer(1, sizeof(uint), ComputeBufferType.Raw);

        // 初始化Indirect渲染的参数数组（共5个uint参数，对应DrawMeshInstancedIndirect的要求）
        // 初始化Indirect渲染的参数数组（共5个uint参数，对应DrawMeshInstancedIndirect的要求）
        uint[] args = new uint[5];
        // args[0]：草Mesh的索引数量（子网格0）
        args[0] = (uint)GetGrassMeshCache().GetIndexCount(submesh: 0);
        // args[1]：最大实例数（草的最大渲染数量，由maxBufferCount决定）
        args[1] = (uint)(maxBufferCount * 1000000); 
        // args[2]：草Mesh的索引起始位置（子网格0）
        args[2] = (uint)GetGrassMeshCache().GetIndexStart(submesh: 0);
        // args[3]：草Mesh的基顶点位置（子网格0）
        args[3] = (uint)GetGrassMeshCache().GetBaseVertex(submesh: 0);
        // args[4]：预留参数（固定为0）
        args[4] = 0;
        // 将参数写入argsBuffer
        argsBuffer.SetData(args);
    
        // ========== 给草材质传递参数（GPU渲染时用） ==========
        // 【图注：他们RT是和height RT一样uv；这是每颗草的属性，这三个值可以确定每根草uv位置，为后续颜色RT uv采样铺垫】
        grassMat.SetTexture(name: "_DensityTexture", densityTex); // 传递密度纹理（控制草的分布）
        grassMat.SetTextureScale(name: "_DensityTexture", new Vector2(1, 1)); // 设置密度纹理的缩放（保持原尺寸）
        grassMat.SetVector(name: "_CenterPos", centerPos); // 传递相机取整后的XZ位置（确定草的UV基准）
        grassMat.SetFloat(name: "_DrawDistance", drawDistance); // 传递草的最大绘制距离
        grassMat.SetFloat(name: "_TextureUpdateThreshold", textureUpdateThreshold); // 传递纹理更新阈值
    
        // ========== 核心：GPU批量渲染草（实例化渲染，性能极高） ==========
        // 【图注：最重要，GPU画草】
        // DrawMeshInstancedIndirect：通过ComputeBuffer批量渲染大量实例（草），比普通实例化渲染更灵活
        // 参数：草Mesh、子网格索引、草材质、渲染范围（cameraBounds）、Indirect参数缓冲区（argsBuffer）
        Graphics.DrawMeshInstancedIndirect(
            GetGrassMeshCache(), 
            submeshIndex: 0, 
            grassMat, 
            cameraBounds, 
            argsBuffer
        );
    }

    
    /// 根据细分值（grassMeshSubdivision）动态生成草叶网格，并缓存（避免重复生成→优化性能）
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
            nTL.x,
            nTR.x,
            nBL.x,
            nBR.x,
            fTL.x,
            fTR.x,
            fBL.x,
            fBR.x
        };
        float startX = xValues.Max();
        float endX = xValues.Min();

        // 得y轴得最大/最小值
        float[] yValues = new float[]
        {
            nTL.y,
            nTR.y,
            nBL.y,
            nBR.y,
            fTL.y,
            fTR.y,
            fBL.y,
            fBR.y
        };
        float startY = yValues.Max();
        float endY = yValues.Min();
        // 得z轴得最大/最小值
        float[] zValues = new float[]
        {
            nTL.z,
            nTR.z,
            nBL.z,
            nBR.z,
            fTL.z,
            fTR.z,
            fBL.z,
            fBR.z
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
    private int oldSubdivision;
    public Mesh GetGrassMeshCache()
    {
        // 仅当“缓存网格不存在” 或 “细分值发生变化”时，才重新生成网格（避免无意义的计算）
        if (!cachedGrassMesh || oldSubdivision != grassMeshSubdivision)
        {
            cachedGrassMesh = new Mesh();// 初始化
            // ======== 初始化顶点、三角形数组 ===============
            Vector3[] vertices = new Vector3[3 + 4*grassMeshSubdivision]; // 基础三个顶点，每多细分增加四个顶点
            int[] triangles = new int[3*(1+2*grassMeshSubdivision)]; // 基础一个顶部三角形，每多细分增加两个三角形，每个三角形三个索引

            // 循环生成每个细分段的三角形
            for(int i = 0; i < grassMeshSubdivision; i++)
            {
                // 计算当前细分段在草叶高度上的比例（y1=当前段底部，y2=当前段顶部）
                float y1 = (float)i/(grassMeshSubdivision+1);
                float y2 = (float)(i+1)/(grassMeshSubdivision+1);
                // 生成当前分段的四个顶点，固定宽度0.5
                Vector3 bottomLeft = new Vector3(-0.25f, y1);  // 段底部-左
                Vector3 bottomRight = new Vector3(0.25f, y1);  // 段底部-右
                Vector3 topLeft = new Vector3(-0.25f, y2);     // 段顶部-左
                Vector3 topRight = new Vector3(0.25f, y2);     // 段顶部-右
                // 计算当前段4个顶点在顶点数组中的索引
                int bottomLeftIndex = i * 4 + 1;
                int bottomRightIndex = i * 4 + 2;
                int topLeftIndex = i * 4 + 3;
                int topRightIndex = i * 4 + 4;
                // 将顶点存入顶点数组
                vertices[bottomLeftIndex] = bottomLeft;
                vertices[bottomRightIndex] = bottomRight;
                vertices[topLeftIndex] = topLeft;
                vertices[topRightIndex] = topRight;
                // 生成当前段的2个三角形（组成一个四边形）
                // 第一个三角形：bottomLeft → topRight → bottomRight
                triangles[i * 6] = bottomLeftIndex;
                triangles[i * 6 + 1] = topRightIndex;
                triangles[i * 6 + 2] = bottomRightIndex;
                // 第二个三角形：bottomLeft → topLeft → topRight
                triangles[i * 6 + 3] = bottomLeftIndex;
                triangles[i * 6 + 4] = topLeftIndex;
                triangles[i * 6 + 5] = topRightIndex;
            }
            // ========== 步骤3：生成草叶“顶部的三角形”（让草叶末端变尖） ==========
            // 顶部3个顶点：左、尖顶、右
            vertices[grassMeshSubdivision * 4] = new Vector3(-0.25f, (float)grassMeshSubdivision / (grassMeshSubdivision + 1));
            vertices[grassMeshSubdivision * 4 + 1] = new Vector3(0, 1); // 草叶最顶端（y=1）
            vertices[grassMeshSubdivision * 4 + 2] = new Vector3(0.25f, (float)grassMeshSubdivision / (grassMeshSubdivision + 1));
            // 顶部三角形的索引（连接左→尖顶→右）
            triangles[grassMeshSubdivision * 6] = grassMeshSubdivision * 4;
            triangles[grassMeshSubdivision * 6 + 1] = grassMeshSubdivision * 4 + 1;
            triangles[grassMeshSubdivision * 6 + 2] = grassMeshSubdivision * 4 + 2;
            // ========== 步骤4：将顶点/三角形数据赋值给Mesh，并更新缓存 ==========
            cachedGrassMesh.SetVertices(vertices); // 把顶点数组传入Mesh
            cachedGrassMesh.SetTriangles(triangles, submesh: 0); // 把三角形数组传入Mesh（子网格0）

            oldSubdivision = grassMeshSubdivision; // 更新“上一次的细分值”，避免重复生成
        }

        // 返回缓存好的草叶Mesh
        return cachedGrassMesh;
    }

}
