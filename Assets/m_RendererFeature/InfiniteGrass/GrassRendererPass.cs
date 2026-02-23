using System;
using System.Collections.Generic;
using System.Linq;
using System.Security.Cryptography;
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
        public LayerMask renderLayer; // 要渲染深度图的图层
        [Tooltip("深度图的分辨率（建议2048/1024）")]
        public int textureSize = 2048;
        [Tooltip("深度图的绘制距离（和草的绘制距离一致）")]
        public float drawDistance = 300;
        [Tooltip("纹理更新阈值（减少频繁更新）")]
        public float textureUpdateThreshold = 10.0f;
        [Tooltip("草的间隔")]
        public float spacing = 1.0f;
        [Tooltip("草的最大数量，单位10万")]
        public float maxBufferCount = 1.0f;
        [Tooltip("深度图材质（用于输出深度值）")]
        public Material topOrthDepMat; // 这个用于计算从上方渲染的地形高度图
        [Tooltip("视图空间线性深度材质")]
        public Material viewSpaceDepMat; // 这个用于渲染主摄像机视角下的线性深度，使用深度缓存的话，因为摄像机参数不一致，编辑器空间的遮挡剔除会出错
        public Material showMat;

        public ComputeShader computeShader;
    }
    GrassInstancePass grassInstancePass;

    public override void Create()
    {
        grassInstancePass = new GrassInstancePass("GrassInstancePass",settings);

        // Configures where the render pass should be injected.
        grassInstancePass.renderPassEvent = RenderPassEvent.AfterRenderingPrePasses;
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if(settings.topOrthDepMat != null){
            renderer.EnqueuePass(grassInstancePass);
        }
    }
    protected override void Dispose(bool disposing)
    {
        if(disposing){
            grassInstancePass.Dispose();
        }
    }
    [SerializeField]private Settings settings = new Settings();
    
    class GrassInstancePass : ScriptableRenderPass
    {
        //topOrthographicDepth
        private readonly string passName;
        private readonly Settings settings; // 传入的数据
        private RTHandle topOrthographicDepth; // 创建一个用于从上方往下看的储存深度值的RTHandle
        private RTHandle camDepRT; // 正常视角下的摄像机的线性深度，这里渲染一张，不用深度缓冲，因为变换了摄像机的话，其参数不同，会导致编辑器视角与游戏视角的效果不一致
        public int unsampleInt = 2;
        
        private readonly List<ShaderTagId> shaderTagList = new List<ShaderTagId>();
        
        // 实例数据
        private ComputeBuffer _countersBuffer; // 储存每个类型的数量的Buffer
        private ComputeBuffer _segmentedBuffer;



        public GrassInstancePass(string name,Settings settings)// 构造函数
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
            // 安全校验
            if(Camera.main == null||settings.topOrthDepMat == null || settings.computeShader == null) 
            {
                Debug.Log("请指定材质与CS");
                return;
            }
            RenderingUtils.ReAllocateIfNeeded(ref topOrthographicDepth,
                new RenderTextureDescriptor(settings.textureSize,settings.textureSize,RenderTextureFormat.RFloat,32),
                FilterMode.Bilinear);
            RenderingUtils.ReAllocateIfNeeded(ref camDepRT,
                new RenderTextureDescriptor( (int)(Camera.main.pixelWidth / unsampleInt) , 
                (int)Camera.main.pixelHeight / unsampleInt, RenderTextureFormat.RFloat,0),
                FilterMode.Bilinear);

            ConfigureTarget(topOrthographicDepth);
            // 配置清除规则：清除颜色为0（深度值0表示最近），清除深度和颜色
            ConfigureClear(ClearFlag.All, Color.black);
            
        }
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            
            // 安全校验
            if(Camera.main == null||settings.topOrthDepMat == null || settings.viewSpaceDepMat == null || settings.computeShader == null) 
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
                settings.topOrthDepMat.SetVector("_BoundsYMinMax", new Vector2(camBounds.min.y, camBounds.max.y));
                // 在本次渲染过程中，强制让所有被选中的物体，
                // 都使用你指定的这个材质（depthMaterial）来渲染，临时替换掉它们自己的材质。
                drawSetting.overrideMaterial = settings.topOrthDepMat;
                var filterSetting = new FilteringSettings(RenderQueueRange.all, settings.renderLayer);
                context.DrawRenderers(renderingData.cullResults, ref drawSetting, ref filterSetting);
            }
            // 这个是不论在运行状态还是在视图模式，都是场景中设置的主摄像机，所以始终用主摄像机做遮挡剔除
            cmd.SetViewProjectionMatrices(Camera.main.worldToCameraMatrix, Camera.main.projectionMatrix);               

            // 正常摄像机视角下的深度信息，不知道为什么， renderingData.cameraData.renderer.cameraDepthTargetHandle 结果不对
            // 只能自己渲染一张 视图空间的线性深度信息
            using (new ProfilingScope(cmd, new ProfilingSampler("Cam Depth Map RT")))
            {
                cmd.SetRenderTarget(camDepRT);
                cmd.ClearRenderTarget(true,true, Color.black);
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();
                var drawSetting = CreateDrawingSettings(shaderTagList, ref renderingData, renderingData.cameraData.defaultOpaqueSortFlags);
                drawSetting.overrideMaterial = settings.viewSpaceDepMat;
                var filterSetting = new FilteringSettings(RenderQueueRange.all, settings.renderLayer);
                context.DrawRenderers(renderingData.cullResults, ref drawSetting, ref filterSetting);
            }

            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            
            // 这个是在运行模式是主摄像机，在视图模式是视图摄像机
            cmd.SetViewProjectionMatrices(renderingData.cameraData.camera.worldToCameraMatrix, renderingData.cameraData.camera.projectionMatrix); 
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();

            // ================== 以下使用compute shader计算草地位置 =================
            int typeCounters = myRendererData.instance.dataArray.Length; // 类型数量,通过获取单例当中的组数量来得知
            _countersBuffer?.Release();
            _countersBuffer = new ComputeBuffer(typeCounters, sizeof(uint)); 
            // 重置计数器
            uint[] zeroCounters = new uint[2];
            _countersBuffer.SetData(zeroCounters);
            _countersBuffer.SetCounterValue(0);

            _segmentedBuffer?.Release();
            _segmentedBuffer = new ComputeBuffer((int)(100000 * settings.maxBufferCount) , sizeof(float) * 3);


            // 将Compute Shader的计算包装成一个函数
            ComputePosBuffer(ref cmd,settings.computeShader,
                centerPos,camBounds,1.0f,1000.0f,   ref _segmentedBuffer , ref _countersBuffer  );

            // 将草位置缓冲区设为全局，供实例化渲染Shader使用
            cmd.SetGlobalTexture("_GrassHeightMap",topOrthographicDepth);
            cmd.SetGlobalVector("_GrassUVParams",new Vector4(centerPos.x,centerPos.y,settings.textureUpdateThreshold,settings.drawDistance));
            cmd.SetGlobalBuffer("_GrassPositions", _segmentedBuffer);

            if(myRendererData.instance != null)
            {
                // 传递最大实例数跟单例
                for (int t = 0 ; t < 2 ; t ++)
                {
                    cmd.SetComputeBufferParam(settings.computeShader,1,"_CountersR",_countersBuffer);
                    cmd.SetComputeBufferParam(settings.computeShader,1,"_Args",myRendererData.instance.argsBufferArray[t]);
                    cmd.SetComputeIntParam(settings.computeShader,"_TypeIndex",t);
                    cmd.DispatchCompute(settings.computeShader,1,1,1, 1);
                }

                if (myRendererData.instance.previewVisibleGrassCount)
                {
                    cmd.CopyCounterValue(_countersBuffer, myRendererData.instance.tBuffer, 0);
                }
            }

            // 执行ComputeShader相关命令
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            
            // 释放CommandBuffer（归还到池）
            CommandBufferPool.Release(cmd);


            // =================== 可视化调试部分 ===================
            settings.showMat.SetTexture("_MainTex",camDepRT);
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
        public void ComputePosBuffer(ref CommandBuffer cmd , ComputeShader cs,
            Vector3 centerPos,Bounds camBounds,float spaciingScale,float extraDistanceRemoval ,
            ref ComputeBuffer segmentedBuffer , ref ComputeBuffer countersBuffer)
        {
            float spacing = settings.spacing * spaciingScale;
            // 计算草的网格大小（XZ方向的网格数量）
            Vector2Int gridSize = new Vector2Int(
                Mathf.CeilToInt(camBounds.size.x / spacing),
                Mathf.CeilToInt(camBounds.size.z / spacing)
            );
            // 计算网格的起始索引（定位草的网格位置）
            Vector2Int gridStartIndex = new Vector2Int(
                Mathf.FloorToInt(camBounds.min.x / spacing),
                Mathf.FloorToInt(camBounds.min.z / spacing)
            );
            // ========== 关键修改：使用CommandBuffer设置所有参数 ==========
            cmd.SetComputeFloatParam(cs, "_spacing", spacing);
            cmd.SetComputeFloatParam(cs, "_drawDistance", settings.drawDistance);
            cmd.SetComputeFloatParam(cs, "_textureUpdateThreshold", settings.textureUpdateThreshold);
            cmd.SetComputeFloatParam(cs, "_extraDistanceRemoval", extraDistanceRemoval);
            
            // Vector2需要转换为Vector4
            cmd.SetComputeVectorParam(cs, "_gridStartIndex", new Vector4(gridStartIndex.x, gridStartIndex.y, 0, 0));
            cmd.SetComputeVectorParam(cs, "_gridSize", new Vector4(gridSize.x, gridSize.y, 0, 0));
            cmd.SetComputeVectorParam(cs, "_camPosition", new Vector4(Camera.main.transform.position.x, 
                                                                       Camera.main.transform.position.y, 
                                                                       Camera.main.transform.position.z, 0));
            cmd.SetComputeVectorParam(cs, "_centerPos", new Vector4(centerPos.x, centerPos.y, 0, 0));
            cmd.SetComputeVectorParam(cs, "_boundsMin", new Vector4(camBounds.min.x, camBounds.min.y, camBounds.min.z, 0));
            cmd.SetComputeVectorParam(cs, "_boundsMax", new Vector4(camBounds.max.x, camBounds.max.y, camBounds.max.z, 0));
            cmd.SetComputeMatrixParam(cs, "_VPMatrix", Camera.main.projectionMatrix * Camera.main.worldToCameraMatrix);
            cmd.SetComputeMatrixParam(cs, "_VMatrix", Camera.main.worldToCameraMatrix);

            cmd.SetComputeTextureParam(cs, 0, "_grassHeightTex", topOrthographicDepth);
            cmd.SetComputeTextureParam(cs,0,"_CameraDepthTexture",camDepRT);


            cmd.SetComputeBufferParam(cs, 0, "_Counters", countersBuffer);
            cmd.SetComputeBufferParam(cs, 0, "_SegmentedBuffer", segmentedBuffer);

            // 调度ComputeShader执行（线程组数量：X=gridSize.x/8，Y=gridSize.y/8，Z=1）
            // 线程组大小通常设为8x8x1，因此需要除以8并向上取整
            cmd.DispatchCompute(cs,
                0,
                Mathf.CeilToInt((float)gridSize.x / 8),
                Mathf.CeilToInt((float)gridSize.y / 8), 
            1);
        }
        public void Dispose()
        {
            topOrthographicDepth?.Release();
            camDepRT?.Release();
            // ComputeBuffer的释放后续再优化
            if (_countersBuffer != null)
            {
                _countersBuffer.Release();
                _countersBuffer = null;
            }
            if (_segmentedBuffer != null)
            {
                _segmentedBuffer.Release();
                _segmentedBuffer = null;
            }
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