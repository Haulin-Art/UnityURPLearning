Shader "Unlit/cesShadow"
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

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_MainTex);SAMPLER(sampler_MainTex);

            float4x4 _POSvpM;
            TEXTURE2D(_POSpcf);
            SAMPLER(sampler_POSpcf);
            //SAMPLER(sampler_POSMap_LinearClamp); 

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float4 Nor : NORMAL;
            };
            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                float3 posWS : TEXCOORD1;
                float3 norWS : TEXCOORD3;
                float4 screenPos :TEXCOORD4;
            };


            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = TransformObjectToHClip(v.vertex);
                //o.vertex.z = 1.0 - o.vertex.z;
                o.posWS = TransformObjectToWorld(v.vertex);
                o.norWS = TransformObjectToWorldDir(v.Nor).xyz;
                o.screenPos = ComputeScreenPos(o.vertex);
                return o;
            }

            float4 frag (v2f i) : SV_Target
            {
                float2 screenUV = i.screenPos.xy / i.screenPos.w;
                float depth = LinearEyeDepth(i.vertex.z,_ZBufferParams);
                
                Light ld = GetMainLight();
                float3 lightDir = normalize(ld.direction); // 主光源方向（世界空间，ForwardBase通道）

                float lambert = max(0.0,dot(lightDir,i.norWS));
                lambert = saturate(lambert);

                // =================== 对PCF阴影进行模糊采样 =============================
                float2 w = float2(0.001,0.0); // 固定步长
                float dd = clamp(depth*2.0,0.3,5.0); // 限制深度
                w /= dd; // 根据深度变换步长，越远越小
                float s0 = SAMPLE_TEXTURE2D(_POSpcf, sampler_POSpcf, screenUV).r;
                float count = 0.0; //记录有效点数
                float total = 0.0; // 总数
                int kenelC = 2;
                for(float i = -kenelC;i<=kenelC;i++)
                {
                    for(float j = -kenelC;j<=kenelC;j++)
                    {
                        float2 newuv = screenUV + w.x*float2(i,j);
                        newuv = clamp(newuv,0.0,1.0);
                        float s1 = SAMPLE_TEXTURE2D(_POSpcf, sampler_POSpcf, newuv).r;
                        // 只有在变化率小于0.5的地方才会采样，避免导致边缘模糊
                        // 不然会发生特定角度亮部与阴影相互污染的情况，中间会出现一条灰线
                        if(abs(s1-s0)<0.5)
                        {
                            count += 1.0;
                            total += s1;
                        }
                    }
                }
                total /= count;
                float visible = saturate(total*lambert + 0.05);

                
                return float4(visible*float3(1,1,1),1.0);
            }
            ENDHLSL
        }
    }
}
