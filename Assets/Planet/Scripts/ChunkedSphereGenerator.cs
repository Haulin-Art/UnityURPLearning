using UnityEngine;
using UnityEngine.Rendering;
using System.Collections.Generic;

[ExecuteInEditMode]
public class CubedSphereGenerator : MonoBehaviour
{
    [Header("球体设置")]
    [Range(0.5f, 50f)] public float radius = 5f;
    [Range(1, 5)] public int chunkLevel = 2;  // 分块等级：1=6面，2=24面，3=96面
    
    [Header("渲染设置")]
    public Material quadMaterial;
    public ComputeShader cullingComputeShader;
    
    [Header("剔除设置")]
    [Range(0.01f, 1f)] public float updateInterval = 0.1f;
    public bool enableCulling = true;
    public float cullDistance = 100f;
    
    [Header("调试")]
    public bool showGizmos = true;
    public Color gizmoColor = new Color(1, 0.5f, 0, 0.3f);
    
    // 计算着色器常量
    private const int THREADS_X = 64;
    private const string CULL_KERNEL = "CSMain";
    
    // GPU数据结构
    private struct InstanceData
    {
        public Vector3 position;      // 世界空间位置
        public Vector3 forward;       // 前向方向（正方形法线）
        public Vector3 right;         // 右方向
        public Vector3 up;            // 上方向
        public float scale;           // 缩放
        public int isVisible;         // 是否可见
        
        public static int Size => sizeof(float) * 10 + sizeof(int);
    }
    
    // CPU数据
    private List<InstanceData> _instanceDataList = new List<InstanceData>();
    private InstanceData[] _instanceDataArray;
    
    // GPU缓冲区
    private ComputeBuffer _instanceBuffer;
    private ComputeBuffer _argsBuffer;
    private ComputeBuffer _counterBuffer;
    
    // 渲染组件
    private Mesh _quadMesh;
    private MaterialPropertyBlock _materialProps;
    
    // 状态
    private int _instanceCount = 0;
    private int _visibleCount = 0;
    private Camera _mainCamera;
    private float _lastUpdateTime;
    private bool _initialized = false;
    
    void Start()
    {
        Initialize();
        GenerateSphere();
        SetupBuffers();
    }
    
    void Update()
    {
        if (!_initialized || _instanceCount == 0) return;
        
        // 定期更新剔除
        if (Time.time - _lastUpdateTime >= updateInterval)
        {
            UpdateCulling();
            _lastUpdateTime = Time.time;
        }
        
        // 渲染可见实例
        RenderInstances();
    }
    
    void OnValidate()
    {
        // 在编辑器中自动更新
        #if UNITY_EDITOR
        if (!Application.isPlaying && enabled && gameObject.activeInHierarchy)
        {
            RegenerateSphere();
        }
        #endif
    }
    
    [ContextMenu("重新生成球体")]
    public void RegenerateSphere()
    {
        Cleanup();
        Initialize();
        GenerateSphere();
        SetupBuffers();
    }
    
    [ContextMenu("清除球体")]
    public void Cleanup()
    {
        // 释放缓冲区
        if (_instanceBuffer != null)
        {
            _instanceBuffer.Release();
            _instanceBuffer = null;
        }
        
        if (_argsBuffer != null)
        {
            _argsBuffer.Release();
            _argsBuffer = null;
        }
        
        if (_counterBuffer != null)
        {
            _counterBuffer.Release();
            _counterBuffer = null;
        }
        
        // 清空数据
        _instanceDataList.Clear();
        _instanceDataArray = null;
        _instanceCount = 0;
        _visibleCount = 0;
        _initialized = false;
    }
    
    void OnDestroy()
    {
        Cleanup();
    }
    
    private void Initialize()
    {
        if (_initialized) return;
        
        // 获取主摄像机
        _mainCamera = Camera.main;
        if (_mainCamera == null)
        {
            _mainCamera = FindObjectOfType<Camera>();
        }
        
        // 获取正方形网格
        _quadMesh = QuadMeshGenerator.GetUnitQuad();
        
        // 初始化材质属性块
        _materialProps = new MaterialPropertyBlock();
        
        // 创建默认材质
        if (quadMaterial == null)
        {
            CreateDefaultMaterial();
        }
        
        _initialized = true;
    }
    
    private void CreateDefaultMaterial()
    {
        // 创建一个简单的支持GPU实例化的材质
        Shader shader = Shader.Find("Universal Render Pipeline/Lit");
        if (shader == null)
        {
            shader = Shader.Find("Standard");
        }
        
        if (shader != null)
        {
            quadMaterial = new Material(shader);
            quadMaterial.name = "Quad Instance Material";
            quadMaterial.enableInstancing = true;
            quadMaterial.color = new Color(0.8f, 0.4f, 0.6f, 1f);
        }
        else
        {
            Debug.LogError("无法找到合适的着色器！");
        }
    }
    
    private void GenerateSphere()
    {
        _instanceDataList.Clear();
        
        // 计算分块数
        int chunksPerFace = (int)Mathf.Pow(4, chunkLevel - 1);
        int chunksPerSide = (int)Mathf.Sqrt(chunksPerFace);
        float faceSize = 2f; // 立方体面的大小（-1到1）
        float chunkSize = faceSize / chunksPerSide;
        
        Debug.Log($"生成球体: 分块等级={chunkLevel}, 每面分块数={chunksPerFace}, 总方块数={6 * chunksPerFace}");
        
        // 六个面的方向
        Vector3[] faceDirections = 
        {
            Vector3.forward,  // 前
            Vector3.back,     // 后
            Vector3.right,    // 右
            Vector3.left,     // 左
            Vector3.up,       // 上
            Vector3.down      // 下
        };
        
        // 为每个面生成分块
        for (int faceIndex = 0; faceIndex < 6; faceIndex++)
        {
            Vector3 faceNormal = faceDirections[faceIndex];
            
            // 确定该面的局部坐标系
            Vector3 localRight, localUp;
            GetLocalAxes(faceNormal, out localRight, out localUp);
            
            // 在该面上生成分块网格
            for (int y = 0; y < chunksPerSide; y++)
            {
                for (int x = 0; x < chunksPerSide; x++)
                {
                    // 计算正方形在面上的中心位置（在立方体坐标系中）
                    float u = (x + 0.5f) * chunkSize - 1f;
                    float v = (y + 0.5f) * chunkSize - 1f;
                    
                    // 立方体坐标系中的位置
                    Vector3 cubePosition = faceNormal + localRight * u + localUp * v;
                    
                    // 将立方体位置映射到球面
                    Vector3 spherePosition = cubePosition.normalized * radius;
                    
                    // 计算正方形在球面上的旋转
                    // 前向：球面法线（从球心指向外）
                    Vector3 forward = cubePosition.normalized;
                    
                    // 右方向：面局部右方向在球面切线上的投影
                    Vector3 right = Vector3.ProjectOnPlane(localRight, forward).normalized;
                    if (right.magnitude < 0.001f)
                    {
                        // 如果投影太小，使用备用方向
                        right = Vector3.Cross(forward, Vector3.up).normalized;
                        if (right.magnitude < 0.001f)
                        {
                            right = Vector3.Cross(forward, Vector3.right).normalized;
                        }
                    }
                    
                    // 上方向：确保正交
                    Vector3 up = Vector3.Cross(right, forward).normalized;
                    
                    // 计算正方形大小（在球面上会有些变形）
                    float chunkScale = chunkSize * radius * 0.5f;
                    
                    // 添加到实例列表
                    InstanceData data = new InstanceData
                    {
                        position = spherePosition,
                        forward = forward,
                        right = right,
                        up = up,
                        scale = chunkScale,
                        isVisible = 1
                    };
                    
                    _instanceDataList.Add(data);
                }
            }
        }
        
        // 转换为数组
        _instanceCount = _instanceDataList.Count;
        _instanceDataArray = _instanceDataList.ToArray();
        
        Debug.Log($"生成了 {_instanceCount} 个正方形实例");
    }
    
    private void GetLocalAxes(Vector3 normal, out Vector3 right, out Vector3 up)
    {
        // 根据法线方向确定局部坐标系
        if (Mathf.Abs(normal.y) > 0.707f) // 上下面
        {
            right = Vector3.right;
            up = Vector3.forward;
            
            // 下面需要翻转
            if (normal.y < 0)
            {
                up = Vector3.back;
            }
        }
        else if (Mathf.Abs(normal.z) > 0.707f) // 前后面
        {
            right = Vector3.right;
            up = Vector3.up;
            
            // 后面需要翻转
            if (normal.z < 0)
            {
                right = Vector3.left;
            }
        }
        else // 左右面
        {
            right = Vector3.forward;
            up = Vector3.up;
            
            // 左面需要翻转
            if (normal.x < 0)
            {
                right = Vector3.back;
            }
        }
    }
    
    private void SetupBuffers()
    {
        if (_instanceCount == 0) return;
        
        // 创建实例数据缓冲区
        if (_instanceBuffer != null) _instanceBuffer.Release();
        _instanceBuffer = new ComputeBuffer(_instanceCount, InstanceData.Size);
        _instanceBuffer.SetData(_instanceDataArray);
        
        // 创建间接绘制参数缓冲区
        if (_argsBuffer != null) _argsBuffer.Release();
        _argsBuffer = new ComputeBuffer(5, sizeof(uint), ComputeBufferType.IndirectArguments);
        
        // 设置初始绘制参数
        uint[] args = new uint[5]
        {
            _quadMesh.GetIndexCount(0),  // 索引数量
            (uint)_instanceCount,        // 实例数量
            _quadMesh.GetIndexStart(0),  // 起始索引
            _quadMesh.GetBaseVertex(0),  // 基础顶点
            0                            // 起始实例
        };
        _argsBuffer.SetData(args);
        
        // 创建计数器缓冲区（用于计算着色器）
        if (_counterBuffer != null) _counterBuffer.Release();
        _counterBuffer = new ComputeBuffer(1, sizeof(int), ComputeBufferType.Raw);
        
        // 设置材质属性
        _materialProps.SetBuffer("_InstanceBuffer", _instanceBuffer);
        _materialProps.SetFloat("_Radius", radius);
    }
    
    private void UpdateCulling()
    {
        if (!enableCulling || cullingComputeShader == null || _mainCamera == null)
        {
            // 不使用剔除，所有实例都可见
            _visibleCount = _instanceCount;
            return;
        }
        
        // 计算视锥平面
        Plane[] planes = GeometryUtility.CalculateFrustumPlanes(_mainCamera);
        Vector4[] planeData = new Vector4[6];
        
        for (int i = 0; i < 6; i++)
        {
            planeData[i] = new Vector4(planes[i].normal.x, planes[i].normal.y, planes[i].normal.z, planes[i].distance);
        }
        
        // 获取计算着色器内核
        int kernel = cullingComputeShader.FindKernel(CULL_KERNEL);
        
        // 设置计算着色器参数
        cullingComputeShader.SetBuffer(kernel, "_InstanceBuffer", _instanceBuffer);
        cullingComputeShader.SetBuffer(kernel, "_ArgsBuffer", _argsBuffer);
        cullingComputeShader.SetBuffer(kernel, "_CounterBuffer", _counterBuffer);
        
        // 设置视锥平面
        cullingComputeShader.SetVectorArray("_FrustumPlanes", planeData);
        cullingComputeShader.SetVector("_CameraPosition", _mainCamera.transform.position);
        cullingComputeShader.SetFloat("_CullDistance", cullDistance);
        cullingComputeShader.SetInt("_InstanceCount", _instanceCount);
        
        // 执行计算着色器
        int threadGroups = Mathf.CeilToInt(_instanceCount / (float)THREADS_X);
        cullingComputeShader.Dispatch(kernel, threadGroups, 1, 1);
        
        // 读取可见实例数量（如果需要）
        // int[] counter = new int[1];
        // _counterBuffer.GetData(counter);
        // _visibleCount = counter[0];
        
        // 为了简单，这里假设所有实例都可见
        _visibleCount = _instanceCount;
    }
    
    private void RenderInstances()
    {
        if (_visibleCount == 0 || quadMaterial == null || _quadMesh == null || _instanceBuffer == null)
            return;
        
        // 设置材质属性
        _materialProps.SetMatrix("_ObjectToWorld", Matrix4x4.identity);
        _materialProps.SetMatrix("_WorldToObject", Matrix4x4.identity);
        _materialProps.SetFloat("_Time", Time.time);
        
        // 使用GPU实例化绘制
        Graphics.DrawMeshInstancedProcedural(
            _quadMesh,                // 网格
            0,                        // 子网格索引
            quadMaterial,             // 材质
            new Bounds(transform.position, Vector3.one * radius * 2f), // 包围盒
            _visibleCount,            // 实例数量
            _materialProps,           // 材质属性块
            ShadowCastingMode.On,     // 投射阴影
            true,                     // 接收阴影
            gameObject.layer          // 层级
        );
    }
    
    void OnDrawGizmosSelected()
    {
        if (!showGizmos || _instanceDataList == null || _instanceDataList.Count == 0) return;
        
        Gizmos.color = gizmoColor;
        Gizmos.matrix = transform.localToWorldMatrix;
        
        // 绘制球体边界
        Gizmos.DrawWireSphere(Vector3.zero, radius);
        
        // 绘制一些实例（限制数量避免卡顿）
        int maxToDraw = Mathf.Min(100, _instanceDataList.Count);
        for (int i = 0; i < maxToDraw; i++)
        {
            InstanceData data = _instanceDataList[i];
            
            // 计算变换矩阵
            Matrix4x4 trs = Matrix4x4.TRS(
                data.position,
                Quaternion.LookRotation(data.forward, data.up),
                Vector3.one * data.scale
            );
            
            // 绘制正方形框
            DrawGizmoQuad(trs);
            
            // 绘制法线
            Gizmos.color = Color.red;
            Gizmos.DrawLine(data.position, data.position + data.forward * data.scale * 0.5f);
            Gizmos.color = gizmoColor;
        }
        
        Gizmos.matrix = Matrix4x4.identity;
    }
    
    private void DrawGizmoQuad(Matrix4x4 matrix)
    {
        // 正方形的四个角
        Vector3[] corners = new Vector3[4]
        {
            matrix.MultiplyPoint(new Vector3(-0.5f, -0.5f, 0)),
            matrix.MultiplyPoint(new Vector3(0.5f, -0.5f, 0)),
            matrix.MultiplyPoint(new Vector3(0.5f, 0.5f, 0)),
            matrix.MultiplyPoint(new Vector3(-0.5f, 0.5f, 0))
        };
        
        // 绘制四边形边框
        for (int i = 0; i < 4; i++)
        {
            int next = (i + 1) % 4;
            Gizmos.DrawLine(corners[i], corners[next]);
        }
    }
    
    [ContextMenu("打印信息")]
    public void PrintInfo()
    {
        Debug.Log($"球体信息:");
        Debug.Log($"- 半径: {radius}");
        Debug.Log($"- 分块等级: {chunkLevel}");
        Debug.Log($"- 总方块数: {_instanceCount}");
        Debug.Log($"- 是否启用剔除: {enableCulling}");
        Debug.Log($"- 更新间隔: {updateInterval}");
    }
}