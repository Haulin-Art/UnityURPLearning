Shader "PostProcessing/PlanetCloudAtmosScattering"
{
    Properties
    {
        [HideInInspector]_MainTex ("Base (RGB)", 2D) = "white" {}
        _BlueNTex ("随机蓝噪波纹理",2D ) = "black"{}
        _Brightness ("亮度",Float) = 5.0
        _SunColor ("光颜色",Color) = (1,1,1,1)
        // 大气参数
        _TotalScale ("整体缩放" , Float ) = 1
        _PlanetRadius ("行星半径", Float) = 6371000
        _AtmosphereHeight ("大气层厚度", Float) = 100000
        _Altitude ("海拔(km)",Float) = 0.0

        _RayleighScaleHeight ("瑞利散射高度", Float) = 8000
        _MieScaleHeight ("米氏散射高度", Float) = 1200

        _AtmosIntensity ("大气密度",Range(0.0,3.0) ) = 1.0
        
        // 散射系数
        _ScatterScale ("散射强度",Vector) = (1,1,1,1)
        // 控制不同波长的散射强度，蓝色(33.1e-6)最大，所以天空是蓝色的
        _RayleighScattering ("瑞利散射系数", Vector) = (0.000058, 0.000135, 0.00033, 0)
        // 控制雾、霾、光晕的强度
        _MieScattering ("米氏散射系数", Float) = 0.00002
        // 控制光线被大气吸收的程度
        _MieExtinction ("米氏消光系数", Float) = 0.00002
        
        // 相位函数参数
        // 控制散射方向性,0.0：各向同性散射,0.76：常见大气值，产生明显光晕,接近0.99：产生非常集中的太阳光柱效果
        _MieG ("Mie G", Range(0, 0.99)) = 0.639

        // 性能和质量
        // 视线方向的采样点数量，值越高效果越平滑
        _NumSamples ("视线采样数", Range(4, 64)) = 16
        // 太阳光方向的采样数量
        _NumSamplesLight ("太阳光采样数", Range(1, 16)) = 8

        _Cloud2Tex ("云贴图2",2D) = "black"{}
        _PlanetAlbedo ("行星颜色",2D) = "black"{}
        _PlanetAlbedoNight ("行星夜晚颜色",2D) = "black"{}
        _planetOcean ("行星海洋遮罩",2D) = "black"{}
        // 3D噪波纹理
        _CloudVoulumeTex ("3D噪波纹理",3D) = "black"{}
        // 特效贴图
        _VFX01 ("特效贴图1",2D) = "black"{}

        _CloudSDFVolume("云SDF",3D)= "black"{}
    }
    
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        LOD 100
        
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        //#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/SpaceTransforms.hlsl"

        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
        
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

        // 云参数
        TEXTURE2D(_Cloud2Tex);SAMPLER(sampler_Cloud2Tex);
        // 行星参数
        TEXTURE2D(_PlanetAlbedo);SAMPLER(sampler_PlanetAlbedo);
        TEXTURE2D(_PlanetAlbedoNight);SAMPLER(sampler_PlanetAlbedoNight);
        TEXTURE2D(_planetOcean);SAMPLER(sampler_planetOcean);       
        // 3D纹理
        TEXTURE3D(_CloudVoulumeTex);SAMPLER(sampler_CloudVoulumeTex); 

        TEXTURE3D(_CloudSDFVolume);SAMPLER(sampler_CloudSDFVolume); 

        // 特效贴图
        TEXTURE2D(_VFX01);SAMPLER(sampler_VFX01);  
        
        CBUFFER_START(UnityPerMaterial)
            float _Brightness;
            float3 _SunColor;
            // 大气参数
            float _TotalScale;
            float _PlanetRadius;
            float _AtmosphereHeight;
            float _Altitude;

            float _RayleighScaleHeight;
            float _MieScaleHeight;
            
            // 散射系数
            float _AtmosIntensity;
            float2 _ScatterScale;
            float3 _RayleighScattering;
            float _MieScattering;
            float _MieExtinction;
            
            // 相位函数
            float _MieG;

            // 性能和质量
            int _NumSamples;
            int _NumSamplesLight;
            
            // 从C#传递
            float3 _CameraWorldPos;
            float3 _SunDirection;
            float4x4 _InvViewProj;        // 逆视投影矩阵

            // ============== 云参数 ============================

        CBUFFER_END
       
        // 增强型快速饱和度调整
        float3 AdjustSaturation(float3 color, float saturation)
        {
            float luminance = dot(color, float3(0.299, 0.587, 0.114));
            float3 gray = luminance.xxx;

            // 基于亮度计算自适应混合系数
            float blendFactor = saturation;

            // 非线性的饱和度调整，避免高光/阴影区域过度变化
            return lerp(gray, color, blendFactor);
        }

        float2 raySphereIntersect(float3 rayOrigin, float3 rayDirection, 
                                 float3 sphereCenter, float sphereRadius) 
        {
            // 计算射线起点到球心的向量
            float3 oc = rayOrigin - sphereCenter;

            // 计算一元二次方程系数 [1,6,7](@ref)
            float a = dot(rayDirection, rayDirection); // 实际上应该是1（方向归一化），但保留通用性
            float b = 2.0 * dot(rayDirection, oc);
            float c = dot(oc, oc) - sphereRadius * sphereRadius;

            // 计算判别式
            float discriminant = b * b - 4.0 * a * c;

            // 判断是否有交点 [7](@ref)
            if (discriminant < 0.0) 
            {
                // 无实数解，射线与球体不相交
                return float2(-1.0, -1.0);
            }
            // 计算交点距离 [1](@ref)
            float sqrtDiscriminant = sqrt(discriminant);
            float t1 = (-b - sqrtDiscriminant) / (2.0 * a);
            float t2 = (-b + sqrtDiscriminant) / (2.0 * a);

            // 确保t1 <= t2
            if (t1 > t2) 
            {
                float temp = t1;
                t1 = t2;
                t2 = temp;
            }
            // 处理交点有效性（排除在射线反方向的交点）
            if (t2 < 0.0) 
            {
                // 两个交点都在射线起点后方
                return float2(-1.0, -1.0);
            }
            if (t1 < 0.0) 
            {
                // 只有一个有效交点（射线起点在球体内）
                t1 = t2;
            }
            return float2(t1, t2);
        }
        // 光线与球体相交计算
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

        // Mie相位函数（Henyey-Greenstein）
        float MiePhase(float cosTheta,float g)
        {
            //float g = _MieG;
            float g2 = g * g;
            float numerator = 1.0 - g2;
            float denominator = 4.0 * PI * pow(1.0 + g2 - 2.0 * g * cosTheta, 1.5);
            return numerator / denominator;
        }
        
        // Rayleigh相位函数
        float RayleighPhase(float cosTheta)
        {
            return (3.0 / (16.0 * PI)) * (1.0 + cosTheta * cosTheta);
            //return 0.75 * (1.0 + cosTheta * cosTheta);
        }
        

        // 获取世界坐标点的阴影信息
        float GetShadowAttenuation(float3 worldPos)
        {
            // 将世界坐标转换到阴影空间
            float4 shadowCoord = TransformWorldToShadowCoord(worldPos);
            // 采样实时阴影
            float shadow = MainLightRealtimeShadow(shadowCoord);
            return shadow;
        }

        float2 CalSphereUV(float3 worldPos, float3 sphereCenter)
        {
            float3 dir = normalize(worldPos - sphereCenter);

            // 使用更稳定的计算方法
            float u = atan2(dir.z, dir.x);
            u = (u < 0.0) ? u + 2.0 * PI : u; // 确保在0-2π范围内
            u /= (2.0 * PI);

            // 避免极点处的无限大值
            float v = acos(clamp(dir.y, -1.0, 1.0)) / PI;

            return float2(u, v);
        }
        float Mapping2MinMax(float min,float max,float t)
        {
            return (max-min)*t + min;
        }
        float samCloudTex(float3 pos,float3 center,float hRatio,float ds)
        {
            float2 cUV = CalSphereUV(pos,center);
            float cc = SAMPLE_TEXTURE2D(_Cloud2Tex,sampler_Cloud2Tex,cUV).r;
            cc = smoothstep(hRatio , hRatio + ds,cc*2);

            //float4 volume = SAMPLE_TEXTURE3D(_CloudVoulumeTex,sampler_CloudVoulumeTex,pos/10*_TotalScale);
            //float4 volume1 = SAMPLE_TEXTURE3D(_CloudVoulumeTex,sampler_CloudVoulumeTex,pos/2*_TotalScale);
            //float vv = (1.0 -volume.w +0.3)*(1.0 -volume.z +0.3)*smoothstep(0.0,1.0,volume.y);
            //vv *= (1-volume1.w + 0.2);
            //vv = smoothstep(hRatio , hRatio + ds,vv*0.9);

            //float4 df = SAMPLE_TEXTURE3D(_CloudSDFVolume,sampler_CloudSDFVolume,pos/15);
            //float vvv = smoothstep(0.5,1.0,1.0 - df.y);
           // vvv = smoothstep(hRatio , hRatio + ds,vvv);
            //vvv *= 0.4;
            //cc *= step(0,cc)*1.0;
            return cc;
        }
        float getCloudSDFDs(float3 pos,float scale)
        {
            float4 volume = SAMPLE_TEXTURE3D(_CloudSDFVolume,sampler_CloudSDFVolume,pos/15);
            float ds = volume.y * scale;
            if (ds<0.001)ds = 0.02;
            return ds;
        }
        // 以下为可以在太空中看的        
        struct atmosData
        {
            float3 ro;
            float3 rd;
            float noise; // 用于消除光线步进的分层感
            float rayLength;// 气体距离
            float sceneDepth; // 场景深度，包含行星
            float3 planetCenter;// 行星中心位置
            float planetRadius;// 行星半径
            float atmosHeight;// 大气层厚度
            float atmosIntensity;// 大气密度
            float2 assHeightScale;// 米尔与瑞丽散射的高度,x是瑞利
            float3 rayleighScattering;// 瑞利散射系数
            float3 mieScattering; // 米尔散射系数
            float3 sunDir;// 光方向
            int numSamples; // 视线方向采样次数
            int numLigSamples; // 光线方向采样次数
        };
        struct cloudData
        {
            float3 ro;
            float3 rd;
            float rayLength;
            float cloudStart;
            float cloudEnd;
            float cloudDensity;
            float cloudLigIntensity;
            bool inCloud;
            bool underPlanet;
        };
        float3 mAtomsScattering(atmosData m, cloudData c
                                ,out float3 atmosSca,out float4 cloudSca)
        {
            atmosSca = float3(0,0,0); cloudSca = float4(0,0,0,0);
            // 合并变量 - 优化寄存器
            float4 ds = float4(0,0,0,0); // x是大气视线步长，y是大气灯光步长，z是云层视线步长，w是云层灯光步长
            ds.x = m.rayLength / m.numSamples;
            ds.z = c.rayLength / m.numSamples;
            float4 accDens = float4(0,0,0,0); // 累积的视线密度，x是大气Ray,y是大气Mie,z是云
            // 单次循环密度变量-声明在循环外，避免寄存器反复创建释放
            float4 cuDens = float4(0,0,0,0); // 分别是Ray,Mie,cloud的单次视线深度
            float4 cuLigDens = float4(0,0,0,0);

            float3 p = m.ro + ( m.rd * ds.x)*0.5; // 初始化位置
            float3 RayF = float3(0,0,0);// 累积的瑞利散射
            float3 MieF = float3(0,0,0);// 累积的米尔散射
            float3 SunF = float3(0,0,0);// 太阳
            // 储存视线方向的上一步数据，用于梯形采样
            float2 prevDens;
            float3 prevRayScatter;
            float3 prevMieScatter;

            // 云参数
            float3 cp = c.ro + (c.rd * ds.z)*0.5; // 视线步进初始位置
            cp += (c.rd * ds.z)*2 * m.noise;
            float4 cloudLight; // 云层总光照
                       

            // 这个用于计算rd方向的总透射率，并混合所有透射率
            // 我们假设视线从A进入大气层，之后沿着rd到B穿过大气层，其中每步的采样点为P，P逆着太阳光与大气层在C点到达边界
            for (int i=0 ; i < m.numSamples ; i++)
            {
                // 当前点的海拔高度
                float h = length(p - m.planetCenter) - m.planetRadius;
                //h *= 5;

                // 计算视线rd深度
                float RayAtmosDens = exp( m.atmosIntensity*(-h / m.assHeightScale.x));
                float RayDensity = ds.x*(RayAtmosDens + prevDens.x)*0.5;
                //RayDensity *= ds.x;
                float MieAtmosDens = exp( m.atmosIntensity*(-h / m.assHeightScale.y));
                float MieDensity = ds.x*(MieAtmosDens + prevDens.y)*0.5;
                // 计算光学深度
                float2 inter = raySphereIntersect(p , m.sunDir , m.planetCenter,m.planetRadius + m.atmosHeight);
                // 也是跟上面一样，计算纯大气层气体厚度
                float rayLen = inter.x>0 && inter.y>0 && inter.y>inter.x ? (inter.y-inter.x) : inter.y;

                // ============================== 光学深度 ================================    
                ds.y = rayLen / m.numLigSamples;
                float3 lp = p + (m.sunDir * ds.y)*0.5 + m.noise*ds.y*m.sunDir; // 光学深度的初始位置
                float lRayDensity = 0;
                float lMieDensity = 0; // 初始化光学深度
                //float lshadow;

                // 云参数
                float perLigCloudDens; // 此次得光学步进深度
                float ch = (length(cp - m.planetCenter) - c.cloudStart)/(c.cloudEnd-c.cloudStart); // 云层高度
                float cc = samCloudTex(cp,m.planetCenter,ch,ds.z);
                //if( ch<0 || ch>1 ) cc = 0;
                accDens.z += 1.0 * cc * ds.z ;//(c.cloudEnd - c.cloudStart);
                cloudLight.w += 1.0 - exp(-accDens.z *0.2); // 累积云的密度
                // 云光学步进参数
                float2 cinter = raySphereIntersect(cp , m.sunDir , m.planetCenter ,c.cloudEnd);
                float cRayLen = cinter.x>0 && cinter.y>0 && cinter.y>cinter.x ? (cinter.y-cinter.x) : cinter.y;
                ds.w = cRayLen / m.numLigSamples;
                ds.w = 0.5*smoothstep(0.0,0.03, ds.w );

                //ds.z = getCloudSDFDs(cp,1);
                //ds.w = 0.02;
                float3 clp = cp + (m.sunDir * ds.w)*0.5 ;
                clp += m.sunDir * ds.w * m.noise *0.3;
                
                float cloudAtmosShadow; // 计算云层对大气光的遮挡
                float3 casp = p + (m.sunDir * ds.y)*0.5 ;//+ m.noise*ds.y*m.sunDir; 
                float casds = 0.15;
                // ============================= 光学方向步进 ==========================
                for (int j = 0 ;j < m.numLigSamples ; j++)
                {
                    // 当前光学深度采样点处的海拔高度
                    float lh = length(lp - m.planetCenter) - m.planetRadius;
                    lRayDensity += ds.y*exp( m.atmosIntensity*(-lh / m.assHeightScale.x));
                    lMieDensity += ds.y*exp(m.atmosIntensity*(-lh / m.assHeightScale.y));
                    // 计算云对大气散射的遮挡
                    float caslh = length(casp - m.planetCenter) - m.planetRadius;
                    if(caslh < c.cloudEnd - m.planetRadius){
                        cloudAtmosShadow += ds.y * samCloudTex(casp,m.planetCenter,lh,ds.y);
                    }

                    // 云部分c
                    float ch = (length(clp - m.planetCenter) - c.cloudStart)/(c.cloudEnd-c.cloudStart);
                    float cc = samCloudTex(clp,m.planetCenter,ch,ds.w);
                    perLigCloudDens += 1* cc * ds.w ;

                    //ds.w = getCloudSDFDs(cp,1);
                    // 更新数据
                    lp += ds.y * m.sunDir;
                    clp += ds.w * m.sunDir;
                    casp += casds * m.sunDir;
                }
                // ============================= 统计数据 ========================================
                // 计算透射率
                float3 transmittance = 1.0*exp(-1*(m.rayleighScattering*(accDens.x+lRayDensity)+
                                    m.mieScattering*(accDens.y+lMieDensity)));

                float cos = dot(m.sunDir , m.rd); // 角度
                // 计算方法是：采样点大气密度 * 步长 * 散射系数 * 相位函数 * 光路透射率 * 视线透射率
                RayF += RayDensity * m.rayleighScattering * RayleighPhase(cos) * transmittance; // 添加相位函数的变量
                float3 mie = MieDensity* ds.x  * m.mieScattering * transmittance; // 添加相位函数的变量
                MieF += mie * MiePhase(cos,_MieG); // 添加相位函数的变量
                SunF += mie * MiePhase(cos,0.95); // 添加相位函数的变量

                // ================ 处理阴影 =======================================
                float shadowDis = 0.1*i;
                float shadow = 1.0;
                if (shadowDis <= m.rayLength)
                {
                    shadow = GetShadowAttenuation(m.ro + m.rd*0.2*(i));
                }
                shadow = GetShadowAttenuation(p);
                //MieF *= lerp(shadow,1.0,0.3);
                //RayF *= lerp(shadow,1.0,0.3);
                // 云层阴影
                MieF *= lerp(exp(-cloudAtmosShadow*10),1.0,0.3);
                RayF *= lerp(exp(-cloudAtmosShadow*10),1.0,0.3);

                // ============== 云部分 =========================================

                cloudLight.xyz +=  cloudLight.w * 1 * exp(-(perLigCloudDens + 1.0*accDens.z));//*(1.0-exp(-perLigCloudDens*2));
                cloudLight.xyz *= 0.5;

                // =========== 更新上一步数据 =======================================
                p += m.rd * ds.x; // 更新采样点位置
                prevDens.xy = float2(RayDensity,MieDensity);
                prevRayScatter = RayF;
                prevMieScatter = MieF;
                // 累积
                accDens.xy += float2(RayDensity,MieDensity);

                // ========== 更新上一帧云数据 =====================================
                cp += m.rd* ds.z;
            }
            atmosSca = (RayF + MieF + SunF)*_Brightness;
            cloudSca = float4( cloudLight.xyz*(1.0-c.underPlanet) , cloudLight.w);
            //cloudSca = cloudAlpha;


            atmosSca = AdjustSaturation(atmosSca,3);

            return atmosSca + cloudSca.xyz;
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
            // 采样原始颜色
            float4 originalColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv);
            
            // 采样深度
            float depth = SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepthTexture, i.uv).r;
            float linearDep = Linear01Depth(depth,_ZBufferParams);

            // 屏幕UV
            float2 screenUV = i.screenPos.xy / i.screenPos.w;
            // ========== 步骤1：获取ro（光线原点） ==========
            float3 ro = _CameraWorldPos; // 直接使用相机世界位置
            // ========== 步骤3：计算基础rd（光线方向，未结合深度） ==========
            // 1. 把屏幕UV转成裁剪空间坐标（范围：x/y∈[-1,1]）
            float4 clipPos = float4(screenUV * 2.0 - 1.0, 1.0, 1.0);
            // 2. 逆视投影矩阵：裁剪空间 → 世界空间
            float4 worldPos = mul(_InvViewProj, clipPos);
            worldPos /= worldPos.w; // 透视除法
            // 3. 计算光线方向并单位化
            float3 rd = normalize(worldPos.xyz - ro);
            
            // ============================ 采样蓝噪波 =================================
            float2 aspectScreenUV = 6.0*float2(screenUV.x , screenUV.y/(_ScreenParams.x/_ScreenParams.y));
            float blueN = SAMPLE_TEXTURE2D(_BlueNTex,sampler_BlueNTex,aspectScreenUV).r;

            // ================================== 参数设置 ========================
            float scaleFactor = _TotalScale;
            float atmosH = _AtmosphereHeight/scaleFactor;
            float planetR = _PlanetRadius/scaleFactor;
            float3 newPlanetCenter = float3(0.0,- planetR - _Altitude*1000/scaleFactor,0.0);

            // ================================== 球光线距离 =============================
            // 计算光线与大气层的交点
            float2 inter = raySphereIntersect(ro,rd,newPlanetCenter,planetR+atmosH);
            // 计算在大气层上的起点，要是在大气层外，则起点在大气层表面，如果在内部，则等于摄像机位置
            float3 rayStart = inter.x>0 && inter.y>0 && inter.y>inter.x ? (ro + inter.x*rd ) : ro;
            // 也是跟上面一样，计算纯大气层气体厚度
            float rayLen = inter.x>0 && inter.y>0 && inter.y>inter.x ? (inter.y-inter.x) : inter.y;
            // 计算光线与行星的交点
            float2 inter2 = raySphereIntersect(ro,rd,newPlanetCenter,planetR);
            // 大气层厚度-考虑星球遮挡
            // 这个是求终点距离，如果在地表内，交点就是近点
            float furDis = lerp( inter.y, inter2.x , step(0.0,inter2.x));
            // 这里直接混合本来的场景深度，会因为 ZBuffer 的最远值限制，也就是视锥终点，所以要设置场景深度最远
            // 当快到达 ZBuffer 的最远处的时候，采取一个极大值
            float yvzhi = step(0.9,Linear01Depth(depth,_ZBufferParams));
            float linearEyeDep = LinearEyeDepth(depth,_ZBufferParams);
            float sceneDepth = lerp(linearEyeDep,1.0*1e8,yvzhi);
            //sceneDepth = linearEyeDep;
            furDis = min(furDis,sceneDepth);
            float rayLen2 = inter.x>0 && inter.y>0 && inter.y>inter.x ? (furDis - inter.x) : furDis;


            // =============================== 大气层参数 ===================================
            atmosData data;
            data.ro = rayStart + 0.0*(rayLen2/_NumSamples)*blueN*rd; // 根据蓝噪波随机增加采样距离
            data.rd = rd;
            data.noise = blueN;
            data.rayLength = rayLen2;// 气体距离
            data.sceneDepth = min(sceneDepth,max(inter2.x,0.0) + step(inter2.x,0.00001));
            data.planetCenter = newPlanetCenter;// 行星中心位置
            data.planetRadius = planetR;// 行星半径
            data.atmosHeight = atmosH;// 大气层厚度
            data.atmosIntensity = pow(_AtmosIntensity,-1);// 大气密度
            data.assHeightScale = 1.0*float2(_RayleighScaleHeight / scaleFactor , _MieScaleHeight/scaleFactor);// 米尔与瑞丽散射的高度,x是瑞利
            data.rayleighScattering = _ScatterScale.x * scaleFactor*float3(0.000058, 0.000135, 0.00033);// 瑞利散射系数
            data.mieScattering = _ScatterScale.y * scaleFactor*float3(0.00002,0.00002,0.00002); // 米尔散射系数
            data.sunDir = normalize(_SunDirection);// 光方向
            data.numSamples = _NumSamples; // 视线方向采样次数
            data.numLigSamples = _NumSamplesLight; // 光线方向采样次数


            // =========================== 云层数据 ==================================
            // ================================== 云层距离 =============================
            float cloudStart = data.planetRadius+ 0.3/_TotalScale;
            float cloudEnd =  data.planetRadius + 0.5/_TotalScale;
            float ro2center = length(ro-data.planetCenter);// 摄像机距离星球中心的距离，也就是相对高度
            // 计算光线与云终点球的交点
            float2 cinter = raySphereIntersect(ro,rd,newPlanetCenter,cloudEnd);
            // 计算光线与云圈起点球的交点
            float2 cinter2 = raySphereIntersect(ro,rd,newPlanetCenter,cloudStart);
            // 计算在云圈的起点，要是在云圈外，则起点在云圈表面，如果在内部，则等于摄像机位置
            float3 cRayStart = ro2center > cloudEnd ? (ro + cinter.x*rd ) : ro;
            cRayStart = ro2center < cloudStart ? (ro + cinter2.y*rd) :cRayStart;
            // 云圈厚度-在云圈的得时候
            float cFurDis = lerp( cinter.y, cinter2.x , step(0.0,cinter2.x));
            cFurDis = min(cFurDis,sceneDepth);

            // 各处的距离
            //float outdis = lerp(cinter.y - cinter.x,cinter2.x-cinter.x,step(0,cinter2.x));
            float outdis = lerp(cinter.y - cinter.x , cinter2.x-cinter.x,step(0,inter2.x));
            outdis = min(5*(cloudEnd-cloudStart) , outdis); // 限制边缘最大距离，不然会出错
            //float middis = lerp(cinter.x,cinter2.x,step(0,cinter2.x));
            //middis = 1;
            float middis = lerp(cinter.x,inter2.x,step(0,inter2.x));
            float indis = cinter.x - cinter2.x;

            float cRayLen2 = ro2center > cloudEnd ? outdis : middis;
            cRayLen2 = ro2center < cloudStart ? indis : cRayLen2;

            // ========================== 云参数 ===================================
            cloudData cdata;
            cdata.ro = cRayStart ;//+ 0.5*(cRayLen2/_NumSamples)*blueN*rd;
            cdata.rd = rd;
            cdata.rayLength = cRayLen2;
            cdata.cloudStart = cloudStart;
            cdata.cloudEnd = cloudEnd;
            cdata.cloudDensity = 1.0;
            cdata.cloudLigIntensity = 0.5;
            cdata.inCloud =  ro2center > cloudEnd && ro2center < cloudStart ? false : true;
            cdata.underPlanet =  ro2center < data.planetRadius ? true : false;


            // ========================== 行星 ====================================
            float3 planetPos = ro + rd*inter2.x;
            float3 planetNor = normalize(planetPos - data.planetCenter);
            float2 planetUV = CalSphereUV(planetPos,data.planetCenter);
            float3 planetCol = SAMPLE_TEXTURE2D(_PlanetAlbedo,sampler_PlanetAlbedo,planetUV);
            planetCol *= step(0.0,inter2.x) *1/PI *saturate(dot(_SunDirection,planetNor));
            float planetOceanMask = SAMPLE_TEXTURE2D(_planetOcean,sampler_planetOcean,planetUV).r;
            float3 planetSpecular = 0.3* planetOceanMask * step(0.0,inter2.x) * pow(max(0,dot(normalize(_SunDirection-rd),planetNor)),50.0);
            // ========================= 行星TBN - 云面投影=================================
            float3 planetT = cross(float3(0,1,0),planetNor);
            float3 planetB = cross(planetNor,planetT);
            float3x3 planetTBN = float3x3(planetT,planetB,planetNor);
            float3 sunProj = mul(planetTBN,-_SunDirection);
            float3 cloudShadow = SAMPLE_TEXTURE2D(_Cloud2Tex,sampler_Cloud2Tex,planetUV + sunProj.xy*0.03).r;
            cloudShadow = smoothstep(0.3,0.0,cloudShadow);


            // ========================== 最终颜色 =================================
            float3 atmosScattering;float4 cloudScattering;

            float3 scatter = mAtomsScattering(data,cdata,atmosScattering,cloudScattering);
            scatter = atmosScattering + cloudScattering.xyz;
            scatter = _SunColor*max(0,scatter);
            // ========================== 计算太阳形状 ================================
            float Sun = 2.0*step(0.9998,dot(rd,_SunDirection)) + 1.0;
            scatter *= Sun;
            // ========================= 远处的天空调成黑色 =============================
            originalColor.xyz *= step(yvzhi,0.001);

            // ========================== 合成颜色 ==================================
            float3 finalCol = _Brightness * _SunColor * scatter*step(0.0,rayLen)*yvzhi + originalColor;
            finalCol = (originalColor / (originalColor + scatter*50.0*step(0.0,rayLen)))*originalColor + scatter*1.0;


            // ======================== 特效 =======================================
            //float2 vfxUV = CalSphereUV(ro + cinter2.x*rd,data.planetCenter);
            float2 vfxUV = (ro + cinter2.x*rd).xz - data.planetCenter.xz;
            vfxUV *= 0.07;
            vfxUV += float2(0.5,0.5);
            float vfxMask = (ro + cinter2.x*rd).y - data.planetCenter.y; 
            float3 vfx01 = SAMPLE_TEXTURE2D(_VFX01,sampler_VFX01,vfxUV);
            vfx01 *= 15.0*step(0.47,vfxMask/40)*step(0,cinter2.x);
            vfx01 *= 0;


            //float4 volume1 = SAMPLE_TEXTURE3D(_CloudSDFVolume,sampler_CloudSDFVolume,planetPos/10);
            //float4 volume2 = SAMPLE_TEXTURE3D(_CloudVoulumeTex,sampler_CloudVoulumeTex,planetPos/2);

            //return float4(atmosScattering*float3(1,1,1),1);
            //return float4(cloudScattering.a*float3(1,1,1),1);
            //return float4(lerp(atmosScattering,cloudScattering.xyz,cloudScattering.a)*float3(1,1,1),1.0);
            //return float4(cdata.rayLength/60*float3(1,1,1),1.0);
            return float4((1.0*planetCol* cloudShadow + finalCol + 1*planetSpecular + vfx01)*float3(1,1,1),1.0);

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