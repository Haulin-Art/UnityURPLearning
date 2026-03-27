using System.Collections.Generic;
using UnityEngine;

namespace UVAdjacencyMap
{
    /// <summary>
    /// UV邻接图烘焙器
    /// 输出格式：R=邻接UV.x, G=邻接UV.y, B=邻接边缘遮罩, A=UV岛范围遮罩
    /// 直接输出RenderTexture（ARGBFloat格式）
    /// </summary>
    public class UVAdjacencyMapBaker
    {
        #region 数据结构

        public struct BakeSettings
        {
            public int resolution;
            public int edgePadding;
            public float uvEpsilon;
            public int uvChannel;
            public bool enableDebugLog;

            public static BakeSettings Default => new BakeSettings
            {
                resolution = 1024,
                edgePadding = 4,
                uvEpsilon = 0.001f,
                uvChannel = 0,
                enableDebugLog = false
            };
        }

        public struct BakeResult
        {
            public Texture2D adjacencyMap;      // Texture2D版本（用于预览）
            public RenderTexture adjacencyRT;   // RenderTexture版本（高精度，用于运行时）
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
            public bool hasData;           // 是否有邻接数据
            public bool isInUVIsland;      // 是否在UV岛内（用于A通道）
        }

        #endregion

        #region 公共方法

        public static BakeResult Bake(Mesh mesh, BakeSettings settings)
        {
            BakeResult result = new BakeResult
            {
                success = false,
                adjacencyMap = null,
                adjacencyRT = null,
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

            // 烘焙纹理
            Texture2D adjacencyMap = BakeWithCPU(mesh, buildResult, settings);

            if (adjacencyMap != null)
            {
                result.adjacencyMap = adjacencyMap;
                // 创建RenderTexture版本
                result.adjacencyRT = CreateRenderTexture(adjacencyMap);
                result.success = true;
            }

            return result;
        }

        /// <summary>
        /// 从Texture2D创建RenderTexture（ARGBFloat格式，高精度）
        /// </summary>
        private static RenderTexture CreateRenderTexture(Texture2D texture)
        {
            if (texture == null)
            {
                Debug.LogError("[UV邻接图] texture为null！");
                return null;
            }

            // 首先测试Texture2D是否正确生成
            Color[] testPixels = texture.GetPixels(0, 0, 16, 16);
            int nonBlackPixels = 0;
            foreach (var p in testPixels)
            {
                if (p.r > 0 || p.g > 0 || p.b > 0 || p.a > 0)
                    nonBlackPixels++;
            }
            Debug.Log($"[UV邻接图] Texture2D测试: {nonBlackPixels}/256 个非黑色像素");

            RenderTexture rt = new RenderTexture(texture.width, texture.height, 0, RenderTextureFormat.ARGBFloat);
            rt.wrapMode = TextureWrapMode.Clamp;
            rt.filterMode = FilterMode.Bilinear;
            rt.Create();

            // 使用Blit将Texture2D数据复制到RenderTexture
            Graphics.Blit(texture, rt);

            // 验证RenderTexture
            RenderTexture prevRT = RenderTexture.active;
            RenderTexture.active = rt;
            Texture2D testRead = new Texture2D(16, 16, TextureFormat.RGBAFloat, false);
            testRead.ReadPixels(new Rect(0, 0, 16, 16), 0, 0);
            testRead.Apply();
            Color[] rtPixels = testRead.GetPixels();
            int rtNonBlack = 0;
            foreach (var p in rtPixels)
            {
                if (p.r > 0 || p.g > 0 || p.b > 0 || p.a > 0)
                    rtNonBlack++;
            }
            Debug.Log($"[UV邻接图] RenderTexture测试: {rtNonBlack}/256 个非黑色像素");
            RenderTexture.active = prevRT;

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

            // Step 1: 烘焙UV岛遮罩（A通道）
            BakeUVIslandMask(pixelData, mesh, settings.uvChannel, resolution);
            
            // Step 2: 写入边缘邻接信息（包含内描边和外描边）
            WriteEdgeAdjacencyCPU(pixelData, buildResult.seams, resolution, settings.edgePadding, settings.enableDebugLog);
            
            // 转换为颜色数组
            Color[] pixels = new Color[resolution * resolution];
            for (int i = 0; i < pixels.Length; i++)
            {
                if (pixelData[i].hasData)
                {
                    // R=邻接UV.x, G=邻接UV.y, B=1(邻接边缘)
                    // A=UV岛范围（内描边A=1，外描边A=0）
                    float aChannel = pixelData[i].isInUVIsland ? 1f : 0f;
                    pixels[i] = new Color(pixelData[i].adjacentUV.x, pixelData[i].adjacentUV.y, 1, aChannel);
                }
                else if (pixelData[i].isInUVIsland)
                {
                    // UV岛内但没有邻接数据， B=0, A=1
                    pixels[i] = new Color(0, 0, 0, 1);
                }
                else
                {
                    // UV岛外， B=0, A=0
                    pixels[i] = new Color(0, 0, 0, 0);
                }
            }
            
            Texture2D texture = new Texture2D(resolution, resolution, TextureFormat.RGBAFloat, false);
            texture.SetPixels(pixels);
            texture.Apply();
            
            return texture;
        }
        
        /// <summary>
        /// 烘焙UV岛遮罩
        /// </summary>
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
        
        /// <summary>
        /// 光栅化三角形（保守光栅化：检查像素四个角）
        /// </summary>
        private static void RasterizeTriangle(PixelData[] pixelData, Vector2 uv0, Vector2 uv1, Vector2 uv2, int resolution)
        {
            int minX = Mathf.FloorToInt(Mathf.Min(uv0.x, uv1.x, uv2.x) * resolution);
            int maxX = Mathf.CeilToInt(Mathf.Max(uv0.x, uv1.x, uv2.x) * resolution);
            int minY = Mathf.FloorToInt(Mathf.Min(uv0.y, uv1.y, uv2.y) * resolution);
            int maxY = Mathf.CeilToInt(Mathf.Max(uv0.y, uv1.y, uv2.y) * resolution);
            
            // 扩展边界以确保边缘像素被包含
            minX = Mathf.Max(0, minX - 1);
            maxX = Mathf.Min(resolution - 1, maxX + 1);
            minY = Mathf.Max(0, minY - 1);
            maxY = Mathf.Min(resolution - 1, maxY + 1);
            
            float pixelSize = 1f / resolution;
            
            for (int y = minY; y <= maxY; y++)
            {
                for (int x = minX; x <= maxX; x++)
                {
                    // 检查像素的四个角是否至少有一个在三角形内
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
        
        /// <summary>
        /// 检查点是否在三角形内（使用重心坐标法）
        /// </summary>
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
                            // isInUVIsland保持不变，用于区分内描边和外描边
                            
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
