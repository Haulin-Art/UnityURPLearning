using System.Collections.Generic;
using UnityEngine;

namespace UVAdjacencyMap
{
    /// <summary>
    /// UV邻接图构建器
    /// 使用直接遍历匹配，避免位置Key的精度问题
    /// </summary>
    public static class UVAdjacencyMapBuilder
    {
        #region 数据结构

        public struct EdgeInfo
        {
            public int vertexA;
            public int vertexB;
            public int triangleIndex;
            public int localEdgeIndex;
            public Vector2 uvA;
            public Vector2 uvB;
            public Vector3 posA;
            public Vector3 posB;
        }

        public struct SeamAdjacency
        {
            public EdgeInfo edgeA;
            public EdgeInfo edgeB;
            public int islandA;
            public int islandB;
            public bool reversedMapping;
        }

        public struct UVIsland
        {
            public int id;
            public List<int> triangleIndices;
            public Rect uvBounds;
        }

        public struct BuildResult
        {
            public List<SeamAdjacency> seams;
            public List<UVIsland> islands;
            public Dictionary<int, int> triangleToIsland;
            public int totalEdgeCount;
            public int seamCount;
            public int islandCount;
        }

        #endregion

        #region 公共方法

        public static BuildResult Build(Mesh mesh, int uvChannel = 0, float uvEpsilon = 0.001f)
        {
            BuildResult result = new BuildResult
            {
                seams = new List<SeamAdjacency>(),
                islands = new List<UVIsland>(),
                triangleToIsland = new Dictionary<int, int>()
            };

            Vector3[] vertices = mesh.vertices;
            int[] triangles = mesh.triangles;
            Vector2[] uvs = uvChannel == 0 ? mesh.uv : mesh.uv2;

            if (uvs == null || uvs.Length == 0)
            {
                Debug.LogWarning("[UV邻接图] Mesh没有UV坐标！");
                return result;
            }

            int triangleCount = triangles.Length / 3;

            // 计算模型边界框以确定位置Hash精度
            Bounds bounds = mesh.bounds;
            float maxDimension = Mathf.Max(bounds.size.x, bounds.size.y, bounds.size.z);
            // 使用更高的精度：将最大维度映射到100000级别
            int positionPrecision = Mathf.Max(10000, Mathf.RoundToInt(100000f / Mathf.Max(maxDimension, 0.001f)));
            Debug.Log($"[UV邻接图] 模型最大维度: {maxDimension:F4}, 位置Hash精度: {positionPrecision}");

            // Step 1: 提取所有边
            List<EdgeInfo> allEdges = new List<EdgeInfo>();
            for (int triIndex = 0; triIndex < triangleCount; triIndex++)
            {
                int i0 = triangles[triIndex * 3 + 0];
                int i1 = triangles[triIndex * 3 + 1];
                int i2 = triangles[triIndex * 3 + 2];

                allEdges.Add(CreateEdge(i0, i1, triIndex, 0, vertices, uvs));
                allEdges.Add(CreateEdge(i1, i2, triIndex, 1, vertices, uvs));
                allEdges.Add(CreateEdge(i2, i0, triIndex, 2, vertices, uvs));
            }
            result.totalEdgeCount = allEdges.Count;

            // Step 2: 按3D位置分组边（关键！UV接缝的两条边在UV空间中是分离的）
            // 使用3D位置中点来分组
            Dictionary<long, List<EdgeInfo>> edgesByPosition = new Dictionary<long, List<EdgeInfo>>();
            
            foreach (var edge in allEdges)
            {
                // 使用3D位置中点的hash作为key
                long key = GetPositionHash(edge.posA, edge.posB, positionPrecision);
                
                if (!edgesByPosition.ContainsKey(key))
                    edgesByPosition[key] = new List<EdgeInfo>();
                edgesByPosition[key].Add(edge);
            }

            // Step 3: 找UV接缝 - 直接遍历匹配
            List<SeamAdjacency> seams = new List<SeamAdjacency>();
            
            // 位置匹配精度（使用相对精度）
            float posEpsilon = 0.0001f;

            foreach (var kvp in edgesByPosition)
            {
                var group = kvp.Value;
                
                if (group.Count == 2)
                {
                    var edgeA = group[0];
                    var edgeB = group[1];

                    // 检查UV是否不连续
                    if (!AreUVsContinuous(edgeA, edgeB, uvEpsilon))
                    {
                        seams.Add(new SeamAdjacency
                        {
                            edgeA = edgeA,
                            edgeB = edgeB,
                            islandA = -1,
                            islandB = -1,
                            reversedMapping = false  // 暂时设为false，后面统一处理
                        });
                    }
                }
                else if (group.Count > 2)
                {
                    // 多条边的情况，两两配对
                    for (int i = 0; i < group.Count; i++)
                    {
                        for (int j = i + 1; j < group.Count; j++)
                        {
                            var edgeA = group[i];
                            var edgeB = group[j];

                            if (!AreUVsContinuous(edgeA, edgeB, uvEpsilon))
                            {
                                seams.Add(new SeamAdjacency
                                {
                                    edgeA = edgeA,
                                    edgeB = edgeB,
                                    islandA = -1,
                                    islandB = -1,
                                    reversedMapping = false  // 暂时设为false，后面统一处理
                                });
                            }
                        }
                    }
                }
            }

            // Step 3.5: 建立全局顶点对应关系，确保共享顶点的边使用一致的映射方向
            BuildGlobalVertexMapping(seams, positionPrecision);

            result.seams = seams;
            result.seamCount = seams.Count;

            Debug.Log($"[UV邻接图] 总边数: {allEdges.Count}, 位置分组数: {edgesByPosition.Count}, UV接缝: {seams.Count}");

            // Step 4: 识别UV岛
            result.islands = IdentifyUVIslands(mesh, uvChannel, uvEpsilon);
            result.islandCount = result.islands.Count;

            Debug.Log($"[UV邻接图] UV岛数: {result.islandCount}");

            // Step 5: 分配岛ID
            AssignIslandIdsToSeams(result);

            return result;
        }

        public static float GetParameterOnEdge(Vector2 uv, Vector2 edgeUvA, Vector2 edgeUvB)
        {
            Vector2 edgeDir = edgeUvB - edgeUvA;
            float edgeLengthSq = edgeDir.sqrMagnitude;

            if (edgeLengthSq < 0.0001f)
                return 0f;

            Vector2 toPoint = uv - edgeUvA;
            return Mathf.Clamp01(Vector2.Dot(toPoint, edgeDir) / edgeLengthSq);
        }

        public static Vector2 MapUVAcrossSeam(Vector2 uv, in SeamAdjacency seam)
        {
            float t = GetParameterOnEdge(uv, seam.edgeA.uvA, seam.edgeA.uvB);

            if (seam.reversedMapping)
                return Vector2.Lerp(seam.edgeB.uvB, seam.edgeB.uvA, t);
            else
                return Vector2.Lerp(seam.edgeB.uvA, seam.edgeB.uvB, t);
        }

        #endregion

        #region 私有方法

        private static EdgeInfo CreateEdge(int vA, int vB, int triIndex, int localEdgeIndex,
            Vector3[] vertices, Vector2[] uvs)
        {
            return new EdgeInfo
            {
                vertexA = vA,
                vertexB = vB,
                triangleIndex = triIndex,
                localEdgeIndex = localEdgeIndex,
                uvA = uvs[vA],
                uvB = uvs[vB],
                posA = vertices[vA],
                posB = vertices[vB]
            };
        }

        private static bool AreUVsContinuous(EdgeInfo edgeA, EdgeInfo edgeB, float epsilon)
        {
            bool match1 = Vector2.Distance(edgeA.uvA, edgeB.uvA) < epsilon &&
                          Vector2.Distance(edgeA.uvB, edgeB.uvB) < epsilon;

            bool match2 = Vector2.Distance(edgeA.uvA, edgeB.uvB) < epsilon &&
                          Vector2.Distance(edgeA.uvB, edgeB.uvA) < epsilon;

            return match1 || match2;
        }

        private static bool DetermineVertexCorrespondence(EdgeInfo edgeA, EdgeInfo edgeB)
        {
            // 计算所有可能的顶点对应关系的距离
            float distAA = Vector3.Distance(edgeA.posA, edgeB.posA);
            float distAB = Vector3.Distance(edgeA.posA, edgeB.posB);
            float distBA = Vector3.Distance(edgeA.posB, edgeB.posA);
            float distBB = Vector3.Distance(edgeA.posB, edgeB.posB);

            // 情况1: A-A, B-B 对应（正向）
            // edgeA.posA -> edgeB.posA, edgeA.posB -> edgeB.posB
            float errorForward = distAA + distBB;

            // 情况2: A-B, B-A 对应（反向）
            // edgeA.posA -> edgeB.posB, edgeA.posB -> edgeB.posA
            float errorReversed = distAB + distBA;

            // 选择误差更小的对应方式
            // 返回true表示反向映射（A->B, B->A）
            return errorReversed < errorForward;
        }

        /// <summary>
        /// 建立全局顶点对应关系，确保共享顶点的边使用一致的映射方向
        /// </summary>
        private static void BuildGlobalVertexMapping(List<SeamAdjacency> seams, int precision)
        {
            // 使用Union-Find来建立顶点对应关系
            // 每个顶点位置有一个唯一的"代表"
            // 我们需要建立edgeA侧顶点和edgeB侧顶点之间的对应关系
            
            // 步骤1: 收集所有接缝边的顶点位置
            // 使用位置hash作为顶点的唯一标识
            Dictionary<long, List<int>> positionToSeamIndices = new Dictionary<long, List<int>>();
            
            // 对于每条接缝，记录edgeA的两个顶点位置
            for (int seamIdx = 0; seamIdx < seams.Count; seamIdx++)
            {
                var seam = seams[seamIdx];
                
                // edgeA的两个顶点
                long posA1 = GetPositionHashSingle(seam.edgeA.posA, precision);
                long posA2 = GetPositionHashSingle(seam.edgeA.posB, precision);
                
                // edgeB的两个顶点
                long posB1 = GetPositionHashSingle(seam.edgeB.posA, precision);
                long posB2 = GetPositionHashSingle(seam.edgeB.posB, precision);
                
                // 记录位置到接缝索引的映射
                if (!positionToSeamIndices.ContainsKey(posA1))
                    positionToSeamIndices[posA1] = new List<int>();
                if (!positionToSeamIndices.ContainsKey(posA2))
                    positionToSeamIndices[posA2] = new List<int>();
                
                positionToSeamIndices[posA1].Add(seamIdx);
                positionToSeamIndices[posA2].Add(seamIdx);
            }
            
            // 步骤2: 建立顶点对应关系
            // 使用字典记录：edgeA侧的位置 -> edgeB侧的对应位置
            Dictionary<long, long> vertexMapping = new Dictionary<long, long>();
            
            // 步骤3: 使用BFS传播顶点对应关系
            HashSet<int> processedSeams = new HashSet<int>();
            Queue<int> seamQueue = new Queue<int>();
            
            // 从第一条接缝开始
            if (seams.Count > 0)
            {
                seamQueue.Enqueue(0);
            }
            
            while (processedSeams.Count < seams.Count)
            {
                int seamIdx;
                
                if (seamQueue.Count > 0)
                {
                    seamIdx = seamQueue.Dequeue();
                }
                else
                {
                    // 找一条未处理的接缝
                    seamIdx = -1;
                    for (int i = 0; i < seams.Count; i++)
                    {
                        if (!processedSeams.Contains(i))
                        {
                            seamIdx = i;
                            break;
                        }
                    }
                    
                    if (seamIdx == -1)
                        break;
                }
                
                if (processedSeams.Contains(seamIdx))
                    continue;
                
                var seam = seams[seamIdx];
                long posA1 = GetPositionHashSingle(seam.edgeA.posA, precision);
                long posA2 = GetPositionHashSingle(seam.edgeA.posB, precision);
                long posB1 = GetPositionHashSingle(seam.edgeB.posA, precision);
                long posB2 = GetPositionHashSingle(seam.edgeB.posB, precision);
                
                // 检查是否已有部分顶点映射
                bool hasMapping1 = vertexMapping.TryGetValue(posA1, out long mappedB1);
                bool hasMapping2 = vertexMapping.TryGetValue(posA2, out long mappedB2);
                
                bool reversed;
                
                if (!hasMapping1 && !hasMapping2)
                {
                    // 没有现有映射，根据距离确定映射方向
                    reversed = DetermineVertexCorrespondence(seam.edgeA, seam.edgeB);
                    
                    // 建立新的映射
                    if (reversed)
                    {
                        vertexMapping[posA1] = posB2;
                        vertexMapping[posA2] = posB1;
                    }
                    else
                    {
                        vertexMapping[posA1] = posB1;
                        vertexMapping[posA2] = posB2;
                    }
                }
                else if (hasMapping1 && !hasMapping2)
                {
                    // posA1已有映射，根据它确定方向
                    reversed = (mappedB1 == posB2);
                    vertexMapping[posA2] = reversed ? posB1 : posB2;
                }
                else if (!hasMapping1 && hasMapping2)
                {
                    // posA2已有映射，根据它确定方向
                    reversed = (mappedB2 == posB1);
                    vertexMapping[posA1] = reversed ? posB2 : posB1;
                }
                else
                {
                    // 两个顶点都已有映射，检查一致性
                    reversed = (mappedB1 == posB2 && mappedB2 == posB1);
                    
                    // 如果映射不一致，输出警告
                    bool consistent = (reversed && mappedB1 == posB2 && mappedB2 == posB1) ||
                                     (!reversed && mappedB1 == posB1 && mappedB2 == posB2);
                    
                    if (!consistent)
                    {
                        Debug.LogWarning($"[UV邻接图] 接缝 #{seamIdx} 的顶点映射与已有映射冲突！\n" +
                            $"  posA1映射: {mappedB1}, 期望: {(reversed ? posB2 : posB1)}\n" +
                            $"  posA2映射: {mappedB2}, 期望: {(reversed ? posB1 : posB2)}");
                    }
                }
                
                // 更新接缝的reversedMapping
                SeamAdjacency updatedSeam = seam;
                updatedSeam.reversedMapping = reversed;
                seams[seamIdx] = updatedSeam;
                
                processedSeams.Add(seamIdx);
                
                // 将共享顶点的其他接缝加入队列
                if (positionToSeamIndices.TryGetValue(posA1, out var connectedSeams1))
                {
                    foreach (int connectedIdx in connectedSeams1)
                    {
                        if (!processedSeams.Contains(connectedIdx))
                            seamQueue.Enqueue(connectedIdx);
                    }
                }
                if (positionToSeamIndices.TryGetValue(posA2, out var connectedSeams2))
                {
                    foreach (int connectedIdx in connectedSeams2)
                    {
                        if (!processedSeams.Contains(connectedIdx))
                            seamQueue.Enqueue(connectedIdx);
                    }
                }
            }
            
            Debug.Log($"[UV邻接图] 建立了 {vertexMapping.Count} 个顶点对应关系");
        }

        /// <summary>
        /// 获取单个位置的hash值
        /// </summary>
        private static long GetPositionHashSingle(Vector3 pos, int precision)
        {
            int x = Mathf.RoundToInt(pos.x * precision);
            int y = Mathf.RoundToInt(pos.y * precision);
            int z = Mathf.RoundToInt(pos.z * precision);
            
            unchecked
            {
                long hash = 17;
                hash = hash * 31 + x;
                hash = hash * 31 + y;
                hash = hash * 31 + z;
                return hash;
            }
        }

        /// <summary>
        /// 验证接缝映射的正确性（用于调试）
        /// </summary>
        public static void ValidateSeamMapping(SeamAdjacency seam, int seamIndex)
        {
            var edgeA = seam.edgeA;
            var edgeB = seam.edgeB;
            bool reversed = seam.reversedMapping;

            // 验证3D位置的对应关系
            float distAA = Vector3.Distance(edgeA.posA, edgeB.posA);
            float distAB = Vector3.Distance(edgeA.posA, edgeB.posB);
            float distBA = Vector3.Distance(edgeA.posB, edgeB.posA);
            float distBB = Vector3.Distance(edgeA.posB, edgeB.posB);

            // 计算两种映射方式的误差
            float errorForward = distAA + distBB;  // A->A, B->B
            float errorReversed = distAB + distBA; // A->B, B->A

            Debug.Log($"[验证接缝 #{seamIndex}]\n" +
                $"  EdgeA: 顶点({edgeA.vertexA}, {edgeA.vertexB}), " +
                $"3D位置({edgeA.posA.x:F4},{edgeA.posA.y:F4},{edgeA.posA.z:F4})->({edgeA.posB.x:F4},{edgeA.posB.y:F4},{edgeA.posB.z:F4})\n" +
                $"  EdgeA UV: ({edgeA.uvA.x:F6},{edgeA.uvA.y:F6})->({edgeA.uvB.x:F6},{edgeA.uvB.y:F6})\n" +
                $"  EdgeB: 顶点({edgeB.vertexA}, {edgeB.vertexB}), " +
                $"3D位置({edgeB.posA.x:F4},{edgeB.posA.y:F4},{edgeB.posA.z:F4})->({edgeB.posB.x:F4},{edgeB.posB.y:F4},{edgeB.posB.z:F4})\n" +
                $"  EdgeB UV: ({edgeB.uvA.x:F6},{edgeB.uvA.y:F6})->({edgeB.uvB.x:F6},{edgeB.uvB.y:F6})\n" +
                $"  3D距离: A-A={distAA:F6}, A-B={distAB:F6}, B-A={distBA:F6}, B-B={distBB:F6}\n" +
                $"  映射误差: 正向={errorForward:F6}, 反向={errorReversed:F6}\n" +
                $"  reversedMapping={reversed} (选择{(errorReversed < errorForward ? "反向" : "正向")})");

            // 验证映射逻辑
            // 测试t=0和t=1的映射
            Vector2 mappedT0, mappedT1;
            Vector3 targetPosForT0, targetPosForT1;
            
            if (reversed)
            {
                // 反向映射：edgeA.uvA -> edgeB.uvB, edgeA.uvB -> edgeB.uvA
                mappedT0 = edgeB.uvB;
                mappedT1 = edgeB.uvA;
                targetPosForT0 = edgeB.posB;
                targetPosForT1 = edgeB.posA;
            }
            else
            {
                // 正向映射：edgeA.uvA -> edgeB.uvA, edgeA.uvB -> edgeB.uvB
                mappedT0 = edgeB.uvA;
                mappedT1 = edgeB.uvB;
                targetPosForT0 = edgeB.posA;
                targetPosForT1 = edgeB.posB;
            }

            Debug.Log($"  映射验证:\n" +
                $"    t=0: sourceUV({edgeA.uvA.x:F6},{edgeA.uvA.y:F6}) -> targetUV({mappedT0.x:F6},{mappedT0.y:F6})\n" +
                $"    t=1: sourceUV({edgeA.uvB.x:F6},{edgeA.uvB.y:F6}) -> targetUV({mappedT1.x:F6},{mappedT1.y:F6})");

            // 验证3D位置是否真的对应
            float error0 = Vector3.Distance(edgeA.posA, targetPosForT0);
            float error1 = Vector3.Distance(edgeA.posB, targetPosForT1);

            Debug.Log($"  3D位置验证:\n" +
                $"    t=0: 源位置({edgeA.posA.x:F4},{edgeA.posA.y:F4},{edgeA.posA.z:F4}) " +
                $"目标位置({targetPosForT0.x:F4},{targetPosForT0.y:F4},{targetPosForT0.z:F4}) " +
                $"误差={error0:F6}\n" +
                $"    t=1: 源位置({edgeA.posB.x:F4},{edgeA.posB.y:F4},{edgeA.posB.z:F4}) " +
                $"目标位置({targetPosForT1.x:F4},{targetPosForT1.y:F4},{targetPosForT1.z:F4}) " +
                $"误差={error1:F6}");

            if (error0 > 0.001f || error1 > 0.001f)
            {
                Debug.LogWarning($"  ⚠️ 3D位置映射存在较大误差！可能需要检查顶点对应关系。");
            }
        }

        /// <summary>
        /// 检查相邻边的映射一致性（用于调试边与边之间的不连续问题）
        /// 使用3D位置而不是顶点索引来检查共享顶点
        /// </summary>
        public static void CheckAdjacentSeamsConsistency(List<SeamAdjacency> seams)
        {
            Debug.Log($"[UV邻接图] 检查相邻边的映射一致性，共 {seams.Count} 条接缝...");

            // 使用3D位置来分组顶点
            // 对于每条接缝的每个顶点，记录其3D位置和映射目标
            Dictionary<long, List<(int seamIdx, bool isVertexA, Vector2 targetUV)>> positionToMappings 
                = new Dictionary<long, List<(int, bool, Vector2)>>();

            int precision = 100000;

            for (int seamIdx = 0; seamIdx < seams.Count; seamIdx++)
            {
                var seam = seams[seamIdx];
                
                // edgeA的两个顶点
                long posA1 = GetPositionHashSingle(seam.edgeA.posA, precision);
                long posA2 = GetPositionHashSingle(seam.edgeA.posB, precision);
                
                // 计算映射目标
                Vector2 targetUV1 = seam.reversedMapping ? seam.edgeB.uvB : seam.edgeB.uvA;
                Vector2 targetUV2 = seam.reversedMapping ? seam.edgeB.uvA : seam.edgeB.uvB;
                
                if (!positionToMappings.ContainsKey(posA1))
                    positionToMappings[posA1] = new List<(int, bool, Vector2)>();
                if (!positionToMappings.ContainsKey(posA2))
                    positionToMappings[posA2] = new List<(int, bool, Vector2)>();
                
                positionToMappings[posA1].Add((seamIdx, true, targetUV1));
                positionToMappings[posA2].Add((seamIdx, false, targetUV2));
            }

            // 检查每个位置的所有映射是否一致
            int inconsistentCount = 0;
            foreach (var kvp in positionToMappings)
            {
                var mappings = kvp.Value;
                
                if (mappings.Count > 1)
                {
                    // 同一个3D位置被多条边引用，检查映射是否一致
                    Vector2 firstTarget = mappings[0].targetUV;
                    
                    for (int i = 1; i < mappings.Count; i++)
                    {
                        float uvDiff = Vector2.Distance(firstTarget, mappings[i].targetUV);
                        if (uvDiff > 0.001f)
                        {
                            inconsistentCount++;
                            var seam1 = seams[mappings[0].seamIdx];
                            var seam2 = seams[mappings[i].seamIdx];
                            
                            // 找出共享的3D位置
                            Vector3 sharedPos = seam1.edgeA.posA;
                            if (GetPositionHashSingle(seam1.edgeA.posB, precision) == kvp.Key)
                                sharedPos = seam1.edgeA.posB;
                            
                            Debug.LogWarning($"[映射不一致 #{inconsistentCount}]\n" +
                                $"  共享3D位置: ({sharedPos.x:F4}, {sharedPos.y:F4}, {sharedPos.z:F4})\n" +
                                $"  Seam #{mappings[0].seamIdx}:\n" +
                                $"    edgeA: UV({seam1.edgeA.uvA.x:F4},{seam1.edgeA.uvA.y:F4})->({seam1.edgeA.uvB.x:F4},{seam1.edgeA.uvB.y:F4})\n" +
                                $"    edgeB: UV({seam1.edgeB.uvA.x:F4},{seam1.edgeB.uvA.y:F4})->({seam1.edgeB.uvB.x:F4},{seam1.edgeB.uvB.y:F4})\n" +
                                $"    reversed={seam1.reversedMapping}, 映射到: ({firstTarget.x:F6}, {firstTarget.y:F6})\n" +
                                $"  Seam #{mappings[i].seamIdx}:\n" +
                                $"    edgeA: UV({seam2.edgeA.uvA.x:F4},{seam2.edgeA.uvA.y:F4})->({seam2.edgeA.uvB.x:F4},{seam2.edgeA.uvB.y:F4})\n" +
                                $"    edgeB: UV({seam2.edgeB.uvA.x:F4},{seam2.edgeB.uvA.y:F4})->({seam2.edgeB.uvB.x:F4},{seam2.edgeB.uvB.y:F4})\n" +
                                $"    reversed={seam2.reversedMapping}, 映射到: ({mappings[i].targetUV.x:F6}, {mappings[i].targetUV.y:F6})\n" +
                                $"  差异: {uvDiff:F6}");
                        }
                    }
                }
            }

            if (inconsistentCount == 0)
            {
                Debug.Log($"[UV邻接图] ✓ 所有相邻边的映射一致");
            }
            else
            {
                Debug.LogWarning($"[UV邻接图] ⚠️ 发现 {inconsistentCount} 处映射不一致！这是边与边之间不连续的原因。");
            }
        }

        private static List<UVIsland> IdentifyUVIslands(Mesh mesh, int uvChannel, float uvEpsilon)
        {
            List<UVIsland> islands = new List<UVIsland>();
            HashSet<int> visitedTriangles = new HashSet<int>();

            int[] triangles = mesh.triangles;
            int triangleCount = triangles.Length / 3;

            Dictionary<int, List<int>> neighbors = BuildTriangleNeighbors(mesh, uvChannel, uvEpsilon);

            for (int triIndex = 0; triIndex < triangleCount; triIndex++)
            {
                if (visitedTriangles.Contains(triIndex))
                    continue;

                UVIsland island = FloodFillIsland(triIndex, visitedTriangles, neighbors, mesh, uvChannel);
                islands.Add(island);
            }

            return islands;
        }

        private static Dictionary<int, List<int>> BuildTriangleNeighbors(Mesh mesh, int uvChannel, float uvEpsilon)
        {
            Dictionary<int, List<int>> neighbors = new Dictionary<int, List<int>>();

            Vector3[] vertices = mesh.vertices;
            int[] triangles = mesh.triangles;
            Vector2[] uvs = uvChannel == 0 ? mesh.uv : mesh.uv2;

            // 计算位置Hash精度（与Build函数保持一致）
            Bounds bounds = mesh.bounds;
            float maxDimension = Mathf.Max(bounds.size.x, bounds.size.y, bounds.size.z);
            int precision = Mathf.Max(10000, Mathf.RoundToInt(100000f / Mathf.Max(maxDimension, 0.001f)));

            // 使用边到三角形的映射
            Dictionary<long, List<int>> edgeToTriangles = new Dictionary<long, List<int>>();

            int triangleCount = triangles.Length / 3;

            for (int triIndex = 0; triIndex < triangleCount; triIndex++)
            {
                int i0 = triangles[triIndex * 3 + 0];
                int i1 = triangles[triIndex * 3 + 1];
                int i2 = triangles[triIndex * 3 + 2];

                AddEdgeTriangleRef(edgeToTriangles, i0, i1, triIndex, vertices, precision);
                AddEdgeTriangleRef(edgeToTriangles, i1, i2, triIndex, vertices, precision);
                AddEdgeTriangleRef(edgeToTriangles, i2, i0, triIndex, vertices, precision);
            }

            foreach (var kvp in edgeToTriangles)
            {
                var triList = kvp.Value;

                if (triList.Count == 2)
                {
                    int triA = triList[0];
                    int triB = triList[1];

                    if (AreTrianglesUVContinuous(triA, triB, triangles, uvs, uvEpsilon))
                    {
                        if (!neighbors.ContainsKey(triA)) neighbors[triA] = new List<int>();
                        if (!neighbors.ContainsKey(triB)) neighbors[triB] = new List<int>();

                        neighbors[triA].Add(triB);
                        neighbors[triB].Add(triA);
                    }
                }
            }

            return neighbors;
        }

        private static void AddEdgeTriangleRef(Dictionary<long, List<int>> edgeToTriangles,
            int vA, int vB, int triIndex, Vector3[] vertices, int precision = 100000)
        {
            long key = GetPositionHash(vertices[vA], vertices[vB], precision);

            if (!edgeToTriangles.ContainsKey(key))
                edgeToTriangles[key] = new List<int>();

            if (!edgeToTriangles[key].Contains(triIndex))
                edgeToTriangles[key].Add(triIndex);
        }

        private static long GetPositionHash(Vector3 posA, Vector3 posB, int precision = 100000)
        {
            int ax = Mathf.RoundToInt(posA.x * precision);
            int ay = Mathf.RoundToInt(posA.y * precision);
            int az = Mathf.RoundToInt(posA.z * precision);
            int bx = Mathf.RoundToInt(posB.x * precision);
            int by = Mathf.RoundToInt(posB.y * precision);
            int bz = Mathf.RoundToInt(posB.z * precision);

            if (CompareInt3(ax, ay, az, bx, by, bz) > 0)
            {
                int tx = ax; ax = bx; bx = tx;
                int ty = ay; ay = by; by = ty;
                int tz = az; az = bz; bz = tz;
            }

            unchecked
            {
                long hash = 17;
                hash = hash * 31 + ax;
                hash = hash * 31 + ay;
                hash = hash * 31 + az;
                hash = hash * 31 + bx;
                hash = hash * 31 + by;
                hash = hash * 31 + bz;
                return hash;
            }
        }

        private static int CompareInt3(int ax, int ay, int az, int bx, int by, int bz)
        {
            if (ax != bx) return ax.CompareTo(bx);
            if (ay != by) return ay.CompareTo(by);
            return az.CompareTo(bz);
        }

        private static bool AreTrianglesUVContinuous(int triA, int triB, int[] triangles, Vector2[] uvs, float epsilon)
        {
            int[] edgesA = new int[] {
                triangles[triA * 3 + 0], triangles[triA * 3 + 1],
                triangles[triA * 3 + 1], triangles[triA * 3 + 2],
                triangles[triA * 3 + 2], triangles[triA * 3 + 0]
            };

            int[] edgesB = new int[] {
                triangles[triB * 3 + 0], triangles[triB * 3 + 1],
                triangles[triB * 3 + 1], triangles[triB * 3 + 2],
                triangles[triB * 3 + 2], triangles[triB * 3 + 0]
            };

            for (int i = 0; i < 6; i += 2)
            {
                Vector2 uvA1 = uvs[edgesA[i]];
                Vector2 uvA2 = uvs[edgesA[i + 1]];

                for (int j = 0; j < 6; j += 2)
                {
                    Vector2 uvB1 = uvs[edgesB[j]];
                    Vector2 uvB2 = uvs[edgesB[j + 1]];

                    bool match1 = Vector2.Distance(uvA1, uvB1) < epsilon &&
                                  Vector2.Distance(uvA2, uvB2) < epsilon;
                    bool match2 = Vector2.Distance(uvA1, uvB2) < epsilon &&
                                  Vector2.Distance(uvA2, uvB1) < epsilon;

                    if (match1 || match2)
                        return true;
                }
            }

            return false;
        }

        private static UVIsland FloodFillIsland(int startTriangle, HashSet<int> visitedTriangles,
            Dictionary<int, List<int>> neighbors, Mesh mesh, int uvChannel)
        {
            UVIsland island = new UVIsland
            {
                id = -1,
                triangleIndices = new List<int>(),
                uvBounds = new Rect()
            };

            Vector2[] uvs = uvChannel == 0 ? mesh.uv : mesh.uv2;
            int[] triangles = mesh.triangles;

            Queue<int> queue = new Queue<int>();
            queue.Enqueue(startTriangle);

            float minX = float.MaxValue, minY = float.MaxValue;
            float maxX = float.MinValue, maxY = float.MinValue;

            while (queue.Count > 0)
            {
                int triIndex = queue.Dequeue();

                if (visitedTriangles.Contains(triIndex))
                    continue;

                visitedTriangles.Add(triIndex);
                island.triangleIndices.Add(triIndex);

                for (int i = 0; i < 3; i++)
                {
                    int vertexIndex = triangles[triIndex * 3 + i];
                    Vector2 uv = uvs[vertexIndex];

                    minX = Mathf.Min(minX, uv.x);
                    minY = Mathf.Min(minY, uv.y);
                    maxX = Mathf.Max(maxX, uv.x);
                    maxY = Mathf.Max(maxY, uv.y);
                }

                if (neighbors.TryGetValue(triIndex, out List<int> neighborList))
                {
                    foreach (int neighbor in neighborList)
                    {
                        if (!visitedTriangles.Contains(neighbor))
                            queue.Enqueue(neighbor);
                    }
                }
            }

            island.uvBounds = new Rect(minX, minY, maxX - minX, maxY - minY);
            return island;
        }

        private static void AssignIslandIdsToSeams(BuildResult result)
        {
            for (int islandId = 0; islandId < result.islands.Count; islandId++)
            {
                foreach (int triIndex in result.islands[islandId].triangleIndices)
                {
                    result.triangleToIsland[triIndex] = islandId;
                }
            }

            for (int i = 0; i < result.seams.Count; i++)
            {
                SeamAdjacency seam = result.seams[i];

                if (result.triangleToIsland.TryGetValue(seam.edgeA.triangleIndex, out int islandA))
                    seam.islandA = islandA;

                if (result.triangleToIsland.TryGetValue(seam.edgeB.triangleIndex, out int islandB))
                    seam.islandB = islandB;

                result.seams[i] = seam;
            }
        }

        #endregion
    }
}
