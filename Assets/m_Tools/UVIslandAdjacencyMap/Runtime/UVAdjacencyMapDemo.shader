Shader "UV/UVAdjacencyMapDemo"
{
    Properties
    {
        _MainTex ("主纹理", 2D) = "white" {}
        _AdjacencyMap ("邻接图", 2D) = "black" {}
        _BlendStrength ("混合强度", Range(0, 1)) = 0.5
        _BlendDistance ("混合距离", Range(0, 0.1)) = 0.02
        _ShowAdjacency ("显示邻接信息", Range(0, 1)) = 0
    }
    
    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        
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
            };
            
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };
            
            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            
            TEXTURE2D(_AdjacencyMap);
            SAMPLER(sampler_AdjacencyMap);
            
            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float _BlendStrength;
                float _BlendDistance;
                float _ShowAdjacency;
            CBUFFER_END
            
            Varyings vert(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.uv = TRANSFORM_TEX(input.uv, _MainTex);
                return output;
            }
            
            half4 frag(Varyings input) : SV_Target
            {
                // 采样主纹理
                half4 mainColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv);
                
                // 采样邻接图
                half4 adjacencyData = SAMPLE_TEXTURE2D(_AdjacencyMap, sampler_AdjacencyMap, input.uv);
                
                // 解析邻接数据
                // R: 邻接UV.x
                // G: 邻接UV.y
                // B: 到边缘的距离权重 (0=边缘, 1=远离)
                // A: 邻接岛ID (0=无邻接)
                
                float2 adjacentUV = adjacencyData.rg;
                float edgeDistance = adjacencyData.b;  // 0=边缘, 1=远离
                float hasAdjacency = adjacencyData.a;  // >0 表示有邻接
                
                // 如果有邻接信息，进行混合
                if (hasAdjacency > 0)
                {
                    // 计算混合权重
                    // edgeDistance=0时（边缘），权重最高
                    // edgeDistance=1时（远离边缘），权重最低
                    float blendWeight = (1.0 - edgeDistance) * _BlendStrength;
                    
                    // 采样邻接UV的颜色
                    half4 adjacentColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, adjacentUV);
                    
                    // 混合颜色
                    mainColor = lerp(mainColor, adjacentColor, blendWeight);
                }
                
                // 调试模式：显示邻接信息
                if (_ShowAdjacency > 0.5)
                {
                    if (hasAdjacency > 0)
                    {
                        // 显示邻接UV坐标（用于调试）
                        return half4(adjacentUV, 0, 1);
                    }
                    else
                    {
                        // 无邻接区域显示为暗色
                        return half4(0.1, 0.1, 0.1, 1);
                    }
                }
                
                return mainColor;
            }
            ENDHLSL
        }
    }
    
    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}
