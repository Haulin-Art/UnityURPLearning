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
    /// 烹焙设置
    /// </summary>
    public struct BakeSettings
    {
        public int resolution;           // 纹理分辨率
        public int uvChannel;            // UV通道（0或1）
        public bool useEXRFormat;        // 是否使用EXR格式
        public bool enableDebugLog;      // 是否启用调试日志
        public Vector3 customGravity;    // 自定义重力方向（默认Vector3.down）
        
        // 新增选项
        public bool normalizeTo01;       // 是否将值从[-1,1]映射到[0,1]
        public bool compressToRG;        // 是否压缩到RG通道（否则输出RGB三通道）

        public static BakeSettings Default => new BakeSettings
        {
            resolution = 256,
            uvChannel = 0,
            useEXRFormat = true,
            enableDebugLog = false,
            customGravity = Vector3.down,
            normalizeTo01 = false,       // 默认不映射，保留原始值
            compressToRG = false         // 默认输出RGB三通道
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
            int validCount = 0;

            // 构建空间索引以加速查找
            Dictionary<Vector2Int, List<int>> spatialIndex = BuildSpatialIndex(uvTriangles, resolution);

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

                        // 计算切线空间重力（返回三维向量）
                        Vector3 tangentGravity = CalculateTangentSpaceGravity(normal, tangent, settings.customGravity);

                        float r, g, b, a;

                        if (settings.compressToRG)
                        {
                            // 压缩到RG通道
                            if (settings.normalizeTo01)
                            {
                                // 映射到[0,1]范围
                                r = tangentGravity.x * 0.5f + 0.5f;
                                g = tangentGravity.y * 0.5f + 0.5f;
                            }
                            else
                            {
                                // 保留原始值[-1,1]
                                r = tangentGravity.x;
                                g = tangentGravity.y;
                            }
                            b = 0;
                            a = 1;
                        }
                        else
                        {
                            // 输出RGB三通道（完整的三维重力方向）
                            if (settings.normalizeTo01)
                            {
                                // 映射到[0,1]范围
                                r = tangentGravity.x * 0.5f + 0.5f;
                                g = tangentGravity.y * 0.5f + 0.5f;
                                b = tangentGravity.z * 0.5f + 0.5f;
                            }
                            else
                            {
                                // 保留原始值[-1,1]
                                r = tangentGravity.x;
                                g = tangentGravity.y;
                                b = tangentGravity.z;
                            }
                            a = 1;
                        }

                        pixels[pixelIndex] = new Color(r, g, b, a);
                        validCount++;

                        // 调试输出采样点详情
                        if (settings.enableDebugLog && validCount <= 5)
                        {
                            Debug.Log($"[切线空间重力图] 采样点 {validCount}:\n" +
                                $"  UV: ({uv.x:F4}, {uv.y:F4})\n" +
                                $"  三角形索引: {triIndex}\n" +
                                $"  重心坐标: ({barycentric.x:F3}, {barycentric.y:F3}, {barycentric.z:F3})\n" +
                                $"  法线: ({normal.x:F3}, {normal.y:F3}, {normal.z:F3})\n" +
                                $"  切线: ({tangent.x:F3}, {tangent.y:F3}, {tangent.z:F3}, w={tangent.w:F1})\n" +
                                $"  切线空间重力: ({tangentGravity.x:F3}, {tangentGravity.y:F3}, {tangentGravity.z:F3})\n" +
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
                    }
                }
            }

            result.validPixelCount = validCount;

            // 创建纹理
            Texture2D texture = new Texture2D(resolution, resolution, TextureFormat.RGBAFloat, false);
            texture.SetPixels(pixels);
            texture.Apply();

            return texture;
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
        /// </summary>
        private static Vector3 CalculateTangentSpaceGravity(Vector3 normal, Vector4 tangent, Vector3 worldGravity)
        {
            // 构建TBN基向量
            Vector3 T = new Vector3(tangent.x, tangent.y, tangent.z).normalized;
            Vector3 N = normal.normalized;
            // 副切线 = 法线 × 切线 * tangent.w（w存储了副切线方向）
            // 注意：副切线也需要归一化！
            Vector3 B = (Vector3.Cross(N, T) * tangent.w).normalized;

            // 切线空间重力 = TBN转置 × 世界空间重力
            // 由于TBN是正交矩阵，转置等于逆，所以：
            // G_tangent = (G·T, G·B, G·N)
            float Gx = Vector3.Dot(worldGravity, T);  // 重力在切线方向的分量
            float Gy = Vector3.Dot(worldGravity, B);  // 重力在副切线方向的分量
            float Gz = Vector3.Dot(worldGravity, N);  // 重力在法线方向的分量

            return new Vector3(Gx, Gy, Gz);
        }

        #endregion
    }
}
