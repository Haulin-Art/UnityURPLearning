using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[ExecuteInEditMode]
public class ZMDShowScripts : MonoBehaviour
{
    [SerializeField]
    public enum DebugMode
    {
        None,
        Shadow
    }

    public Material[] materials;

    public float rimThickness;
    public Color rimColor;

    public DebugMode debugMode;

    public bool rain = false;
    void Start()
    {
        
    }

    // Update is called once per frame
    void Update()
    {
        if (Input.GetKeyDown(KeyCode.R))
        {
            rain = !rain;
        }
        if (Input.GetKeyDown(KeyCode.V))
        {
            if (debugMode != DebugMode.Shadow)
            {
                debugMode = DebugMode.Shadow;
            }
            else
            {
                debugMode = DebugMode.None;
            }
        }
        

        if (materials == null || materials.Length == 0)
        {
            return;
        }
        for (int i = 0; i < materials.Length; i++)
        {
            materials[i].SetFloat("_RimThickness", rimThickness);
            materials[i].SetColor("_RimColor", rimColor);

            if (debugMode == DebugMode.Shadow)
            {
                materials[i].SetFloat("_DebugMode", 1.0f);
            }
            else
            {
                materials[i].SetFloat("_DebugMode", 0.0f);
            }
            materials[i].SetFloat("_Rain", rain ? 1.0f : 0.0f);
        }
    }
}
