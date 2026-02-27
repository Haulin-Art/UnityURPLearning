Shader "Unlit/PlaneFog"
{
    Properties
    {
        _Density ("密度纹理", 2D) = "white" {}
        _Normal ("法向纹理",2D) = "blue" {}
        _Flowmap ("流动贴图",2D) = "black" {}
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" 
               "Queue"="Transparent"
               "IgnoreProjector"="True"
             }
        LOD 100

        Pass
        {
            Blend SrcAlpha OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_Density);SAMPLER(sampler_Density);
            TEXTURE2D(_Normal);SAMPLER(sampler_Normal);
            TEXTURE2D(_Flowmap);SAMPLER(sampler_Flowmap);

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float4 normal : NORMAL;
                float4 tangent : TANGENT;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                float3 normal : TEXCOORD1;
                float4 tangent : TEXCOORD2;
                float3 posWS : TEXCOORD3;
            };

            // 自定义函数区
            // 解码RGB法线贴图，映射到-1~1
            float3 DecodeNormalRGB(float4 packedNormal)
            {
                #ifdef UNITY_NO_DXT5nm
                    // 如果纹理是RGB格式，直接映射
                    float3 normal = packedNormal.rgb * 2.0 - 1.0;
                #else
                    // 如果是DXT5nm格式，使用UnpackNormal
                    // UnpackNormal是专门为Unity的DXT5nm压缩格式设计的，只有RG通道的推荐使用
                    float3 normal = UnpackNormal(packedNormal);
                #endif
                return normalize(normal);
            }
            // 自定义函数区结束

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = TransformObjectToHClip(v.vertex);
                o.uv = v.uv;

                // 这是什么操作
                // 函数将模型空间的法线和切线转换为世界空间
                VertexNormalInputs normalInput = GetVertexNormalInputs(v.normal, v.tangent);
                // 用于处理镜像变换时的副切线方向问题
                real sign = v.tangent.w * GetOddNegativeScale();
                o.normal = normalInput.normalWS;
                // 存储的世界空间法线和切线（带符号）用于在片元着色器中构建TBN矩阵
                o.tangent = real4(normalInput.tangentWS,sign);

                o.posWS = TransformObjectToWorld(v.vertex).xyz;

                return o;
            }

            float4 frag (v2f i) : SV_Target
            {
                float3 norTS = DecodeNormalRGB(SAMPLE_TEXTURE2D(_Normal,sampler_Normal,i.uv));

                float3x3 TBN = float3x3(i.tangent.xyz,i.tangent.w*cross(i.normal.xyz,i.tangent.xyz),i.normal.xyz);
                float3 norWS = normalize(mul(norTS,TBN));
                norWS = float3(norWS.x,-norWS.y,norWS.z);
                
                float trans = SAMPLE_TEXTURE2D(_Density,sampler_Density,i.uv).x;
                //float dis = length(float3(i.posWS-_CameraWorldPos.xyz));
                //float disFade = smoothstep(5.0,20.0,dis);
                //trans *= disFade;


                Light ld = GetMainLight();
                float3 lightDir = normalize(ld.direction); // 主光源方向（世界空间，ForwardBase通道）
                float3 lightColor = ld.color;
                float diff = max(0,dot(lightDir,norWS));

                //return float4(norWS,1.0);
                return float4(diff*float3(1,1,1),trans);
            }
            ENDHLSL
        }
    }
}
