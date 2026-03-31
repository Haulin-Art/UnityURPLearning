using UnityEngine;
using System.Collections.Generic;

namespace RuntimeGravityMap
{
    /// <summary>
    /// 调试模式枚举
    /// </summary>
    public enum DebugMode
    {
        None,               // 正常输出
        OutputUV,           // 输出UV坐标
        OutputTriangleIndex,// 输出三角形索引
        OutputNormal,       // 输出法线
        OutputTangent,      // 输出切线
        OutputRawGravity,   // 输出原始重力方向
        OutputIntensity     // 输出流动强度
    }

    /// <summary>
    /// 更新模式枚举
    /// </summary>
    public enum UpdateMode
    {
        Manual,             // 手动更新
        EveryFrame,         // 每帧更新
        Interval,           // 定时更新
        OnTransformChange,  // 变换改变时更新
        OnRotationChange    // 仅旋转改变时更新（推荐用于静态网格）
    }

    /// <summary>
    /// 空间索引方法
    /// </summary>
    public enum SpatialIndexMethod
    {
        BruteForce,         // 暴力遍历（适合低面数网格）
        SpatialGrid         // 空间网格索引（适合高面数网格）
    }

    /// <summary>
    /// 运行时重力图生成器
    /// 使用GPU Compute Shader实时生成切线空间重力图
    /// </summary>
    [RequireComponent(typeof(MeshFilter))]
    public class RuntimeGravityMapGenerator : MonoBehaviour
    {
        #region 序列化字段

        [Header("网格源设置")]
        [SerializeField] private MeshFilter _meshFilter;
        [SerializeField] private SkinnedMeshRenderer _skinnedMeshRenderer;
        [SerializeField] private bool _useSkinnedMesh = false;

        [Header("输出设置")]
        [SerializeField] private int _resolution = 256;
        [SerializeField] private Vector3 _gravity = Vector3.down;
        [SerializeField] private int _uvChannel = 0;
        [SerializeField] private bool _useExternalRT = false;
        [SerializeField] private RenderTexture _externalGravityMap;

        [Header("更新设置")]
        [SerializeField] private UpdateMode _updateMode = UpdateMode.Manual;
        [SerializeField] [Range(0.01f, 1f)] private float _updateInterval = 0.1f;
        [SerializeField] private SpatialIndexMethod _indexMethod = SpatialIndexMethod.SpatialGrid;
        [SerializeField] private int _spatialGridSize = 32;

        [Header("调试设置")]
        [SerializeField] private DebugMode _debugMode = DebugMode.None;
        [SerializeField] private bool _showDebugInfo = false;
        [SerializeField] private bool _showDirectionArrows = false;
        [SerializeField] [Range(0.1f, 2f)] private float _arrowScale = 0.5f;

        [Header("Compute Shader引用")]
        [SerializeField] private ComputeShader _computeShaderAsset;

        #endregion

        #region 公共属性

        /// <summary>
        /// 生成的重力图RenderTexture
        /// </summary>
        public RenderTexture GravityMap
        {
            get
            {
                if (_useExternalRT && _externalGravityMap != null)
                    return _externalGravityMap;
                return _gravityMap;
            }
        }

        /// <summary>
        /// 当前分辨率
        /// </summary>
        public int Resolution
        {
            get
            {
                if (_useExternalRT && _externalGravityMap != null)
                    return _externalGravityMap.width;
                return _resolution;
            }
        }

        /// <summary>
        /// 上次更新耗时（毫秒）
        /// </summary>
        public float LastUpdateTimeMs => _lastUpdateTimeMs;

        /// <summary>
        /// 是否已初始化
        /// </summary>
        public bool IsInitialized => _isInitialized;

        #endregion

        #region 私有字段

        private RenderTexture _gravityMap;
        private ComputeShader _computeShader;
        private int _kernelIndex;
        private int _kernelIndexSpatial;

        // 网格数据缓冲区
        private ComputeBuffer _vertexBuffer;
        private ComputeBuffer _normalBuffer;
        private ComputeBuffer _tangentBuffer;
        private ComputeBuffer _uvBuffer;
        private ComputeBuffer _indexBuffer;

        // 空间索引缓冲区
        private ComputeBuffer _spatialIndexOffsetBuffer;
        private ComputeBuffer _spatialIndexCountBuffer;
        private ComputeBuffer _triangleListBuffer;

        // 蒙皮网格临时数据
        private Mesh _bakedMesh;
        private Vector3[] _vertices;
        private Vector3[] _normals;
        private Vector4[] _tangents;
        private Vector2[] _uvs;
        private int[] _indices;

        // 状态追踪
        private bool _isInitialized = false;
        private float _lastUpdateTimeMs = 0f;
        private float _lastUpdateTime = 0f;
        private Vector3 _lastPosition;
        private Quaternion _lastRotation;
        private Vector3 _lastScale;

        // 空间索引数据
        private Dictionary<Vector2Int, List<int>> _spatialIndex;
        private uint[] _spatialIndexOffsets;
        private uint[] _spatialIndexCounts;
        private uint[] _triangleList;

        #endregion

        #region Unity生命周期

        private void Awake()
        {
            Initialize();
        }

        private void Start()
        {
            if (_updateMode == UpdateMode.OnTransformChange)
            {
                _lastPosition = transform.position;
                _lastRotation = transform.rotation;
                _lastScale = transform.localScale;
            }
        }

        private void Update()
        {
            switch (_updateMode)
            {
                case UpdateMode.EveryFrame:
                    UpdateGravityMap();
                    break;

                case UpdateMode.Interval:
                    if (Time.time - _lastUpdateTime >= _updateInterval)
                    {
                        UpdateGravityMap();
                        _lastUpdateTime = Time.time;
                    }
                    break;

                case UpdateMode.OnTransformChange:
                    if (HasTransformChanged())
                    {
                        UpdateGravityMap();
                        _lastPosition = transform.position;
                        _lastRotation = transform.rotation;
                        _lastScale = transform.localScale;
                    }
                    break;

                case UpdateMode.OnRotationChange:
                    if (HasRotationChanged())
                    {
                        UpdateGravityMap();
                        _lastRotation = transform.rotation;
                    }
                    break;
            }
        }

        private void OnDestroy()
        {
            ReleaseResources();
        }

        private void OnDrawGizmosSelected()
        {
            if (_showDirectionArrows && _gravityMap != null)
            {
                DrawDirectionArrows();
            }
        }

        #endregion

        #region 公共方法

        /// <summary>
        /// 初始化生成器
        /// </summary>
        public void Initialize()
        {
            if (_isInitialized) return;

            // 使用直接引用的Compute Shader
            if (_computeShaderAsset != null)
            {
                _computeShader = _computeShaderAsset;
            }
            else
            {
                // 尝试从Resources加载作为备选
                _computeShader = Resources.Load<ComputeShader>("GravityMapBaker");
            }
            
            if (_computeShader == null)
            {
                Debug.LogError("[RuntimeGravityMap] 无法获取 Compute Shader！请在Inspector中指定或确保文件在 Resources 文件夹中！");
                return;
            }

            // 获取内核索引
            _kernelIndex = _computeShader.FindKernel("BakeGravityMap");
            _kernelIndexSpatial = _computeShader.FindKernel("BakeGravityMapWithSpatialIndex");

            // 创建输出纹理
            CreateOutputTexture();

            // 获取网格引用
            if (_meshFilter == null)
                _meshFilter = GetComponent<MeshFilter>();
            if (_skinnedMeshRenderer == null)
                _skinnedMeshRenderer = GetComponent<SkinnedMeshRenderer>();

            _isInitialized = true;

            // 初始更新
            UpdateGravityMap();
        }

        /// <summary>
        /// 更新重力图
        /// </summary>
        public void UpdateGravityMap()
        {
            if (!_isInitialized)
            {
                Initialize();
                if (!_isInitialized) return;
            }

            var stopwatch = System.Diagnostics.Stopwatch.StartNew();

            // 获取网格数据
            Mesh mesh = GetMesh();
            if (mesh == null)
            {
                Debug.LogWarning("[RuntimeGravityMap] 无法获取网格数据！");
                return;
            }

            // 提取网格数据
            ExtractMeshData(mesh);

            // 创建或更新缓冲区
            CreateBuffers();

            // 构建空间索引（如果需要）
            if (_indexMethod == SpatialIndexMethod.SpatialGrid)
            {
                BuildSpatialIndex();
            }

            // 执行Compute Shader
            ExecuteComputeShader();

            stopwatch.Stop();
            _lastUpdateTimeMs = stopwatch.ElapsedMilliseconds;

            if (_showDebugInfo)
            {
                Debug.Log($"[RuntimeGravityMap] 更新完成，耗时: {_lastUpdateTimeMs:F2}ms，分辨率: {_resolution}，三角形数: {_indices.Length / 3}");
            }
        }

        /// <summary>
        /// 设置重力方向
        /// </summary>
        public void SetGravity(Vector3 gravity)
        {
            _gravity = gravity.normalized;
        
            if (_isInitialized && _updateMode == UpdateMode.Manual)
            {
                UpdateGravityMap();
            }
        }

        /// <summary>
        /// 设置分辨率
        /// </summary>
        public void SetResolution(int resolution)
        {
            _resolution = Mathf.ClosestPowerOfTwo(Mathf.Clamp(resolution, 64, 2048));
            CreateOutputTexture();
            if (_isInitialized && _updateMode == UpdateMode.Manual)
            {
                UpdateGravityMap();
            }
        }

        #endregion

        #region 私有方法 - 网格数据

        /// <summary>
        /// 获取网格（支持静态网格和蒙皮网格）
        /// </summary>
        private Mesh GetMesh()
        {
            if (_useSkinnedMesh && _skinnedMeshRenderer != null)
            {
                // 为蒙皮网格创建烘焙后的网格
                if (_bakedMesh == null)
                    _bakedMesh = new Mesh();
                _bakedMesh.Clear();
                _skinnedMeshRenderer.BakeMesh(_bakedMesh);
                return _bakedMesh;
            }
            else if (_meshFilter != null)
            {
                return _meshFilter.sharedMesh;
            }
            return null;
        }

        /// <summary>
        /// 提取网格数据
        /// </summary>
        private void ExtractMeshData(Mesh mesh)
        {
            // 顶点
            _vertices = mesh.vertices;

            // 法线（如果没有则计算）
            _normals = mesh.normals;
            if (_normals == null || _normals.Length == 0)
            {
                mesh.RecalculateNormals();
                _normals = mesh.normals;
            }

            // 切线（如果没有则计算）
            _tangents = mesh.tangents;
            if (_tangents == null || _tangents.Length == 0)
            {
                mesh.RecalculateTangents();
                _tangents = mesh.tangents;
            }

            // UV
            if (_uvChannel == 0)
            {
                _uvs = mesh.uv;
            }
            else if (_uvChannel == 1)
            {
                _uvs = mesh.uv2;
            }
            else
            {
                var uvList = new List<Vector2>();
                mesh.GetUVs(_uvChannel, uvList);
                _uvs = uvList.ToArray();
            }

            // 索引
            _indices = mesh.triangles;
        }

        #endregion

        #region 私有方法 - GPU缓冲区

        /// <summary>
        /// 创建输出纹理
        /// </summary>
        private void CreateOutputTexture()
        {
            // 使用外部RT时不创建内部RT
            if (_useExternalRT && _externalGravityMap != null)
            {
                _gravityMap = null;
                return;
            }

            if (_gravityMap != null)
            {
                _gravityMap.Release();
            }

            _gravityMap = new RenderTexture(_resolution, _resolution, 0, RenderTextureFormat.ARGBFloat);
            _gravityMap.enableRandomWrite = true;
            _gravityMap.wrapMode = TextureWrapMode.Clamp;
            _gravityMap.filterMode = FilterMode.Bilinear;
            _gravityMap.Create();
        }

        /// <summary>
        /// 创建GPU缓冲区
        /// </summary>
        private void CreateBuffers()
        {
            // 释放旧缓冲区
            ReleaseBuffers();

            // 创建新缓冲区
            _vertexBuffer = new ComputeBuffer(_vertices.Length, sizeof(float) * 3);
            _normalBuffer = new ComputeBuffer(_normals.Length, sizeof(float) * 3);
            _tangentBuffer = new ComputeBuffer(_tangents.Length, sizeof(float) * 4);
            _uvBuffer = new ComputeBuffer(_uvs.Length, sizeof(float) * 2);
            _indexBuffer = new ComputeBuffer(_indices.Length, sizeof(uint));

            // 上传数据
            _vertexBuffer.SetData(_vertices);
            _normalBuffer.SetData(_normals);
            _tangentBuffer.SetData(_tangents);
            _uvBuffer.SetData(_uvs);
            _indexBuffer.SetData(_indices);
        }

        /// <summary>
        /// 释放GPU缓冲区
        /// </summary>
        private void ReleaseBuffers()
        {
            _vertexBuffer?.Release();
            _normalBuffer?.Release();
            _tangentBuffer?.Release();
            _uvBuffer?.Release();
            _indexBuffer?.Release();
            _spatialIndexOffsetBuffer?.Release();
            _spatialIndexCountBuffer?.Release();
            _triangleListBuffer?.Release();

            _vertexBuffer = null;
            _normalBuffer = null;
            _tangentBuffer = null;
            _uvBuffer = null;
            _indexBuffer = null;
            _spatialIndexOffsetBuffer = null;
            _spatialIndexCountBuffer = null;
            _triangleListBuffer = null;
        }

        /// <summary>
        /// 释放所有资源
        /// </summary>
        private void ReleaseResources()
        {
            ReleaseBuffers();

            if (_gravityMap != null)
            {
                _gravityMap.Release();
                _gravityMap = null;
            }

            if (_bakedMesh != null)
            {
                Destroy(_bakedMesh);
                _bakedMesh = null;
            }
        }

        #endregion

        #region 私有方法 - 空间索引

        /// <summary>
        /// 构建空间索引
        /// </summary>
        private void BuildSpatialIndex()
        {
            int gridSize = _spatialGridSize;
            int cellCount = gridSize * gridSize;
            int triangleCount = _indices.Length / 3;

            // 初始化空间索引字典
            _spatialIndex = new Dictionary<Vector2Int, List<int>>();

            // 遍历所有三角形，记录每个网格单元覆盖的三角形
            for (int triIndex = 0; triIndex < triangleCount; triIndex++)
            {
                int i0 = _indices[triIndex * 3 + 0];
                int i1 = _indices[triIndex * 3 + 1];
                int i2 = _indices[triIndex * 3 + 2];

                Vector2 uv0 = _uvs[i0];
                Vector2 uv1 = _uvs[i1];
                Vector2 uv2 = _uvs[i2];

                // 计算UV包围盒
                float minX = Mathf.Min(uv0.x, uv1.x, uv2.x);
                float maxX = Mathf.Max(uv0.x, uv1.x, uv2.x);
                float minY = Mathf.Min(uv0.y, uv1.y, uv2.y);
                float maxY = Mathf.Max(uv0.y, uv1.y, uv2.y);

                // 计算覆盖的网格单元范围
                int minGX = Mathf.FloorToInt(minX * gridSize);
                int maxGX = Mathf.FloorToInt(maxX * gridSize);
                int minGY = Mathf.FloorToInt(minY * gridSize);
                int maxGY = Mathf.FloorToInt(maxY * gridSize);

                // 添加到覆盖的网格单元
                for (int gx = minGX; gx <= maxGX; gx++)
                {
                    for (int gy = minGY; gy <= maxGY; gy++)
                    {
                        Vector2Int key = new Vector2Int(gx, gy);
                        if (!_spatialIndex.ContainsKey(key))
                        {
                            _spatialIndex[key] = new List<int>();
                        }
                        _spatialIndex[key].Add(triIndex);
                    }
                }
            }

            // 转换为数组格式供GPU使用
            _spatialIndexOffsets = new uint[cellCount];
            _spatialIndexCounts = new uint[cellCount];
            List<uint> triangleListTemp = new List<uint>();

            for (int y = 0; y < gridSize; y++)
            {
                for (int x = 0; x < gridSize; x++)
                {
                    int cellIndex = y * gridSize + x;
                    Vector2Int key = new Vector2Int(x, y);

                    _spatialIndexOffsets[cellIndex] = (uint)triangleListTemp.Count;

                    if (_spatialIndex.TryGetValue(key, out List<int> triangles))
                    {
                        _spatialIndexCounts[cellIndex] = (uint)triangles.Count;
                        foreach (int tri in triangles)
                        {
                            triangleListTemp.Add((uint)tri);
                        }
                    }
                    else
                    {
                        _spatialIndexCounts[cellIndex] = 0;
                    }
                }
            }

            _triangleList = triangleListTemp.ToArray();

            // 创建GPU缓冲区
            _spatialIndexOffsetBuffer = new ComputeBuffer(cellCount, sizeof(uint));
            _spatialIndexCountBuffer = new ComputeBuffer(cellCount, sizeof(uint));
            _triangleListBuffer = new ComputeBuffer(_triangleList.Length, sizeof(uint));

            _spatialIndexOffsetBuffer.SetData(_spatialIndexOffsets);
            _spatialIndexCountBuffer.SetData(_spatialIndexCounts);
            _triangleListBuffer.SetData(_triangleList);
        }

        #endregion

        #region 私有方法 - Compute Shader执行

        /// <summary>
        /// 执行Compute Shader
        /// </summary>
        private void ExecuteComputeShader()
        {
            // 获取当前使用的RT
            RenderTexture targetRT = GravityMap;
            if (targetRT == null)
            {
                Debug.LogError("[RuntimeGravityMap] 目标RenderTexture为空！");
                return;
            }

            // 使用目标RT的分辨率
            int currentResolution = targetRT.width;

            // 计算相对于物体的重力方向
            // 物体旋转多少度，重力方向就反向旋转多少度
            // 例如：物体绕X轴旋转45度，重力相对网格就是旋转-45度
            Quaternion inverseRotation = Quaternion.Inverse(transform.rotation);
            Vector3 relativeGravity = inverseRotation * _gravity.normalized;

            // 设置公共参数
            _computeShader.SetInt("_Resolution", currentResolution);
            _computeShader.SetVector("_WorldGravity", relativeGravity);
            _computeShader.SetInt("_DebugMode", (int)_debugMode);
            _computeShader.SetInt("_TriangleCount", _indices.Length / 3);

            // 设置网格数据缓冲区
            _computeShader.SetBuffer(_kernelIndex, "_Vertices", _vertexBuffer);
            _computeShader.SetBuffer(_kernelIndex, "_Normals", _normalBuffer);
            _computeShader.SetBuffer(_kernelIndex, "_Tangents", _tangentBuffer);
            _computeShader.SetBuffer(_kernelIndex, "_UVs", _uvBuffer);
            _computeShader.SetBuffer(_kernelIndex, "_Indices", _indexBuffer);
            _computeShader.SetTexture(_kernelIndex, "_OutputTexture", targetRT);

            // 计算线程组大小
            int threadGroups = Mathf.CeilToInt(currentResolution / 8.0f);

            // 根据索引方法选择内核
            if (_indexMethod == SpatialIndexMethod.SpatialGrid && _spatialIndexOffsetBuffer != null)
            {
                // 设置空间索引参数
                _computeShader.SetInt("_SpatialGridSize", _spatialGridSize);
                _computeShader.SetBuffer(_kernelIndexSpatial, "_Vertices", _vertexBuffer);
                _computeShader.SetBuffer(_kernelIndexSpatial, "_Normals", _normalBuffer);
                _computeShader.SetBuffer(_kernelIndexSpatial, "_Tangents", _tangentBuffer);
                _computeShader.SetBuffer(_kernelIndexSpatial, "_UVs", _uvBuffer);
                _computeShader.SetBuffer(_kernelIndexSpatial, "_Indices", _indexBuffer);
                _computeShader.SetBuffer(_kernelIndexSpatial, "_SpatialIndexOffsets", _spatialIndexOffsetBuffer);
                _computeShader.SetBuffer(_kernelIndexSpatial, "_SpatialIndexCounts", _spatialIndexCountBuffer);
                _computeShader.SetBuffer(_kernelIndexSpatial, "_TriangleList", _triangleListBuffer);
                _computeShader.SetTexture(_kernelIndexSpatial, "_OutputTexture", targetRT);

                _computeShader.Dispatch(_kernelIndexSpatial, threadGroups, threadGroups, 1);
            }
            else
            {
                // 使用暴力遍历内核
                _computeShader.Dispatch(_kernelIndex, threadGroups, threadGroups, 1);
            }
        }

        #endregion

        #region 私有方法 - 调试

        /// <summary>
        /// 检查变换是否改变
        /// </summary>
        private bool HasTransformChanged()
        {
            return transform.position != _lastPosition ||
                   transform.rotation != _lastRotation ||
                   transform.localScale != _lastScale;
        }

        /// <summary>
        /// 检查旋转是否改变
        /// </summary>
        private bool HasRotationChanged()
        {
            return transform.rotation != _lastRotation;
        }

        /// <summary>
        /// 绘制方向箭头（调试用）
        /// </summary>
        private void DrawDirectionArrows()
        {
            if (_gravityMap == null || _vertices == null) return;

            // 采样一些点绘制方向箭头
            int sampleCount = Mathf.Min(100, _vertices.Length);
            int step = Mathf.Max(1, _vertices.Length / sampleCount);

            for (int i = 0; i < _vertices.Length; i += step)
            {
                Vector2 uv = _uvs[i];
                Vector3 worldPos = transform.TransformPoint(_vertices[i]);

                // 从重力图采样
                RenderTexture.active = _gravityMap;
                Texture2D tempTex = new Texture2D(1, 1, TextureFormat.RGBAFloat, false);
                tempTex.ReadPixels(new Rect(uv.x * _resolution, uv.y * _resolution, 1, 1), 0, 0);
                tempTex.Apply();
                Color data = tempTex.GetPixel(0, 0);
                Destroy(tempTex);
                RenderTexture.active = null;

                if (data.a > 0.5f)
                {
                    // 绘制流动方向
                    Vector2 flowDir = new Vector2(data.r, data.g);
                    float intensity = data.b;

                    // 在世界空间中绘制箭头
                    Vector3 tangent = transform.TransformDirection(_tangents[i].xyz().normalized);
                    Vector3 normal = transform.TransformDirection(_normals[i].normalized);
                    Vector3 bitangent = Vector3.Cross(normal, tangent) * _tangents[i].w;

                    Vector3 flowWorld = tangent * flowDir.x + bitangent * flowDir.y;

                    Gizmos.color = Color.HSVToRGB(intensity * 0.3f, 1, 1);
                    Gizmos.DrawRay(worldPos, flowWorld * _arrowScale);
                }
            }
        }

        #endregion
    }

    /// <summary>
    /// Vector4扩展方法
    /// </summary>
    public static class Vector4Extensions
    {
        public static Vector3 xyz(this Vector4 v)
        {
            return new Vector3(v.x, v.y, v.z);
        }
    }
}
