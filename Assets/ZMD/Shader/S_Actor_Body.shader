Shader "Unlit/S_Actor_Body"
{
    Properties
    {
        _DTex ("颜色贴图", 2D) = "white" {}
        _NTex ("法线贴图", 2D) = "blue" {}
        _IsSkin ("是皮肤",Float ) = 0.0
        _UseRP ("使用Ramp",Float ) = 0.0
        _RPTex ("Ramp图", 2D) = "white" {}
        _FresIn ("菲尼尔内侧颜色",Color) = (1,1,1,1)
        _FresOut ("菲尼尔外侧颜色",Color) = (1,1,1,1)
        _RoughnessScale ("粗糙度控制",Vector) = (1.0,0.1,0.0,0.0)
        _AOScale ("AO控制",Vector) = (0.0,1.0,0.0,0.0)
        _RMAOTex ("粗糙度金属度AO贴图", 2D) = "write" {}
        _MatCapTex ("MatCap贴图", 2D) = "black" {}
        _UseDrop ("使用流水", Float) = 1.0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque"}
        LOD 100

        Pass
        {   
            Tags {"LightMode" = "UniversalForward"}
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
            float _IsSkin;
            float _UseRP;
            TEXTURE2D(_RPTex);SAMPLER(sampler_RPTex);
            float2 _RoughnessScale;
            float2 _AOScale;
            TEXTURE2D(_RMAOTex);SAMPLER(sampler_RMAOTex);
            TEXTURE2D(_MatCapTex);SAMPLER(sampler_MatCapTex);
            float _UseDrop;

            TEXTURE2D(_CSShadow);SAMPLER(sampler_CSShadow);
            float4x4 _POSvpM;
            TEXTURE2D(_POSpcf);
            SAMPLER(sampler_POSpcf);

            float3 _FresIn;
            float3 _FresOut;
            //SAMPLER(sampler_POSMap_LinearClamp); 

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal : NORMAL;
                float4 tangent : TANGENT;
                float3 vertexCol : COLOR0;
            };
            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                float3 posWS : TEXCOORD1;
                float3 norWS : TEXCOORD3;
                float4 screenPos :TEXCOORD4;
                float4 tanWS : TEXCOORD5;

                float3 norTS : TEXCOORD7;
                float3 vertexCol : TEXCOORD6;
            };
            // 用于解码终末地的法线贴图，他们把三个分量的法线贴图压缩到了两个分量
            float3 decodeNormal(float2 Nxy,float NStrength)
            {
                float2 nNxy = Nxy*2.0 - 1.0;
                //nNxy = Nxy.xy;
                float z = sqrt(1.0 - dot(nNxy,nNxy)); // 勾股定理
                //z = max(0.0,z)*0.5 + 0.5;
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

                o.norTS = v.normal;
                o.vertexCol = v.vertexCol;
                //o.vertexCol = TransformObjectToWorldDir(v.vertexCol*2.0 - 1.0);

                return o;
            }

            float4 frag (v2f i) : SV_Target
            {
                // ======================= 采样法线 ===================================
                float3 NTex = SAMPLE_TEXTURE2D(_NTex,sampler_NTex,i.uv).xyz;
                float3 nt = UnpackNormal(SAMPLE_TEXTURE2D(_NTex,sampler_NTex,i.uv));
                nt.z = 1.0*sqrt(1.0-saturate(dot(nt.xy,nt.xy)));
                nt = normalize(nt);
                // 构建TBN矩阵
                float3 bitWS = i.tanWS.w * cross(i.norWS.xyz,i.tanWS.xyz);
                float3x3 TBN = float3x3(i.tanWS.xyz,bitWS,i.norWS);
                // 将法线转换到世界空间
                // 这里将矩阵放在右侧，相当于矩阵的转置，因为TBN矩阵是正交矩阵，转置等于逆矩阵
                float3 ntWS = normalize( mul(nt ,TBN ));
                //ntWS = i.norWS;

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

                // ====================== PBR 数据 ======================================
                Light ld = GetMainLight();
                float3 lightDir = normalize(ld.direction); // 主光源方向（世界空间，ForwardBase通道）
                float3 lightColor = ld.color;
                // 获取视线方向
                float3 viewDirWS = GetWorldSpaceNormalizeViewDir(i.posWS);
                // Unity基础环境光
                float3 ambient = SampleSH(ntWS) * albedo * ao;
                float lambert = dot(lightDir,ntWS);
                // 菲尼尔
                float sampleFresnel = pow(saturate(dot(viewDirWS,ntWS)),1.0);
                float3 fIn = float3(1.544,1.544,1.544);float3 fOut = float3(0.6,0.5,0.4);
                float3 fresnel = lerp(_FresOut,_FresIn*1.0,sampleFresnel);
                // rim 边缘光
                float rim = smoothstep(0.15,0.0,saturate(dot(viewDirWS,ntWS)))*shadow;
                rim *= 0.0;

                // =================== 采样Ramp ================================
                // 这里为了获得暗部的细节，lambert是没钳制的，线混合Lambert与阴影
                float invisible = min(shadow,saturate(lambert))*0.5 + 0.5;
                float2 rampUV = float2(invisible,0.5);
                //rampUV = clamp(rampUV,0.01,0.99);
                float4 ramp = SAMPLE_TEXTURE2D(_RPTex,sampler_RPTex,rampUV);

                // 直接光漫反射
                float3 indireDiff = 0.5*albedo*ramp.xyz*lightColor/PI;



                // ================== 间接光 =====================================
                //float3 UnityAmbient = SampleSH(ntWS) ;
                //float ambientStren = 0.0*dot(UnityAmbient,float3(0.299,0.587,0.114));
                //ambientStren = lerp(ambientStren,1.0,0.2);
                //float3 huanjing = 1.0 * ambientStren * albedo * lightColor  ; 

                // ================== 阴影修正系数 =================================
                float correctShadow = lerp(albedo*0.5,1.0,min(shadow,saturate(lambert)));

                // ================= 最终着色 ===================================
                float3 finalCol = (indireDiff + albedo*invisible*lightColor)*correctShadow*fresnel + rim;


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
                float2 ccn = 13.0* float2(max(cc.x,0.25*cc.y) - max(ccx.x,0.25*ccx.y),max(cc.x,0.25*cc.y) - max(ccy.x,0.25*ccy.y) );
                float3 ccn_WS = normalize( mul(float3(ccn.x,ccn.y,1.0) ,TBN));

                float dropFresnel = pow(saturate(dot(viewDirWS,ccn_WS)),10.0);
                // 采样水滴MatCap
                float3 dropMatCap = SAMPLE_TEXTURE2D(_MatCapTex,sampler_MatCapTex,ccn_WS.xy * 0.5 + 0.5).xyz;
                float3 dropMC = lerp(0.0,dropMatCap,step(0.03,cc.x+cc.y));
                dropMC *= smoothstep(0.1,0.0,dropFresnel)*step(0.03,cc.x+cc.y);
                //float3 dropWS = i.posWS + upMask * ntWS * max(c.x* 0.01 , c.y * 0.002);
                //float3 dropN = normalize(cross(ddy(dropWS),ddx(dropWS)));

                float3 ntWS_Drop = normalize( lerp(ntWS,ccn_WS,step(0.01,cc.x + cc.y)));

                float3 dropHighlight1 = lightColor*pow(saturate(dot(lightDir,ntWS_Drop)),40.0);
                // 水的高光，根据水的法向与物体表面切向计算
                float3 dropHighlight = lightColor * pow(saturate(dot(i.tanWS,ccn_WS)),5.0);
                dropHighlight *= step(0.03,cc.x + cc.y) * saturate(dot(lightDir,ccn_WS));
                dropHighlight += dropHighlight1*2.0;
                // 水的暗部
                float3 dropAB =  pow(saturate(1.0-dot(bitWS,ccn_WS)),0.5);
                //dropHighlight *= step(0.03,cc.x + cc.y) * saturate(dot(lightDir,ccn_WS));


                float3 finalDrop = lerp(shadow,1.0,0.2)*(dropHighlight+dropMC)*step(0.01,cc.x + cc.y);

                // =================环境色 ===========================
                float3 ambient2 = SampleSH(ntWS_Drop) * albedo * ao;

                //return float4(i.uv.xy,0.0,1.0);
                return float4(((finalCol+ambient2)*dropAB+lerp(0.0,finalDrop,_UseDrop))*float3(1,1,1),1);
            }
            ENDHLSL
        }
    }
}
