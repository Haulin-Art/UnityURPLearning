Shader "PostProcessing/AtmosScattering_Fixed"
{
    Properties
    {
        [HideInInspector]_MainTex ("Base (RGB)", 2D) = "white" {}
        _BlueNTex ("随机蓝噪波纹理",2D ) = "black"{}
        _Brightness ("亮度",Float) = 5.0
        _SunColor ("光颜色",Color) = (1,1,1,1)
        _TotalScale ("整体缩放" , Float ) = 1
        _PlanetRadius ("行星半径", Float) = 6371000
        _AtmosphereHeight ("大气层厚度", Float) = 100000
        _Altitude ("海拔(km)",Float) = 0.0

        _RayleighScaleHeight ("瑞利散射高度", Float) = 8000
        _MieScaleHeight ("米氏散射高度", Float) = 1200

        _AtmosIntensity ("大气密度",Range(0.0,3.0) ) = 1.0
        
        _ScatterScale ("散射强度",Vector) = (1,1,1,1)
        _RayleighScattering ("瑞利散射系数", Vector) = (0.000058, 0.000135, 0.00033, 0)
        _MieScattering ("米氏散射系数", Float) = 0.00002
        _MieExtinction ("米氏消光系数", Float) = 0.00002
        
        _MieG ("Mie G", Range(0, 0.99)) = 0.639

        _NumSamples ("视线采样数", Range(4, 64)) = 16
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
            
            float _AtmosIntensity;
            float2 _ScatterScale;
            float3 _RayleighScattering;
            float _MieScattering;
            float _MieExtinction;
            
            float _MieG;

            int _NumSamples;
            int _NumSamplesLight;
            
            float3 _CameraWorldPos;
            float3 _SunDirection;
            float4x4 _InvViewProj;
        CBUFFER_END
        
        float2 RaySphereIntersect(float3 rayOrigin, float3 rayDir, float3 sphereCenter, float sphereRadius)
        {
            float3 oc = rayOrigin - sphereCenter;
            float a = dot(rayDir, rayDir);
            float b = 2.0 * dot(oc, rayDir);
            float c = dot(oc, oc) - sphereRadius * sphereRadius;
            float discriminant = b * b - 4.0 * a * c;
            
            if (discriminant < 0.0)
                return float2(-1.0, -1.0);
            
            float sqrtDisc = sqrt(discriminant);
            float t1 = (-b - sqrtDisc) / (2.0 * a);
            float t2 = (-b + sqrtDisc) / (2.0 * a);
            
            return float2(min(t1, t2), max(t1, t2));
        }

        float MiePhase(float cosTheta)
        {
            float g = _MieG;
            float g2 = g * g;
            float numerator = 1.0 - g2;
            float denominator = 4.0 * PI * pow(1.0 + g2 - 2.0 * g * cosTheta, 1.5);
            return numerator / denominator;
        }
        
        float RayleighPhase(float cosTheta)
        {
            return (3.0 / (16.0 * PI)) * (1.0 + cosTheta * cosTheta);
        }
        
        float3 ReconstructWorldPosition(float2 uv, float depth)
        {
            float4 clipPos = float4(uv * 2.0 - 1.0, depth, 1.0);
            
            #if UNITY_UV_STARTS_AT_TOP
                clipPos.y = -clipPos.y;
            #endif
            
            float4 worldPos = mul(_InvViewProj, clipPos);
            return worldPos.xyz / worldPos.w;
        }
            
        struct AtmosData
        {
            float3 ro;
            float3 rd;
            float noise;
            float rayLength;
            float3 planetCenter;
            float planetRadius;
            float atmosHeight;
            float atmosIntensity;
            float2 heightScale;
            float3 rayleighScattering;
            float3 mieScattering;
            float3 sunDir;
            int numSamples;
            int numLigSamples;
        };

        float3 ComputeAtmosScattering(AtmosData data)
        {
            float ds = data.rayLength / data.numSamples;
            float3 p = data.ro + (data.rd * ds) * 0.5;
            float3 rayleighAccum = float3(0, 0, 0);
            float3 mieAccum = float3(0, 0, 0);
            float2 prevDensity = float2(0, 0);
            float2 accDensity = float2(0, 0);

            for (int i = 0; i < data.numSamples; i++)
            {
                float h = length(p - data.planetCenter) - data.planetRadius;

                float rayleighAtmosDensity = exp(data.atmosIntensity * (-h / data.heightScale.x));
                float rayleighDensity = ds * (rayleighAtmosDensity + prevDensity.x) * 0.5;
                float mieAtmosDensity = exp(data.atmosIntensity * (-h / data.heightScale.y));
                float mieDensity = ds * (mieAtmosDensity + prevDensity.y) * 0.5;

                float2 inter = RaySphereIntersect(p, data.sunDir, data.planetCenter, data.planetRadius + data.atmosHeight);
                float rayLen = inter.x > 0 && inter.y > 0 && inter.y > inter.x ? (inter.y - inter.x) : inter.y;

                float lds = rayLen / data.numLigSamples;
                float3 lp = p + (data.sunDir * lds) * 0.5;
                float lightRayleighDensity = 0;
                float lightMieDensity = 0;

                int lstep = 0;
                while (lstep < data.numLigSamples)
                {
                    float lh = length(lp - data.planetCenter) - data.planetRadius;
                    lightRayleighDensity += lds * exp(data.atmosIntensity * (-lh / data.heightScale.x));
                    lightMieDensity += lds * exp(data.atmosIntensity * (-lh / data.heightScale.y));
                    lp += lds * data.sunDir;
                    lstep += 1;
                }

                float3 transmittance = exp(-(data.rayleighScattering * (rayleighDensity + lightRayleighDensity) +
                                    data.mieScattering * (mieDensity + lightMieDensity)));

                float cosTheta = dot(data.sunDir, data.rd);
                rayleighAccum += rayleighAtmosDensity * ds * data.rayleighScattering * RayleighPhase(cosTheta) * transmittance;
                mieAccum += mieAtmosDensity * ds * data.mieScattering * MiePhase(cosTheta) * transmittance;

                p += data.rd * ds;

                prevDensity = float2(rayleighAtmosDensity, mieAtmosDensity);
                accDensity += float2(rayleighDensity, mieDensity);
            }
            return (rayleighAccum + mieAccum);
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
            float linearDep = Linear01Depth(depth, _ZBufferParams);

            float2 screenUV = i.screenPos.xy / i.screenPos.w;
            
            float3 ro = _CameraWorldPos;
            
            float4 clipPos = float4(screenUV * 2.0 - 1.0, 1.0, 1.0);
            float4 worldPos = mul(_InvViewProj, clipPos);
            worldPos /= worldPos.w;
            float3 rd = normalize(worldPos.xyz - ro);
            
            float aspectRatio = _ScreenParams.x / _ScreenParams.y;
            float2 aspectScreenUV = float2(screenUV.x, screenUV.y * aspectRatio);
            float blueN = SAMPLE_TEXTURE2D(_BlueNTex, sampler_BlueNTex, aspectScreenUV).r;

            float scaleFactor = _TotalScale;
            float atmosH = _AtmosphereHeight / scaleFactor;
            float planetR = _PlanetRadius / scaleFactor;
            float3 newPlanetCenter = float3(0.0, -planetR - _Altitude * 1000 / scaleFactor, 0.0);

            float2 inter = RaySphereIntersect(ro, rd, newPlanetCenter, planetR + atmosH);
            float3 rayStart = inter.x > 0 && inter.y > 0 && inter.y > inter.x ? (ro + inter.x * rd) : ro;
            float rayLen = inter.x > 0 && inter.y > 0 && inter.y > inter.x ? (inter.y - inter.x) : inter.y;
            
            float2 inter2 = RaySphereIntersect(ro, rd, newPlanetCenter, planetR);
            float farDis = lerp(inter.y, inter2.x, step(0.0, inter2.x));
            
            float isFarPlane = step(0.9, Linear01Depth(depth, _ZBufferParams));
            float linearEyeDep = LinearEyeDepth(depth, _ZBufferParams);
            float sceneDepth = lerp(linearEyeDep, 1.0e8, isFarPlane);
            farDis = min(farDis, sceneDepth);
            float rayLen2 = inter.x > 0 && inter.y > 0 && inter.y > inter.x ? (farDis - inter.x) : farDis;

            AtmosData data;
            data.ro = rayStart + 0.5 * (rayLen2 / _NumSamples) * blueN * rd;
            data.rd = rd;
            data.noise = blueN;
            data.rayLength = rayLen2;
            data.planetCenter = newPlanetCenter;
            data.planetRadius = planetR;
            data.atmosHeight = atmosH;
            data.atmosIntensity = 1.0 / max(_AtmosIntensity, 0.001);
            data.heightScale = float2(_RayleighScaleHeight / scaleFactor, _MieScaleHeight / scaleFactor);
            data.rayleighScattering = _ScatterScale.x * scaleFactor * float3(0.000058, 0.000135, 0.00033);
            data.mieScattering = _ScatterScale.y * scaleFactor * float3(0.00002, 0.00002, 0.00002);
            data.sunDir = normalize(_SunDirection);
            data.numSamples = _NumSamples;
            data.numLigSamples = _NumSamplesLight;

            float3 scatter = ComputeAtmosScattering(data);

            originalColor.xyz *= step(isFarPlane, 0.001);

            float3 finalCol = _Brightness * _SunColor * scatter * step(0.0, rayLen) + originalColor;

            return float4(finalCol, 1.0);
        }
        ENDHLSL
        
        Pass
        {
            Name "MieScattering"
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            ENDHLSL
        }
    }
}
