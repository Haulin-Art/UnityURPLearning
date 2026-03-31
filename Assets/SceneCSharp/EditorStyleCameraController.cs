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
    [SerializeField] private float positionSmoothTime = 0.1f;
    
    [Header("旋转设置")]
    [SerializeField] private float rotationSpeed = 3f;
    [SerializeField] private float mouseSensitivity = 2f;
    [SerializeField] private bool invertY = false;
    [SerializeField] private float rotationSmoothTime = 0.05f;
    
    [Header("缩放设置")]
    [SerializeField] private float zoomSpeed = 10f;
    [SerializeField] private float minZoom = 1f;
    [SerializeField] private float maxZoom = 100f;
    
    [Header("控制设置")]
    [SerializeField] private KeyCode speedUpKey = KeyCode.LeftShift;
    [SerializeField] private KeyCode slowDownKey = KeyCode.LeftControl;
    [SerializeField] private KeyCode exitControlModeKey = KeyCode.Escape;
    
    [Header("调试设置")]
    [SerializeField] private DebugMode debugMode = DebugMode.None;
    [SerializeField] private KeyCode toggleDebugKey = KeyCode.F1;
    
    private Vector3 _currentRotation;
    private Vector3 _targetRotation;
    private Vector3 _rotationVelocity;
    
    private Vector3 _targetPosition;
    private Vector3 _positionVelocity;
    
    private float _currentZoom = 10f;
    
    // 控制模式状态
    private bool _isInControlMode = false;
    private bool _isRotating = false;
    
    // 用于检测应用焦点变化，避免编辑器参数调整后的跳弹
    private bool _wasFocused = true;
    private float _inputDisableTimer = 0f;
    private const float INPUT_DISABLE_DURATION = 0.1f;
    
    // 调试状态
    private bool _showDebugInfo = false;
    
    /// <summary>
    /// 调试模式枚举
    /// </summary>
    public enum DebugMode
    {
        None,           // 不显示调试信息
        LogInfo,        // 在Console中输出日志
        OnScreenInfo    // 在屏幕上显示信息
    }
    
    /// <summary>
    /// 当前是否处于控制模式
    /// </summary>
    public bool IsInControlMode => _isInControlMode;
    
    private void Start()
    {
        _currentRotation = transform.eulerAngles;
        _targetRotation = _currentRotation;
        _targetPosition = transform.position;
        
        // 如果附加到摄像机，则设置初始距离
        if (TryGetComponent<Camera>(out var cam))
        {
            _currentZoom = Vector3.Distance(transform.position, transform.position + transform.forward * 10f);
        }
        
        // 初始状态：自由模式
        ExitControlMode();
    }
    
    private void Update()
    {
        HandleDebugToggle();
        HandleApplicationFocus();
        HandleControlModeSwitch();
        
        // 更新输入禁用计时器
        if (_inputDisableTimer > 0)
        {
            _inputDisableTimer -= Time.unscaledDeltaTime;
        }
        
        // 只在控制模式下处理相机控制
        if (_isInControlMode && _inputDisableTimer <= 0)
        {
            HandleMovement();
            HandleRotation();
            HandleZoom();
        }
        
        ApplySmoothTransform();
        HandleDebugOutput();
    }
    
    /// <summary>
    /// 处理调试模式切换
    /// </summary>
    private void HandleDebugToggle()
    {
        if (Input.GetKeyDown(toggleDebugKey))
        {
            _showDebugInfo = !_showDebugInfo;
        }
    }
    
    /// <summary>
    /// 处理应用焦点变化，避免编辑器参数调整后的跳弹
    /// </summary>
    private void HandleApplicationFocus()
    {
        bool isFocused = Application.isFocused;
        
        // 检测焦点变化
        if (_wasFocused && !isFocused)
        {
            // 失去焦点，可能是在编辑器中操作
            _inputDisableTimer = INPUT_DISABLE_DURATION;
        }
        else if (!_wasFocused && isFocused)
        {
            // 重新获得焦点，禁用输入一小段时间
            _inputDisableTimer = INPUT_DISABLE_DURATION;
        }
        
        _wasFocused = isFocused;
    }
    
    /// <summary>
    /// 处理控制模式切换
    /// </summary>
    private void HandleControlModeSwitch()
    {
        // 按ESC退出控制模式
        if (Input.GetKeyDown(exitControlModeKey))
        {
            if (_isInControlMode)
            {
                ExitControlMode();
            }
            return;
        }
        
        // 如果不在控制模式，点击鼠标进入控制模式
        if (!_isInControlMode)
        {
            if (Input.GetMouseButtonDown(0) || Input.GetMouseButtonDown(1))
            {
                EnterControlMode();
            }
        }
    }
    
    /// <summary>
    /// 进入控制模式
    /// </summary>
    private void EnterControlMode()
    {
        _isInControlMode = true;
        Cursor.lockState = CursorLockMode.Locked;
        Cursor.visible = false;
        
        // 进入控制模式时禁用输入一小段时间，避免跳弹
        _inputDisableTimer = INPUT_DISABLE_DURATION;
        
        LogDebug("进入控制模式");
    }
    
    /// <summary>
    /// 退出控制模式
    /// </summary>
    private void ExitControlMode()
    {
        _isInControlMode = false;
        _isRotating = false;
        Cursor.lockState = CursorLockMode.None;
        Cursor.visible = true;
        
        LogDebug("退出控制模式");
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
        
        // 更新目标位置
        if (moveDirection != Vector3.zero)
        {
            moveDirection.Normalize();
            _targetPosition += moveDirection * currentSpeed * Time.deltaTime;
        }
    }
    
    /// <summary>
    /// 处理摄像机旋转
    /// </summary>
    private void HandleRotation()
    {
        // 右键按下开始旋转
        if (Input.GetMouseButtonDown(1))
        {
            _isRotating = true;
        }
        
        // 右键抬起停止旋转
        if (Input.GetMouseButtonUp(1))
        {
            _isRotating = false;
        }
        
        // 只在按住右键时旋转
        if (_isRotating && Input.GetMouseButton(1))
        {
            float mouseX = Input.GetAxis("Mouse X") * mouseSensitivity;
            float mouseY = Input.GetAxis("Mouse Y") * mouseSensitivity * (invertY ? 1 : -1);
            
            _targetRotation.x += mouseY;
            _targetRotation.y += mouseX;
            
            // 限制X轴旋转角度
            _targetRotation.x = Mathf.Clamp(_targetRotation.x, -90f, 90f);
        }
        
        // 键盘旋转（可选）
        if (Input.GetKey(KeyCode.LeftArrow))
        {
            _targetRotation.y -= rotationSpeed * Time.deltaTime * 60f;
        }
        if (Input.GetKey(KeyCode.RightArrow))
        {
            _targetRotation.y += rotationSpeed * Time.deltaTime * 60f;
        }
        if (Input.GetKey(KeyCode.UpArrow))
        {
            _targetRotation.x -= rotationSpeed * Time.deltaTime * 60f;
            _targetRotation.x = Mathf.Clamp(_targetRotation.x, -90f, 90f);
        }
        if (Input.GetKey(KeyCode.DownArrow))
        {
            _targetRotation.x += rotationSpeed * Time.deltaTime * 60f;
            _targetRotation.x = Mathf.Clamp(_targetRotation.x, -90f, 90f);
        }
    }
    
    /// <summary>
    /// 处理摄像机缩放（只在控制模式下生效）
    /// </summary>
    private void HandleZoom()
    {
        float scroll = Input.GetAxis("Mouse ScrollWheel");
        
        if (Mathf.Abs(scroll) > 0.01f)
        {
            _currentZoom -= scroll * zoomSpeed;
            _currentZoom = Mathf.Clamp(_currentZoom, minZoom, maxZoom);
            
            // 沿着摄像机前向方向移动
            _targetPosition += transform.forward * scroll * zoomSpeed;
        }
    }
    
    /// <summary>
    /// 应用平滑变换
    /// </summary>
    private void ApplySmoothTransform()
    {
        // 平滑位置
        transform.position = Vector3.SmoothDamp(
            transform.position, 
            _targetPosition, 
            ref _positionVelocity, 
            positionSmoothTime
        );
        
        // 平滑旋转
        _currentRotation = Vector3.SmoothDamp(
            _currentRotation, 
            _targetRotation, 
            ref _rotationVelocity, 
            rotationSmoothTime
        );
        
        transform.rotation = Quaternion.Euler(_currentRotation);
    }
    
    /// <summary>
    /// 处理调试输出
    /// </summary>
    private void HandleDebugOutput()
    {
        if (debugMode == DebugMode.None || !_showDebugInfo)
            return;
        
        if (debugMode == DebugMode.LogInfo)
        {
            // 只在状态变化时输出，避免刷屏
        }
    }
    
    /// <summary>
    /// 输出调试日志
    /// </summary>
    private void LogDebug(string message)
    {
        if (debugMode == DebugMode.LogInfo && _showDebugInfo)
        {
            Debug.Log($"[EditorStyleCameraController] {message}");
        }
    }
    
    /// <summary>
    /// 在屏幕上显示调试信息
    /// </summary>
    private void OnGUI()
    {
        if (debugMode != DebugMode.OnScreenInfo || !_showDebugInfo)
            return;
        
        GUILayout.BeginArea(new Rect(10, 10, 320, 220));
        GUILayout.Box($"[EditorStyleCameraController 调试信息]\n" +
                     $"控制模式: {(_isInControlMode ? "是" : "否")}\n" +
                     $"正在旋转: {_isRotating}\n" +
                     $"位置: {_targetPosition}\n" +
                     $"旋转: {_targetRotation}\n" +
                     $"缩放: {_currentZoom:F2}\n" +
                     $"光标状态: {Cursor.lockState}\n" +
                     $"应用焦点: {Application.isFocused}\n" +
                     $"输入禁用计时: {_inputDisableTimer:F3}\n" +
                     $"位置平滑速度: {_positionVelocity}\n" +
                     $"旋转平滑速度: {_rotationVelocity}");
        GUILayout.EndArea();
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
        
        _targetPosition = center + direction * radius * distanceMultiplier;
        
        // 看向目标
        Vector3 lookRotation = Quaternion.LookRotation(center - _targetPosition).eulerAngles;
        _targetRotation = lookRotation;
        _currentRotation = lookRotation;
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
        _targetPosition = position;
        _targetRotation = rotation;
        _currentRotation = rotation;
        transform.position = position;
        transform.rotation = Quaternion.Euler(rotation);
    }
    
    /// <summary>
    /// 手动进入控制模式（可从外部调用）
    /// </summary>
    public void RequestEnterControlMode()
    {
        EnterControlMode();
    }
    
    /// <summary>
    /// 手动退出控制模式（可从外部调用）
    /// </summary>
    public void RequestExitControlMode()
    {
        ExitControlMode();
    }
}
