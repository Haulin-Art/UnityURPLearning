Shader "Kimi/Unlit/SWEWaterSurface"
{
    Properties
    {
        _HeightTex ("Height Texture", 2D) = "black" {}
        _NormalTex ("Normal Texture", 2D) = "bump" {}
        
        [Header(Water Surface)]
        _BaseColor ("Base Color", Color) = (0.0, 0.4, 0.7, 0.8)
        _DeepColor ("Deep Color", Color) = (0.0, 0.1, 0.3, 1.0)
        _WaterDepth ("Water Depth", Float) = 2.0
        _WaveHeightScale ("Wave Height Scale", Float) = 0.3
        
        [Header(Wave Visualization)]
        _WaveColorScale ("Wave Color Scale", Float) = 2.0
        _WaveBrightness ("Wave Brightness", Float) = 1.5
        
        [Header(Foam)]
        _FoamColor ("Foam Color", Color) = (1, 1, 1, 1)
        _FoamThreshold ("Foam Threshold", Float) = 0.5
        
        [Header(Specular)]
        _SpecularPower ("Specular Power", Range(1, 256)) = 64
        _SpecularIntensity ("Specular Intensity", Range(0, 2)) = 1.0
        
        [Header(Edge)]
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
        
        Pass
        {
            Name "SWEWaterSurface"
            
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull Back
            
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
                float4 tangentOS : TANGENT;
            };
            
            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
                float4 tangentWS : TEXCOORD3;
            };
            
            TEXTURE2D(_HeightTex);
            SAMPLER(sampler_HeightTex);
            TEXTURE2D(_NormalTex);
            SAMPLER(sampler_NormalTex);
            
            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _DeepColor;
                float4 _FoamColor;
                float _WaterDepth;
                float _WaveHeightScale;
                float _WaveColorScale;
                float _WaveBrightness;
                float _FoamThreshold;
                float _SpecularPower;
                float _SpecularIntensity;
                float _EdgeFade;
            CBUFFER_END
            
            Varyings vert(Attributes input)
            {
                Varyings output;
                
                float2 uv = input.uv;
                
                // 采样高度场
                float height = SAMPLE_TEXTURE2D_LOD(_HeightTex, sampler_HeightTex, uv, 0).r;
                
                // 顶点位移 - 根据高度场变形
                float3 positionOS = input.positionOS.xyz;
                positionOS.y += height * _WaveHeightScale;
                
                VertexPositionInputs posInputs = GetVertexPositionInputs(positionOS);
                VertexNormalInputs normalInputs = GetVertexNormalInputs(input.normalOS, input.tangentOS);
                
                output.positionHCS = posInputs.positionCS;
                output.uv = uv;
                output.positionWS = posInputs.positionWS;
                output.normalWS = normalInputs.normalWS;
                output.tangentWS = float4(normalInputs.tangentWS, normalInputs.bitangentWS.x);
                
                return output;
            }
            
            float4 frag(Varyings input) : SV_Target
            {
                float2 uv = input.uv;
                
                // 采样高度场
                float height = SAMPLE_TEXTURE2D(_HeightTex, sampler_HeightTex, uv).r;
                
                // 采样法线贴图
                float4 normalData = SAMPLE_TEXTURE2D(_NormalTex, sampler_NormalTex, uv);
                float3 normalTS = normalData.xyz;
                
                // 构建TBN矩阵
                float3 bitangentWS = cross(input.normalWS, input.tangentWS.xyz);
                float3x3 TBN = float3x3(input.tangentWS.xyz, bitangentWS, input.normalWS);
                
                // 转换法线到世界空间
                float3 normalWS = normalize(mul(normalTS, TBN));
                
                // 视线方向
                float3 viewDirWS = normalize(_WorldSpaceCameraPos - input.positionWS);
                
                // 主光源
                Light mainLight = GetMainLight();
                float3 lightDirWS = normalize(mainLight.direction);
                
                // ========== 波浪颜色可视化 ==========
                // 将高度映射到颜色 - 使用正弦波产生条纹效果
                float wavePattern = sin(height * _WaveColorScale * 3.14159);
                float heightAbs = abs(height);
                
                // 基础颜色根据高度混合
                float heightFactor = saturate(heightAbs / _FoamThreshold);
                float3 baseColor = lerp(_DeepColor.rgb, _BaseColor.rgb, heightFactor);
                
                // 添加波浪条纹
                float stripePattern = sin(height * 20.0) * 0.5 + 0.5;
                baseColor = lerp(baseColor, baseColor * 1.3, stripePattern * heightFactor);
                
                // ========== 泡沫效果 ==========
                // 波峰处产生泡沫
                float foamMask = smoothstep(_FoamThreshold * 0.3, _FoamThreshold, heightAbs);
                float3 foamColor = _FoamColor.rgb;
                
                // ========== 高光 ==========
                float3 halfDir = normalize(lightDirWS + viewDirWS);
                float NdotH = saturate(dot(normalWS, halfDir));
                float specular = pow(NdotH, _SpecularPower) * _SpecularIntensity;
                
                // ========== 合成颜色 ==========
                float3 finalColor = baseColor * _WaveBrightness;
                
                // 添加漫反射光照
                float NdotL = saturate(dot(normalWS, lightDirWS));
                finalColor *= (0.5 + 0.5 * NdotL);
                
                // 添加高光
                finalColor += mainLight.color * specular;
                
                // 添加泡沫
                finalColor = lerp(finalColor, foamColor, foamMask * 0.8);
                
                // ========== 边缘淡化 ==========
                float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
                float edgeFade = smoothstep(0.0, _EdgeFade, edge);
                
                // ========== 透明度 ==========
                float alpha = lerp(_BaseColor.a * 0.3, _BaseColor.a, edgeFade);
                alpha = lerp(alpha, 1.0, foamMask * 0.5);
                
                // 调试用：直接显示高度场（灰度）
                // return float4(height * 0.5 + 0.5, height * 0.5 + 0.5, height * 0.5 + 0.5, 1);
                
                // 调试用：显示高度热力图
                // float3 heatmap = lerp(float3(0,0,1), lerp(float3(0,1,0), float3(1,0,0), saturate(height)), saturate(-height));
                // return float4(heatmap, 1);
                
                return float4(finalColor, alpha);
            }
            ENDHLSL
        }
    }
}
