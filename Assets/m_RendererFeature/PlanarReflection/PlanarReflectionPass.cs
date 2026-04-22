using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class PlanarReflectionPass : ScriptableRenderPass
{
    private readonly string profilerTag;
    private readonly LayerMask reflectionLayerMask;
    private readonly int reflectionTextureResolution;
    private readonly float updateInterval;
    private readonly float clipPlaneOffset;
    private readonly bool debugView;
    private readonly float planeHeight;

    private Camera reflectionCamera;
    private RTHandle reflectionRT;
    private RTHandle cameraColorTarget;

    private static readonly int reflectionTextureId = Shader.PropertyToID("_PlanarReflectionTexture");

    public PlanarReflectionPass(
        string profilerTag,
        LayerMask reflectionLayerMask,
        int reflectionTextureResolution,
        float updateInterval,
        float clipPlaneOffset,
        bool debugView,
        float planeHeight
    )
    {
        this.profilerTag = profilerTag;
        this.reflectionLayerMask = reflectionLayerMask;
        this.reflectionTextureResolution = reflectionTextureResolution;
        this.updateInterval = updateInterval;
        this.clipPlaneOffset = clipPlaneOffset;
        this.debugView = debugView;
        this.planeHeight = planeHeight;

        CreateReflectionCamera();
    }

    public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
    {
        ConfigureInput(ScriptableRenderPassInput.None);
    }

    public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
    {
        var descriptor = new RenderTextureDescriptor(
            reflectionTextureResolution,
            reflectionTextureResolution,
            RenderTextureFormat.DefaultHDR,
            24
        )
        {
            useMipMap = false,
            autoGenerateMips = false
        };

        RenderingUtils.ReAllocateIfNeeded(ref reflectionRT, descriptor, FilterMode.Bilinear, TextureWrapMode.Clamp, name: "_PlanarReflectionRT");
    }

    private void CreateReflectionCamera()
    {
        var existingCamera = GameObject.Find("PlanarReflectionCamera");
        if (existingCamera != null)
        {
            reflectionCamera = existingCamera.GetComponent<Camera>();
        }
        else
        {
            var cameraObj = new GameObject("PlanarReflectionCamera");
            cameraObj.hideFlags = HideFlags.HideAndDontSave;
            reflectionCamera = cameraObj.AddComponent<Camera>();
        }

        reflectionCamera.enabled = false;
        reflectionCamera.orthographic = false;
        reflectionCamera.depthTextureMode = DepthTextureMode.None;
        reflectionCamera.cullingMask = reflectionLayerMask;
        reflectionCamera.clearFlags = CameraClearFlags.SolidColor;
        reflectionCamera.backgroundColor = Color.black;
        reflectionCamera.usePhysicalProperties = false;
        reflectionCamera.useOcclusionCulling = false;

        Debug.Log($"[PlanarReflection] Camera created, planeHeight={planeHeight}");
    }

    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        var mainCamera = renderingData.cameraData.camera;
        if (mainCamera == null || reflectionRT == null) return;

        CommandBuffer cmd = CommandBufferPool.Get(profilerTag);

        cameraColorTarget = renderingData.cameraData.renderer.cameraColorTargetHandle;

        // 配置反射相机
        ConfigureReflectionCamera(mainCamera);

        // 设置渲染目标为反射纹理
        cmd.SetRenderTarget(reflectionRT);

        // 清除
        CoreUtils.ClearRenderTarget(cmd, ClearFlag.All, Color.black);

        // 翻转剔除方向
        GL.invertCulling = true;

        // 设置反射相机的视图投影矩阵
        Matrix4x4 reflectionMatrix = reflectionCamera.worldToCameraMatrix;
        Matrix4x4 projectionMatrix = reflectionCamera.projectionMatrix;
        cmd.SetViewProjectionMatrices(reflectionMatrix, projectionMatrix);

        // 执行渲染 - 只渲染不透明物体
        var shaderTagIds = new List<ShaderTagId> {
            new ShaderTagId("SRPDefaultUnlit"),
            new ShaderTagId("UniversalForward"),
            new ShaderTagId("UniversalForwardOnly")
        };

        var drawingSettings = CreateDrawingSettings(shaderTagIds, ref renderingData, SortingCriteria.CommonOpaque);
        var filteringSettings = new FilteringSettings(RenderQueueRange.opaque, reflectionLayerMask);

        context.DrawRenderers(renderingData.cullResults, ref drawingSettings, ref filteringSettings);

        // 恢复剔除方向
        GL.invertCulling = false;

        // 提交渲染
        context.Submit();

        // 设置全局反射纹理
        cmd.SetGlobalTexture(reflectionTextureId, reflectionRT);

        // 调试视图 - 将反射纹理blit到屏幕
        if (debugView)
        {
            cmd.Blit(reflectionRT, cameraColorTarget);
        }

        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
    }

    private void ConfigureReflectionCamera(Camera mainCamera)
    {
        // 复制主相机基本参数
        reflectionCamera.CopyFrom(mainCamera);
        reflectionCamera.cullingMask = reflectionLayerMask;
        reflectionCamera.clearFlags = CameraClearFlags.SolidColor;
        reflectionCamera.backgroundColor = Color.black;
        reflectionCamera.useOcclusionCulling = false;
        reflectionCamera.usePhysicalProperties = false;

        // 计算反射平面（使用可配置的平面高度）
        Vector3 planeNormal = Vector3.up;
        Vector3 planePosition = new Vector3(0, planeHeight, 0);
        float d = -Vector3.Dot(planeNormal, planePosition);
        Vector4 reflectionPlane = new Vector4(planeNormal.x, planeNormal.y, planeNormal.z, d);

        // 计算反射矩阵
        Matrix4x4 reflectionMatrix = Matrix4x4.identity;
        CalculateReflectionMatrix(ref reflectionMatrix, reflectionPlane);

        // 设置反射相机位置 - 关于Y=planeHeight平面对称
        Vector3 reflectedPos = reflectionMatrix.MultiplyPoint(mainCamera.transform.position);
        reflectionCamera.transform.position = reflectedPos;
        reflectionCamera.transform.rotation = mainCamera.transform.rotation;

        // 关键：worldToCameraMatrix通过反射矩阵计算
        reflectionCamera.worldToCameraMatrix = mainCamera.worldToCameraMatrix * reflectionMatrix;

        // 计算斜裁剪平面（只渲染平面上方的物体）
        Vector4 clipPlane = CameraSpacePlane(mainCamera, planePosition + planeNormal * clipPlaneOffset, planeNormal, 1.0f);
        reflectionCamera.projectionMatrix = mainCamera.CalculateObliqueMatrix(clipPlane);
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

    private Vector4 CameraSpacePlane(Camera cam, Vector3 pos, Vector3 normal, float sideSign)
    {
        Matrix4x4 worldToCameraMatrix = cam.worldToCameraMatrix;
        Vector3 cpos = worldToCameraMatrix.MultiplyPoint(pos);
        Vector3 cnormal = worldToCameraMatrix.MultiplyVector(normal).normalized * sideSign;
        return new Vector4(cnormal.x, cnormal.y, cnormal.z, -Vector3.Dot(cpos, cnormal));
    }

    public override void OnCameraCleanup(CommandBuffer cmd)
    {
    }

    public void Dispose()
    {
        reflectionRT?.Release();
    }
}