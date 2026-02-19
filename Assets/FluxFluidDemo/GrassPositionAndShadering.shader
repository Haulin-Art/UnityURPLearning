Shader "InfiniteGrass/GrassPositionAndShadering"
{
    // ====================================== 材质参数面板（可在Inspector中调整） ======================================
    Properties
    {
        // 主颜色纹理（草叶的基础颜色纹理）
        [MainTexture] _BaseColorTexture("BaseColor Texture", 2D) = "white" {}
        // 草叶颜色A（基础色，与ColorB插值）
        _ColorA("ColorA", Color) = (0,0,0,1)
        // 草叶颜色B（高光色，与ColorA插值）
        _ColorB("ColorB", Color) = (1,1,1,1)
        // AO颜色（环境光遮蔽色，草叶底部的暗部颜色）
        _AOColor("AO Color", Color) = (0.5,0.5,0.5)

        // 分组：草叶形状参数
        [Header(Grass Shape)][Space]
        _GrassWidth("Grass Width", Float) = 1                // 草叶基础宽度
        _GrassHeight("Grass Height", Float) = 1              // 草叶基础高度
        _GrassWidthRandomness("Grass Width Randomness", Range(0, 1)) = 0.25  // 草叶宽度随机度（0=无随机，1=最大随机）
        _GrassHeightRandomness("Grass Height Randomness", Range(0, 1)) = 0.5 // 草叶高度随机度

        _GrassCurving("Grass Curving", Float) = 0.1          // 草叶弯曲度
        [Space]
        _ExpandDistantGrassWidth("Expand Distant Grass Width", Float) = 1  // 远处草叶宽度扩展量
        _ExpandDistantGrassRange("Expand Distant Grass Range", Vector) = (50, 200, 0, 0) // 宽度扩展的距离范围（x=起始距离，y=最大距离）

        // 分组：风动参数
        [Header(Wind)][Space]
        _WindTexture("Wind Texture", 2D) = "white" {}        // 风动纹理（用于模拟动态风）
        _WindScroll("Wind Scroll", Vector) = (1, 1, 0, 0)    // 风动纹理的滚动速度（x=水平速度，y=垂直速度）
        _WindStrength("Wind Strength", Float) = 1            // 风动强度

        // 分组：光照参数
        [Header(Lighting)][Space]
        _RandomNormal("Random Normal", Range(0, 1)) = 0.1    // 法线随机度（增加光照的自然感）

        // 密度纹理（用户自定义，示例中未核心使用，可扩展密度控制）
        _DensityTexture("Density Texture", 2D) = "white" {}
        _DensityTexture_ST("Density Texture ST", Vector) = (0, 0, 0, 0)
    }

    // ====================================== 子着色器（URP 渲染逻辑） ======================================
    SubShader
    {
        // 标签：定义Shader的渲染属性
        // RenderType = Opaque：不透明物体（参与深度测试/写入）
        // RenderPipeline = UniversalPipeline：指定为URP管线
        // Queue = Geometry：渲染队列（不透明物体队列，与默认几何体同队列）
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" "Queue"="Geometry"}

        // ====================================== 前向渲染通道（URP 主渲染通道） ======================================
        Pass
        {
            Cull Back           // 背面剔除（只渲染草叶的正面，优化性能）
            ZTest Less          // 深度测试（只有像素深度小于当前深度缓冲区时才渲染）
            // 光照模式：UniversalForward（URP 前向渲染，支持主光、额外光、阴影）
            Tags { "LightMode" = "UniversalForward" }

            // ====================================== HLSL 代码块（核心渲染逻辑） ======================================
            HLSLPROGRAM
            // 顶点着色器和片元着色器的入口函数
            #pragma vertex vert
            #pragma fragment frag

            // 多编译宏：支持主光阴影（根据项目设置自动编译不同版本）
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE // 主光级联阴影（用于大场景）
            // 多编译宏：支持额外光源（点光、聚光等）
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS // 额外光源阴影
            #pragma multi_compile _ _SHADOWS_SOFT // 软阴影
            #pragma multi_compile_fog // 雾效（URP 雾效系统）

            // 包含URP的核心着色器库（提供矩阵、光照、雾效等工具函数）
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            // ====================================== 输入结构体（顶点属性） ======================================
            // 存储从Mesh传入的顶点数据（这里仅使用位置属性，草叶的Mesh通常是简单的四边形）
            struct Attributes
            {
                float4 positionOS   : POSITION; // 物体空间位置（Object Space）
            };

            // ====================================== 输出结构体（顶点到片元的插值数据） ======================================
            struct Varyings
            {
                float4 positionCS  : SV_POSITION; // 裁剪空间位置（Clip Space，必须）
                half3 color        : COLOR;       // 草叶的最终颜色（顶点阶段计算后传递给片元）
                
                float2 uv : TEXCOORD0;            // 纹理坐标（示例中未使用，可扩展）
                float4 color2 : COLOR1;           // 备用颜色（示例中未使用，可扩展）
            };

            // ====================================== 常量缓冲区（GPU 显存优化） ======================================
            // CBUFFER_START(UnityPerMaterial)：将材质参数放入常量缓冲区，减少GPU显存访问次数
            CBUFFER_START(UnityPerMaterial)
                // 颜色参数
                half3 _ColorA;
                half3 _ColorB;
                float4 _BaseColorTexture_ST; // 基础颜色纹理的缩放和平移（TRANSFORM_TEX宏使用）
                half3 _AOColor;

                // 草叶形状参数
                float _GrassWidth;
                float _GrassHeight;
                float _GrassCurving;
                float _GrassWidthRandomness;
                float _GrassHeightRandomness;

                // 远处草叶宽度扩展参数
                float _ExpandDistantGrassWidth;
                float2 _ExpandDistantGrassRange;

                // 风动参数
                float4 _WindTexture_ST; // 风动纹理的缩放和平移
                float _WindStrength;
                float2 _WindScroll;

                // 光照参数
                half _RandomNormal;

                // 从C#端传递的全局参数（与ComputeShader、RenderFeature共享）
                float2 _CenterPos;               // 纹理渲染的中心位置
                float _DrawDistance;             // 草的绘制距离
                float _TextureUpdateThreshold;   // 纹理更新阈值

                // 结构化缓冲区：存储草的世界位置（GPU实例化渲染的核心数据）
                StructuredBuffer<float3> _GrassPositions;

            CBUFFER_END

            // ====================================== 纹理采样器（全局） ======================================
            sampler2D _BaseColorTexture;    // 基础颜色纹理
            sampler2D _WindTexture;         // 风动纹理

            sampler2D _GrassColorRT;        // 地形颜色纹理（从RenderFeature传递的渲染纹理）
            sampler2D _GrassSlopeRT;        // 地形坡度纹理（从RenderFeature传递的渲染纹理）

            sampler2D _DensityTexture;      // 密度纹理（示例中未核心使用）
            float4 _DensityTexture_ST;      // 密度纹理的缩放和平移

            // ====================================== 辅助函数：单光源光照计算 ======================================
            // 计算单个光源（主光/额外光）对草叶的光照贡献
            // 参数：light=光源数据，N=法线，V=视角方向，albedo=草叶漫反射色，mask=颜色掩码（控制高光），positionY=顶点Y坐标（控制高光强度）
            half3 ApplySingleDirectLight(Light light, half3 N, half3 V, half3 albedo, half mask, half positionY)
            {
                // 计算半程向量（光源方向+视角方向的中间方向，用于高光计算）
                half3 H = normalize(light.direction + V);

                // 漫反射光照（Lambert模型：dot(N, 光源方向)，映射到0~1范围）
                half directDiffuse = dot(N, light.direction) * 0.5 + 0.5;

                // 高光反射（多次平方，模拟高光的锐利度，类似Phong模型的高光指数）
                float directSpecular = saturate(dot(N,H));
                directSpecular *= directSpecular;
                directSpecular *= directSpecular;
                directSpecular *= directSpecular;
                directSpecular *= directSpecular;

                // 高光强度随顶点Y坐标衰减（草叶顶部高光强，底部弱）
                directSpecular *= positionY * 0.12;

                // 光源的最终贡献：光源颜色 * 阴影衰减 * 距离衰减
                half3 lighting = light.color * (light.shadowAttenuation * light.distanceAttenuation);
                // 最终光照结果：漫反射 + 高光（高光受mask控制，mask=1时高光为0）
                half3 result = (albedo * directDiffuse + directSpecular * (1-mask)) * lighting;

                return result; 
            }

            // ====================================== 辅助函数：哈希函数（生成伪随机数） ======================================
            // MurmurHash3 哈希算法（简化版）：将浮点数输入转换为无符号整数哈希值
            uint murmurHash3(float input) {
                uint h = abs(input);
                h ^= h >> 16;
                h *= 0x85ebca6b;
                h ^= h >> 13;
                h *= 0xc2b2ae3d;
                h ^= h >> 16;
                return h;
            }

            // 生成0~1的伪随机数
            float random(float input) {
                return murmurHash3(input) / 4294967295.0;
            }

            // 生成-1~1的伪随机数（带符号随机数）
            float srandom(float input) {
                return (murmurHash3(input) / 4294967295.0) * 2 - 1;
            }

            // ====================================== 辅助函数：数值重映射 ======================================
            // 将输入值从 [InMinMax.x, InMinMax.y] 映射到 [OutMinMax.x, OutMinMax.y]
            float Remap(float In, float2 InMinMax, float2 OutMinMax)
            {
                return OutMinMax.x + (In - InMinMax.x) * (OutMinMax.y - OutMinMax.x) / (InMinMax.y - InMinMax.x);
            }

            // ====================================== 辅助函数：总光照计算 ======================================
            // 计算所有光源（主光+额外光+SH环境光）的总光照贡献
            float3 CalculateLighting(float3 albedo, float3 positionWS, float3 N, float3 V, float mask, float positionY){
                // 1. SH环境光（球面调和函数，低开销的全局环境光）
                half3 result = SampleSH(0) * albedo;

                // 2. 主光光照（包含阴影）
                Light mainLight = GetMainLight(TransformWorldToShadowCoord(positionWS)); // 获取主光数据（带阴影坐标）
                result += ApplySingleDirectLight(mainLight, N, V, albedo, mask, positionY);

                // 3. 额外光源光照（点光、聚光等）
                int additionalLightsCount = GetAdditionalLightsCount(); // 获取额外光源数量
                for (int i = 0; i < additionalLightsCount; ++i)
                {
                    Light light = GetAdditionalLight(i, positionWS); // 获取第i个额外光源数据
                    result += ApplySingleDirectLight(light, N, V, albedo, mask, positionY);
                }

                return result;
            }

            // ====================================== 顶点着色器（核心逻辑） ======================================
            // instanceID : SV_InstanceID：实例ID（GPU实例化渲染的核心，每个实例对应一个草叶）
            Varyings vert(Attributes IN, uint instanceID : SV_InstanceID)
            {
                Varyings OUT;

                // 1. 获取当前实例的草叶世界位置（从结构化缓冲区读取，instanceID为索引）
                float3 pivot = _GrassPositions[instanceID];

                // 2. 计算地形纹理（颜色/坡度）的采样UV坐标（与ComputeShader中的UV计算逻辑一致）
                float2 uv = (pivot.xz - _CenterPos) / (_DrawDistance + _TextureUpdateThreshold);
                uv = uv * 0.5 + 0.5; // 从[-1,1]映射到[0,1]

                // 3. 计算草叶宽度（基础宽度 + 随机化 + 远处宽度扩展）
                // 3.1 基础宽度随机化（基于草叶位置生成固定随机数，避免帧间闪烁）
                float grassWidth = _GrassWidth * (1 - random(pivot.x * 950 + pivot.z * 10) * _GrassWidthRandomness);
                // 3.2 计算草叶到相机的距离
                float distanceFromCamera = length(_WorldSpaceCameraPos - pivot);
                // 3.3 远处宽度扩展（根据距离在指定范围内线性映射，扩展宽度）
                grassWidth += saturate(Remap(distanceFromCamera, float2(_ExpandDistantGrassRange.x, _ExpandDistantGrassRange.y), float2(0, 1))) * _ExpandDistantGrassWidth;
                // 3.4 宽度随顶点Y坐标衰减（草叶底部宽，顶部窄，模拟自然形态）
                grassWidth *= (1 - IN.positionOS.y);

                // 4. 计算草叶高度（基础高度 + 随机化）
                float grassHeight = _GrassHeight * (1 - random(pivot.x * 230 + pivot.z * 10) * _GrassHeightRandomness);
                
                // 5. 广告牌（Billboard）逻辑：获取相机的世界空间变换轴（右、上、前）
                // UNITY_MATRIX_V：视图矩阵（世界→相机空间），其行向量为相机的变换轴
                float3 cameraTransformRightWS = UNITY_MATRIX_V[0].xyz;    // 相机右方向（世界空间）
                float3 cameraTransformUpWS = UNITY_MATRIX_V[1].xyz;      // 相机上方向（世界空间）
                float3 cameraTransformForwardWS = -UNITY_MATRIX_V[2].xyz;// 相机前方向（世界空间，取反因为视图矩阵的前方向是负的）

                // 6. 采样地形坡度纹理，重构草叶的生长方向（适配地形坡度）
                float4 slope = tex2Dlod(_GrassSlopeRT, float4(uv, 0, 0)); // tex2Dlod：顶点阶段纹理采样（需指定mipmap层级为0）
                float xSlope = slope.r * 2 - 1; // 坡度X分量（从0~1映射到-1~1）
                float zSlope = slope.g * 2 - 1; // 坡度Z分量
                // 重构坡度方向（Y分量随坡度大小衰减，模拟地形的陡峭度）
                float3 slopeDirection = normalize(float3(xSlope, 1 - (max(abs(xSlope), abs(zSlope)) * 0.5), zSlope));
                // 草叶的基础方向：从垂直向上lerp到坡度方向（由slope.a控制混合权重）
                float3 bladeDirection = normalize(lerp(float3(0, 1, 0), slopeDirection, slope.a));

                // 7. 风动效果：采样风动纹理，添加动态偏移
                // 风动纹理坐标：草叶位置的XZ分量 + 时间滚动（模拟风的移动）
                half3 windTex = tex2Dlod(_WindTexture, float4(TRANSFORM_TEX(pivot.xz, _WindTexture) + _WindScroll * _Time.y,0,0));
                // 风动偏移：从0~1映射到-1~1，乘以风动强度，再乘以slope.a（坡度越陡，风动越弱）
                float2 wind = (windTex.rg * 2 - 1) * _WindStrength * (1-slope.a);
                // 风动仅影响草叶的XZ方向，且随顶点Y坐标递增（草叶顶部风动更明显）
                bladeDirection.xz += wind * IN.positionOS.y;
                // 重新归一化方向，避免长度变化
                bladeDirection = normalize(bladeDirection);
                
                // 8. 计算草叶的右切线方向（用于草叶的广告牌拉伸，始终朝向相机）
                // 叉乘：草叶方向 × 相机前方向 → 得到草叶的右方向（垂直于两者）
                float3 rightTangent = normalize(cross(bladeDirection, cameraTransformForwardWS));

                // 9. 计算草叶的物体空间位置（核心：广告牌+形状缩放）
                // 草叶的高度方向：bladeDirection * 顶点Y坐标 * 草叶高度
                // 草叶的宽度方向：rightTangent * 顶点X坐标 * 草叶宽度
                float3 positionOS = bladeDirection * IN.positionOS.y * grassHeight 
                                    + rightTangent * IN.positionOS.x * grassWidth;

                // 10. 草叶弯曲效果：随顶点Y坐标的平方递增（顶部弯曲更明显）
                positionOS.xz += (IN.positionOS.y * IN.positionOS.y) * float2(
                    srandom(pivot.x * 851 + pivot.z * 10),  // X方向弯曲的随机偏移
                    srandom(pivot.z * 647 + pivot.x * 10)   // Z方向弯曲的随机偏移
                ) * _GrassCurving;

                // 11. 物体空间 → 世界空间（草叶位置 = 物体空间位置 + 草叶的世界枢轴点）
                float3 positionWS = positionOS + pivot;
                
                // 12. 世界空间 → 裁剪空间（URP工具函数，将世界位置转换为裁剪空间位置，用于渲染）
                OUT.positionCS = TransformWorldToHClip(positionWS);

                // 13. 计算草叶的基础颜色（融合基础纹理、ColorA、ColorB）
                // 采样基础颜色纹理，用R通道插值ColorA和ColorB
                half3 baseColor = lerp(_ColorA, _ColorB, tex2Dlod(_BaseColorTexture, float4(TRANSFORM_TEX(pivot.xz, _BaseColorTexture),0,0)).r);
                // 融合AO颜色：草叶底部（IN.positionOS.y=0）显示AOColor，顶部显示baseColor
                half3 albedo = lerp(_AOColor, baseColor, IN.positionOS.y);
                // 融合地形颜色纹理：根据纹理的Alpha通道插值草叶颜色和地形颜色
                float4 color = tex2Dlod(_GrassColorRT, float4(uv, 0, 0));
                albedo = lerp(albedo, color.rgb, color.a);

                // 14. 光照计算：法线+视角方向+光照总贡献
                // 法线向量：草叶方向 + 相机前方向的轻微偏移 + 随机化（增加自然感）
                half3 N = normalize(bladeDirection + cameraTransformForwardWS * -0.5 + _RandomNormal * half3(
                    srandom(pivot.x * 314 + pivot.z * 10),  // X方向法线随机
                    0,                                      // Y方向法线不随机
                    srandom(pivot.z * 677 + pivot.x * 10)   // Z方向法线随机
                ));
                // 视角方向：相机位置 → 草叶世界位置的归一化向量
                half3 V = normalize(_WorldSpaceCameraPos - positionWS);
                // 计算总光照（环境光+主光+额外光）
                // color.a：地形颜色的Alpha通道，用于控制高光（如烧焦的草叶无高光）
                float3 lighting = CalculateLighting(albedo, positionWS, N, V, color.a, IN.positionOS.y);

                // 15. 雾效：应用URP雾效（根据裁剪空间Z坐标计算雾因子，混合光照和雾色）
                float fogFactor = ComputeFogFactor(OUT.positionCS.z);
                OUT.color.rgb = MixFog(lighting, fogFactor);

                return OUT;
            }

            // ====================================== 片元着色器（简单输出） ======================================
            // 片元着色器仅输出顶点阶段计算的颜色（无额外计算，优化性能）
            half4 frag(Varyings IN) : SV_Target
            {
                return half4(IN.color.rgb, 1); // SV_Target：渲染到颜色缓冲区，Alpha=1（不透明）
            }
            ENDHLSL
        }
    }
}