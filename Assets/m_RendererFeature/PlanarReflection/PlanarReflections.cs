using System;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Serialization;
using Unity.Mathematics;

namespace UnityEngine.Rendering.Universal
{
    // 确保该脚本在编辑模式和运行模式下都能执行（方便调试）
    [ExecuteAlways]
    public class PlanarReflections : MonoBehaviour
    {
        #region 枚举与设置类定义
        [Serializable]
        public enum ResolutionMulltiplier
        {
            Full,   // 全分辨率
            Half,   // 一半分辨率
            Third,  // 三分之一分辨率
            Quarter // 四分之一分辨率
        }

        [Serializable]
        public class PlanarReflectionSettings
        {
            public ResolutionMulltiplier m_ResolutionMultiplier = ResolutionMulltiplier.Third;
            public float m_ClipPlaneOffset = 0.07f; // 裁剪平面偏移，防止伪影
            public LayerMask m_ReflectLayers = -1;   // 哪些层会被反射
            public bool m_Shadows;                   // 反射中是否渲染阴影
        }
        #endregion

        #region 公共变量
        [SerializeField]
        public PlanarReflectionSettings m_settings = new PlanarReflectionSettings();

        public GameObject target;          // 反射平面所在的物体（如水面）
        [FormerlySerializedAs("camOffset")]
        public float m_planeOffset;        // 平面位置的微调偏移量
        #endregion

        #region 私有变量
        private static Camera _reflectionCamera;       // 用于渲染反射的摄像机
        private RenderTexture _reflectionTexture;      // 存储反射结果的RT
        private readonly int _planarReflectionTextureId = Shader.PropertyToID("_PlanarReflectionTexture"); // Shader全局纹理ID
        private int2 _oldReflectionTextureSize;        // 记录旧的RT尺寸，用于动态调整

        // 事件：在开始渲染平面反射时触发（供外部注入逻辑）
        public static event Action<ScriptableRenderContext, Camera> BeginPlanarReflections;
        #endregion

        #region 生命周期与清理
        private void OnEnable()
        {
            // 注册到URP的渲染管线回调中
            RenderPipelineManager.beginCameraRendering += ExecutePlanarReflections;
        }
        
        private void OnDisable()
        {
            Cleanup();
        }

        private void OnDestroy()
        {
            Cleanup();
        }

        private void Cleanup()
        {
            // 注销回调
            RenderPipelineManager.beginCameraRendering -= ExecutePlanarReflections;

            // 销毁反射摄像机
            if(_reflectionCamera)
            {
                _reflectionCamera.targetTexture = null;
                SafeDestroy(_reflectionCamera.gameObject);
            }
            // 释放临时RT
            if (_reflectionTexture)
            {
                RenderTexture.ReleaseTemporary(_reflectionTexture);
            }
        }

        // 安全销毁对象（区分编辑器模式）
        private static void SafeDestroy(Object obj)
        {
            if (Application.isEditor)
            {
                DestroyImmediate(obj);
            }
            else
            {
                Destroy(obj);
            }
        }
        #endregion

        #region 摄像机同步与计算
        // 将主摄像机的属性拷贝给反射摄像机
        private void UpdateCamera(Camera src, Camera dest)
        {
            if (dest == null) return;

            dest.CopyFrom(src);
            dest.useOcclusionCulling = false; // 关闭遮挡剔除，因为反射视角不同
            if (dest.gameObject.TryGetComponent(out UniversalAdditionalCameraData camData))
            {
                camData.renderShadows = m_settings.m_Shadows;
            }
        }

        // 核心逻辑：计算反射矩阵并配置反射摄像机
        private void UpdateReflectionCamera(Camera realCamera)
        {
            if (_reflectionCamera == null)
                _reflectionCamera = CreateMirrorObjects();
            
            // 获取反射平面的位置和法线
            Vector3 pos = Vector3.zero;
            Vector3 normal = Vector3.up;
            if (target != null)
            {
                pos = target.transform.position + Vector3.up * m_planeOffset;
                normal = target.transform.up;
            }

            // 同步基础参数
            UpdateCamera(realCamera, _reflectionCamera);
            
            // 构建反射平面方程 (Ax + By + Cz + D = 0)
            var d = -Vector3.Dot(normal, pos) - m_settings.m_ClipPlaneOffset;
            var reflectionPlane = new Vector4(normal.x, normal.y, normal.z, d);

            // 计算反射矩阵（镜像矩阵）
            var reflection = Matrix4x4.identity;
            reflection *= Matrix4x4.Scale(new Vector3(1, -1, 1)); // Y轴翻转

            CalculateReflectionMatrix(ref reflection, reflectionPlane);
            
            // 计算反射摄像机的位置（真实摄像机关于平面的对称点）
            var oldPosition = realCamera.transform.position - new Vector3(0, pos.y * 2, 0);
            var newPosition = ReflectPosition(oldPosition);
            
            // 设置反射摄像机的朝向和矩阵
            _reflectionCamera.transform.forward = Vector3.Scale(realCamera.transform.forward, new Vector3(1, -1, 1));
            _reflectionCamera.worldToCameraMatrix = realCamera.worldToCameraMatrix * reflection;
            
            // 计算斜截投影矩阵（用于裁剪掉平面下方的物体，优化性能并防止错误渲染）
            var clipPlane = CameraSpacePlane(_reflectionCamera, pos - Vector3.up * 0.1f, normal, 1.0f);
            var projection = realCamera.CalculateObliqueMatrix(clipPlane);
            _reflectionCamera.projectionMatrix = projection;
            
            // 设置剔除层级和位置
            _reflectionCamera.cullingMask = m_settings.m_ReflectLayers;
            _reflectionCamera.transform.position = newPosition;
        }

        // 计算反射矩阵的数学公式
        private static void CalculateReflectionMatrix(ref Matrix4x4 reflectionMat, Vector4 plane)
        {
            reflectionMat.m00 = (1F - 2F * plane[0] * plane[0]);
            reflectionMat.m01 = (-2F * plane[0] * plane[1]);
            reflectionMat.m02 = (-2F * plane[0] * plane[2]);
            reflectionMat.m03 = (-2F * plane[3] * plane[0]);

            reflectionMat.m10 = (-2F * plane[1] * plane[0]);
            reflectionMat.m11 = (1F - 2F * plane[1] * plane[1]);
            reflectionMat.m12 = (-2F * plane[1] * plane[2]);
            reflectionMat.m13 = (-2F * plane[3] * plane[1]);

            reflectionMat.m20 = (-2F * plane[2] * plane[0]);
            reflectionMat.m21 = (-2F * plane[2] * plane[1]);
            reflectionMat.m22 = (1F - 2F * plane[2] * plane[2]);
            reflectionMat.m23 = (-2F * plane[3] * plane[2]);

            reflectionMat.m30 = 0F;
            reflectionMat.m31 = 0F;
            reflectionMat.m32 = 0F;
            reflectionMat.m33 = 1F;
        }

        // 简单的Y轴镜像位置计算
        private static Vector3 ReflectPosition(Vector3 pos)
        {
            var newPos = new Vector3(pos.x, -pos.y, pos.z);
            return newPos;
        }
        #endregion

        #region 分辨率与RT管理
        // 根据枚举返回缩放比例
        private float GetScaleValue()
        {
            switch(m_settings.m_ResolutionMultiplier)
            {
                case ResolutionMulltiplier.Full: return 1f;
                case ResolutionMulltiplier.Half: return 0.5f;
                case ResolutionMulltiplier.Third: return 0.33f;
                case ResolutionMulltiplier.Quarter: return 0.25f;
                default: return 0.5f;
            }
        }

        // 将世界空间平面转换到摄像机裁剪空间
        private Vector4 CameraSpacePlane(Camera cam, Vector3 pos, Vector3 normal, float sideSign)
        {
            var offsetPos = pos + normal * m_settings.m_ClipPlaneOffset;
            var m = cam.worldToCameraMatrix;
            var cameraPosition = m.MultiplyPoint(offsetPos);
            var cameraNormal = m.MultiplyVector(normal).normalized * sideSign;
            return new Vector4(cameraNormal.x, cameraNormal.y, cameraNormal.z, -Vector3.Dot(cameraPosition, cameraNormal));
        }

        // 创建反射摄像机对象
        private Camera CreateMirrorObjects()
        {
            var go = new GameObject("Planar Reflections",typeof(Camera));
            var cameraData = go.AddComponent(typeof(UniversalAdditionalCameraData)) as UniversalAdditionalCameraData;

            // 配置URP摄像机数据
            cameraData.requiresColorOption = CameraOverrideOption.Off;
            cameraData.requiresDepthOption = CameraOverrideOption.Off;
            cameraData.SetRenderer(1); // 使用索引为1的Renderer（通常是ForwardRenderer）

            var t = transform;
            var reflectionCamera = go.GetComponent<Camera>();
            reflectionCamera.transform.SetPositionAndRotation(t.position, t.rotation);
            reflectionCamera.depth = -10; // 确保在主摄像机之前渲染
            reflectionCamera.enabled = false; // 不启用GameObject上的Update循环
            go.hideFlags = HideFlags.HideAndDontSave; // 不在Hierarchy中显示

            return reflectionCamera;
        }

        // 分配或复用反射纹理
        private void PlanarReflectionTexture(Camera cam)
        {
            if (_reflectionTexture == null)
            {
                var res = ReflectionResolution(cam, UniversalRenderPipeline.asset.renderScale);
                bool useHdr10 = RenderingUtils.SupportsRenderTextureFormat(RenderTextureFormat.RGB111110Float);
                RenderTextureFormat hdrFormat = useHdr10 ? RenderTextureFormat.RGB111110Float : RenderTextureFormat.DefaultHDR;
                // 申请临时RT
                _reflectionTexture = RenderTexture.GetTemporary(res.x, res.y, 16,
                    GraphicsFormatUtility.GetGraphicsFormat(hdrFormat, true));
            }
            _reflectionCamera.targetTexture =  _reflectionTexture;
        }

        // 计算最终反射纹理的分辨率
        private int2 ReflectionResolution(Camera cam, float scale)
        {
            var x = (int)(cam.pixelWidth * scale * GetScaleValue());
            var y = (int)(cam.pixelHeight * scale * GetScaleValue());
            return new int2(x, y);
        }
        #endregion

        #region 渲染执行入口
        // URP每帧渲染开始前调用此方法
        private void ExecutePlanarReflections(ScriptableRenderContext context, Camera camera)
        {
            // 跳过反射摄像机和预览摄像机，防止递归
            if (camera.cameraType == CameraType.Reflection || camera.cameraType == CameraType.Preview)
                return;

            UpdateReflectionCamera(camera); 
            PlanarReflectionTexture(camera);

            // 保存并修改全局渲染设置（如反转剔除、关闭雾效）
            var data = new PlanarReflectionSettingData();
            data.Set();

            // 触发事件，允许外部脚本修改渲染行为
            BeginPlanarReflections?.Invoke(context, _reflectionCamera); 
            
            // 手动执行一次URP渲染（只渲染反射摄像机）
            UniversalRenderPipeline.RenderSingleCamera(context, _reflectionCamera); 

            // 恢复原始设置
            data.Restore();
            
            // 将渲染好的纹理传递给Shader，供后续渲染使用
            Shader.SetGlobalTexture(_planarReflectionTextureId, _reflectionTexture);

            Debug.Log($"[PlanarReflection] RT size: {_reflectionTexture.width}x{_reflectionTexture.height}");
        }
        #endregion

        #region 辅助类：临时修改渲染设置
        class PlanarReflectionSettingData
        {
            private readonly bool _fog;
            private readonly int _maxLod;
            private readonly float _lodBias;

            public PlanarReflectionSettingData()
            {
                // 记录当前状态
                _fog = RenderSettings.fog;
                _maxLod = QualitySettings.maximumLODLevel;
                _lodBias = QualitySettings.lodBias;
            }

            public void Set()
            {
                // 为了正确渲染镜像，需要反转背面剔除
                GL.invertCulling = true;
                RenderSettings.fog = false; // 反射中通常不需要雾效
                QualitySettings.maximumLODLevel = 1; // 降低LOD级别以提高反射质量
                QualitySettings.lodBias = _lodBias * 0.5f; // 调整LOD偏移
            }

            public void Restore()
            {
                // 恢复原始状态
                GL.invertCulling = false;
                RenderSettings.fog = _fog;
                QualitySettings.maximumLODLevel = _maxLod;
                QualitySettings.lodBias = _lodBias;
            }
        }
        #endregion
    }
}