using System;
using System.Collections.Generic;
using System.Linq;
using UnityEditor.Experimental.GraphView;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class GrassRendererPass : ScriptableRendererFeature
{
    // 输入信息
    [System.Serializable]
    public class Settings
    {
        [Tooltip("要渲染深度图的图层")]
        public LayerMask renderLayer;
        [Tooltip("深度图的分辨率（建议2048/1024）")]
        public int textureSize = 2048;
        [Tooltip("使用的摄像机，默认mainCamera")]
        public Camera customCam;
        [Tooltip("深度图的绘制距离（和草的绘制距离一致）")]
        public float drawDistance = 300;
        [Tooltip("纹理更新阈值（减少频繁更新）")]
        public float textureUpdateThreshold = 10.0f;
        [Tooltip("草的间隔")]
        public float spacing = 1.0f;
        [Tooltip("草的最大数量，单位10万")]
        public float maxBufferCount = 1.0f;
        [Tooltip("深度图材质（用于输出深度值）")]
        public Material depthMaterial;
        public Material showMat;

        public ComputeShader computeShader;
    }
        GrassPass landSDFPass;

    public override void Create()
    {
        landSDFPass = new GrassPass("GrassPass",settings);

        // Configures where the render pass should be injected.
        landSDFPass.renderPassEvent = RenderPassEvent.AfterRenderingPrePasses;
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if(settings.depthMaterial != null){
            renderer.EnqueuePass(landSDFPass);
        }
    }
    protected override void Dispose(bool disposing)
    {
        if(disposing){
            landSDFPass.Dispose();
        }
    }
    [SerializeField]private Settings settings = new Settings();
    
    class GrassPass : ScriptableRenderPass
    {
        private readonly string passName;
        private readonly Settings settings; // 传入的数据
        private RTHandle depRT;// 创建一个用于储存深度值的RTHandle
        private readonly List<ShaderTagId> shaderTagList = new List<ShaderTagId>();
        
        ComputeBuffer grassPosBuffer;
        
        public GrassPass(string name,Settings settings)// 构造函数
        {
            passName = name;
            this.settings = settings;

            if(myRendererData.instance != null)
            {
                //settings.drawDistance = myRendererData.instance.drawDistance;
                settings.drawDistance = myRendererData.instance.drawDistance;
                settings.textureUpdateThreshold = myRendererData.instance.textureUpdateThreshold;
                settings.textureSize = myRendererData.instance.textureSize;
                settings.spacing = myRendererData.instance.spacing;
                settings.maxBufferCount = myRendererData.instance.maxBufferCount;
            }


            shaderTagList.Add(new ShaderTagId("SRPDefaultUnlit"));
            shaderTagList.Add(new ShaderTagId("UniversalForward"));
            shaderTagList.Add(new ShaderTagId("UniversalForwardOnly"));
        }
        // 初始化渲染纹理
        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            
            RenderingUtils.ReAllocateIfNeeded(ref depRT,
                new RenderTextureDescriptor(settings.textureSize,settings.textureSize,RenderTextureFormat.RFloat,32),
                FilterMode.Bilinear);
            ConfigureTarget(depRT);
            // 配置清除规则：清除颜色为0（深度值0表示最近），清除深度和颜色
            ConfigureClear(ClearFlag.All, Color.black);
            
        }
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            
            // 安全校验
            if(Camera.main == null||settings.depthMaterial == null || settings.computeShader == null) 
            {
                Debug.Log("请指定材质与CS");
                return;
            }

            CommandBuffer cmd = CommandBufferPool.Get(passName);
            Bounds camBounds = CalCamBounds(Camera.main,settings.drawDistance);
            Vector2 centerPos = new Vector2(
                Mathf.Floor(Camera.main.transform.position.x/settings.textureUpdateThreshold)*settings.textureUpdateThreshold,
                Mathf.Floor(Camera.main.transform.position.z/settings.textureUpdateThreshold)*settings.textureUpdateThreshold
            );
            // V矩阵
            Matrix4x4 vMatrix = Matrix4x4.TRS(
                new Vector3(centerPos.x,camBounds.max.y,centerPos.y),
                Quaternion.LookRotation(-Vector3.up),
                new Vector3(1,1,-1) // Z轴取反，不然照的就是反方向了
            ).inverse;
            
            // P矩阵
            Matrix4x4 pMatrix = Matrix4x4.Ortho(
                -(settings.drawDistance + settings.textureUpdateThreshold),//上下左右四个角
                (settings.drawDistance + settings.textureUpdateThreshold),
                -(settings.drawDistance + settings.textureUpdateThreshold),
                (settings.drawDistance + settings.textureUpdateThreshold),
                0.1f,//近裁切面
                camBounds.size.y // 远裁切面
            );
            cmd.SetViewProjectionMatrices(vMatrix, pMatrix);
            using (new ProfilingScope(cmd, new ProfilingSampler("Grass Height Map RT")))
            {
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();
                var drawSetting = CreateDrawingSettings(shaderTagList, ref renderingData, renderingData.cameraData.defaultOpaqueSortFlags);
                settings.depthMaterial.SetVector("_BoundsYMinMax", new Vector2(camBounds.min.y, camBounds.max.y));
                // 在本次渲染过程中，强制让所有被选中的物体，
                // 都使用你指定的这个材质（depthMaterial）来渲染，临时替换掉它们自己的材质。
                drawSetting.overrideMaterial = settings.depthMaterial;
                var filterSetting = new FilteringSettings(RenderQueueRange.all, settings.renderLayer);
                context.DrawRenderers(renderingData.cullResults, ref drawSetting, ref filterSetting);
            }
            //Finally we reset the camera matricies to the original ones
            cmd.SetViewProjectionMatrices(renderingData.cameraData.camera.worldToCameraMatrix, renderingData.cameraData.camera.projectionMatrix);
            
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            
            // ================== 以下使用compute shader计算草地位置 ==================
            // 计算草的网格大小（XZ方向的网格数量）
            Vector2Int gridSize = new Vector2Int(
                Mathf.CeilToInt(camBounds.size.x / settings.spacing),
                Mathf.CeilToInt(camBounds.size.z / settings.spacing)
            );
            // 计算网格的起始索引（定位草的网格位置）
            Vector2Int gridStartIndex = new Vector2Int(
                Mathf.FloorToInt(camBounds.min.x / settings.spacing),
                Mathf.FloorToInt(camBounds.min.z / settings.spacing)
            );
            // 释放旧的缓冲区
            grassPosBuffer?.Release();
            // 创建新的Append模式ComputeBuffer（GPU端动态追加数据）
            // 参数：容量、每个元素大小（3个float：x/y/z位置）、缓冲区类型
            grassPosBuffer = new ComputeBuffer((int)(100000 * settings.maxBufferCount), sizeof(float) * 3, ComputeBufferType.Append);
            // 向ComputeBuffer中添加数据
            
            settings.computeShader.SetFloat("_spacing", settings.spacing);
            settings.computeShader.SetFloat("_drawDistance", settings.drawDistance);
            settings.computeShader.SetFloat("_textureUpdateThreshold", settings.textureUpdateThreshold);
            settings.computeShader.SetVector("_gridStartIndex", (Vector2)gridStartIndex);
            settings.computeShader.SetVector("_gridSize", (Vector2)gridSize);
            settings.computeShader.SetVector("_camPosition", Camera.main.transform.position);
            settings.computeShader.SetVector("_centerPos", centerPos);
            settings.computeShader.SetVector("_boundsMin", camBounds.min);
            settings.computeShader.SetVector("_boundsMax", camBounds.max);

            settings.computeShader.SetMatrix("_VPMatrix", Camera.main.projectionMatrix * Camera.main.worldToCameraMatrix);

            settings.computeShader.SetTexture(0, "_grassHeightTex", depRT); 
            settings.computeShader.SetBuffer(0, "_GrassPositions", grassPosBuffer); //// 绑定缓冲区（0是Kernel索引）
            
            //settings.computeShader.SetTexture(0,"_CameraDepthTexture",renderingData.cameraData.renderer.cameraDepthTargetHandle.rt);

            // 重置Append缓冲区的计数器（必须）
            grassPosBuffer.SetCounterValue(0);
            // 调度ComputeShader执行（线程组数量：X=gridSize.x/8，Y=gridSize.y/8，Z=1）
            // 线程组大小通常设为8x8x1，因此需要除以8并向上取整
            cmd.DispatchCompute(settings.computeShader,
                0,
                Mathf.CeilToInt((float)gridSize.x / 8),
                Mathf.CeilToInt((float)gridSize.y / 8), 
                1);
            // 将草位置缓冲区设为全局，供实例化渲染Shader使用
            cmd.SetGlobalBuffer("_GrassPositions", grassPosBuffer);
            
            if(myRendererData.instance != null){
                // 将缓冲区计数器值复制到argsBuffer（DrawMeshInstancedIndirect需要的参数）
                // argsBuffer结构：[0]顶点数 [1]实例数 [2]起始顶点 [3]起始实例 [4]实际实例数（由计数器提供）
                // 这里的4是起始字节，不是元素索引，也就是说argsBuffer的第一项是0-3，第二项是4-7.....
                cmd.CopyCounterValue(grassPosBuffer, myRendererData.instance.argsBuffer, 4);
                // 预览草的数量：将计数器值复制到tBuffer
                if (myRendererData.instance.previewVisibleGrassCount)
                {
                    cmd.CopyCounterValue(grassPosBuffer, myRendererData.instance.tBuffer, 0);
                }
            }
            // 执行ComputeShader相关命令
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            
            // 释放CommandBuffer（归还到池）
            CommandBufferPool.Release(cmd);



            // =================== 可视化调试部分 ===================
            //settings.showMat.SetFloat("_KKK",0.5f);
            settings.showMat.SetTexture("_MainTex",depRT);
            // 用于可视化包围盒
            if(myRendererData.instance != null)
            {
                Bounds tbounds = camBounds;
                tbounds.Expand(myRendererData.instance.drawDistance);
                myRendererData.instance.camBounds.size = new Vector3(
                    tbounds.size.x ,
                    camBounds.size.y,
                    tbounds.size.x
                ); 
                myRendererData.instance.camBounds.center = new Vector3(
                    centerPos.x,
                    myRendererData.instance.camBounds.center.y,
                    centerPos.y
                );
            }

        }
        public void Dispose()
        {
            depRT?.Release();
            // ComputeBuffer的释放后续再优化
            if (grassPosBuffer != null)
            {
                grassPosBuffer.Release();
                // 编辑器模式下强制销毁，避免残留
                grassPosBuffer?.Release();
                grassPosBuffer = null;
            }
            //grassPosBuffer?.Release();
        }
        // 用于获取变换后的摄像机包围盒的自定义函数
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
}


