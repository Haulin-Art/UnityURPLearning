Shader "Custom/ArrayDistributionInstanced_Tutorial"
{
    /*
    ╔══════════════════════════════════════════════════════════════════════════════╗
    ║                    URP GPU Instancing Shader 完全教程                          ║
    ║                                                                              ║
    ║  本Shader是一个完整的教学示例，详细讲解URP下支持GPU Instancing的PBR着色器       ║
    ║  的每一个组成部分。适合想要深入理解URP Shader开发的开发者学习。                 ║
    ╚══════════════════════════════════════════════════════════════════════════════╝

    ┌──────────────────────────────────────────────────────────────────────────────┐
    │ 第一部分：Shader整体结构概述                                                   │
    └──────────────────────────────────────────────────────────────────────────────┘

    Unity Shader文件的基本结构：
    
    Shader "Shader名称"
    {
        Properties { ... }      // 属性定义：在材质面板显示的可调参数
        SubShader { ... }       // 子着色器：实际的渲染代码
        FallBack "..."          // 备用着色器：当当前着色器不支持时使用
    }

    为什么需要这种结构？
    - Properties让美术/设计师可以在Inspector中调整参数
    - SubShader包含实际的GPU代码
    - FallBack确保兼容性，当设备不支持时降级到简单着色器

    */

    Properties
    {
        /*
        ┌──────────────────────────────────────────────────────────────────────────┐
        │ 第二部分：Properties 属性块详解                                            │
        └──────────────────────────────────────────────────────────────────────────┘

        Properties定义了在材质面板中显示的参数。语法格式：
        
        属性名 ("显示名称", 类型) = 默认值

        【属性特性 Attribute】
        Unity提供了一些特性来增强属性显示：
        
        [MainColor]     - 标记为主颜色，会被Unity自动识别
        [MainTexture]   - 标记为主纹理，会被Unity自动识别
        [HDR]           - 允许高动态范围颜色值
        [Gamma]         - 指示该值需要Gamma校正
        [PowerSlider(3)]- 使用幂次滑块，更适合大范围值
        [IntRange]      - 将Range显示为整数
        [Enum]          - 使用枚举下拉框
        [Toggle]        - 开关切换
        [KeywordEnum]   - 枚举并自动定义shader关键字
        [Space(10)]     - 添加垂直间距
        [Header("标题")] - 添加分组标题


        【常用属性类型】
        
        Color       - 颜色值，显示为颜色选择器
        2D          - 2D纹理
        Range(min, max) - 浮点数滑块
        Float       - 浮点数输入框
        Int         - 整数输入框
        Vector      - 四维向量
        3D          - 3D纹理（用于体积渲染）
        Cube        - 立方体贴图（用于环境反射）

        */

        // [MainColor] 特性告诉Unity这是主颜色属性
        // 当脚本访问 material.color 时会自动引用这个属性
        [MainColor] _BaseColor ("基础颜色", Color) = (1, 1, 1, 1)

        // [MainTexture] 特性告诉Unity这是主纹理属性
        // 当脚本访问 material.mainTexture 时会自动引用这个属性
        [MainTexture] _BaseMap ("基础纹理", 2D) = "white" {}

        // Range类型创建一个滑块，值限制在0到1之间
        // 适合需要限制范围的参数，如金属度、光滑度
        _Metallic ("金属度", Range(0, 1)) = 0
        _Smoothness ("光滑度", Range(0, 1)) = 0.5
    }

    SubShader
    {
        /*
        ┌──────────────────────────────────────────────────────────────────────────┐
        │ 第三部分：SubShader 和 Tags 详解                                          │
        └──────────────────────────────────────────────────────────────────────────┘

        【什么是SubShader？】
        
        一个Shader可以包含多个SubShader，Unity会从上到下选择第一个
        能够在当前硬件上运行的SubShader。这允许你为不同性能级别的
        硬件提供不同复杂度的着色器版本。

        【Tags 标签系统】
        
        Tags是键值对，告诉Unity如何以及何时渲染这个着色器。

        常用Tags：
        
        "RenderType" = "Opaque"          - 不透明物体
        "RenderType" = "Transparent"     - 透明物体
        "RenderType" = "TransparentCutout"- Alpha Test透明
        "Queue" = "Geometry"             - 渲染队列：几何体（默认2000）
        "Queue" = "Transparent"          - 渲染队列：透明（3000+）
        "Queue" = "AlphaTest"            - 渲染队列：Alpha测试（2450）
        "Queue" = "Overlay"              - 渲染队列：覆盖（4000）
        "RenderPipeline" = "UniversalPipeline" - 指定URP渲染管线
        "IgnoreProjector" = "True"       - 忽略投影器

        【渲染队列顺序】
        
        Background (1000)  -> 背景
        Geometry (2000)    -> 不透明物体
        AlphaTest (2450)   -> Alpha测试物体
        Transparent (3000) -> 透明物体
        Overlay (4000)     -> 覆盖层（如UI）

        数字越小越先渲染。先渲染的物体会写入深度缓冲，
        后渲染的物体可以通过深度测试来避免过度绘制。

        【LOD (Level of Detail)】
        
        LOD值用于根据设备性能选择不同复杂度的SubShader。
        可以在Quality Settings中设置最大LOD值。
        LOD 100 表示这个着色器的复杂度级别为100。

        */

        Tags 
        { 
            "RenderType" = "Opaque"           // 标记为不透明物体
            "RenderPipeline" = "UniversalPipeline"  // 指定使用URP渲染管线
        }
        LOD 100

        /*
        ┌──────────────────────────────────────────────────────────────────────────┐
        │ 第四部分：Pass 详解                                                        │
        └──────────────────────────────────────────────────────────────────────────┘

        【什么是Pass？】
        
        Pass是一次完整的渲染过程。一个SubShader可以包含多个Pass，
        每个Pass都会让物体被渲染一次。

        常见的Pass类型：
        
        1. ForwardLit (UniversalForward) - 前向渲染Pass，计算光照
        2. ShadowCaster - 阴影投射Pass，将物体渲染到阴影贴图
        3. DepthOnly - 深度预渲染Pass，用于深度预处理
        4. DepthNormals - 深度法线Pass，用于某些后处理效果
        5. Meta - 光照贴图烘焙Pass

        【URP的LightMode Tags】
        
        URP使用LightMode tag来标识Pass的用途：
        
        "UniversalForward"     - 前向渲染主Pass
        "ShadowCaster"         - 阴影投射
        "DepthOnly"            - 仅深度
        "DepthNormals"         - 深度和法线
        "UniversalGBuffer"     - 延迟渲染G-Buffer
        "Universal2D"          - 2D渲染

        */

        Pass
        {
            // Pass名称，可以在其他地方引用
            Name "ForwardLit"

            // LightMode tag告诉URP这个Pass的用途
            // "UniversalForward" 是URP前向渲染的主Pass
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            /*
            ┌──────────────────────────────────────────────────────────────────────────┐
            │ 第五部分：HLSL 基础与编译指令                                              │
            └──────────────────────────────────────────────────────────────────────────┘

            【HLSL vs CG】
            
            旧版Shader使用CG语言（CGPROGRAM/ENDCG）
            URP推荐使用HLSL（HLSLPROGRAM/ENDHLSL）
            
            HLSL优势：
            - 更好的跨平台支持
            - 与DirectX HLSL语法一致
            - 支持更多现代GPU特性

            【编译指令 #pragma】
            
            #pragma 指令告诉Unity如何编译着色器：

            #pragma vertex vert    - 指定顶点着色器函数名为"vert"
            #pragma fragment frag  - 指定片元着色器函数名为"frag"

            【multi_compile 和 shader_feature】
            
            这两个指令用于创建着色器变体（Shader Variants）。
            每个变体是一个独立编译的着色器版本。

            multi_compile：
            - 所有变体都会被编译并包含在构建中
            - 运行时可以切换
            - 适合需要运行时切换的功能

            shader_feature：
            - 只编译材质实际使用的变体
            - 减少构建大小
            - 但运行时不能动态切换

            【变体关键字格式】
            
            #pragma multi_compile KEYWORD1 KEYWORD2 KEYWORD3
            - 创建3个变体，分别启用KEYWORD1、KEYWORD2、KEYWORD3
            
            #pragma multi_compile _ KEYWORD
            - 下划线表示"无关键字"版本
            - 创建2个变体：默认版本和KEYWORD版本

            */

            // ========== 编译指令 ==========

            // 基础着色器函数声明
            #pragma vertex vert
            #pragma fragment frag

            /*
            【GPU Instancing 核心】
            
            #pragma multi_compile_instancing
            
            这是使用Graphics.DrawMeshInstanced()必须的！
            
            它会生成两个着色器变体：
            1. 普通版本 - 不使用实例化
            2. INSTANCING_ON版本 - 启用实例化

            启用实例化后，Unity会自动：
            - 在顶点着色器中提供UNITY_VERTEX_INPUT_INSTANCE_ID
            - 提供访问每个实例属性的宏
            - 支持通过矩阵数组批量渲染

            为什么需要GPU Instancing？
            - 传统方式：每个物体一次Draw Call
            - Instancing：一次Draw Call渲染多个相同网格
            - 性能提升：减少CPU-GPU通信开销
            - 限制：最多1023个实例/批次（Unity限制）
            */
            #pragma multi_compile_instancing

            /*
            【主光源阴影变体】
            
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            
            创建4个变体：
            1. _ (无阴影) - 主光源不投射阴影
            2. _MAIN_LIGHT_SHADOWS - 主光源阴影（单一阴影贴图）
            3. _MAIN_LIGHT_SHADOWS_CASCADE - 级联阴影（用于大场景）
            4. _MAIN_LIGHT_SHADOWS_SCREEN - 屏幕空间阴影（URP 11+）

            级联阴影(CSM)原理：
            - 将视锥体分成多个级联区域
            - 近处使用高分辨率阴影
            - 远处使用低分辨率阴影
            - 解决阴影锯齿问题
            */
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN

            /*
            【额外光源支持】
            
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            
            3个变体：
            1. _ - 不计算额外光源
            2. _ADDITIONAL_LIGHTS_VERTEX - 在顶点着色器计算额外光源（性能更好）
            3. _ADDITIONAL_LIGHTS - 在片元着色器计算额外光源（质量更高）

            额外光源 = 主光源（Directional Light）之外的光源
            - Point Light（点光源）
            - Spot Light（聚光灯）
            */
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS

            /*
            【额外光源阴影】
            
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            
            _fragment后缀表示这个关键字只在片元着色器中有效
            启用后，额外光源也能投射阴影
            */
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS

            /*
            【软阴影】
            
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            
            软阴影使用PCF（Percentage Closer Filtering）技术
            对阴影贴图进行多次采样并平均，产生柔和的阴影边缘
            */
            #pragma multi_compile_fragment _ _SHADOWS_SOFT

            /*
            【混合光照】
            
            #pragma multi_compile _ _MIXED_LIGHTING_SUBTRACTIVE
            
            用于混合光照模式（Baked + Realtime）
            Subtractive模式：实时主光源 + 烘焙的额外光源
            */
            #pragma multi_compile _ _MIXED_LIGHTING_SUBTRACTIVE

            /*
            【光照贴图】
            
            #pragma multi_compile _ LIGHTMAP_ON
            
            启用光照贴图支持
            光照贴图是预烘焙的静态光照信息
            */
            #pragma multi_compile _ LIGHTMAP_ON

            /*
            【雾效】
            
            #pragma multi_compile_fog
            
            自动添加雾效相关变体：FOG_LINEAR, FOG_EXP, FOG_EXP2
            根据Rendering Settings中的雾效设置自动选择
            */
            #pragma multi_compile_fog

            /*
            ┌──────────────────────────────────────────────────────────────────────────┐
            │ 第六部分：Include 文件详解                                                 │
            └──────────────────────────────────────────────────────────────────────────┘

            【什么是Include文件？】
            
            Include文件类似于C语言的#include，将其他文件的内容插入到当前位置。
            Unity和URP提供了大量预定义的Include文件，包含常用的函数、宏和结构体。

            【URP核心Include文件】
            
            Core.hlsl - 核心库
            - 空间变换函数（物体空间->世界空间->裁剪空间）
            - 纹理采样宏
            - 通用辅助函数
            
            Lighting.hlsl - 光照库
            - 光照计算函数
            - 阴影采样函数
            - PBR相关函数
            - Light、InputData、SurfaceData结构体

            【为什么要用Include？】
            1. 避免重复代码
            2. 使用Unity提供的优化实现
            3. 自动处理平台差异
            4. 获得最新功能更新

            【路径说明】
            
            Packages/com.unity.render-pipelines.universal/ShaderLibrary/
            - 这是URP包内的标准路径
            - Unity会自动解析这个路径

            */

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            /*
            ┌──────────────────────────────────────────────────────────────────────────┐
            │ 第七部分：结构体定义详解                                                   │
            └──────────────────────────────────────────────────────────────────────────┘

            【GPU渲染管线流程】
            
            顶点数据 -> 顶点着色器 -> 光栅化 -> 片元着色器 -> 输出颜色

            【Attributes 结构体（顶点输入）】
            
            这是顶点着色器的输入，包含网格的原始顶点数据。
            每个字段后面的冒号和全大写名称是"语义"(Semantic)，
            告诉GPU这个数据的用途。

            常用语义：
            - POSITION    : 顶点位置
            - NORMAL      : 顶点法线
            - TANGENT     : 顶点切线
            - TEXCOORD0   : 纹理坐标0（UV）
            - TEXCOORD1   : 纹理坐标1（可用于光照贴图UV）
            - COLOR       : 顶点颜色

            */

            struct Attributes
            {
                // 物体空间位置
                // float4而不是float3是因为GPU对齐要求，w分量通常为1
                float4 positionOS : POSITION;

                // 物体空间法线
                // 用于光照计算
                float3 normalOS : NORMAL;

                // 物体空间切线
                // float4的w分量存储副切线的方向符号（+1或-1）
                // 切线和副切线用于法线贴图变换
                float4 tangentOS : TANGENT;

                // 纹理坐标（UV）
                // 用于采样纹理
                float2 uv : TEXCOORD0;

                // 光照贴图UV
                // 用于采样烘焙的光照贴图
                float2 lightmapUV : TEXCOORD1;

                /*
                【GPU Instancing 关键宏】
                
                UNITY_VERTEX_INPUT_INSTANCE_ID
                
                这个宏展开后是一个uint instanceID变量。
                在GPU Instancing中，每个实例都有唯一的ID。
                
                展开后的代码类似于：
                uint instanceID : SV_InstanceID;
                
                通过这个ID，着色器可以访问每个实例的属性（如变换矩阵）。
                */
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            /*
            【Varyings 结构体（顶点到片元的数据传递）】
            
            Varyings是顶点着色器输出、片元着色器输入的数据结构。
            数据会在光栅化过程中进行插值。

            为什么叫Varyings？
            - 因为这些值在三角形内部是变化的（插值）
            - 与uniform（全局统一值）相对

            TEXCOORD0-7 是通用的插值寄存器，可以存储任意数据。
            */

            struct Varyings
            {
                // 裁剪空间位置
                // SV_POSITION是系统值语义，告诉GPU这是屏幕位置
                // GPU使用这个值进行裁剪和屏幕映射
                float4 positionCS : SV_POSITION;

                // 纹理坐标
                float2 uv : TEXCOORD0;

                // 世界空间位置
                // 用于光照计算、阴影采样、雾效等
                float3 positionWS : TEXCOORD1;

                // 世界空间法线
                // 用于光照计算
                float3 normalWS : TEXCOORD2;

                // 世界空间切线
                // w分量存储副切线的方向符号
                // 用于构建TBN矩阵（法线贴图）
                float4 tangentWS : TEXCOORD3;

                // 雾效因子
                // 用于在片元着色器中计算雾效
                float fogFactor : TEXCOORD4;

                // 光照贴图UV
                float2 lightmapUV : TEXCOORD5;

                // GPU Instancing：传递实例ID到片元着色器
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            /*
            ┌──────────────────────────────────────────────────────────────────────────┐
            │ 第八部分：纹理与采样器声明                                                 │
            └──────────────────────────────────────────────────────────────────────────┘

            【URP中的纹理声明方式】
            
            传统方式（Built-in RP）：
            sampler2D _MainTex;
            
            URP方式：
            TEXTURE2D(_BaseMap);        // 声明纹理
            SAMPLER(sampler_BaseMap);   // 声明采样器

            为什么要分开声明？
            1. 现代API（DX11+, Vulkan, Metal）将纹理和采样器分离
            2. 允许一个纹理使用多种采样方式
            3. 更好的性能和灵活性

            【采样器类型】
            - sampler_BaseMap     : 标准采样器
            - sampler_BaseMap_clamp: Clamp模式采样器
            - sampler_BaseMap_trilinear: 三线性过滤采样器

            */

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            /*
            ┌──────────────────────────────────────────────────────────────────────────┐
            │ 第九部分：CBUFFER 与 SRP Batcher                                          │
            └──────────────────────────────────────────────────────────────────────────┘

            【什么是CBUFFER？】
            
            CBUFFER (Constant Buffer) 是GPU内存中的一块区域，
            用于存储着色器需要的常量数据。

            【SRP Batcher】
            
            SRP Batcher是Unity的可编程渲染管线优化技术。
            它通过减少Draw Call之间的CPU设置开销来提升性能。

            SRP Batcher要求：
            1. 所有材质属性必须在CBUFFER_START(UnityPerMaterial)中声明
            2. CBUFFER名称必须是"UnityPerMaterial"
            3. 不能使用MaterialPropertyBlock

            【为什么SRP Batcher能提升性能？】
            
            不使用SRP Batcher：
            每个Draw Call -> CPU设置材质属性 -> GPU渲染
            
            使用SRP Batcher：
            材质属性存储在GPU常量缓冲区
            CPU只需告诉GPU使用哪个缓冲区索引
            大幅减少CPU-GPU通信

            【数据类型选择】
            
            float  - 32位浮点数
            half   - 16位浮点数（移动端优化）
            real   - 根据平台自动选择float或half

            颜色和简单参数用half可以提升性能。
            位置计算通常需要float精度。

            */

            CBUFFER_START(UnityPerMaterial)
                // _ST后缀是Unity约定：Scale(缩放)和Translation(偏移)
                // xy分量：纹理缩放
                // zw分量：纹理偏移
                float4 _BaseMap_ST;

                // 颜色使用half精度足够
                half4 _BaseColor;

                // 金属度和光滑度范围0-1，half精度足够
                half _Metallic;
                half _Smoothness;
            CBUFFER_END

            /*
            ┌──────────────────────────────────────────────────────────────────────────┐
            │ 第十部分：顶点着色器详解                                                   │
            └──────────────────────────────────────────────────────────────────────────┘

            【顶点着色器的作用】
            
            1. 将顶点从物体空间变换到裁剪空间
            2. 传递数据给片元着色器
            3. 计算逐顶点的值（如雾效因子）

            【坐标空间变换流程】
            
            物体空间 -> 世界空间 -> 视空间 -> 裁剪空间 -> NDC -> 屏幕空间

            物体空间：模型自身的坐标系
            世界空间：场景的全局坐标系
            视空间：以摄像机为原点的坐标系
            裁剪空间：用于裁剪和投影的空间
            NDC(Normalized Device Coordinates)：标准化设备坐标
            屏幕空间：最终的像素坐标

            */

            Varyings vert(Attributes input)
            {
                Varyings output;

                /*
                【GPU Instancing 宏详解】
                
                UNITY_SETUP_INSTANCE_ID(input)
                - 从input中提取instanceID
                - 设置全局实例索引
                - 后续的宏调用会使用这个索引
                
                展开后类似于：
                uint instanceID = input.instanceID;
                UnitySetupCompoundMatrices(instanceID);

                UNITY_TRANSFER_INSTANCE_ID(input, output)
                - 将instanceID从input复制到output
                - 片元着色器需要这个ID来访问实例属性

                为什么片元着色器也需要实例ID？
                - 某些实例属性可能在片元着色器中使用
                - 如每个实例不同的颜色
                */
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);

                /*
                【GetVertexPositionInputs 函数详解】
                
                这个函数一次性计算顶点在各个空间的位置：
                
                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                
                返回结构体包含：
                - positionWS : 世界空间位置
                - positionVS : 视空间位置
                - positionCS : 裁剪空间位置
                - positionNDC : NDC坐标

                内部实现（简化）：
                positionWS = mul(unity_ObjectToWorld, positionOS);
                positionVS = mul(unity_MatrixV, positionWS);
                positionCS = mul(unity_MatrixVP, positionWS);

                为什么使用这个函数而不是手动计算？
                1. 自动处理GPU Instancing的矩阵
                2. 平台兼容性处理
                3. 代码更简洁
                */
                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);

                /*
                【GetVertexNormalInputs 函数详解】
                
                类似于位置变换，但专门处理法线和切线：
                
                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);
                
                返回结构体包含：
                - normalWS : 世界空间法线
                - tangentWS : 世界空间切线
                - bitangentWS : 世界空间副切线

                法线变换的特殊性：
                - 法线不能直接用模型矩阵变换
                - 需要使用逆转置矩阵
                - unity_WorldToObject就是模型矩阵的逆
                
                数学原理：
                如果点变换是 P' = M * P
                则法线变换是 N' = (M^-1)^T * N
                */
                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);

                // 将计算结果存入输出结构体
                output.positionCS = vertexInput.positionCS;
                output.positionWS = vertexInput.positionWS;
                output.normalWS = normalInput.normalWS;

                /*
                【副切线计算】
                
                切线空间的三个轴：
                - T (Tangent)   : 切线方向
                - B (Bitangent) : 副切线方向
                - N (Normal)    : 法线方向

                副切线可以通过法线和切线的叉积得到：
                B = cross(N, T) * sign

                sign存储在tangentOS.w中，值为+1或-1
                这是因为切线方向可能需要翻转以匹配纹理UV方向。

                GetOddNegativeScale()处理模型缩放为负值的情况。
                当模型有奇数个负缩放时，需要翻转副切线。
                */
                real sign = input.tangentOS.w * GetOddNegativeScale();
                output.tangentWS = float4(normalInput.tangentWS.xyz, sign);

                /*
                【TRANSFORM_TEX 宏】
                
                TRANSFORM_TEX(uv, textureName)
                
                展开后：
                uv * textureName_ST.xy + textureName_ST.zw
                
                这就是为什么纹理属性需要_ST后缀！
                - xy：缩放
                - zw：偏移

                这样可以在材质面板中调整纹理的缩放和偏移。
                */
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);

                /*
                【ComputeFogFactor 函数】
                
                计算雾效因子，用于在片元着色器中混合雾颜色。

                参数是裁剪空间的深度值（z分量）。
                返回值根据雾效模式不同：
                - Linear：线性插值因子
                - Exponential：指数衰减因子

                雾效在片元着色器中应用：
                finalColor = lerp(fogColor, objectColor, fogFactor);
                */
                output.fogFactor = ComputeFogFactor(vertexInput.positionCS.z);

                /*
                【光照贴图UV变换】
                
                unity_LightmapST是Unity内置的光照贴图缩放偏移值。
                与纹理UV类似，需要对光照贴图UV进行变换。
                */
                output.lightmapUV = input.lightmapUV * unity_LightmapST.xy + unity_LightmapST.zw;

                return output;
            }

            /*
            ┌──────────────────────────────────────────────────────────────────────────┐
            │ 第十一部分：片元着色器详解                                                 │
            └──────────────────────────────────────────────────────────────────────────┘

            【片元着色器的作用】
            
            1. 计算每个像素的最终颜色
            2. 处理纹理采样
            3. 计算光照
            4. 应用雾效等后处理效果

            【SV_Target 语义】
            
            SV_Target表示输出到渲染目标（通常是屏幕）
            等同于DX9的COLOR语义

            */

            half4 frag(Varyings input) : SV_Target
            {
                // GPU Instancing：在片元着色器中设置实例ID
                // 如果需要访问实例属性，这是必须的
                UNITY_SETUP_INSTANCE_ID(input);

                /*
                【纹理采样】
                
                SAMPLE_TEXTURE2D(textureName, samplerName, uv)
                
                这是URP的纹理采样宏，展开后根据平台不同：
                - DX11: textureName.Sample(samplerName, uv)
                - GLES: texture2D(textureName, uv)
                
                返回值是rgba四分量颜色。
                */
                half4 albedoAlpha = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);

                // 分离RGB和Alpha通道
                // albedo是基础颜色（漫反射颜色）
                // alpha用于透明度（本shader不使用）
                half3 albedo = albedoAlpha.rgb * _BaseColor.rgb;
                half alpha = albedoAlpha.a * _BaseColor.a;

                /*
                【法线贴图处理】
                
                这里我们使用默认法线（指向Z轴正方向），
                因为这个shader没有法线贴图属性。

                如果有法线贴图，需要：
                1. 采样法线贴图
                2. 将法线从切线空间变换到世界空间

                法线贴图通常存储的是切线空间的法线：
                - RGB值范围0-1
                - 需要解码为-1到1范围
                - UnpackNormal()函数做这个工作
                */
                half3 normalTS = half3(0, 0, 1);

                /*
                【TBN矩阵构建】
                
                TBN矩阵用于在切线空间和世界空间之间变换法线。

                T (Tangent)   : 纹理U方向
                B (Bitangent) : 纹理V方向
                N (Normal)    : 表面法线方向

                TBN = | Tx Bx Nx |
                      | Ty By Ny |
                      | Tz Bz Nz |

                世界空间法线 = TBN * 切线空间法线
                */
                float sgn = input.tangentWS.w;
                float3 bitangent = sgn * cross(input.normalWS.xyz, input.tangentWS.xyz);
                float3x3 tangentToWorld = float3x3(input.tangentWS.xyz, bitangent.xyz, input.normalWS.xyz);

                // 将切线空间法线变换到世界空间
                half3 normalWS = TransformTangentToWorld(normalTS, tangentToWorld);
                normalWS = normalize(normalWS);  // 重新归一化

                /*
                【InputData 结构体】
                
                InputData是URP定义的结构体，包含光照计算需要的所有输入数据。
                
                主要字段：
                - positionWS : 世界空间位置
                - normalWS : 世界空间法线
                - viewDirectionWS : 视线方向（从像素指向摄像机）
                - shadowCoord : 阴影坐标（用于采样阴影贴图）
                - fogCoord : 雾效坐标
                - bakedGI : 烘焙的全局光照
                - normalizedScreenSpaceUV : 屏幕空间UV（用于屏幕空间阴影）
                - shadowMask : 阴影遮罩（用于混合光照）
                */
                InputData inputData = (InputData)0;
                inputData.positionWS = input.positionWS;
                inputData.normalWS = normalWS;

                /*
                【GetWorldSpaceNormalizeViewDir 函数】
                
                计算从像素到摄像机的归一化方向向量。
                
                viewDirection = normalize(cameraPosition - pixelPosition)
                
                用于：
                - 高光计算
                - Fresnel效果
                - 边缘光
                */
                inputData.viewDirectionWS = GetWorldSpaceNormalizeViewDir(input.positionWS);

                /*
                【TransformWorldToShadowCoord 函数】
                
                将世界空间位置变换到阴影贴图空间。
                阴影贴图是从光源视角渲染的深度图，
                需要将像素位置变换到光源空间才能采样。

                对于级联阴影，这个函数还会选择合适的级联级别。
                */
                inputData.shadowCoord = TransformWorldToShadowCoord(input.positionWS);

                inputData.fogCoord = input.fogFactor;

                /*
                【SampleSH 函数 - 球谐光照】
                
                球谐光照用于计算环境光照。
                
                什么是球谐函数？
                - 一种用少量系数表示球面函数的数学方法
                - Unity用3阶球谐（9个系数）表示环境光
                - 存储在unity_SHAr, unity_SHAg, unity_SHAb等变量中

                为什么用球谐？
                - 烘焙的光照探针用球谐存储
                - 运行时计算速度快
                - 可以表示低频的环境光照

                SampleSH函数根据法线方向采样球谐系数，
                返回该方向的环境光颜色。
                */
                inputData.bakedGI = SampleSH(input.normalWS);

                /*
                【GetNormalizedScreenSpaceUV 函数】
                
                计算归一化的屏幕空间UV坐标。
                范围是0-1，从屏幕左下角到右上角。

                用于：
                - 屏幕空间阴影
                - 屏幕空间反射
                - 后处理效果
                */
                inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(input.positionCS);

                /*
                【SAMPLE_SHADOWMASK 宏】
                
                采样阴影遮罩贴图。
                阴影遮罩用于混合光照模式：
                - 静态物体阴影来自烘焙
                - 动态物体阴影来自实时阴影
                - 阴影遮罩决定使用哪个
                */
                inputData.shadowMask = SAMPLE_SHADOWMASK(input.lightmapUV);

                /*
                【SurfaceData 结构体】
                
                SurfaceData包含描述表面属性的数据。
                URP的PBR函数使用这些数据计算光照。

                主要字段：
                - albedo : 基础颜色（漫反射）
                - metallic : 金属度（0=电介质，1=金属）
                - specular : 高光颜色（非金属工作流通常不使用）
                - smoothness : 光滑度（0=粗糙，1=光滑）
                - normalTS : 切线空间法线
                - emission : 自发光
                - occlusion : 遮蔽
                - alpha : 透明度
                */
                SurfaceData surfaceData = (SurfaceData)0;
                surfaceData.albedo = albedo;
                surfaceData.metallic = _Metallic;
                surfaceData.smoothness = _Smoothness;
                surfaceData.normalTS = normalTS;
                surfaceData.alpha = alpha;

                /*
                【UniversalFragmentPBR 函数 - PBR光照计算核心】
                
                这是URP的PBR光照计算主函数。
                它实现了基于物理的渲染（Physically Based Rendering）。

                PBR的核心原理：
                1. 能量守恒：反射光不能超过入射光
                2. 微表面理论：表面由微小镜面组成
                3. 菲涅尔效应：掠射角反射更强

                函数内部计算：
                1. 直接光照（主光源 + 额外光源）
                   - 漫反射
                   - 高光反射
                   - 可见性（阴影）

                2. 间接光照（环境光）
                   - 漫反射环境光
                   - 高光环境光

                返回值：最终的颜色（带alpha）
                */
                half4 color = UniversalFragmentPBR(inputData, surfaceData);

                /*
                【MixFog 函数 - 应用雾效】
                
                将雾颜色混合到最终颜色中。
                
                混合公式：
                finalColor = lerp(fogColor, objectColor, fogFactor)
                
                fogFactor由雾效模式决定：
                - Linear: fogFactor = (end - distance) / (end - start)
                - Exp: fogFactor = exp(-density * distance)
                - Exp2: fogFactor = exp(-(density * distance)^2)
                */
                color.rgb = MixFog(color.rgb, inputData.fogCoord);

                return color;
            }
            ENDHLSL
        }

        /*
        ┌──────────────────────────────────────────────────────────────────────────┐
        │ 第十二部分：ShadowCaster Pass 详解                                        │
        └──────────────────────────────────────────────────────────────────────────┘

        【什么是ShadowCaster Pass？】
        
        ShadowCaster Pass用于将物体渲染到阴影贴图中。
        当光源投射阴影时，Unity会：
        1. 从光源视角渲染场景
        2. 将深度值写入阴影贴图
        3. 在正常渲染时采样阴影贴图判断是否在阴影中

        【为什么需要单独的Pass？】
        
        1. 不需要计算光照，只需要深度
        2. 渲染状态不同（如ColorMask 0）
        3. 可以优化性能

        【渲染状态设置】
        
        ZWrite On     : 写入深度缓冲
        ZTest LEqual  : 深度测试通过条件：新像素深度 <= 缓冲深度
        ColorMask 0   : 不写入任何颜色通道，只写深度

        【使用URP内置函数】
        
        ShadowPassVertex 和 ShadowPassFragment 是URP提供的内置函数，
        处理了阴影渲染的所有细节：
        - 偏移（Shadow Bias）防止阴影瑕疵
        - 不同光源类型的阴影渲染
        */
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"

            ENDHLSL
        }

        /*
        ┌──────────────────────────────────────────────────────────────────────────┐
        │ 第十三部分：DepthOnly Pass 详解                                           │
        └──────────────────────────────────────────────────────────────────────────┘

        【什么是DepthOnly Pass？】
        
        DepthOnly Pass用于深度预渲染。
        在渲染不透明物体之前，先渲染整个场景的深度。

        【为什么需要深度预渲染？】
        
        1. 优化Overdraw（过度绘制）
           - 先渲染深度，再渲染颜色
           - 只有可见的像素才会计算光照
           - 减少片元着色器执行次数

        2. 某些效果需要深度信息
           - 屏幕空间环境光遮蔽（SSAO）
           - 屏幕空间反射（SSR）
           - 后处理效果

        【URP渲染流程】
        
        1. Depth Prepass (DepthOnly)
           - 渲染深度到深度纹理
        2. Opaque Pass (ForwardLit)
           - 渲染不透明物体
           - 使用深度测试避免Overdraw
        3. Transparent Pass
           - 渲染透明物体
        4. Post Processing
           - 后处理效果

        【LitInput.hlsl 的作用】
        
        LitInput.hlsl包含了Lit着色器需要的输入定义：
        - 纹理和采样器声明
        - CBUFFER定义
        - SurfaceData初始化函数

        这样ShadowCaster和DepthOnly Pass可以复用这些定义。
        */
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }

            ZWrite On
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthOnlyPass.hlsl"

            ENDHLSL
        }
    }

    /*
    ┌──────────────────────────────────────────────────────────────────────────┐
    │ 第十四部分：FallBack 备用着色器                                            │
    └──────────────────────────────────────────────────────────────────────────┘

    【什么是FallBack？】
    
    当当前设备的GPU不支持这个Shader的所有特性时，
    Unity会尝试使用FallBack指定的着色器。

    【为什么需要FallBack？】
    
    1. 兼容性：确保在所有设备上都能显示
    2. 性能：低端设备可以使用更简单的着色器
    3. 功能：某些功能不支持时有替代方案

    【常见的FallBack选择】
    
    "Hidden/Universal Render Pipeline/FallbackError" - URP错误着色器（显示粉色）
    "Universal Render Pipeline/Lit" - URP标准Lit着色器
    "Diffuse" - 内置漫反射着色器
    "VertexLit" - 内置顶点光照着色器（最简单）
    */
    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}
