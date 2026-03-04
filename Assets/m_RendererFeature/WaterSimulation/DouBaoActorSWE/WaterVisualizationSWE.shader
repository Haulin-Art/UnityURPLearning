Shader "Unlit/WaterVisualizationSWE"
{
    Properties
    {
        _HeightTex ("Height Texture", 2D) = "black" {}
        _HuTex ("Hu Texture", 2D) = "black" {}
        _WaveHeight ("Wave Height", Float) = 1.0
        _NormalStrength ("Normal Strength", Float) = 0.5
        _WaterColor ("Water Color", Color) = (0.1, 0.3, 0.6, 1.0)
        _FoamColor ("Foam Color", Color) = (1.0, 1.0, 1.0, 1.0)
        _FoamThreshold ("Foam Threshold", Float) = 0.1
        _SpecularIntensity ("Specular Intensity", Float) = 0.5
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
                float3 viewDirWS : TEXCOORD3;
            };
            
            TEXTURE2D(_HeightTex);
            SAMPLER(sampler_HeightTex);
            TEXTURE2D(_HuTex);
            SAMPLER(sampler_HuTex);
            
            CBUFFER_START(UnityPerMaterial)
            float _WaveHeight;
            float _NormalStrength;
            float4 _WaterColor;
            float4 _FoamColor;
            float _FoamThreshold;
            float _SpecularIntensity;
            float _EdgeFade;
            CBUFFER_END
            
            Varyings vert(Attributes input)
            {
                Varyings output = (Varyings)0;
                
                float height = SAMPLE_TEXTURE2D_LOD(_HeightTex, sampler_HeightTex, input.uv, 0).r;
                
                float3 positionOS = input.positionOS.xyz;
                positionOS.y += height * _WaveHeight*0.001;
                
                VertexPositionInputs vertexInput = GetVertexPositionInputs(positionOS);
                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS);
                
                output.positionHCS = vertexInput.positionCS;
                output.uv = input.uv;
                output.normalWS = normalInput.normalWS;
                output.worldPos = vertexInput.positionWS;
                output.viewDirWS = GetWorldSpaceViewDir(vertexInput.positionWS);
                
                return output;
            }
            
            float4 frag(Varyings input) : SV_Target
            {
                float2 ddx_uv = ddx(input.uv);
                float2 ddy_uv = ddy(input.uv);
                
                float h_center = SAMPLE_TEXTURE2D(_HeightTex, sampler_HeightTex, input.uv).r;
                float h_right = SAMPLE_TEXTURE2D_GRAD(_HeightTex, sampler_HeightTex, 
                    input.uv + float2(ddx_uv.x, 0), ddx_uv, ddy_uv).r;
                float h_left = SAMPLE_TEXTURE2D_GRAD(_HeightTex, sampler_HeightTex, 
                    input.uv - float2(ddx_uv.x, 0), ddx_uv, ddy_uv).r;
                float h_up = SAMPLE_TEXTURE2D_GRAD(_HeightTex, sampler_HeightTex, 
                    input.uv + float2(0, ddy_uv.y), ddx_uv, ddy_uv).r;
                float h_down = SAMPLE_TEXTURE2D_GRAD(_HeightTex, sampler_HeightTex, 
                    input.uv - float2(0, ddy_uv.y), ddx_uv, ddy_uv).r;
                
                float2 hu = SAMPLE_TEXTURE2D(_HuTex, sampler_HuTex, input.uv).xy;
                
                float3 normalTS = normalize(float3(
                    (h_left - h_right) * _NormalStrength,
                    2.0,
                    (h_down - h_up) * _NormalStrength
                ));
                
                float3 bitangent = cross(input.normalWS, float3(1, 0, 0));
                float3 tangent = cross(bitangent, input.normalWS);
                float3x3 TBN = float3x3(tangent, bitangent, input.normalWS);
                float3 normalWS = normalize(mul(normalTS, TBN));
                
                Light mainLight = GetMainLight();
                float3 lightDir = normalize(mainLight.direction);
                float3 viewDir = normalize(input.viewDirWS);
                float3 halfDir = normalize(lightDir + viewDir);
                
                float NdotL = saturate(dot(normalWS, lightDir));
                float NdotH = saturate(dot(normalWS, halfDir));
                float specular = pow(NdotH, 64.0) * _SpecularIntensity;
                
                float height_grad = abs(h_right - h_left) + abs(h_up - h_down);
                float speed = length(hu);
                float foam = smoothstep(_FoamThreshold, _FoamThreshold * 3.0, height_grad + speed * 0.5);
                
                float3 baseColor = lerp(_WaterColor.rgb, _FoamColor.rgb, foam);
                
                float3 finalColor = baseColor * (0.5 + 0.5 * NdotL) + mainLight.color * specular;
                
                float edge = min(
                    min(input.uv.x, 1.0 - input.uv.x),
                    min(input.uv.y, 1.0 - input.uv.y)
                );
                float fade = smoothstep(0.0, _EdgeFade, edge);
                
                float alpha = lerp(0.0, _WaterColor.a, fade);
                
                return float4(finalColor, alpha);
            }
            ENDHLSL
        }
    }
}
