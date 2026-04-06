using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[ExecuteInEditMode]
public class Curve2Shader : MonoBehaviour
{
    [SerializeField]private Material material;
    [SerializeField]private AnimationCurve densityGradient = new AnimationCurve(new Keyframe(0, 0),new Keyframe(0.2f, 1.0f), new Keyframe(1, 0));
    [SerializeField]private int rampResolution = 256;
    private Texture2D densityRampTexture;
    // 用于检测是否变化
    private AnimationCurve lastDensityGradient;
    private int lastRampResolution;
    // Start is called before the first frame update
    void Start()
    {
        lastDensityGradient = densityGradient;
        lastRampResolution = rampResolution;
        CreatRampTexture(ref densityRampTexture, rampResolution);
        UpdateRampTexture(ref densityGradient, ref densityRampTexture, rampResolution);
        if (material != null)
        {
            material.SetTexture("_CloudHeightGradient", densityRampTexture);
        }
    }

    // Update is called once per frame
    void Update()
    {
        //if (densityGradient != lastDensityGradient || rampResolution != lastRampResolution)
        //{
            UpdateRampTexture(ref densityGradient, ref densityRampTexture, rampResolution);
            if (material != null)
            {
                material.SetTexture("_CloudHeightGradient", densityRampTexture);
            }
        //}
    }
    void UpdateRampTexture(ref AnimationCurve curve,ref Texture2D rampTexture, int resolution)
    {
        for (int i = 0; i < resolution; i++)
        {
            float t = (float)i / (resolution - 1);
            float value = curve.Evaluate(t);
            rampTexture.SetPixel(i, 0, new Color(value, 0, 0, 1));
        }
        rampTexture.Apply();
    }
    void CreatRampTexture(ref Texture2D rampTexture, int resolution)
    {
        rampTexture = new Texture2D(resolution, 1, TextureFormat.RFloat, false);
        rampTexture.wrapMode = TextureWrapMode.Clamp;
        rampTexture.filterMode = FilterMode.Bilinear;
    }
}
