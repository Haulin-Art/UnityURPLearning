using UnityEngine;
using UnityEditor;
using TangentSpaceGravityMap;

namespace TangentSpaceGravityMap.Editor
{
    /// <summary>
    /// 切线空间重力图生成工具窗口
    /// </summary>
    public class TangentSpaceGravityMapWindow : EditorWindow
    {
        #region 菜单项

        [MenuItem("Tools/切线空间重力图生成工具")]
        public static void ShowWindow()
        {
            var window = GetWindow<TangentSpaceGravityMapWindow>("切线空间重力图生成工具");
            window.minSize = new Vector2(400, 500);
            window.Show();
        }

        #endregion

        #region 序列化字段

        // 目标网格
        [SerializeField] private Mesh targetMesh;
        
        // 烘焙参数
        [SerializeField] private int resolution = 256;
        [SerializeField] private int uvChannel = 0;
        [SerializeField] private bool useEXRFormat = true;
        [SerializeField] private Vector3 customGravity = Vector3.down;
        
        // 输出格式选项
        [SerializeField] private bool normalizeTo01 = false;     // 是否映射到[0,1]
        [SerializeField] private bool compressToRG = false;      // 是否压缩到RG通道
        
        // 调试选项
        [SerializeField] private DebugMode debugMode = DebugMode.None;
        
        // 输出路径
        [SerializeField] private string outputPath = "Assets/GravityMap.exr";

        // 预览
        [SerializeField] private Texture2D previewTexture;
        [SerializeField] private bool showPreview = true;
        [SerializeField] private Vector2 previewScrollPosition;

        // 烘焙结果
        private BakeResult lastBakeResult;
        private bool hasBaked = false;

        #endregion

        #region GUI

        private void OnGUI()
        {
            EditorGUILayout.Space(10);

            // 标题
            EditorGUILayout.LabelField("切线空间重力图生成工具", EditorStyles.boldLabel);
            EditorGUILayout.Space(10);

            // 目标网格选择
            DrawMeshSelection();
            
            EditorGUILayout.Space(10);

            // 烘焙参数
            DrawBakeSettings();
            
            EditorGUILayout.Space(10);

            // 调试选项
            DrawDebugOptions();
            
            EditorGUILayout.Space(10);

            // 输出设置
            DrawOutputSettings();
            
            EditorGUILayout.Space(10);

            // 生成按钮
            DrawGenerateButton();
            
            EditorGUILayout.Space(10);

            // 结果显示
            DrawResultInfo();
            
            EditorGUILayout.Space(10);

            // 预览
            if (showPreview && previewTexture != null)
            {
                DrawPreview();
            }
        }

        /// <summary>
        /// 绘制网格选择区域
        /// </summary>
        private void DrawMeshSelection()
        {
            EditorGUILayout.LabelField("目标网格", EditorStyles.boldLabel);
            
            EditorGUI.BeginChangeCheck();
            targetMesh = (Mesh)EditorGUILayout.ObjectField("网格", targetMesh, typeof(Mesh), false);
            if (EditorGUI.EndChangeCheck())
            {
                // 网格改变时清除预览
                previewTexture = null;
                hasBaked = false;
            }

            // 显示网格信息
            if (targetMesh != null)
            {
                EditorGUI.indentLevel++;
                EditorGUILayout.LabelField($"顶点数: {targetMesh.vertexCount}");
                EditorGUILayout.LabelField($"三角形数: {targetMesh.triangles.Length / 3}");
                EditorGUILayout.LabelField($"有法线: {targetMesh.normals != null && targetMesh.normals.Length > 0}");
                EditorGUILayout.LabelField($"有切线: {targetMesh.tangents != null && targetMesh.tangents.Length > 0}");
                EditorGUILayout.LabelField($"有UV0: {targetMesh.uv != null && targetMesh.uv.Length > 0}");
                EditorGUI.indentLevel--;
            }
            else
            {
                EditorGUILayout.HelpBox("请选择一个网格资产", MessageType.Info);
            }
        }

        /// <summary>
        /// 绘制烘焙参数设置
        /// </summary>
        private void DrawBakeSettings()
        {
            EditorGUILayout.LabelField("烘焙参数", EditorStyles.boldLabel);
            
            EditorGUI.indentLevel++;
            
            resolution = EditorGUILayout.IntPopup("分辨率", resolution, 
                new string[] { "128", "256", "512", "1024", "2048" },
                new int[] { 128, 256, 512, 1024, 2048 });
            
            uvChannel = EditorGUILayout.IntPopup("UV通道", uvChannel,
                new string[] { "UV0", "UV1", "UV2", "UV3" },
                new int[] { 0, 1, 2, 3 });
            
            useEXRFormat = EditorGUILayout.Toggle("使用EXR格式", useEXRFormat);
            
            customGravity = EditorGUILayout.Vector3Field("重力方向", customGravity);
            if (GUILayout.Button("重置为Y轴负方向"))
            {
                customGravity = Vector3.down;
            }
            
            EditorGUILayout.Space(5);
            
            // 输出格式选项
            EditorGUILayout.LabelField("输出格式", EditorStyles.boldLabel);
            
            compressToRG = EditorGUILayout.Toggle("压缩到RG通道", compressToRG);
            if (compressToRG)
            {
                EditorGUILayout.HelpBox("只输出XY分量（切线和副切线方向）\n适用于2D流体模拟", MessageType.Info);
            }
            else
            {
                EditorGUILayout.HelpBox("输出XYZ三分量（完整切线空间方向）\nRGB = 切线/副切线/法线方向分量", MessageType.Info);
            }
            
            normalizeTo01 = EditorGUILayout.Toggle("映射到[0,1]", normalizeTo01);
            if (normalizeTo01)
            {
                EditorGUILayout.HelpBox("将[-1,1]映射到[0,1]\n适用于不支持负值的纹理格式", MessageType.Info);
            }
            else
            {
                EditorGUILayout.HelpBox("保留原始值[-1,1]\n推荐使用EXR格式", MessageType.Info);
            }
            
            EditorGUI.indentLevel--;
        }

        /// <summary>
        /// 绘制调试选项
        /// </summary>
        private void DrawDebugOptions()
        {
            EditorGUILayout.LabelField("调试选项", EditorStyles.boldLabel);
            
            EditorGUI.indentLevel++;
            
            debugMode = (DebugMode)EditorGUILayout.EnumPopup("调试模式", debugMode);
            
            showPreview = EditorGUILayout.Toggle("显示预览", showPreview);
            
            EditorGUI.indentLevel--;
        }

        /// <summary>
        /// 绘制输出设置
        /// </summary>
        private void DrawOutputSettings()
        {
            EditorGUILayout.LabelField("输出设置", EditorStyles.boldLabel);
            
            EditorGUI.indentLevel++;
            
            // 输出路径
            EditorGUILayout.BeginHorizontal();
            EditorGUILayout.LabelField("输出路径", GUILayout.Width(80));
            outputPath = EditorGUILayout.TextField(outputPath);
            if (GUILayout.Button("浏览", GUILayout.Width(50)))
            {
                string extension = useEXRFormat ? "exr" : "png";
                string path = EditorUtility.SaveFilePanel("保存重力图", "Assets", "GravityMap", extension);
                if (!string.IsNullOrEmpty(path))
                {
                    // 转换为相对路径
                    if (path.StartsWith(Application.dataPath))
                    {
                        path = "Assets" + path.Substring(Application.dataPath.Length);
                    }
                    outputPath = path;
                }
            }
            EditorGUILayout.EndHorizontal();
            
            // 自动设置扩展名
            if (!string.IsNullOrEmpty(outputPath))
            {
                string expectedExtension = useEXRFormat ? ".exr" : ".png";
                if (!outputPath.EndsWith(expectedExtension, System.StringComparison.OrdinalIgnoreCase))
                {
                    string directory = System.IO.Path.GetDirectoryName(outputPath);
                    string fileName = System.IO.Path.GetFileNameWithoutExtension(outputPath);
                    outputPath = System.IO.Path.Combine(directory, fileName + expectedExtension);
                }
            }
            
            EditorGUI.indentLevel--;
        }

        /// <summary>
        /// 绘制生成按钮
        /// </summary>
        private void DrawGenerateButton()
        {
            EditorGUI.BeginDisabledGroup(targetMesh == null);
            
            EditorGUILayout.BeginHorizontal();
            GUILayout.FlexibleSpace();
            
            if (GUILayout.Button("生成重力图", GUILayout.Width(150), GUILayout.Height(30)))
            {
                Generate();
            }
            
            GUILayout.FlexibleSpace();
            EditorGUILayout.EndHorizontal();
            
            EditorGUI.EndDisabledGroup();
        }

        /// <summary>
        /// 绘制结果信息
        /// </summary>
        private void DrawResultInfo()
        {
            if (!hasBaked) return;

            EditorGUILayout.LabelField("烘焙结果", EditorStyles.boldLabel);
            
            EditorGUI.indentLevel++;
            
            if (lastBakeResult.success)
            {
                EditorGUILayout.HelpBox("烘焙成功！", MessageType.Info);
                
                float coverage = (float)lastBakeResult.validPixelCount / lastBakeResult.totalPixelCount * 100f;
                EditorGUILayout.LabelField($"有效像素: {lastBakeResult.validPixelCount} / {lastBakeResult.totalPixelCount}");
                EditorGUILayout.LabelField($"覆盖率: {coverage:F1}%");
            }
            else
            {
                EditorGUILayout.HelpBox($"烘焙失败: {lastBakeResult.errorMessage}", MessageType.Error);
            }
            
            EditorGUI.indentLevel--;
        }

        /// <summary>
        /// 绘制预览区域
        /// </summary>
        private void DrawPreview()
        {
            EditorGUILayout.LabelField("预览", EditorStyles.boldLabel);
            
            float previewSize = Mathf.Min(position.width - 40, 256);
            
            previewScrollPosition = EditorGUILayout.BeginScrollView(previewScrollPosition, GUILayout.Height(previewSize + 20));
            
            EditorGUILayout.BeginHorizontal();
            GUILayout.FlexibleSpace();
            
            // 显示预览纹理
            Rect previewRect = GUILayoutUtility.GetRect(previewSize, previewSize, GUILayout.Width(previewSize), GUILayout.Height(previewSize));
            EditorGUI.DrawPreviewTexture(previewRect, previewTexture, null, ScaleMode.ScaleToFit, 0);
            
            GUILayout.FlexibleSpace();
            EditorGUILayout.EndHorizontal();
            
            // 颜色说明
            string formatDesc = compressToRG 
                ? "R通道: 重力在切线方向(X)分量\nG通道: 重力在副切线方向(Y)分量"
                : "R通道: 重力在切线方向(X)分量\nG通道: 重力在副切线方向(Y)分量\nB通道: 重力在法线方向(Z)分量";
            formatDesc += "\nA通道: 有效区域遮罩";
            EditorGUILayout.HelpBox(formatDesc, MessageType.Info);
            
            EditorGUILayout.EndScrollView();
        }

        #endregion

        #region 生成逻辑

        /// <summary>
        /// 生成重力图
        /// </summary>
        private void Generate()
        {
            if (targetMesh == null)
            {
                EditorUtility.DisplayDialog("错误", "请先选择目标网格！", "确定");
                return;
            }

            // 验证网格数据
            if (targetMesh.normals == null || targetMesh.normals.Length == 0)
            {
                EditorUtility.DisplayDialog("错误", "网格没有法线数据！请确保网格有法线。", "确定");
                return;
            }

            if (targetMesh.tangents == null || targetMesh.tangents.Length == 0)
            {
                EditorUtility.DisplayDialog("错误", "网格没有切线数据！请确保网格有切线。\n\n可以在导入设置中勾选'Tangents'或使用脚本计算。", "确定");
                return;
            }

            // 构建烘焙设置
            BakeSettings settings = new BakeSettings
            {
                resolution = resolution,
                uvChannel = uvChannel,
                useEXRFormat = useEXRFormat,
                enableDebugLog = debugMode != DebugMode.None,
                customGravity = customGravity.normalized,
                normalizeTo01 = normalizeTo01,
                compressToRG = compressToRG
            };

            // 显示进度
            EditorUtility.DisplayProgressBar("切线空间重力图", "正在烘焙...", 0.5f);

            try
            {
                // 执行烘焙
                lastBakeResult = TangentSpaceGravityMapBaker.Bake(targetMesh, settings);
                hasBaked = true;

                if (lastBakeResult.success)
                {
                    // 更新预览
                    previewTexture = lastBakeResult.gravityMap;

                    // 自动保存
                    if (!string.IsNullOrEmpty(outputPath))
                    {
                        if (TangentSpaceGravityMapBaker.SaveTexture(lastBakeResult.gravityMap, outputPath, useEXRFormat))
                        {
                            AssetDatabase.Refresh();
                            Debug.Log($"[切线空间重力图] 已保存到: {outputPath}");
                        }
                    }

                    // 验证转换正确性
                    if (debugMode == DebugMode.ValidateConversion)
                    {
                        ValidateConversion(lastBakeResult.gravityMap, settings);
                    }
                }
                else
                {
                    EditorUtility.DisplayDialog("烘焙失败", lastBakeResult.errorMessage, "确定");
                }
            }
            finally
            {
                EditorUtility.ClearProgressBar();
            }
        }

        /// <summary>
        /// 验证转换正确性
        /// </summary>
        private void ValidateConversion(Texture2D gravityMap, BakeSettings settings)
        {
            // 随机采样几个点验证
            int sampleCount = 5;
            Debug.Log($"[切线空间重力图] 开始验证 {sampleCount} 个采样点...");

            for (int i = 0; i < sampleCount; i++)
            {
                int x = Random.Range(0, settings.resolution);
                int y = Random.Range(0, settings.resolution);
                Color pixel = gravityMap.GetPixel(x, y);

                if (pixel.a > 0.5f)
                {
                    // 还原切线空间重力
                    Vector3 tangentGravity;
                    if (settings.normalizeTo01)
                    {
                        tangentGravity = new Vector3(
                            pixel.r * 2f - 1f,
                            pixel.g * 2f - 1f,
                            settings.compressToRG ? 0 : pixel.b * 2f - 1f
                        );
                    }
                    else
                    {
                        tangentGravity = new Vector3(
                            pixel.r,
                            pixel.g,
                            settings.compressToRG ? 0 : pixel.b
                        );
                    }
                    
                    float magnitude = tangentGravity.magnitude;

                    Debug.Log($"验证点 {i + 1}: UV=({(float)x / settings.resolution:F2}, {(float)y / settings.resolution:F2}), " +
                              $"切线空间重力=({tangentGravity.x:F3}, {tangentGravity.y:F3}, {tangentGravity.z:F3}), 强度={magnitude:F3}");
                }
            }
        }

        #endregion
    }
}
