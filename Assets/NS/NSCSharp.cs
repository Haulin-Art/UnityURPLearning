using System;
using System.Collections;
using System.Collections.Generic;
using Unity.Mathematics;
using UnityEngine;

public struct canyv
{
    public Vector3 cuPos;//当前位置
    public Vector3 laPos;//上一帧位置
    public Vector2 vel;//相对方向
};


public class NSCSharp : MonoBehaviour
{
    //public myEnum canyv;
    [Header("文件")]
    public ComputeShader cs;
    public Shader shader;
    public Material mat;

    [Header("参与交互物体")]
    public GameObject actor;
    canyv[] dat;
    canyv cy;
    ComputeBuffer wt;

    RenderTexture rt;// 最终的rt
    int kernelId;//核函数下标


    // Start is called before the first frame update
    void Start()
    {
        // 传入传出的rt设置
        //rt = new RenderTexture(256, 256, 16);
        rt = new RenderTexture(256, 256, 0, RenderTextureFormat.ARGBFloat);
        rt.enableRandomWrite = true;
        rt.Create();

        kernelId = cs.FindKernel("CSMain");

        // 设置数据数量，以及单个数据占用的byte大小
        wt = new ComputeBuffer(1,32);
        dat = new canyv[1];
        cy.cuPos = new Vector3(actor.transform.position.x, actor.transform.position.y, actor.transform.position.z);
        cy.laPos = new Vector3(actor.transform.position.x, actor.transform.position.y, actor.transform.position.z);
        cy.vel = new Vector2(cy.cuPos.x - cy.laPos.x, cy.cuPos.z - cy.laPos.z);
        dat[0] = cy;
        // 将我们的数据传入我们设定的buffer
        wt.SetData(dat);


        runCS();

    }

    // Update is called once per frame
    void Update()
    {
        cy.cuPos = new Vector3(actor.transform.position.x, actor.transform.position.y, actor.transform.position.z);
        cy.vel = new Vector2(cy.cuPos.x - cy.laPos.x, cy.cuPos.z - cy.laPos.z);
        cy.laPos = cy.cuPos;
        dat[0] = cy;
        //UnityEngine.Debug.Log(cy.vel);
        runCS();
    }

    void runCS()
    {
        mat.mainTexture = rt;
        //mat.SetTexture("mainTex", rt);
        // 设置tex
        cs.SetTexture(kernelId, "Result", rt);
        // 设置物体位置buffer
        // 设置交互物体信息buffer
        wt.SetData(dat);
        cs.SetBuffer(kernelId, "wt", wt);

        cs.Dispatch(kernelId, 256 / 8, 256 / 8, 1);

    }
    // 关键：释放非托管资源（避免内存泄漏）
    void OnDestroy()
    {
        // 释放 RenderTexture
        if (rt != null)
        {
            rt.Release();
            rt = null;
        }
        // 释放 ComputeBuffer
        if (wt != null)
        {
            wt.Release();
            wt = null;
        }
    }

}
