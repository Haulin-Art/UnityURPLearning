Shader "Unlit/kn_WaterVisualization"
{
    Properties
    {
        _StateTex ("State Texture", 2D) = "black" {}
        _WaveHeight ("Wave Height Scale", Float) = 2.0
        _NormalStrength ("Normal Strength", Float) = 1.0
        _FoamIntensity ("Foam Intensity", Float) = 1.0
        _EdgeFade ("Edge Fade", Range(0, 1)) = 0.1
        _WaterColor ("Water Color", Color) = (0.0, 0.3, 0.6, 1.0)
        _FoamColor ("Foam Color", Color) = (1.0, 1.0, 1.0, 1.0)
        _DeepWaterColor ("Deep Water Color", Color) = (0.0, 0.1, 0.3, 1.0)
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
                float4 stateData : TEXCOORD3;
            };

            TEXTURE2D(_StateTex);
            SAMPLER(sampler_StateTex);

            CBUFFER_START(UnityPerMaterial)
                float _WaveHeight;
                float _NormalStrength;
                float _FoamIntensity;
                float _EdgeFade;
                float4 _WaterColor;
                float4 _FoamColor;
                float4 _DeepWaterColor;
            CBUFFER_END

            Varyings vert(Attributes input)
            {
                Varyings output = (Varyings)0;

                // 采样状态纹理获取高度信息
                float4 state = SAMPLE_TEXTURE2D_LOD(_StateTex, sampler_StateTex, input.uv, 0);
                float waterHeight = state.b;
                float2 velocity = state.rg;
                float speed = length(velocity);

                // 顶点高度基于水位
                float3 positionOS = input.positionOS.xyz;
                positionOS.y += waterHeight * _WaveHeight * 0.1;

                // 添加波浪细节
                float time = _Time.y;
                float wave1 = sin(input.uv.x * 20.0 + time * 2.0) * 0.02;
                float wave2 = cos(input.uv.y * 15.0 + time * 1.5) * 0.02;
                positionOS.y += (wave1 + wave2) * saturate(speed);

                VertexPositionInputs vertexInput = GetVertexPositionInputs(positionOS);
                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS);

                output.positionHCS = vertexInput.positionCS;
                output.uv = input.uv;
                output.normalWS = normalInput.normalWS;
                output.worldPos = vertexInput.positionWS;
                output.stateData = state;

                return output;
            }

            float4 frag(Varyings input) : SV_Target
            {
                float4 state = input.stateData;
                float2 velocity = state.rg;
                float waterHeight = state.b;
                float speed = length(velocity);

                // 计算法线（基于速度梯度）
                float2 ddx_uv = ddx(input.uv);
                float2 ddy_uv = ddy(input.uv);

                float4 stateRight = SAMPLE_TEXTURE2D_GRAD(_StateTex, sampler_StateTex,
                    input.uv + float2(ddx_uv.x, 0), ddx_uv, ddy_uv);
                float4 stateLeft = SAMPLE_TEXTURE2D_GRAD(_StateTex, sampler_StateTex,
                    input.uv - float2(ddx_uv.x, 0), ddx_uv, ddy_uv);
                float4 stateUp = SAMPLE_TEXTURE2D_GRAD(_StateTex, sampler_StateTex,
                    input.uv + float2(0, ddy_uv.y), ddx_uv, ddy_uv);
                float4 stateDown = SAMPLE_TEXTURE2D_GRAD(_StateTex, sampler_StateTex,
                    input.uv - float2(0, ddy_uv.y), ddx_uv, ddy_uv);

                // 基于高度差计算法线
                float3 normalTS = normalize(float3(
                    (stateLeft.b - stateRight.b) * _NormalStrength,
                    (stateDown.b - stateUp.b) * _NormalStrength,
                    1.0
                ));

                // 转换到世界空间
                float3 bitangent = cross(input.normalWS, float3(1, 0, 0));
                float3 tangent = cross(bitangent, input.normalWS);
                float3x3 TBN = float3x3(tangent, bitangent, input.normalWS);
                float3 normalWS = normalize(mul(normalTS, TBN));

                // 主光源
                Light mainLight = GetMainLight();
                float3 lightDir = normalize(mainLight.direction);
                float NdotL = saturate(dot(normalWS, lightDir));

                // 视角方向
                float3 viewDir = normalize(_WorldSpaceCameraPos - input.worldPos);
                float3 halfDir = normalize(lightDir + viewDir);
                float NdotH = saturate(dot(normalWS, halfDir));

                // 菲涅尔效果
                float fresnel = pow(1.0 - saturate(dot(normalWS, viewDir)), 3.0);

                // 水深颜色混合
                float depthFactor = saturate(waterHeight * 0.5);
                float3 waterColor = lerp(_DeepWaterColor.rgb, _WaterColor.rgb, depthFactor);

                // 速度泡沫效果
                float foam = saturate((speed - 0.5) * _FoamIntensity);
                float3 finalColor = lerp(waterColor, _FoamColor.rgb, foam);

                // 添加高光
                float specular = pow(NdotH, 128.0) * 0.5;
                finalColor += specular;

                // 简单光照
                finalColor *= (0.6 + 0.4 * NdotL);

                // 添加菲涅尔反射
                finalColor = lerp(finalColor, float3(0.8, 0.9, 1.0), fresnel * 0.3);

                // 边缘淡化
                float edge = min(
                    min(input.uv.x, 1.0 - input.uv.x),
                    min(input.uv.y, 1.0 - input.uv.y)
                );
                float fade = smoothstep(0.0, _EdgeFade, edge);

                // 基于速度的透明度
                float alpha = lerp(0.6, 0.9, saturate(speed * 0.5)) * fade;

                return float4(finalColor, alpha);
            }
            ENDHLSL
        }
    }
}
