using System.Collections;
using System.Collections.Generic;
using UnityEngine;

/// <summary>
/// 这个脚本用于控制显示结果
/// </summary>
public class ShowControl : MonoBehaviour
{
    public int _DebugView = 0;
    public Material _WaterMaterial;


    // Start is called before the first frame update
    void Start()
    {
        
    }

    // Update is called once per frame
    void Update()
    {
        if (Input.GetKeyDown(KeyCode.Y))
        {
            _DebugView = 2;
            _WaterMaterial.SetFloat("_DebugView",_DebugView);
        }
        if (Input.GetKeyDown(KeyCode.F))
        {
            _DebugView = 0;
            _WaterMaterial.SetFloat("_DebugView",_DebugView);
        }
        if (Input.GetKeyDown(KeyCode.N))
        {
            _DebugView = 5;
            _WaterMaterial.SetFloat("_DebugView",_DebugView);
        }
        if (Input.GetKeyDown(KeyCode.C))
        {
            _DebugView = 1;
            _WaterMaterial.SetFloat("_DebugView",_DebugView);
        }

    }
}
