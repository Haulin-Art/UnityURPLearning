using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using Unity.Mathematics;

public class PlanarReflectionRenderFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class Settings
    {
        [Header("Reflection Settings")]
        public LayerMask reflectLayers = -1;
        public RenderPassEvent renderPassEvent = RenderPassEvent.BeforeRenderingOpaques;
        public string passName = "Planar Reflection Pass";

        [Header("Quality")]
        public ResolutionMultiplier resolutionMultiplier = ResolutionMultiplier.Third;
        public float clipPlaneOffset = 0.07f;
        public bool renderShadows = false;

        [Header("Water Plane")]
        [Tooltip("Water surface height (Y coordinate)")]
        public float waterHeight = 0f;
        public float planeOffset = 0f;
    }

    public enum ResolutionMultiplier
    {
        Full,
        Half,
        Third,
        Quarter
    }

    public Settings settings = new Settings();
    private PlanarReflectionRenderPass m_Pass;

    public override void Create()
    {
        m_Pass = new PlanarReflectionRenderPass(settings);
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (renderingData.cameraData.camera.cameraType is CameraType.Preview or CameraType.Reflection)
            return;

        renderer.EnqueuePass(m_Pass);
    }

    protected override void Dispose(bool disposing)
    {
        base.Dispose(disposing);
        if (disposing)
        {
            m_Pass?.Dispose();
        }
    }

    class PlanarReflectionRenderPass : ScriptableRenderPass
    {
        private Settings m_Settings;
        private RTHandle _reflectionTexture;
        private RTHandle _tempDepRT;
        private Camera _reflectionCamera;
        private readonly int _planarReflectionTextureId = Shader.PropertyToID("_PlanarReflectionTexture");
        private GameObject _reflectionCameraGO;

        // 用于调试：Blit到屏幕的临时RT
        private RTHandle _debugTexture;
        private readonly int _debugTextureId = Shader.PropertyToID("_DebugReflectionTex");


        public PlanarReflectionRenderPass(Settings settings)
        {
            m_Settings = settings;
            renderPassEvent = settings.renderPassEvent;

        }


        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            var camera = renderingData.cameraData.camera;

            if (_reflectionCamera == null)
            {
                CreateReflectionCamera();
            }

            int2 resolution = CalculateReflectionResolution(camera);

            RenderTextureDescriptor desc = new RenderTextureDescriptor(
                resolution.x,
                resolution.y,
                RenderTextureFormat.DefaultHDR,
                0
            );
            desc.sRGB = true;

            RenderTextureDescriptor desc_dep = new RenderTextureDescriptor(
                resolution.x,
                resolution.y,
                RenderTextureFormat.RFloat,
                24
            );

            RenderingUtils.ReAllocateIfNeeded(ref _reflectionTexture, desc, FilterMode.Bilinear, TextureWrapMode.Clamp);
            RenderingUtils.ReAllocateIfNeeded(ref _tempDepRT, desc_dep, FilterMode.Point, TextureWrapMode.Clamp);
            // 调试用：全屏RT
            RenderTextureDescriptor debugDesc = new RenderTextureDescriptor(
                camera.pixelWidth, camera.pixelHeight, RenderTextureFormat.DefaultHDR, 0
            );

            RenderingUtils.ReAllocateIfNeeded(ref _debugTexture, debugDesc, FilterMode.Point, TextureWrapMode.Clamp);
            
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (_reflectionCamera == null)
                return;

            UpdateReflectionCamera(renderingData.cameraData.camera);


            // 为反射相机执行 culling
            if (!_reflectionCamera.TryGetCullingParameters(out var cullingParameters))
                return;
            cullingParameters.cullingMask = (uint)m_Settings.reflectLayers.value;
            var cullingResults = context.Cull(ref cullingParameters);

            CommandBuffer cmd = CommandBufferPool.Get(m_Settings.passName);

            // 保存原始渲染状态
            bool originalFog = RenderSettings.fog;
            int originalLod = QualitySettings.maximumLODLevel;
            float originalLodBias = QualitySettings.lodBias;
            bool originalInvertCulling = GL.invertCulling;
            // 保存摄像机矩阵
            Matrix4x4 viewMatrix = renderingData.cameraData.camera.worldToCameraMatrix;
            Matrix4x4 projectionMatrix = renderingData.cameraData.camera.projectionMatrix;
            // 原始渲染的目标
            RenderTargetIdentifier camColorTgt = renderingData.cameraData.renderer.cameraColorTargetHandle;
            RenderTargetIdentifier camDepthTgt = renderingData.cameraData.renderer.cameraDepthTargetHandle;

            RenderSettings.fog = false;
            QualitySettings.maximumLODLevel = 1;
            QualitySettings.lodBias = originalLodBias * 0.5f;

            // 设置反射纹理为目标
            cmd.SetRenderTarget(_reflectionTexture,_tempDepRT);
            cmd.ClearRenderTarget(true, true, Color.clear);

            // 设置反射摄像机矩阵
            cmd.SetViewProjectionMatrices(
                _reflectionCamera.worldToCameraMatrix,
                _reflectionCamera.projectionMatrix
            );

            // 绘制设置
            var drawSettings = new DrawingSettings(
                new ShaderTagId("UniversalForward"),
                new SortingSettings(_reflectionCamera)
            )
            {
                perObjectData = PerObjectData.ReflectionProbes,
            };

            drawSettings.SetShaderPassName(0, new ShaderTagId("UniversalForward"));
            drawSettings.SetShaderPassName(1, new ShaderTagId("UniversalForwardOnly"));
            drawSettings.SetShaderPassName(2, new ShaderTagId("SRPDefaultUnlit"));

            var filterSettings = new FilteringSettings(
                RenderQueueRange.all,
                m_Settings.reflectLayers
            );

            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();

            // 渲染反射（使用 RenderStateBlock 渲染背面）
            context.DrawRenderers(cullingResults, ref drawSettings, ref filterSettings);
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();

            // 设置全局纹理（正常的水面shader会采样这个）
            cmd.SetGlobalTexture(_planarReflectionTextureId, _reflectionTexture);
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            
            
            // 恢复渲染状态
            RenderSettings.fog = originalFog;
            QualitySettings.maximumLODLevel = originalLod;
            QualitySettings.lodBias = originalLodBias;
            
            // 恢复摄像机矩阵
            cmd.SetViewProjectionMatrices(viewMatrix, projectionMatrix);

            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        public override void OnCameraCleanup(CommandBuffer cmd)
        {
        }

        public void Dispose()
        {
            if (_reflectionTexture != null)
            {
                RTHandles.Release(_reflectionTexture);
                _reflectionTexture = null;
            }

            if (_debugTexture != null)
            {
                RTHandles.Release(_debugTexture);
                _debugTexture = null;
            }

            if (_reflectionCameraGO != null)
            {
                UnityEngine.Object.DestroyImmediate(_reflectionCameraGO);
                _reflectionCameraGO = null;
                _reflectionCamera = null;
            }
        }

        private void CreateReflectionCamera()
        {
            _reflectionCameraGO = new GameObject("Planar Reflection Camera");
            _reflectionCameraGO.hideFlags = HideFlags.HideAndDontSave | HideFlags.HideInInspector;

            _reflectionCamera = _reflectionCameraGO.AddComponent<Camera>();
            _reflectionCamera.enabled = false;
            _reflectionCamera.allowHDR = true;
            _reflectionCamera.allowMSAA = false;
            _reflectionCamera.cameraType = CameraType.Reflection; // ✅ 很重要

            var camData = _reflectionCameraGO.AddComponent<UniversalAdditionalCameraData>();
            camData.requiresColorOption = CameraOverrideOption.Off;
            camData.requiresDepthOption = CameraOverrideOption.Off;
            camData.renderShadows = m_Settings.renderShadows;
            camData.SetRenderer(1);
        }

        private void UpdateReflectionCamera(Camera mainCamera)
        {
            if (_reflectionCamera == null) return;

            _reflectionCamera.CopyFrom(mainCamera);
            _reflectionCamera.useOcclusionCulling = false;
            _reflectionCamera.cullingMask = m_Settings.reflectLayers;
            _reflectionCamera.depth = -1000;
            _reflectionCamera.rect = new Rect(0, 0, 1, 1);

            // 水面位置
            float waterHeight = m_Settings.waterHeight + m_Settings.planeOffset;

            // 1. 计算反射相机位置（对称 Y 轴）
            Vector3 camPos = mainCamera.transform.position;
            float reflectedY = waterHeight - (camPos.y - waterHeight);
            Vector3 reflectedPos = new Vector3(camPos.x, reflectedY, camPos.z);
            _reflectionCamera.transform.position = reflectedPos;

            // 2. 用欧拉角计算反射相机旋转（方位角不变，俯仰角取反）
            Vector3 euler = mainCamera.transform.eulerAngles;
            float reflectedPitch = -euler.x;
            if (reflectedPitch > 90) reflectedPitch -= 360;
            if (reflectedPitch < -90) reflectedPitch += 360;
            _reflectionCamera.transform.rotation = Quaternion.Euler(reflectedPitch, euler.y, 0);

            // 4. 设置反射相机的 view matrix（从计算好的 transform 获取）
            _reflectionCamera.worldToCameraMatrix = _reflectionCamera.worldToCameraMatrix;

            // 5. 计算斜截投影矩阵
            Vector4 clipPlane = CameraSpacePlane(_reflectionCamera,
                new Vector3(0, waterHeight, 0),
                Vector3.up, 1.0f, m_Settings.clipPlaneOffset);

            _reflectionCamera.projectionMatrix = mainCamera.CalculateObliqueMatrix(clipPlane);
        }

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
            reflectionMat.m22 = (1 - 2F * plane[2] * plane[2]);
            reflectionMat.m23 = (-2F * plane[3] * plane[2]);

            reflectionMat.m30 = 0F;
            reflectionMat.m31 = 0F;
            reflectionMat.m32 = 0F;
            reflectionMat.m33 = 1F;
        }

        private static Vector4 CameraSpacePlane(Camera cam, Vector3 pos, Vector3 normal, float sideSign, float clipPlaneOffset)
        {
            Vector3 offsetPos = pos + normal * clipPlaneOffset;
            Matrix4x4 m = cam.worldToCameraMatrix;
            Vector3 cpos = m.MultiplyPoint(offsetPos);
            Vector3 cnormal = m.MultiplyVector(normal).normalized * sideSign;
            return new Vector4(cnormal.x, cnormal.y, cnormal.z, -Vector3.Dot(cpos, cnormal));
        }

        private int2 CalculateReflectionResolution(Camera cam)
        {
            float scale = GetScaleValue();
            int width = Mathf.Max(1, (int)(cam.pixelWidth * scale));
            int height = Mathf.Max(1, (int)(cam.pixelHeight * scale));
            return new int2(width, height);
        }

        private float GetScaleValue()
        {
            return m_Settings.resolutionMultiplier switch
            {
                ResolutionMultiplier.Full => 1f,
                ResolutionMultiplier.Half => 0.5f,
                ResolutionMultiplier.Third => 0.33f,
                ResolutionMultiplier.Quarter => 0.25f,
                _ => 0.5f
            };
        }
    }
}