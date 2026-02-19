using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class NorOutLineRF : ScriptableRendererFeature
{
    public Material mat;
    public String m_Tag = "CES";

    PSMPass m_ScriptablePass;


    /// <inheritdoc/>
    public override void Create()
    {
        m_ScriptablePass = new PSMPass(mat, m_Tag);

        m_ScriptablePass.renderPassEvent = RenderPassEvent.AfterRenderingTransparents;
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(m_ScriptablePass);
    }

    protected override void Dispose(bool disposing)
    {
        m_ScriptablePass.Dispose();
    }


    class PSMPass : ScriptableRenderPass
    {
        private Material mat;
        private String m_Tag;
        private List<Renderer> m_Renderer = new List<Renderer>();
        private ProfilingSampler m_pro;
        Bounds bounds; // 总包围盒
        public PSMPass(Material mat, String tag)
        {
            this.mat = mat;
            this.m_Tag = tag;
        }
        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            // 关键步骤：配置渲染目标[1](@ref)
            //ConfigureTarget(RT01);
            // 清除RT为透明黑色
            //ConfigureClear(ClearFlag.All, Color.clear);
                m_Renderer.Clear();

            Renderer[] allRenderers = UnityEngine.Object.FindObjectsOfType<Renderer>();
            bounds.size = Vector3.zero;
            foreach (Renderer r in allRenderers)
            {
                //if (r.gameObject.activeInHierarchy && r.gameObject.layer == 6 && r != null && r.isVisible)
                if (r.gameObject.CompareTag(m_Tag) && r.isVisible)
                {
                    m_Renderer.Add(r);
                    bounds.Encapsulate(r.bounds);// 合并所有包围盒
                }
            }
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get();
            using (new ProfilingScope(cmd,m_pro))
            {
                foreach (Renderer ren in m_Renderer)
                {
                    // 获取物体原本材质上的颜色贴图，用于传递，不然一个颜色比如再白的区域还行，黑色就可能不对了
                    Material[] matt = ren.sharedMaterials;

                    OutLineRenderData data = ren.GetComponent<OutLineRenderData>(); // 获取设定的用于传递数据的类
                    // 创建或获取一个新的MaterialPropertyBlock
                    MaterialPropertyBlock mpb = new MaterialPropertyBlock();
                    // 先获取Renderer当前的属性（可选，用于合并）
                    ren.GetPropertyBlock(mpb);
                    // 将自定义属性设置到MaterialPropertyBlock中                 
                    if (data != null )
                    {
                        mpb.SetColor("_LineCol",data.OutLineColor);
                        mpb.SetFloat("_Thickness",data.OutLineThickness);
                        // 这里需要注意"_KDTex"的名称得是唯一的，只有那个描边材质有的，不然物体材质中同名的会被强制替换
                        mpb.SetTexture("_KDTex",matt[0].GetTexture("_DTex"));
                    }
                    // 将设置好的属性块应用到此Renderer
                    ren.SetPropertyBlock(mpb);
                    // 此时，DrawRenderer调用会自动使用刚刚设置的MaterialPropertyBlock
                    for (int i = 0 ; i < ren.sharedMaterials.Length ; i++)
                    {
                        // ren.sharedMaterial
                        cmd.DrawRenderer(ren,mat,i,0);
                    }
                }
                context.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
            }
        }

        public override void OnCameraCleanup(CommandBuffer cmd)
        {
        }
        public void Dispose()
        {
        }
    }
    
}


