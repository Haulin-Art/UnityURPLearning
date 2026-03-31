using UnityEngine;
using UnityEditor;

namespace RuntimeGravityMap
{
    /// <summary>
    /// 物体空间位置图烘焙器（GPU加速）
    /// </summary>
    public class OSPosMapBaker : EditorWindow
    {
        [MenuItem("Tools/OSPosMap烘焙器")]
        public static void ShowWindow()
        {
            GetWindow<OSPosMapBaker>("OSPosMap烘焙器");
        }

        private Mesh _targetMesh;
        private ComputeShader _computeShader;
        private int _resolution = 512;
        private int _uvChannel = 0;
        private string _outputPath = "Assets/OSPosMap.asset";

        private void OnGUI()
        {
            EditorGUILayout.LabelField("物体空间位置图烘焙器 (GPU)", EditorStyles.boldLabel);
            EditorGUILayout.HelpBox("使用GPU并行计算，输出格式：xyz=位置，w=UV岛有效标记", MessageType.Info);

            EditorGUILayout.Space(10);

            _targetMesh = (Mesh)EditorGUILayout.ObjectField("目标网格", _targetMesh, typeof(Mesh), false);
            _computeShader = (ComputeShader)EditorGUILayout.ObjectField("Compute Shader", _computeShader, typeof(ComputeShader), false);

            if (_targetMesh != null)
            {
                EditorGUI.indentLevel++;
                EditorGUILayout.LabelField($"顶点数: {_targetMesh.vertexCount}");
                EditorGUILayout.LabelField($"三角形数: {_targetMesh.triangles.Length / 3}");
                EditorGUI.indentLevel--;
            }

            _resolution = EditorGUILayout.IntPopup("分辨率", _resolution,
                new string[] { "256", "512", "1024", "2048" },
                new int[] { 256, 512, 1024, 2048 });

            _uvChannel = EditorGUILayout.IntPopup("UV通道", _uvChannel,
                new string[] { "UV0", "UV1", "UV2", "UV3" },
                new int[] { 0, 1, 2, 3 });

            EditorGUILayout.BeginHorizontal();
            EditorGUILayout.LabelField("输出路径", GUILayout.Width(80));
            _outputPath = EditorGUILayout.TextField(_outputPath);
            if (GUILayout.Button("浏览", GUILayout.Width(50)))
            {
                string path = EditorUtility.SaveFilePanel("保存位置图", "Assets", "OSPosMap", "asset");
                if (!string.IsNullOrEmpty(path) && path.StartsWith(Application.dataPath))
                {
                    _outputPath = "Assets" + path.Substring(Application.dataPath.Length);
                }
            }
            EditorGUILayout.EndHorizontal();

            EditorGUILayout.Space(10);

            EditorGUI.BeginDisabledGroup(_targetMesh == null || _computeShader == null);
            if (GUILayout.Button("烘焙", GUILayout.Height(30)))
            {
                Bake();
            }
            EditorGUI.EndDisabledGroup();
        }

        private void Bake()
        {
            if (_targetMesh == null || _computeShader == null) return;

            // 提取网格数据
            Vector3[] vertices = _targetMesh.vertices;
            Vector2[] uvs = GetUVs(_targetMesh, _uvChannel);
            int[] triangles = _targetMesh.triangles;

            if (vertices == null || vertices.Length == 0)
            {
                EditorUtility.DisplayDialog("错误", "网格没有顶点数据！", "确定");
                return;
            }

            if (uvs == null || uvs.Length == 0)
            {
                EditorUtility.DisplayDialog("错误", "网格没有UV数据！", "确定");
                return;
            }

            // 创建Compute Buffer
            ComputeBuffer vertexBuffer = new ComputeBuffer(vertices.Length, sizeof(float) * 3);
            ComputeBuffer uvBuffer = new ComputeBuffer(uvs.Length, sizeof(float) * 2);
            ComputeBuffer indexBuffer = new ComputeBuffer(triangles.Length, sizeof(uint));

            vertexBuffer.SetData(vertices);
            uvBuffer.SetData(uvs);
            indexBuffer.SetData(triangles);

            // 创建临时RenderTexture
            RenderTexture rt = new RenderTexture(_resolution, _resolution, 0, RenderTextureFormat.ARGBFloat);
            rt.enableRandomWrite = true;
            rt.wrapMode = TextureWrapMode.Clamp;
            rt.filterMode = FilterMode.Point;
            rt.Create();

            // 设置Compute Shader
            int kernel = _computeShader.FindKernel("BakeOSPosMap");
            _computeShader.SetBuffer(kernel, "_Vertices", vertexBuffer);
            _computeShader.SetBuffer(kernel, "_UVs", uvBuffer);
            _computeShader.SetBuffer(kernel, "_Indices", indexBuffer);
            _computeShader.SetTexture(kernel, "_OutputTexture", rt);
            _computeShader.SetInt("_Resolution", _resolution);
            _computeShader.SetInt("_TriangleCount", triangles.Length / 3);

            // 执行
            int groups = Mathf.CeilToInt(_resolution / 8f);
            _computeShader.Dispatch(kernel, groups, groups, 1);

            // 读回数据
            Texture2D texture = new Texture2D(_resolution, _resolution, TextureFormat.RGBAFloat, false, true);
            RenderTexture.active = rt;
            texture.ReadPixels(new Rect(0, 0, _resolution, _resolution), 0, 0);
            texture.Apply();
            RenderTexture.active = null;

            // 保存
            AssetDatabase.CreateAsset(texture, _outputPath);
            AssetDatabase.Refresh();

            // 清理
            vertexBuffer.Release();
            uvBuffer.Release();
            indexBuffer.Release();
            rt.Release();

            Debug.Log($"[OSPosMapBaker] 烘焙完成: {_outputPath}");
            Selection.activeObject = texture;
        }

        private Vector2[] GetUVs(Mesh mesh, int channel)
        {
            if (channel == 0) return mesh.uv;
            if (channel == 1) return mesh.uv2;
            var list = new System.Collections.Generic.List<Vector2>();
            mesh.GetUVs(channel, list);
            return list.ToArray();
        }
    }
}
