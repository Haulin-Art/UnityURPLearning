Shader "RendererFeature/Atmosphere/CloudTindalShader"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            float3 _CameraWorldPos;
            float4x4 _InvViewProj; 

            TEXTURE2D(_MainTex);SAMPLER(sampler_MainTex);

            // 来自RF的体积云的信息
            TEXTURE2D(_AtmosRFCloudTex);SAMPLER(sampler_AtmosRFCloudTex);

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


            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = TransformObjectToHClip(v.vertex);
                o.uv = v.uv;
                o.screenPos = ComputeScreenPos(o.vertex);
                return o;
            }

            float frag (v2f i) : SV_Target
            {
                // 计算基础数据
                float2 ScreenUV = i.screenPos.xy / i.screenPos.w;
                Light light = GetMainLight();
                float3 lightDirWS = normalize(light.direction);
                float3 lightColor = light.color;
                // 计算rd
                // 1. 把屏幕UV转成裁剪空间坐标（范围：x/y∈[-1,1]）
                float4 clipPos = float4(ScreenUV * 2.0 - 1.0, 1.0, 1.0);
                // 2. 逆视投影矩阵：裁剪空间 → 世界空间
                float4 worldPos = mul(_InvViewProj, clipPos);
                worldPos /= worldPos.w; // 透视除法
                // 3. 计算光线方向并单位化
                float3 rd = normalize(worldPos.xyz - _CameraWorldPos);

                // ✅ 世界空间 → 裁剪空间方向（URP 官方函数）
                float3 lightDirCS = TransformWorldToHClipDir(lightDirWS);
                // ✅ 转成屏幕空间偏移（NDC → UV）
                float2 lightDirSS = lightDirCS.xy * 0.5 + 0.5;
                // ✅ 控制步进强度（非常重要）
                float stepScale = 0.03;
                float2 offset = lightDirSS * stepScale;

                float mask = smoothstep(0.01,0.03,rd.y);

                //return float4(rd,1.0);

                float totalTindalIntensity = 0.0;

                for (int i = 0; i < 8; i++)
                {
                    float2 uvOfSet = offset * float2(i, i);
                    float CloudTransmice = mask*SAMPLE_TEXTURE2D(_AtmosRFCloudTex,sampler_AtmosRFCloudTex, ScreenUV+uvOfSet).a;
                    CloudTransmice = smoothstep(0.3,0.9,CloudTransmice);
                    totalTindalIntensity += CloudTransmice;
                }

                //return float4(float3(1,1,1)*totalTindalIntensity/8,1);


                float4 col = SAMPLE_TEXTURE2D(_MainTex,sampler_MainTex,ScreenUV);
                //return float4(col.rgb,1);
                return float4(col.rgb + float3(1,1,1)*(totalTindalIntensity/20),1);
            }
            ENDHLSL
        }
    }
}
