Shader "Unlit/S_Actor_Brow"
{
    Properties
    {
        _DTex ("颜色贴图", 2D) = "white" {}
        _NTex ("法线贴图", 2D) = "blue" {}
        _IsSkin ("是皮肤",Float ) = 0.0
        _UseRP ("使用Ramp",Float ) = 0.0
        _RPTex ("Ramp图", 2D) = "white" {}
        _RoughnessScale ("粗糙度控制",Vector) = (1.0,0.1,0.0,0.0)
        _AOScale ("AO控制",Vector) = (0.0,1.0,0.0,0.0)
        _RMAOTex ("粗糙度金属度AO贴图", 2D) = "write" {}
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100
        Pass
        {
            Stencil
            {
                Ref 1
                Comp Always
                Pass Replace
            }

            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            //#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Packing.hlsl"
            #include "Assets/ZMD/Shader/PBR_BRDF_Library.hlsl"

            TEXTURE2D(_DTex);SAMPLER(sampler_DTex);
            TEXTURE2D(_NTex);SAMPLER(sampler_NTex);
            float _IsSkin;
            float _UseRP;
            TEXTURE2D(_RPTex);SAMPLER(sampler_RPTex);
            float2 _RoughnessScale;
            float2 _AOScale;
            TEXTURE2D(_RMAOTex);SAMPLER(sampler_RMAOTex);

            float4x4 _POSvpM;
            TEXTURE2D(_POSpcf);
            SAMPLER(sampler_POSpcf);
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
                // 添加眼部透过头发
                // 获取视线方向
                //v.vertex.xyz += v.normal * 0.0001;
                o.vertex = TransformObjectToHClip(v.vertex);
                //o.vertex.z += 0.009;
                //o.vertex.z = 1.0 - o.vertex.z;
                o.posWS = TransformObjectToWorld(v.vertex);
                //o.norWS = TransformObjectToWorldDir(v.Nor).xyz;
                o.screenPos = ComputeScreenPos(o.vertex);

                VertexNormalInputs normalInput = GetVertexNormalInputs(v.normal, v.tangent);
                real sign = v.tangent.w * GetOddNegativeScale();
                
                o.norWS = normalInput.normalWS;
                //o.tanWS = normalInput.tangentWS;
                o.tanWS = real4(normalInput.tangentWS,sign);

                // 添加眼部透过头发
                // 获取视线方向


                return o;
            }

            float4 frag (v2f i) : SV_Target
            {
                
                // ======================= 采样法线 ===================================
                float2 NTex = SAMPLE_TEXTURE2D(_NTex,sampler_NTex,i.uv).xy;
                float3 nt = decodeNormal(NTex,1.0);
                nt = pow(nt,1.0/2.2);
                nt = nt*2.0 - 1.0;
                // 构建TBN矩阵
                float3 bitWS = i.tanWS.w * cross(i.norWS.xyz,i.tanWS.xyz);
                float3x3 TBN = float3x3(i.tanWS.xyz,bitWS,i.norWS);
                // 构建TBN矩阵的转置矩阵
                float3x3 TBN_t = transpose(TBN);
                // 将法线转换到世界空间
                float3 ntWS = normalize( mul(TBN_t,nt) );


                //// ================== 采样自定义高精度阴影Pass ================================================
                float2 screenUV = i.screenPos.xy / i.screenPos.w;
                float depth = LinearEyeDepth(i.vertex.z,_ZBufferParams);

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

                // ============================ 表面贴图 =================================
                float4 DTex = SAMPLE_TEXTURE2D(_DTex,sampler_DTex,i.uv);
                float3 albedo = DTex.xyz;
                
                

                float4 rmao = SAMPLE_TEXTURE2D(_RMAOTex,sampler_RMAOTex,i.uv);
                float metallic = rmao.x;
                float roughness = rmao.a;
                float ao =rmao.z;
                //ao = 1.0;

                // ====================== PBR BRDF ======================================
                Light ld = GetMainLight();
                float3 lightDir = normalize(ld.direction); // 主光源方向（世界空间，ForwardBase通道）
                float3 lightColor = ld.color;

                // 获取视线方向
                float3 viewDirWS = GetWorldSpaceNormalizeViewDir(i.posWS);
                // 准备BRDF数据
                PBR_BRDF_Data brdfData;
                brdfData.albedo = float3(1,1,1);
                brdfData.normal = ntWS;
                brdfData.viewDir = viewDirWS;
                brdfData.lightDir = lightDir;
                brdfData.irradiance = lightColor*1.0;
                brdfData.roughness = roughness*_RoughnessScale.x + _RoughnessScale.y;
                brdfData.metallic = metallic;
                brdfData.occlusion = ao*_AOScale.x + _AOScale.y;
                brdfData.F0 = float3(0.0, 0.0, 0.0); // 自动计算
                brdfData.worldPos = i.posWS;
                // 计算BRDF
                PBR_BRDF_Result brdfResult = BRDF_CookTorrance(brdfData, false, false);
                // 添加环境光照(简化版本)
                float3 ambient = SampleSH(ntWS) * albedo * ao;
                // 组合最终颜色
                float3 finalColor = brdfResult.radiance * shadow + ambient*0.0 ;


                float sampleFresnel = pow(saturate(dot(viewDirWS,ntWS)),0.5);
                //float 
                float3 fIn = float3(1.544,1.544,1.544);float3 fOut = float3(0.6,0.5,0.4);
                float fresnel = lerp(fOut,fIn,sampleFresnel);

                float lambert = max(0.0,dot(lightDir,ntWS));
                lambert = saturate(lambert);
                float2 rampUV = float2(lerp(clamp(lambert*shadow,0.01,0.99),1.0,0.5)*lerp(sampleFresnel,1.0,0.5),0.5);
                
                
                if(_IsSkin==0.0)
                {
                    rampUV = float2(lerp(clamp(lambert*shadow,0.01,0.99),1.0,0.0),0.5);
                }
                
                float3 ramp = SAMPLE_TEXTURE2D(_RPTex,sampler_RPTex,rampUV);
                if(_UseRP == 0.0)
                {
                    ramp = 3.0*brdfResult.radiance.x*shadow;
                }




                //return float4(brdfResult.radiance.x*shadow*float3(1,1,1),1.0);
                return float4((albedo)*float3(1,1,1),1.0);
            }
            ENDHLSL
        }
    }
}
