using UnityEngine;
using UnityEditor;
using System.Collections.Generic;

namespace MieScattering.Tools
{
    public class Voronoi3DGenerator : EditorWindow
    {
        #region 参数定义
        private int resolution = 64;
        private float cellSize = 0.1f;
        private float distanceFalloff = 1.0f;
        private int randomSeed = 1234;
        private int numCells = 20;
        
        private enum VoronoiMode
        {
            CellEdge,
            CellDistance,
            CellID,
            WorleyNoise
        }
        private VoronoiMode voronoiMode = VoronoiMode.CellEdge;
        
        private enum DebugMode
        {
            None,
            ShowSlice,
            ShowMinDistance,
            ShowSecondDistance,
            ShowOctave0,
            ShowOctave1,
            ShowOctave2,
            ShowOctave3
        }
        private DebugMode debugMode = DebugMode.ShowSlice;
        
        private int previewSlice = 32;
        private bool useTiling = false;
        private float contrast = 1.0f;
        private float brightness = 0.0f;
        
        private bool useFractal = false;
        private int fractalOctaves = 4;
        private float fractalLacunarity = 2.0f;
        private float fractalGain = 0.5f;
        private float fractalBaseFrequency = 1.0f;
        
        private enum FractalBlendMode
        {
            Add,
            Multiply,
            Max,
            Min,
            AbsAdd
        }
        private FractalBlendMode fractalBlendMode = FractalBlendMode.Add;
        #endregion

        #region 预览相关
        private Texture3D previewTexture;
        private Texture2D slicePreview;
        private Material previewMaterial;
        private Vector2 previewScrollPosition;
        private float[] octaveValues;
        #endregion

        [MenuItem("MieScattering/Voronoi 3D生成器")]
        public static void ShowWindow()
        {
            var window = GetWindow<Voronoi3DGenerator>("Voronoi 3D生成器");
            window.minSize = new Vector2(400, 750);
        }

        private void OnGUI()
        {
            previewScrollPosition = EditorGUILayout.BeginScrollView(previewScrollPosition);
            
            DrawHeader();
            EditorGUILayout.Space();
            DrawParameters();
            EditorGUILayout.Space();
            DrawFractalOptions();
            EditorGUILayout.Space();
            DrawDebugOptions();
            EditorGUILayout.Space();
            DrawActionButtons();
            EditorGUILayout.Space();
            DrawPreview();
            
            EditorGUILayout.EndScrollView();
        }

        private void DrawHeader()
        {
            GUILayout.Label("Voronoi 3D纹理生成器", EditorStyles.boldLabel);
            EditorGUILayout.HelpBox("生成可导出的Voronoi 3D噪波纹理，支持多种模式和分形迭代。", MessageType.Info);
        }

        private void DrawParameters()
        {
            GUILayout.Label("生成参数", EditorStyles.boldLabel);
            EditorGUI.indentLevel++;
            
            resolution = EditorGUILayout.IntPopup("分辨率", resolution, 
                new string[] { "32", "64", "128", "256" }, 
                new int[] { 32, 64, 128, 256 });
            
            voronoiMode = (VoronoiMode)EditorGUILayout.EnumPopup("Voronoi模式", voronoiMode);
            numCells = EditorGUILayout.IntSlider("单元数量", numCells, 5, 100);
            cellSize = EditorGUILayout.Slider("单元大小", cellSize, 0.01f, 1.0f);
            distanceFalloff = EditorGUILayout.Slider("距离衰减", distanceFalloff, 0.1f, 5.0f);
            contrast = EditorGUILayout.Slider("对比度", contrast, 0.1f, 3.0f);
            brightness = EditorGUILayout.Slider("亮度", brightness, -1.0f, 1.0f);
            randomSeed = EditorGUILayout.IntField("随机种子", randomSeed);
            useTiling = EditorGUILayout.Toggle("无缝平铺", useTiling);
            
            EditorGUI.indentLevel--;
        }

        private void DrawFractalOptions()
        {
            GUILayout.Label("分形迭代 (FBM)", EditorStyles.boldLabel);
            EditorGUI.indentLevel++;
            
            useFractal = EditorGUILayout.Toggle("启用分形迭代", useFractal);
            
            if (useFractal)
            {
                fractalOctaves = EditorGUILayout.IntSlider("迭代次数", fractalOctaves, 1, 8);
                fractalBlendMode = (FractalBlendMode)EditorGUILayout.EnumPopup("混合模式", fractalBlendMode);
                fractalLacunarity = EditorGUILayout.Slider("频率增长", fractalLacunarity, 1.0f, 4.0f);
                fractalGain = EditorGUILayout.Slider("振幅衰减", fractalGain, 0.1f, 1.0f);
                fractalBaseFrequency = EditorGUILayout.Slider("基础频率", fractalBaseFrequency, 0.5f, 4.0f);
                
                string blendDesc = GetBlendModeDescription();
                EditorGUILayout.HelpBox(blendDesc, MessageType.Info);
            }
            
            EditorGUI.indentLevel--;
        }

        private string GetBlendModeDescription()
        {
            switch (fractalBlendMode)
            {
                case FractalBlendMode.Add:
                    return "叠加模式: value = Σ(amplitude * octave)\n标准FBM，低频提供结构，高频添加细节";
                case FractalBlendMode.Multiply:
                    return "乘法模式: value = Π(1 + amplitude * octave)\n高频细节会强烈影响结果，产生更复杂的纹理";
                case FractalBlendMode.Max:
                    return "最大值模式: value = max(all octaves)\n保留每层最显著的特征";
                case FractalBlendMode.Min:
                    return "最小值模式: value = min(all octaves)\n保留每层最暗的区域";
                case FractalBlendMode.AbsAdd:
                    return "绝对值叠加: value = Σ(amplitude * |octave - 0.5|)\n产生类似湍流的效果，适合云和烟雾";
                default:
                    return "";
            }
        }

        private void DrawDebugOptions()
        {
            GUILayout.Label("调试选项", EditorStyles.boldLabel);
            EditorGUI.indentLevel++;
            
            debugMode = (DebugMode)EditorGUILayout.EnumPopup("调试模式", debugMode);
            
            if (debugMode == DebugMode.ShowSlice)
            {
                previewSlice = EditorGUILayout.IntSlider("预览切片", previewSlice, 0, resolution - 1);
            }
            
            EditorGUI.indentLevel--;
        }

        private void DrawActionButtons()
        {
            GUILayout.Label("操作", EditorStyles.boldLabel);
            EditorGUILayout.BeginHorizontal();
            
            if (GUILayout.Button("生成纹理", GUILayout.Height(30)))
            {
                GenerateVoronoi3D();
            }
            
            GUI.enabled = previewTexture != null;
            if (GUILayout.Button("导出3D纹理", GUILayout.Height(30)))
            {
                ExportTexture3D();
            }
            GUI.enabled = true;
            
            EditorGUILayout.EndHorizontal();
            
            if (previewTexture != null && GUILayout.Button("刷新预览"))
            {
                UpdateSlicePreview();
            }
        }

        private void DrawPreview()
        {
            if (previewTexture == null) return;
            
            GUILayout.Label("预览", EditorStyles.boldLabel);
            
            EditorGUILayout.BeginVertical(EditorStyles.helpBox);
            
            GUILayout.Label($"纹理信息: {previewTexture.width}x{previewTexture.height}x{previewTexture.depth}");
            GUILayout.Label($"格式: {previewTexture.format}");
            GUILayout.Label($"分形迭代: {(useFractal ? $"是 ({fractalOctaves} 层, {fractalBlendMode})" : "否")}");
            
            if (slicePreview != null && debugMode == DebugMode.ShowSlice)
            {
                GUILayout.Label($"切片 Z={previewSlice}");
                
                float aspectRatio = (float)slicePreview.width / slicePreview.height;
                int previewWidth = Mathf.Min(300, (int)(EditorGUIUtility.currentViewWidth - 40));
                int previewHeight = (int)(previewWidth / aspectRatio);
                
                GUILayout.Label("", GUILayout.Height(previewHeight));
                Rect previewRect = GUILayoutUtility.GetLastRect();
                EditorGUI.DrawPreviewTexture(previewRect, slicePreview);
            }
            
            EditorGUILayout.EndVertical();
        }

        private void GenerateVoronoi3D()
        {
            if (previewTexture != null)
            {
                DestroyImmediate(previewTexture);
            }
            if (slicePreview != null)
            {
                DestroyImmediate(slicePreview);
            }

            Random.InitState(randomSeed);
            
            List<List<Vector3>> fractalCellCenters = new List<List<Vector3>>();
            float frequency = fractalBaseFrequency;
            
            int octaves = useFractal ? fractalOctaves : 1;
            octaveValues = new float[octaves];
            
            for (int octave = 0; octave < octaves; octave++)
            {
                List<Vector3> cellCenters = new List<Vector3>();
                int cellsForOctave = Mathf.Max(5, (int)(numCells * frequency));
                
                for (int i = 0; i < cellsForOctave; i++)
                {
                    cellCenters.Add(new Vector3(
                        Random.Range(0f, 1f),
                        Random.Range(0f, 1f),
                        Random.Range(0f, 1f)
                    ));
                }
                
                fractalCellCenters.Add(cellCenters);
                frequency *= fractalLacunarity;
            }

            previewTexture = new Texture3D(resolution, resolution, resolution, TextureFormat.RGBAFloat, false);
            previewTexture.wrapMode = TextureWrapMode.Repeat;
            previewTexture.filterMode = FilterMode.Trilinear;

            Color[] colors = new Color[resolution * resolution * resolution];
            
            for (int z = 0; z < resolution; z++)
            {
                for (int y = 0; y < resolution; y++)
                {
                    for (int x = 0; x < resolution; x++)
                    {
                        float u = (float)x / resolution;
                        float v = (float)y / resolution;
                        float w = (float)z / resolution;
                        Vector3 pos = new Vector3(u, v, w);

                        float finalValue = CalculateFractalValue(pos, fractalCellCenters, octaves);
                        finalValue = ApplyContrastBrightness(finalValue, contrast, brightness);
                        finalValue = Mathf.Clamp01(finalValue);

                        int index = x + y * resolution + z * resolution * resolution;
                        
                        float debugValue = GetDebugValue(x, y, z, finalValue);
                        colors[index] = new Color(debugValue, debugValue, debugValue, 1);
                    }
                }
                
                EditorUtility.DisplayProgressBar("生成Voronoi 3D纹理", 
                    $"正在处理... {z + 1}/{resolution}", 
                    (float)z / resolution);
            }

            previewTexture.SetPixels(colors);
            previewTexture.Apply();
            
            EditorUtility.ClearProgressBar();
            
            UpdateSlicePreview();
            
            Debug.Log($"Voronoi 3D纹理生成完成: 分辨率={resolution}, 单元数={numCells}, 模式={voronoiMode}, 分形迭代={useFractal}, 混合模式={fractalBlendMode}");
        }

        private float CalculateFractalValue(Vector3 pos, List<List<Vector3>> fractalCellCenters, int octaves)
        {
            float frequency = fractalBaseFrequency;
            float amplitude = 1.0f;
            
            float[] octaveResults = new float[octaves];
            
            for (int octave = 0; octave < octaves; octave++)
            {
                float octaveCellSize = cellSize / frequency;
                List<Vector3> cellCenters = fractalCellCenters[octave];
                
                float minDist = float.MaxValue;
                float secondMinDist = float.MaxValue;
                int closestCellID = 0;

                for (int i = 0; i < cellCenters.Count; i++)
                {
                    Vector3 cellPos = cellCenters[i];
                    float dist = CalculateDistance(pos, cellPos, useTiling) / octaveCellSize;
                    
                    if (dist < minDist)
                    {
                        secondMinDist = minDist;
                        minDist = dist;
                        closestCellID = i;
                    }
                    else if (dist < secondMinDist)
                    {
                        secondMinDist = dist;
                    }
                }

                float octaveValue = CalculateVoronoiValue(minDist, secondMinDist, closestCellID, cellCenters.Count);
                octaveResults[octave] = octaveValue;
                octaveValues[octave] = octaveValue;
                
                frequency *= fractalLacunarity;
                amplitude *= fractalGain;
            }

            if (!useFractal || octaves == 1)
            {
                return octaveResults[0];
            }

            return BlendOctaves(octaveResults);
        }

        private float BlendOctaves(float[] octaveResults)
        {
            float frequency = fractalBaseFrequency;
            float amplitude = 1.0f;
            float result = 0f;
            
            switch (fractalBlendMode)
            {
                case FractalBlendMode.Add:
                    for (int i = 0; i < octaveResults.Length; i++)
                    {
                        result += octaveResults[i] * amplitude;
                        amplitude *= fractalGain;
                    }
                    break;
                    
                case FractalBlendMode.Multiply:
                    result = 1f;
                    for (int i = 0; i < octaveResults.Length; i++)
                    {
                        result *= (1f + octaveResults[i] * amplitude * 0.5f);
                        amplitude *= fractalGain;
                    }
                    result -= 1f;
                    break;
                    
                case FractalBlendMode.Max:
                    result = 0f;
                    for (int i = 0; i < octaveResults.Length; i++)
                    {
                        result = Mathf.Max(result, octaveResults[i]);
                    }
                    break;
                    
                case FractalBlendMode.Min:
                    result = 1f;
                    for (int i = 0; i < octaveResults.Length; i++)
                    {
                        result = Mathf.Min(result, octaveResults[i]);
                    }
                    break;
                    
                case FractalBlendMode.AbsAdd:
                    for (int i = 0; i < octaveResults.Length; i++)
                    {
                        result += Mathf.Abs(octaveResults[i] - 0.5f) * amplitude * 2f;
                        amplitude *= fractalGain;
                    }
                    break;
            }
            
            return result;
        }

        private float GetDebugValue(int x, int y, int z, float finalValue)
        {
            switch (debugMode)
            {
                case DebugMode.ShowOctave0:
                    return octaveValues != null && octaveValues.Length > 0 ? octaveValues[0] : finalValue;
                case DebugMode.ShowOctave1:
                    return octaveValues != null && octaveValues.Length > 1 ? octaveValues[1] : finalValue;
                case DebugMode.ShowOctave2:
                    return octaveValues != null && octaveValues.Length > 2 ? octaveValues[2] : finalValue;
                case DebugMode.ShowOctave3:
                    return octaveValues != null && octaveValues.Length > 3 ? octaveValues[3] : finalValue;
                default:
                    return finalValue;
            }
        }

        private float CalculateDistance(Vector3 a, Vector3 b, bool tiling)
        {
            if (!tiling)
            {
                return Vector3.Distance(a, b);
            }
            
            float dx = Mathf.Abs(a.x - b.x);
            float dy = Mathf.Abs(a.y - b.y);
            float dz = Mathf.Abs(a.z - b.z);
            
            dx = Mathf.Min(dx, 1.0f - dx);
            dy = Mathf.Min(dy, 1.0f - dy);
            dz = Mathf.Min(dz, 1.0f - dz);
            
            return Mathf.Sqrt(dx * dx + dy * dy + dz * dz);
        }

        private float CalculateVoronoiValue(float minDist, float secondMinDist, int cellID, int totalCells)
        {
            switch (voronoiMode)
            {
                case VoronoiMode.CellEdge:
                    float edge = secondMinDist - minDist;
                    return Mathf.Pow(edge, distanceFalloff);
                    
                case VoronoiMode.CellDistance:
                    return Mathf.Pow(minDist, distanceFalloff);
                    
                case VoronoiMode.CellID:
                    return (float)cellID / totalCells;
                    
                case VoronoiMode.WorleyNoise:
                    return 1.0f - Mathf.Pow(minDist, distanceFalloff);
                    
                default:
                    return 0;
            }
        }

        private float ApplyContrastBrightness(float value, float contrast, float brightness)
        {
            return (value - 0.5f) * contrast + 0.5f + brightness;
        }

        private void UpdateSlicePreview()
        {
            if (previewTexture == null) return;
            
            if (slicePreview != null)
            {
                DestroyImmediate(slicePreview);
            }
            
            slicePreview = new Texture2D(resolution, resolution, TextureFormat.RGBAFloat, false);
            Color[] sliceColors = new Color[resolution * resolution];
            
            Color[] allColors = previewTexture.GetPixels();
            
            for (int y = 0; y < resolution; y++)
            {
                for (int x = 0; x < resolution; x++)
                {
                    int index = x + y * resolution + previewSlice * resolution * resolution;
                    sliceColors[x + y * resolution] = allColors[index];
                }
            }
            
            slicePreview.SetPixels(sliceColors);
            slicePreview.Apply();
        }

        private void ExportTexture3D()
        {
            if (previewTexture == null)
            {
                EditorUtility.DisplayDialog("提示", "请先生成Voronoi 3D纹理", "确定");
                return;
            }

            string fractalStr = useFractal ? $"_FBM{fractalOctaves}_{fractalBlendMode}" : "";
            string defaultName = $"Voronoi3D_{voronoiMode}_{resolution}x{resolution}x{resolution}{fractalStr}";
            string path = EditorUtility.SaveFilePanelInProject(
                "导出3D纹理",
                defaultName,
                "asset",
                "请输入文件名"
            );

            if (!string.IsNullOrEmpty(path))
            {
                Texture3D exportedTexture = new Texture3D(resolution, resolution, resolution, TextureFormat.RGBAFloat, false);
                exportedTexture.SetPixels(previewTexture.GetPixels());
                exportedTexture.wrapMode = TextureWrapMode.Repeat;
                exportedTexture.filterMode = FilterMode.Trilinear;
                exportedTexture.Apply();
                
                AssetDatabase.CreateAsset(exportedTexture, path);
                AssetDatabase.SaveAssets();
                AssetDatabase.Refresh();
                
                EditorUtility.DisplayDialog("成功", $"3D纹理已导出到:\n{path}", "确定");
                Debug.Log($"Voronoi 3D纹理已导出: {path}");
            }
        }

        private void OnDestroy()
        {
            if (previewTexture != null)
            {
                DestroyImmediate(previewTexture);
            }
            if (slicePreview != null)
            {
                DestroyImmediate(slicePreview);
            }
            if (previewMaterial != null)
            {
                DestroyImmediate(previewMaterial);
            }
            
            EditorUtility.ClearProgressBar();
        }
    }
}
