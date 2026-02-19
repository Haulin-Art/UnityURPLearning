using System.Collections.Generic;
using System.Linq;
using Unity.Mathematics;
//using Unity.VisualScripting;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.UI;

public class GrassDataRendererFeature : ScriptableRendererFeature
{
    [SerializeField]private LayerMask layer;
    [SerializeField]private Material mat;
    [SerializeField]private ComputeShader cs;
    
    
    class GrassDataPass : ScriptableRenderPass
    {
        // List<ShaderTagId> 是引用类型，如果只声明变量而不初始化，它的默认值是 null（不是空列表）。
        // 之后你如果直接用它（比如调用 shaderTagList.Add(...)），会直接报 NullReferenceException（空引用异常）—— 因为你在操作一个 “不存在的对象”。
        // 这行代码是 **“声明变量的同时，直接初始化一个空的 List 对象”，这样 shaderTagList 从一开始就是一个可用的空列表 **（不是 null）
        private List<ShaderTagId> shaderTagList = new List<ShaderTagId>();
        private RTHandle heightRT;
        private RTHandle heightDepRT;
        private RTHandle maskRT;
        private RTHandle colorRT;
        private RTHandle slopeRT;

        private LayerMask heightLayer;
        private Material heightMat;
        private ComputeShader heightCS;
        // 构造函数：接收外部参数，初始化Shader标签列表
        public GrassDataPass(LayerMask heightLayer,Material heightMat,ComputeShader heightCS)
        {
            //this.name = "GrassDataPass";
            this.heightLayer = heightLayer;
            this.heightMat = heightMat;
            this.heightCS = heightCS;

            shaderTagList.Add(new ShaderTagId("SRPDefaultUnlit"));
            shaderTagList.Add(new ShaderTagId("UniversalForward"));
            shaderTagList.Add(new ShaderTagId("UniversalForwardOnly"));
        }
        // // 重写：相机设置阶段调用（用于初始化渲染纹理等资源）
        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            int texSize = 2048;
            // 渲染工具类.重新分配渲染纹理（按需创建/复用）：RenderingUtils.ReAllocateIfNeeded会自动管理资源
            RenderingUtils.ReAllocateIfNeeded(ref heightRT,
                new RenderTextureDescriptor(texSize,texSize,RenderTextureFormat.RGFloat,0),// 格式RGFloat（存高度）、无深度缓冲
                FilterMode.Bilinear);
            RenderingUtils.ReAllocateIfNeeded(ref heightDepRT,
                new RenderTextureDescriptor(texSize,texSize,RenderTextureFormat.RFloat,32),// 格式RFloat、32位深度缓冲
                FilterMode.Bilinear);
            RenderingUtils.ReAllocateIfNeeded(ref maskRT,
                new RenderTextureDescriptor(texSize,texSize,RenderTextureFormat.RFloat,0),// 格式RFloat（存遮罩）
                FilterMode.Bilinear);
            RenderingUtils.ReAllocateIfNeeded(ref colorRT,
                new RenderTextureDescriptor(texSize,texSize,RenderTextureFormat.ARGBFloat,0),// 格式ARGBFloat（存颜色）
                FilterMode.Bilinear);
            RenderingUtils.ReAllocateIfNeeded(ref slopeRT,
                new RenderTextureDescriptor(texSize,texSize,RenderTextureFormat.ARGBFloat,0),// 格式ARGBFloat（存坡度）
                FilterMode.Bilinear);
            // 配置当前Pass的渲染目标：指定颜色附件+深度附件
            ConfigureTarget(heightRT,heightDepRT);
            // 配置渲染目标的清除规则：清除所有内容，清除颜色为黑色
            ConfigureClear(ClearFlag.All, Color.black);
        }

        ComputeBuffer grassPositionBuffer;
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (!InfiniteGrassRenderer.instance||heightMat==null||heightCS==null)
            {
                return;
            }
            // 从URP的CommandBuffer对象池获取CommandBuffer（减少GC）
            // CommandBuffer的作用：记录一系列GPU指令（如设置矩阵、绘制物体、调度计算着色器）
            CommandBuffer cmd = CommandBufferPool.Get();
            // 从草渲染器单例（InfiniteGrassRenderer）中获取配置参数
            float spacing = InfiniteGrassRenderer.instance.spacing; // 草的分布间距
            float fullDensityDistance = InfiniteGrassRenderer.instance.fullDensityDistance; // 草保持全密度的距离
            float drawDistance = InfiniteGrassRenderer.instance.drawDistance; // 草的最大绘制距离
            float maxBufferCount = InfiniteGrassRenderer.instance.maxBufferCount; // 草位置缓冲区的最大容量
            float textureUpdateThreshold = InfiniteGrassRenderer.instance.textureUpdateThreshold; // 纹理更新阈值（控制更新频率）
        
            // 计算相机周围得包围盒
            Bounds cameraBounds = CalCamBounds(Camera.main,drawDistance);
            // 处理相机的XZ位置：减少纹理频繁更新
            Vector2 centerPos = new Vector2(
                Mathf.Floor(Camera.main.transform.position.x/textureUpdateThreshold),
                Mathf.Floor(Camera.main.transform.position.z/textureUpdateThreshold)
            );
            // V矩阵
            Matrix4x4 vMatrix = Matrix4x4.TRS(
                new Vector3(centerPos.x,cameraBounds.max.y,centerPos.y),
                Quaternion.LookRotation(-Vector3.up),
                new Vector3(1,-1,1)
            ).inverse;
            // P矩阵
            Matrix4x4 pMatrix = Matrix4x4.Ortho(
                -(drawDistance+textureUpdateThreshold), // 左边界
                (drawDistance+textureUpdateThreshold),// 右边界
                -(drawDistance+textureUpdateThreshold),// 下边界
                (drawDistance+textureUpdateThreshold),// 上边界
                0,// 近裁剪面（相机位置）
                cameraBounds.size.y // 远裁剪面（地形高度范围）
            );
            // 将构建好的视矩阵+投影矩阵设置给相机
            // 作用：让后续的绘制操作（如渲染地形）使用这个“从上方正交视角”的矩阵，而不是主相机默认的透视矩阵
            cmd.SetViewProjectionMatrices(vMatrix,pMatrix);

            
            // 性能分析作用域：标记这段逻辑的性能数据（在Profiler中显示为“Grass Height Map RT1”）
            using (new ProfilingScope(cmd, new ProfilingSampler(name: "Grass Height Map RT1")))
            {
                // 执行当前CommandBuffer中记录的GPU指令（把之前的指令提交给GPU执行）
                context.ExecuteCommandBuffer(cmd);
                // 清空CommandBuffer：执行完后清空，避免后续重复执行旧指令
                cmd.Clear();

                // 注释：替换“heightMapLayer图层”物体的材质，并用该材质渲染它们
                // 1. 创建绘制设置（DrawingSettings）：指定要渲染的Shader标签、排序方式等
                //    参数：shaderTagsList（之前定义的Shader通道标签）、渲染数据、默认不透明物体排序标记
                var drawSetting = CreateDrawingSettings(shaderTagList, ref renderingData, renderingData.cameraData.defaultOpaqueSortFlags);

                // 2. 给高度图材质传递参数：相机包围盒的Y轴最小/最大值（后续材质Shader用这个计算地形高度）
                heightMat.SetVector(name: "_BoundsYMinMax",new Vector2(cameraBounds.min.y, cameraBounds.max.y));
                // 3. 覆盖绘制材质：让本次绘制强制使用heightMapMat（忽略物体自身的材质）
                drawSetting.overrideMaterial = heightMat;

                // 4. 创建过滤设置（FilteringSettings）：指定只渲染“heightMapLayer图层”的物体
                //    参数：渲染队列范围（所有）、要过滤的图层（heightMapLayer）
                var filterSetting = new FilteringSettings(RenderQueueRange.all, heightLayer);

                // 5. 执行绘制：渲染符合“过滤设置（heightMapLayer图层）”的物体，使用上面的“绘制设置（覆盖材质为heightMapMat）”
                context.DrawRenderers(renderingData.cullResults, ref drawSetting, ref filterSetting);
            }
            

        }

        public override void OnCameraCleanup(CommandBuffer cmd)
        {
        }
        // 释放资源
        public void Dispose()
        {
            heightRT?.Release();
            heightDepRT?.Release();
            maskRT?.Release();
            colorRT?.Release();
            slopeRT?.Release();
        }
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
    }

    GrassDataPass grassDtPass;

    // 这个方法两个作用，一是新建Pass，2是设置Pass的注入顺序
    //thisMethodHasTwoFunctionsFirstToCreateANewPassAndSecondToSetTheInjectionOrderOfThePass
    public override void Create()
    {
        grassDtPass = new GrassDataPass(layer,mat,cs);

        // Configures where the render pass should be injected.
        grassDtPass.renderPassEvent = RenderPassEvent.AfterRenderingOpaques;
    }
    // 将自定义类加入渲染队列
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(grassDtPass);
    }
    // 释放资源
    protected override void Dispose(bool disposing)
    {
        if(disposing){
            grassDtPass.Dispose();
        }
    }

}


