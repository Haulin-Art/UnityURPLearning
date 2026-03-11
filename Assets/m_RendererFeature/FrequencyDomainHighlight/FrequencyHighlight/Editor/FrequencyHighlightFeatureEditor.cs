#if UNITY_EDITOR
using UnityEngine;
using UnityEditor;

namespace FrequencyHighlight
{
    [CustomPropertyDrawer(typeof(FrequencyHighlightFeature.Settings))]
    public class FrequencyHighlightSettingsDrawer : PropertyDrawer
    {
        public override void OnGUI(Rect position, SerializedProperty property, GUIContent label)
        {
            EditorGUI.BeginProperty(position, label, property);
            
            // 绘制默认属性
            EditorGUI.PropertyField(position, property, label, true);
            
            EditorGUI.EndProperty();
        }
        
        public override float GetPropertyHeight(SerializedProperty property, GUIContent label)
        {
            return EditorGUI.GetPropertyHeight(property, label, true);
        }
    }
    
    [CustomEditor(typeof(FrequencyHighlightFeature))]
    public class FrequencyHighlightFeatureEditor : Editor
    {
        public override void OnInspectorGUI()
        {
            // 绘制默认Inspector
            DrawDefaultInspector();
            
            // 获取目标对象
            FrequencyHighlightFeature feature = (FrequencyHighlightFeature)target;
            
            // 添加分隔线
            EditorGUILayout.Space(10);
            EditorGUILayout.LabelField("高光形状频谱图生成", EditorStyles.boldLabel);
            
            // 检查是否设置了必要的资源
            bool canGenerate = feature.settings.highlightShapeSource != null && 
                              feature.settings.fftComputeShader != null;
            
            if (!canGenerate)
            {
                EditorGUILayout.HelpBox("请设置时域高光形状图和FFT Compute Shader", MessageType.Warning);
            }
            
            // 禁用按钮如果条件不满足
            EditorGUI.BeginDisabledGroup(!canGenerate);
            
            // 添加更新按钮
            if (GUILayout.Button("更新高光形状频谱图", GUILayout.Height(30)))
            {
                feature.UpdateHighlightKernel();
                EditorUtility.SetDirty(feature);
            }
            
            EditorGUI.EndDisabledGroup();
            
            // 显示当前状态
            if (feature.settings.highlightKernelFrequencyRT != null)
            {
                EditorGUILayout.Space(5);
                EditorGUILayout.LabelField("当前频谱图信息:", EditorStyles.miniLabel);
                EditorGUILayout.LabelField($"  分辨率: {feature.settings.highlightKernelFrequencyRT.width}x{feature.settings.highlightKernelFrequencyRT.height}", EditorStyles.miniLabel);
                EditorGUILayout.LabelField($"  格式: {feature.settings.highlightKernelFrequencyRT.format}", EditorStyles.miniLabel);
                
                // 显示预览
                if (feature.settings.highlightKernelFrequencyRT != null)
                {
                    EditorGUILayout.Space(5);
                    EditorGUILayout.LabelField("频谱图预览 (幅度谱):", EditorStyles.miniLabel);
                    
                    // 创建预览纹理
                    Texture2D previewTex = GeneratePreviewTexture(feature.settings.highlightKernelFrequencyRT);
                    if (previewTex != null)
                    {
                        GUILayout.Box(previewTex, GUILayout.Width(128), GUILayout.Height(128));
                        DestroyImmediate(previewTex);
                    }
                }
            }
        }
        
        private Texture2D GeneratePreviewTexture(RenderTexture rt)
        {
            if (rt == null) return null;
            
            // 创建临时RenderTexture用于可视化
            RenderTexture tempRT = RenderTexture.GetTemporary(rt.width, rt.height, 0, RenderTextureFormat.ARGBFloat);
            
            // 创建临时Texture2D
            Texture2D tex = new Texture2D(rt.width, rt.height, TextureFormat.RGBAFloat, false);
            
            // 读取RenderTexture数据
            RenderTexture.active = rt;
            tex.ReadPixels(new Rect(0, 0, rt.width, rt.height), 0, 0);
            tex.Apply();
            RenderTexture.active = null;
            
            // 转换为幅度谱可视化
            Color[] pixels = tex.GetPixels();
            for (int i = 0; i < pixels.Length; i++)
            {
                float realPart = pixels[i].r;
                float imagPart = pixels[i].g;
                float magnitude = Mathf.Sqrt(realPart * realPart + imagPart * imagPart);
                float logMagnitude = Mathf.Log(1 + magnitude) / 5f; // 归一化
                pixels[i] = new Color(logMagnitude, logMagnitude, logMagnitude, 1);
            }
            tex.SetPixels(pixels);
            tex.Apply();
            
            RenderTexture.ReleaseTemporary(tempRT);
            
            return tex;
        }
    }
}
#endif
