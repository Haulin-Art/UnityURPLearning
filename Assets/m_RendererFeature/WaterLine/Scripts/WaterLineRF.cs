using System.Collections.Generic;
using UnityEditor.Rendering;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class WaterLineFeature : ScriptableRendererFeature
{
    public RenderPassEvent renderPassEvent = RenderPassEvent.AfterRenderingPostProcessing; // 定义执行的时机
    public Material featureMaterial; // 定义使用的Pass的材质
    public Material CautionMaterial; // 焦散处理材质
    public Material WaterSurfaceHeightMaterial; // 定义使用的Pass的材质
    public float heightOffset = 0.97f; // 水线高度偏移
    public float CES = 0.0f;

    WaterLineFeaturePass m_ScriptablePass;

    /// <inheritdoc/>
    public override void Create()
    {
        // 创建一个可编程渲染管线
        m_ScriptablePass = new WaterLineFeaturePass();
        // 将可编程RendererFeature中的值传递给执行者
        m_ScriptablePass.material = featureMaterial;
        m_ScriptablePass.cautionMat = CautionMaterial;
        m_ScriptablePass.WaterSurfaceHeightMaterial = WaterSurfaceHeightMaterial;
        m_ScriptablePass.heightOffset = heightOffset;
        m_ScriptablePass.CES = CES;
        //var strack = VolumeManager.instance.stack;
        //volume = strack.GetComponent<自定义的类>();
        //m_ScriptablePass.volume = volume;
        m_ScriptablePass.renderPassEvent = renderPassEvent;
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        // 判空后再入队，避免空状态传递
        if (m_ScriptablePass != null && featureMaterial != null)
        {
            // 将绘制命令每帧添加进渲染队列
            renderer.EnqueuePass(m_ScriptablePass);
        }
    }


    class WaterLineFeaturePass : ScriptableRenderPass // 真正执行绘制命令的自定义Pass脚本
    {
        const string ProfilerTag = "WaterLineFeaturePass"; // 定义一个名字标签 
        RTHandle _cameraColorTgt; // RTHandle是2021年后封装的一个高级RenderTexture管理类
        RTHandle _cameraDepthTgt;
        RTHandle _waterSurfaceHeightRT;
        RTHandle _tempDepthRT;
        RTHandle _dropProcessRT;

        RTHandle _waterLineMaskRT;
        RTHandle _waterLineMaskRT_Read;

        RTHandle _mipmapSceneRT;

        int shaderID = Shader.PropertyToID("_Temp_RT"); // 定义用于申请临时RT的ID，其实就是把字符串换成id的形式表达，效率更高
        int heightShaderID = Shader.PropertyToID("_WaterSurfaceHeightRT");


        public Material material;
        public Material cautionMat;
        public Material WaterSurfaceHeightMaterial;
        public float heightOffset;
        //public 
        private bool start; // 是否启用
        private Light ld; // 主光源
        private Camera camera; // 相机
        public float CES;
        private readonly List<ShaderTagId> shaderTagIdList = new List<ShaderTagId>() // 定义一个ShaderTagId列表，指定要渲染的Pass
        {
            new ShaderTagId("SRPDefaultUnlit"),
            new ShaderTagId("UniversalForward"),
            new ShaderTagId("UniversalForwardOnly"),
            new ShaderTagId("WaterSurfaceHeight")
        };
        // Pass开始前调用，提前设置当前Pass要用的信息
        public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
            //base.Configure(cmd, cameraTextureDescriptor);
            ConfigureInput(ScriptableRenderPassInput.Depth | ScriptableRenderPassInput.Normal);
        }

        // 每帧 渲染相机前调用
        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            // 查看场景当中有没有主光源，以及获取主光源
            start = true;
            if (!renderingData.shadowData.supportsMainLightShadows)start = false;
            
            // 获取主光源在可见光源中的索引
            int shadowLightIndex = renderingData.lightData.mainLightIndex;
            // 索引为-1说明没有找到主光源，设置为不启用
            if(shadowLightIndex==-1)start = false;
            // 根据索引从见可见光源列表当中获取主光源的可见数据
            VisibleLight shadowLight = renderingData.lightData.visibleLights[shadowLightIndex];
            ld = shadowLight.light; // 从可见光源数据当中获取Unity的Light组件引用
            // 检查灯光设置，如果灯光组件没有开启阴影，或者灯光数据的灯光类型不是平行光
            //if(ld.shadows == LightShadows.None || shadowLight.lightType != LightType.Directional)start = false;
            if(shadowLight.lightType != LightType.Directional)start = false;
            // 没开启立刻返回
            if(!start)return;
            
            
            if (material == null) return;
            // 在这里给材质传入数据，好进行计算
            // 设置太阳方向
            // 设置相机和光照参数
            //mainCam = renderingData.cameraData.camera;
            camera = renderingData.cameraData.camera;
            //camera = Camera.main;
            //material.SetVector("_CameraWorldPos", camera.transform.position);
            material.SetVector("_SunDirection", -ld.transform.forward);
            // 2. 传递逆视投影矩阵（用于Shader中转世界空间）
            Matrix4x4 viewProjMatrix = camera.projectionMatrix * camera.worldToCameraMatrix;
            Matrix4x4 invViewProjMatrix = viewProjMatrix.inverse;
            material.SetMatrix("_InvViewProj", invViewProjMatrix);


            RenderingUtils.ReAllocateIfNeeded(ref _waterSurfaceHeightRT,
                new RenderTextureDescriptor( 512  , 512, 
                RenderTextureFormat.ARGBFloat,0),
                FilterMode.Bilinear);
            RenderingUtils.ReAllocateIfNeeded(ref _tempDepthRT,
                new RenderTextureDescriptor( 512  , 512, 
                RenderTextureFormat.RFloat,16),
                FilterMode.Bilinear);

            var descriptor = new RenderTextureDescriptor(
                    renderingData.cameraData.cameraTargetDescriptor.width,
                    renderingData.cameraData.cameraTargetDescriptor.height,
                    RenderTextureFormat.ARGBFloat, 0);  // 使用ARGB32而不是默认格式
            descriptor.msaaSamples = 1;  // 关键：禁用多重采样
            descriptor.mipCount = 3;
            descriptor.useMipMap = true;
            descriptor.autoGenerateMips = false;

            RenderingUtils.ReAllocateIfNeeded(ref _dropProcessRT,
                descriptor,  // 使用ARGB32而不是默认格式
                FilterMode.Bilinear);


            RenderingUtils.ReAllocateIfNeeded(ref _mipmapSceneRT,
                descriptor,  // 使用ARGB32而不是默认格式
                FilterMode.Bilinear);


            // 吃水线mask，与计算解耦，这样的话就可以很方便地得到上一帧的吃水线mask，供水珠效果使用
            RenderingUtils.ReAllocateIfNeeded(ref _waterLineMaskRT,
                new RenderTextureDescriptor(
                    512, 512,
                    RenderTextureFormat.RGFloat, 0),  // 两个通道，a是水线sdf，b多帧混合结果
                FilterMode.Bilinear);

            RenderingUtils.ReAllocateIfNeeded(ref _waterLineMaskRT_Read,
                new RenderTextureDescriptor(
                    512, 512,
                    RenderTextureFormat.RFloat, 0), 
                FilterMode.Bilinear);
        }

        // 具体渲染逻辑代码
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if(material == null || WaterSurfaceHeightMaterial == null) return;
            // 定义Pass的名字，该名字会在FrameDebug的窗口显示对应的Pass
            CommandBuffer cmd = CommandBufferPool.Get(ProfilerTag);
            // 用于临时申请GPU渲染纹理的方法
            // 后续可以根据shaderID获得此临时RT的引用
            using (new ProfilingScope(cmd, new ProfilingSampler("WaterLineFeaturePass")))
            {
                var descriptor = renderingData.cameraData.cameraTargetDescriptor;
                descriptor.msaaSamples = 1;  // 关键：禁用多重采样
                descriptor.depthBufferBits = 0; // 禁用深度
                cmd.GetTemporaryRT(shaderID, descriptor, FilterMode.Bilinear);

                // 申请一个新的RT用来存储水面高度
                var descriptor1 = renderingData.cameraData.cameraTargetDescriptor;
                descriptor1.msaaSamples = 1;  // 关键：禁用多重采样
                descriptor1.depthBufferBits = 0; // 禁用深度
                //descriptor1.colorFormat = RenderTextureFormat.RFloat; // 只需要一个通道来存储高度值
                descriptor1.width = 512; // 可以根据需要调整分辨率
                descriptor1.height = 512;
                cmd.GetTemporaryRT(heightShaderID, descriptor1, FilterMode.Point);
                // 获得相机当前的RT
                _cameraColorTgt = renderingData.cameraData.renderer.cameraColorTargetHandle;

                // 现在不用
                
                //Vector2 centerPos = new Vector2(renderingData.cameraData.camera.transform.position.x,renderingData.cameraData.camera.transform.position.z);
                Vector2 centerPos = new Vector2(
                Mathf.Floor(renderingData.cameraData.camera.transform.position.x/0.5f)*0.5f,
                Mathf.Floor(renderingData.cameraData.camera.transform.position.z/0.5f)*0.5f);
                
                // V矩阵
                Matrix4x4 vMatrix = Matrix4x4.TRS(
                    new Vector3(centerPos.x,heightOffset+0.5f,centerPos.y), // 位置——在原始摄像机向上偏移一定高度,heightOffset是水面基础高度，因此还得再往上一点
                    Quaternion.LookRotation(-Vector3.up), // 旋转——摄像机朝下看，所以forward是负y轴
                    new Vector3(1,1,-1) // 缩放——Z轴取反，因为摄像机默认沿着-z的方向拍摄，不然照的就是反方向了
                ).inverse;

                // P矩阵，2×2×1.9 的立方体（深度为1.9）。
                float orthoSize = 2.0f; // 可以根据需要调整正交大小
                Matrix4x4 pMatrix = Matrix4x4.Ortho(
                    -orthoSize,//上下左右四个角
                    orthoSize,
                    -orthoSize,
                    orthoSize,
                    0.1f,//近裁切面
                    5.0f*orthoSize // 远裁切面
                );
                cmd.SetViewProjectionMatrices(vMatrix, pMatrix);
                // 组合视图投影矩阵
                Matrix4x4 vpMatrix = pMatrix * vMatrix;
                material.SetMatrix("_VPMatrix", vpMatrix);
                // 获取所有注册的渲染器
                if (WaterLineRenderer.Instance == null)
                {
                    Debug.LogError("WaterLineRenderer instance is null!");
                    return;
                }
                var waterLineRenderers = WaterLineRenderer.Instance.waterLineRenderers;
                
                using (new ProfilingScope(cmd, new ProfilingSampler("WaterSurfaceHeight")))
                {
                    cmd.SetRenderTarget(_waterSurfaceHeightRT,_tempDepthRT);
                    cmd.ClearRenderTarget(true,true, Color.black);
                    context.ExecuteCommandBuffer(cmd);
                    cmd.Clear();

                    foreach (var renderer in waterLineRenderers)
                    {
                        if (renderer == null || !renderer.enabled) continue;
                        var meshFilter = renderer.GetComponent<MeshFilter>();
                        if (meshFilter == null || meshFilter.sharedMesh == null) continue;
                        cmd.DrawRenderer(renderer, WaterSurfaceHeightMaterial, 0, 2); // 1 表示材质中的 Pass 索引
                    }
                }
                //cmd.Blit(_waterSurfaceHeightRT, _cameraColorTgt.nameID); // 从waterSurfaceHeightRT读出数据，写入cameraColorTgt，使用waterSurfaceHeightMaterial的第一个Pass进行处理
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();

                
                // 这个是不论在运行状态还是在视图模式，都是场景中设置的主摄像机，所以始终用主摄像机做遮挡剔除
                cmd.SetViewProjectionMatrices(renderingData.cameraData.camera.worldToCameraMatrix, renderingData.cameraData.camera.projectionMatrix); 
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();

                // 计算摄像机近平面上的四个点，用于传递到Shader中进行屏幕空间线性插值，进而计算出每个像素对应的世界空间位置
                // 计算摄像机近平面的四个顶点
                float nearOffset = 0.0f; // 避免精度问题导致的穿透
                Vector3 nTL = camera.ViewportToWorldPoint(new Vector3(0,1,camera.nearClipPlane+nearOffset));
                Vector3 nTR = camera.ViewportToWorldPoint(new Vector3(1,1,camera.nearClipPlane+nearOffset));
                Vector3 nBL = camera.ViewportToWorldPoint(new Vector3(0,0,camera.nearClipPlane+nearOffset));
                Vector3 nBR = camera.ViewportToWorldPoint(new Vector3(1,0,camera.nearClipPlane+nearOffset));
                material.SetVector("_NearPlaneCornersTL", nTL);
                material.SetVector("_NearPlaneCornersTR", nTR);
                material.SetVector("_NearPlaneCornersBL", nBL);
                material.SetVector("_NearPlaneCornersBR", nBR);

                material.SetTexture("_HeightTex", _waterSurfaceHeightRT);

                // 生成吃水线以及水下的部分Mask
                material.SetTexture("_waterLineMaskRT_Read", _waterLineMaskRT_Read);
                cmd.Blit(_waterLineMaskRT_Read, _waterLineMaskRT.nameID, material, 1); // Pass 1 负责生成吃水线和水下部分的Mask,a通道是吃水线SDF，b通道上一帧的b加上当前帧的水下部分，进行多帧混合
                cmd.Blit(_waterLineMaskRT,_waterLineMaskRT_Read); // 把当前帧生成的吃水线mask保存到_waterLineMaskRT_Read中，以供下一帧使用
                material.SetTexture("_WaterLineMaskRT", _waterLineMaskRT); // 将吃水线和水下部分的Mask传递给后续Pass使用
                
                
                // 给当前场景生成mipmap链，并且焦散处理
                if (cautionMat == null)
                {
                    cmd.Blit(_cameraColorTgt.nameID,_mipmapSceneRT);
                }else
                {
                    cmd.Blit(_cameraColorTgt.nameID,_mipmapSceneRT,cautionMat,0);
                }
                cmd.GenerateMips(_mipmapSceneRT);
                material.SetTexture("_ScreenMipMapRT2",_mipmapSceneRT);


                cmd.Blit(_cameraColorTgt.nameID,shaderID,material,0); // 吃水线以及水下效果
                cmd.Blit(shaderID, _cameraColorTgt.nameID);

                
                // 将CommandBuffer录制的所有渲染命令提交给GPU执行
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();
                
                CommandBufferPool.Release(cmd);
            }
            // 截图功能
            
        }
        // 释放资源
        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            if (cmd != null)
            {
                cmd.ReleaseTemporaryRT(shaderID);
                //_waterSurfaceHeightRT?.Release();
                //_tempDepthRT?.Release();
                //_dropProcessRT?.Release();
                //_mipmapSceneRT?.Release();
                //_waterLineMaskRT?.Release();
                //_waterLineMaskRT_Read?.Release();
            }
        }
        public void SwapRT(ref RTHandle rt1, ref RTHandle rt2)
        {
            RTHandle temp = rt1;
            rt1 = rt2;
            rt2 = temp;
        }
    }
}