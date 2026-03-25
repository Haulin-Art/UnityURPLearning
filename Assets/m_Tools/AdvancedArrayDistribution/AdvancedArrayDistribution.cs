using UnityEngine;

/// <summary>
/// 高级阵列化渲染组件
/// 使用DrawMeshInstancedIndirect进行大规模实例渲染
/// 支持GPU驱动的视锥剔除与HZB遮挡剔除
/// </summary>
[ExecuteAlways]
public class AdvancedArrayDistribution : MonoBehaviour
{
    #region 调试模式枚举

    /// <summary>
    /// 调试模式
    /// </summary>
    public enum DebugMode
    {
        // 基础调试
        None,                   // 正常渲染
        LogInstanceCount,       // 输出实例计数
        RenderAllInstances,     // 跳过所有剔除
        
        // 剔除调试（后续阶段使用）
        FrustumCullingOnly,     // 仅视锥剔除
        OcclusionCullingOnly,   // 仅遮挡剔除
        FullCullingPipeline,    // 完整剔除流程
        
        // 可视化调试（后续阶段使用）
        ShowCullingStats,       // 显示剔除统计
        ColorByCullingState     // 按剔除状态着色
    }

    #endregion

    #region 序列化字段 - 网格与材质

    [Header("网格与材质")]
    [Tooltip("要绘制的网格")]
    [SerializeField] private Mesh mesh;
    
    [Tooltip("使用的材质（需配合AdvancedArrayInstanced.shader）")]
    [SerializeField] private Material material;

    #endregion

    #region 序列化字段 - 阵列设置

    [Header("阵列设置")]
    [Tooltip("各方向上的实例数量")]
    [SerializeField] private Vector3Int arraySize = new Vector3Int(10, 1, 10);
    
    [Tooltip("实例之间的间距")]
    [SerializeField] private Vector3 spacing = Vector3.one;
    
    [Tooltip("阵列起始点（本地坐标）")]
    [SerializeField] private Vector3 startPoint = Vector3.zero;
    
    [Tooltip("整体偏移量")]
    [SerializeField] private Vector3 globalOffset = Vector3.zero;

    #endregion

    #region 序列化字段 - 实例变换

    [Header("实例变换")]
    [Tooltip("单个实例的缩放比例")]
    [SerializeField] private Vector3 instanceScale = Vector3.one;
    
    [Tooltip("单个实例的旋转（欧拉角）")]
    [SerializeField] private Vector3 instanceRotationEuler = Vector3.zero;

    #endregion

    #region 序列化字段 - 渲染选项

    [Header("渲染选项")]
    [Tooltip("是否在编辑器中绘制Gizmos")]
    [SerializeField] private bool drawGizmos = true;
    
    [Tooltip("是否投射阴影")]
    [SerializeField] private bool castShadows = true;
    
    [Tooltip("是否接收阴影")]
    [SerializeField] private bool receiveShadows = true;
    
    [Tooltip("渲染层级")]
    [SerializeField] private int layer = 0;

    #endregion

    #region 序列化字段 - Compute Shader

    [Header("Compute Shader")]
    [Tooltip("实例数据生成与剔除的Compute Shader")]
    [SerializeField] private ComputeShader instanceDataCompute;

    #endregion

    #region 序列化字段 - 调试

    [Header("调试")]
    [Tooltip("调试模式")]
    [SerializeField] private DebugMode debugMode = DebugMode.None;

    #endregion

    #region 私有字段 - ComputeBuffer

    private ComputeBuffer instanceDataBuffer;   // 所有实例数据
    private ComputeBuffer visibleBuffer;        // 剔除后的可见实例
    private ComputeBuffer argsBuffer;           // 间接绘制参数
    private ComputeBuffer counterBuffer;        // 可见实例计数器

    private const int ARGS_BUFFER_SIZE = 5;     // ArgsBuffer大小（5个uint）

    #endregion

    #region 私有字段 - Kernel索引

    private int kernelGenerateInstances;
    private int kernelCullingAndCount;
    private int kernelUpdateArgsBuffer;

    #endregion

    #region 私有字段 - 缓存

    private int totalInstanceCount;
    private Vector3Int cachedArraySize;
    private bool needsBufferRecreate = true;

    #endregion

    #region 属性

    /// <summary>
    /// 获取实例总数
    /// </summary>
    public int TotalInstanceCount => totalInstanceCount;

    #endregion

    #region Unity生命周期

    private void OnEnable()
    {
        InitializeComputeShader();
        CreateBuffers();
    }

    private void OnDisable()
    {
        ReleaseBuffers();
    }

    private void Update()
    {
        // 检查阵列尺寸是否变化
        if (cachedArraySize != arraySize)
        {
            needsBufferRecreate = true;
            cachedArraySize = arraySize;
        }

        // 重新创建Buffer（如果需要）
        if (needsBufferRecreate)
        {
            CreateBuffers();
            needsBufferRecreate = false;
        }

        // 更新实例数据
        UpdateInstanceData();

        // 执行渲染
        Render();
    }

    #endregion

    #region 初始化方法

    /// <summary>
    /// 初始化Compute Shader
    /// </summary>
    private void InitializeComputeShader()
    {
        if (instanceDataCompute == null)
            return;

        kernelGenerateInstances = instanceDataCompute.FindKernel("GenerateInstances");
        kernelCullingAndCount = instanceDataCompute.FindKernel("CullingAndCount");
        kernelUpdateArgsBuffer = instanceDataCompute.FindKernel("UpdateArgsBuffer");
    }

    /// <summary>
    /// 创建ComputeBuffer
    /// </summary>
    private void CreateBuffers()
    {
        // 计算总实例数
        totalInstanceCount = arraySize.x * arraySize.y * arraySize.z;

        if (totalInstanceCount <= 0)
            return;

        // 释放旧的Buffer
        ReleaseBuffers();

        // 实例数据Buffer（每个实例16字节：float3 position + float padding）
        instanceDataBuffer = new ComputeBuffer(totalInstanceCount, 16);
        
        // 可见实例Buffer（与总实例数相同大小）
        visibleBuffer = new ComputeBuffer(totalInstanceCount, 16);
        
        // 计数器Buffer（1个uint）
        counterBuffer = new ComputeBuffer(1, sizeof(uint), ComputeBufferType.Raw);
        
        // 间接绘制参数Buffer
        argsBuffer = new ComputeBuffer(ARGS_BUFFER_SIZE, sizeof(uint), ComputeBufferType.IndirectArguments);
        
        // 初始化ArgsBuffer
        InitializeArgsBuffer();

        // 调试输出
        if (debugMode == DebugMode.LogInstanceCount)
        {
            Debug.Log($"[AdvancedArrayDistribution] 创建Buffer: 总实例数={totalInstanceCount}");
        }
    }

    /// <summary>
    /// 初始化间接绘制参数Buffer
    /// </summary>
    private void InitializeArgsBuffer()
    {
        if (mesh == null || argsBuffer == null)
            return;

        uint[] args = new uint[ARGS_BUFFER_SIZE];
        args[0] = mesh.GetIndexCount(0);        // 索引数
        args[1] = (uint)totalInstanceCount;     // 实例数量（初始为全部）
        args[2] = mesh.GetIndexStart(0);        // 起始索引位置
        args[3] = mesh.GetBaseVertex(0);        // 起始顶点位置
        args[4] = 0;                            // 起始实例位置

        argsBuffer.SetData(args);
    }

    /// <summary>
    /// 释放ComputeBuffer
    /// </summary>
    private void ReleaseBuffers()
    {
        instanceDataBuffer?.Release();
        instanceDataBuffer = null;
        
        visibleBuffer?.Release();
        visibleBuffer = null;
        
        argsBuffer?.Release();
        argsBuffer = null;
        
        counterBuffer?.Release();
        counterBuffer = null;
    }

    #endregion

    #region 更新方法

    /// <summary>
    /// 更新实例数据（通过Compute Shader生成位置）
    /// </summary>
    private void UpdateInstanceData()
    {
        if (instanceDataCompute == null || instanceDataBuffer == null)
            return;

        // 设置Compute Shader参数
        instanceDataCompute.SetInts("_ArraySize", new int[] { arraySize.x, arraySize.y, arraySize.z });
        instanceDataCompute.SetVector("_Spacing", spacing);
        instanceDataCompute.SetVector("_StartPoint", startPoint);
        instanceDataCompute.SetVector("_GlobalOffset", globalOffset);
        instanceDataCompute.SetMatrix("_LocalToWorld", transform.localToWorldMatrix);

        // 设置Buffer
        instanceDataCompute.SetBuffer(kernelGenerateInstances, "_InstanceDataBuffer", instanceDataBuffer);

        // 计算线程组数量
        int threadGroups = Mathf.CeilToInt(totalInstanceCount / 64.0f);

        // 执行Compute Shader
        instanceDataCompute.Dispatch(kernelGenerateInstances, threadGroups, 1, 1);
    }

    /// <summary>
    /// 重置计数器
    /// </summary>
    private void ResetCounter()
    {
        if (counterBuffer == null)
            return;

        uint[] zero = new uint[] { 0 };
        counterBuffer.SetData(zero);
    }

    #endregion

    #region 渲染方法

    /// <summary>
    /// 执行渲染
    /// </summary>
    private void Render()
    {
        if (mesh == null || material == null || argsBuffer == null)
            return;

        // 设置材质属性
        material.SetVector("_InstanceScale", instanceScale);
        // Material没有SetQuaternion方法，使用SetVector传递四元数
        Quaternion rotation = Quaternion.Euler(instanceRotationEuler);
        material.SetVector("_InstanceRotation", new Vector4(rotation.x, rotation.y, rotation.z, rotation.w));

        // 根据调试模式选择渲染方式
        switch (debugMode)
        {
            case DebugMode.RenderAllInstances:
                // 跳过剔除，直接绘制所有实例
                RenderAllInstances();
                break;
            
            default:
                // 正常渲染流程（当前阶段等同于RenderAllInstances）
                RenderAllInstances();
                break;
        }
    }

    /// <summary>
    /// 渲染所有实例（跳过剔除）
    /// </summary>
    private void RenderAllInstances()
    {
        // 设置实例数据Buffer到材质
        material.SetBuffer("_InstanceDataBuffer", instanceDataBuffer);

        // 更新ArgsBuffer中的实例数量
        uint[] args = new uint[ARGS_BUFFER_SIZE];
        argsBuffer.GetData(args);
        args[1] = (uint)totalInstanceCount;
        argsBuffer.SetData(args);

        // 执行间接绘制
        Graphics.DrawMeshInstancedIndirect(
            mesh,
            0,
            material,
            new Bounds(transform.position, CalculateBoundsSize()),
            argsBuffer,
            0,
            null,
            castShadows ? UnityEngine.Rendering.ShadowCastingMode.On : UnityEngine.Rendering.ShadowCastingMode.Off,
            receiveShadows,
            layer
        );
    }

    /// <summary>
    /// 计算阵列的包围盒大小
    /// </summary>
    private Vector3 CalculateBoundsSize()
    {
        Vector3 arraySizeWorld = new Vector3(
            (arraySize.x - 1) * spacing.x,
            (arraySize.y - 1) * spacing.y,
            (arraySize.z - 1) * spacing.z
        );
        
        // 添加实例本身的尺寸
        arraySizeWorld += instanceScale;
        
        // 放大包围盒以确保所有实例都在内
        return arraySizeWorld * 2.0f;
    }

    #endregion

    #region Gizmos绘制

#if UNITY_EDITOR
    private void OnDrawGizmosSelected()
    {
        if (!drawGizmos || mesh == null)
            return;

        // 绘制阵列范围
        Gizmos.color = Color.cyan;
        Vector3 arraySizeWorld = new Vector3(
            (arraySize.x - 1) * spacing.x,
            (arraySize.y - 1) * spacing.y,
            (arraySize.z - 1) * spacing.z
        );
        Vector3 center = transform.TransformPoint(startPoint + arraySizeWorld * 0.5f + globalOffset);
        Gizmos.matrix = Matrix4x4.TRS(center, transform.rotation, transform.lossyScale);
        Gizmos.DrawWireCube(Vector3.zero, arraySizeWorld + spacing);

        // 绘制实例位置点（仅在小规模时显示）
        if (totalInstanceCount <= 1000)
        {
            Gizmos.color = Color.yellow;
            Gizmos.matrix = Matrix4x4.identity;
            for (int x = 0; x < arraySize.x; x++)
            {
                for (int y = 0; y < arraySize.y; y++)
                {
                    for (int z = 0; z < arraySize.z; z++)
                    {
                        Vector3 localPos = startPoint + new Vector3(x * spacing.x, y * spacing.y, z * spacing.z) + globalOffset;
                        Vector3 worldPos = transform.TransformPoint(localPos);
                        Gizmos.DrawWireSphere(worldPos, 0.05f);
                    }
                }
            }
        }

        // 显示统计信息
        UnityEditor.Handles.Label(
            center + Vector3.up * (arraySizeWorld.y + 1),
            $"实例总数: {totalInstanceCount}"
        );
    }
#endif

    #endregion

    #region 公共方法

    /// <summary>
    /// 强制刷新Buffer
    /// </summary>
    public void RefreshBuffers()
    {
        needsBufferRecreate = true;
    }

    /// <summary>
    /// 获取阵列的实际尺寸（不含间距）
    /// </summary>
    public Vector3 GetArraySize()
    {
        return new Vector3(
            (arraySize.x - 1) * spacing.x,
            (arraySize.y - 1) * spacing.y,
            (arraySize.z - 1) * spacing.z
        );
    }

    #endregion
}
