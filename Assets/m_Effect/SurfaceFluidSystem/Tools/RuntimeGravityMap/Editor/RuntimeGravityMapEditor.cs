using UnityEngine;
using UnityEditor;
using RuntimeGravityMap;

namespace RuntimeGravityMapEditor
{
    /// <summary>
    /// RuntimeGravityMapGenerator的自定义编辑器
    /// </summary>
    [CustomEditor(typeof(RuntimeGravityMapGenerator))]
    public class RuntimeGravityMapEditor : UnityEditor.Editor
    {
        #region 序列化属性

        private SerializedProperty _meshFilterProp;
        private SerializedProperty _skinnedMeshRendererProp;
        private SerializedProperty _useSkinnedMeshProp;
        private SerializedProperty _resolutionProp;
        private SerializedProperty _gravityProp;
        private SerializedProperty _uvChannelProp;
        private SerializedProperty _useExternalRTProp;
        private SerializedProperty _externalGravityMapProp;
        private SerializedProperty _updateModeProp;
        private SerializedProperty _updateIntervalProp;
        private SerializedProperty _indexMethodProp;
        private SerializedProperty _spatialGridSizeProp;
        private SerializedProperty _debugModeProp;
        private SerializedProperty _showDebugInfoProp;
        private SerializedProperty _showDirectionArrowsProp;
        private SerializedProperty _arrowScaleProp;
        private SerializedProperty _computeShaderAssetProp;

        #endregion

        #region 预览相关

        private bool _showPreview = true;
        private int _previewDebugMode = 0;
        private Material _previewMaterial;
        private GUIContent[] _previewModeLabels = new GUIContent[]
        {
            new GUIContent("方向颜色"),
            new GUIContent("XY分量"),
            new GUIContent("强度"),
            new GUIContent("有效区域"),
            new GUIContent("箭头")
        };

        #endregion

        private void OnEnable()
        {
            _meshFilterProp = serializedObject.FindProperty("_meshFilter");
            _skinnedMeshRendererProp = serializedObject.FindProperty("_skinnedMeshRenderer");
            _useSkinnedMeshProp = serializedObject.FindProperty("_useSkinnedMesh");
            _resolutionProp = serializedObject.FindProperty("_resolution");
            _gravityProp = serializedObject.FindProperty("_gravity");
            _uvChannelProp = serializedObject.FindProperty("_uvChannel");
            _useExternalRTProp = serializedObject.FindProperty("_useExternalRT");
            _externalGravityMapProp = serializedObject.FindProperty("_externalGravityMap");
            _updateModeProp = serializedObject.FindProperty("_updateMode");
            _updateIntervalProp = serializedObject.FindProperty("_updateInterval");
            _indexMethodProp = serializedObject.FindProperty("_indexMethod");
            _spatialGridSizeProp = serializedObject.FindProperty("_spatialGridSize");
            _debugModeProp = serializedObject.FindProperty("_debugMode");
            _showDebugInfoProp = serializedObject.FindProperty("_showDebugInfo");
            _showDirectionArrowsProp = serializedObject.FindProperty("_showDirectionArrows");
            _arrowScaleProp = serializedObject.FindProperty("_arrowScale");
            _computeShaderAssetProp = serializedObject.FindProperty("_computeShaderAsset");
        }

        public override void OnInspectorGUI()
        {
            serializedObject.Update();

            RuntimeGravityMapGenerator generator = (RuntimeGravityMapGenerator)target;

            // 标题
            EditorGUILayout.LabelField("运行时重力图生成器", EditorStyles.boldLabel);
            EditorGUILayout.Space(5);

            // Compute Shader设置（必须先设置）
            DrawComputeShaderSection();

            EditorGUILayout.Space(5);

            // 状态信息
            DrawStatusInfo(generator);

            EditorGUILayout.Space(10);

            // 网格源设置
            DrawMeshSourceSection();

            EditorGUILayout.Space(5);

            // 输出设置
            DrawOutputSettingsSection();

            EditorGUILayout.Space(5);

            // 更新设置
            DrawUpdateSettingsSection();

            EditorGUILayout.Space(5);

            // 调试设置
            DrawDebugSettingsSection();

            EditorGUILayout.Space(10);

            // 操作按钮
            DrawActionButtons(generator);

            EditorGUILayout.Space(10);

            // 预览
            if (generator.GravityMap != null)
            {
                DrawPreviewSection(generator);
            }

            serializedObject.ApplyModifiedProperties();
        }

        /// <summary>
        /// 绘制Compute Shader设置
        /// </summary>
        private void DrawComputeShaderSection()
        {
            EditorGUILayout.LabelField("Compute Shader设置", EditorStyles.boldLabel);

            EditorGUI.indentLevel++;

            EditorGUILayout.PropertyField(_computeShaderAssetProp, new GUIContent("Compute Shader"));

            if (_computeShaderAssetProp.objectReferenceValue == null)
            {
                EditorGUILayout.HelpBox("请指定 GravityMapBaker.compute 文件！", MessageType.Error);
            }

            EditorGUI.indentLevel--;
        }

        /// <summary>
        /// 绘制状态信息
        /// </summary>
        private void DrawStatusInfo(RuntimeGravityMapGenerator generator)
        {
            EditorGUILayout.BeginVertical(EditorStyles.helpBox);

            EditorGUILayout.LabelField("状态信息", EditorStyles.boldLabel);

            EditorGUI.indentLevel++;

            // 初始化状态
            EditorGUI.BeginDisabledGroup(true);
            EditorGUILayout.Toggle("已初始化", generator.IsInitialized);
            EditorGUI.EndDisabledGroup();

            // 分辨率
            EditorGUILayout.LabelField("分辨率", $"{generator.Resolution} x {generator.Resolution}");

            // 上次更新耗时
            EditorGUILayout.LabelField("上次更新耗时", $"{generator.LastUpdateTimeMs:F2} ms");

            // 重力图状态
            if (generator.GravityMap != null)
            {
                EditorGUILayout.LabelField("重力图格式", generator.GravityMap.format.ToString());
            }

            EditorGUI.indentLevel--;

            EditorGUILayout.EndVertical();
        }

        /// <summary>
        /// 绘制网格源设置
        /// </summary>
        private void DrawMeshSourceSection()
        {
            EditorGUILayout.LabelField("网格源设置", EditorStyles.boldLabel);

            EditorGUI.indentLevel++;

            EditorGUILayout.PropertyField(_useSkinnedMeshProp, new GUIContent("使用蒙皮网格"));

            if (_useSkinnedMeshProp.boolValue)
            {
                EditorGUILayout.PropertyField(_skinnedMeshRendererProp, new GUIContent("蒙皮网格渲染器"));
            }
            else
            {
                EditorGUILayout.PropertyField(_meshFilterProp, new GUIContent("网格过滤器"));
            }

            EditorGUI.indentLevel--;
        }

        /// <summary>
        /// 绘制输出设置
        /// </summary>
        private void DrawOutputSettingsSection()
        {
            EditorGUILayout.LabelField("输出设置", EditorStyles.boldLabel);

            EditorGUI.indentLevel++;

            // 外部RT选项
            EditorGUILayout.PropertyField(_useExternalRTProp, new GUIContent("使用外部RT"));

            if (_useExternalRTProp.boolValue)
            {
                EditorGUILayout.PropertyField(_externalGravityMapProp, new GUIContent("外部重力图RT"));

                if (_externalGravityMapProp.objectReferenceValue == null)
                {
                    EditorGUILayout.HelpBox("请指定外部RenderTexture！", MessageType.Error);
                }
                else
                {
                    RenderTexture rt = (RenderTexture)_externalGravityMapProp.objectReferenceValue;
                    EditorGUILayout.LabelField("RT分辨率", $"{rt.width} x {rt.height}");
                    EditorGUILayout.LabelField("RT格式", rt.format.ToString());

                    if (!rt.enableRandomWrite)
                    {
                        EditorGUILayout.HelpBox("外部RT需要启用 'Enable Random Write'！", MessageType.Warning);
                    }
                }
            }
            else
            {
                EditorGUILayout.PropertyField(_resolutionProp, new GUIContent("分辨率"));
                _resolutionProp.intValue = Mathf.ClosestPowerOfTwo(Mathf.Clamp(_resolutionProp.intValue, 64, 2048));
            }

            EditorGUILayout.PropertyField(_gravityProp, new GUIContent("重力方向"));

            if (GUILayout.Button("重置为Y轴负方向", GUILayout.Width(150)))
            {
                _gravityProp.vector3Value = Vector3.down;
            }

            EditorGUILayout.PropertyField(_uvChannelProp, new GUIContent("UV通道"));

            EditorGUI.indentLevel--;
        }

        /// <summary>
        /// 绘制更新设置
        /// </summary>
        private void DrawUpdateSettingsSection()
        {
            EditorGUILayout.LabelField("更新设置", EditorStyles.boldLabel);

            EditorGUI.indentLevel++;

            EditorGUILayout.PropertyField(_updateModeProp, new GUIContent("更新模式"));

            // 显示更新模式说明
            string updateDesc = GetUpdateModeDescription((UpdateMode)_updateModeProp.enumValueIndex);
            EditorGUILayout.HelpBox(updateDesc, MessageType.Info);

            if (_updateModeProp.enumValueIndex == (int)UpdateMode.Interval)
            {
                EditorGUILayout.PropertyField(_updateIntervalProp, new GUIContent("更新间隔(秒)"));
            }

            EditorGUILayout.PropertyField(_indexMethodProp, new GUIContent("索引方法"));

            if (_indexMethodProp.enumValueIndex == (int)SpatialIndexMethod.SpatialGrid)
            {
                EditorGUILayout.PropertyField(_spatialGridSizeProp, new GUIContent("空间网格大小"));
                EditorGUILayout.HelpBox("空间网格索引适合高面数网格，可大幅提升性能。\n" +
                    "网格大小建议：\n" +
                    "- 低面数(<1K)：16\n" +
                    "- 中面数(1K-10K)：32\n" +
                    "- 高面数(>10K)：64", MessageType.Info);
            }
            else
            {
                EditorGUILayout.HelpBox("暴力遍历适合低面数网格(<1000三角形)，实现简单但性能较低。", MessageType.Info);
            }

            EditorGUI.indentLevel--;
        }

        /// <summary>
        /// 绘制调试设置
        /// </summary>
        private void DrawDebugSettingsSection()
        {
            EditorGUILayout.LabelField("调试设置", EditorStyles.boldLabel);

            EditorGUI.indentLevel++;

            EditorGUILayout.PropertyField(_debugModeProp, new GUIContent("调试模式"));

            // 显示调试模式说明
            string debugDesc = GetDebugModeDescription((DebugMode)_debugModeProp.enumValueIndex);
            EditorGUILayout.HelpBox(debugDesc, MessageType.Info);

            EditorGUILayout.PropertyField(_showDebugInfoProp, new GUIContent("显示调试信息"));
            EditorGUILayout.PropertyField(_showDirectionArrowsProp, new GUIContent("显示方向箭头"));

            if (_showDirectionArrowsProp.boolValue)
            {
                EditorGUILayout.PropertyField(_arrowScaleProp, new GUIContent("箭头大小"));
            }

            EditorGUI.indentLevel--;
        }

        /// <summary>
        /// 获取更新模式说明
        /// </summary>
        private string GetUpdateModeDescription(UpdateMode mode)
        {
            switch (mode)
            {
                case UpdateMode.Manual:
                    return "手动更新：需要调用 UpdateGravityMap() 或点击按钮更新";
                case UpdateMode.EveryFrame:
                    return "每帧更新：适合蒙皮网格或持续变形的网格\n注意：性能开销较大";
                case UpdateMode.Interval:
                    return "定时更新：按指定间隔更新\n适合需要定期更新但不需要每帧更新的场景";
                case UpdateMode.OnTransformChange:
                    return "变换改变时更新：当位置/旋转/缩放任一变化时更新";
                case UpdateMode.OnRotationChange:
                    return "仅旋转改变时更新：（推荐）\n当物体旋转时自动更新重力图\n适合静态网格，性能开销最小";
                default:
                    return "";
            }
        }

        /// <summary>
        /// 获取调试模式说明
        /// </summary>
        private string GetDebugModeDescription(DebugMode mode)
        {
            switch (mode)
            {
                case DebugMode.None:
                    return "正常输出：xy = 流动方向，z = 强度，w = 有效标记";
                case DebugMode.OutputUV:
                    return "输出UV坐标：R = U坐标，G = V坐标";
                case DebugMode.OutputTriangleIndex:
                    return "输出三角形索引：灰度值表示三角形索引";
                case DebugMode.OutputNormal:
                    return "输出插值法线：RGB = 法线方向映射到颜色";
                case DebugMode.OutputTangent:
                    return "输出插值切线：RGB = 切线方向映射到颜色";
                case DebugMode.OutputRawGravity:
                    return "输出原始重力方向：切线空间重力分量";
                case DebugMode.OutputIntensity:
                    return "输出流动强度：灰度值表示强度";
                default:
                    return "";
            }
        }

        /// <summary>
        /// 绘制操作按钮
        /// </summary>
        private void DrawActionButtons(RuntimeGravityMapGenerator generator)
        {
            EditorGUILayout.BeginHorizontal();

            GUILayout.FlexibleSpace();

            if (GUILayout.Button("立即更新", GUILayout.Width(100), GUILayout.Height(30)))
            {
                generator.UpdateGravityMap();
                Debug.Log("[RuntimeGravityMap] 手动更新完成");
            }

            GUILayout.Space(10);

            if (GUILayout.Button("重新初始化", GUILayout.Width(100), GUILayout.Height(30)))
            {
                generator.Initialize();
                Debug.Log("[RuntimeGravityMap] 重新初始化完成");
            }

            GUILayout.FlexibleSpace();

            EditorGUILayout.EndHorizontal();
        }

        /// <summary>
        /// 绘制预览区域
        /// </summary>
        private void DrawPreviewSection(RuntimeGravityMapGenerator generator)
        {
            _showPreview = EditorGUILayout.Foldout(_showPreview, "重力图预览", true);

            if (!_showPreview) return;

            EditorGUI.indentLevel++;

            // 预览模式选择
            _previewDebugMode = GUILayout.Toolbar(_previewDebugMode, _previewModeLabels);

            EditorGUILayout.Space(5);

            // 绘制预览纹理
            Rect previewRect = GUILayoutUtility.GetRect(256, 256, GUILayout.ExpandWidth(true));

            if (generator.GravityMap != null)
            {
                // 创建预览材质
                if (_previewMaterial == null)
                {
                    Shader shader = Shader.Find("Hidden/RuntimeGravityMap/DebugView");
                    if (shader != null)
                    {
                        _previewMaterial = new Material(shader);
                    }
                }

                if (_previewMaterial != null)
                {
                    _previewMaterial.SetFloat("_DebugMode", _previewDebugMode);
                    _previewMaterial.SetTexture("_GravityMap", generator.GravityMap);

                    // 绘制预览
                    EditorGUI.DrawPreviewTexture(previewRect, generator.GravityMap, _previewMaterial, ScaleMode.ScaleToFit, 0);
                }
            }

            // 颜色说明
            EditorGUILayout.Space(5);

            string colorDesc = GetColorDescription(_previewDebugMode);
            EditorGUILayout.HelpBox(colorDesc, MessageType.Info);

            EditorGUI.indentLevel--;
        }

        /// <summary>
        /// 获取颜色说明
        /// </summary>
        private string GetColorDescription(int mode)
        {
            switch (mode)
            {
                case 0:
                    return "方向颜色模式：\n" +
                           "- 颜色表示流动方向（HSV色轮编码）\n" +
                           "- 亮度表示流动强度";
                case 1:
                    return "XY分量模式：\n" +
                           "- R通道：流动方向X分量 [-1,1] -> [0,1]\n" +
                           "- G通道：流动方向Y分量 [-1,1] -> [0,1]";
                case 2:
                    return "强度模式：\n" +
                           "- 灰度值表示流动强度\n" +
                           "- 白色 = 强流动，黑色 = 无流动";
                case 3:
                    return "有效区域模式：\n" +
                           "- 白色 = 有效UV区域\n" +
                           "- 黑色 = 无效区域";
                case 4:
                    return "箭头模式：\n" +
                           "- 箭头指向流动方向\n" +
                           "- 背景颜色表示方向";
                default:
                    return "";
            }
        }
    }
}
