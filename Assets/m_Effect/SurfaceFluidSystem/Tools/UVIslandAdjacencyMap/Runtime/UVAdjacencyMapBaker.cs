using System.Collections.Generic;
using UnityEngine;

namespace UVAdjacencyMap
{
    /// <summary>
    /// UV邻接图烘焙器
    /// 输出格式：R=邻接UV.x, G=邻接UV.y, B=邻接边缘遮罩, A=UV岛范围遮罩
    /// 支持PNG、EXR、RenderTexture三种输出格式
    /// </summary>
    public class UVAdjacencyMapBaker
    {
        #region 数据结构

        public enum OutputFormat
        {
            PNG,    // 8位精度，兼容性好
            EXR,    // 32位浮点精度
            RT      // RenderTexture，运行时使用
        }

        public struct BakeSettings
        {
            public int resolution;
            public int edgePadding;
            public float uvEpsilon;
            public int uvChannel;
            public bool enableDebugLog;
            public OutputFormat outputFormat;

            public static BakeSettings Default => new BakeSettings
            {
                resolution = 1024,
                edgePadding = 4,
                uvEpsilon = 0.001f,
                uvChannel = 0,
                enableDebugLog = false,
                outputFormat = OutputFormat.RT
            };
        }

        public struct BakeResult
        {
            public Texture2D texture2D;         // Texture2D版本（PNG/EXR）
            public RenderTexture renderTexture; // RenderTexture版本
            public UVAdjacencyMapBuilder.BuildResult buildResult;
            public bool success;
            public string errorMessage;
        }

        /// <summary>
        /// 像素数据结构
        /// </summary>
        private struct PixelData
        {
            public Vector2 adjacentUV;
            public float distance;
            public bool hasData;
            public bool isInUVIsland;
        }

        #endregion

        #region 公共方法

        public static BakeResult Bake(Mesh mesh, BakeSettings settings)
        {
            BakeResult result = new BakeResult
            {
                success = false,
                texture2D = null,
                renderTexture = null,
                buildResult = default,
                errorMessage = ""
            };

            if (mesh == null)
            {
                result.errorMessage = "Mesh为空！";
                return result;
            }

            if (mesh.uv == null || mesh.uv.Length == 0)
            {
                result.errorMessage = "Mesh没有UV坐标！";
                return result;
            }

            UVAdjacencyMapBuilder.BuildResult buildResult = UVAdjacencyMapBuilder.Build(
                mesh, settings.uvChannel, settings.uvEpsilon);
            result.buildResult = buildResult;

            if (buildResult.seams == null || buildResult.seams.Count == 0)
            {
                result.errorMessage = "没有找到UV接缝";
                return result;
            }

            if (settings.enableDebugLog)
            {
                int validateCount = Mathf.Min(5, buildResult.seams.Count);
                Debug.Log($"[UV邻接图] 开始验证前 {validateCount} 条接缝的映射关系...");
                for (int i = 0; i < validateCount; i++)
                {
                    UVAdjacencyMapBuilder.ValidateSeamMapping(buildResult.seams[i], i);
                }
                
                UVAdjacencyMapBuilder.CheckAdjacentSeamsConsistency(buildResult.seams);
            }

            // 烘焙纹理数据
            Texture2D texture = BakeWithCPU(mesh, buildResult, settings);

            if (texture != null)
            {
                result.texture2D = texture;
                
                // 验证纹理数据
                if (settings.enableDebugLog)
                {
                    Color[] pixels = texture.GetPixels();
                    int nonZeroCount = 0;
                    int hasAdjacencyCount = 0;
                    int inIslandCount = 0;
                    
                    for (int i = 0; i < pixels.Length; i++)
                    {
                        if (pixels[i].a > 0) inIslandCount++;
                        if (pixels[i].b > 0) hasAdjacencyCount++;
                        if (pixels[i].r != 0 || pixels[i].g != 0) nonZeroCount++;
                    }
                    
                    Debug.Log($"[UV邻接图] 纹理数据验证:\n" +
                        $"- 总像素: {pixels.Length}\n" +
                        $"- UV岛内像素: {inIslandCount}\n" +
                        $"- 有邻接信息像素: {hasAdjacencyCount}\n" +
                        $"- RG非零像素: {nonZeroCount}");
                }
                
                // 根据输出格式创建对应的纹理
                if (settings.outputFormat == OutputFormat.RT)
                {
                    result.renderTexture = CreateRenderTexture(texture);
                    Debug.Log($"[UV邻接图] 已创建RenderTexture: {result.renderTexture.width}x{result.renderTexture.height}");
                }
                
                result.success = true;
            }

            return result;
        }

        /// <summary>
        /// 保存纹理到文件
        /// </summary>
        public static bool SaveTexture(Texture2D texture, string path, OutputFormat format)
        {
            if (texture == null || string.IsNullOrEmpty(path))
                return false;

            try
            {
                byte[] bytes;
                
                if (format == OutputFormat.PNG)
                {
                    // PNG需要8位精度，创建专门的纹理
                    Texture2D pngTex = new Texture2D(texture.width, texture.height, TextureFormat.RGBA32, false);
                    Color[] pixels = texture.GetPixels();
                    
                    // PNG格式：保持原始数据，但转换为8位
                    pngTex.SetPixels(pixels);
                    pngTex.Apply();
                    bytes = pngTex.EncodeToPNG();
                    
                    if (Application.isPlaying)
                        UnityEngine.Object.Destroy(pngTex);
                    else
                        UnityEngine.Object.DestroyImmediate(pngTex);
                        
                    Debug.Log($"[UV邻接图] PNG纹理已保存（8位精度）: {path}");
                }
                else // EXR
                {
                    // EXR保持32位浮点精度
                    bytes = texture.EncodeToEXR(Texture2D.EXRFlags.CompressZIP);
                    Debug.Log($"[UV邻接图] EXR纹理已保存（32位浮点精度）: {path}");
                }
                
                System.IO.File.WriteAllBytes(path, bytes);
                return true;
            }
            catch (System.Exception e)
            {
                Debug.LogError($"[UV邻接图] 保存纹理失败: {e.Message}");
                return false;
            }
        }

        /// <summary>
        /// 创建RenderTexture - 使用更可靠的数据传递方式
        /// </summary>
        private static RenderTexture CreateRenderTexture(Texture2D texture)
        {
            if (texture == null)
                return null;

            // 创建ARGBFloat格式的RenderTexture
            RenderTexture rt = new RenderTexture(texture.width, texture.height, 0, RenderTextureFormat.ARGBFloat);
            rt.wrapMode = TextureWrapMode.Clamp;
            rt.filterMode = FilterMode.Bilinear;
            rt.Create();

            // 方法1: 使用RenderTexture.active直接写入像素数据
            RenderTexture prevRT = RenderTexture.active;
            try
            {
                RenderTexture.active = rt;
                
                // 创建临时Texture2D并读取像素
                Texture2D tempTex = new Texture2D(texture.width, texture.height, TextureFormat.RGBAFloat, false);
                tempTex.SetPixels(texture.GetPixels());
                tempTex.Apply();
                
                // 使用GL.IssuePluginEvent确保渲染管线刷新
                GL.InvalidateState();
                
                // 使用Graphics.CopyTexture（更可靠）
                Graphics.CopyTexture(tempTex, 0, 0, rt, 0, 0);
                
                // 验证数据是否写入成功
                Texture2D verifyTex = new Texture2D(rt.width, rt.height, TextureFormat.RGBAFloat, false);
                verifyTex.ReadPixels(new Rect(0, 0, rt.width, rt.height), 0, 0);
                verifyTex.Apply();
                
                Color[] pixels = verifyTex.GetPixels();
                int nonZeroCount = 0;
                for (int i = 0; i < Mathf.Min(100, pixels.Length); i++)
                {
                    if (pixels[i].r != 0 || pixels[i].g != 0 || pixels[i].b != 0 || pixels[i].a != 0)
                    {
                        nonZeroCount++;
                    }
                }
                Debug.Log($"[UV邻接图] RenderTexture验证: 前100像素中有{nonZeroCount}个非零像素");
                
                // 清理临时纹理
                if (Application.isPlaying)
                {
                    UnityEngine.Object.Destroy(tempTex);
                    UnityEngine.Object.Destroy(verifyTex);
                }
                else
                {
                    UnityEngine.Object.DestroyImmediate(tempTex);
                    UnityEngine.Object.DestroyImmediate(verifyTex);
                }
            }
            finally
            {
                RenderTexture.active = prevRT;
            }

            return rt;
        }

        #endregion

        #region CPU烘焙

        private static Texture2D BakeWithCPU(Mesh mesh, UVAdjacencyMapBuilder.BuildResult buildResult, BakeSettings settings)
        {
            int resolution = settings.resolution;
            
            PixelData[] pixelData = new PixelData[resolution * resolution];
            for (int i = 0; i < pixelData.Length; i++)
            {
                pixelData[i] = new PixelData { hasData = false, distance = float.MaxValue, isInUVIsland = false };
            }

            // Step 1: 烘焙UV岛遮罩
            BakeUVIslandMask(pixelData, mesh, settings.uvChannel, resolution);
            
            // Step 2: 写入边缘邻接信息
            WriteEdgeAdjacencyCPU(pixelData, buildResult.seams, resolution, settings.edgePadding, settings.enableDebugLog);
            
            // 转换为颜色数组
            Color[] pixels = new Color[resolution * resolution];
            for (int i = 0; i < pixels.Length; i++)
            {
                if (pixelData[i].hasData)
                {
                    float aChannel = pixelData[i].isInUVIsland ? 1f : 0f;
                    pixels[i] = new Color(pixelData[i].adjacentUV.x, pixelData[i].adjacentUV.y, 1, aChannel);
                }
                else if (pixelData[i].isInUVIsland)
                {
                    pixels[i] = new Color(0, 0, 0, 1);
                }
                else
                {
                    pixels[i] = new Color(0, 0, 0, 0);
                }
            }
            
            // 使用RGBAFloat格式
            Texture2D texture = new Texture2D(resolution, resolution, TextureFormat.RGBAFloat, false);
            texture.SetPixels(pixels);
            texture.Apply();
            
            return texture;
        }
        
        private static void BakeUVIslandMask(PixelData[] pixelData, Mesh mesh, int uvChannel, int resolution)
        {
            int[] triangles = mesh.triangles;
            Vector2[] uvs = uvChannel == 0 ? mesh.uv : mesh.uv2;
            
            if (uvs == null || uvs.Length == 0)
                return;
            
            int triangleCount = triangles.Length / 3;
            
            for (int triIndex = 0; triIndex < triangleCount; triIndex++)
            {
                int i0 = triangles[triIndex * 3 + 0];
                int i1 = triangles[triIndex * 3 + 1];
                int i2 = triangles[triIndex * 3 + 2];
                
                Vector2 uv0 = uvs[i0];
                Vector2 uv1 = uvs[i1];
                Vector2 uv2 = uvs[i2];
                
                RasterizeTriangle(pixelData, uv0, uv1, uv2, resolution);
            }
        }
        
        private static void RasterizeTriangle(PixelData[] pixelData, Vector2 uv0, Vector2 uv1, Vector2 uv2, int resolution)
        {
            int minX = Mathf.FloorToInt(Mathf.Min(uv0.x, uv1.x, uv2.x) * resolution);
            int maxX = Mathf.CeilToInt(Mathf.Max(uv0.x, uv1.x, uv2.x) * resolution);
            int minY = Mathf.FloorToInt(Mathf.Min(uv0.y, uv1.y, uv2.y) * resolution);
            int maxY = Mathf.CeilToInt(Mathf.Max(uv0.y, uv1.y, uv2.y) * resolution);
            
            minX = Mathf.Max(0, minX - 1);
            maxX = Mathf.Min(resolution - 1, maxX + 1);
            minY = Mathf.Max(0, minY - 1);
            maxY = Mathf.Min(resolution - 1, maxY + 1);
            
            float pixelSize = 1f / resolution;
            
            for (int y = minY; y <= maxY; y++)
            {
                for (int x = minX; x <= maxX; x++)
                {
                    float px = (float)x / resolution;
                    float py = (float)y / resolution;
                    
                    bool inTriangle = 
                        IsPointInTriangle(new Vector2(px, py), uv0, uv1, uv2) ||
                        IsPointInTriangle(new Vector2(px + pixelSize, py), uv0, uv1, uv2) ||
                        IsPointInTriangle(new Vector2(px, py + pixelSize), uv0, uv1, uv2) ||
                        IsPointInTriangle(new Vector2(px + pixelSize, py + pixelSize), uv0, uv1, uv2);
                    
                    if (inTriangle)
                    {
                        int index = y * resolution + x;
                        pixelData[index].isInUVIsland = true;
                    }
                }
            }
        }
        
        private static bool IsPointInTriangle(Vector2 p, Vector2 a, Vector2 b, Vector2 c)
        {
            Vector2 v0 = c - a;
            Vector2 v1 = b - a;
            Vector2 v2 = p - a;
            
            float dot00 = Vector2.Dot(v0, v0);
            float dot01 = Vector2.Dot(v0, v1);
            float dot02 = Vector2.Dot(v0, v2);
            float dot11 = Vector2.Dot(v1, v1);
            float dot12 = Vector2.Dot(v1, v2);
            
            float invDenom = 1f / (dot00 * dot11 - dot01 * dot01);
            float u = (dot11 * dot02 - dot01 * dot12) * invDenom;
            float v = (dot00 * dot12 - dot01 * dot02) * invDenom;
            
            return (u >= 0) && (v >= 0) && (u + v <= 1);
        }

        private static void WriteEdgeAdjacencyCPU(
            PixelData[] pixelData,
            List<UVAdjacencyMapBuilder.SeamAdjacency> seams,
            int resolution,
            int edgePadding,
            bool enableDebugLog = false)
        {
            float pixelSize = 1f / resolution;
            float paddingUV = pixelSize * edgePadding;

            int totalWritten = 0;
            int debugCount = 0;

            foreach (var seam in seams)
            {
                totalWritten += WriteEdgeRegion(pixelData, seam, true, resolution, paddingUV, enableDebugLog && debugCount < 5, ref debugCount);
                totalWritten += WriteEdgeRegion(pixelData, seam, false, resolution, paddingUV, enableDebugLog && debugCount < 5, ref debugCount);
            }

            Debug.Log($"[UV邻接图] 写入了 {totalWritten} 个像素的邻接信息");
        }

        private static int WriteEdgeRegion(
            PixelData[] pixelData,
            UVAdjacencyMapBuilder.SeamAdjacency seam,
            bool writeEdgeA,
            int resolution,
            float paddingUV,
            bool enableDebugLog,
            ref int debugCount)
        {
            UVAdjacencyMapBuilder.EdgeInfo sourceEdge, targetEdge;
            bool reversed;
            
            if (writeEdgeA)
            {
                sourceEdge = seam.edgeA;
                targetEdge = seam.edgeB;
                reversed = seam.reversedMapping;
            }
            else
            {
                sourceEdge = seam.edgeB;
                targetEdge = seam.edgeA;
                reversed = seam.reversedMapping;
            }

            float minX = Mathf.Min(sourceEdge.uvA.x, sourceEdge.uvB.x) - paddingUV;
            float maxX = Mathf.Max(sourceEdge.uvA.x, sourceEdge.uvB.x) + paddingUV;
            float minY = Mathf.Min(sourceEdge.uvA.y, sourceEdge.uvB.y) - paddingUV;
            float maxY = Mathf.Max(sourceEdge.uvA.y, sourceEdge.uvB.y) + paddingUV;

            int pxMin = Mathf.Clamp(Mathf.FloorToInt(minX * resolution), 0, resolution - 1);
            int pxMax = Mathf.Clamp(Mathf.CeilToInt(maxX * resolution), 0, resolution - 1);
            int pyMin = Mathf.Clamp(Mathf.FloorToInt(minY * resolution), 0, resolution - 1);
            int pyMax = Mathf.Clamp(Mathf.CeilToInt(maxY * resolution), 0, resolution - 1);

            int writtenPixels = 0;

            Vector2 sourceDir = sourceEdge.uvB - sourceEdge.uvA;
            float sourceLengthSq = sourceDir.sqrMagnitude;
            
            if (sourceLengthSq < 0.0000001f)
                return 0;
            
            float sourceLength = Mathf.Sqrt(sourceLengthSq);
            Vector2 sourceDirNorm = sourceDir / sourceLength;

            if (enableDebugLog)
            {
                Debug.Log($"[UV邻接图调试] 边映射:\n" +
                    $"  源边: UV({sourceEdge.uvA.x:F6},{sourceEdge.uvA.y:F6}) -> ({sourceEdge.uvB.x:F6},{sourceEdge.uvB.y:F6})\n" +
                    $"  目标边: UV({targetEdge.uvA.x:F6},{targetEdge.uvA.y:F6}) -> ({targetEdge.uvB.x:F6},{targetEdge.uvB.y:F6})\n" +
                    $"  反向映射: {reversed}");
                debugCount++;
            }

            for (int py = pyMin; py <= pyMax; py++)
            {
                for (int px = pxMin; px <= pxMax; px++)
                {
                    Vector2 uv = new Vector2((px + 0.5f) / resolution, (py + 0.5f) / resolution);

                    float dist = DistanceToEdgePrecise(uv, sourceEdge.uvA, sourceEdge.uvB, sourceDirNorm);

                    if (dist <= paddingUV)
                    {
                        int index = py * resolution + px;
                        
                        if (dist < pixelData[index].distance)
                        {
                            float t = GetParameterOnEdgePrecise(uv, sourceEdge.uvA, sourceEdge.uvB, sourceLengthSq);

                            Vector2 adjacentUV;
                            if (reversed)
                            {
                                adjacentUV = targetEdge.uvB + (targetEdge.uvA - targetEdge.uvB) * t;
                            }
                            else
                            {
                                adjacentUV = targetEdge.uvA + (targetEdge.uvB - targetEdge.uvA) * t;
                            }

                            pixelData[index].adjacentUV = adjacentUV;
                            pixelData[index].distance = dist;
                            pixelData[index].hasData = true;
                            
                            writtenPixels++;
                        }
                    }
                }
            }

            return writtenPixels;
        }

        private static float GetParameterOnEdgePrecise(Vector2 uv, Vector2 edgeUvA, Vector2 edgeUvB, float edgeLengthSq)
        {
            if (edgeLengthSq < 0.0000001f)
                return 0f;

            Vector2 edgeDir = edgeUvB - edgeUvA;
            Vector2 toPoint = uv - edgeUvA;
            
            float t = Vector2.Dot(toPoint, edgeDir) / edgeLengthSq;
            return Mathf.Clamp01(t);
        }

        private static float DistanceToEdgePrecise(Vector2 point, Vector2 edgeStart, Vector2 edgeEnd, Vector2 edgeDirNorm)
        {
            Vector2 toPoint = point - edgeStart;
            float edgeLength = Vector2.Distance(edgeStart, edgeEnd);
            
            if (edgeLength < 0.0000001f)
                return Vector2.Distance(point, edgeStart);

            float projLength = Vector2.Dot(toPoint, edgeDirNorm);
            projLength = Mathf.Clamp(projLength, 0, edgeLength);
            
            Vector2 projection = edgeStart + edgeDirNorm * projLength;

            return Vector2.Distance(point, projection);
        }

        #endregion
    }
}
