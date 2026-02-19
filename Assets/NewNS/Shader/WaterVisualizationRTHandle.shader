Shader "Unlit/WaterDyeVisualization"
{
    Properties
    {
        _VelocityTex ("Velocity Texture", 2D) = "black" {}
        _DyeTex ("Dye Texture", 2D) = "black" {}
        _WaveHeight ("Wave Height", Float) = 2.0
        _NormalStrength ("Normal Strength", Float) = 1.0
        _FoamIntensity ("Foam Intensity", Float) = 1.0
        _EdgeFade ("Edge Fade", Range(0, 1)) = 0.1
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
            Name "WaterSurface"
            
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
            };
            
            TEXTURE2D(_VelocityTex);
            SAMPLER(sampler_VelocityTex);
            TEXTURE2D(_DyeTex);
            SAMPLER(sampler_DyeTex);
            
            CBUFFER_START(UnityPerMaterial)
            float _WaveHeight;
            float _NormalStrength;
            float _FoamIntensity;
            float _EdgeFade;
            float _Resolution;
            CBUFFER_END
            
            Varyings vert(Attributes input)
            {
                Varyings output = (Varyings)0;
                
                // 采样速度场获取高度信息
                float4 velocity = SAMPLE_TEXTURE2D_LOD(_VelocityTex, sampler_VelocityTex, input.uv, 0);
                float speed = length(velocity.xy);
                
                // 顶点高度基于速度大小
                float3 positionOS = input.positionOS.xyz;
                //positionOS.y += speed * _WaveHeight;
                
                // 添加一些基础波浪效果
                float time = _Time.y;
                float wave = sin(input.uv.x * 15.0 + time) * 
                           cos(input.uv.y * 12.0 + time) * 0.05;
                //positionOS.y += wave;
                
                VertexPositionInputs vertexInput = GetVertexPositionInputs(positionOS);
                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS);
                
                output.positionHCS = vertexInput.positionCS;
                output.uv = input.uv;
                output.normalWS = normalInput.normalWS;
                output.worldPos = vertexInput.positionWS;
                
                return output;
            }
            
            float4 frag(Varyings input) : SV_Target
            {
                // 采样速度场
                float4 velocity = SAMPLE_TEXTURE2D(_VelocityTex, sampler_VelocityTex, input.uv);
                float speed = length(velocity.xy);
                
                // 采样染料场 - 这才是真正的流体颜色！
                float4 dye = SAMPLE_TEXTURE2D(_DyeTex, sampler_DyeTex, input.uv);
                
                // 计算法线（基于速度梯度）
                float2 ddx_uv = ddx(input.uv);
                float2 ddy_uv = ddy(input.uv);
                
                float2 velRight = SAMPLE_TEXTURE2D_GRAD(_VelocityTex, sampler_VelocityTex, 
                    input.uv + float2(ddx_uv.x, 0), ddx_uv, ddy_uv).xy;
                float2 velLeft = SAMPLE_TEXTURE2D_GRAD(_VelocityTex, sampler_VelocityTex, 
                    input.uv - float2(ddx_uv.x, 0), ddx_uv, ddy_uv).xy;
                float2 velUp = SAMPLE_TEXTURE2D_GRAD(_VelocityTex, sampler_VelocityTex, 
                    input.uv + float2(0, ddy_uv.y), ddx_uv, ddy_uv).xy;
                float2 velDown = SAMPLE_TEXTURE2D_GRAD(_VelocityTex, sampler_VelocityTex, 
                    input.uv - float2(0, ddy_uv.y), ddx_uv, ddy_uv).xy;
                
                // 计算切线空间法线
                float3 normalTS = normalize(float3(
                    (velLeft.x - velRight.x) * _NormalStrength,
                    (velDown.y - velUp.y) * _NormalStrength,
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
                
                // 基础颜色来自染料场
                float3 baseColor = dye.rgb;
                
                // 根据速度添加泡沫效果
                float foam = saturate(speed * 5.0 - 0.3) * _FoamIntensity;
                float3 foamColor = lerp(baseColor, float3(1, 1, 1), foam);
                
                // 边缘淡化效果
                float edge = min(
                    min(input.uv.x, 1.0 - input.uv.x),
                    min(input.uv.y, 1.0 - input.uv.y)
                );
                float fade = smoothstep(0.0, _EdgeFade, edge);
                
                // 最终颜色 = 染料颜色 + 光照 + 泡沫
                float3 finalColor = foamColor * (0.7 + 0.3 * NdotL);
                
                // 透明度基于染料浓度和边缘淡化
                float alpha = lerp(dye.a * 0.5, dye.a, fade);
                
                return float4(velocity.xy,0,1);
                //return float4(smoothstep(0.95,0.85,2.0*abs(input.uv-0.5)),0.0,1.0);
                return float4(dye*float3(1,1,1),1);
                return float4(finalColor, alpha);
            }
            ENDHLSL
        }
    }
}