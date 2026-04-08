using System.Collections.Generic;
using UnityEngine;

public class WaterLineRenderer : MonoBehaviour
{
    public List<Renderer> waterLineRenderers = new List<Renderer>();
    public List<GameObject> waterLineGameObjects = new List<GameObject>();
    
    // 单例模式，但不使用 DontDestroyOnLoad
    private static WaterLineRenderer _instance;
    public static WaterLineRenderer Instance
    {
        get
        {
            if (_instance == null)
            {
                // 尝试在场景中查找已有的实例
                _instance = FindObjectOfType<WaterLineRenderer>();
                
                if (_instance == null)
                {
                    var go = new GameObject("WaterLineRendererManager");
                    _instance = go.AddComponent<WaterLineRenderer>();
                    
                    // 只有在播放模式下才使用 DontDestroyOnLoad
                    if (Application.isPlaying)
                    {
                        DontDestroyOnLoad(go);
                    }
                    else
                    {
                        // 在编辑器模式下，隐藏这个对象
                        go.hideFlags = HideFlags.HideAndDontSave;
                    }
                }
            }
            return _instance;
        }
    }
    
    public void RegisterRenderer(Renderer renderer)
    {
        if (!waterLineRenderers.Contains(renderer))
        {
            waterLineRenderers.Add(renderer);
        }
    }
    
    public void UnregisterRenderer(Renderer renderer)
    {
        waterLineRenderers.Remove(renderer);
    }
    
    // 可选：清理空引用
    public void CleanupNullReferences()
    {
        for (int i = waterLineRenderers.Count - 1; i >= 0; i--)
        {
            if (waterLineRenderers[i] == null)
            {
                waterLineRenderers.RemoveAt(i);
            }
        }
    }
}