using UnityEngine;
using UnityEditor;

[CustomEditor(typeof(BruteForceSDFBaker))]
public class BruteForceSDFBakerEditor : Editor
{
    public override void OnInspectorGUI()
    {
        DrawDefaultInspector();

        BruteForceSDFBaker baker = (BruteForceSDFBaker)target;

        EditorGUILayout.Space(10);
        
        EditorGUILayout.HelpBox(
            "暴力法SDF烘焙器\n\n" +
            "特点:\n" +
            "- 100%精确计算每个像素到边界的最近距离\n" +
            "- 方向向量完全准确，无放射状伪影\n" +
            "- 适合预烘焙，不适合实时计算\n\n" +
            "使用方法:\n" +
            "1. 准备一张二值纹理（白色=陆地/内部，黑色=水域/外部）\n" +
            "2. 确保纹理开启了Read/Write Enable\n" +
            "3. 点击下方按钮开始烘焙\n" +
            "4. 结果将保存到指定文件夹",
            MessageType.Info
        );

        EditorGUILayout.Space(10);

        if (GUILayout.Button("烘焙 SDF", GUILayout.Height(40)))
        {
            baker.BakeSDF();
        }

        EditorGUILayout.Space(5);

        if (GUILayout.Button("清除输出文件夹", GUILayout.Height(30)))
        {
            string outputPath = System.IO.Path.Combine(Application.dataPath, baker.outputFolder);
            if (System.IO.Directory.Exists(outputPath))
            {
                if (EditorUtility.DisplayDialog("确认删除", 
                    $"确定要删除文件夹 {baker.outputFolder} 中的所有内容吗?", 
                    "确定", "取消"))
                {
                    System.IO.Directory.Delete(outputPath, true);
                    AssetDatabase.Refresh();
                    Debug.Log($"已删除输出文件夹: {baker.outputFolder}");
                }
            }
            else
            {
                Debug.Log("输出文件夹不存在");
            }
        }
    }
}
