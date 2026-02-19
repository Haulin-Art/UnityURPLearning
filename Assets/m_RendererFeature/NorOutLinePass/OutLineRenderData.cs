using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class OutLineRenderData : MonoBehaviour
{
    [Header("渲染效果属性")]
    public Color OutLineColor = Color.black;
    [Range(0.0f,5.0f)]
    public float OutLineThickness = 1.0f;

}
