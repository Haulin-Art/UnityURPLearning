Shader "Unlit/S_Ground"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _MainCol ("主颜色",Color) = (0.23,0.33,0.0,0.0)
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

            #include "Assets/ZMD/Shader/Flow_Drop_Func_Library.hlsl"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                float4 screenPos :TEXCOORD4;
            };

            TEXTURE2D(_MainTex);SAMPLER(sampler_MainTex);
            float4 _MainTex_ST;
            float4 _MainCol;

            TEXTURE2D(_CSShadow);SAMPLER(sampler_CSShadow);
            TEXTURE2D(_POSpcf);
            SAMPLER(sampler_POSpcf);

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = TransformObjectToHClip(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.screenPos = ComputeScreenPos(o.vertex);
                return o;
            }

            float4 frag (v2f i) : SV_Target
            {
                //// ================== 采样自定义高精度阴影Pass ================================================
                float2 screenUV = i.screenPos.xy / i.screenPos.w;
                float depth = LinearEyeDepth(i.vertex.z,_ZBufferParams);
                /*
                // =================== 对PCF阴影进行模糊采样 =============================
                float2 w = float2(0.001,0.0); // 固定步长
                float dd = clamp(depth*2.0,0.3,5.0); // 限制深度
                w /= dd; // 根据深度变换步长，越远越小
                float s0 = SAMPLE_TEXTURE2D(_POSpcf, sampler_POSpcf, screenUV).r;
                float count = 0.0; //记录有效点数
                float total = 0.0; // 总数
                int kenelC = 2;
                for(float k = -kenelC;k<=kenelC;k++)
                {
                    for(float j = -kenelC;j<=kenelC;j++)
                    {
                        float2 newuv = screenUV + w.x*float2(k,j);
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
                float shadow =  total/count;
                */
                
                float shadow =  SAMPLE_TEXTURE2D(_CSShadow, sampler_CSShadow, screenUV).r;

                // 灯光数据
                Light mainLight = GetMainLight();
                float3 lightCol = mainLight.color;


                // sample the texture
                float col = SAMPLE_TEXTURE2D(_MainTex,sampler_MainTex, i.uv).r;
                float3 color = lerp(_MainCol.x,_MainCol.y,col) * lightCol;

                // 远处雾气
                //float fog = smoothstep(4.0,10.0,depth);
                //color = lerp(color,pow(0.9,2.2)*float3(1,1,1),fog);
                
                // 雨水
                // ======================== 流水 ==============================
                float T = _Time.y;
                float t = T*2;
                float drop = StaticDrops(i.uv*3.0,t/3.0,0.8);


                //return float4(lerp(1.0,0.5,drop) * float3(1,1,1) ,1.0 );
                return float4(color*lerp(shadow,1.0,0.5) * lerp(1.0,0.5,drop)* float3(1,1,1) ,1.0 );
            }
            ENDHLSL
        }
    }
}
