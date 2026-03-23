using System.Collections.Generic;
using UnityEngine;

namespace UVAdjacencyMap
{
    /// <summary>
    /// UV邻接图烘焙器
    /// 输出格式：R=邻接UV.x, G=邻接UV.y, B=0, A=1
    /// 支持EXR格式以获得更高精度
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
            public bool useEXRFormat;  // 使用EXR格式
            public bool enableDebugLog;  // 启用调试日志

            public static BakeSettings Default => new BakeSettings
            {
                resolution = 1024,
                edgePadding = 4,
                uvEpsilon = 0.001f,
                uvChannel = 0,
                useEXRFormat = true,
                enableDebugLog = false
            };
        }

        public struct BakeResult
        {
            public Texture2D adjacencyMap;
            public UVAdjacencyMapBuilder.BuildResult buildResult;
            public bool success;
            public string errorMessage;
        }

        /// <summary>
        /// 像素数据结构（用于存储最近的边信息）
        /// </summary>
        private struct PixelData
        {
            public Vector2 adjacentUV;
            public float distance;
            public bool hasData;
        }

        #endregion

        #region 公共方法

        public static BakeResult Bake(Mesh mesh, BakeSettings settings)
        {
            BakeResult result = new BakeResult
            {
                success = false,
                adjacencyMap = null,
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

            // 构建邻接关系
            UVAdjacencyMapBuilder.BuildResult buildResult = UVAdjacencyMapBuilder.Build(
                mesh, settings.uvChannel, settings.uvEpsilon);
            result.buildResult = buildResult;

            // 检查是否有接缝
            if (buildResult.seams == null || buildResult.seams.Count == 0)
            {
                result.errorMessage = "没有找到UV接缝";
                return result;
            }

            // 验证接缝映射（调试模式）
            if (settings.enableDebugLog)
            {
                int validateCount = Mathf.Min(5, buildResult.seams.Count);
                Debug.Log($"[UV邻接图] 开始验证前 {validateCount} 条接缝的映射关系...");
                for (int i = 0; i < validateCount; i++)
                {
                    UVAdjacencyMapBuilder.ValidateSeamMapping(buildResult.seams[i], i);
                }
                
                // 检查相邻边的映射一致性
                UVAdjacencyMapBuilder.CheckAdjacentSeamsConsistency(buildResult.seams);
            }

            Texture2D adjacencyMap = BakeWithCPU(buildResult, settings);

            if (adjacencyMap != null)
            {
                result.adjacencyMap = adjacencyMap;
                result.success = true;
            }

            return result;
        }

        public static bool SaveTexture(Texture2D texture, string path, bool useEXR = true)
        {
            if (texture == null || string.IsNullOrEmpty(path))
                return false;

            try
            {
                byte[] bytes;
                if (useEXR && path.EndsWith(".exr", System.StringComparison.OrdinalIgnoreCase))
                {
                    bytes = texture.EncodeToEXR(Texture2D.EXRFlags.CompressZIP);
                }
                else
                {
                    bytes = texture.EncodeToPNG();
                }
                System.IO.File.WriteAllBytes(path, bytes);
                Debug.Log($"[UV邻接图] 纹理已保存到: {path}");
                return true;
            }
            catch (System.Exception e)
            {
                Debug.LogError($"[UV邻接图] 保存纹理失败: {e.Message}");
                return false;
            }
        }

        #endregion

        #region CPU烘焙

        private static Texture2D BakeWithCPU(
            UVAdjacencyMapBuilder.BuildResult buildResult,
            BakeSettings settings)
        {
            int resolution = settings.resolution;
            
            // 使用PixelData数组来存储每个像素的信息
            PixelData[] pixelData = new PixelData[resolution * resolution];
            for (int i = 0; i < pixelData.Length; i++)
            {
                pixelData[i] = new PixelData { hasData = false, distance = float.MaxValue };
            }

            // 写入边缘邻接信息（使用距离判断，保留最近的边）
            WriteEdgeAdjacencyCPU(pixelData, buildResult.seams, resolution, settings.edgePadding, settings.enableDebugLog);

            // 转换为颜色数组
            Color[] pixels = new Color[resolution * resolution];
            for (int i = 0; i < pixels.Length; i++)
            {
                if (pixelData[i].hasData)
                {
                    pixels[i] = new Color(pixelData[i].adjacentUV.x, pixelData[i].adjacentUV.y, 0, 1);
                }
                else
                {
                    pixels[i] = new Color(0, 0, 0, 1);
                }
            }

            // 使用RGBAFloat格式以获得更高精度
            Texture2D texture = new Texture2D(resolution, resolution, TextureFormat.RGBAFloat, false);
            texture.SetPixels(pixels);
            texture.Apply();

            return texture;
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
            int debugCount = 0;  // 限制调试输出数量

            foreach (var seam in seams)
            {
                // 写入edgeA区域
                totalWritten += WriteEdgeRegion(pixelData, seam, true, resolution, paddingUV, enableDebugLog && debugCount < 5, ref debugCount);
                
                // 写入edgeB区域
                totalWritten += WriteEdgeRegion(pixelData, seam, false, resolution, paddingUV, enableDebugLog && debugCount < 5, ref debugCount);
            }

            Debug.Log($"[UV邻接图] 写入了 {totalWritten} 个像素的邻接信息");
        }

        /// <summary>
        /// 写入单条边的区域（使用距离判断，只保留最近的边）
        /// </summary>
        private static int WriteEdgeRegion(
            PixelData[] pixelData,
            UVAdjacencyMapBuilder.SeamAdjacency seam,
            bool writeEdgeA,
            int resolution,
            float paddingUV,
            bool enableDebugLog,
            ref int debugCount)
        {
            // 确定源边和目标边
            // reversedMapping表示edgeA的顶点对应关系：
            // - true: edgeA.posA -> edgeB.posB, edgeA.posB -> edgeB.posA
            // - false: edgeA.posA -> edgeB.posA, edgeA.posB -> edgeB.posB
            // 无论处理哪条边，映射方向保持一致
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
                // 当处理edgeB时，源边变成edgeB，目标边变成edgeA
                // 映射关系是对称的，reversed保持不变：
                // - 如果edgeA.posA -> edgeB.posB，那么edgeB.posB -> edgeA.posA（同样是反向）
                // - 如果edgeA.posA -> edgeB.posA，那么edgeB.posA -> edgeA.posA（同样是正向）
                sourceEdge = seam.edgeB;
                targetEdge = seam.edgeA;
                reversed = seam.reversedMapping;
            }

            // 计算源边的包围盒并扩展
            float minX = Mathf.Min(sourceEdge.uvA.x, sourceEdge.uvB.x) - paddingUV;
            float maxX = Mathf.Max(sourceEdge.uvA.x, sourceEdge.uvB.x) + paddingUV;
            float minY = Mathf.Min(sourceEdge.uvA.y, sourceEdge.uvB.y) - paddingUV;
            float maxY = Mathf.Max(sourceEdge.uvA.y, sourceEdge.uvB.y) + paddingUV;

            // 转换为像素范围
            int pxMin = Mathf.Clamp(Mathf.FloorToInt(minX * resolution), 0, resolution - 1);
            int pxMax = Mathf.Clamp(Mathf.CeilToInt(maxX * resolution), 0, resolution - 1);
            int pyMin = Mathf.Clamp(Mathf.FloorToInt(minY * resolution), 0, resolution - 1);
            int pyMax = Mathf.Clamp(Mathf.CeilToInt(maxY * resolution), 0, resolution - 1);

            int writtenPixels = 0;

            // 预计算边的方向向量
            Vector2 sourceDir = sourceEdge.uvB - sourceEdge.uvA;
            float sourceLengthSq = sourceDir.sqrMagnitude;
            
            if (sourceLengthSq < 0.0000001f)
                return 0;
            
            // 归一化方向用于距离计算
            float sourceLength = Mathf.Sqrt(sourceLengthSq);
            Vector2 sourceDirNorm = sourceDir / sourceLength;

            // 调试输出：验证边的映射关系
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

                    // 计算到源边的距离（精确计算）
                    float dist = DistanceToEdgePrecise(uv, sourceEdge.uvA, sourceEdge.uvB, sourceDirNorm);

                    if (dist <= paddingUV)
                    {
                        int index = py * resolution + px;
                        
                        // 只在距离更近时更新（避免拐角处重叠）
                        if (dist < pixelData[index].distance)
                        {
                            // 精确计算参数t
                            float t = GetParameterOnEdgePrecise(uv, sourceEdge.uvA, sourceEdge.uvB, sourceLengthSq);

                            // 精确映射到目标边
                            Vector2 adjacentUV;
                            if (reversed)
                            {
                                // 反向映射：sourceEdge.uvA -> targetEdge.uvB, sourceEdge.uvB -> targetEdge.uvA
                                adjacentUV = targetEdge.uvB + (targetEdge.uvA - targetEdge.uvB) * t;
                            }
                            else
                            {
                                // 正向映射：sourceEdge.uvA -> targetEdge.uvA, sourceEdge.uvB -> targetEdge.uvB
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

        /// <summary>
        /// 精确计算参数t（在边上的位置，0~1）
        /// </summary>
        private static float GetParameterOnEdgePrecise(Vector2 uv, Vector2 edgeUvA, Vector2 edgeUvB, 
            float edgeLengthSq)
        {
            if (edgeLengthSq < 0.0000001f)
                return 0f;

            Vector2 edgeDir = edgeUvB - edgeUvA;
            Vector2 toPoint = uv - edgeUvA;
            
            // 直接使用投影公式：t = dot(toPoint, edgeDir) / |edgeDir|^2
            float t = Vector2.Dot(toPoint, edgeDir) / edgeLengthSq;
            return Mathf.Clamp01(t);
        }

        /// <summary>
        /// 精确计算点到边的距离
        /// </summary>
        private static float DistanceToEdgePrecise(Vector2 point, Vector2 edgeStart, Vector2 edgeEnd, 
            Vector2 edgeDirNorm)
        {
            Vector2 toPoint = point - edgeStart;
            float edgeLength = Vector2.Distance(edgeStart, edgeEnd);
            
            if (edgeLength < 0.0000001f)
                return Vector2.Distance(point, edgeStart);

            // 计算投影长度
            float projLength = Vector2.Dot(toPoint, edgeDirNorm);
            
            // Clamp到边上
            projLength = Mathf.Clamp(projLength, 0, edgeLength);
            
            // 计算投影点
            Vector2 projection = edgeStart + edgeDirNorm * projLength;

            return Vector2.Distance(point, projection);
        }

        #endregion
    }
}
