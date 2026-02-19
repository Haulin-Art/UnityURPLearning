using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class OutLinePass : ScriptableRendererFeature
{
    public Material mat;
    public Material norMat;
    public float thickness;
    public LayerMask layerMask;
    
    m_OutLinePass m_ScriptablePass;
    public override void Create()
    {
        m_ScriptablePass = new m_OutLinePass(mat,norMat,layerMask);
        m_ScriptablePass.renderPassEvent = RenderPassEvent.AfterRenderingPostProcessing;
    }
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(m_ScriptablePass);
    }
    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            m_ScriptablePass?.Dispos();
        }
    }

    class m_OutLinePass : ScriptableRenderPass
    {
        public Material norMat;
        public Material mat;

        private RTHandle _cameraColorTgt;
        private RTHandle _Nor;
        private RTHandle _Dep;

        public LayerMask LayerM;
        int shaderID = Shader.PropertyToID("_Temp_RT"); // 定义用于申请临时RT的ID

        private readonly List<ShaderTagId> shaderTagIds = new List<ShaderTagId>();


        public m_OutLinePass(Material mat,Material norMat,LayerMask LayerM)
        {
            this.mat = mat;
            this.norMat = norMat;
            this.LayerM = LayerM;


            shaderTagIds.Add(new ShaderTagId("SRPDefaultUnlit"));
            shaderTagIds.Add(new ShaderTagId("UniversalForward"));
            shaderTagIds.Add(new ShaderTagId("UniversalForwardOnly"));
            //shaderTagIds.Add(new ShaderTagId("OutlinePass"));
        }
        public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
            //base.Configure(cmd, cameraTextureDescriptor);
            ConfigureInput(ScriptableRenderPassInput.Depth | ScriptableRenderPassInput.Normal);
        }
        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            if(mat==null || norMat == null )return;

            var camera = renderingData.cameraData.camera;
            if (camera == null) return;
            int unsampleInt = 1; // 降采样系数
            
            RenderingUtils.ReAllocateIfNeeded( ref _Nor,
                new RenderTextureDescriptor( (int)(camera.pixelWidth / unsampleInt) , 
                (int)camera.pixelHeight /unsampleInt, RenderTextureFormat.RG16,0),
                FilterMode.Bilinear
            );
            RenderingUtils.ReAllocateIfNeeded( ref _Dep,
                new RenderTextureDescriptor( (int)(camera.pixelWidth / unsampleInt) , 
                (int)camera.pixelHeight /unsampleInt, RenderTextureFormat.RFloat,16),
                FilterMode.Bilinear
            );

        }
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if(mat==null)return;

            CommandBuffer cmd = CommandBufferPool.Get("OutLinePass");
            // 获取当前相机的画面的配置，用这个描述创建临时RT

            // 在绘制法线/深度前，先清除_Nor和_Dep
            cmd.SetRenderTarget(_Nor);
            cmd.ClearRenderTarget(true, true, Color.black); // 清除法线图
            cmd.SetRenderTarget(_Dep);
            cmd.ClearRenderTarget(true, true, Color.white); // 清除深度图（通常为1表示最远）


            cmd.SetRenderTarget(_Nor,_Dep);
            //ConfigureClear(ClearFlag.All, Color.white);
            // 一、绘制一张带有指定物体场景深度与法向的RT
            using (new ProfilingScope(cmd, new ProfilingSampler("Outline depN RT")))
            {
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();        
                var drawSetting = CreateDrawingSettings(shaderTagIds, ref renderingData, renderingData.cameraData.defaultOpaqueSortFlags);
                drawSetting.overrideMaterial = norMat;
                var filterSetting = new FilteringSettings(RenderQueueRange.all,LayerM);
                context.DrawRenderers(renderingData.cullResults, ref drawSetting, ref filterSetting);
            }
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            
            var descriptor = renderingData.cameraData.cameraTargetDescriptor;
            descriptor.msaaSamples = 1;  // 关键：禁用多重采样
            descriptor.depthBufferBits = 0; // 禁用深度
            cmd.GetTemporaryRT(shaderID ,descriptor);
            //cmd.GetTemporaryRT(shaderID, Camera.main.pixelWidth, Camera.main.pixelHeight, 0, FilterMode.Bilinear, RenderTextureFormat.Default);
            _cameraColorTgt = renderingData.cameraData.renderer.cameraColorTargetHandle;
            
            //mat.SetTexture("_ColorTex",_cameraColorTgt);
            mat.SetTexture("_Nor",_Nor);
            mat.SetTexture("_Dep",_Dep);
            
            cmd.Blit(_cameraColorTgt.nameID,shaderID,mat);
            cmd.Blit(shaderID,_cameraColorTgt.nameID);

            
            context.ExecuteCommandBuffer(cmd);
            cmd.ReleaseTemporaryRT(shaderID); // 释放临时RT
        }
        public override void OnCameraCleanup(CommandBuffer cmd)
        {
        }
        public void Dispos()
        {
            _cameraColorTgt?.Release();
            _Dep?.Release();
            _Nor?.Release();

        }
    }
}


