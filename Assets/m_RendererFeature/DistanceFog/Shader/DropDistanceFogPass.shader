Shader "Unlit/DropDistanceFogPass"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _RO ("RO", Vector) = (0,0,0,0)
        //_CameraWorldPos ("_CameraWorldPos", Vector) = (0,0,0,0)

        //_CameraDepthTexture ("_CameraDepthTexture", 2D) = "black" {}
    }
    SubShader
    {
        Tags { "RenderType"="Opaque"
              "RenderPipeline"="UniversalPipeline" // URP管线标签（必须）
              "Queue"="Overlay" 
              }
        LOD 100
        ZTest Always
        ZWrite Off
        Cull Off

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            //#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/UniversalRenderPipeline.hlsl"
            //#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            //#include "Assets/ZMD/Shader/Flow_Drop_Func_Library.hlsl"


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
            // URP 规范：声明纹理+采样器（替代传统 sampler2D）
            TEXTURE2D(_MainTex); 
            SAMPLER(sampler_MainTex); 
            float4 _MainTex_ST;
            
            TEXTURE2D(_CameraDepthTexture);
            SAMPLER(sampler_CameraDepthTexture); 

            // C#传递的参数
            //float3 _CameraWorldPos;       // ro：相机世界位置
           // float4x4 _InvViewProj;        // 逆视投影矩阵
            //#ifndef S(a,b,t)
            #define S(a,b,t) smoothstep(a,b,t)
            //#endif                                                       


            float3 N13(float p) {
                // 来自DAVE HOSKINS的哈希函数
                float3 p3 = frac(float3(p,p,p) * float3(0.1031, 0.11369, 0.13787));
                p3 += dot(p3, p3.yzx + 19.19);
                return frac(float3((p3.x + p3.y)*p3.z, (p3.x+p3.z)*p3.y, (p3.y+p3.z)*p3.x));
            }

            float4 N14(float t) {
                return frac(sin(t*float4(123.0, 1024.0, 1456.0, 264.0)) * float4(6547.0, 345.0, 8799.0, 1564.0));
            }

            float N(float t) {
                return frac(sin(t*12345.564)*7658.76);
            }

            float Saw(float b, float t) {
                return S(0.0, b, t) * S(1.0, b, t);
            }
            float2 DropLayer2(float2 uv, float t,float scale=1.0) {
                float2 UV = uv;
                uv.y += t * 0.75;
                float2 a = float2(6.0, 1.0);
                float2 grid = a * 2.0;
                float2 id = floor(uv * grid);

                float colShift = N(id.x); 
                uv.y += colShift;
                id = floor(uv * grid);
                float3 n = N13(id.x * 35.2 + id.y * 2376.1);
                float2 st = frac(uv * grid) - float2(0.5, 0.0);

                float x = n.x - 0.5;
                float y = UV.y * 20.0;
                float wiggle = sin(y + sin(y));
                //x += wiggle * (0.5 - abs(x)) * (n.z - 0.5);
                //x *= 0.7;

                float ti = frac(t + n.z);
                ti = 1.0;
                y = (Saw(0.85, ti) - 0.5) * 0.9 + 0.5;
                float2 p = float2(x, y);

                float d = length((st - p) * a.yx);
                float mainDrop = S(0.3*scale, 0.0, d);

                float r = sqrt(S(0.5, y, st.y));
                float cd = abs(st.x - x);
                float trail = S((0.15*scale) * r , 0.0 * r * r, cd);
                float trailFront = S(-0.02, 0.02, st.y - y);
                trail *= trailFront * r * r;

                y = UV.y;
                float trail2 = S(0.2 * r, 0.0, cd);
                float droplets = max(0.0, (sin(y * (1.0 - y) * 120.0) - st.y)) * trail2 * trailFront * n.z;
                y = frac(y * 10.0) + (st.y - 0.5);
                float dd = length(st - float2(x, y));
                droplets = S(0.3, 0.0, dd);
                float m = mainDrop ;//;+ droplets * r * trailFront;

                return float2(mainDrop, trail);
            }
            float yvshui(float2 uv, float t)
            {
                float2 drop = DropLayer2(uv,t*1.5,0.15);
                float2 drop2 = DropLayer2(uv*1.5,t/1.5,0.055);
                float2 drop3 = DropLayer2(uv*5,t/2.0,0.025);

                return saturate(drop.y + drop2.y + drop3.y);
            }


            v2f vert (appdata v)
            {
                v2f o;
                o.uv = v.uv;
                o.vertex = TransformObjectToHClip(v.vertex.xyz); 
                // // 错误修正：ComputeScreenPos的参数是裁剪空间顶点（o.vertex），而非v.screenPos（appdata无此成员）
                o.screenPos = ComputeScreenPos(o.vertex);
                return o;
            }

            float4 frag (v2f i) : SV_Target
            {
                // 屏幕UV
                float2 screenUV = i.screenPos.xy / i.screenPos.w;
                //float depth = SampleSceneDepth(screenUV); // 替换你的SAMPLE_TEXTURE2D
                float depth = SAMPLE_TEXTURE2D(_CameraDepthTexture,sampler_CameraDepthTexture,screenUV).x;
                // float4 _ZBufferParams; Unity内置深度参数（x=1-far/near, y=far/near, z=x/far, w=y/far）
                // 方式1：转换为「0（近裁面）~1（远裁面）」的线性相对深度（推荐）
                float linear01Depth = Linear01Depth(depth, _ZBufferParams);
                // 方式2：转换为「实际世界空间距离（米）」（比如近裁面1米，远裁面100米，值为1~100）
                float linearWorldDepth = LinearEyeDepth(depth, _ZBufferParams); // 视空间深度（相机空间）

                float4 col = SAMPLE_TEXTURE2D(_MainTex,sampler_MainTex, i.uv);
                
                
                //float fogMask = smoothstep(5.0,10.0,linearWorldDepth);
                //float3 finalCol = lerp(col.rgb,pow(0.9,2.2),fogMask);



                /*
                // ========== 步骤1：获取ro（光线原点） ==========
                float3 ro = _CameraWorldPos; // 直接使用相机世界位置
                // ========== 步骤3：计算基础rd（光线方向，未结合深度） ==========
                // 1. 把屏幕UV转成裁剪空间坐标（范围：x/y∈[-1,1]）
                float4 clipPos = float4(screenUV * 2.0 - 1.0, 1.0, 1.0);
                // 2. 逆视投影矩阵：裁剪空间 → 世界空间
                float4 worldPos = mul(_InvViewProj, clipPos);
                worldPos /= worldPos.w; // 透视除法
                // 3. 计算光线方向并单位化
                float3 rd = normalize(worldPos.xyz - ro);

                float3 camForward = normalize(mul((float3x3)_InvViewProj, float3(0,0,-1)));

                float ll = 0.0;

                float planeX = -24.7;
                float planeZ = 13;

                float thickness = 0.015;
                float fre = 1.5;
                float3 hitPoint;
                if(abs(rd.y)>1e-6)
                {
                    float tx = (planeX - ro.x) / rd.x;
                    //float tz = (planeZ - ro.z) / rd.z;
                    //if(tx>0 && tz >0 && tx<linearWorldDepth && tz<linearWorldDepth)
                    hitPoint = ro + rd * (tx);
                    float mask = step(frac(abs(hitPoint.z)*fre),thickness) + step(frac(abs(hitPoint.y)*fre),thickness);
                    //mask += step(frac(abs(hitPoint.x)*2.0),0.01);
                    if(tx>0  && tx<linearWorldDepth && mask)
                    {
                        //hitPoint = ro + rd * t;
                        //if(hitPoint.y<5.0)
                        ll = 0.7; // 如果“经过”，显示红色
                    }
                }
                //float kt = 
                */
                // ======================== 流水 ==============================
                float T = _Time.y;
                float t = T*2;

                float appDrop = smoothstep(0.5,3.0,linearWorldDepth); // 近处没有雨水效果
                float d1 = yvshui(screenUV, t);
                float suaijian = lerp(1.0,0.85,d1); // 雨水使得颜色衰减
                suaijian = lerp(1.0,suaijian,appDrop); // 近处没有雨水效果
                float2 e = float2(0.001,0.0);
                float dx = yvshui(screenUV+e.xy, t);
                float dy = yvshui(screenUV+e.yx, t);

                float2 uuvv = float2(dx - d1, dy - d1);

                float3 newCol =  SAMPLE_TEXTURE2D(_MainTex,sampler_MainTex, i.uv- uuvv*0.0025).rgb;
                float3 cc = lerp(col,newCol,appDrop); // 靠近了没有雨水效果


                // 远处雾气
                float fogMask = smoothstep(5.0,10.0,linearWorldDepth);
                float3 finalCol = lerp(cc,pow(0.7,2.2),fogMask);

                //return float4(d1*float3(1,1,1),1);
                return float4(suaijian*finalCol*float3(1,1,1),1);
            }
            ENDHLSL
        }
    }
}
