using UnityEngine;
using System.Collections;

// 添加这个属性，让脚本在编辑模式下也能执行Update
[ExecuteInEditMode]
public class CameraWaterFollower : MonoBehaviour
{
    [Header("水面跟随设置")]
    public Transform waterObj;                // 要跟随的水面物体
    public Transform targetYAxisObj;           // 可选：用于跟随相机旋转的物体（如果需要水面旋转）
    public float heightOffset = 0.97f;       // 水线高度偏移
    public float smoothTime = 0.1f;         // 平滑移动时间（0表示立即移动）
    
    [Header("编辑器模式设置")]
    public bool updateInEditor = true;      // 是否在编辑器中更新
    public float editorUpdateInterval = 0.1f; // 编辑器更新间隔（秒）
    
    private Vector3 _velocity = Vector3.zero;  // 平滑速度
    private Coroutine _editorCoroutine;       // 编辑器协程
    
    private void OnEnable()
    {
        if (waterObj == null)
        {
            // 如果没有指定水面物体，使用当前物体
            waterObj = transform;
        }
        
        // 在编辑器模式下启动协程
        if (!Application.isPlaying && updateInEditor)
        {
            StartEditorCoroutine();
        }
    }
    
    private void OnDisable()
    {
        // 停止编辑器协程
        StopEditorCoroutine();
    }
    
    private void Start()
    {
        if (Application.isPlaying)
        {
            // 播放模式下直接跟随
            FollowCamera();
        }
    }
    
    private void Update()
    {
        if (Application.isPlaying)
        {
            // 播放模式下每帧跟随
            FollowCamera();
        }
    }
    
    // 编辑器协程相关
    private void StartEditorCoroutine()
    {
        StopEditorCoroutine();
        
        if (updateInEditor && gameObject.activeInHierarchy)
        {
            _editorCoroutine = StartCoroutine(EditorUpdate());
        }
    }
    
    private void StopEditorCoroutine()
    {
        if (_editorCoroutine != null)
        {
            StopCoroutine(_editorCoroutine);
            _editorCoroutine = null;
        }
    }
    
    private IEnumerator EditorUpdate()
    {
        while (!Application.isPlaying && updateInEditor)
        {
            FollowCamera();
            yield return new WaitForSeconds(editorUpdateInterval);
        }
    }
    
    // 核心跟随函数
    private void FollowCamera()
    {
        if (waterObj == null) return;
        if (targetYAxisObj != null)
        {
            // 如果指定了旋转对象，跟随其Y轴
            heightOffset = targetYAxisObj.position.y;
        }


        // 获取当前活动的相机
        Camera currentCamera = GetCurrentCamera();
        if (currentCamera == null) return;
        
        // 计算目标位置
        Vector3 targetPosition = new Vector3(
            currentCamera.transform.position.x,
            heightOffset,
            currentCamera.transform.position.z
        );
        
        // 应用平滑移动
        if (smoothTime > 0)
        {
            waterObj.transform.position = Vector3.SmoothDamp(
                waterObj.transform.position,
                targetPosition,
                ref _velocity,
                smoothTime
            );
        }
        else
        {
            waterObj.transform.position = targetPosition;
        }
    }
    
    // 获取当前活动的相机
    private Camera GetCurrentCamera()
    {
        if (Application.isPlaying)
        {
            // 播放模式下使用主相机
            return Camera.main;
        }
        else
        {
            // 编辑器模式下尝试获取Scene视图相机
            #if UNITY_EDITOR
            return GetSceneViewCamera();
            #else
            return null;
            #endif
        }
    }
    
    #if UNITY_EDITOR
    // 获取场景视图相机
    private Camera GetSceneViewCamera()
    {
        // 获取当前正在绘制的场景视图
        var sceneView = UnityEditor.SceneView.currentDrawingSceneView;
        
        if (sceneView == null)
        {
            // 如果没有当前绘制视图，尝试获取第一个可用的场景视图
            if (UnityEditor.SceneView.sceneViews.Count > 0)
            {
                sceneView = UnityEditor.SceneView.sceneViews[0] as UnityEditor.SceneView;
            }
        }
        
        return sceneView?.camera;
    }
    
    // 在Inspector中绘制自定义UI
    private void OnValidate()
    {
        // 当编辑器设置更改时，重启协程
        if (!Application.isPlaying)
        {
            StartEditorCoroutine();
        }
    }
    #endif
    
    // 重置位置到相机下方
    [ContextMenu("立即重置位置")]
    public void ResetPositionImmediately()
    {
        if (waterObj == null) return;
        
        Camera currentCamera = GetCurrentCamera();
        if (currentCamera == null) return;
        
        Vector3 camPos = currentCamera.transform.position;
        waterObj.transform.position = new Vector3(camPos.x, heightOffset, camPos.z);
        _velocity = Vector3.zero; // 重置速度
    }
    
    // 绘制Gizmo，在Scene视图中显示位置
    #if UNITY_EDITOR
    private void OnDrawGizmosSelected()
    {
        if (waterObj == null) return;
        
        // 绘制跟随的物体位置
        Gizmos.color = Color.blue;
        Gizmos.DrawWireCube(waterObj.position, new Vector3(1, 0.1f, 1));
        
        // 绘制到相机的连接线
        Camera currentCamera = GetCurrentCamera();
        if (currentCamera != null)
        {
            Gizmos.color = Color.cyan;
            Gizmos.DrawLine(waterObj.position, currentCamera.transform.position);
            
            // 绘制相机下方的目标位置
            Vector3 targetPos = new Vector3(
                currentCamera.transform.position.x,
                heightOffset,
                currentCamera.transform.position.z
            );
            Gizmos.color = Color.green;
            Gizmos.DrawWireSphere(targetPos, 0.5f);
        }
    }
    #endif
}