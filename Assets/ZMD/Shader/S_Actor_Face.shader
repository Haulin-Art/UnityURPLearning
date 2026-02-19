Shader "Unlit/S_Actor_Face"
{
    Properties
    {
        _DTex ("颜色贴图", 2D) = "white" {}
        _NTex ("法线贴图", 2D) = "blue" {}
        _RPTex ("Ramp图", 2D) = "white" {}
        _SDFTex ("SDF图", 2D) = "white" {}
        _SDFCenter("SDF中心",Float) = 0.0
        _SDFSharp("SDF模糊度",Float) = 0.
        _SDFShadowCol ("SDF阴影颜色",Color) = (1,1,1,1)
        _FaceCM ("面部调整贴图", 2D) = "white" {}

    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100


        // 描边Pass
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
                o.vertex = TransformObjectToHClip(v.vertex+v.normal*0.00001);
                return o;
            }
            float4 frag (v2f i) : SV_Target
            {
                return float4(0,0,0,1);
            }
            ENDHLSL
        }
        */

        Pass
        {
            Tags { "LightMode"="UniversalForward" }

            // 这个蒙版测试用于刘海阴影
            Stencil
            {
                Ref 2
                Comp Always
                Pass Replace
            }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_DTex);SAMPLER(sampler_DTex);
            TEXTURE2D(_NTex);SAMPLER(sampler_NTex);
            TEXTURE2D(_RPTex);SAMPLER(sampler_RPTex);
            TEXTURE2D(_SDFTex);SAMPLER(sampler_SDFTex);
            float _SDFCenter;
            float _SDFSharp;
            float3 _SDFShadowCol;
            TEXTURE2D(_FaceCM);SAMPLER(sampler_FaceCM);


            float4x4 _POSvpM;
            TEXTURE2D(_POSpcf);
            SAMPLER(sampler_POSpcf);
            TEXTURE2D(_CSShadow);SAMPLER(sampler_CSShadow);
            //SAMPLER(sampler_POSMap_LinearClamp); 

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
                
                // ======================= 采样法线 ===================================
                float2 NTex = SAMPLE_TEXTURE2D(_NTex,sampler_NTex,i.uv).xy;
                float3 nt = float3(NTex.xy*2.0 - 1.0,0.0);
                nt.z = sqrt(1.0 - dot(NTex.xy,NTex.xy));
                // 构建TBN矩阵
                float3 bitWS = i.tanWS.w * cross(i.norWS.xyz,i.tanWS.xyz);
                float3x3 TBN = float3x3(i.tanWS.xyz,bitWS,i.norWS);
                // 构建TBN矩阵的转置矩阵
                float3x3 TBN_t = transpose(TBN);
                // 将法线转换到世界空间
                float3 ntWS = normalize( mul(TBN_t,nt) );


                // ==================== 阴影 =======================================
                float2 screenUV = i.screenPos.xy / i.screenPos.w;
                float shadow =  SAMPLE_TEXTURE2D(_CSShadow, sampler_CSShadow, screenUV).r;

                // ============================ 初始化数据 =======================
                Light ld = GetMainLight();
                float3 lightDir = normalize(ld.direction); // 主光源方向（世界空间，ForwardBase通道）
                float3 lightColor = ld.color;
                // 获取视线方向
                float3 viewDirWS = GetWorldSpaceNormalizeViewDir(i.posWS);
                // 添加环境光照(简化版本)
                //float3 ambient = SampleSH(ntWS) * albedo;

                // ============================ 表面贴图 =================================
                float4 DTex = SAMPLE_TEXTURE2D(_DTex,sampler_DTex,i.uv);
                float3 albedo = DTex.xyz;
                float4 SDF = SAMPLE_TEXTURE2D(_SDFTex,sampler_SDFTex,float2(1.0-i.uv.x,i.uv.y));
                float4 faceCorrect = SAMPLE_TEXTURE2D(_FaceCM,sampler_FaceCM,i.uv);

                // ========================= 调整Albedo纯度 ======================
                float gray1 = dot(albedo,float3(0.299,0.587,0.114));
                albedo = lerp(float3(gray1,gray1,gray1),albedo,1.);

                // ============================ SDF ==============================
                float3 actorRight= float3(0,0,-1); // 角色向前向量
                float3 actorForward= float3(1,0,0); // 角色向前向量
                float3 actorUp= float3(0,1,0); // 角色向上向量
                // lightDirProjHeadWS 是投影在xz平面上的灯光向量，并且归一化了
                float3 lightDirProjHeadWS = normalize( lightDir - dot(lightDir,actorUp)*actorUp );
                float sX = dot(lightDirProjHeadWS,actorRight); // 用于判定灯光在左还是在右
                float sZ = dot(lightDirProjHeadWS,-1.0*actorForward);
                // 这里相当于将lightDirProjHeadWS转换到了角色的坐标系当中，之后方便根据轴计算角度
                float angle =  atan2(sX,sZ)/PI ; 
                // 这里是为了映射到正值，但实测光的结果好像反了，所以又加了一层映射
                float AngleThreshold = lerp( 1.0+angle, 1.0-angle , step(0.0,angle)) ;
                float FlipThreshold = sX ;
                // 根据是否翻转确定uv的x是否翻转
                float2 AngleUV =float2( lerp( 1.0 - i.uv.x , i.uv.x , step(0,FlipThreshold)) ,i.uv.y );
                float2 sdfTex = SAMPLE_TEXTURE2D(_SDFTex,sampler_SDFTex,AngleUV).xy;

                float xx = (sdfTex.x + sdfTex.y)/2.0 ; 
                float center = AngleThreshold + _SDFCenter; // 偏移
                float finSDF = xx - center;

                float sdf = smoothstep(0.0,_SDFSharp,finSDF);

                // ======================== 采样RAMP图 ========================
                float xiaeShadow = faceCorrect.y; // 下颚下的阴影
                float2 rampUV = float2(sdf * (1.0-xiaeShadow),0.5);//*lerp(shadow,1.0,0.3)
                rampUV = clamp(rampUV,0.01,0.99);
                float4 ramp = SAMPLE_TEXTURE2D(_RPTex,sampler_RPTex,rampUV);

                // ===================== 环境光项 ================================
                float3 amCol = float3(1.551,1.282,1.271);
                float amFloat = lerp(0.25,0.07,(1.0-ramp.a));
                float3 am = amFloat*amCol*albedo*(lightColor/2.0);
                
                // ======================= 漫反射项 ============================
                float3 diffusion = (1.0/PI) * ramp.xyz * albedo * lightColor;

                // =========================== 计算菲尼尔项 ========================
                float3 headCenter = float3(0,180,0);
                float sampleFresnel = saturate(dot(viewDirWS,normalize(i.vertex.xyz - headCenter)));
                //sampleFresnel = saturate(dot(viewDirWS,ntWS));
                //float 
                //float3 fIn = float3(1.544,1.544,1.544);float3 fOut = float3(0.6,0.5,0.4);
                float3 fIn = 0.1*float3(1,1,1);float3 fOut = 0.0*float3(1,1,1);
                float fresnel = lerp(fOut,fIn,sampleFresnel)*ramp.a * (lightColor/2.0);

                // ================ 阴影调节系数，阴影处变得更暗点 ===============
                float minValue = 0.9;
                float shadowCorrect = (1.0 - minValue)* ramp.a*(1.0-xiaeShadow) + minValue;

                // ====================== 组合数据 =================================
                float3 finalCol = (am + diffusion + fresnel)*shadowCorrect;

                // =============== 调整饱和度 ==================================
                //finalCol = pow(finalCol,1.0/2.2);
                float gray2 = dot(finalCol,float3(0.299,0.587,0.114));
                //finalCol = lerp(float3(gray2,gray2,gray2),finalCol,1.5);
                finalCol = lerp(float3(gray2,gray2,gray2),finalCol,1.0 + 0.5*(1.0 - ramp.a));



                albedo = pow(albedo,1.0);
                //float gray = dot(albedo,float3(0.299,0.587,0.114));
                // 根据贴图增加纯度
                //float3 albedo_plus = lerp(float3(gray,gray,gray),albedo,1.9);

                //return float4(albedo*float3(1,1,1),1.0);
                return float4((finalCol + lerp(_SDFShadowCol*albedo,float3(0,0,0),sdf*(1.0-xiaeShadow)))*float3(1.0,0.95,0.95)*1.5,1.0);
            }
            ENDHLSL
        }
    }
}
