Shader "Unlit/ScreenWSPos"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _HeightTex ("Height Texture", 2D) = "black" {}

        _DropNormalTex ("静态水珠法线", 2D) = "blue" {}


        [Space(15)]
        _Tile06 ("================= 水下折射设置 ========================",Float) = 0.0 
        _AbsorptionColor ("折射吸收颜色", Color) = (0.53, 0.7, 0.86)
        _AbsorptionScale ("折射吸收强度", Range(0.0, 10.0)) = 1.0
        _RefractionBlurStart ("折射模糊开始深度", Range(0.0, 10.0)) = 0.3
        _RefractionBlurEnd ("折射模糊结束深度", Range(0.1, 50.0)) = 5.0
        _RefractionBlurStrength ("折射模糊强度", Range(0.0,10.0)) = 2.0

        //[Header("BSDF设置")]
        [Space(15)]
        _Tile10 ("================= BSDF 基础散射设置 ========================",Float) = 0.0 
        //_SSSNormalSmoothness ("次表面法线平滑度(决定是否使用波浪的法线)", Range(0.0, 1.0)) = 0.5
        _ScatterColor ("散射颜色", Color) = (0.2, 0.5, 0.8)
        _BSDFAbsorptionColor ("BSDF吸收颜色", Color) = (0.1, 0.2, 0.3)
        _PhaseG ("相位参数G", Range(-1.0, 1.0)) = 0.8
        _Thickness ("厚度", Range(0.0, 20.0)) = 0.5
        _DepthScale ("深度缩放", Range(0.1, 50.0)) = 10.0
        
        //[Header("光线步进设置")]
        [Space(15)]
        _Tile07 ("================= 光线步进散射 ========================",Float) = 0.0 
        //[Toggle(_USE_RAY_MARCHING)] _UseRayMarching ("启用光线步进", Float) = 0
        _RayMarchSteps ("步进次数", Range(1, 16)) = 6
        _RayMarchIntensity ("步进强度", Range(0.0, 10.0)) = 2.71
        _RayMarchMaxDistance ("最大步进距离", Range(0.1, 50.0)) = 5.0
        [Toggle] _UsePerSamPosShadow("使用采样点阴影",Float) = 0

    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        HLSLINCLUDE
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            #include "Assets/m_Shader/m_WaterShader/ff_WaterBSDF.hlsl"
            #include "Assets/m_Shader/m_WaterShader/ff_WaterRayMarching.hlsl"
            #include "Assets/m_Shader/m_WaterShader/ff_WaterRefraction.hlsl"

            #include "Assets/ZMD/Shader/Flow_Drop_Func_Library.hlsl"

            TEXTURE2D(_DropNormalTex);SAMPLER(sampler_DropNormalTex);
            TEXTURE2D(_MainTex);SAMPLER(sampler_MainTex);
            TEXTURE2D(_HeightTex);SAMPLER(sampler_HeightTex);
            //TEXTURE2D(_CameraDepthTexture);SAMPLER(sampler_CameraDepthTexture);
            //TEXTURE2D(_CameraColorTexture);SAMPLER(sampler_CameraColorTexture);

            // 自定义的带有Mipmap的屏幕不透明物体纹理
            TEXTURE2D(_ScreenMipMapRT);SAMPLER(sampler_ScreenMipMapRT); // 只用这个实现伪前向散射模糊效果
            TEXTURE2D(_ScreenMipMapRT2);SAMPLER(sampler_ScreenMipMapRT2);


            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;

                float3 _AbsorptionColor;
                float _AbsorptionScale;
                float _RefractionBlurStart;
                float _RefractionBlurEnd;
                float _RefractionBlurStrength;


                float3 _ScatterColor;
                float3 _BSDFAbsorptionColor;
                float _PhaseG;
                float _Thickness;
                float _DepthScale;

                int _RayMarchSteps;
                float _RayMarchIntensity;
                float _RayMarchMaxDistance;
                float _UsePerSamPosShadow;


                float4x4 _VPMatrix; // 视图投影矩阵
                float3 _NearPlaneCornersTL;
                float3 _NearPlaneCornersTR;
                float3 _NearPlaneCornersBL;
                float3 _NearPlaneCornersBR;
            CBUFFER_END

        ENDHLSL

        Pass
        {
            HLSLPROGRAM

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
                float3 worldPos : TEXCOORD2;
            };


            
            float3 m_FFRayMarchVolumeScattering(
                float3 rayOrigin,
                float3 rayDirection,
                float maxDistance,
                float3 extinctionCoeff,
                float3 scatterAlbedo,
                float3 lightDir,
                float3 viewDir,
                float3 lightColor,
                float phaseG,
                float shadowValue,
                FFRayMarchConfig config)
            {
                // 初始化累积变量
                float3 totalScatter = 0;            // 总散射
                float3 accumulatedTransmittance = 1; // 累积透射率，初始为1（无衰减）

                // 计算抖动值，消除带状伪影
                // 使用屏幕位置和时间作为随机种子
                float dither = FFSampleDither(rayOrigin.xy, _Time.y) * config.jitterStrength;

                // 预计算相位函数参数
                // cosTheta = cos(视线方向与光线方向的夹角)
                float cosTheta = FFComputePhaseCosTheta(viewDir, lightDir);

                // 步进循环
                [loop]
                for (int i = 0; i < config.stepCount; i++)
                {
                    // 计算归一化参数t，加入抖动偏移
                    float t = (float(i) + dither) / float(config.stepCount);

                    // 计算当前位置的归一化距离（指数分布）
                    float normalizedDistance = FFGetExponentialStepPosition(t, config.expFactor, config.stepCount);
                    float currentDistance = normalizedDistance * maxDistance;

                    // 计算当前步长
                    float stepSize = FFGetExponentialStepSize(t, config.expFactor, config.stepCount, maxDistance);

                    // 计算当前步进点的世界坐标
                    float3 currentWorldPos = rayOrigin + rayDirection * currentDistance;

                    // 计算当前步的阴影值
                    float currentShadow = shadowValue;
                    if (config.usePerStepShadow)
                    {
                        currentShadow = 1.0 - FFSampleShadowAtPositionFast(currentWorldPos);
                        //currentShadow = 1.0 - FFSampleShadowAtPosition(currentWorldPos);
                    }

                    // 计算当前步的透射率
                    float3 stepTransmittance = exp(-extinctionCoeff * stepSize);

                    // 计算相位函数值
                    float phaseValue = FFWaterPhaseFunctionFast(phaseG, cosTheta);

                    // 计算消光因子和散射贡献
                    float3 extinctionFactor = 1.0 - stepTransmittance;
                    float3 scatterContribution = lightColor * extinctionFactor * scatterAlbedo * phaseValue * (1.0 - currentShadow);

                    // 累积散射
                    totalScatter += scatterContribution * accumulatedTransmittance;

                    // 更新累积透射率
                    accumulatedTransmittance *= stepTransmittance;
                }

                return totalScatter;
            }



            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = TransformObjectToHClip(v.vertex);
                o.uv = v.uv;
                
                // 计算屏幕空间位置
                o.screenPos = ComputeScreenPos(o.vertex);

                o.worldPos = TransformObjectToWorld(v.vertex);
                return o;
            }


            float4 frag (v2f i) : SV_Target
            {
                // 平面UV坐标
                float2 ScreenUV = i.screenPos.xy / i.screenPos.w;
                //#if UNITY_UV_STARTS_AT_TOP
                //    ScreenUV.y = 1.0 - ScreenUV.y;
                //#endif
                float3 ScreenWorldPos = lerp(
                    lerp(_NearPlaneCornersBL, _NearPlaneCornersBR, ScreenUV.x),
                    lerp(_NearPlaneCornersTL, _NearPlaneCornersTR, ScreenUV.x),
                    ScreenUV.y
                );
                float3 nearPlaneCenter = (_NearPlaneCornersTL + _NearPlaneCornersTR + _NearPlaneCornersBL + _NearPlaneCornersBR) / 4.0;
                float3 cameraPos = _WorldSpaceCameraPos;

                float4 touying = mul(_VPMatrix, float4(ScreenWorldPos,1));
                float2 zz = (touying.xy / touying.w)/2.0 + 0.5;
                float height = SAMPLE_TEXTURE2D(_HeightTex, sampler_HeightTex, zz).r;

                float3 rd = normalize(ScreenWorldPos - cameraPos);

                float thickness = 0.003;float shixin = thickness - 0.0015;
                float shuixia = step(ScreenWorldPos.y,height);
                float waterline = smoothstep(height-thickness,height-shixin,ScreenWorldPos.y)*
                    (1.0-smoothstep(height+shixin,height+thickness,ScreenWorldPos.y));

                // ==================== 静态水珠,偏移采样 ==================================
                float3 dropNormal = SAMPLE_TEXTURE2D_LOD(_DropNormalTex, sampler_DropNormalTex, ScreenUV,0).rgb * 2.0 - 1.0;
                float dropMask = (1.0-shuixia)*smoothstep(1.0,0.8,ScreenUV.y);
                //ScreenUV += (dropNormal.xz * 0.08)* dropMask;
                ScreenUV = saturate(ScreenUV); 
                
                //return float4(float3(1,1,1)*(dropMask+waterline),1.0);
                //return float4(float3(1,1,1)*smoothstep(ScreenWorldPos.y+0.03,ScreenWorldPos.y+0.07,height),1);


                float3 sceneColor = SAMPLE_TEXTURE2D_LOD(_MainTex, sampler_MainTex, ScreenUV,5.0);
                float3 hei = SAMPLE_TEXTURE2D(_HeightTex, sampler_HeightTex, ScreenUV);
                
                float zzz = step(length(ScreenWorldPos-hei),0.0002);
                



                // 采样深度
                float depth = SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepthTexture, ScreenUV).r;
                float linearDepth = LinearEyeDepth(depth, _ZBufferParams);


                float planeT = (1.2-cameraPos.y) / rd.y; // 到达水平面的距离
                planeT = max(planeT, 0); // 确保不为负数
                planeT += 100000000*step(planeT,0); // 没有相交的地方设置为极大数
                //float
                float waterDepth = min(linearDepth,planeT);

                float mipmapDepRamp = smoothstep(_RefractionBlurStart, _RefractionBlurEnd, linearDepth);
                //float3 mipmapScreenColor = SAMPLE_TEXTURE2D_LOD(_ScreenMipMapRT, sampler_ScreenMipMapRT, ScreenUV, mipmapDepRamp*_RefractionBlurStrength).rgb;
                float3 newMipScene = SAMPLE_TEXTURE2D_LOD(_ScreenMipMapRT2,sampler_ScreenMipMapRT2, ScreenUV,mipmapDepRamp*_RefractionBlurStrength);
                // 根据水深应用水的吸收效果
                float3 refractionColor = FFApplyWaterAbsorption(newMipScene, smoothstep(0.0, 5.0, waterDepth)*_AbsorptionScale, _AbsorptionColor);
                
                //float3 newMipScene = SAMPLE_TEXTURE2D_LOD(_ScreenMipMapRT2,sampler_ScreenMipMapRT2, ScreenUV,3.0);
                //return float4(newMipScene,1);


                // 获取太阳方向
                Light mainLight = GetMainLight();
                float3 SunDir = normalize(mainLight.direction);
                float3 SunColor = mainLight.color;


                

                
                float _FresnelF0 = 0.02;

                //return float4(float3(1,1,1)*waterDepth/10,1);
                // 计算消光系数和散射反照率
                float3 extinctionCoeff = _ScatterColor + _BSDFAbsorptionColor;
                float3 scatterAlbedo = _ScatterColor / max(extinctionCoeff, 1e-6);
                
                float3 bsdfScattering=float3(0,0,0);
                
                // 这里我发现使用不平滑的法线后，此表面散射会呈现一块一块黑的，环境反射不能很好地结合，表现在有黑边的感觉，这个给个只有近岸海浪的此表面的法线调整阈值
                float3 sssNormal = -rd;
                // 使用Ray Marching进行体积散射
                FFRayMarchConfig rmConfig = FFCreateDefaultRayMarchConfig();
                rmConfig.stepCount = (int)_RayMarchSteps;
                rmConfig.maxDistance =  min(_RayMarchMaxDistance, waterDepth);
                rmConfig.usePerStepShadow = 1;
                
                float3 rayDir = rd;
                //rayDir.y = -abs(rayDi.y);
                //rayDir = normalize(rayDir);
                
                bsdfScattering = FFRayMarchVolumeScattering(
                    ScreenWorldPos, rayDir, rmConfig.maxDistance,
                    extinctionCoeff, scatterAlbedo,
                    SunDir, -rd, SunColor,
                    _PhaseG, 0.0, rmConfig
                );
                
                bsdfScattering *= _RayMarchIntensity;
                //bsdfScattering = ScreenWorldPos;

                //20*saturate(10.0-linearDepth)*100000
                float T_exit = FFFresnelExit(_FresnelF0, sssNormal, rd);
                bsdfScattering *= lerp(T_exit,1.0,0.7);
                // 使用简化的BSDF计算
                bsdfScattering += 0.0*2.0*FFEvaluateWaterScattering(
                    sssNormal, -rd, SunDir, SunColor,
                    _ScatterColor, _BSDFAbsorptionColor,
                    20.0, _FresnelF0, _PhaseG,
                    0.0
                )*smoothstep(-0.02,0.00,SunDir.y);


                //float t = _Time.y*0.5;
                //float drop1 = Drops(ScreenUV,_Time.y,  0.1, 0.5, 0.1);
                //float2 d = DropLayer2(ScreenUV*2.0, t,0.5);
                //return float4(float3(1,1,1)*(d.x+d.y),1);

                //bsdfScattering = -rd;
                //return float4(float3(1,1,1)*shuixia,1);

                float3 finalColor = lerp(sceneColor,bsdfScattering+0.7*refractionColor,shuixia) *saturate(1.0-waterline*shuixia+0.6);
                //finalColor = finalColor * (1.0-smoothstep(3.0,10.0,linearDepth)*shuixia);

                return float4(finalColor,1);
            }
            ENDHLSL
        }

        // 屏幕后处理，给画面增加水滴模糊
        Pass
        {
            HLSLPROGRAM

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
                float3 worldPos : TEXCOORD2;
            };

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = TransformObjectToHClip(v.vertex);
                o.uv = v.uv;
                
                // 计算屏幕空间位置
                o.screenPos = ComputeScreenPos(o.vertex);

                o.worldPos = TransformObjectToWorld(v.vertex);
                return o;
            }

            float4 frag (v2f i) : SV_Target
            {
                float2 ScreenUV = i.screenPos.xy / i.screenPos.w;
                float3 dropNormal = SAMPLE_TEXTURE2D_LOD(_DropNormalTex, sampler_DropNormalTex, ScreenUV,0).rgb * 2.0 - 1.0;
                ScreenUV -= dropNormal.xz * 0.05;

                float3 sceneColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, ScreenUV);


                return float4(sceneColor,1);
            }
            ENDHLSL
        }
    }
}
