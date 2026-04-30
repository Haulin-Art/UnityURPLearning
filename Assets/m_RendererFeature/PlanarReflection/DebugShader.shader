Shader "m_RendererFeature/PlanarReflection/DebugShader"
{
    Properties
    {
        [Enum(OpaquesReflection,0,FlipYOpaquesReflection,1,Atmosphere,2,Cloud,3,CompositeCloudAndAtmos,4,FinalReflection,5)]
        _DebugView ("显示结果", Float) = 0
        /*
        OpaquesReflection, // 显示不透明物体的反射
        FlipYOpaquesReflection, // 用翻转y轴的uv采样，正确的不透明物体的平面的反射
        Atmosphere, // 大气层
        Cloud, // 上下半球对称云
        CompositeCloudAndAtmos // 大气层与上下半球对称合成
        */
        _EnvPanoramic ("环境反射全景贴图",2D ) = "white" {}
        _PanoramicRotation ("全景贴图旋转角度", Range(0.0, 1.0)) = 0.0
        _PanoramicRotation2 ("全景贴图旋转角度2", Range(0.0, 4.0)) = 0.0
    }



    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
        }

        Pass
        {
            Name "PlanarReflection"
            ZWrite On
            Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float4 screenPos  : TEXCOORD0;
            };
            TEXTURE2D(_EnvPanoramic);SAMPLER(sampler_EnvPanoramic);
            // 来自 Renderer Feature 的体积云渲染的纹理
            TEXTURE2D(_AtmosRFCloudTex);SAMPLER(sampler_AtmosRFCloudTex);

            TEXTURE2D(_PlanarReflectionTexture);SAMPLER(sampler_PlanarReflectionTexture);
            int _DebugView;
            float3 _CameraWorldPos;
            float4x4 _InvViewProj;
            float _PanoramicRotation;float _PanoramicRotation2;

            // ======================== 全景图相关 ========================
            // 绕 Y 轴旋转函数
            float3 RotateAroundY(float3 position, float angle)
            {
                float sinAngle, cosAngle;
                sincos(angle, sinAngle, cosAngle);

                float3 rotatedPos;
                rotatedPos.x = position.x * cosAngle - position.z * sinAngle;
                rotatedPos.z = position.x * sinAngle + position.z * cosAngle;
                rotatedPos.y = position.y;

                return rotatedPos;
            }
            // 全景图UV转换
            float2 DirToPanoramicUV(float3 dir)
            {
                dir = RotateAroundY(dir,6.0*_PanoramicRotation);
                //dir = normalize(dir);
                float phi = atan2(dir.z, dir.x);
                float theta = acos(dir.y);
                
                float rotationRad = _PanoramicRotation * 3.14159265 / 180.0;
                phi += rotationRad;
                
                float2 uv;
                uv.x = phi / (2.0 * 3.14159265) + 0.5;
                uv.y = theta / 3.14159265;
                
                return uv;
            }


            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.screenPos  = ComputeScreenPos(OUT.positionCS);
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                float2 screenUV = IN.screenPos.xy / IN.screenPos.w;



                // 计算rd
                // 1. 把屏幕UV转成裁剪空间坐标（范围：x/y∈[-1,1]）
                float4 clipPos = float4(screenUV * 2.0 - 1.0, 1.0, 1.0);
                // 2. 逆视投影矩阵：裁剪空间 → 世界空间
                float4 worldPos = mul(_InvViewProj, clipPos);
                worldPos /= worldPos.w; // 透视除法
                // 3. 计算光线方向并单位化
                float3 rd = normalize(worldPos.xyz - _CameraWorldPos);

                // 采样大气层散射
                float3 EnvColor = SAMPLE_TEXTURE2D_LOD(_EnvPanoramic,sampler_EnvPanoramic, DirToPanoramicUV(RotateAroundY(-rd, _PanoramicRotation)), 0.0).rgb;
                float3 EnvColor_duichen = SAMPLE_TEXTURE2D_LOD(_EnvPanoramic,sampler_EnvPanoramic, DirToPanoramicUV(RotateAroundY(rd, 1.0-_PanoramicRotation2)), 0.0).rgb;
                float3 EnvColor_f = lerp(EnvColor_duichen,EnvColor,step(0,rd.y));
                // 云信息
                float4 RFCloudData = SAMPLE_TEXTURE2D(_AtmosRFCloudTex,sampler_AtmosRFCloudTex, screenUV.xy);
                float3 FinalColor = RFCloudData.rgb;
                float TotalTransmittance = lerp(1.0,RFCloudData.a,smoothstep(0.01,0.03,rd.y));
                TotalTransmittance = RFCloudData.a;

                // 混合云
                float3 cloudColor = lerp(FinalColor, EnvColor, 0.3);
                float3 mixColor = lerp(cloudColor, EnvColor_f, saturate(TotalTransmittance));

                if (_DebugView == 0)
                {
                    screenUV = IN.screenPos.xy / IN.screenPos.w;
                }
                if (_DebugView == 1 || _DebugView == 5)
                {
                    screenUV.y = 1.0 - screenUV.y;
                }

                half3 reflection = SAMPLE_TEXTURE2D(_PlanarReflectionTexture,sampler_PlanarReflectionTexture,screenUV).rgb;

                if (_DebugView == 2)
                {
                    return float4(EnvColor,1.0);
                }
                if (_DebugView == 3)
                {
                    return float4(lerp(cloudColor,0.0,TotalTransmittance),1.0);
                }
                if (_DebugView == 4)
                {
                    return float4(mixColor,1.0);
                }
                if (_DebugView == 5)
                {
                    return float4(lerp(mixColor,reflection,step(0.01,length(reflection))),1.0);
                    //return float4(mixColor*step(0.01,length(reflection)),1.0);
                }


                return half4(reflection, 1);
            }
            ENDHLSL
        }
    }
}
