Shader "Unlit/PlaneFog"
{
    Properties
    {
        _Density ("密度纹理", 2D) = "white" {}
        _Normal ("法向纹理",2D) = "bump" {}
        _Flowmap ("流动贴图",2D) = "black" {}
        _FlowSpeed ("流动速度", Range(0, 2)) = 0.5
        _FlowIntensity ("流动强度", Range(0, 1)) = 0.3
        _FogColor ("雾气颜色", Color) = (1, 1, 1, 1)
        _AmbientStrength ("环境光强度", Range(0, 1)) = 0.2
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" 
               "Queue"="Transparent"
               "IgnoreProjector"="True"
             }
        LOD 100

        Pass
        {
            Blend SrcAlpha OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_Density);SAMPLER(sampler_Density);
            TEXTURE2D(_Normal);SAMPLER(sampler_Normal);
            TEXTURE2D(_Flowmap);SAMPLER(sampler_Flowmap);
            
            float _FlowSpeed;
            float _FlowIntensity;
            float4 _FogColor;
            float _AmbientStrength;

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float4 normal : NORMAL;
                float4 tangent : TANGENT;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                float3 normal : TEXCOORD1;
                float4 tangent : TEXCOORD2;
                float3 posWS : TEXCOORD3;
            };

            // 自定义函数区
            // 解码RGB法线贴图，映射到-1~1
            float3 DecodeNormalRGB(float4 packedNormal)
            {
                #ifdef UNITY_NO_DXT5nm
                    // 如果纹理是RGB格式，直接映射
                    float3 normal = packedNormal.rgb * 2.0 - 1.0;
                #else
                    // 如果是DXT5nm格式，使用UnpackNormal
                    // UnpackNormal是专门为Unity的DXT5nm压缩格式设计的，只有RG通道的推荐使用
                    float3 normal = UnpackNormal(packedNormal);
                #endif
                return normalize(normal);
            }
            // 自定义函数区结束

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = TransformObjectToHClip(v.vertex);
                o.uv = v.uv;

                // 这是什么操作
                // 函数将模型空间的法线和切线转换为世界空间
                VertexNormalInputs normalInput = GetVertexNormalInputs(v.normal, v.tangent);
                // 用于处理镜像变换时的副切线方向问题
                real sign = v.tangent.w * GetOddNegativeScale();
                o.normal = normalInput.normalWS;
                // 存储的世界空间法线和切线（带符号）用于在片元着色器中构建TBN矩阵
                o.tangent = real4(normalInput.tangentWS,sign);

                o.posWS = TransformObjectToWorld(v.vertex).xyz;

                return o;
            }

            float4 frag (v2f i) : SV_Target
            {
                float2 flowUV = SAMPLE_TEXTURE2D(_Flowmap, sampler_Flowmap, i.uv).rg * 2.0 - 1.0;
                float phase0 = frac(_Time.y * _FlowSpeed);
                float phase1 = frac(phase0 + 0.5);
                
                float2 uv0 = i.uv + flowUV * phase0 * _FlowIntensity;
                float2 uv1 = i.uv + flowUV * phase1 * _FlowIntensity;
                
                float trans0 = SAMPLE_TEXTURE2D(_Density, sampler_Density, uv0).r;
                float trans1 = SAMPLE_TEXTURE2D(_Density, sampler_Density, uv1).r;
                
                float flowWeight = abs(phase0 - 0.5) * 2.0;
                float trans = lerp(trans0, trans1, flowWeight);
                
                float3 norTS0 = DecodeNormalRGB(SAMPLE_TEXTURE2D(_Normal, sampler_Normal, uv0));
                float3 norTS1 = DecodeNormalRGB(SAMPLE_TEXTURE2D(_Normal, sampler_Normal, uv1));
                float3 norTS = lerp(norTS0, norTS1, flowWeight);

                float3x3 TBN = float3x3(i.tangent.xyz, i.tangent.w * cross(i.normal.xyz, i.tangent.xyz), i.normal.xyz);
                float3 norWS = normalize(mul(norTS, TBN));
                norWS = float3(norWS.x, -norWS.y, norWS.z);
                
                Light ld = GetMainLight();
                float3 lightDir = normalize(ld.direction);
                float3 lightColor = ld.color;
                float diff = saturate(dot(lightDir, norWS));
                
                float3 finalColor = _FogColor.rgb * lightColor * (diff + _AmbientStrength);
                return float4(finalColor, trans);
            }
            ENDHLSL
        }
    }
}
