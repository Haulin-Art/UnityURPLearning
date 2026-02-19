Shader "Unlit/S_Actor_Cloth"
{
    Properties
    {
        _DTex ("颜色贴图", 2D) = "white" {}
        _NTex ("法线贴图", 2D) = "blue" {}
        _ETex ("自发光图", 2D) = "black" {}
        _MTex ("另一种自发光", 2D) = "black" {}
        _MColor ("自发光颜色",Color) = (1,1,1,1)
        _RPTex ("Ramp图", 2D) = "white" {}
        _FresIn ("菲尼尔内侧颜色",Color) = (1,1,1,1)
        _FresOut ("菲尼尔外侧颜色",Color) = (0,0,0,0)
        _RoughnessScale ("粗糙度控制",Vector) = (1.0,0.1,0.0,0.0)
        _AOScale ("AO控制",Vector) = (0.0,1.0,0.0,0.0)
        _RMAOTex ("粗糙度金属度AO贴图", 2D) = "write" {}
        _UseWhite ("是否将白的地方更提白",Float) = 1.0
        _MatCapTex ("MatCap贴图", 2D) = "black" {}
    }
    SubShader
    {
        Tags { "RenderType"="Opaque"}
        LOD 100

        Pass
        {   
            Cull Off
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            //#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Packing.hlsl"
            #include "Assets/ZMD/Shader/PBR_BRDF_Library.hlsl"
            #include "Assets/ZMD/Shader/Flow_Drop_Func_Library.hlsl"

            TEXTURE2D(_DTex);SAMPLER(sampler_DTex);
            TEXTURE2D(_NTex);SAMPLER(sampler_NTex);
            TEXTURE2D(_ETex);SAMPLER(sampler_ETex);
            TEXTURE2D(_MTex);SAMPLER(sampler_MTex);
            TEXTURE2D(_RPTex);SAMPLER(sampler_RPTex);
            float3 _MColor;
            float2 _RoughnessScale;
            float2 _AOScale;
            TEXTURE2D(_RMAOTex);SAMPLER(sampler_RMAOTex);

            TEXTURE2D(_MatCapTex);SAMPLER(sampler_MatCapTex);

            TEXTURE2D(_CSShadow);SAMPLER(sampler_CSShadow);
            float4x4 _POSvpM;
            TEXTURE2D(_POSpcf);
            SAMPLER(sampler_POSpcf);

            TEXTURE2D(_CameraDepthTexture);SAMPLER(sampler_CameraDepthTexture); 

            float3 _FresIn;
            float3 _FresOut;

            float _UseWhite;
            //SAMPLER(sampler_POSMap_LinearClamp); 

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float2 uv1 : TEXCOORD1;
                float3 normal : NORMAL;
                float4 tangent : TANGENT;
            };
            struct v2f
            {
                float2 uv : TEXCOORD0;
                float2 uv1 : TEXCOORD1;
                float4 vertex : SV_POSITION;
                float3 posWS : TEXCOORD2;
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
                return normalize(float3(Nxy,z));
            }


            v2f vert (appdata v)
            {
                v2f o;
                o.uv = v.uv;
                o.uv1 = v.uv1;
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


                // 二次元角色透视矫正
                // 摄像机朝前向量
                float3 orthoViewDir = mul(UNITY_MATRIX_I_V,float4(0,0,1,0.0)).xyz;
                float3 otv = normalize(float3(orthoViewDir.x,-orthoViewDir.y,orthoViewDir.z));

                float3 objectCenter = mul(unity_ObjectToWorld, float4(0,0,0,1)).xyz;
                float3 targetPos = float3(objectCenter.x, o.posWS.y, objectCenter.z);
                float3 tpVS = mul(UNITY_MATRIX_V,float4(targetPos,1.0)).xyz;
                float3 obVS = mul(UNITY_MATRIX_V,float4(o.posWS,1.0)).xyz;
                float value = -tpVS.z + obVS.z;

                float3 correct =0.004*value*otv;

                //o.vertex = TransformObjectToHClip(v.vertex - correct);

                return o;
            }

            float4 frag (v2f i) : SV_Target
            {
                
                // ======================= 采样法线 ===================================
                float3 NTex = SAMPLE_TEXTURE2D(_NTex,sampler_NTex,i.uv).xyz;
                float3 nt = UnpackNormal(SAMPLE_TEXTURE2D(_NTex,sampler_NTex,i.uv));
                nt.z = 0.6*sqrt(1.0-saturate(dot(nt.xy,nt.xy)));
                nt = normalize(nt);
                // 构建TBN矩阵
                float3 bitWS = i.tanWS.w * cross(i.norWS.xyz,i.tanWS.xyz);
                float3x3 TBN = float3x3(i.tanWS.xyz,bitWS,i.norWS);
                // 构建TBN矩阵的转置矩阵
                float3x3 TBN_t = transpose(TBN);
                // 将法线转换到世界空间
                float3 ntWS = normalize( mul(nt,TBN) );

                //// ================== 采样阴影 ===============================================
                float2 screenUV = i.screenPos.xy / i.screenPos.w;
                float shadow =  SAMPLE_TEXTURE2D(_CSShadow, sampler_CSShadow, screenUV).r;

                // ============================ 表面贴图 =================================
                float4 DTex = SAMPLE_TEXTURE2D(_DTex,sampler_DTex,i.uv);
                float3 albedo = DTex.xyz;
                float4 rmao = SAMPLE_TEXTURE2D(_RMAOTex,sampler_RMAOTex,i.uv);
                float metallic = rmao.x;
                float roughness = rmao.a;
                float ao =rmao.z;
                float3 emission = SAMPLE_TEXTURE2D(_ETex,sampler_ETex,i.uv).xyz;
                float otherEmis = SAMPLE_TEXTURE2D(_MTex,sampler_MTex,i.uv1).x;

                // ====================== PBR 数据 ======================================
                Light ld = GetMainLight();
                float3 lightDir = normalize(ld.direction); // 主光源方向（世界空间，ForwardBase通道）
                float3 lightColor = ld.color;
                // 获取视线方向
                float3 viewDirWS = GetWorldSpaceNormalizeViewDir(i.posWS);

                float lambert = dot(lightDir,ntWS);


                // =================== 采样Ramp ================================
                // 这里为了获得暗部的细节，lambert是没钳制的，线混合Lambert与阴影
                float invisible = shadow*saturate(lambert);//*0.5 + 0.5;
                //float invisible1 = lerp(invisible,1.0,0.3334);
                //invisible = pow(invisible,1.0/2.2);
                // 貌似是为了规避模型接缝，这里得用两次转换
                float2 rampUV = float2(invisible,0.5);
                //rampUV = clamp(rampUV,0.01,0.99);
                float4 ramp = SAMPLE_TEXTURE2D(_RPTex,sampler_RPTex,rampUV);



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
                //float ccgg = ActorDrops(dropUV / 1.5 , staticDropUV , t, 0.15, 0.2, 0.2,upMask,dyMask).x;
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

                // 水的高光，根据水的法向与物体表面切向计算
                float3 dropHighlight = lightColor * pow(saturate(dot(i.tanWS,ccn_WS)),5.0);
                dropHighlight *= step(0.03,cc.x + cc.y) * saturate(dot(lightDir,ccn_WS));
                // 水的暗部
                float3 dropAB =  pow(saturate(1.0-dot(bitWS,ccn_WS)),0.5);

                // 菲尼尔
                float sampleFresnel = pow(saturate(dot(viewDirWS,ntWS_Drop)),1.5);
                //float3 fIn = float3(1.544,1.544,1.544);float3 fOut = float3(0.6,0.5,0.4);
                float3 fresnel = lerp(_FresOut,_FresIn,sampleFresnel);
                // rim 边缘光
                float rim = smoothstep(0.15,0.0,saturate(dot(viewDirWS,ntWS)))*shadow;
                //rim *= 0.0;


                // ================== PBR BRDF 数据 ===============================
                PBR_BRDF_Data data;
                // 也不知道为什么，贴图白的部分好像跟他们的效果对不上，再加上两个灰度大于0.2的部分，这样才比较接近
                float albedoWhite =  lightColor/2.0*_UseWhite * step(0.2, dot(albedo,float3(0.299,0.587,0.114)));
                float3 albedo2 = albedo + albedo*albedoWhite*lightColor;
                data.albedo = albedo2 * lerp(1.0,0.7,step(0.03,cc.x + cc.y)) * dropAB;
                data.normal = ntWS_Drop;
                data.viewDir = viewDirWS;
                data.lightDir = lightDir;
                data.irradiance = lightColor;
                data.roughness =lerp( roughness * _RoughnessScale.x + _RoughnessScale.y,0.0,cc.x+cc.y);
                data.metallic = metallic;
                data.F0 = 0.0;
                data.occlusion = ao;
                data.worldPos = i.posWS;
                PBR_BRDF_Result pbr = BRDF_CookTorrance(data,true,false);

                // ====================== 衣服白色区域增加fresnel 效果
                float3 fres = fresnel * albedoWhite;

                // 最终数据
                float3 diff = 1.0 * ramp.xyz * pbr.diffuse * shadow * fres; // 直接光漫反射
                float3 spec = pbr.specular * shadow; // 直接光镜面反射
                float3 ambi = albedo * ao * lightColor * 0.15 ; // 环境光
                float3 emis = emission * 1.0 ; // 第一种自发光
                float3 oems =  otherEmis * _MColor * 10.0 ; // 第二种自发光，使用一个灰度遮罩控制的自发光


                // Unity基础环境光
                float3 ambient = SampleSH(ntWS_Drop) * albedo * ao;
                //float3 reflectDir = reflect(-viewDirWS,ntWS_Drop);
                //float3 matcap = SAMPLE_TEXTURE2D(_MatCapTex,sampler_MatCapTex,reflectDir.xy * 0.5 + 0.5).xyz;
                
                float modelDepth = LinearEyeDepth(i.vertex.z,_ZBufferParams);
                float sdep = SAMPLE_TEXTURE2D(_CameraDepthTexture,sampler_CameraDepthTexture,screenUV  + float2(0.0015/(modelDepth+0.00001),0.0)).r;
                float linearDepth = LinearEyeDepth(sdep,_ZBufferParams);
                float rimm = step(0.2,(linearDepth - modelDepth)/2.0);

                // dropHighlight
                //return float4(ccgg*float3(1,1,1),1.0);     
                return float4( diff+ spec+ + ambi + ambient*0.4 + emis + oems + rimm*0.0 + dropMC + dropHighlight ,1.0 );       
                return float4( diff + spec + ambi + emis + oems + dropMC ,1.0 );
                return float4(ramp*pbr.diffuse*shadow + pbr.specular + albedo*ao*lightColor*0.1  + emission*2.0 + otherEmis*_MColor*20.0 ,1.0);
                return float4((pbr.radiance*2.0 + albedo*lightColor*0.05 + emission*2.0 + otherEmis*_MColor*20.0 )*float3(1,1,1),1);
            }
            ENDHLSL
        }
    }
}