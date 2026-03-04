   Shader "Unlit/SWEWaterVisualization"
{
    Properties
    {
        _StateTex ("State Texture", 2D) = "black" {}
        _HeightTex ("Height Texture", 2D) = "black" {}
        _WaveHeight ("Wave Height Scale", Float) = 2.0
        _NormalStrength ("Normal Strength", Float) = 1.0
        _WaterColor ("Water Color", Color) = (0.0, 0.3, 0.6, 0.8)
        _FoamColor ("Foam Color", Color) = (1.0, 1.0, 1.0, 1.0)
        _DepthColor ("Deep Water Color", Color) = (0.0, 0.1, 0.3, 1.0)
        _EdgeFade ("Edge Fade", Range(0, 1)) = 0.1
        _HeightScale ("Height Visualization Scale", Float) = 1.0
    }
    
    SubShader
    {
        Tags 
        { 
            "RenderType"="Transparent" 
            "RenderPipeline"="UniversalPipeline"
            "Queue"="Transparent"
        }
        
        Blend SrcAlpha OneMinusSrcAlpha
        ZWrite Off
        
        Pass
        {
            Name "SWEWaterSurface"
            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            
            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float3 normalOS : NORMAL;
            };
            
            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float3 worldPos : TEXCOORD2;
                float height : TEXCOORD3;
                float2 velocity : TEXCOORD4;
            };
            
            TEXTURE2D(_StateTex);
            SAMPLER(sampler_StateTex);
            TEXTURE2D(_HeightTex);
            SAMPLER(sampler_HeightTex);
            
            CBUFFER_START(UnityPerMaterial)
                float _WaveHeight;
                float _NormalStrength;
                float4 _WaterColor;
                float4 _FoamColor;
                float4 _DepthColor;
                float _EdgeFade;
                float _HeightScale;
            CBUFFER_END
            
            Varyings vert(Attributes input)
            {
                Varyings output = (Varyings)0;
                
                // 采样状态场获取高度和速度信息
                float4 state = SAMPLE_TEXTURE2D_LOD(_StateTex, sampler_StateTex, input.uv, 0);
                float2 velocity = state.rg;
                float height = state.b;
                
                // 顶点高度基于水位高度
                float3 positionOS = input.positionOS.xyz;
                positionOS.y += (height ) * _WaveHeight; // 以baseWaterLevel=1为基准
                
                VertexPositionInputs vertexInput = GetVertexPositionInputs(positionOS);
                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS);
                
                output.positionHCS = vertexInput.positionCS;
                output.uv = input.uv;
                output.normalWS = normalInput.normalWS;
                output.worldPos = vertexInput.positionWS;
                output.height = height;
                output.velocity = velocity;
                
                return output;
            }
            
            float4 frag(Varyings input) : SV_Target
            {
                // 采样状态场
                float4 state = SAMPLE_TEXTURE2D(_StateTex, sampler_StateTex, input.uv);
                float2 velocity = state.rg;
                float height = state.b;
                
                // 计算速度大小
                float speed = length(velocity);
                
                // 计算法线（基于高度梯度）
                float2 texelSize = float2(1.0 / 256.0, 1.0 / 256.0); // 假设256x256纹理
                
                float h_right = SAMPLE_TEXTURE2D(_HeightTex, sampler_HeightTex, input.uv + float2(texelSize.x, 0));
                float h_left = SAMPLE_TEXTURE2D(_HeightTex, sampler_HeightTex, input.uv - float2(texelSize.x, 0));
                float h_up = SAMPLE_TEXTURE2D(_HeightTex, sampler_HeightTex, input.uv + float2(0, texelSize.y));
                float h_down = SAMPLE_TEXTURE2D(_HeightTex, sampler_HeightTex, input.uv - float2(0, texelSize.y));
                
                // 计算切线空间法线
                float3 normalTS = normalize(float3(
                    (h_left - h_right) * _NormalStrength,
                    (h_down - h_up) * _NormalStrength,
                    1.0
                ));
                
                // 转换到世界空间
                float3 bitangent = cross(input.normalWS, float3(1, 0, 0));
                float3 tangent = cross(bitangent, input.normalWS);
                float3x3 TBN = float3x3(tangent, bitangent, input.normalWS);
                float3 normalWS = normalize(mul(normalTS, TBN));
                
                // 简单光照
                Light mainLight = GetMainLight();
                float3 lightDir = normalize(mainLight.direction);
                float NdotL = saturate(dot(normalWS, lightDir));
                
                // 基于水位深度的颜色混合
                float depthFactor = saturate((height - 0.5) * 0.5); // 归一化深度
                float3 baseColor = lerp(_DepthColor.rgb, _WaterColor.rgb, depthFactor);
                
                // 根据速度添加泡沫效果
                float foam = saturate(speed * 3.0 - 0.2);
                float3 finalColor = lerp(baseColor, _FoamColor.rgb, foam * 0.5);
                
                // 添加高光
                float3 viewDir = normalize(_WorldSpaceCameraPos - input.worldPos);
                float3 halfDir = normalize(lightDir + viewDir);
                float specAngle = saturate(dot(normalWS, halfDir));
                float specular = pow(specAngle, 64.0) * 0.5;
                finalColor += specular;
                
                // 边缘淡化效果
                float edge = min(
                    min(input.uv.x, 1.0 - input.uv.x),
                    min(input.uv.y, 1.0 - input.uv.y)
                );
                float fade = smoothstep(0.0, _EdgeFade, edge);
                
                // 基于高度的透明度
                float alpha = lerp(_WaterColor.a * 0.5, _WaterColor.a, fade);
                alpha = saturate(alpha + foam * 0.3);
                
                // 应用光照
                finalColor *= (0.6 + 0.4 * NdotL);
                
                return float4(finalColor, alpha);
            }
            ENDHLSL
        }
    }
}
