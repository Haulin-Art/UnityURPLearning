using System.Collections;
using System.Collections.Generic;
using Unity.Mathematics;
using UnityEngine;
using UnityEngine.Rendering;

public class GLM_SWESimulation : MonoBehaviour
{
    [Header("File Input")]
    public ComputeShader computeShader;
    public Material mat;

    [Space(10)]
    [Header("Follow Settings")]
    public GameObject root;
    [Range(0.0f, 20.0f)] public float offsetScale = 10.0f;

    [Space(10)]
    [Header("Simulation Parameters")]
    public int size = 256;
    [Range(0.0f, 0.5f)] public float dt = 0.05f;
    [Range(0.0f, 0.2f)] public float penRadius = 0.02f;
    [Range(0.0f, 20.0f)] public float SpeedScale = 5.0f;
    [Range(0.0f, 0.1f)] public float speedAttenuation = 0.005f;
    [Range(0.0f, 0.1f)] public float heightAttenuation = 0.005f;

    [Space(10)]
    [Header("Shallow Water Parameters")]
    [Range(1.0f, 100.0f)] public float gravity = 30.0f;
    [Range(0.1f, 10.0f)] public float baseWaterLevel = 1.0f;
    [Range(0.0f, 0.1f)] public float bedFriction = 0.001f;

    [Space(10)]
    [Header("Debug Output")]
    public RenderTexture debugOutputRT;
    public bool enableDebug = true;

    private Vector4 footPos;
    private int2 footDrop;
    private Vector2 pos = new Vector2(0.5f, 0.5f);
    private Vector2 prePos;
    private Vector2 force;
    private bool keyDown = false;

    private RTHandle stateBuffer1;
    private RTHandle stateBuffer2;

    private int advectionKernel;
    private int updateKernel;
    private int boundaryKernel;

    private int texSizeID;
    private int dtID;
    private int footPosID;
    private int footDropID;
    private int ForceID;
    private int radiusID;
    private int keyDownID;
    private int attenuationID;
    private int gravityID;
    private int baseWaterLevelID;
    private int bedFrictionID;
    private int StateReadID;
    private int StateWriteID;
    private int StateTexID;

    void Start()
    {
        if (computeShader == null)
        {
            Debug.LogError("[GLM_SWE] Compute Shader is not assigned!");
            enabled = false;
            return;
        }

        if (mat == null)
        {
            Debug.LogError("[GLM_SWE] Material is not assigned!");
            enabled = false;
            return;
        }

        force = new Vector2(0f, 0f);
        if (root != null)
        {
            pos = new Vector2(root.transform.position.x, root.transform.position.z);
            prePos = pos;
        }

        CachePropertyIDs();
        InitializeKernels();
        InitializeRTHandles();

        Debug.Log("[GLM_SWE] Initialization complete.");
    }

    void CachePropertyIDs()
    {
        texSizeID = Shader.PropertyToID("texSize");
        dtID = Shader.PropertyToID("dt");
        footPosID = Shader.PropertyToID("footPos");
        footDropID = Shader.PropertyToID("footDrop");
        ForceID = Shader.PropertyToID("Force");
        radiusID = Shader.PropertyToID("radius");
        keyDownID = Shader.PropertyToID("keyDown");
        attenuationID = Shader.PropertyToID("attenuation");
        gravityID = Shader.PropertyToID("gravity");
        baseWaterLevelID = Shader.PropertyToID("baseWaterLevel");
        bedFrictionID = Shader.PropertyToID("bedFriction");
        StateReadID = Shader.PropertyToID("StateRead");
        StateWriteID = Shader.PropertyToID("StateWrite");
        StateTexID = Shader.PropertyToID("StateTex");
    }

    void Update()
    {
        if (computeShader == null || mat == null) return;
        if (root == null) return;

        gameObject.transform.position = new Vector3(root.transform.position.x, 0.05f, root.transform.position.z);

        pos = new Vector2(root.transform.position.x, root.transform.position.z);

        force = (prePos - pos);
        keyDown = (pos != prePos);

        footDrop.x = 1;
        footDrop.y = 1;

        footPos = new Vector4(0, 0, 0, 0);

        SimulateFluid();

        mat.SetTexture("_HeightTex", stateBuffer1);

        prePos = pos;

        Shader.SetGlobalTexture("_SWEStateTex", stateBuffer1.rt);
        Shader.SetGlobalVector("_SWEParams", new Vector4(
            root.transform.position.x,
            root.transform.position.z,
            offsetScale,
            baseWaterLevel
        ));

        if (enableDebug && debugOutputRT != null)
        {
            CopyHeightToDebugRT();
        }
    }

    void InitializeKernels()
    {
        advectionKernel = computeShader.FindKernel("AdvectionKernel");
        updateKernel = computeShader.FindKernel("UpdateKernel");
        boundaryKernel = computeShader.FindKernel("BoundaryKernel");
    }

    void InitializeRTHandles()
    {
        ReleaseRTHandles();

        stateBuffer1 = RTHandles.Alloc(
            size, size,
            colorFormat: UnityEngine.Experimental.Rendering.GraphicsFormat.R16G16B16A16_SFloat,
            enableRandomWrite: true,
            name: "StateBuffer1"
        );
        stateBuffer2 = RTHandles.Alloc(
            size, size,
            colorFormat: UnityEngine.Experimental.Rendering.GraphicsFormat.R16G16B16A16_SFloat,
            enableRandomWrite: true,
            name: "StateBuffer2"
        );
    }

    void ReleaseRTHandles()
    {
        stateBuffer1?.Release();
        stateBuffer2?.Release();
    }

    void SimulateFluid()
    {
        int threadGroups = Mathf.CeilToInt(size / 8.0f);

        computeShader.SetFloat(texSizeID, (float)size);
        computeShader.SetFloat(dtID, dt);
        computeShader.SetVector(footPosID, footPos);
        computeShader.SetInts(footDropID, footDrop.x, footDrop.y);
        computeShader.SetVector(ForceID, new Vector3(force.x, force.y, SpeedScale));
        computeShader.SetFloat(radiusID, penRadius);
        computeShader.SetBool(keyDownID, keyDown);
        computeShader.SetVector(attenuationID, new Vector2(speedAttenuation, heightAttenuation));
        computeShader.SetFloat(gravityID, gravity);
        computeShader.SetFloat(baseWaterLevelID, baseWaterLevel);
        computeShader.SetFloat(bedFrictionID, bedFriction);

        computeShader.SetTexture(advectionKernel, StateReadID, stateBuffer1);
        computeShader.SetTexture(advectionKernel, StateWriteID, stateBuffer2);
        computeShader.SetTexture(advectionKernel, StateTexID, stateBuffer1);
        computeShader.Dispatch(advectionKernel, threadGroups, threadGroups, 1);
        Swap(ref stateBuffer1, ref stateBuffer2);

        computeShader.SetTexture(updateKernel, StateReadID, stateBuffer1);
        computeShader.SetTexture(updateKernel, StateWriteID, stateBuffer2);
        computeShader.Dispatch(updateKernel, threadGroups, threadGroups, 1);
        Swap(ref stateBuffer1, ref stateBuffer2);

        computeShader.SetTexture(boundaryKernel, StateReadID, stateBuffer1);
        computeShader.SetTexture(boundaryKernel, StateWriteID, stateBuffer2);
        computeShader.Dispatch(boundaryKernel, threadGroups, threadGroups, 1);
        Swap(ref stateBuffer1, ref stateBuffer2);
    }

    void CopyHeightToDebugRT()
    {
        if (debugOutputRT == null) return;

        RenderTexture prev = RenderTexture.active;
        Graphics.Blit(stateBuffer1, debugOutputRT);
        RenderTexture.active = prev;
    }

    void Swap(ref RTHandle a, ref RTHandle b)
    {
        RTHandle temp = a;
        a = b;
        b = temp;
    }

    private void OnDestroy()
    {
        ReleaseRTHandles();
    }

    private void OnDisable()
    {
        ReleaseRTHandles();
    }

    void OnDrawGizmosSelected()
    {
        if (root != null)
        {
            Gizmos.color = Color.cyan;
            Gizmos.DrawWireCube(transform.position, new Vector3(offsetScale * 2, 0.1f, offsetScale * 2));

            Gizmos.color = keyDown ? Color.green : Color.yellow;
            Gizmos.DrawWireSphere(root.transform.position, penRadius * offsetScale);
        }
    }
}
