Shader "FluidFlux/water"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _WaterCol ("浅水颜色",Color) = (0.0,0.3,0.6)
        _DeepWaterCol ("深水颜色",Color) = (0.0,0.3,0.6)
        [Space(15)]
        _VectorDisMap ("矢量置换纹理", 2D) = "white" {}
        _VectorDisMapNormal("矢量置换纹理法线", 2D) = "white" {}
        [Space(15)]
        _VectorDisMapScale ("矢量置换整体强度", Float) = 3.0
        _VDMXScale ("矢量置换x强度", Range(-2,2)) = 1.0
        _VDMYScale ("矢量置换y强度", Range(-2,2)) = -0.2
        [Space(15)]
        _WavePos ("浪花位置",Range(-2.0,2.0))= 1.0
        _WaveScale ("浪花大小范围",Range(-5.0,5.0)) = 2.0
        [Space(15)]
        _VDMXOffset ("矢量置换x偏移", Float) = 0.0
        _VDMYOffset ("矢量置换y偏移", Float) = -0.5
        _OceanNorTex ("海面法线", 2D) = "white" {}
        _Speed ("波动速度", Range(-5.0,5.0)) = 0.2
        _SineCount ("正弦波数量", Range(0.0,5.0)) = 3.0
        _sineScale ("正弦波幅度", Range(-1.0,1.0)) = 0.15

        _SDFTex ("SDF距离图", 2D) = "white" {}
        _GradientTex ("梯度图", 2D) = "white" {}

        _CES ("CES",Range(-1.0,1.0)) = 0.0
        
        [Header(Fresnel Settings)]
        _FresnelF0 ("Fresnel F0", Range(0.0, 0.1)) = 0.02
        _FresnelPower ("Fresnel Power", Range(1.0, 10.0)) = 5.0
        
        [Header(Refraction Settings)]
        _RefractionStrength ("Refraction Strength", Range(0.0, 0.1)) = 0.02
        _AbsorptionColor ("Absorption Color", Color) = (0.1, 0.2, 0.3)
        
        [Header(Reflection Settings)]
        _EnvReflectionStrength ("Env Reflection Strength", Range(0.0, 2.0)) = 0.5
        _Roughness ("Roughness", Range(0.0, 1.0)) = 0.3
        
        [Header(Specular Settings)]
        _SpecularPower ("Specular Power", Range(8.0, 256.0)) = 64.0
        _SpecularIntensity ("Specular Intensity", Range(0.0, 3.0)) = 1.0
        
        [Header(BSDF Settings)]
        _ScatterColor ("Scatter Color", Color) = (0.2, 0.5, 0.8)
        _BSDFAbsorptionColor ("BSDF Absorption Color", Color) = (0.1, 0.2, 0.3)
        _PhaseG ("Phase G", Range(-1.0, 1.0)) = 0.8
        _Thickness ("Thickness", Range(0.0, 1.0)) = 0.5
        _DepthScale ("Depth Scale", Range(0.1, 50.0)) = 10.0
        
        [Header(Ray Marching Settings)]
        [Toggle(_USE_RAY_MARCHING)] _UseRayMarching ("Use Ray Marching", Float) = 0
        _RayMarchSteps ("Ray March Steps", Range(1, 16)) = 8
        _RayMarchIntensity ("Ray March Intensity", Range(0.0, 3.0)) = 1.0
        _RayMarchMaxDistance ("Ray March Max Distance", Range(0.1, 50.0)) = 20.0
        
        [Header(SSS Settings)]
        [Toggle(_USE_SSS)] _UseSSS ("Use SSS", Float) = 1
        _SSSColor ("SSS Color", Color) = (0.0, 0.5, 0.8, 1.0)
        _SSSStrength ("SSS Strength", Range(0.0, 5.0)) = 1.0
        _SSSDepthScale ("SSS Depth Scale", Range(0.1, 50.0)) = 5.0
        _SSSFade ("SSS Fade", Color) = (1.0, 1.0, 1.0, 1.0)
        _SunGlitterIntensity ("Sun Glitter Intensity", Range(0.0, 2.0)) = 0.3
        _SunGlitterSpeed ("Sun Glitter Speed", Range(0.0, 10.0)) = 2.0
    }
    SubShader
    {
        Tags { 
            "RenderType" = "Transparent"
            "Queue" = "Transparent"
            "IgnoreProjector" = "True"
            "RenderPipeline" = "UniversalPipeline"
        }
        Cull Off

        HLSLINCLUDE
            #pragma shader_feature _USE_RAY_MARCHING
            #pragma shader_feature _USE_SSS
            
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "ff_WaterCommon.hlsl"
            #include "ff_WaterFresnel.hlsl"
            #include "ff_WaterRefraction.hlsl"
            #include "ff_WaterReflection.hlsl"
            #include "ff_WaterPhase.hlsl"
            #include "ff_WaterBSDF.hlsl"
            #include "ff_WaterRayMarching.hlsl"
            #include "ff_WaterForwardScatter.hlsl"
            
            #pragma vertex vert
            #pragma fragment frag
            
            CBUFFER_START(UnityPerMaterial)
                float3 _WaterCol;
                float3 _DeepWaterCol;
                float _VectorDisMapScale;
                float _VDMXScale;
                float _VDMYScale;
                float _WavePos;
                float _WaveScale;
                float _VDMXOffset;
                float _VDMYOffset;
                float _Speed;
                float _SineCount;
                float _sineScale;
                float _CES;
                float _FresnelF0;
                float _FresnelPower;
                float _RefractionStrength;
                float3 _AbsorptionColor;
                float _EnvReflectionStrength;
                float _Roughness;
                float _SpecularPower;
                float _SpecularIntensity;
                float3 _ScatterColor;
                float3 _BSDFAbsorptionColor;
                float _PhaseG;
                float _Thickness;
                float _DepthScale;
                float _UseRayMarching;
                float _RayMarchSteps;
                float _RayMarchIntensity;
                float _RayMarchMaxDistance;
                float _UseSSS;
                float3 _SSSColor;
                float _SSSStrength;
                float _SSSDepthScale;
                float3 _SSSFade;
                float _SunGlitterIntensity;
                float _SunGlitterSpeed;
            CBUFFER_END
            
            float4 _VectorDisMap_ST;
            TEXTURE2D(_VectorDisMap);SAMPLER(sampler_VectorDisMap); 
            TEXTURE2D(_VectorDisMapNormal);SAMPLER(sampler_VectorDisMapNormal); 
            TEXTURE2D(_OceanNorTex);SAMPLER(sampler_OceanNorTex); 
            float4 _OceanNorTex_ST;

            TEXTURE2D(_SDFTex);SAMPLER(sampler_SDFTex);
            TEXTURE2D(_GradientTex);SAMPLER(sampler_GradientTex); 

            TEXTURE2D(_CameraOpaqueTexture);SAMPLER(sampler_CameraOpaqueTexture);
            float4 _CameraOpaqueTexture_TexelSize;

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
                float3 worldPos : TEXCOORD1;
                float4 pos : SV_POSITION;
                float2 newUV : TEXCOORD5;
                float uvMask : TEXCOORD10;
                float4 screenUV : TEXCOORD6;
                float3 norWS : TEXCOORD7;
                float3 ttt : TEXCOORD8;
                float3 viewDirWS : TEXCOORD9;
            };
            
            float2 animUV(float2 uv,float sinBase ,float time,float4 uv_ST)
            {
                float w = 0.01;
                float2 newUV = uv*uv_ST.xy + uv_ST.zw;
                float nu = frac(newUV.x - time*_Speed);
                nu += -_sineScale * sin(((sinBase - time*_Speed)*2.0 - 1.0) * PI*_SineCount);
                nu = clamp(frac(nu),w,1.0-w);
                float nv = pow(abs(frac(newUV.y)-0.5),0.97);
                float weizhi = 1.0 ; float daxiao = 2.0;
                nv = -clamp((uv.x+_WavePos)*_WaveScale - nv,w,1.0-w);
                newUV = float2(nu,nv);
                return newUV;
            }
            
            float3 decodeDisp(float3 disp)
            {
                disp = pow(disp,0.45);
                disp -= 0.5;
                disp *= float3(_VDMXScale,_VDMYScale,0.5);
                disp = float3(disp.x,0.0,disp.y);
                disp *= _VectorDisMapScale;
                disp += float3(_VDMXOffset,0.0,_VDMYOffset);
                return disp;
            }
            
            float2 waveUV(float dis,float offset,float duanshu,float qingxie)
            {
                float u = frac(dis-_Time.y*_Speed+qingxie);
                float v = u - dis + offset ;
                v /= duanshu;
                return clamp(float2(u,v),0.01,0.99);
            }
            
            float3 getVdm(float2 UV)
            {
                float2 gradient = SAMPLE_TEXTURE2D_LOD(_GradientTex,sampler_GradientTex,UV,0.0).xy;
                float sdf = SAMPLE_TEXTURE2D_LOD(_SDFTex,sampler_SDFTex,UV,0.0).x;
                float3 forward = float3(gradient.x,0,gradient.y);

                float dis = -sdf*15.0;
                float3 dir = forward;
                float2 UUVV = waveUV(UV.x*5.0,3.0,2.0,-1.5*UV.y);
                UUVV = 1-waveUV( dis , 2.0  , 2.0 , 0.2*gradient.y - 0.2*gradient.x) ;
                float3 ddisp = SAMPLE_TEXTURE2D_LOD(_VectorDisMap,sampler_VectorDisMap,UUVV,0.0).xyz;
                float3 vdm = decodeDisp(ddisp).x*dir + decodeDisp(ddisp).z*float3(0,1,0);
                return vdm;
            }
            
            v2f vert (appdata v)
            {
                v2f o;
                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.uv = v.uv;
                float scale = 20.0;
                float2 worldUV=1.0- (o.worldPos/scale + 0.5).xz;
                float2 UV = worldUV;
                UV = o.uv;
                UV = v.vertex.xz;
                UV = saturate(worldUV);

                float2 gradient = SAMPLE_TEXTURE2D_LOD(_GradientTex,sampler_GradientTex,UV,0.0).xy;
                float sdf = SAMPLE_TEXTURE2D_LOD(_SDFTex,sampler_SDFTex,UV,0.0).x;
                float3 forward = float3(gradient.x,0,gradient.y);

                float dis = -sdf*7.0;
                float3 dir = forward;
                float2 UUVV = 1-waveUV( dis , 1.0  , 2.0 , -1.5*gradient.y) ;
                float3 ddisp = SAMPLE_TEXTURE2D_LOD(_VectorDisMap,sampler_VectorDisMap,UUVV,0.0).xyz;
                float3 vdm =  decodeDisp(ddisp).x*dir + decodeDisp(ddisp).z*float3(0,1,0);

                o.newUV = UUVV;

                vdm = getVdm(UV);

                float3 vdmR = getVdm(UV+float2(0.01,0.0));
                float3 vdmU = getVdm(UV+float2(0.0,0.01));
                // 计算法线，这里需要注意的是，计算法线用的是世界坐标采样，因此，用这个映射过的世界坐标采样后
                // 得到的矢量位移信息转换到世界空间后，得在加上偏移后的世界位置，这样差分得到的法向才是对的
                float mask = step(sdf,0);
                mask *= smoothstep(0.5,0.40,abs(UV.x-0.5)) * smoothstep(0.5,0.40,abs(UV.y-0.5));
                o.uvMask = mask;
                float3 wp  = o.worldPos+TransformObjectToWorld(vdm*mask);
                float3 wpr = o.worldPos-float3(0.01*scale,0,0)+TransformObjectToWorld(vdmR*mask);
                float3 wpu = o.worldPos-float3(0,0,0.01*scale)+TransformObjectToWorld(vdmU*mask);
                o.norWS = normalize(cross((wpu-wp),(wpr-wp)));

                o.ttt = ddisp*float3(1,1,1);
                //o.ttt = mask*float3(1,1,1);

                float3 newPos = v.vertex.xyz + vdm*mask;

                o.pos = TransformObjectToHClip(float4(newPos,1.0));

                o.screenUV = ComputeScreenPos(o.pos);
                
                o.viewDirWS = _WorldSpaceCameraPos - o.worldPos;
                
                return o;
            }
        ENDHLSL

        Pass
        {
            Tags {"LightMode" = "SRPDefaultUnlit"}
            ZWrite On
            ColorMask 0
            HLSLPROGRAM
            float4 frag (v2f i) : SV_Target
            {   
                return 0;
            }
            ENDHLSL
        }
        
        Pass
        {
            Tags { 
                "LightMode" = "UniversalForward"
            }
            ZWrite Off
            Cull Off
            Blend SrcAlpha OneMinusSrcAlpha

            HLSLPROGRAM
            
            float foamMask(float2 fuv,float2 fanimUV, float fDefaultFoam,float fFoamTex)
            {
                fDefaultFoam = pow(fDefaultFoam,0.77);
                float midFoam = pow(fanimUV.x,0.7) * pow(fuv.x,4.8);
                midFoam = pow(midFoam,0.9);
                float nearFoam = smoothstep(0.85,1.0,fuv.x);
                float foam = midFoam + nearFoam + fDefaultFoam;
                foam = clamp(foam,0.0,1.0);
                foam *= fFoamTex;
                return foam;
            }

            float4 frag (v2f i) : SV_Target
            {
                float2 newUV = animUV(i.uv,1, _Time.y, _VectorDisMap_ST);
                newUV = i.newUV;
                float scale = 20.0;
                float2 worldUV=1.0- (i.worldPos/scale + 0.5).xz;
                
                float3 viewDirWS = normalize(i.viewDirWS);
                float3 normal = normalize(i.norWS);

                // 这个贴图的xy是矢量置换信息，z是海浪会出现浮沫的遮罩信息
                float3 dispCol = SAMPLE_TEXTURE2D(_VectorDisMap, sampler_VectorDisMap,newUV).rgb;
                float sdf = SAMPLE_TEXTURE2D(_SDFTex,sampler_SDFTex,worldUV).x;
                float foamM = smoothstep(0.1,0.0,-sdf); // 只有靠近岸边的地方采油浮沫

                // 这个贴图的xyz存储法线信息，w储存浮沫信息
                float4 waveTex = SAMPLE_TEXTURE2D(_OceanNorTex,sampler_OceanNorTex, i.uv * _OceanNorTex_ST.xy + _OceanNorTex_ST.zw);
                float foam = foamMask(worldUV, newUV, dispCol.z, waveTex.w) * foamM;

                // 用于修正浮沫在贴图边缘的白边问题
                float xz = (1.0-step(newUV.x,0.05))*(1.0-step(0.95,newUV.x));
                xz += smoothstep(0.45,1.0,i.uv.x);
                xz = clamp(xz,0.0,1.0);
                foam *= xz;
                foam *= i.uvMask;

                // 屏幕UV
                float2 screenUV = i.screenUV.xy/i.screenUV.w;

                // ==================== 折射效果 ====================
                // 根据法线偏移屏幕UV来模拟折射
                float2 refractionOffset = FFGetRefractionOffset(normal, viewDirWS, _RefractionStrength);
                float2 refractedScreenUV = screenUV + refractionOffset;
                refractedScreenUV = saturate(refractedScreenUV);
                
                // 采样折射后的背景颜色
                float3 refractionColor = SAMPLE_TEXTURE2D(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, refractedScreenUV).rgb;
                // 采样折射后的背景深度
                float3 refractionDepth = SAMPLE_TEXTURE2D(_CameraDepthTexture,  sampler_CameraDepthTexture , refractedScreenUV).rgb;
                // 通过折射后的深度计算相对深度
                //float depth = SAMPLE_TEXTURE2D(_CameraDepthTexture,sampler_CameraDepthTexture,screenUV).r;
                float depthLinear = LinearEyeDepth(refractionDepth,_ZBufferParams);
                float selfDepthLinear = LinearEyeDepth(i.pos.z,_ZBufferParams);
                float waterDepth = depthLinear - selfDepthLinear;
                float rampMask = smoothstep(0.0,2.0,waterDepth);

                Light ld = GetMainLight();
                float3 lightDir = normalize(ld.direction);
                float3 lightColor = ld.color;
                
                // 根据水深应用水的吸收效果
                refractionColor = FFApplyWaterAbsorption(refractionColor, waterDepth, _AbsorptionColor);
                
                // 混合浅水与深水颜色，得到最终颜色
                float3 albedo = lerp(_WaterCol,_DeepWaterCol,rampMask);
                
                // 将折射颜色与水体颜色混合
                albedo = lerp(refractionColor, albedo, saturate(rampMask * 1.0));
                //albedo = refractionColor*albedo;
                
                // ==================== BSDF水体散射 ====================
                // 计算厚度（基于水深）
                float thickness = saturate(waterDepth / _DepthScale);
                
                // 计算消光系数和散射反照率
                float3 extinctionCoeff = _ScatterColor + _BSDFAbsorptionColor;
                float3 scatterAlbedo = _ScatterColor / max(extinctionCoeff, 1e-6);
                
                float3 bsdfScattering;
                
                #ifdef _USE_RAY_MARCHING
                    // 使用Ray Marching进行体积散射
                    FFRayMarchConfig rmConfig = FFCreateDefaultRayMarchConfig();
                    rmConfig.stepCount = (int)_RayMarchSteps;
                    rmConfig.maxDistance = min(waterDepth, _RayMarchMaxDistance);
                    
                    float3 rayDir = -viewDirWS;
                    rayDir.y = -abs(rayDir.y);
                    rayDir = normalize(rayDir);
                    
                    bsdfScattering = FFRayMarchVolumeScattering(
                        i.worldPos, rayDir, rmConfig.maxDistance,
                        extinctionCoeff, scatterAlbedo,
                        lightDir, viewDirWS, lightColor,
                        _PhaseG, 0.0, rmConfig
                    );
                    
                    bsdfScattering *= _RayMarchIntensity;
                    
                    float T_exit = FFFresnelExit(_FresnelF0, normal, viewDirWS);
                    bsdfScattering *= T_exit;
                #else
                    // 使用简化的BSDF计算
                    bsdfScattering = FFEvaluateWaterScattering(
                        normal, viewDirWS, lightDir, lightColor,
                        _ScatterColor, _BSDFAbsorptionColor,
                        thickness, _FresnelF0, _PhaseG,
                        0.0
                    );
                #endif
                
                // ==================== 高光计算 ====================
                float3 reflectDir = reflect(-viewDirWS, normal);
                float RdotL = saturate(dot(reflectDir, lightDir));
                float specular = pow(RdotL, _SpecularPower);
                float3 specCol = specular * lightColor * _SpecularIntensity;

                float fresnel = FFFresnelWater(normal, viewDirWS, _FresnelF0);
                fresnel = pow(fresnel, _FresnelPower);

                // ==================== 环境反射 ====================
                // 计算反射方向
                //float3 reflectDir = FFGetReflectionDir(normal, viewDirWS);
                
                // 采样环境反射（使用URP内置的GlossyEnvironmentReflection，支持Reflection Probe和Skybox）
                float3 envReflection = FFSampleEnvReflection(reflectDir, _Roughness, _EnvReflectionStrength);
                
                // 将环境反射与基础颜色混合
                float3 reflectionColor = FFBlendReflection(albedo, envReflection, fresnel, 1.0);

                // ==================== 最终颜色合成 ====================
                // 将BSDF散射与反射混合
                float3 finalColor = lerp(reflectionColor, bsdfScattering, 0.5);
                finalColor += specCol;

                // ==================== SSS次表面散射 ====================
                #ifdef _USE_SSS
                {
                    float3 sss = FFComputeWaterSSSFull(
                        normal, float3(0, 1, 0), viewDirWS,
                        lightDir, lightColor, waterDepth,
                        _SSSColor, _SSSStrength, _SSSDepthScale, _SSSFade
                    );
                    finalColor += sss;
                    
                    float3 sunGlitter = FFComputeSunGlitterAnimated(
                        normal, viewDirWS, lightDir, lightColor,
                        _Roughness, _SunGlitterIntensity,
                        _Time.y, _SunGlitterSpeed
                    );
                    finalColor += sunGlitter;
                }
                #endif

                float alpha = lerp(saturate(rampMask*50.0), 1.0, fresnel * 0.5);

                //return float4(bsdfScattering,1.0);
                return float4((finalColor+foam*2.0)*float3(1,1,1), alpha);
            }
            ENDHLSL
        }
            
    }
}
