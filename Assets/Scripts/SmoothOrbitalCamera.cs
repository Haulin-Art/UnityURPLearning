using UnityEngine;

public class AdaptiveCameraController : MonoBehaviour
{
    [Header("Follow Target")]
    public Transform target; // 需要跟随的父物体（角色）

    [Header("Mouse Rotation")]
    public float mouseSensitivity = 5.0f;
    public Vector2 upperLowerLimit = new Vector2(-30.0f, 60.0f);

    [Header("Zoom Settings")]
    public float initDistance = 5.0f;
    public float minDistance = 1.0f;   // 允许更近的距离
    public float maxDistance = 10.0f;
    public float zoomSpeed = 2.0f;

    [Header("LookAt Points (Dynamic Blending)")]
    public Vector3 bodyLookAtOffset = new Vector3(0, 0.8f, 0);   // 腰部偏移（目标位置基础上）
    public Vector3 faceLookAtOffset = new Vector3(0, 1.6f, 0);   // 面部偏移（目标位置基础上）
    public float blendStartDistance = 4.0f;  // 开始混合的远距离
    public float blendEndDistance = 2.0f;    // 完成混合的近距离

    [Header("Smoothing")]
    public float rotationSmoothTime = 0.1f;
    public float zoomSmoothTime = 0.2f;

    private float currentX;
    private float currentY;
    private float targetDistance;
    private float currentDistance;

    // 用于平滑阻尼的变量
    private Vector3 rotationSmoothVelocity;
    private float zoomSmoothVelocity;
    private Vector3 currentRotation;

    void Start()
    {
        // 初始化角度，基于相机当前的朝向
        currentX = transform.eulerAngles.y;
        currentY = transform.eulerAngles.x;
        targetDistance = initDistance;
        currentDistance = targetDistance;

        // 锁定鼠标到屏幕中心并隐藏
        Cursor.lockState = CursorLockMode.Locked;
        Cursor.visible = false;
    }

    void LateUpdate()
    {
        if (target == null)
        {
            Debug.LogWarning("AdaptiveCameraController: Target is not assigned!");
            return;
        }

        HandleMouseInput();
        UpdateCameraPosition();

        // 原有的鼠标输入处理...
        HandleMouseInput();
    
        // 按下ESC键在锁定/释放鼠标之间切换
        if (Input.GetKeyDown(KeyCode.Escape))
        {
            ToggleMouseCursor();
        }

    }

    void HandleMouseInput()
    {
        // 1. 处理鼠标右键拖拽旋转
        if (Input.GetMouseButton(1)) // 1 代表鼠标右键
        {
            currentX += Input.GetAxis("Mouse X") * mouseSensitivity;
            currentY -= Input.GetAxis("Mouse Y") * mouseSensitivity; // 注意是减号，用于反转Y轴
            currentY = Mathf.Clamp(currentY, upperLowerLimit.x, upperLowerLimit.y);
        }

        // 2. 处理鼠标滚轮缩放
        float scroll = Input.GetAxis("Mouse ScrollWheel");
        if (scroll != 0)
        {
            targetDistance -= scroll * zoomSpeed;
            targetDistance = Mathf.Clamp(targetDistance, minDistance, maxDistance);
        }
    }

    void UpdateCameraPosition()
    {
        // 使用平滑阻尼处理旋转
        Vector3 targetRotation = new Vector3(currentY, currentX);
        currentRotation = Vector3.SmoothDamp(currentRotation, targetRotation, ref rotationSmoothVelocity, rotationSmoothTime);

        // 使用平滑阻尼处理距离
        currentDistance = Mathf.SmoothDamp(currentDistance, targetDistance, ref zoomSmoothVelocity, zoomSmoothTime);

        // 将旋转角度转换为四元数
        Quaternion rotation = Quaternion.Euler(currentRotation.x, currentRotation.y, 0);

        // 计算相机的新位置：目标位置 + 旋转后的反向距离向量
        Vector3 negDistance = new Vector3(0.0f, 0.0f, -currentDistance);
        Vector3 position = rotation * negDistance + target.position;

        // 核心改进：动态计算注视点
        Vector3 finalLookAtPoint = CalculateLookAtPoint();

        // 应用变换
        transform.rotation = Quaternion.LookRotation(finalLookAtPoint - position); // 使相机看向混合后的点
        transform.position = position;
    }

    Vector3 CalculateLookAtPoint()
    {
        // 计算两个注视点的世界坐标
        Vector3 bodyLookAt = target.position + bodyLookAtOffset;
        Vector3 faceLookAt = target.position + faceLookAtOffset;

        // 根据当前距离计算混合比例
        float t = Mathf.InverseLerp(blendStartDistance, blendEndDistance, currentDistance);
        t = Mathf.Clamp01(t); // 确保t在[0,1]范围内

        // 使用Lerp平滑混合两个注视点
        return Vector3.Lerp(bodyLookAt, faceLookAt, t);
    }
    void ToggleMouseCursor()
    {
        if (Cursor.lockState == CursorLockMode.Locked)
        {
            // 切换到解锁模式，并显示鼠标（用于UI操作）
            Cursor.lockState = CursorLockMode.None;
            Cursor.visible = true;
        }
        else
        {
            // 切换回锁定模式，隐藏鼠标（返回游戏）
            Cursor.lockState = CursorLockMode.Locked;
            Cursor.visible = false; // 在Locked模式下，这行可省略，但明确设置是好习惯
        }
    }
}