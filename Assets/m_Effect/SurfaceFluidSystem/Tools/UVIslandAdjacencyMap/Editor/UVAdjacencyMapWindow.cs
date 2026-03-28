using UnityEngine;
using UnityEditor;
using System.Collections.Generic;

namespace UVAdjacencyMap
{
    /// <summary>
    /// UV邻接图生成工具编辑器窗口
    /// 支持PNG、EXR、RenderTexture三种输出格式
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
        [SerializeField] private UVAdjacencyMapBaker.OutputFormat outputFormat = UVAdjacencyMapBaker.OutputFormat.RT;
        [SerializeField] private string outputPath = "Assets/UVAdjacencyMap.png";

        [Header("调试设置")]
        [SerializeField] private DebugMode debugMode = DebugMode.None;
        [SerializeField] private bool showPreview = true;
        [SerializeField] private bool enableDebugLog = false;

        #endregion

        #region 私有字段

        private Texture2D previewTexture;
        private RenderTexture previewRT;
        private UVAdjacencyMapBuilder.BuildResult lastBuildResult;
        private UVAdjacencyMapBaker.BakeResult lastBakeResult;
        private Vector2 scrollPosition;
        private bool isProcessing = false;

        #endregion

        #region 枚举

        public enum DebugMode
        {
            None,
            LogStatistics,
            LogSeamDetails,
            VisualizeInScene
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
            
            if (showPreview && (previewTexture != null || previewRT != null))
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
                "根据网格的UV拓扑生成邻接纹理，用于跨UV岛的无缝流动效果。\n" +
                "输出格式: R=邻接UV.x, G=邻接UV.y, B=邻接边缘遮罩, A=UV岛范围遮罩。\n" +
                "需要注意，如果选择的输出类型为EXR，需要关闭压缩，不然会无法正确显示a通道，如果是rt，需要注意更改后与重新加载都可能清空，每次生成最好先删除原rt，再重新生成",
                MessageType.Info);
            
            EditorGUILayout.Space(10);
        }

        private void DrawMeshSelection()
        {
            EditorGUILayout.LabelField("目标网格", EditorStyles.boldLabel);
            
            targetMesh = (Mesh)EditorGUILayout.ObjectField("网格", targetMesh, typeof(Mesh), false);
            
            if (targetMesh != null)
            {
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
            
            outputFormat = (UVAdjacencyMapBaker.OutputFormat)EditorGUILayout.EnumPopup("输出格式", outputFormat);
            
            // 根据格式显示不同说明
            switch (outputFormat)
            {
                case UVAdjacencyMapBaker.OutputFormat.PNG:
                    EditorGUILayout.HelpBox("PNG格式: 8位精度，兼容性好，适合预览", MessageType.Info);
                    break;
                case UVAdjacencyMapBaker.OutputFormat.EXR:
                    EditorGUILayout.HelpBox("EXR格式: 32位浮点精度，适合流体模拟", MessageType.Info);
                    break;
                case UVAdjacencyMapBaker.OutputFormat.RT:
                    EditorGUILayout.HelpBox("RenderTexture: 运行时使用，高精度，无需保存文件", MessageType.Info);
                    break;
            }
            
            // 只有PNG和EXR需要保存路径
            if (outputFormat != UVAdjacencyMapBaker.OutputFormat.RT)
            {
                // 自动更新扩展名
                string ext = outputFormat == UVAdjacencyMapBaker.OutputFormat.EXR ? ".exr" : ".png";
                if (!outputPath.EndsWith(ext, System.StringComparison.OrdinalIgnoreCase))
                {
                    outputPath = System.IO.Path.ChangeExtension(outputPath, ext);
                }
                
                EditorGUILayout.BeginHorizontal();
                EditorGUILayout.PrefixLabel("输出路径");
                outputPath = EditorGUILayout.TextField(outputPath);
                if (GUILayout.Button("...", GUILayout.Width(30)))
                {
                    string path = EditorUtility.SaveFilePanel("保存邻接纹理", 
                        System.IO.Path.GetDirectoryName(outputPath), 
                        System.IO.Path.GetFileNameWithoutExtension(outputPath), 
                        ext.TrimStart('.'));
                    if (!string.IsNullOrEmpty(path))
                    {
                        outputPath = "Assets" + path.Substring(Application.dataPath.Length);
                    }
                }
                EditorGUILayout.EndHorizontal();
            }
            
            EditorGUILayout.Space(10);
        }

        private void DrawDebugSettings()
        {
            EditorGUILayout.LabelField("调试设置", EditorStyles.boldLabel);
            
            debugMode = (DebugMode)EditorGUILayout.EnumPopup("调试模式", debugMode);
            showPreview = EditorGUILayout.Toggle("显示预览", showPreview);
            enableDebugLog = EditorGUILayout.Toggle("详细日志", enableDebugLog);
            
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
            
            EditorGUI.DrawRect(previewRect, new Color(0.2f, 0.2f, 0.2f, 1f));
            
            // RT格式优先显示RenderTexture，其他格式显示Texture2D
            Texture displayTex = null;
            if (outputFormat == UVAdjacencyMapBaker.OutputFormat.RT && previewRT != null)
            {
                displayTex = previewRT;
            }
            else if (previewTexture != null)
            {
                displayTex = previewTexture;
            }
            
            if (displayTex != null)
            {
                GUI.DrawTexture(previewRect, displayTex, ScaleMode.ScaleToFit);
            }
            
            // 显示当前预览的纹理信息
            string previewInfo = "";
            if (outputFormat == UVAdjacencyMapBaker.OutputFormat.RT && previewRT != null)
            {
                previewInfo = $"RenderTexture: {previewRT.width}x{previewRT.height}, 格式: {previewRT.format}";
            }
            else if (previewTexture != null)
            {
                previewInfo = $"Texture2D: {previewTexture.width}x{previewTexture.height}, 格式: {previewTexture.format}";
            }
            
            if (!string.IsNullOrEmpty(previewInfo))
            {
                EditorGUILayout.HelpBox(previewInfo, MessageType.None);
            }
            
            EditorGUILayout.HelpBox(
                "R/G通道: 邻接UV坐标\n" +
                "B通道: 邻接边缘遮罩\n" +
                "A通道: UV岛范围遮罩",
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
                EditorGUILayout.LabelField($"输出格式: {outputFormat}");
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
                
                UVAdjacencyMapBaker.BakeSettings settings = new UVAdjacencyMapBaker.BakeSettings
                {
                    resolution = resolution,
                    edgePadding = edgePadding,
                    uvEpsilon = uvEpsilon,
                    uvChannel = uvChannel,
                    enableDebugLog = enableDebugLog,
                    outputFormat = outputFormat
                };
                
                lastBakeResult = UVAdjacencyMapBaker.Bake(targetMesh, settings);
                lastBuildResult = lastBakeResult.buildResult;
                
                if (lastBakeResult.success)
                {
                    // 更新预览
                    previewTexture = lastBakeResult.texture2D;
                    previewRT = lastBakeResult.renderTexture;
                    
                    // 保存文件（PNG/EXR格式）
                    if (outputFormat != UVAdjacencyMapBaker.OutputFormat.RT)
                    {
                        SaveTexture();
                    }
                    
                    HandleDebugOutput();
                    
                    Debug.Log($"[UV邻接图] 生成成功！格式: {outputFormat}, 接缝数: {lastBuildResult.seamCount}, UV岛数: {lastBuildResult.islandCount}");
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
            if (lastBakeResult.texture2D == null)
                return;
            
            // 确保目录存在
            string directory = System.IO.Path.GetDirectoryName(outputPath);
            if (!string.IsNullOrEmpty(directory) && !System.IO.Directory.Exists(directory))
            {
                System.IO.Directory.CreateDirectory(directory);
            }
            
            UVAdjacencyMapBaker.SaveTexture(lastBakeResult.texture2D, outputPath, outputFormat);
            AssetDatabase.Refresh();
            
            // 修复导入设置
            FixImportSettings();
        }

        private void FixImportSettings()
        {
            TextureImporter importer = AssetImporter.GetAtPath(outputPath) as TextureImporter;
            if (importer == null)
                return;
            
            bool needsReimport = false;
            
            if (importer.alphaSource != TextureImporterAlphaSource.FromInput)
            {
                importer.alphaSource = TextureImporterAlphaSource.FromInput;
                needsReimport = true;
            }
            
            if (!importer.alphaIsTransparency)
            {
                importer.alphaIsTransparency = true;
                needsReimport = true;
            }
            
            if (outputFormat == UVAdjacencyMapBaker.OutputFormat.EXR && importer.sRGBTexture)
            {
                importer.sRGBTexture = false;
                needsReimport = true;
            }
            
            if (needsReimport)
            {
                importer.SaveAndReimport();
                Debug.Log($"[UV邻接图] 已修复导入设置");
            }
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
                        $"- 纹理分辨率: {resolution}x{resolution}\n" +
                        $"- 输出格式: {outputFormat}");
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
            }
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
            
            GameObject selectedObj = Selection.activeGameObject;
            if (selectedObj == null)
                return;
            
            MeshFilter meshFilter = selectedObj.GetComponent<MeshFilter>();
            if (meshFilter == null || meshFilter.sharedMesh != targetMesh)
                return;
            
            Transform transform = selectedObj.transform;
            Vector3[] vertices = targetMesh.vertices;
            
            Handles.matrix = transform.localToWorldMatrix;
            
            foreach (var seam in lastBuildResult.seams)
            {
                int[] triangles = targetMesh.triangles;
                
                int vA1 = triangles[seam.edgeA.triangleIndex * 3 + seam.edgeA.localEdgeIndex];
                int vA2 = triangles[seam.edgeA.triangleIndex * 3 + (seam.edgeA.localEdgeIndex + 1) % 3];
                
                int vB1 = triangles[seam.edgeB.triangleIndex * 3 + seam.edgeB.localEdgeIndex];
                int vB2 = triangles[seam.edgeB.triangleIndex * 3 + (seam.edgeB.localEdgeIndex + 1) % 3];
                
                Vector3 posA1 = vertices[vA1];
                Vector3 posA2 = vertices[vA2];
                Vector3 posB1 = vertices[vB1];
                Vector3 posB2 = vertices[vB2];
                
                Handles.color = Color.red;
                Handles.DrawLine(posA1, posA2, 2f);
                Handles.DrawLine(posB1, posB2, 2f);
                
                Handles.color = Color.blue;
                Handles.DrawLine((posA1 + posA2) * 0.5f, (posB1 + posB2) * 0.5f, 1f);
            }
            
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
    }
}
