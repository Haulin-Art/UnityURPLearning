using UnityEngine;
using UnityEditor;
using System.IO;
using System.Collections.Generic;

namespace UVAdjacencyMap
{
    /// <summary>
    /// UV邻接图生成工具编辑器窗口
    /// </summary>
    public class UVAdjacencyMapWindow : EditorWindow
    {
        #region 常量

        private const string MENU_PATH = "Tools/UV邻接图生成工具";
        private const string WINDOW_TITLE = "UV邻接图生成工具";

        #endregion

        #region 序列化字段

        [Header("目标网格")]
        [SerializeField] private Mesh targetMesh;

        [Header("烘焙设置")]
        [SerializeField] private int resolution = 1024;
        [SerializeField] [Range(1, 32)] private int edgePadding = 4;
        [SerializeField] [Range(0, 1)] private float uvEpsilon = 0.001f;
        [SerializeField] private int uvChannel = 0;

        [Header("输出设置")]
        [SerializeField] private string outputPath = "Assets/UVAdjacencyMap.exr";
        [SerializeField] private bool autoSave = true;
        [SerializeField] private bool useEXRFormat = true;  // 使用EXR格式获得更高精度

        [Header("调试设置")]
        [SerializeField] private DebugMode debugMode = DebugMode.None;
        [SerializeField] private bool showPreview = true;
        [SerializeField] private bool enableDebugLog = false;  // 启用详细调试日志

        #endregion

        #region 私有字段

        private Texture2D previewTexture;
        private UVAdjacencyMapBuilder.BuildResult lastBuildResult;
        private UVAdjacencyMapBaker.BakeResult lastBakeResult;
        private Vector2 scrollPosition;
        private bool isProcessing = false;

        #endregion

        #region 枚举

        /// <summary>
        /// 调试模式
        /// </summary>
        public enum DebugMode
        {
            None,               // 无调试输出
            LogStatistics,      // 输出统计信息
            LogSeamDetails,     // 输出接缝详情
            SaveSeamData,       // 保存接缝数据
            VisualizeInScene    // 在场景中可视化
        }

        #endregion

        #region 编辑器入口

        [MenuItem(MENU_PATH)]
        public static void ShowWindow()
        {
            UVAdjacencyMapWindow window = GetWindow<UVAdjacencyMapWindow>(WINDOW_TITLE);
            window.minSize = new Vector2(400, 500);
            window.Show();
        }

        #endregion

        #region GUI

        private void OnGUI()
        {
            scrollPosition = EditorGUILayout.BeginScrollView(scrollPosition);

            DrawHeader();
            DrawMeshSelection();
            DrawBakeSettings();
            DrawOutputSettings();
            DrawDebugSettings();
            DrawActionButtons();
            
            if (showPreview && previewTexture != null)
            {
                DrawPreview();
            }

            if (lastBuildResult.seams != null && debugMode != DebugMode.None)
            {
                DrawDebugInfo();
            }

            EditorGUILayout.EndScrollView();
        }

        private void DrawHeader()
        {
            EditorGUILayout.Space(10);
            
            using (new EditorGUILayout.HorizontalScope())
            {
                GUILayout.FlexibleSpace();
                GUILayout.Label("UV邻接图生成工具", EditorStyles.boldLabel);
                GUILayout.FlexibleSpace();
            }
            
            EditorGUILayout.HelpBox(
                "根据网格的UV拓扑生成邻接纹理，用于跨UV岛的无缝流动效果。",
                MessageType.Info);
            
            EditorGUILayout.Space(10);
        }

        private void DrawMeshSelection()
        {
            EditorGUILayout.LabelField("目标网格", EditorStyles.boldLabel);
            
            EditorGUI.BeginChangeCheck();
            targetMesh = (Mesh)EditorGUILayout.ObjectField("网格", targetMesh, typeof(Mesh), false);
            
            if (targetMesh != null)
            {
                // 显示网格信息
                EditorGUILayout.LabelField($"  顶点数: {targetMesh.vertexCount}");
                EditorGUILayout.LabelField($"  三角形数: {targetMesh.triangles.Length / 3}");
                EditorGUILayout.LabelField($"  有UV: {(targetMesh.uv != null && targetMesh.uv.Length > 0 ? "是" : "否")}");
            }
            
            EditorGUILayout.Space(10);
        }

        private void DrawBakeSettings()
        {
            EditorGUILayout.LabelField("烘焙设置", EditorStyles.boldLabel);
            
            resolution = EditorGUILayout.IntPopup("分辨率", resolution, 
                new[] { "256", "512", "1024", "2048", "4096" },
                new[] { 256, 512, 1024, 2048, 4096 });
            
            edgePadding = EditorGUILayout.IntSlider("边缘扩展像素", edgePadding, 1, 32);
            
            uvEpsilon = EditorGUILayout.FloatField("UV比较精度", uvEpsilon);
            uvChannel = EditorGUILayout.IntPopup("UV通道", uvChannel,
                new[] { "UV1", "UV2", "UV3", "UV4" },
                new[] { 0, 1, 2, 3 });
            
            EditorGUILayout.Space(10);
        }

        private void DrawOutputSettings()
        {
            EditorGUILayout.LabelField("输出设置", EditorStyles.boldLabel);
            
            // EXR格式选项
            useEXRFormat = EditorGUILayout.Toggle("使用EXR格式", useEXRFormat);
            EditorGUILayout.HelpBox(
                useEXRFormat ? "EXR格式：32位浮点精度，适合流体模拟" : "PNG格式：8位精度，文件较小",
                MessageType.None);
            
            EditorGUILayout.BeginHorizontal();
            EditorGUILayout.PrefixLabel("输出路径");
            
            // 根据格式自动调整扩展名
            string currentExt = Path.GetExtension(outputPath);
            string desiredExt = useEXRFormat ? ".exr" : ".png";
            if (currentExt != desiredExt && !string.IsNullOrEmpty(currentExt))
            {
                outputPath = Path.ChangeExtension(outputPath, desiredExt);
            }
            
            outputPath = EditorGUILayout.TextField(outputPath);
            string fileExt = useEXRFormat ? "exr" : "png";
            if (GUILayout.Button("...", GUILayout.Width(30)))
            {
                string path = EditorUtility.SaveFilePanel("保存邻接纹理", 
                    Path.GetDirectoryName(outputPath), 
                    Path.GetFileNameWithoutExtension(outputPath), 
                    fileExt);
                if (!string.IsNullOrEmpty(path))
                {
                    outputPath = "Assets" + path.Substring(Application.dataPath.Length);
                }
            }
            EditorGUILayout.EndHorizontal();
            
            autoSave = EditorGUILayout.Toggle("自动保存", autoSave);
            
            EditorGUILayout.Space(10);
        }

        private void DrawDebugSettings()
        {
            EditorGUILayout.LabelField("调试设置", EditorStyles.boldLabel);
            
            debugMode = (DebugMode)EditorGUILayout.EnumPopup("调试模式", debugMode);
            showPreview = EditorGUILayout.Toggle("显示预览", showPreview);
            enableDebugLog = EditorGUILayout.Toggle("详细日志", enableDebugLog);
            
            if (enableDebugLog)
            {
                EditorGUILayout.HelpBox("启用后将输出边映射的详细信息，用于调试精度问题。", MessageType.Info);
            }
            
            EditorGUILayout.Space(10);
        }

        private void DrawActionButtons()
        {
            EditorGUI.BeginDisabledGroup(targetMesh == null || isProcessing);
            
            EditorGUILayout.BeginHorizontal();
            GUILayout.FlexibleSpace();
            
            if (GUILayout.Button("生成邻接图", GUILayout.Width(150), GUILayout.Height(30)))
            {
                Generate();
            }
            
            GUILayout.FlexibleSpace();
            EditorGUILayout.EndHorizontal();
            
            EditorGUI.EndDisabledGroup();
            
            EditorGUILayout.Space(10);
        }

        private void DrawPreview()
        {
            EditorGUILayout.LabelField("预览", EditorStyles.boldLabel);
            
            Rect previewRect = GUILayoutUtility.GetRect(200, 200, GUILayout.ExpandWidth(true));
            
            // 绘制背景
            EditorGUI.DrawRect(previewRect, new Color(0.2f, 0.2f, 0.2f, 1f));
            
            // 绘制预览纹理
            if (previewTexture != null)
            {
                GUI.DrawTexture(previewRect, previewTexture, ScaleMode.ScaleToFit);
            }
            
            // 绘制说明
            EditorGUILayout.HelpBox(
                "R/G通道: 邻接UV坐标\n" +
                "B通道: 到边缘的距离权重\n" +
                "A通道: 邻接岛ID",
                MessageType.None);
            
            EditorGUILayout.Space(10);
        }

        private void DrawDebugInfo()
        {
            EditorGUILayout.LabelField("调试信息", EditorStyles.boldLabel);
            
            switch (debugMode)
            {
                case DebugMode.LogStatistics:
                    DrawStatistics();
                    break;
                    
                case DebugMode.LogSeamDetails:
                    DrawSeamDetails();
                    break;
                    
                case DebugMode.VisualizeInScene:
                    DrawVisualizationInfo();
                    break;
            }
        }

        private void DrawStatistics()
        {
            EditorGUILayout.LabelField($"总边数: {lastBuildResult.totalEdgeCount}");
            EditorGUILayout.LabelField($"接缝数: {lastBuildResult.seamCount}");
            EditorGUILayout.LabelField($"UV岛数: {lastBuildResult.islandCount}");
            
            if (lastBakeResult.success)
            {
                EditorGUILayout.LabelField($"纹理分辨率: {resolution}x{resolution}");
            }
        }

        private void DrawSeamDetails()
        {
            int displayCount = Mathf.Min(10, lastBuildResult.seams.Count);
            
            for (int i = 0; i < displayCount; i++)
            {
                var seam = lastBuildResult.seams[i];
                
                EditorGUILayout.BeginVertical(EditorStyles.helpBox);
                EditorGUILayout.LabelField($"接缝 #{i}", EditorStyles.boldLabel);
                EditorGUILayout.LabelField($"  边A: 三角形{seam.edgeA.triangleIndex}, " +
                    $"UV({seam.edgeA.uvA.x:F3},{seam.edgeA.uvA.y:F3})-({seam.edgeA.uvB.x:F3},{seam.edgeA.uvB.y:F3})");
                EditorGUILayout.LabelField($"  边B: 三角形{seam.edgeB.triangleIndex}, " +
                    $"UV({seam.edgeB.uvA.x:F3},{seam.edgeB.uvA.y:F3})-({seam.edgeB.uvB.x:F3},{seam.edgeB.uvB.y:F3})");
                EditorGUILayout.LabelField($"  岛A: {seam.islandA}, 岛B: {seam.islandB}");
                EditorGUILayout.EndVertical();
            }
            
            if (lastBuildResult.seams.Count > 10)
            {
                EditorGUILayout.LabelField($"... 还有 {lastBuildResult.seams.Count - 10} 条接缝");
            }
        }

        private void DrawVisualizationInfo()
        {
            EditorGUILayout.HelpBox(
                "场景可视化已启用。\n" +
                "红色线条: UV接缝位置\n" +
                "蓝色连线: 邻接边对\n" +
                "绿色点: UV岛中心",
                MessageType.Info);
            
            if (GUILayout.Button("清除场景绘制"))
            {
                SceneView.RepaintAll();
            }
        }

        #endregion

        #region 功能方法

        private void Generate()
        {
            isProcessing = true;
            
            try
            {
                EditorUtility.DisplayProgressBar("UV邻接图", "正在生成...", 0.3f);
                
                // 烘焙纹理（内部会调用Builder）
                UVAdjacencyMapBaker.BakeSettings settings = new UVAdjacencyMapBaker.BakeSettings
                {
                    resolution = resolution,
                    edgePadding = edgePadding,
                    uvEpsilon = uvEpsilon,
                    uvChannel = uvChannel,
                    useEXRFormat = useEXRFormat,
                    enableDebugLog = enableDebugLog
                };
                
                lastBakeResult = UVAdjacencyMapBaker.Bake(targetMesh, settings);
                lastBuildResult = lastBakeResult.buildResult;
                
                if (lastBakeResult.success)
                {
                    previewTexture = lastBakeResult.adjacencyMap;
                    
                    // 保存纹理
                    if (autoSave)
                    {
                        SaveTexture();
                    }
                    
                    // 输出调试信息
                    HandleDebugOutput();
                    
                    Debug.Log($"[UV邻接图] 生成成功！接缝数: {lastBuildResult.seamCount}, UV岛数: {lastBuildResult.islandCount}");
                }
                else
                {
                    Debug.LogError($"[UV邻接图] 生成失败: {lastBakeResult.errorMessage}");
                }
            }
            finally
            {
                EditorUtility.ClearProgressBar();
                isProcessing = false;
            }
        }

        private void SaveTexture()
        {
            if (lastBakeResult.adjacencyMap == null)
                return;
            
            // 确保目录存在
            string directory = Path.GetDirectoryName(outputPath);
            if (!Directory.Exists(directory))
            {
                Directory.CreateDirectory(directory);
            }
            
            UVAdjacencyMapBaker.SaveTexture(lastBakeResult.adjacencyMap, outputPath, useEXRFormat);
            AssetDatabase.Refresh();
        }

        private void HandleDebugOutput()
        {
            switch (debugMode)
            {
                case DebugMode.LogStatistics:
                    Debug.Log($"[UV邻接图] 统计信息:\n" +
                        $"- 顶点数: {targetMesh.vertexCount}\n" +
                        $"- 三角形数: {targetMesh.triangles.Length / 3}\n" +
                        $"- 总边数: {lastBuildResult.totalEdgeCount}\n" +
                        $"- UV接缝数: {lastBuildResult.seamCount}\n" +
                        $"- UV岛数: {lastBuildResult.islandCount}\n" +
                        $"- 纹理分辨率: {resolution}x{resolution}");
                    break;
                    
                case DebugMode.LogSeamDetails:
                    Debug.Log($"[UV邻接图] 接缝详情:");
                    for (int i = 0; i < lastBuildResult.seams.Count; i++)
                    {
                        var seam = lastBuildResult.seams[i];
                        Debug.Log($"接缝 #{i}:\n" +
                            $"  边A: 三角形{seam.edgeA.triangleIndex}, UV({seam.edgeA.uvA})-({seam.edgeA.uvB})\n" +
                            $"  边B: 三角形{seam.edgeB.triangleIndex}, UV({seam.edgeB.uvA})-({seam.edgeB.uvB})\n" +
                            $"  岛映射: {seam.islandA} ↔ {seam.islandB}");
                    }
                    break;
                    
                case DebugMode.SaveSeamData:
                    SaveSeamDataToJSON();
                    break;
            }
        }

        private void SaveSeamDataToJSON()
        {
            string jsonPath = Path.ChangeExtension(outputPath, ".json");
            
            SeamDataList dataList = new SeamDataList();
            dataList.seams = new SeamDataEntry[lastBuildResult.seams.Count];
            
            for (int i = 0; i < lastBuildResult.seams.Count; i++)
            {
                var seam = lastBuildResult.seams[i];
                dataList.seams[i] = new SeamDataEntry
                {
                    edgeA_uvA = new float[] { seam.edgeA.uvA.x, seam.edgeA.uvA.y },
                    edgeA_uvB = new float[] { seam.edgeA.uvB.x, seam.edgeA.uvB.y },
                    edgeB_uvA = new float[] { seam.edgeB.uvA.x, seam.edgeB.uvA.y },
                    edgeB_uvB = new float[] { seam.edgeB.uvB.x, seam.edgeB.uvB.y },
                    islandA = seam.islandA,
                    islandB = seam.islandB,
                    reversed = seam.reversedMapping
                };
            }
            
            string json = JsonUtility.ToJson(dataList, true);
            File.WriteAllText(jsonPath, json);
            
            Debug.Log($"[UV邻接图] 接缝数据已保存到: {jsonPath}");
        }

        #endregion

        #region 场景可视化

        private void OnEnable()
        {
            SceneView.duringSceneGui += OnSceneGUI;
        }

        private void OnDisable()
        {
            SceneView.duringSceneGui -= OnSceneGUI;
        }

        private void OnSceneGUI(SceneView sceneView)
        {
            if (debugMode != DebugMode.VisualizeInScene || lastBuildResult.seams == null)
                return;
            
            // 需要一个关联的GameObject来获取世界坐标
            // 这里简化处理，只在有选中对象时绘制
            GameObject selectedObj = Selection.activeGameObject;
            if (selectedObj == null)
                return;
            
            MeshFilter meshFilter = selectedObj.GetComponent<MeshFilter>();
            if (meshFilter == null || meshFilter.sharedMesh != targetMesh)
                return;
            
            Transform transform = selectedObj.transform;
            Vector3[] vertices = targetMesh.vertices;
            
            Handles.matrix = transform.localToWorldMatrix;
            
            // 绘制接缝
            foreach (var seam in lastBuildResult.seams)
            {
                int[] triangles = targetMesh.triangles;
                
                // 获取边A的顶点位置
                int vA1 = triangles[seam.edgeA.triangleIndex * 3 + seam.edgeA.localEdgeIndex];
                int vA2 = triangles[seam.edgeA.triangleIndex * 3 + (seam.edgeA.localEdgeIndex + 1) % 3];
                
                // 获取边B的顶点位置
                int vB1 = triangles[seam.edgeB.triangleIndex * 3 + seam.edgeB.localEdgeIndex];
                int vB2 = triangles[seam.edgeB.triangleIndex * 3 + (seam.edgeB.localEdgeIndex + 1) % 3];
                
                Vector3 posA1 = vertices[vA1];
                Vector3 posA2 = vertices[vA2];
                Vector3 posB1 = vertices[vB1];
                Vector3 posB2 = vertices[vB2];
                
                // 绘制边A（红色）
                Handles.color = Color.red;
                Handles.DrawLine(posA1, posA2, 2f);
                
                // 绘制边B（红色）
                Handles.DrawLine(posB1, posB2, 2f);
                
                // 绘制连接线（蓝色）
                Handles.color = Color.blue;
                Handles.DrawLine((posA1 + posA2) * 0.5f, (posB1 + posB2) * 0.5f, 1f);
            }
            
            // 绘制UV岛中心
            if (lastBuildResult.islands != null)
            {
                Handles.color = Color.green;
                foreach (var island in lastBuildResult.islands)
                {
                    Vector3 center = Vector3.zero;
                    HashSet<int> uniqueVertices = new HashSet<int>();
                    
                    foreach (int triIndex in island.triangleIndices)
                    {
                        for (int i = 0; i < 3; i++)
                        {
                            int v = targetMesh.triangles[triIndex * 3 + i];
                            if (uniqueVertices.Add(v))
                            {
                                center += vertices[v];
                            }
                        }
                    }
                    
                    if (uniqueVertices.Count > 0)
                    {
                        center /= uniqueVertices.Count;
                        Handles.SphereHandleCap(0, center, Quaternion.identity, 0.02f, EventType.Repaint);
                    }
                }
            }
            
            Handles.matrix = Matrix4x4.identity;
        }

        #endregion

        #region 辅助类

        [System.Serializable]
        private class SeamDataList
        {
            public SeamDataEntry[] seams;
        }

        [System.Serializable]
        private class SeamDataEntry
        {
            public float[] edgeA_uvA;
            public float[] edgeA_uvB;
            public float[] edgeB_uvA;
            public float[] edgeB_uvB;
            public int islandA;
            public int islandB;
            public bool reversed;
        }

        #endregion
    }
}
