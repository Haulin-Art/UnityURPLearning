using UnityEngine;

namespace RuntimeGravityMap
{
    /// <summary>
    /// 实时重力图生成器
    /// 基于物体空间位置图，通过差分采样计算切线空间重力方向
    /// </summary>
    [ExecuteInEditMode]
    public class RealTimeGravityMapGenerator : MonoBehaviour
    {
        [Header("必需资源")]
        [Tooltip("物体空间位置图：xyz=位置，w=有效标记")]
        public Texture2D osPosMap;
        public ComputeShader computeShader;

        [Header("输出")]
        [Tooltip("使用外部RT（勾选后不会自动创建RT）")]
        public bool useExternalRT = false;
        [Tooltip("输出重力图")]
        public RenderTexture gravityMap;

        [Header("重力")]
        public Vector3 worldGravity = Vector3.down;

        [Header("轮廓扩展")]
        [Tooltip("是否启用轮廓扩展")]
        public bool enableOutlineExtend = false;
        [Tooltip("轮廓扩展宽度（像素）")]
        [Range(1, 16)] public int outlineWidth = 4;
        [Tooltip("SDF图：单通道，存储到UV岛边界的距离")]
        public Texture2D sdfMap;
        [Tooltip("SDF梯度图：xy=梯度方向（指向UV岛边界）")]
        public Texture2D sdfGradientMap;

        [Tooltip("UV跳跃贴图：RG:跳跃目标UV, Z:跳跃边缘, A:UV范围")]
        public Texture2D uvJumpMap;        

        [Header("调试")]
        [Tooltip("勾选后立即生成一次")]
        public bool debugGenerate = false;
        [Tooltip("显示调试信息")]
        public bool showDebugLog = false;

        [Header("更新模式")]
        public bool updateEveryFrame = false;
        [Range(0.01f, 1f)] public float updateInterval = 0.1f;

        // 私有
        private int _kernelCompute;
        private int _kernelExtend;
        private RenderTexture _tempGravityMap;
        private RenderTexture _internalGravityMap;  // 内部创建的RT
        private Quaternion _lastRotation;
        private float _lastTime;
        private bool _isInitialized = false;

#if UNITY_EDITOR
        private void OnValidate()
        {
            if (debugGenerate)
            {
                debugGenerate = false;
                Init();
                UpdateGravityMap();
                UnityEditor.EditorUtility.SetDirty(this);
            }
        }
#endif

        private void Awake()
        {
            Init();
        }

        private void Start()
        {
            _lastRotation = transform.rotation;
        }

        private void Update()
        {
            if (transform.rotation != _lastRotation)
            {
                UpdateGravityMap();
                _lastRotation = transform.rotation;
            }
            else if (updateEveryFrame || (updateInterval > 0 && Time.time - _lastTime >= updateInterval))
            {
                UpdateGravityMap();
                _lastTime = Time.time;
            }
        }

        public void Init()
        {
            if (osPosMap == null)
            {
                if (showDebugLog) Debug.LogWarning("[RealTimeGravityMap] osPosMap为空！");
                return;
            }

            if (computeShader == null)
            {
                if (showDebugLog) Debug.LogWarning("[RealTimeGravityMap] computeShader为空！");
                return;
            }

            _kernelCompute = computeShader.FindKernel("ComputeGravityMap");
            _kernelExtend = computeShader.FindKernel("ExtendOutline");

            int size = osPosMap.width;

            // 只有在不使用外部RT时才创建内部RT
            if (!useExternalRT)
            {
                if (_internalGravityMap == null || _internalGravityMap.width != size)
                {
                    if (_internalGravityMap != null) _internalGravityMap.Release();
                    _internalGravityMap = new RenderTexture(size, size, 0, RenderTextureFormat.RGFloat);
                    _internalGravityMap.enableRandomWrite = true;
                    _internalGravityMap.wrapMode = TextureWrapMode.Clamp;
                    _internalGravityMap.filterMode = FilterMode.Bilinear;
                    _internalGravityMap.Create();
                }
                gravityMap = _internalGravityMap;
            }
            else
            {
                // 使用外部RT时检查
                if (gravityMap == null)
                {
                    if (showDebugLog) Debug.LogWarning("[RealTimeGravityMap] 外部RT为空！");
                    return;
                }
                if (!gravityMap.enableRandomWrite)
                {
                    if (showDebugLog) Debug.LogWarning("[RealTimeGravityMap] 外部RT需要启用enableRandomWrite！");
                }
            }

            // 创建临时纹理（用于轮廓扩展）
            if (enableOutlineExtend && (_tempGravityMap == null || _tempGravityMap.width != size))
            {
                if (_tempGravityMap != null) _tempGravityMap.Release();
                _tempGravityMap = new RenderTexture(size, size, 0, RenderTextureFormat.RGFloat);
                _tempGravityMap.enableRandomWrite = true;
                _tempGravityMap.wrapMode = TextureWrapMode.Clamp;
                _tempGravityMap.filterMode = FilterMode.Point;
                _tempGravityMap.Create();
            }

            _isInitialized = true;

            if (showDebugLog) Debug.Log($"[RealTimeGravityMap] 初始化完成，分辨率: {size}, gravityMap: {gravityMap}");
        }

        public void UpdateGravityMap()
        {
            if (!_isInitialized)
            {
                Init();
                if (!_isInitialized) return;
            }

            if (osPosMap == null || computeShader == null || gravityMap == null || uvJumpMap == null)
            {
                if (showDebugLog) Debug.LogWarning("[RealTimeGravityMap] 缺少必要资源！");
                return;
            }

            // 计算相对重力
            Vector3 relativeGravity = Quaternion.Inverse(transform.rotation) * worldGravity.normalized;

            int size = gravityMap.width;
            int groups = Mathf.CeilToInt(size / 8f);

            if (showDebugLog) Debug.Log($"[RealTimeGravityMap] 开始计算，size: {size}, groups: {groups}, kernel: {_kernelCompute}");

            // 设置公共参数
            computeShader.SetFloat("_TexSize", (float)size);
            computeShader.SetVector("_RelativeGravity", relativeGravity);

            // Pass 1: 计算重力图
            RenderTexture targetRT = enableOutlineExtend && _tempGravityMap != null ? _tempGravityMap : gravityMap;
            computeShader.SetTexture(_kernelCompute, "_OSPosMap", osPosMap);
            computeShader.SetTexture(_kernelCompute, "_GravityMap", targetRT);
            computeShader.SetTexture(_kernelCompute, "_UVJumpMap", uvJumpMap);
            computeShader.Dispatch(_kernelCompute, groups, groups, 1);

            if (showDebugLog) Debug.Log($"[RealTimeGravityMap] Pass 1 完成，targetRT: {targetRT}");

            // Pass 2: 轮廓扩展
            if (enableOutlineExtend && _tempGravityMap != null && sdfMap != null && sdfGradientMap != null)
            {
                computeShader.SetFloat("_OutlineWidth", (float)outlineWidth);
                computeShader.SetTexture(_kernelExtend, "_GravityMap", gravityMap);
                computeShader.SetTexture(_kernelExtend, "_GravityMapRead", _tempGravityMap);
                computeShader.SetTexture(_kernelExtend, "_SDFMap", sdfMap);
                computeShader.SetTexture(_kernelExtend, "_SDFGradientMap", sdfGradientMap);
                computeShader.Dispatch(_kernelExtend, groups, groups, 1);

                if (showDebugLog) Debug.Log($"[RealTimeGravityMap] Pass 2 完成");
            }

            if (showDebugLog) Debug.Log($"[RealTimeGravityMap] 更新完成，相对重力: {relativeGravity}");
        }

        private void OnDestroy()
        {
            // 只释放内部创建的RT
            if (_internalGravityMap != null)
            {
                _internalGravityMap.Release();
                _internalGravityMap = null;
            }
            if (_tempGravityMap != null)
            {
                _tempGravityMap.Release();
                _tempGravityMap = null;
            }
            _isInitialized = false;
        }
    }
}
