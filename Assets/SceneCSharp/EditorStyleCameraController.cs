using UnityEngine;

/// <summary>
/// 编辑器风格的摄像机控制器
/// 在游戏运行时提供类似Scene窗口的摄像机控制
/// </summary>
public class EditorStyleCameraController : MonoBehaviour
{
    [Header("移动设置")]
    [SerializeField] private float moveSpeed = 10f;
    [SerializeField] private float fastMoveMultiplier = 3f;
    [SerializeField] private float slowMoveMultiplier = 0.3f;
    
    [Header("旋转设置")]
    [SerializeField] private float rotationSpeed = 3f;
    [SerializeField] private float mouseSensitivity = 1.5f;
    [SerializeField] private bool invertY = false;
    
    [Header("缩放设置")]
    [SerializeField] private float zoomSpeed = 10f;
    [SerializeField] private float minZoom = 1f;
    [SerializeField] private float maxZoom = 100f;
    
    [Header("其他设置")]
    [SerializeField] private KeyCode speedUpKey = KeyCode.LeftShift;
    [SerializeField] private KeyCode slowDownKey = KeyCode.LeftControl;
    [SerializeField] private bool requireRightClickToRotate = true;
    
    private Vector3 _currentRotation;
    private Vector3 _currentPosition;
    private float _currentZoom = 10f;
    
    private void Start()
    {
        _currentRotation = transform.eulerAngles;
        _currentPosition = transform.position;
        
        // 如果附加到摄像机，则设置初始距离
        if (TryGetComponent<Camera>(out var cam))
        {
            _currentZoom = Vector3.Distance(transform.position, transform.position + transform.forward * 10f);
        }
    }
    
    private void Update()
    {
        HandleMovement();
        HandleRotation();
        HandleZoom();
    }
    
    /// <summary>
    /// 处理摄像机移动
    /// </summary>
    private void HandleMovement()
    {
        float currentSpeed = moveSpeed;
        
        // 速度调整
        if (Input.GetKey(speedUpKey))
            currentSpeed *= fastMoveMultiplier;
        else if (Input.GetKey(slowDownKey))
            currentSpeed *= slowMoveMultiplier;
        
        // 计算移动方向
        Vector3 moveDirection = Vector3.zero;
        
        // WASD移动
        if (Input.GetKey(KeyCode.W))
            moveDirection += transform.forward;
        if (Input.GetKey(KeyCode.S))
            moveDirection -= transform.forward;
        if (Input.GetKey(KeyCode.A))
            moveDirection -= transform.right;
        if (Input.GetKey(KeyCode.D))
            moveDirection += transform.right;
        
        // QE上下移动
        if (Input.GetKey(KeyCode.Q) || Input.GetKey(KeyCode.PageDown))
            moveDirection -= Vector3.up;
        if (Input.GetKey(KeyCode.E) || Input.GetKey(KeyCode.PageUp))
            moveDirection += Vector3.up;
        
        // 平滑移动
        if (moveDirection != Vector3.zero)
        {
            moveDirection.Normalize();
            _currentPosition += moveDirection * currentSpeed * Time.deltaTime;
            transform.position = _currentPosition;
        }
    }
    
    /// <summary>
    /// 处理摄像机旋转
    /// </summary>
    private void HandleRotation()
    {
        // 检查是否需要右键才能旋转
        if (requireRightClickToRotate && !Input.GetMouseButton(1))
            return;
        
        // 鼠标右键旋转
        if (Input.GetMouseButton(1))
        {
            float mouseX = Input.GetAxis("Mouse X") * mouseSensitivity;
            float mouseY = Input.GetAxis("Mouse Y") * mouseSensitivity * (invertY ? 1 : -1);
            
            _currentRotation.x += mouseY;
            _currentRotation.y += mouseX;
            
            // 限制X轴旋转角度
            _currentRotation.x = Mathf.Clamp(_currentRotation.x, -90f, 90f);
            
            transform.rotation = Quaternion.Euler(_currentRotation);
            
            // 隐藏并锁定光标
            Cursor.lockState = CursorLockMode.Locked;
            Cursor.visible = false;
        }
        else
        {
            // 恢复光标
            Cursor.lockState = CursorLockMode.None;
            Cursor.visible = true;
        }
        
        // 键盘旋转（可选）
        if (Input.GetKey(KeyCode.LeftArrow))
        {
            _currentRotation.y -= rotationSpeed;
            transform.rotation = Quaternion.Euler(_currentRotation);
        }
        if (Input.GetKey(KeyCode.RightArrow))
        {
            _currentRotation.y += rotationSpeed;
            transform.rotation = Quaternion.Euler(_currentRotation);
        }
        if (Input.GetKey(KeyCode.UpArrow))
        {
            _currentRotation.x -= rotationSpeed;
            _currentRotation.x = Mathf.Clamp(_currentRotation.x, -90f, 90f);
            transform.rotation = Quaternion.Euler(_currentRotation);
        }
        if (Input.GetKey(KeyCode.DownArrow))
        {
            _currentRotation.x += rotationSpeed;
            _currentRotation.x = Mathf.Clamp(_currentRotation.x, -90f, 90f);
            transform.rotation = Quaternion.Euler(_currentRotation);
        }
    }
    
    /// <summary>
    /// 处理摄像机缩放
    /// </summary>
    private void HandleZoom()
    {
        float scroll = Input.GetAxis("Mouse ScrollWheel");
        
        if (Mathf.Abs(scroll) > 0.01f)
        {
            _currentZoom -= scroll * zoomSpeed;
            _currentZoom = Mathf.Clamp(_currentZoom, minZoom, maxZoom);
            
            // 沿着摄像机前向方向移动
            _currentPosition += transform.forward * scroll * zoomSpeed;
            transform.position = _currentPosition;
        }
    }
    
    /// <summary>
    /// 聚焦到特定物体
    /// </summary>
    public void FocusOnObject(GameObject target, float distanceMultiplier = 2f)
    {
        if (target == null) return;
        
        Bounds bounds = CalculateBounds(target);
        Vector3 center = bounds.center;
        float radius = bounds.extents.magnitude;
        
        // 计算合适的位置
        Vector3 direction = (transform.position - center).normalized;
        if (direction == Vector3.zero) direction = Vector3.back;
        
        _currentPosition = center + direction * radius * distanceMultiplier;
        transform.position = _currentPosition;
        
        // 看向目标
        transform.LookAt(center);
        _currentRotation = transform.eulerAngles;
    }
    
    /// <summary>
    /// 计算物体的包围盒
    /// </summary>
    private Bounds CalculateBounds(GameObject target)
    {
        Renderer[] renderers = target.GetComponentsInChildren<Renderer>();
        
        if (renderers.Length == 0)
            return new Bounds(target.transform.position, Vector3.one);
        
        Bounds bounds = renderers[0].bounds;
        foreach (Renderer renderer in renderers)
        {
            bounds.Encapsulate(renderer.bounds);
        }
        
        return bounds;
    }
    
    /// <summary>
    /// 重置摄像机位置和旋转
    /// </summary>
    public void ResetCamera(Vector3 position, Vector3 rotation)
    {
        _currentPosition = position;
        _currentRotation = rotation;
        transform.position = position;
        transform.rotation = Quaternion.Euler(rotation);
    }
}