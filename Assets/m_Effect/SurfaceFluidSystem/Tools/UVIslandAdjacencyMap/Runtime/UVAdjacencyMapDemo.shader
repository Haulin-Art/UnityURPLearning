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
                // B: 邻接边缘遮罩 (1=有邻接信息)
                // A: UV岛范围遮罩 (1=在UV岛内)
                
                float2 adjacentUV = adjacencyData.rg;
                float hasAdjacency = adjacencyData.b;  // 邻接边缘遮罩
                float inUVIsland = adjacencyData.a;    // UV岛范围遮罩
                
                // 如果有邻接信息，进行混合
                if (hasAdjacency > 0)
                {
                    // 采样邻接UV的颜色
                    half4 adjacentColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, adjacentUV);
                    
                    // 混合颜色
                    mainColor = lerp(mainColor, adjacentColor, _BlendStrength);
                }
                
                // 调试模式：显示邻接信息
                if (_ShowAdjacency > 0.5)
                {
                    if (hasAdjacency > 0)
                    {
                        // 显示邻接UV坐标（用于调试）
                        return half4(adjacentUV, 0, 1);
                    }
                    else if (inUVIsland > 0)
                    {
                        // UV岛内部显示为灰色
                        return half4(0.3, 0.3, 0.3, 1);
                    }
                    else
                    {
                        // UV岛外部显示为黑色
                        return half4(0, 0, 0, 1);
                    }
                }
                
                return mainColor;
            }
            ENDHLSL
        }
    }
    
    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}
