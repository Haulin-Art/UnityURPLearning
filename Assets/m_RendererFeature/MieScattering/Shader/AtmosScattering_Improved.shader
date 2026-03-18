Shader "PostProcessing/AtmosScattering_Improved"
{
    Properties
    {
        [HideInInspector]_MainTex ("Base (RGB)", 2D) = "white" {}
        _BlueNTex ("随机蓝噪波纹理",2D ) = "black"{}
        _Brightness ("亮度",Float) = 1.0
        _SunColor ("光颜色",Color) = (1,1,1,1)
        _TotalScale ("整体缩放" , Float ) = 1
        _PlanetRadius ("行星半径", Float) = 6371000
        _AtmosphereHeight ("大气层厚度", Float) = 100000
        _Altitude ("海拔(km)",Float) = 0.0

        _RayleighScaleHeight ("瑞利散射高度", Float) = 8000
        _MieScaleHeight ("米氏散射高度", Float) = 1200
        _OzoneScaleHeight ("臭氧层高度", Float) = 25000
        _OzoneCenterHeight ("臭氧层中心高度", Float) = 25000

        _AtmosIntensity ("大气密度",Range(0.0,3.0) ) = 1.0
        
        _ScatterScale ("散射强度(X:Rayleigh Y:Mie)",Vector) = (1,1,1,1)
        _RayleighScattering ("瑞利散射系数", Vector) =(0.0000058,0.0000135,0.0000331)
        _MieScattering ("米氏散射系数", Float) = 0.0000021
        _MieExtinction ("米氏消光系数", Float) = 0.0000025
        _OzoneAbsorption ("臭氧吸收系数", Vector) = (0.00000065,0.000001881,0.000000085)
        
        _MieG ("Mie相位函数G值", Range(0, 0.99)) = 0.76
        _SunMieG ("太阳Mie相位函数G值", Range(0, 0.999)) = 0.98
        _SunMieIntensity ("太阳Mie散射强度", Range(0, 10)) = 1.0

        _NumSamples ("视线采样数", Range(4, 64)) = 32
        _NumSamplesLight ("太阳光采样数", Range(1, 16)) = 8
    }
    
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        LOD 100
        
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/SpaceTransforms.hlsl"
        
        struct Attributes
        {
            float4 positionOS : POSITION;
            float2 uv : TEXCOORD0;
        };
        
        struct Varyings
        {
            float4 positionCS : SV_POSITION;
            float2 uv : TEXCOORD0;
            float4 screenPos : TEXCOORD2;
        };
        
        TEXTURE2D(_MainTex);SAMPLER(sampler_MainTex);
        TEXTURE2D(_BlueNTex);SAMPLER(sampler_BlueNTex);
        TEXTURE2D(_CameraDepthTexture);SAMPLER(sampler_CameraDepthTexture);
        
        CBUFFER_START(UnityPerMaterial)
            float _Brightness;
            float3 _SunColor;
            float _TotalScale;
            float _PlanetRadius;
            float _AtmosphereHeight;
            float _Altitude;

            float _RayleighScaleHeight;
            float _MieScaleHeight;
            float _OzoneScaleHeight;
            float _OzoneCenterHeight;
            
            float _AtmosIntensity;
            float2 _ScatterScale;
            float3 _RayleighScattering;
            float _MieScattering;
            float _MieExtinction;
            float3 _OzoneAbsorption;
            
            float _MieG;
            float _SunMieG;
            float _SunMieIntensity;

            int _NumSamples;
            int _NumSamplesLight;
            
            float3 _CameraWorldPos;
            float3 _SunDirection;
            float4x4 _InvViewProj;
        CBUFFER_END

        // 瑞利散射系数 (单位: 1/m)
        // 红光散射最弱，蓝光散射最强，这就是天空是蓝色的原因
        static const float3 kBetaR = float3(5.8e-6, 13.5e-6, 33.1e-6);
        
        // 米氏散射系数 (单位: 1/m)
        // 对所有波长的散射大致相同，所以云和雾是白色的
        static const float3 kBetaM = float3(21e-6, 21e-6, 21e-6);
        
        // 臭氧吸收系数 (单位: 1/m)
        // 主要吸收绿光，对日落橙红色效果很重要
        static const float3 kOzone = float3(0.65e-6, 1.881e-6, 0.085e-6);
        
        // 射线与球体相交检测
        // 返回值: x = 近交点距离, y = 远交点距离，不相交返回 (-1, -1)
        float2 RaySphereIntersect(float3 rayOrigin, float3 rayDir, float3 sphereCenter, float sphereRadius)
        {
            float3 oc = rayOrigin - sphereCenter;
            float b = dot(oc, rayDir);
            float c = dot(oc, oc) - sphereRadius * sphereRadius;
            float discriminant = b * b - c;
            
            if (discriminant < 0.0)
                return float2(-1.0, -1.0);
            
            float sqrtDisc = sqrt(discriminant);
            return float2(-b - sqrtDisc, -b + sqrtDisc);
        }

        // 瑞利散射密度随高度变化: ρ(h) = exp(-h/H_R)
        float GetRayleighDensity(float h)
        {
            return exp(-h / _RayleighScaleHeight);
        }

        // 米氏散射密度随高度变化: ρ(h) = exp(-h/H_M)
        float GetMieDensity(float h)
        {
            return exp(-h / _MieScaleHeight);
        }

        // 臭氧密度随高度变化（高斯分布，中心在臭氧层高度）
        float GetOzoneDensity(float h)
        {
            return exp(-abs(h - _OzoneCenterHeight) / _OzoneScaleHeight);
        }

        // 瑞利相位函数: P_R(θ) = 3/(16π) * (1 + cos²θ)
        float RayleighPhase(float cosTheta)
        {
            return (3.0 / (16.0 * PI)) * (1.0 + cosTheta * cosTheta);
        }

        // Henyey-Greenstein 米氏相位函数
        // g = 0: 各向同性散射
        // g > 0: 前向散射（太阳光晕效果）
        // g 越大，光晕越集中
        float MiePhase(float cosTheta, float g)
        {
            float g2 = g * g;
            float numerator = 1.0 - g2;
            float denominator = pow(1.0 + g2 - 2.0 * g * cosTheta, 1.5);
            return numerator / (4.0 * PI * denominator);
        }

        // 计算光学深度（Optical Depth）
        // 返回值: x = 瑞利光学深度, y = 米氏光学深度, z = 臭氧光学深度
        float3 ComputeOpticalDepth(float3 p, float3 dir, float rayLength, int numSamples,
                                   float3 planetCenter, float planetRadius)
        {
            float ds = rayLength / (float)numSamples;
            float3 currentP = p;
            float3 opticalDepth = float3(0, 0, 0);
            
            for (int i = 0; i < numSamples; i++)
            {
                float h = length(currentP - planetCenter) - planetRadius;
                
                if (h < 0.0)
                    return float3(1e6, 1e6, 1e6);
                
                opticalDepth.x += GetRayleighDensity(h) * ds;
                opticalDepth.y += GetMieDensity(h) * ds;
                opticalDepth.z += GetOzoneDensity(h) * ds;
                
                currentP += dir * ds;
            }
            
            return opticalDepth;
        }

        // 核心大气散射计算（单次散射模型）
        float3 ComputeAtmosScattering(float3 rayOrigin, float3 rayDir, float rayLength,
                                      float3 planetCenter, float planetRadius, float atmosHeight,
                                      float3 sunDir, int numSamples, int numLightSamples)
        {
            float ds = rayLength / (float)numSamples;
            float3 p = rayOrigin + rayDir * ds * 0.5;
            
            float3 accumRayleigh = float3(0, 0, 0);
            float3 accumMie = float3(0, 0, 0);
            
            float3 totalRayleighDepth = float3(0, 0, 0);
            float3 totalMieDepth = float3(0, 0, 0);
            float3 totalOzoneDepth = float3(0, 0, 0);

            float3 betaR = _ScatterScale.x * kBetaR;
            float3 betaM = _ScatterScale.y * kBetaM;
            float mieExtinction = _MieExtinction > 0 ? _MieExtinction : 1.1 * _ScatterScale.y * 21e-6;

            // 计算相位函数（在整个积分过程中保持不变）
            float cosTheta = dot(rayDir, sunDir);
            float phaseR = RayleighPhase(cosTheta);
            float phaseM = MiePhase(cosTheta, _MieG);

            for (int i = 0; i < numSamples; i++)
            {
                float h = length(p - planetCenter) - planetRadius;
                
                if (h < 0.0)
                    break;
                
                float rayleighDensity = GetRayleighDensity(h);
                float mieDensity = GetMieDensity(h);
                float ozoneDensity = GetOzoneDensity(h);

                // 计算从当前点到大气层边界的光线长度
                float2 lightInter = RaySphereIntersect(p, sunDir, planetCenter, planetRadius + atmosHeight);
                float lightRayLength = max(0.0, lightInter.y);
                
                // 检测地球遮挡
                // 如果太阳方向被地球遮挡，则该采样点没有散射贡献
                float2 planetInter = RaySphereIntersect(p, sunDir, planetCenter, planetRadius);
                bool sunBlocked = false;
                if (planetInter.x > 0.0)
                {
                    // 地球在太阳方向上，检查是否在太阳之前
                    // 如果地球交点距离小于到大气层边界的距离，说明地球挡住了太阳
                    if (planetInter.x < lightRayLength)
                    {
                        sunBlocked = true;
                    }
                }

                if (lightRayLength > 0.0 && !sunBlocked)
                {
                    // 计算光线方向的光学深度
                    float3 lightOpticalDepth = ComputeOpticalDepth(p, sunDir, lightRayLength, numLightSamples,
                                                                   planetCenter, planetRadius);
                    
                    // 视线方向到当前点的光学深度
                    float3 viewOpticalDepth = float3(
                        totalRayleighDepth.x + rayleighDensity * ds * 0.5,
                        totalMieDepth.y + mieDensity * ds * 0.5,
                        totalOzoneDepth.z + ozoneDensity * ds * 0.5
                    );
                    
                    // 总光学深度
                    float3 totalOpticalDepth = viewOpticalDepth + lightOpticalDepth;
                    
                    // 计算透射率 T = exp(-τ)
                    float3 tau = betaR * totalOpticalDepth.x 
                               + mieExtinction * totalOpticalDepth.y 
                               + kOzone * totalOpticalDepth.z;
                    float3 transmittance = exp(-tau);
                    
                    // 累积散射光: 密度 × 步长 × 散射系数 × 相位函数 × 透射率
                    accumRayleigh += rayleighDensity * ds * betaR * phaseR * transmittance;
                    accumMie += mieDensity * ds * betaM * phaseM * transmittance;
                }

                // 更新累积光学深度
                totalRayleighDepth.x += rayleighDensity * ds;
                totalMieDepth.y += mieDensity * ds;
                totalOzoneDepth.z += ozoneDensity * ds;
                
                p += rayDir * ds;
            }
            
            return accumRayleigh + accumMie;
        }

        Varyings vert(Attributes v)
        {
            Varyings o;
            o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
            o.uv = v.uv;
            o.screenPos = ComputeScreenPos(o.positionCS);
            return o;
        }
        
        float4 frag(Varyings i) : SV_Target
        {
            float4 originalColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv);
            float depth = SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepthTexture, i.uv).r;

            float2 screenUV = i.screenPos.xy / i.screenPos.w;
            
            // 相机位置作为射线起点
            float3 ro = _CameraWorldPos;
            
            // 重建世界空间射线方向
            float4 clipPos = float4(screenUV * 2.0 - 1.0, 1.0, 1.0);
            float4 worldPos = mul(_InvViewProj, clipPos);
            worldPos /= worldPos.w;
            float3 rd = normalize(worldPos.xyz - ro);
            
            // 计算缩放后的大气参数
            float scaleFactor = _TotalScale;
            float atmosH = _AtmosphereHeight / scaleFactor;
            float planetR = _PlanetRadius / scaleFactor;
            float altitudeScaled = _Altitude * 1000.0 / scaleFactor;
            float3 planetCenter = float3(0.0, -planetR - altitudeScaled, 0.0);

            // 计算视线与大气层的交点
            float2 inter = RaySphereIntersect(ro, rd, planetCenter, planetR + atmosH);
            
            float rayLen = 0.0;
            float3 rayStart = ro;
            
            if (inter.x > 0.0 || inter.y > 0.0)
            {
                if (inter.x < 0.0)
                {
                    rayStart = ro;
                    rayLen = inter.y;
                }
                else
                {
                    rayStart = ro + rd * inter.x;
                    rayLen = inter.y - inter.x;
                }
            }
            
            // 检测与行星表面的交点
            float2 planetInter = RaySphereIntersect(ro, rd, planetCenter, planetR);
            if (planetInter.x > 0.0)
            {
                rayLen = min(rayLen, planetInter.x - (inter.x > 0.0 ? inter.x : 0.0));
            }

            // 处理场景深度
            float isFarPlane = step(0.9999, Linear01Depth(depth, _ZBufferParams));
            float linearEyeDep = LinearEyeDepth(depth, _ZBufferParams);
            float sceneDepth = lerp(linearEyeDep, 1.0e10, isFarPlane);
            
            float actualRayStart = inter.x > 0.0 ? inter.x : 0.0;
            float maxRayLen = sceneDepth - actualRayStart;
            rayLen = min(rayLen, maxRayLen);
            rayLen = max(rayLen, 0.0);

            float3 sunDir = normalize(_SunDirection);

            // 计算大气散射
            float3 scatter = ComputeAtmosScattering(
                rayStart, rd, rayLen,
                planetCenter, planetR, atmosH,
                sunDir, _NumSamples, _NumSamplesLight
            );

            // 额外的太阳Mie散射（用于绘制明亮的太阳圆盘）
            // 使用更高的G值产生更集中的光晕效果
            float cosTheta = dot(rd, sunDir);
            float sunPhaseM = MiePhase(cosTheta, _SunMieG);
            
            // 检测太阳是否被地球遮挡
            float2 sunPlanetInter = RaySphereIntersect(ro, sunDir, planetCenter, planetR);
            bool sunVisible = true;
            if (sunPlanetInter.x > 0.0)
            {
                sunVisible = false;
            }
            
            // 计算到太阳的透射率
            float3 sunScatter = float3(0, 0, 0);
            if (sunVisible)
            {
                float2 sunAtmosInter = RaySphereIntersect(ro, sunDir, planetCenter, planetR + atmosH);
                float sunRayLength = max(0.0, sunAtmosInter.y);
                
                if (sunRayLength > 0.0)
                {
                    float3 sunOpticalDepth = ComputeOpticalDepth(ro, sunDir, sunRayLength, _NumSamplesLight,
                                                                 planetCenter, planetR);
                    float mieExtinction = _MieExtinction > 0 ? _MieExtinction : 1.1 * _ScatterScale.y * 21e-6;
                    float3 sunTau = _ScatterScale.x * kBetaR * sunOpticalDepth.x 
                                  + mieExtinction * sunOpticalDepth.y 
                                  + kOzone * sunOpticalDepth.z;
                    float3 sunTransmittance = exp(-sunTau);
                    
                    sunScatter = _SunMieIntensity * sunPhaseM * sunTransmittance;
                }
            }

            // 最终颜色 = 散射光 + 太阳 + 原始场景 × 透射率
            float3 finalCol = _Brightness * _SunColor * (scatter + sunScatter);
            
            // 计算视线方向的透射率
            float3 viewOpticalDepth = ComputeOpticalDepth(rayStart, rd, rayLen, 4,
                                                          planetCenter, planetR);
            float mieExtinction = _MieExtinction > 0 ? _MieExtinction : 1.1 * _ScatterScale.y * 21e-6;
            float3 viewTau = _ScatterScale.x * kBetaR * viewOpticalDepth.x 
                           + mieExtinction * viewOpticalDepth.y 
                           + kOzone * viewOpticalDepth.z;
            float3 viewTransmittance = exp(-viewTau);
            
            finalCol += originalColor.rgb * viewTransmittance * (1.0 - isFarPlane);

            return float4(max(finalCol, 0.0), 1.0);
        }
        ENDHLSL
        
        Pass
        {
            Name "AtmosScattering"
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            ENDHLSL
        }
    }
}
