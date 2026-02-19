using System;
using System.Collections.Generic;
using Unity.Mathematics;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class PerObjectShadowRF : ScriptableRendererFeature
{
    // 输入的参数引用
    public LayerMask layerMask;
    public String m_Tag = "BG"; // 需要排除的物体标签，用于在自动计算摄像机的位置的时候不考虑背景
    [Space(10)] // 10像素间距
    [Header("必要文件")]
    public Material SoftShadowMat;
    public ComputeShader BlurComputeShader;

    [Space(10)] // 10像素间距
    [Header("阴影贴图设置")]
    //[Tooltip("阴影贴图的大小")]
    [Range(0.1f, 5.0f)]
    [SerializeField] public float ShadowFieldSize = 1.0f; // 阴影覆盖场景范围
    [Min(512f)] // 最小值限制
    [SerializeField] public int ShadowMapSize = 2048;
    [Range(1, 4)] // 滑块范围
    [SerializeField] private int UnsampleInt = 2;
    [Range(1,16)]
    [SerializeField] private int PoissonCount = 5;
    [Range(0.0001f,0.001f)]
    [SerializeField] private float _initPCSS = 0.0005f; // PCSS默认模糊
    [Range(0.001f,0.02f)]
    [SerializeField] private float _distancePCSS = 0.015f; // 距离PCSS模糊强度
    [Range(0,5)]
    [SerializeField] private int blurSampleCount = 2; // 模糊采样次数
    [Range(0.5f,5.0f)]
    [SerializeField] private float blurStepSize = 1.0f; // 模糊采样步长



    PerObjShadowRP m_ScriptablePass;

    /// <inheritdoc/>
    public override void Create()
    {
        m_ScriptablePass = new PerObjShadowRP(SoftShadowMat,layerMask,m_Tag,BlurComputeShader,
                                                UnsampleInt,ShadowMapSize,PoissonCount,
                                                _initPCSS,_distancePCSS,
                                                blurSampleCount,blurStepSize,ShadowFieldSize);
        m_ScriptablePass.renderPassEvent = RenderPassEvent.AfterRenderingPrePasses;
    }
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(m_ScriptablePass);    
    }
    protected override void Dispose(bool disposing)
    {
        if(disposing)
        {
            m_ScriptablePass?.Dispose();
        }
    }

    class PerObjShadowRP : ScriptableRenderPass
    {
        // 使用的RT
        private RTHandle LSDepRT;
        int texSize;
        int unsampleInt = 2; // 降采样系数
        int PoissonCount = 5;
        float _initPCSS = 0.0005f;
        float _distancePCSS = 0.015f;
        int blurSampleCount = 2;
        float blurStepSize = 1.0f;

        private RTHandle VSPCFNoise; // 带有噪点的pcf图，为于视图空间
        private RTHandle dep;
        // 传入的参数
        public Material SoftShadowMat;
        public LayerMask LayerM;
        private String m_Tag ;
        public float len; // 阴影空间的大小

        private bool start; // 是否启用
        private Light ld; // 主光源
        private readonly List<ShaderTagId> shaderTagIds = new List<ShaderTagId>();
        

        private RTHandle CSShadow;
        private ComputeShader _computeShader;


        private Bounds bounds; // 用于合并所有renderer的包围盒，借此计算光源摄像机矩阵
        private List<Renderer> m_Renderer; // 存储所有需要的renderer

        public PerObjShadowRP(Material SoftShadowMat,LayerMask layerM,String m_Tag,
                            ComputeShader cs,int unsampleInt,int texSize,
                            int PoissonCount,
                            float _initPCSS,float _distancePCSS,
                            int blurSampleCount,float blurStepSize,
                            float len)
        {
            this.LayerM = layerM;
            this.m_Tag = m_Tag;
            this.SoftShadowMat = SoftShadowMat;
            _computeShader = cs;

            this.unsampleInt = unsampleInt;
            this.texSize = texSize;
            this.PoissonCount = PoissonCount;

            this._initPCSS = _initPCSS;
            this._distancePCSS = _distancePCSS;

            this.blurSampleCount = blurSampleCount;
            this.blurStepSize = blurStepSize;

            this.len = len;
            // 初始化数据
            // 往灯光方向移动了多少
            len = 1.1f;

            shaderTagIds.Add(new ShaderTagId("SRPDefaultUnlit"));
            shaderTagIds.Add(new ShaderTagId("UniversalForward"));
            shaderTagIds.Add(new ShaderTagId("UniversalForwardOnly"));
        }
        // Pass开始前调用，提前设置当前Pass要用的信息
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
            
            
            RenderingUtils.ReAllocateIfNeeded( ref LSDepRT,
                new RenderTextureDescriptor( texSize , texSize , RenderTextureFormat.RFloat,16),
                FilterMode.Bilinear
            );
            
            RenderingUtils.ReAllocateIfNeeded( ref VSPCFNoise,
                new RenderTextureDescriptor( (int)(Camera.main.pixelWidth / unsampleInt) , 
                (int)Camera.main.pixelHeight /unsampleInt, RenderTextureFormat.RFloat,0),
                FilterMode.Bilinear
            );
            RenderingUtils.ReAllocateIfNeeded( ref dep,
                new RenderTextureDescriptor( (int)(Camera.main.pixelWidth / unsampleInt) , 
                (int)Camera.main.pixelHeight /unsampleInt , RenderTextureFormat.RFloat,16),
                FilterMode.Bilinear
            );


            var descriptor = new RenderTextureDescriptor((int)(Camera.main.pixelWidth / unsampleInt) , 
                (int)Camera.main.pixelHeight /unsampleInt , RenderTextureFormat.RFloat,0)
            {
                enableRandomWrite = true,  // 必须在这里设置
                sRGB = false,
                msaaSamples = 1,
                useMipMap = false,
                autoGenerateMips = false,
                depthBufferBits = 0
            };
            RenderingUtils.ReAllocateIfNeeded( ref CSShadow,
                descriptor,
                FilterMode.Bilinear
            );

            ConfigureTarget(LSDepRT);
            ConfigureClear(ClearFlag.All, Color.white);


            // ======================= 获取所有renderer ================================
            Renderer[] allRenderer = UnityEngine.Object.FindObjectsOfType<Renderer>(); // 获取场景所有的renderer
            bounds.size = Vector3.zero; // 初始化
            foreach (Renderer r in allRenderer)
            {
                if (r.gameObject.layer == 6 && r.isVisible)
                {
                    if(r.gameObject.CompareTag(m_Tag))return; // 如果是背景就不加入
                    //m_Renderer.Add(r); // 将这个renderer加入
                    bounds.Encapsulate(r.bounds); // 合并包围盒
                }
            }
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if(Camera.main == null || !start || SoftShadowMat == null || _computeShader == null)return;

            //LSDepRT.FilterMode = FilterMode.Bilinear;

            CommandBuffer cmd = CommandBufferPool.Get("PerObjShadowPass");
            // 获取包围盒
            Vector3 posCenter = new Vector3(-22.692f,3.2f,12.998f);
            posCenter = bounds.center; // 设置摄像机中点为包围盒中心
            //Debug.Log(bounds.center);
            Vector3 mainLightDir = -ld.transform.forward;
            Vector3 maxDistance = new Vector3(bounds.extents.x, bounds.extents.y, bounds.extents.z);
            len = maxDistance.magnitude - 0.3f;
            //Debug.Log((bounds.size/2.0f).magnitude);
            // 计算摄像机VP矩阵
            // V矩阵
            Matrix4x4 vMatrix = Matrix4x4.TRS(
                posCenter + mainLightDir*len + new Vector3(0,-0.2f,0),
                Quaternion.LookRotation(-mainLightDir),
                new Vector3(1,1,-1) // Z轴取反，不然照的就是反方向了
            ).inverse;
            // P矩阵
            Matrix4x4 pMatrix = Matrix4x4.Ortho(
                -len,len,//上下左右四个角
                -len,len,
                0.001f,//近裁切面
                2.0f*len // 远裁切面
            );

            cmd.SetViewProjectionMatrices(vMatrix,pMatrix);

            
            // 绘制到RT，灯光空间的深度图
            using (new ProfilingScope(cmd, new ProfilingSampler("LS Depth RT")))
            {
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();
                var drawSetting = CreateDrawingSettings(shaderTagIds, ref renderingData, renderingData.cameraData.defaultOpaqueSortFlags);
                //drawSetting.overrideMaterial = POMat;
                var filterSetting = new FilteringSettings(RenderQueueRange.all, LayerM);
                context.DrawRenderers(renderingData.cullResults, ref drawSetting, ref filterSetting);
            }
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();

            // 把摄像机矩阵变换成之前的
            Matrix4x4 cvMatrix = renderingData.cameraData.camera.worldToCameraMatrix;
            cmd.SetViewProjectionMatrices(renderingData.cameraData.camera.worldToCameraMatrix, 
                                renderingData.cameraData.camera.projectionMatrix);
            
            // 设置全局矩阵，用于传入shader
            Matrix4x4 vpMatrix = pMatrix*vMatrix;
            cmd.SetGlobalMatrix("_POSvpM",vpMatrix);
            cmd.SetGlobalVector("_POSLightDir",mainLightDir);
            //cmd.SetGlobalMatrix("_POSpM",pMatrix);
            cmd.SetGlobalTexture("_POSMap",LSDepRT);
            
            

            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();     

            // 绘制PCF阴影,使用材质覆盖，渲染出带有噪点的平滑过渡的PCF的屏幕纹理，好采样
            // 这里必须再额外设置一个作为深度buffer的rt，不然渲染顺序会错误，作为深度缓冲的rt必须得是开启深度的
            cmd.SetRenderTarget(VSPCFNoise,dep);
            cmd.ClearRenderTarget(true,true,new Color(0,0,0,0));
            using (new ProfilingScope(cmd, new ProfilingSampler("VS pcfNoise RT")))
            {
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();  
                    
                var drawSetting = CreateDrawingSettings(shaderTagIds, ref renderingData, renderingData.cameraData.defaultOpaqueSortFlags);
                drawSetting.overrideMaterial = SoftShadowMat;
                // 设置材质参数
                SoftShadowMat.SetFloat("_PoissonCount",PoissonCount);
                SoftShadowMat.SetFloat("_initPCSS",_initPCSS);
                SoftShadowMat.SetFloat("_distancePCSS",_distancePCSS);

                var filterSetting = new FilteringSettings(RenderQueueRange.all, LayerM);
                context.DrawRenderers(renderingData.cullResults, ref drawSetting, ref filterSetting);
                
                //cmd.Blit(renderingData.cameraData.renderer.cameraColorTargetHandle,VSPCFNoise);
            }  
            cmd.SetGlobalTexture("_POSpcf",VSPCFNoise);
            cmd.SetGlobalTexture("_CameraDepthTexture",dep);
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();

            
            // 设置Compute Shader
            int _kernelHandle = _computeShader.FindKernel("CSSoftShadowBlur");
            _computeShader.SetTexture(_kernelHandle,"CSShadow",CSShadow);
            _computeShader.SetTexture(_kernelHandle,"_ScreenShadowMap",VSPCFNoise);
            _computeShader.SetTexture(_kernelHandle,"_CameraDepth",dep);
            _computeShader.SetFloat("SizeW",(int)(Camera.main.pixelWidth / unsampleInt));
            _computeShader.SetFloat("SizeH",(int)Camera.main.pixelHeight /unsampleInt );
            _computeShader.SetFloat("blurSampleCount",blurSampleCount );
            _computeShader.SetFloat("blurStepSize",blurStepSize );

            _computeShader.Dispatch(_kernelHandle, Camera.main.pixelWidth / 8, Camera.main.pixelHeight / 8, 1);

            cmd.SetGlobalTexture("_CSShadow",CSShadow);
            //cmd.SetGlobalTexture("_CSShadow",VSPCFNoise);
            
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            
            CommandBufferPool.Release(cmd);
        }
        public void Dispose()
        {
            LSDepRT?.Release();
            VSPCFNoise?.Release();
            dep?.Release();
            CSShadow?.Release();
        }
    }
}


