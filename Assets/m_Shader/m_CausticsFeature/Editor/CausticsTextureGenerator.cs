using UnityEngine;
using UnityEditor;

namespace FluidFlux.Caustics
{
    /// <summary>
    /// 焦散纹理生成器
    /// 提供编辑器菜单项，用于程序化生成焦散纹理
    /// </summary>
    public static class CausticsTextureGenerator
    {
        /// <summary>
        /// 菜单项：Assets/Create/FluidFlux/Caustics Texture
        /// 点击后生成焦散纹理并保存为PNG文件
        /// </summary>
        [MenuItem("Assets/Create/FluidFlux/Caustics Texture")]
        public static void GenerateCausticsTexture()
        {
            // 设置生成纹理的分辨率
            int resolution = 512;
            
            // 创建Texture2D对象，启用Mipmap
            Texture2D texture = new Texture2D(resolution, resolution, TextureFormat.RGB24, true);
            
            // 查找焦散生成器Shader
            Shader causticsShader = Shader.Find("Hidden/FluidFlux/CausticsGenerator");
            if (causticsShader == null)
            {
                Debug.LogError("CausticsGenerator shader not found!");
                return;
            }

            // 创建临时材质
            Material material = new Material(causticsShader);
            
            // 创建临时渲染纹理
            RenderTexture rt = RenderTexture.GetTemporary(resolution, resolution, 0, RenderTextureFormat.ARGB32);
            
            // 使用Shader的Pass 1（RGB通道）渲染焦散效果
            Graphics.Blit(null, rt, material, 1);

            // 从渲染纹理读取像素数据
            RenderTexture.active = rt;
            texture.ReadPixels(new Rect(0, 0, resolution, resolution), 0, 0);
            texture.Apply();
            RenderTexture.active = null;

            // 释放临时渲染纹理
            RenderTexture.ReleaseTemporary(rt);

            // 弹出保存文件对话框
            string path = EditorUtility.SaveFilePanelInProject(
                "Save Caustics Texture",
                "CausticsTexture",
                "png",
                "Save caustics texture as PNG");

            // 如果用户选择了保存路径
            if (!string.IsNullOrEmpty(path))
            {
                // 将纹理编码为PNG
                byte[] bytes = texture.EncodeToPNG();
                
                // 写入文件
                System.IO.File.WriteAllBytes(path, bytes);
                
                // 导入到Unity资源数据库
                AssetDatabase.ImportAsset(path);
                
                // 设置纹理导入参数
                TextureImporter importer = AssetImporter.GetAtPath(path) as TextureImporter;
                if (importer != null)
                {
                    // 设置为重复模式，适合焦散纹理
                    importer.wrapMode = TextureWrapMode.Repeat;
                    importer.SaveAndReimport();
                }

                Debug.Log($"Caustics texture saved to: {path}");
            }

            // 清理临时对象
            Object.DestroyImmediate(material);
            Object.DestroyImmediate(texture);
        }
    }
}
