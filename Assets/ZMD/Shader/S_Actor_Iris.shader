Shader "Unlit/S_Actor_Iris"
{
    Properties
    {
        _DTex ("颜色贴图", 2D) = "white" {}
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

            float2 GetParallaxUV(float3 viewDirTS, float2 uv, float depthValue, float parallaxScale)
            {
                const int numSamples = 10;
                float layerHeight = 1.0 / numSamples;
                float2 deltaUV = parallaxScale * viewDirTS.xy / viewDirTS.z / numSamples;

                float currentLayerHeight = 0.0;
                float2 currentUV = uv;
                float currentDepth = 1.0 - depthValue;

                for (int i = 0; i < numSamples; ++i) 
                {
                    if (currentLayerHeight >= currentDepth) 
                        break;

                    currentUV -= deltaUV;
                    currentLayerHeight += layerHeight;
                }

                return currentUV;
            }


            v2f vert (appdata v)
            {
                v2f o;
                o.uv = v.uv;
                // 添加眼部透过头发
                // 获取视线方向
                //v.vertex.xyz += v.normal * 0.0001;
                o.vertex = TransformObjectToHClip(v.vertex);
                //o.vertex.z += 0.008;
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
                // 构建TBN矩阵
                float3 bitWS = i.tanWS.w * cross(i.norWS.xyz,i.tanWS.xyz);
                float3x3 TBN = float3x3(i.tanWS.xyz,bitWS,i.norWS);
                // 构建TBN矩阵的转置矩阵
                float3x3 TBN_t = transpose(TBN);

                // ======================== 准备视差映射数据 ===========================
                // 获取视线方向
                float3 viewDirWS = GetWorldSpaceNormalizeViewDir(i.posWS);
                float3 viewDirTS = mul(TBN,viewDirWS); // 切线空间视线向量
                float heigh = 1.0-pow(length(i.uv - 0.5),2.0)*4.5;
                heigh = saturate(heigh);
                float2 parallaxUV = GetParallaxUV(viewDirTS,i.uv,-heigh,0.08);

                //// ================== 采样自定义高精度阴影Pass ================================================
                float2 screenUV = i.screenPos.xy / i.screenPos.w;
                float depth = LinearEyeDepth(i.vertex.z,_ZBufferParams);



                // ============================ 表面贴图 =================================
                float4 DTex = SAMPLE_TEXTURE2D(_DTex,sampler_DTex,parallaxUV);
                float3 albedo = DTex.xyz;


                // ====================== PBR BRDF ======================================
                Light ld = GetMainLight();
                float3 lightDir = normalize(ld.direction); // 主光源方向（世界空间，ForwardBase通道）
                float3 lightColor = ld.color;




                //return float4(brdfResult.radiance.x*shadow*float3(1,1,1),1.0);
                //return float4(heigh*float3(1,1,1),1.0);
                return float4((albedo*lightColor)*float3(1,1,1),1.0);
            }
            ENDHLSL
        }
    }
}
