Shader "Unlit/S_Actor_Hair"
{
    Properties
    {
        _DTex ("颜色贴图", 2D) = "white" {}
        _NTex ("法线贴图", 2D) = "blue" {}
        _RPTex ("Ramp图", 2D) = "white" {}
        _AOTex ("Ramp图", 2D) = "white" {}
        _AdjustCol ("颜色调整" , Color) = (1.0,1.0,1.0,1.0)
        _MatCapTex ("MatCap贴图", 2D) = "black" {}
        _UseDrop ("使用流水", Float) = 1.0
        _UseShadow ("使用阴影", Float) = 1.0
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent+10" }//头发的顺序要在眼睛之后
        LOD 100

        
        // 第一个Pass,深度写入，负责挡住的部分
        // 精简Pass
        Pass
        {
            Name "DepthWrite"
            Tags {"LightMode" = "SRPDefaultUnlit"}//"LightMode"="UniversalForward" }
            ZWrite On
            //ColorMask 0
            Blend SrcAlpha OneMinusSrcAlpha
            Cull Back
            //Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            //ZTest Always
            //Cull Back
            
            // 判断在眼睛眉毛部分的
            Stencil
            {
                Ref 1
                Comp Equal
                Pass Keep
            }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            
            
            
            TEXTURE2D(_DTex);SAMPLER(sampler_DTex);
            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };
            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                float3 posWS : TEXCOORD1;
                float3 norWS : TEXCOORD3;
                float4 tanWS : TEXCOORD5;
            };
            v2f vert (appdata v) 
            {
                v2f o;
                o.uv = v.uv;
                o.vertex = TransformObjectToHClip(v.vertex.xyz); 
                return o;
            }
            float4 frag (v2f i) : SV_Target
            {
                float3 col = SAMPLE_TEXTURE2D(_DTex,sampler_DTex,i.uv);
                return float4(col*0.2,0.8);
            }
            ENDHLSL
        }

        /*
        Pass
        {
            Name "NormalExtend"
            Cull Front
            Tags { "LightMode"="SRPDefaultUnlit" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"       
            
            TEXTURE2D(_DTex);SAMPLER(sampler_DTex);
            
            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal : NORMAL;
                //float4 tangent : TANGENT;
            };
            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            v2f vert (appdata v)
            {
                v2f o;
                o.uv = v.uv;
                o.vertex = TransformObjectToHClip(v.vertex+v.normal*0.000006);
                return o;
            }
            float4 frag (v2f i) : SV_Target
            {
                float3 col = SAMPLE_TEXTURE2D(_DTex,sampler_DTex,i.uv);
                return float4(pow(col,4.0),1);
            }
            ENDHLSL
        }
        */
        // 主Pass
        Pass
        {
            Tags { 
                "LightMode" = "UniversalForward"  // 关键：正确的光照模式
            }

            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite On
            Cull Back
            
            Stencil
            {
                Ref 1
                Comp NotEqual
                Pass Keep
            }
            

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            
            #include "Assets/ZMD/Shader/Flow_Drop_Func_Library.hlsl"
            //#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Packing.hlsl"
            //#include "Assets/ZMD/Shader/PBR_BRDF_Library.hlsl"
            //#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            TEXTURE2D(_DTex);SAMPLER(sampler_DTex);
            TEXTURE2D(_NTex);SAMPLER(sampler_NTex);
            TEXTURE2D(_RPTex);SAMPLER(sampler_RPTex);
            TEXTURE2D(_AOTex);SAMPLER(sampler_AOTex);
            float3 _AdjustCol;
            
            TEXTURE2D(_MatCapTex);SAMPLER(sampler_MatCapTex);
            float _UseDrop;
            float _UseShadow;

            // 自定义阴影贴图
            float4x4 _POSvpM;
            TEXTURE2D(_POSpcf);
            SAMPLER(sampler_POSpcf);
            TEXTURE2D(_CSShadow);SAMPLER(sampler_CSShadow);
            //SAMPLER(sampler_POSMap_LinearClamp); 

            // 场景深度图
            TEXTURE2D(_CameraDepthTexture);SAMPLER(sampler_CameraDepthTexture); 

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
                float4 vertex : SV_POSITION;
                float3 posWS : TEXCOORD1;
                float3 norWS : TEXCOORD3;
                float4 screenPos :TEXCOORD4;
                float4 tanWS : TEXCOORD5;
            };
            // 用于解码终末地的法线贴图，他们把三个分量的法线贴图压缩到了两个分量
            float3 decodeNormal(float2 Nxy,float NStrength)
            {
                float2 nNxy = Nxy*2.0 - 1.0;
                float z = sqrt(1.0 - saturate(dot(nNxy,nNxy))); // 勾股定理
                z = max(0.0,z)*0.5 + 0.5;
                z *= NStrength;
                return normalize(float3(Nxy,z));
            }

            v2f vert (appdata v)
            {
                v2f o;
                o.uv = v.uv;
                o.vertex = TransformObjectToHClip(v.vertex);
                //o.vertex.z = 1.0 - o.vertex.z;
                o.posWS = TransformObjectToWorld(v.vertex);
                //o.norWS = TransformObjectToWorldDir(v.Nor).xyz;
                o.screenPos = ComputeScreenPos(o.vertex);

                VertexNormalInputs normalInput = GetVertexNormalInputs(v.normal, v.tangent);
                real sign = v.tangent.w * GetOddNegativeScale();
                
                o.norWS = normalInput.normalWS;
                //o.tanWS = normalInput.tangentWS;
                o.tanWS = real4(normalInput.tangentWS,sign);

                return o;
            }

            float4 frag (v2f i) : SV_Target
            {
                
                // ======================= 细节法线 N ===================================
                float4 NTex = SAMPLE_TEXTURE2D(_NTex,sampler_NTex,i.uv);
                float3 nt = float3(NTex.xy*2.0 - 1.0,0.0);
                nt.z = 0.7*sqrt(1.0 - dot(nt.xy,nt.xy));
                // 构建TBN矩阵
                float3 bitWS = i.tanWS.w * cross(i.norWS.xyz,i.tanWS.xyz);
                float3x3 TBN = float3x3(i.tanWS.xyz,bitWS,i.norWS);
                // 构建TBN矩阵的转置矩阵
                float3x3 TBN_t = transpose(TBN);
                // 将法线转换到世界空间
                float3 ntWS = normalize( mul(nt,TBN) );

                // ======================== 整体的法线 HN ========================
                float3 phNt = float3(NTex.zw*2.0 - 1.0,0.0);
                phNt.z = 0.7*sqrt(1.0 - dot(phNt.xy,phNt.xy));
                float3 phNtWS = normalize( mul(phNt,TBN) );
                phNtWS = normalize(phNtWS-float3(0,0.5,0));
                

                //// ================== 采样自定义高精度阴影Pass ================================================
                float2 screenUV = i.screenPos.xy / i.screenPos.w;
                float depth = LinearEyeDepth(i.vertex.z,_ZBufferParams);

                // ==================== 阴影 =======================================
                float shadow =  SAMPLE_TEXTURE2D(_CSShadow, sampler_CSShadow, screenUV).r;
                shadow = lerp(1.0,shadow,_UseShadow);
                // ============================ 表面贴图 =================================
                float4 DTex = SAMPLE_TEXTURE2D(_DTex,sampler_DTex,i.uv);
                float4 albedo = DTex;
                // _P 的x是头发部分的区分，
                // y是用于高光的相乘，相当于噪波
                // z是头发的AO
                // a是用于限制头发高光不在一些缝隙里显示的
                float4 _P = SAMPLE_TEXTURE2D(_AOTex,sampler_AOTex,i.uv);

                // ========================= 调整Albedo纯度 ======================
                float gray1 = dot(albedo,float3(0.299,0.587,0.114));
                //albedo.xyz = lerp(float3(gray1,gray1,gray1),albedo.xyz,1.3);
                albedo.xyz = saturate(albedo);
                
                // ====================== 灯光相关参数 ======================================
                Light ld = GetMainLight();
                float3 lightDir = normalize(ld.direction); // 主光源方向（世界空间，ForwardBase通道）
                float3 lightColor = ld.color;

                // 获取视线方向
                float3 viewDirWS = GetWorldSpaceNormalizeViewDir(i.posWS);
                float3 H = normalize(viewDirWS + lightDir);


                // =================== 基础lambert + shadow =====================
                float lambert = saturate(dot(phNtWS,lightDir));// 整体法线的
                float lambert2 = saturate(dot(ntWS,lightDir));// 细节法向的
                //lambert2 = pow(lambert2,2.0);
                float invisible = lambert*shadow;

                // =================== 采样Ramp ===================================
                float2 rampUV = float2(shadow*lambert2*0.5+0.5,0.5);
                rampUV = clamp(rampUV,0.01,0.99);
                float4 ramp = SAMPLE_TEXTURE2D(_RPTex,sampler_RPTex,rampUV);

                // =================== AO ==========================================
                float3 directionOcculusion = float3(0.081,0.011,0.019);
                //directionOcculusion = pow(directionOcculusion,1.0/2.2);
                float3 ao = _P.z;  
                //ao = pow(ao,1.0/2.2);
                ao = lerp(directionOcculusion,float3(1,1,1),ao);

                // =================== 环境光 ====================================
                float3 am = (1.0/PI) * albedo.xyz * ramp.xyz * lightColor * ao;
                am = pow(am,1.2);

                // ================== 间接光 =====================================
                float3 UnityAmbient = SampleSH(phNtWS) * albedo * ao;
                float ambientStren = dot(UnityAmbient,float3(0.299,0.587,0.114));
                ambientStren = lerp(ambientStren,1.0,0.1);
                float3 huanjing = 1.0*ambientStren * albedo * lightColor ; 

                // =================== 反射项 =====================================
                float3 specCol = float3(3.0,2.701,2.246);
                //float lambert2 = saturate(dot(phNtWS,lightDir));
                float3 specular = pow(max(0.0,dot(phNtWS,H )),7.0)*lightColor;
                float3 spe = 0.1*specular*invisible*specCol*_AdjustCol*ao;

                // =================== 新天使环高光 ===============================
                float3 ori = mul(unity_ObjectToWorld,float4(0,0,0,1)).xyz; // 物体原点
                float3 relativeHeight = float3(-0.02,1.6,0); // 头发相对原点的高度
                float3 hairPosWS = ori + relativeHeight; // 这个建议后期直接传入
                float3 radialN = normalize(i.posWS - hairPosWS); //径向法向
                radialN = normalize(lerp(radialN,ntWS,0.1)); // 混合径向法线与原法线
                float3 radialT = cross(float3(0,1,0),radialN); // 径向切向
                float3 radialB = cross(radialT,radialN); // 径向B
                // 根据头发的部分混合数据
                float hairSep = _P.x; // 分割上半部分头发与下半部分
                radialB = lerp(radialB,bitWS,hairSep);
                // 主高光
                float kHeight = 0.2; // 控制高光位置
                float3 kRD = lerp(normalize(viewDirWS+float3(0,kHeight,0)),viewDirWS,hairSep);
                // 下高光
                float kHeight2 = 0.16; // 控制高光位置
                float3 kRD2 = lerp(normalize(viewDirWS+float3(0,kHeight2,0)),viewDirWS,hairSep);
                // 上高光
                float kHeight3 = 0.24; // 控制高光位置
                float3 kRD3 = lerp(normalize(viewDirWS+float3(0,kHeight3,0)),viewDirWS,hairSep);
                
                // 菲涅尼，dot(HN,V)
                float hFre = saturate(pow(dot(phNtWS,viewDirWS),10.0))*0.6;
                //hFre = smoothstep(0.0,1.0,hFre);
                float kkk = float3(1,1,1)*smoothstep(0.03,0.0,abs(dot(kRD,radialB)))*_P.y*_P.a*hFre;
                float3 kkk2 = float3(1.0,0.5,1.0)*smoothstep(0.04,0.0,abs(dot(kRD2,radialB)))*_P.y*_P.a*hFre*0.3;
                float3 kkk3 = float3(1.0,1.0,0.5)*smoothstep(0.04,0.0,abs(dot(kRD3,radialB)))*_P.y*_P.a*hFre*0.3;
                float3 kk = kkk+kkk2+kkk3;
                kk *= lambert*shadow;

                // =========================== 计算菲尼尔项 ========================
                float3 headCenter = float3(0,180,0);
                float sampleFresnel = saturate(dot(viewDirWS,phNtWS));
                //sampleFresnel = saturate(dot(viewDirWS,ntWS));
                //float 
                float3 fIn = float3(2.0,1.242,1.519);float3 fOut = float3(1.0,0.615,0.89);
                //fIn = float3(1,1,1);fOut = float3(1,1,1);
                //float3 fIn = 0.1*float3(1,1,1);float3 fOut = 0.0*float3(1,1,1);
                float3 fresnel = lerp(fOut,fIn,sampleFresnel);//*ramp.a;

                // ========================= 阴影加深 ===============================
                float an = lerp(ramp.a,1.0,0.7);

                // rim 边缘光
                float rim = smoothstep(0.1,0.0,sampleFresnel)*shadow;
                rim = 0.0;


                //===================== 合成颜色 ==================================
                float3 finalCol = saturate( (am+spe+kk+huanjing)*an*fresnel);

                // =============== 调整饱和度 ==================================
                //finalCol = pow(finalCol,1.0/2.2);
                float gray2 = dot(finalCol,float3(0.299,0.587,0.114));
                //finalCol = lerp(float3(gray2,gray2,gray2),finalCol,1.0);
                //finalCol = lerp(float3(gray2,gray2,gray2),finalCol,1.0 + 0.25*(1.0 - ramp.a*shadow));
                // ================== 暗部更暗 ==================================
                float darkFactor = lerp(0.8,1.0,invisible*ao);
                //darkFactor = 1.0;




                float screenDep = SAMPLE_TEXTURE2D(_CameraDepthTexture,sampler_CameraDepthTexture,screenUV).r;
                float LinD = Linear01Depth(screenDep,_ZBufferParams);



                // ======================== 流水 ==============================
                float T = _Time.y;
                float t = T*0.2;

                float3 relativeP = i.posWS - TransformObjectToWorld(float4(0,0,0,1)).xyz;
                // 柱面法线映射
                float3 cylinderNor = normalize(float3(relativeP.x,0,relativeP.z));
                float3 flatXZNor = normalize(float3(i.norWS.x,0.0,i.norWS.z));
                // 这个系数表示法线与柱面法线的贴合度，贴合度越高，表示该点越好使用角度映射
                // 这个系数用于规定动态雨滴出现的范围，因为这个范围外，动态雨滴会变得畸形
                float yingshe = abs(dot(cylinderNor,flatXZNor));
                // 计算X和Z轴的映射权重
                float mapZ = abs(dot(flatXZNor,float3(0,0,1)));
                // 柱面映射权重
                float angleU = atan2(relativeP.x,relativeP.z) / 3.14159 * 0.5 + 0.5;

                // 流动的水滴UV计算
                float2 dropUV = float2(angleU , i.posWS.y*0.6)*6.0;
                // 静态的水滴UV计算
                float2 staticDropUV = i.posWS.xz * 2.0;
                // 以下为计算水滴遮罩与扰动法线
                float upMask = step(0.0,i.norWS.y); // 只在上半部分出现水滴
                float dyMask = pow(yingshe,6.0); // 动态水滴区域出现的范围
                //dyMask *= upMask;

                float2 cc = ActorDrops(dropUV / 1.5 , staticDropUV , t, 1.0, 0.5, 0.5,upMask,dyMask);
                // 通过微小偏移，计算法向
                float2 e = float2(0.0001,0.0);
                float2 ccx = ActorDrops(dropUV / 1.5 + e.xy , staticDropUV + e.xy , t, 1.0, 0.5, 0.5,upMask,dyMask);
                float2 ccy = ActorDrops(dropUV / 1.5 + e.yx , staticDropUV + e.yx , t, 1.0, 0.5, 0.5,upMask,dyMask);
                // 插值计算法向
                float2 ccn = 8.0* float2(max(cc.x,0.25*cc.y) - max(ccx.x,0.25*ccx.y),max(cc.x,0.25*cc.y) - max(ccy.x,0.25*ccy.y) );
                float3 ccn_WS = normalize( mul( TBN_t, float3(ccn.x,ccn.y,1.0) ) );

                float dropFresnel = pow(saturate(dot(viewDirWS,ccn_WS)),10.0);
                // 采样水滴MatCap
                float3 dropMatCap = SAMPLE_TEXTURE2D(_MatCapTex,sampler_MatCapTex,ccn_WS.xy * 0.5 + 0.5).xyz;
                float3 dropMC = lerp(0.0,dropMatCap,step(0.03,cc.x+cc.y));
                dropMC *= smoothstep(0.1,0.0,dropFresnel)*step(0.03,cc.x+cc.y);
                //float3 dropWS = i.posWS + upMask * ntWS * max(c.x* 0.01 , c.y * 0.002);
                //float3 dropN = normalize(cross(ddy(dropWS),ddx(dropWS)));

                float3 ntWS_Drop = normalize( lerp(ntWS,ccn_WS,step(0.01,cc.x + cc.y)));

                float3 dropHighlight1 = 0.2*lightColor*pow(saturate(dot(lightDir,ntWS_Drop)),50.0);
                // 水的高光，根据水的法向与物体表面切向计算
                float3 dropHighlight = lightColor * pow(saturate(dot(i.tanWS,ccn_WS)),10.0);
                dropHighlight *= step(0.03,cc.x + cc.y) * saturate(dot(lightDir,ccn_WS));
                dropHighlight += dropHighlight1;
                // 水的暗部
                float3 dropAB =  pow(saturate(1.0-dot(bitWS,ccn_WS)),0.5);

                
                float3 finalDrop = (dropHighlight+dropMC)*step(0.01,cc.x + cc.y);
                float albedoDrop = lerp(1.0,0.9,step(0.03,cc.x + cc.y));


                // Unity基础环境光
                float3 ambient = SampleSH(ntWS_Drop) * albedo * ao;

                //return float4(ntWS*float3(1,1,1),1.0);
                return float4(((finalCol + 0.3*ambient)*darkFactor*dropAB + finalDrop)*float3(1,1,1),1.0);

            }
            ENDHLSL
        }
    }
}
