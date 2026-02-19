Shader "Unlit/coastLineWaveShader"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _WaterCol ("浅水颜色",Color) = (0.0,0.3,0.6)
        _DeepWaterCol ("深水颜色",Color) = (0.0,0.3,0.6)
        _VectorDisMap ("矢量置换纹理", 2D) = "white" {}
        _VectorDisMapNormal("矢量置换纹理法线", 2D) = "white" {}
        _VectorDisMapScale ("矢量置换整体强度", Float) = 3.0
        _VDMXScale ("矢量置换x强度", Range(-2,2)) = 1.0
        _VDMYScale ("矢量置换y强度", Range(-2,2)) = -0.2
        _VDMXOffset ("矢量置换x偏移", Float) = 0.0
        _VDMYOffset ("矢量置换y偏移", Float) = -0.5
        _OceanNorTex ("海面法线", 2D) = "white" {}
        _Speed ("波动速度", Range(-5.0,5.0)) = 0.2
        _SineCount ("正弦波数量", Range(0.0,5.0)) = 3.0
        _sineScale ("正弦波幅度", Range(-1.0,1.0)) = 0.15
    }
    SubShader
    {
        Tags { 
            "RenderType" = "Transparent" // 标记为透明物体，用于后处理等
            "Queue" = "Transparent"      // 透明队列，在不透明物体后渲染
            "IgnoreProjector" = "True"   // 忽略投影器（透明物体通常不接收投影）
        }
        Cull Off

        
        // Pass 通用语块
        HLSLINCLUDE
            //#define PI 3.14159265359
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #pragma vertex vert
            #pragma fragment frag
            CBUFFER_START(UnityPerMaterial)
                float3 _WaterCol;
                float3 _DeepWaterCol;
                float _VectorDisMapScale;
                float _VDMXScale;
                float _VDMYScale;
                float _VDMXOffset;
                float _VDMYOffset;
                float _Speed;
                float _SineCount;
                float _sineScale;
            CBUFFER_END
            TEXTURE2D(_CameraDepthTexture);SAMPLER(sampler_CameraDepthTexture); 
            float4 _VectorDisMap_ST;
            TEXTURE2D(_VectorDisMap);SAMPLER(sampler_VectorDisMap); 
            TEXTURE2D(_VectorDisMapNormal);SAMPLER(sampler_VectorDisMapNormal); 
            TEXTURE2D(_OceanNorTex);SAMPLER(sampler_OceanNorTex); 
            float4 _OceanNorTex_ST;

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal : NORMAL;
                float4 tangent : TANGENT;
            };
            struct v2f
            {
                float2 uv : TEXCOORD0;
                float3 worldPos : TEXCOORD1;
                float3 T : TEXCOORD2;
                float3 B : TEXCOORD3;
                float3 N : TEXCOORD4; 
                float4 pos : SV_POSITION;
                float3 vertCol : COLOR0;
                float2 animUV : TEXCOORD5;
                float4 screenUV : TEXCOORD6;
            };
            // 给UV添加动画的函数
            float2 animUV(float2 uv, float time,float4 uv_ST)
            {
                float w = 0.01;
                float2 newUV = uv*uv_ST.xy + uv_ST.zw;
                float nu = frac(newUV.x - time*_Speed);
                nu += -_sineScale * sin((newUV.y*2.0 - 1.0) * PI*_SineCount);
                nu = clamp(frac(nu),w,1.0-w);
                float nv = pow(abs(frac(newUV.y)-0.5),0.97);
                nv = -1.0*clamp(uv.x*1.5 - nv,w,1.0-w);
                newUV = float2(nu,nv);
                return newUV;
            }
            v2f vert (appdata v)
            {
                v2f o;
                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;

                // Unity内置宏：自动处理模型缩放/旋转，返回归一化的世界空间向量
                // 这里必须使用这两个
                float3 N = TransformObjectToWorldNormal(v.normal); // 世界空间法线
                float3 T = TransformObjectToWorldDir(v.tangent.xyz); // 世界空间切线
                // 重新正交化切线（消除插值/缩放带来的偏差，确保T与N垂直）
                T = normalize(T - dot(T, N) * N);
                // 计算副切线（保持正交性）
                float3 B = cross(N, T) * v.tangent.w;
                
                o.T = T;
                o.B = B;
                o.N = N;
                float3x3 TBN = float3x3(T, B, N);

                o.uv = v.uv;
                float2 newUV = animUV(o.uv, _Time.y, _VectorDisMap_ST);
                o.animUV = newUV;

                // ================== 向量置换图部分 ========================
                float3 disp = SAMPLE_TEXTURE2D_LOD(_VectorDisMap,sampler_VectorDisMap,newUV,0.0).xyz;
                // 正确解码这张特殊编码的矢量置换图，以下属于正确采样这张图的手段
                // x是向前轴，y是向上轴，z是浮沫范围
                // Gamma解码
                disp = pow(disp,0.45);
                disp -= 0.5;
                disp *= float3(_VDMXScale,_VDMYScale,0.5);
                disp = float3(disp.x,0.0,disp.y);
                disp *= _VectorDisMapScale;
                disp += float3(_VDMXOffset,0.0,_VDMYOffset);
                float3 worldDisp = mul(TBN, disp);
                // 向量置换2
                float3 waveDis = SAMPLE_TEXTURE2D_LOD(_OceanNorTex,sampler_OceanNorTex,v.uv,0.0).xyz;
                waveDis = 0.05*(waveDis*2.0-1.0);
                float3 waveDis_world = mul(TBN,waveDis);
                // ================== 顶点位移计算 ========================
                float3 newPos = v.vertex.xyz + float3(worldDisp.x,worldDisp.y,0.0)+waveDis_world;
                o.worldPos = newPos;
                
                o.pos = TransformObjectToHClip(float4(newPos,1.0));
                o.vertCol = disp;

                o.screenUV = ComputeScreenPos(o.pos);
                return o;
            }
        ENDHLSL

        Pass
        {
            Tags {"LightMode" = "SRPDefaultUnlit"}//"LightMode"="UniversalForward" }
            ZWrite On
            //Cull Back
            ColorMask 0
            HLSLPROGRAM
            float4 frag (v2f i) : SV_Target
            {   
                return 0;
            }
            ENDHLSL
        }
        
        Pass
        {
            Tags { 
                "LightMode" = "UniversalForward"  // 关键：正确的光照模式
            }
            ZWrite Off
            //ZTest Equal  // 改为Equal，只渲染深度相等的片段
            Cull Off
            //Cull Front
            Blend SrcAlpha OneMinusSrcAlpha

            HLSLPROGRAM

            // 计算浮沫的函数
            float foamMask(float2 fuv,float2 fanimUV, float fDefaultFoam,float fFoamTex)
            {
                // fuv: 原始uv坐标，fanimUV: 动画uv坐标，fDefaultFoam：贴图浮沫范围，fFoamTex：浮沫纹理采样值
                fDefaultFoam = pow(fDefaultFoam,0.77);
                float midFoam = pow(fanimUV.x,0.7) * pow(fuv.x,4.8);
                midFoam = pow(midFoam,0.9);
                float nearFoam = smoothstep(0.85,1.0,fuv.x);
                float foam = midFoam + nearFoam + fDefaultFoam;
                foam = clamp(foam,0.0,1.0);
                //float fFoamTex = formTex.w;
                foam *= fFoamTex;
                return foam;
            }

            float4 frag (v2f i) : SV_Target
            {
                // 计算动画UV
                float2 newUV = animUV(i.uv, _Time.y, _VectorDisMap_ST);
                // 计算法线
                float3 screenNormal = normalize(cross(ddy(i.worldPos),ddx(i.worldPos)));
                

                float3 dispCol = SAMPLE_TEXTURE2D(_VectorDisMap, sampler_VectorDisMap,i.animUV).rgb;
                // ================ 法线计算部分 ====================
                float3 dispN = SAMPLE_TEXTURE2D(_VectorDisMapNormal,sampler_VectorDisMapNormal, newUV).rgb;
                dispN = pow(dispN,0.45);
                //dispN = normalize(dispN*2.0-1.0);
                float3 dispN_world = normalize(mul(float3x3(i.T, i.B, i.N), dispN));
                dispN_world = dispN_world * float3(1,1,1);
                dispN_world = normalize(dispN_world);
                // 波动海面贴图
                float4 waveTex = SAMPLE_TEXTURE2D(_OceanNorTex,sampler_OceanNorTex, i.uv * _OceanNorTex_ST.xy + _OceanNorTex_ST.zw);
                float3 waveN = waveTex.xyz * 2.0 - 1.0;
                float3 waveN_world = normalize(mul(float3x3(i.T, i.B, i.N), waveN));
                // 修正法向z的正负，因为uv改变了正确的位置
                float2 kUV = i.uv*_VectorDisMap_ST.xy + _VectorDisMap_ST.zw;
                float xiuzN = sign(frac(kUV.y)-0.5);
                // 混合两个法线
                float3 normal = normalize(dispN_world + waveN_world*0.3);
                normal = screenNormal;

                // ================ 浮沫计算部分 ====================
                float foam = foamMask(i.uv, newUV, dispCol.z, waveTex.w);

                // ================= 修正部分 ====================
                // 这个xz用于修正在uv.x接近0和1时unity内uv插值错误问题
                float xz = (1.0-step(newUV.x,0.05))*(1.0-step(0.95,newUV.x));
                xz += smoothstep(0.45,1.0,i.uv.x);
                xz = clamp(xz,0.0,1.0);
                foam *= xz;

                // ================= Albedo最终颜色计算 ================
                // rd
                float3 ro = _WorldSpaceCameraPos;
                float3 rd = normalize(_WorldSpaceCameraPos - i.worldPos); // 视角方向（世界空间）
                float2 screenUV = i.screenUV.xy/i.screenUV.w;
                float depth = SAMPLE_TEXTURE2D(_CameraDepthTexture,sampler_CameraDepthTexture,screenUV).r;
                float depthLinear = LinearEyeDepth(depth,_ZBufferParams);
                float selfDepthLinear = LinearEyeDepth(i.pos.z,_ZBufferParams);
                float rampMask = smoothstep(0.0,2.0,depthLinear - selfDepthLinear);
                // 混合浅水区与深水区
                float3 albedo = lerp(_WaterCol,_DeepWaterCol,rampMask);
                // 加入浮沫
                albedo = lerp(albedo,float3(1.0,1.0,1.0),clamp(foam*1.5,0.0,1.0));
                
                // ================= 漫反射计算 ====================
                //float3 viewDir = normalize(_WorldSpaceCameraPos - i.worldPos); // 视角方向（世界空间）
                Light ld = GetMainLight();
                float3 lightDir = normalize(ld.direction); // 主光源方向（世界空间，ForwardBase通道）
                float3 lightColor = ld.color; // 主光源颜色
                float3 diff = max(dot(normal, lightDir), 0.0);
                float3 diffCol = (diff + 0.1) * lightColor;

                // ================ 高光计算 ========================
                float3 h = normalize(rd+lightDir);
                float specular = pow(max(0.0,dot(h,normal)),15.0);
                float3 specCol = specular*lightColor;
                specCol = float3(0,0,0);
                
                // 颜色合成
                diffCol *= albedo;
                diffCol = saturate(diffCol+specCol);
                
                // ================= 透明计算部分 =================
                // 靠近海岸线的地方会更透明
                float trans = smoothstep(0.8,1.0,i.uv.x);
                trans = 1.0 - trans;
                // 浮沫不会透明
                trans += foam*2.0;
                trans = clamp(trans,0.0,0.95);

                //float4 col = tex2D(_MainTex, i.animUV);
                //float3 dispCol = SAMPLE_TEXTURE2D(_VectorDisMap,sampler_VectorDisMap, i.animUV).rgb;

                float w = 0.01;
                //float2 kUV = i.uv*_VectorDisMap_ST.xy + _VectorDisMap_ST.zw;
                //float nv = pow(abs(frac(kUV.y)-0.5),0.97);
                //nv = 1.0*clamp(i.uv.x*1.5 - nv,w,1.0-w);
                //return float4(depth*float3(1,1,1),1.0);
                return float4(diffCol,trans);
                //return float4(diffCol,1.0);
            }
            ENDHLSL
        }
            
    }
}
        
        /*
        // ========== Pass2：正常渲染颜色（透明混合） ==========
        Pass
        {
            // 步骤2：开启混合+关闭深度写入（此时深度缓冲已有Pass1的深度）
            Blend SrcAlpha OneMinusSrcAlpha // 常规透明混合
            ZWrite Off                      // 关闭深度写入（避免覆盖Pass1的深度）
            ZTest LEqual                    // 保留深度测试（只渲染深度缓冲前的像素）
            Cull Off                        // 双面渲染

            
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"
            #include "Lighting.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal : NORMAL;
                float4 tangent : TANGENT;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float3 worldPos : TEXCOORD1;
                float3 T : TEXCOORD2;
                float3 B : TEXCOORD3;
                float3 N : TEXCOORD4; 
                float4 pos : SV_POSITION;
                float3 vertCol : COLOR0;
                float2 animUV : TEXCOORD5;
                float4 screenUV : TEXCOORD6;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;
            float3 _WaterCol;
            float3 _DeepWaterCol;
            sampler2D _VectorDisMap;
            float4 _VectorDisMap_ST;
            sampler2D _VectorDisMapNormal;
            float _VectorDisMapScale;
            float _VDMXScale;
            float _VDMYScale;
            float _VDMXOffset;
            float _VDMYOffset;
            sampler2D _OceanNorTex;
            float4 _OceanNorTex_ST;
            float _Speed;
            float _SineCount;
            float _sineScale;

            sampler2D _CameraDepthTexture;
            //TEXTURE2D(_CameraDepthTexture);SAMPLER(sampler_CameraDepthTexture); 

            // 给UV添加动画的函数
            float2 animUV(float2 uv, float time,float4 uv_ST)
            {
                float w = 0.01;
                float2 newUV = uv*uv_ST.xy + uv_ST.zw;
                float nu = frac(newUV.x - time*_Speed);
                nu += -_sineScale * sin((newUV.y*2.0 - 1.0) * UNITY_PI*_SineCount);
                nu = clamp(frac(nu),w,1.0-w);
                float nv = pow(abs(frac(newUV.y)-0.5),0.97);
                nv = -1.0*clamp(uv.x*1.5 - nv,w,1.0-w);
                newUV = float2(nu,nv);
                return newUV;
            }
            // 计算浮沫的函数
            float foamMask(float2 fuv,float2 fanimUV, float fDefaultFoam,float fFoamTex)
            {
                // fuv: 原始uv坐标，fanimUV: 动画uv坐标，fDefaultFoam：贴图浮沫范围，fFoamTex：浮沫纹理采样值
                fDefaultFoam = pow(fDefaultFoam,0.77);

                float midFoam = pow(fanimUV.x,0.7) * pow(fuv.x,4.8);
                midFoam = pow(midFoam,0.78);
                float nearFoam = smoothstep(0.85,1.0,fuv.x);
                float foam = midFoam + nearFoam + fDefaultFoam;
                foam = clamp(foam,0.0,1.0);

                //float fFoamTex = formTex.w;
                foam *= fFoamTex;
                return foam;
            }

            v2f vert (appdata v)
            {
                v2f o;
                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;

                // Unity内置宏：自动处理模型缩放/旋转，返回归一化的世界空间向量
                float3 N = UnityObjectToWorldNormal(v.normal); // 世界空间法线
                float3 T = UnityObjectToWorldDir(v.tangent.xyz); // 世界空间切线
                // 重新正交化切线（消除插值/缩放带来的偏差，确保T与N垂直）
                T = normalize(T - dot(T, N) * N);
                // 计算副切线（保持正交性）
                float3 B = cross(N, T) * v.tangent.w;
                
                o.T = T;
                o.B = B;
                o.N = N;
                float3x3 TBN = float3x3(T, B, N);

                o.uv = v.uv;
                float2 newUV = animUV(o.uv, _Time.y, _VectorDisMap_ST);
                o.animUV = newUV;

                // ================== 向量置换图部分 ========================
                float3 disp = tex2Dlod(_VectorDisMap, float4(newUV,0.0,0.0)).xyz;
                // 正确解码这张特殊编码的矢量置换图，以下属于正确采样这张图的手段
                // x是向前轴，y是向上轴，z是浮沫范围
                // Gamma解码
                disp = pow(disp,0.45);
                disp -= 0.5;
                disp *= float3(_VDMXScale,_VDMYScale,0.5);
                disp = float3(disp.x,0.0,disp.y);
                disp *= _VectorDisMapScale;
                disp += float3(_VDMXOffset,0.0,_VDMYOffset);

                // ================== 顶点位移计算 ========================
                float3 worldDisp = mul(TBN, disp);
                float3 newPos = v.vertex.xyz + float3(worldDisp.x,worldDisp.y,0.0);
                
                o.pos = UnityObjectToClipPos(float4(newPos,1.0));
                o.vertCol = disp;

                o.screenUV = ComputeScreenPos(o.pos);
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                float2 w = float2(0.015,0.0);
                float2 newUV = animUV(i.uv, _Time.y, _VectorDisMap_ST);
                
                fixed4 col = tex2D(_MainTex, i.animUV);
                fixed3 dispCol = tex2D(_VectorDisMap, i.animUV).rgb;

                // ================ 法线计算部分 ====================
                fixed3 dispN = tex2D(_VectorDisMapNormal, newUV).rgb;
                dispN = pow(dispN,0.45);
                dispN = normalize(dispN*2.0-1.0);
                fixed3 dispN_world = normalize(mul(float3x3(i.T, i.B, i.N), dispN));
                dispN_world = dispN_world * float3(1,1,1);
                dispN_world = normalize(dispN_world);
                // 波动海面贴图
                float4 waveTex = tex2D(_OceanNorTex, i.uv * _OceanNorTex_ST.xy + _OceanNorTex_ST.zw);
                float3 waveN = waveTex.xyz * 2.0 - 1.0;
                float3 waveN_world = normalize(mul(float3x3(i.T, i.B, i.N), waveN));
                // 混合两个法线
                float normal = normalize(dispN_world + waveN_world*0.3);

                // ================ 浮沫计算部分 ====================
                
                float foam = foamMask(i.uv, newUV, dispCol.z, waveTex.w);

                // ================= 修正部分 ====================
                // 这个xz用于修正在uv.x接近0和1时unity内uv插值错误问题
                float xz = (1.0-step(newUV.x,0.05))*(1.0-step(0.95,newUV.x));
                xz += smoothstep(0.45,1.0,i.uv.x);
                xz = clamp(xz,0.0,1.0);
                foam *= xz;

                // ================= Albedo最终颜色计算 ================
                // rd
                float3 ro = _WorldSpaceCameraPos;
                float3 rd = normalize(_WorldSpaceCameraPos - i.worldPos); // 视角方向（世界空间）
                float2 screenUV = i.screenUV.xy/i.screenUV.w;
                float depth = tex2D(_CameraDepthTexture,screenUV).r;
                float depthLinear = LinearEyeDepth(depth);
                float selfDepthLinear = LinearEyeDepth(i.pos.z);
                float rampMask = smoothstep(0.0,2.0,depthLinear - selfDepthLinear);
                // 混合浅水区与深水区
                float3 albedo = lerp(_WaterCol,_DeepWaterCol,rampMask);
                // 加入浮沫
                albedo = lerp(albedo,float3(1.0,1.0,1.0),clamp(foam*1.5,0.0,1.0));
                

                // ================= 漫反射计算 ====================
                //float3 viewDir = normalize(_WorldSpaceCameraPos - i.worldPos); // 视角方向（世界空间）
                float3 lightDir = normalize(_WorldSpaceLightPos0.xyz); // 主光源方向（世界空间，ForwardBase通道）
                fixed3 lightColor = _LightColor0.rgb; // 主光源颜色
                fixed3 diff = max(dot(normal, lightDir), 0.0);
                fixed3 diffCol = (diff + 0.1) * lightColor;

                // ================ 高光计算 ========================
                float3 h = normalize(rd+lightDir);
                float specular = pow(max(0.0,dot(h,normal)),15.0);
                float3 specCol = specular*lightColor;
                specCol = float3(0,0,0);
                
                // 颜色合成
                diffCol *= albedo;
                diffCol = saturate(diffCol+specCol);
                
                // ================= 透明计算部分 =================
                // 靠近海岸线的地方会更透明
                float trans = smoothstep(0.8,1.0,i.uv.x);
                trans = 1.0 - trans;
                // 浮沫不会透明
                trans += foam*2.0;
                trans = clamp(trans,0.0,1.0);
                
                //return fixed4(finalCol,1.0);
                //return fixed4(specular*float3(1,1,1),trans);
                return fixed4(diffCol,trans);
                //return fixed4(screenUV,0.0,1.0);
                //return fixed4(specular*float3(1,1,1),1);
            }
            ENDCG
        }
        */
/*
    }
    FallBack "Unlit/Transparent" // 回退到透明Shader，增加兼容性
}
*/
