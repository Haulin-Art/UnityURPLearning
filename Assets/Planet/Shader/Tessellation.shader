Shader "Unlit/Tessellation"
{
    Properties
    {
        // 1. 细分控制
        _TessFactor ("Tessellation Factor", Range(1, 32)) = 8
        // 2. 平滑强度（沿法线位移的系数，控制平滑程度）
        _SmoothStrength ("Smooth Strength", Range(0, 1)) = 0.5
        // 3. 基础属性
        _BaseColor ("Base Color", Color) = (1,1,1,1)
        _Smoothness ("Smoothness", Range(0, 1)) = 0.5
    }
    SubShader
    {
        Tags 
        { 
            "RenderType"="Opaque" 
            "RenderPipeline"="UniversalPipeline" 
            "Queue"="Geometry"
        }
        LOD 300
        Cull Off

        Pass
        {
            Tags { "LightMode"="UniversalForward" } // URP前向渲染
            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma hull hull
            #pragma domain domain
            #pragma target 5.0 // 细分需要DX11+，最低target 5.0

            // 引入URP核心库和光照库
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            // 材质属性变量（CBUFFER优化性能）
            CBUFFER_START(UnityPerMaterial)
                float _TessFactor;
                float _SmoothStrength;
                float4 _BaseColor;
                float _Smoothness;
            CBUFFER_END

            // ====================== 输入输出结构定义 ======================
            // 顶点输入（对象空间）
            struct Attributes
            {
                float4 positionOS : POSITION; // 对象空间位置
                float3 normalOS   : NORMAL;   // 对象空间法线
                float2 uv         : TEXCOORD0;// UV（可选）
            };

            // 细分因子结构（Hull Shader常量输出）
            struct TessFactors
            {
                float edge[3] : SV_TessFactor;       // 边细分因子
                float inside  : SV_InsideTessFactor; // 内部细分因子
            };

            // 域着色器输出（传递到片元）
            struct Varyings
            {
                float4 positionHCS : SV_POSITION; // 裁剪空间位置
                float3 normalWS    : TEXCOORD0;   // 世界空间法线
                float2 uv          : TEXCOORD1;   // UV
            };

            // ====================== 1. 顶点着色器（预处理） ======================
            Attributes vert(Attributes input)
            {
                // 直接传递原始数据到Hull Shader，无额外处理
                return input;
            }

            // ====================== 2. Hull Shader（控制细分程度） ======================
            // 常量函数：定义整体细分因子
            TessFactors hullConstant(InputPatch<Attributes, 3> patch)
            {
                TessFactors factors;
                // 均匀细分：所有边和内部使用相同的细分因子
                factors.edge[0] = _TessFactor;
                factors.edge[1] = _TessFactor;
                factors.edge[2] = _TessFactor;
                factors.inside = _TessFactor;
                return factors;
            }

            // 控制点函数：输出细分所需的控制点（三角面=3个）
            [domain("tri")]               // 细分图元：三角形
            [partitioning("integer")]     // 细分方式：整数拆分（性能更稳定）
            [outputtopology("triangle_cw")]// 输出拓扑：顺时针三角形
            [outputcontrolpoints(3)]      // 输出控制点数量：3（三角面）
            [patchconstantfunc("hullConstant")] // 关联常量函数
            Attributes hull(InputPatch<Attributes, 3> patch, uint id : SV_OutputControlPointID)
            {
                return patch[id]; // 传递原始控制点到Domain Shader
            }

            // ====================== 3. Domain Shader（通用平滑核心） ======================
            [domain("tri")] // 匹配Hull Shader的图元类型
            Varyings domain(TessFactors factors, 
                            OutputPatch<Attributes, 3> patch, 
                            float3 barycentric : SV_DomainLocation)
            {
                Varyings output;

                // Step 1: 重心插值 - 计算细分后顶点的原始位置/法线（对象空间）
                float3 positionOS = 0;
                float3 normalOS = 0;
                float2 uv = 0;
                for (int i = 0; i < 3; i++)
                {
                    positionOS += patch[i].positionOS.xyz * barycentric[i];
                    normalOS += patch[i].normalOS * barycentric[i];
                    uv += patch[i].uv * barycentric[i];
                }

                // Step 2: 通用平滑核心（PN Triangles）
                // 2.1 归一化插值后的法线（避免插值后法线长度失真）
                normalOS = normalize(normalOS);
                // 2.2 计算原始三角面的平面法向量（用于判断位移方向）
                float3 v0 = patch[0].positionOS.xyz;
                float3 v1 = patch[1].positionOS.xyz;
                float3 v2 = patch[2].positionOS.xyz;
                float3 faceNormal = normalize(cross(v1 - v0, v2 - v0));
                // 2.3 沿插值法线位移顶点，贴合曲率（核心平滑逻辑）
                // 位移距离 = 平滑强度 * 顶点到原始三角面的垂直距离
                float distanceToFace = dot(positionOS - v0, faceNormal);
                positionOS += normalOS * distanceToFace * _SmoothStrength;

                // Step 3: URP坐标转换（对象→世界→裁剪）
                float3 positionWS = TransformObjectToWorld(positionOS);
                output.positionHCS = TransformWorldToHClip(positionWS);
                // 法线转换：对象空间→世界空间（带缩放修正）
                output.normalWS = TransformObjectToWorldNormal(normalOS);
                output.uv = uv;

                return output;
            }

            // ====================== 4. 片元着色器（光照+颜色） ======================
            half4 frag(Varyings input) : SV_Target
            {
                /*
                // URP标准光照计算（让平滑后的网格有立体感）
                Light mainLight = GetMainLight();
                float3 normalWS = normalize(input.normalWS);
                float3 viewDirWS = normalize(_WorldSpaceCameraPos - input.positionWS);
                
                // 漫反射
                half diffuse = saturate(dot(normalWS, mainLight.direction));
                // 镜面反射
                half3 h = normalize(mainLight.direction + viewDirWS);
                half specular = pow(saturate(dot(normalWS, h)), _Smoothness * 100);
                
                // 最终颜色
                half3 albedo = _BaseColor.rgb * _BaseColor.a;
                half3 finalColor = albedo * (diffuse * mainLight.color + specular * 0.5);
                */
                return half4(float3(1,1,1), 1.0);
            }
            
            ENDHLSL
        }
    }
    // 回退Shader（避免细分不支持时出错）
    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}
