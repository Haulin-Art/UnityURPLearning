Shader "Custom/VerifyTangentSpaceGravity"
{
    Properties
    {
        _MainTex ("主纹理", 2D) = "white" {}
        _TangentSpaceGravityMap ("切线空间重力方向图", 2D) = "white" {}
        _GravityStrength ("重力强度", Range(0, 2)) = 1.0
        _ShowWorldSpace ("显示世界空间方向", Range(0, 1)) = 1.0
    }
    
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline" = "UniversalPipeline" }
        
        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            
            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
            };
            
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float3 tangentWS : TEXCOORD2;
                float3 bitangentWS : TEXCOORD3;
                float3 positionWS : TEXCOORD4;
            };
            
            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            
            TEXTURE2D(_TangentSpaceGravityMap);
            SAMPLER(sampler_TangentSpaceGravityMap);
            
            float _GravityStrength;
            float _ShowWorldSpace;
            
            // 构建TBN矩阵的函数
            float3x3 CreateTBNMatrix(float3 normalWS, float3 tangentWS, float3 bitangentWS)
            {
                // TBN矩阵将切线空间转换为世界空间
                // T = Tangent, B = Bitangent, N = Normal
                // [T.x B.x N.x]
                // [T.y B.y N.y]
                // [T.z B.z N.z]
                return float3x3(
                    tangentWS.x, bitangentWS.x, normalWS.x,
                    tangentWS.y, bitangentWS.y, normalWS.y,
                    tangentWS.z, bitangentWS.z, normalWS.z
                );
            }
            
            Varyings vert(Attributes input)
            {
                Varyings output;
                
                // 变换顶点位置到裁剪空间
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.positionWS = TransformObjectToWorld(input.positionOS.xyz);
                
                // 变换法线到世界空间
                output.normalWS = TransformObjectToWorldNormal(input.normalOS, true);
                
                // 变换切线到世界空间
                output.tangentWS = TransformObjectToWorldDir(input.tangentOS.xyz, true);
                
                // 计算副切线（使用切线和法线的叉积，考虑切线的w分量来确定方向）
                // 在Unity中，tangentOS.w 存储了副切线的方向（1或-1）
                output.bitangentWS = cross(output.normalWS, output.tangentWS) * input.tangentOS.w;
                
                output.uv = input.uv;
                
                return output;
            }
            
            half4 frag(Varyings input) : SV_Target
            {
                // 采样主纹理
                half4 mainColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv);
                
                // 采样切线空间重力方向图
                // 重力方向存储在RGB通道中，范围是[0,1]，需要转换到[-1,1]
                half4 gravityTangentSpace = SAMPLE_TEXTURE2D(_TangentSpaceGravityMap, sampler_TangentSpaceGravityMap, input.uv);
                
                // 将[0,1]范围转换到[-1,1]范围
                float3 gravityTangent = gravityTangentSpace.rgb * 2.0 - 1.0;
                
                // 构建TBN矩阵
                float3x3 TBN = CreateTBNMatrix(input.normalWS, input.tangentWS, input.bitangentWS);
                
                // 将切线空间的重力方向转换到世界空间
                // 使用矩阵乘法：worldSpace = TBN * tangentSpace
                float3 gravityWorldSpace = mul(TBN, gravityTangent);
                
                // 归一化世界空间重力方向
                gravityWorldSpace = normalize(gravityWorldSpace);

                float2 dir = gravityWorldSpace.yz;
                
                // 可视化验证
                // 方案1：显示世界空间重力方向（将方向映射为颜色）
                //half3 gravityColor = gravityWorldSpace * 2.0 - 1.0; // [-1,1] -> [0,1]
                
                // 方案2：使用重力方向进行简单的光照计算
                // 假设光源在世界空间的上方
                float3 lightDir = float3(0, 1, 0);
                float lightIntensity = dot(gravityWorldSpace, lightDir) * 0.5 + 0.5;
                
                // 方案3：显示原始切线空间重力方向
                half3 tangentColor = gravityTangent * 0.5 + 0.5;
                
                // 混合显示模式
                half3 finalColor;
                if (_ShowWorldSpace > 0.5)
                {
                    // 显示世界空间重力方向
                    finalColor = float3(dir * float2(1,-1) * _GravityStrength,0);
                }
                else
                {
                    // 显示切线空间重力方向
                    finalColor = tangentColor * _GravityStrength;
                }
                
                // 添加调试信息：显示法线、切线、副切线方向
                // 按键1：显示法线（红色）
                // 按键2：显示切线（绿色）
                // 按键3：显示副切线（蓝色）
                // 这里我们通过UV区域来显示
                /*
                float2 debugUV = input.uv;
                if (debugUV.x < 0.1 && debugUV.y < 0.1)
                {
                    // 左下角小方块显示法线方向
                    finalColor = input.normalWS * 0.5 + 0.5;
                }
                else if (debugUV.x < 0.2 && debugUV.y < 0.1)
                {
                    // 显示切线方向
                    finalColor = input.tangentWS * 0.5 + 0.5;
                }
                else if (debugUV.x < 0.3 && debugUV.y < 0.1)
                {
                    // 显示副切线方向
                    finalColor = input.bitangentWS * 0.5 + 0.5;
                }
                */
                
                // 输出最终颜色
                return half4(finalColor, 1.0);
            }
            ENDHLSL
        }
    }
    
    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}
