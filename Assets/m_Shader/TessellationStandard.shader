Shader "Custom/SimpleTessellation"
{
    Properties
    {
        _BaseColor ("基础颜色", Color) = (1, 1, 1, 1)
        _TessellationUniform ("细分因子", Range(1, 32)) = 4
    }
    
    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        
        Pass
        {
            Tags { "LightMode" = "UniversalForward" }
            
            HLSLPROGRAM
            
            // ============================================================================
            // 细分着色器需要 Shader Model 5.0 或更高版本
            // tessellation tessHW 表示需要硬件支持细分着色器
            // ============================================================================
            #pragma target 5.0
            #pragma require tessellation tessHW
            
            // ============================================================================
            // 声明着色器阶段
            // 细分着色器管线: vertex -> hull -> domain -> fragment
            // 注意: 没有传统的几何着色器，取而代之的是 hull 和 domain
            // ============================================================================
            #pragma vertex vert
            #pragma hull hull
            #pragma domain domain
            #pragma fragment frag
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            
            // ============================================================================
            // 材质属性缓冲区 (用于 GPU Instancing 兼容)
            // ============================================================================
            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float _TessellationUniform;
            CBUFFER_END
            
            // ============================================================================
            // 数据结构定义
            // ============================================================================
            
            // 顶点着色器输入结构
            // 这是从 Mesh 中获取的原始数据
            struct Attributes
            {
                float4 positionOS : POSITION;  // 物体空间位置 (Object Space)
                float3 normalOS : NORMAL;      // 物体空间法线
            };
            
            // 细分控制点结构
            // 这是顶点着色器的输出，也是 Hull Shader 的输入/输出
            // 每个顶点都是一个"控制点"
            struct TessControlPoint
            {
                // INTERNALTESSPOS 是细分着色器专用的语义
                // 它告诉 GPU 这个位置将用于细分计算
                float4 positionOS : INTERNALTESSPOS;
                float3 normalOS : NORMAL;
            };
            
            // 片元着色器输入结构
            // 这是 Domain Shader 的输出
            struct Varyings
            {
                float4 positionCS : SV_POSITION;  // 裁剪空间位置 (Clip Space)，必须用 SV_POSITION
                float3 normalWS : TEXCOORD0;      // 世界空间法线，用于光照计算
            };
            
            // 细分因子结构
            // 这个结构决定了三角形如何被细分
            struct TessFactors
            {
                // edge[3]: 三角形三条边的细分因子
                // - edge[0]: 顶点1到顶点2的边
                // - edge[1]: 顶点2到顶点3的边  
                // - edge[2]: 顶点3到顶点1的边
                // 值越大，这条边被分割得越细
                float edge[3] : SV_TessFactor;
                
                // inside: 三角形内部的细分因子
                // 决定三角形内部被分割成多少个小三角形
                float inside : SV_InsideTessFactor;
            };
            
            // ============================================================================
            // 顶点着色器 (Vertex Shader)
            // 
            // 在细分着色器管线中，顶点着色器的作用是:
            // 1. 将原始顶点数据传递给 Hull Shader
            // 2. 可以进行一些预处理，但通常只是简单传递
            // 
            // 注意: 这里不进行 MVP 变换，因为细分需要在物体空间进行
            // ============================================================================
            TessControlPoint vert(Attributes input)
            {
                TessControlPoint output;
                output.positionOS = input.positionOS;
                output.normalOS = input.normalOS;

                return output;
            }
            
            // ============================================================================
            // Patch Constant Function (补丁常量函数)
            // 
            // 这个函数在 Hull Shader 之前被调用，用于计算细分因子
            // 它对每个"补丁"(Patch，即一个三角形) 调用一次
            // 
            // InputPatch<TessControlPoint, 3> 表示一个包含3个控制点的输入补丁
            // 这3个控制点就是三角形的3个顶点
            // ============================================================================
            TessFactors patchConstantFunction(InputPatch<TessControlPoint, 3> patch)
            {
                TessFactors f;
                
                // ====================================================================
                // 基于距离的动态细分计算
                // 
                // 思路: 
                // 1. 将三角形三个顶点从物体空间转换到世界空间
                // 2. 计算每个顶点到摄像机的距离
                // 3. 根据距离插值细分因子 (近处细分多，远处细分少)
                // ====================================================================
                
                // 将三个顶点从物体空间转换到世界空间
                float3 p0_ws = TransformObjectToWorld(patch[0].positionOS.xyz);
                float3 p1_ws = TransformObjectToWorld(patch[1].positionOS.xyz);
                float3 p2_ws = TransformObjectToWorld(patch[2].positionOS.xyz);
                
                // 计算每个顶点到摄像机的距离
                // _WorldSpaceCameraPos 是 Unity 内置变量，存储摄像机世界坐标
                float dist0 = distance(p0_ws, _WorldSpaceCameraPos);
                float dist1 = distance(p1_ws, _WorldSpaceCameraPos);
                float dist2 = distance(p2_ws, _WorldSpaceCameraPos);
                
                // 取三角形中心到摄像机的距离 (三个顶点距离的平均值)
                float avgDistance = (dist0 + dist1 + dist2) / 3.0;
                
                // ====================================================================
                // 细分因子计算公式
                // 
                // 使用 smoothstep 实现平滑过渡:
                // - 近距离 (minDist): 使用最大细分因子
                // - 远距离 (maxDist): 使用最小细分因子 (1.0)
                // - 中间距离: 平滑插值
                // ====================================================================
                
                float minDist = 2.0;   // 最近距离阈值
                float maxDist = 5.0;  // 最远距离阈值
                float maxTess = _TessellationUniform;  // 最大细分因子
                float minTess = 1.0;   // 最小细分因子
                
                // 计算距离因子: 近处为1，远处为0
                float distanceFactor = 1.0 - smoothstep(minDist, maxDist, avgDistance);
                
                // 最终细分因子 = 最小值 + (最大值 - 最小值) * 距离因子
                float tessFactor = minTess + (maxTess - minTess) * distanceFactor;
                
                // ====================================================================
                // 边细分因子 vs 内部细分因子
                // 
                // 可以根据每条边的具体情况设置不同的细分因子:
                // - edge[0]: 顶点1到顶点2的边，使用 dist1 和 dist2 的平均
                // - edge[1]: 顶点2到顶点3的边，使用 dist2 和 dist0 的平均
                // - edge[2]: 顶点3到顶点1的边，使用 dist0 和 dist1 的平均
                // 
                // 这样可以让三角形的不同边有不同的细分程度
                // ====================================================================
                
                // 方法1: 所有边使用相同的细分因子 (简单)
                f.edge[0] = tessFactor;
                f.edge[1] = tessFactor;
                f.edge[2] = tessFactor;
                f.inside = tessFactor;
                
                // 方法2: 每条边根据其两端顶点的距离单独计算 (更精细)
                // float edgeFactor0 = 1.0 - smoothstep(minDist, maxDist, (dist1 + dist2) * 0.5);
                // float edgeFactor1 = 1.0 - smoothstep(minDist, maxDist, (dist2 + dist0) * 0.5);
                // float edgeFactor2 = 1.0 - smoothstep(minDist, maxDist, (dist0 + dist1) * 0.5);
                // 
                // f.edge[0] = minTess + (maxTess - minTess) * edgeFactor0;
                // f.edge[1] = minTess + (maxTess - minTess) * edgeFactor1;
                // f.edge[2] = minTess + (maxTess - minTess) * edgeFactor2;
                // f.inside = (f.edge[0] + f.edge[1] + f.edge[2]) / 3.0;
                
                return f;
            }
            
            // ============================================================================
            // Hull Shader (外壳着色器)
            // 
            // Hull Shader 有两个职责:
            // 1. 通过属性定义细分参数 (domain, partitioning, outputtopology 等)
            // 2. 输出控制点数据
            // 
            // Hull Shader 对每个控制点(顶点)调用一次
            // ============================================================================
            
            // [domain("tri")] - 指定细分域为三角形
            // 可选值: "tri"(三角形), "quad"(四边形), "isoline"(等值线)
            [domain("tri")]
            
            // [partitioning("integer")] - 指定细分因子的分区方式
            // "integer": 整数细分，细分因子会被截断为整数
            // "fractional_odd": 奇数分数细分，更平滑的过渡
            // "fractional_even": 偶数分数细分
            // "pow2": 2的幂次细分
            [partitioning("integer")]
            
            // [outputtopology("triangle_cw")] - 指定输出图元的拓扑结构
            // "triangle_cw": 顺时针缠绕的三角形
            // "triangle_ccw": 逆时针缠绕的三角形
            // "point": 只输出点
            [outputtopology("triangle_cw")]
            
            // [patchconstantfunc("patchConstantFunction")] - 指定补丁常量函数
            // 这个函数用于计算细分因子
            [patchconstantfunc("patchConstantFunction")]
            
            // [outputcontrolpoints(3)] - 指定输出的控制点数量
            // 对于三角形细分，通常输出3个控制点(与输入相同)
            // 但也可以输出更多控制点(如用于面片细分算法)
            [outputcontrolpoints(3)]
            
            // Hull Shader 主函数
            // InputPatch: 输入的控制点集合
            // SV_OutputControlPointID: 当前处理的控制点索引 (0, 1, 或 2)
            TessControlPoint hull(InputPatch<TessControlPoint, 3> patch, uint id : SV_OutputControlPointID)
            {
                // 简单地传递控制点数据
                // 在更复杂的细分着色器中，可以在这里:
                // 1. 修改控制点位置
                // 2. 计算新的属性(如颜色、UV等)
                // 3. 进行曲面细分算法(如贝塞尔曲面)
                return patch[id];
            }
            
            // ============================================================================
            // Domain Shader (域着色器)
            // 
            // Domain Shader 是细分着色器管线的核心
            // 它对细分后生成的每个新顶点调用一次
            // 
            // 输入:
            // - TessFactors: 细分因子
            // - OutputPatch: Hull Shader 输出的控制点
            // - SV_DomainLocation: 重心坐标，表示新顶点在三角形中的位置
            // 
            // 输出:
            // - 最终的顶点数据，传递给片元着色器
            // ============================================================================
            [domain("tri")]
            Varyings domain(TessFactors factors, OutputPatch<TessControlPoint, 3> patch, float3 barycentricCoordinates : SV_DomainLocation)
            {
                Varyings output;
                
                // ========================================================================
                // 重心坐标插值
                // 
                // barycentricCoordinates (重心坐标) 是一个 float3 (u, v, w)
                // 满足 u + v + w = 1
                // 
                // 它表示新顶点相对于三角形三个顶点的权重:
                // - barycentricCoordinates.x: 顶点0的权重
                // - barycentricCoordinates.y: 顶点1的权重
                // - barycentricCoordinates.z: 顶点2的权重
                // 
                // 新顶点位置 = v0 * u + v1 * v + v2 * w
                // ========================================================================
                
                // 插值位置
                float3 positionOS = patch[0].positionOS.xyz * barycentricCoordinates.x +
                                    patch[1].positionOS.xyz * barycentricCoordinates.y +
                                    patch[2].positionOS.xyz * barycentricCoordinates.z;
                
                // 插值法线 (需要归一化)
                float3 normalOS = patch[0].normalOS * barycentricCoordinates.x +
                                  patch[1].normalOS * barycentricCoordinates.y +
                                  patch[2].normalOS * barycentricCoordinates.z;
                
                // ========================================================================
                // 这里是添加位移贴图的最佳位置
                // 
                // 例如:
                // float height = SAMPLE_TEXTURE2D_LOD(_HeightMap, sampler_HeightMap, uv, 0).r;
                // positionOS += normalize(normalOS) * height * _HeightScale;
                // 
                // 注意: 采样纹理需要使用 _LOD 版本，因为我们在顶点着色器阶段
                // ========================================================================
                
                // 变换到裁剪空间 (MVP 变换)
                output.positionCS = TransformObjectToHClip(float4(positionOS, 1.0));
                
                // 变换法线到世界空间
                output.normalWS = TransformObjectToWorldNormal(normalize(normalOS));
                
                return output;
            }
            
            // ============================================================================
            // 片元着色器 (Fragment Shader / Pixel Shader)
            // 
            // 计算每个像素的最终颜色
            // ============================================================================
            float4 frag(Varyings input) : SV_Target
            {
                // 归一化法线 (插值后可能不是单位向量)
                float3 normal = normalize(input.normalWS);
                
                // 简单的定向光源方向
                float3 lightDir = normalize(float3(1, 1, -1));
                
                // Lambert 漫反射: N·L
                // saturate 将结果限制在 [0, 1] 范围内
                float ndotl = saturate(dot(normal, lightDir));
                
                // 环境光 + 漫反射
                // 0.3 是环境光强度，0.7 是漫反射强度
                float3 finalColor = _BaseColor.rgb * (0.3 + 0.7 * ndotl);
                
                return float4(finalColor, 1.0);
            }
            ENDHLSL
        }
    }
}
