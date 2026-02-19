Shader "Unlit/OutLineShader"
{
    Properties
    {
        _MainTex ("主纹理", 2D) = "white" {}
        _Nor ("法向", 2D) = "white" {}
        _Dep ("深度", 2D) = "white" {}
        _OutlineColor ("描边颜色", Color) = (0, 0, 0, 1)
        _OutlineWidth ("描边宽度", Range(0, 5)) = 1
        _NormalThreshold ("法线阈值", Range(0, 1)) = 0.5
        _DepthThreshold ("深度阈值", Range(0, 1)) = 0.01
        _DepthSensitivity ("深度灵敏度", Range(0, 5)) = 1
        _NormalSensitivity ("法线灵敏度", Range(0, 5)) = 1
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            Name "OutLine"
            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                float4 screenPos : TEXCOORD1;
            };
            
            TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);
            TEXTURE2D(_Nor); SAMPLER(sampler_Nor); 
            TEXTURE2D(_Dep); SAMPLER(sampler_Dep);
            
            float4 _MainTex_TexelSize;
            float4 _OutlineColor;
            float _OutlineWidth;
            float _NormalThreshold;
            float _DepthThreshold;
            float _DepthSensitivity;
            float _NormalSensitivity;
            
            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = TransformObjectToHClip(v.vertex);
                o.uv = v.uv;
                o.screenPos = ComputeScreenPos(o.vertex);
                return o;
            }
            
            // 解码法线（从RG重建）
            float3 DecodeNormal(float2 encodedNormal)
            {
                float3 normal;
                normal.xy = encodedNormal* 2.0 - 1.0;
                normal.z = sqrt(1.0 - saturate(dot(normal.xy, normal.xy)));
                return normalize(normal);
            }
            
            // Sobel边缘检测
            float SobelDepth(float2 uv, float depth , float outlineWidth)
            {
                
                float2 texelSize = _MainTex_TexelSize.xy * outlineWidth;
                
                // 采样周围像素
                float depthUp = SAMPLE_TEXTURE2D(_Dep, sampler_Dep, uv + float2(0, texelSize.y)).r;
                float depthDown = SAMPLE_TEXTURE2D(_Dep, sampler_Dep, uv - float2(0, texelSize.y)).r;
                float depthLeft = SAMPLE_TEXTURE2D(_Dep, sampler_Dep, uv - float2(texelSize.x, 0)).r;
                float depthRight = SAMPLE_TEXTURE2D(_Dep, sampler_Dep, uv + float2(texelSize.x, 0)).r;
                
                depthUp = LinearEyeDepth(depthUp, _ZBufferParams);
                depthDown = LinearEyeDepth(depthDown, _ZBufferParams);
                depthLeft = LinearEyeDepth(depthLeft, _ZBufferParams);
                depthRight = LinearEyeDepth(depthRight, _ZBufferParams);

                // Sobel算子
                float depthHorz = 
                    depthLeft + depthRight - 2.0 * depth;
                float depthVert = 
                    depthUp + depthDown - 2.0 * depth;
                
                return sqrt(depthHorz * depthHorz + depthVert * depthVert) * _DepthSensitivity;
            }
            
            // 法线差异检测
            float NormalEdge(float2 uv, float3 normal, float outlineWidth)
            {
                float2 texelSize = _MainTex_TexelSize.xy * outlineWidth;
                
                // 采样周围像素的法线
                float3 normalUp = DecodeNormal(SAMPLE_TEXTURE2D(_Nor, sampler_Nor, uv + float2(0, texelSize.y)).rg);
                float3 normalDown = DecodeNormal(SAMPLE_TEXTURE2D(_Nor, sampler_Nor, uv - float2(0, texelSize.y)).rg);
                float3 normalLeft = DecodeNormal(SAMPLE_TEXTURE2D(_Nor, sampler_Nor, uv - float2(texelSize.x, 0)).rg);
                float3 normalRight = DecodeNormal(SAMPLE_TEXTURE2D(_Nor, sampler_Nor, uv + float2(texelSize.x, 0)).rg);
                
                // 计算法线差异
                float diffUp = 1.0 - dot(normal, normalUp);
                float diffDown = 1.0 - dot(normal, normalDown);
                float diffLeft = 1.0 - dot(normal, normalLeft);
                float diffRight = 1.0 - dot(normal, normalRight);
                
                // 取最大差异
                float maxDiff = max(max(diffUp, diffDown), max(diffLeft, diffRight));
                
                return maxDiff * _NormalSensitivity;
            }
            
            // Roberts交叉边缘检测（另一种选择，更细的边缘）
            float RobertsDepthEdge(float2 uv, float depth, float outlineWidth)
            {
                float2 texelSize = _MainTex_TexelSize.xy * outlineWidth;
                
                float depthCenter = depth;
                float depthRight = SAMPLE_TEXTURE2D(_Dep, sampler_Dep, uv + float2(texelSize.x, 0)).r;
                float depthDown = SAMPLE_TEXTURE2D(_Dep, sampler_Dep, uv + float2(0, texelSize.y)).r;
                float depthDownRight = SAMPLE_TEXTURE2D(_Dep, sampler_Dep, uv + texelSize).r;
                
                float edge = 0.0;
                edge += abs(depthCenter - depthDownRight);
                edge += abs(depthRight - depthDown);
                
                return edge * _DepthSensitivity;
            }
            
            float4 frag (v2f i) : SV_Target
            {
                float2 screenUV = i.screenPos.xy / i.screenPos.w;
                
                // 采样纹理
                float4 color = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, screenUV);
                float2 encodedNormal = SAMPLE_TEXTURE2D(_Nor, sampler_Nor, screenUV).rg;
                float rawDepth = SAMPLE_TEXTURE2D(_Dep, sampler_Dep, screenUV).r;
                
                // 解码法线和深度
                float3 normal = DecodeNormal(encodedNormal);
                float depth = LinearEyeDepth(rawDepth, _ZBufferParams);
                
                // 边缘检测
                float depthEdge = SobelDepth(screenUV, depth , _OutlineWidth/(depth*4.0));
                float normalEdge = NormalEdge(screenUV, normal, _OutlineWidth/(depth*4.0));
                
                // Roberts边缘检测（可选，效果更锐利）
                // float robertsEdge = RobertsDepthEdge(screenUV, rawDepth);
                
                // 合并边缘检测结果
                float edge = 0.0;
                edge = max(step(_DepthThreshold, depthEdge), step(_NormalThreshold, normalEdge));
                // 或者使用混合
                // edge = saturate(depthEdge * _DepthSensitivity + normalEdge * _NormalSensitivity);
                
                // 可选：使用平滑step函数获得柔和的边缘
                // float smoothEdge = smoothstep(_DepthThreshold, _DepthThreshold + 0.1, depthEdge);
                // smoothEdge = max(smoothEdge, smoothstep(_NormalThreshold, _NormalThreshold + 0.1, normalEdge));
                
                // 应用描边
                float4 outlineColor = lerp(color, _OutlineColor, edge);
                
                // 可选：叠加描边（保持原色，只添加描边）
                //float4 outlineColor = color;
                //outlineColor.rgb = lerp(outlineColor.rgb, _OutlineColor.rgb, edge);
                
                return outlineColor;
                //return color;
            }
            ENDHLSL
        }
    }
}