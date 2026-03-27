using System.Collections.Generic;
using UnityEngine;

namespace TangentSpaceGravityMap
{
    /// <summary>
    /// 调试模式枚举
    /// </summary>
    public enum DebugMode
    {
        None,                   // 无调试输出
        LogStatistics,          // 输出统计信息
        LogSamplePoints,        // 输出采样点详情
        ValidateConversion      // 验证转换正确性
    }

    /// <summary>
    /// 输出模式枚举
    /// </summary>
    public enum OutputMode
    {
        TangentSpaceGravity,    // 切线空间重力方向：重力在切线/副切线方向的分量
        SurfaceFlowDirection    // 表面流动方向：流体在表面上的下坡方向（推荐用于流体模拟）
    }

    /// <summary>
    /// 烘焙设置
    /// </summary>
    public struct BakeSettings
    {
        public int resolution;           // 纹理分辨率
        public int uvChannel;            // UV通道（0或1）
        public bool useEXRFormat;        // 是否使用EXR格式
        public bool enableDebugLog;      // 是否启用调试日志
        public Vector3 customGravity;    // 自定义重力方向（默认Vector3.down）
        
        // 输出选项
        public OutputMode outputMode;    // 输出模式
        public bool normalizeTo01;       // 是否将值从[-1,1]映射到[0,1]
        public bool compressToRG;        // 是否压缩到RG通道（否则输出RGB三通道）
        public int edgePadding;          // 边缘扩展像素数（将UV岛边缘向外扩展）

        public static BakeSettings Default => new BakeSettings
        {
            resolution = 256,
            uvChannel = 0,
            useEXRFormat = true,
            enableDebugLog = false,
            customGravity = Vector3.down,
            outputMode = OutputMode.SurfaceFlowDirection,  // 默认使用表面流动方向
            normalizeTo01 = false,
            compressToRG = false,
            edgePadding = 0            // 默认不扩展边缘
        };
    }

    /// <summary>
    /// 烘焙结果
    /// </summary>
    public struct BakeResult
    {
        public Texture2D gravityMap;     // 生成的重力图
        public bool success;
        public string errorMessage;
        public int validPixelCount;      // 有效像素数
        public int totalPixelCount;      // 总像素数
    }

    /// <summary>
    /// 切线空间重力图烘焙器
    /// 将世界空间重力方向转换到切线空间，并烘焙为纹理
    /// </summary>
    public class TangentSpaceGravityMapBaker
    {
        #region 数据结构

        /// <summary>
        /// 缓存的网格数据
        /// </summary>
        private struct MeshData
        {
            public Vector3[] vertices;
            public Vector3[] normals;
            public Vector4[] tangents;
            public Vector2[] uvs;
            public int[] triangles;
            public int triangleCount;

            public bool IsValid => vertices != null && normals != null && 
                                   tangents != null && uvs != null && triangles != null;
        }

        /// <summary>
        /// UV三角形索引数据
        /// </summary>
        private struct UVTriangleIndex
        {
            public int triangleIndex;     // 三角形索引
            public Vector2 uv0, uv1, uv2; // 三个顶点的UV
            public Rect uvBounds;         // UV包围盒
        }

        #endregion

        #region 公共方法

        /// <summary>
        /// 烘焙切线空间重力图
        /// </summary>
        public static BakeResult Bake(Mesh mesh, BakeSettings settings)
        {
            BakeResult result = new BakeResult
            {
                success = false,
                gravityMap = null,
                errorMessage = "",
                validPixelCount = 0,
                totalPixelCount = settings.resolution * settings.resolution
            };

            // 验证输入
            if (mesh == null)
            {
                result.errorMessage = "Mesh为空！";
                return result;
            }

            // 提取网格数据
            MeshData meshData = ExtractMeshData(mesh, settings.uvChannel);
            if (!meshData.IsValid)
            {
                result.errorMessage = "Mesh数据不完整！请确保Mesh有顶点、法线、切线和UV。";
                return result;
            }

            // 构建UV三角形索引
            List<UVTriangleIndex> uvTriangles = BuildUVTriangleIndices(meshData);
            if (uvTriangles.Count == 0)
            {
                result.errorMessage = "没有找到有效的UV三角形！";
                return result;
            }

            if (settings.enableDebugLog)
            {
                Debug.Log($"[切线空间重力图] 网格数据: 顶点数={meshData.vertices.Length}, 三角形数={meshData.triangleCount}");
            }

            // 执行烘焙
            Texture2D gravityMap = BakeTexture(meshData, uvTriangles, settings, ref result);

            if (gravityMap != null)
            {
                result.gravityMap = gravityMap;
                result.success = true;

                if (settings.enableDebugLog)
                {
                    float coverage = (float)result.validPixelCount / result.totalPixelCount * 100f;
                    Debug.Log($"[切线空间重力图] 烘焙完成: 有效像素={result.validPixelCount}, 覆盖率={coverage:F1}%");
                }
            }

            return result;
        }

        /// <summary>
        /// 保存纹理到文件
        /// </summary>
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
                Debug.Log($"[切线空间重力图] 纹理已保存到: {path}");
                return true;
            }
            catch (System.Exception e)
            {
                Debug.LogError($"[切线空间重力图] 保存纹理失败: {e.Message}");
                return false;
            }
        }

        #endregion

        #region 网格数据处理

        /// <summary>
        /// 提取网格数据
        /// </summary>
        private static MeshData ExtractMeshData(Mesh mesh, int uvChannel)
        {
            MeshData data = new MeshData();

            data.vertices = mesh.vertices;
            data.normals = mesh.normals;
            data.tangents = mesh.tangents;
            data.triangles = mesh.triangles;
            data.triangleCount = mesh.triangles.Length / 3;

            // 获取指定UV通道
            if (uvChannel == 0)
            {
                data.uvs = mesh.uv;
            }
            else if (uvChannel == 1)
            {
                data.uvs = mesh.uv2;
            }
            else
            {
                // 尝试获取其他UV通道
                List<Vector2> uvList = new List<Vector2>();
                mesh.GetUVs(uvChannel, uvList);
                data.uvs = uvList.ToArray();
            }

            return data;
        }

        /// <summary>
        /// 构建UV三角形索引列表
        /// </summary>
        private static List<UVTriangleIndex> BuildUVTriangleIndices(MeshData meshData)
        {
            List<UVTriangleIndex> indices = new List<UVTriangleIndex>();

            for (int triIndex = 0; triIndex < meshData.triangleCount; triIndex++)
            {
                int i0 = meshData.triangles[triIndex * 3 + 0];
                int i1 = meshData.triangles[triIndex * 3 + 1];
                int i2 = meshData.triangles[triIndex * 3 + 2];

                // 检查索引有效性
                if (i0 < 0 || i0 >= meshData.uvs.Length ||
                    i1 < 0 || i1 >= meshData.uvs.Length ||
                    i2 < 0 || i2 >= meshData.uvs.Length)
                {
                    continue;
                }

                UVTriangleIndex idx = new UVTriangleIndex
                {
                    triangleIndex = triIndex,
                    uv0 = meshData.uvs[i0],
                    uv1 = meshData.uvs[i1],
                    uv2 = meshData.uvs[i2]
                };

                // 计算UV包围盒
                idx.uvBounds = new Rect
                {
                    xMin = Mathf.Min(idx.uv0.x, idx.uv1.x, idx.uv2.x),
                    yMin = Mathf.Min(idx.uv0.y, idx.uv1.y, idx.uv2.y),
                    xMax = Mathf.Max(idx.uv0.x, idx.uv1.x, idx.uv2.x),
                    yMax = Mathf.Max(idx.uv0.y, idx.uv1.y, idx.uv2.y)
                };

                indices.Add(idx);
            }

            return indices;
        }

        #endregion

        #region 纹理烘焙

        /// <summary>
        /// 烘焙纹理
        /// </summary>
        private static Texture2D BakeTexture(MeshData meshData, List<UVTriangleIndex> uvTriangles, 
            BakeSettings settings, ref BakeResult result)
        {
            int resolution = settings.resolution;
            Color[] pixels = new Color[resolution * resolution];
            bool[] isValidPixel = new bool[resolution * resolution];  // 标记有效像素
            int validCount = 0;

            // 构建空间索引以加速查找
            Dictionary<Vector2Int, List<int>> spatialIndex = BuildSpatialIndex(uvTriangles, resolution);

            // Step 1: 烘焙UV岛内的像素
            for (int y = 0; y < resolution; y++)
            {
                for (int x = 0; x < resolution; x++)
                {
                    Vector2 uv = new Vector2((x + 0.5f) / resolution, (y + 0.5f) / resolution);
                    int pixelIndex = y * resolution + x;

                    // 查找UV对应的三角形
                    if (FindTriangleForUV(uv, meshData, uvTriangles, spatialIndex, resolution, 
                        out int triIndex, out Vector3 barycentric))
                    {
                        // 插值计算法线和切线
                        Vector3 normal = InterpolateNormal(meshData, triIndex, barycentric);
                        Vector4 tangent = InterpolateTangent(meshData, triIndex, barycentric);

                        // 构建TBN基向量
                        Vector3 T = new Vector3(tangent.x, tangent.y, tangent.z).normalized;
                        Vector3 N = normal.normalized;
                        Vector3 B = (Vector3.Cross(N, T) * tangent.w).normalized;

                        // 根据输出模式计算方向
                        Vector3 outputDirection;
                        if (settings.outputMode == OutputMode.SurfaceFlowDirection)
                        {
                            outputDirection = CalculateSurfaceFlowDirection(N, T, B, settings.customGravity);
                        }
                        else
                        {
                            outputDirection = CalculateTangentSpaceGravity(N, T, settings.customGravity);
                        }

                        float r, g, b, a;

                        if (settings.compressToRG)
                        {
                            if (settings.normalizeTo01)
                            {
                                r = outputDirection.x * 0.5f + 0.5f;
                                g = outputDirection.y * 0.5f + 0.5f;
                            }
                            else
                            {
                                r = outputDirection.x;
                                g = outputDirection.y;
                            }
                            b = 0;
                            a = 1;
                        }
                        else
                        {
                            if (settings.normalizeTo01)
                            {
                                r = outputDirection.x * 0.5f + 0.5f;
                                g = outputDirection.y * 0.5f + 0.5f;
                                b = outputDirection.z * 0.5f + 0.5f;
                            }
                            else
                            {
                                r = outputDirection.x;
                                g = outputDirection.y;
                                b = outputDirection.z;
                            }
                            a = 1;
                        }

                        pixels[pixelIndex] = new Color(r, g, b, a);
                        isValidPixel[pixelIndex] = true;
                        validCount++;

                        // 调试输出采样点详情
                        if (settings.enableDebugLog && validCount <= 5)
                        {
                            Debug.Log($"[切线空间重力图] 采样点 {validCount}:\n" +
                                $"  UV: ({uv.x:F4}, {uv.y:F4})\n" +
                                $"  三角形索引: {triIndex}\n" +
                                $"  重心坐标: ({barycentric.x:F3}, {barycentric.y:F3}, {barycentric.z:F3})\n" +
                                $"  法线(N): ({N.x:F4}, {N.y:F4}, {N.z:F4})\n" +
                                $"  切线(T): ({T.x:F4}, {T.y:F4}, {T.z:F4})\n" +
                                $"  副切线(B): ({B.x:F4}, {B.y:F4}, {B.z:F4})\n" +
                                $"  世界重力: ({settings.customGravity.x:F4}, {settings.customGravity.y:F4}, {settings.customGravity.z:F4})\n" +
                                $"  输出模式: {settings.outputMode}\n" +
                                $"  输出方向: ({outputDirection.x:F4}, {outputDirection.y:F4}, {outputDirection.z:F4})\n" +
                                $"  输出RGBA: ({r:F3}, {g:F3}, {b:F3}, {a:F3})");
                        }
                    }
                    else
                    {
                        // 无效区域
                        if (settings.normalizeTo01)
                        {
                            pixels[pixelIndex] = new Color(0.5f, 0.5f, 0.5f, 0);
                        }
                        else
                        {
                            pixels[pixelIndex] = new Color(0, 0, 0, 0);
                        }
                        isValidPixel[pixelIndex] = false;
                    }
                }
            }

            result.validPixelCount = validCount;

            // Step 2: 边缘扩展
            if (settings.edgePadding > 0)
            {
                int paddedCount = ExpandEdges(pixels, isValidPixel, resolution, settings.edgePadding, settings.normalizeTo01);
                if (settings.enableDebugLog)
                {
                    Debug.Log($"[切线空间重力图] 边缘扩展: 原始有效像素={validCount}, 扩展后新增={paddedCount}");
                }
            }

            // 创建纹理
            Texture2D texture = new Texture2D(resolution, resolution, TextureFormat.RGBAFloat, false);
            texture.SetPixels(pixels);
            texture.Apply();

            return texture;
        }

        /// <summary>
        /// 边缘扩展：将UV岛边缘向外扩展指定像素数
        /// 使用Jump Flooding算法进行快速距离场计算
        /// </summary>
        private static int ExpandEdges(Color[] pixels, bool[] isValidPixel, int resolution, int padding, bool normalizeTo01)
        {
            int paddedCount = 0;
            
            // 使用迭代扩散方式扩展边缘
            // 每次迭代扩展1像素，共迭代padding次
            for (int iter = 0; iter < padding; iter++)
            {
                Color[] newPixels = new Color[resolution * resolution];
                System.Array.Copy(pixels, newPixels, pixels.Length);
                
                for (int y = 0; y < resolution; y++)
                {
                    for (int x = 0; x < resolution; x++)
                    {
                        int pixelIndex = y * resolution + x;
                        
                        // 如果已经是有效像素，跳过
                        if (isValidPixel[pixelIndex])
                            continue;
                        
                        // 查找相邻的有效像素
                        Color? nearestColor = null;
                        float minDist = float.MaxValue;
                        
                        // 检查8邻域
                        for (int dy = -1; dy <= 1; dy++)
                        {
                            for (int dx = -1; dx <= 1; dx++)
                            {
                                if (dx == 0 && dy == 0) continue;
                                
                                int nx = x + dx;
                                int ny = y + dy;
                                
                                if (nx < 0 || nx >= resolution || ny < 0 || ny >= resolution)
                                    continue;
                                
                                int neighborIndex = ny * resolution + nx;
                                if (isValidPixel[neighborIndex])
                                {
                                    float dist = Mathf.Sqrt(dx * dx + dy * dy);
                                    if (dist < minDist)
                                    {
                                        minDist = dist;
                                        nearestColor = pixels[neighborIndex];
                                    }
                                }
                            }
                        }
                        
                        // 如果找到有效邻居，复制其值
                        if (nearestColor.HasValue)
                        {
                            Color c = nearestColor.Value;
                            // 标记为扩展像素（a=0.5表示扩展区域）
                            newPixels[pixelIndex] = new Color(c.r, c.g, c.b, 0.5f);
                            paddedCount++;
                        }
                    }
                }
                
                // 更新有效像素标记（扩展的像素也标记为有效，以便下一轮迭代）
                for (int i = 0; i < pixels.Length; i++)
                {
                    if (newPixels[i].a > 0 && !isValidPixel[i])
                    {
                        isValidPixel[i] = true;
                    }
                }
                
                System.Array.Copy(newPixels, pixels, pixels.Length);
            }
            
            return paddedCount;
        }

        /// <summary>
        /// 构建空间索引以加速UV查找
        /// </summary>
        private static Dictionary<Vector2Int, List<int>> BuildSpatialIndex(List<UVTriangleIndex> uvTriangles, int resolution)
        {
            Dictionary<Vector2Int, List<int>> index = new Dictionary<Vector2Int, List<int>>();
            int gridSize = Mathf.Max(8, resolution / 32);

            for (int i = 0; i < uvTriangles.Count; i++)
            {
                UVTriangleIndex tri = uvTriangles[i];

                int minX = Mathf.FloorToInt(tri.uvBounds.xMin * gridSize);
                int maxX = Mathf.FloorToInt(tri.uvBounds.xMax * gridSize);
                int minY = Mathf.FloorToInt(tri.uvBounds.yMin * gridSize);
                int maxY = Mathf.FloorToInt(tri.uvBounds.yMax * gridSize);

                for (int gx = minX; gx <= maxX; gx++)
                {
                    for (int gy = minY; gy <= maxY; gy++)
                    {
                        Vector2Int key = new Vector2Int(gx, gy);
                        if (!index.ContainsKey(key))
                        {
                            index[key] = new List<int>();
                        }
                        index[key].Add(i);
                    }
                }
            }

            return index;
        }

        /// <summary>
        /// 查找UV对应的三角形
        /// </summary>
        private static bool FindTriangleForUV(Vector2 uv, MeshData meshData, List<UVTriangleIndex> uvTriangles,
            Dictionary<Vector2Int, List<int>> spatialIndex, int resolution, out int triIndex, out Vector3 barycentric)
        {
            triIndex = -1;
            barycentric = Vector3.zero;

            int gridSize = Mathf.Max(8, resolution / 32);
            Vector2Int key = new Vector2Int(Mathf.FloorToInt(uv.x * gridSize), Mathf.FloorToInt(uv.y * gridSize));

            if (!spatialIndex.TryGetValue(key, out List<int> candidates))
            {
                return false;
            }

            foreach (int idx in candidates)
            {
                UVTriangleIndex tri = uvTriangles[idx];

                // 检查UV是否在三角形内
                if (IsPointInTriangle(uv, tri.uv0, tri.uv1, tri.uv2, out barycentric))
                {
                    triIndex = tri.triangleIndex;
                    return true;
                }
            }

            return false;
        }

        /// <summary>
        /// 检查点是否在三角形内（重心坐标法）
        /// </summary>
        private static bool IsPointInTriangle(Vector2 p, Vector2 a, Vector2 b, Vector2 c, out Vector3 barycentric)
        {
            Vector2 v0 = c - a;
            Vector2 v1 = b - a;
            Vector2 v2 = p - a;

            float dot00 = Vector2.Dot(v0, v0);
            float dot01 = Vector2.Dot(v0, v1);
            float dot02 = Vector2.Dot(v0, v2);
            float dot11 = Vector2.Dot(v1, v1);
            float dot12 = Vector2.Dot(v1, v2);

            float denom = dot00 * dot11 - dot01 * dot01;
            if (Mathf.Abs(denom) < 1e-10f)
            {
                barycentric = Vector3.zero;
                return false;
            }

            float invDenom = 1f / denom;
            float u = (dot11 * dot02 - dot01 * dot12) * invDenom;
            float v = (dot00 * dot12 - dot01 * dot02) * invDenom;

            barycentric = new Vector3(1f - u - v, v, u);

            return (u >= -0.0001f) && (v >= -0.0001f) && (u + v <= 1.0001f);
        }

        /// <summary>
        /// 插值计算法线
        /// </summary>
        private static Vector3 InterpolateNormal(MeshData meshData, int triIndex, Vector3 barycentric)
        {
            int i0 = meshData.triangles[triIndex * 3 + 0];
            int i1 = meshData.triangles[triIndex * 3 + 1];
            int i2 = meshData.triangles[triIndex * 3 + 2];

            Vector3 n0 = meshData.normals[i0];
            Vector3 n1 = meshData.normals[i1];
            Vector3 n2 = meshData.normals[i2];

            Vector3 normal = n0 * barycentric.x + n1 * barycentric.y + n2 * barycentric.z;
            return normal.normalized;
        }

        /// <summary>
        /// 插值计算切线
        /// </summary>
        private static Vector4 InterpolateTangent(MeshData meshData, int triIndex, Vector3 barycentric)
        {
            int i0 = meshData.triangles[triIndex * 3 + 0];
            int i1 = meshData.triangles[triIndex * 3 + 1];
            int i2 = meshData.triangles[triIndex * 3 + 2];

            Vector4 t0 = meshData.tangents[i0];
            Vector4 t1 = meshData.tangents[i1];
            Vector4 t2 = meshData.tangents[i2];

            Vector3 tangent3 = new Vector3(t0.x, t0.y, t0.z) * barycentric.x +
                              new Vector3(t1.x, t1.y, t1.z) * barycentric.y +
                              new Vector3(t2.x, t2.y, t2.z) * barycentric.z;

            tangent3.Normalize();

            // 插值w分量
            float w = t0.w * barycentric.x + t1.w * barycentric.y + t2.w * barycentric.z;
            w = w >= 0 ? 1f : -1f;

            return new Vector4(tangent3.x, tangent3.y, tangent3.z, w);
        }

        /// <summary>
        /// 计算切线空间重力方向
        /// 重力在切线/副切线/法线方向的分量
        /// </summary>
        private static Vector3 CalculateTangentSpaceGravity(Vector3 N, Vector3 T, Vector3 worldGravity)
        {
            // 副切线
            Vector3 B = Vector3.Cross(N, T);
            // 注意：需要考虑tangent.w的方向，但这里简化处理，假设B已经正确
            B = B.normalized;

            // 切线空间重力 = TBN转置 × 世界空间重力
            float Gx = Vector3.Dot(worldGravity, T);  // 重力在切线方向的分量
            float Gy = Vector3.Dot(worldGravity, B);  // 重力在副切线方向的分量
            float Gz = Vector3.Dot(worldGravity, N);  // 重力在法线方向的分量

            return new Vector3(Gx, Gy, Gz);
        }

        /// <summary>
        /// 计算表面流动方向（下坡方向）
        /// 这是流体在表面上实际会流动的方向
        /// 
        /// 原理：
        /// 1. 世界空间重力投影到表面切平面上
        /// 2. 投影方向即为流体流动方向
        /// 3. 将投影方向转换到切线空间
        /// </summary>
        private static Vector3 CalculateSurfaceFlowDirection(Vector3 N, Vector3 T, Vector3 B, Vector3 worldGravity)
        {
            // 步骤1：计算重力在表面切平面上的投影
            // 投影 = 重力 - (重力·法线) * 法线
            // 这去掉了重力垂直于表面的分量，只保留切平面内的分量
            float gravityAlongNormal = Vector3.Dot(worldGravity, N);
            Vector3 gravityOnTangentPlane = worldGravity - N * gravityAlongNormal;

            // 如果投影为零（完全水平或完全垂直的表面），返回零向量
            if (gravityOnTangentPlane.sqrMagnitude < 1e-10f)
            {
                return Vector3.zero;
            }

            // 步骤2：将投影方向转换到切线空间
            // 切线空间坐标 = (投影·T, 投影·B, 0)
            // 注意：z分量为0，因为投影在切平面上
            float flowX = Vector3.Dot(gravityOnTangentPlane, T);
            float flowY = Vector3.Dot(gravityOnTangentPlane, B);

            // 步骤3：归一化输出方向（保持单位长度）
            // 这样在shader中可以直接使用方向，强度可以通过其他方式控制
            Vector2 flowDir2D = new Vector2(flowX, flowY);
            float magnitude = flowDir2D.magnitude;
            
            if (magnitude > 1e-6f)
            {
                flowDir2D /= magnitude;
            }

            // 返回归一化的流动方向，z分量存储原始强度（可选）
            return new Vector3(flowDir2D.x, flowDir2D.y, magnitude);
        }

        #endregion
    }
}
