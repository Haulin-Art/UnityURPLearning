Shader "PostProcessing/AtmosScattering"
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
        CBUFFER_END
        
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
        float MiePhase(float cosTheta)
        {
            float g = _MieG;
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
        
        // 从UV和深度重建世界位置
        float3 ReconstructWorldPosition(float2 uv, float depth)
        {
            // 从深度纹理重建裁剪空间位置
            float4 clipPos = float4(uv * 2.0 - 1.0, depth, 1.0);
            
            // 处理平台差异
            #if UNITY_UV_STARTS_AT_TOP
                clipPos.y = -clipPos.y;
            #endif
            
            // 转换到世界空间
            float4 worldPos = mul(unity_MatrixInvVP, clipPos);
            return worldPos.xyz / worldPos.w;
        }
            
        // 以下为可以在太空中看的        
        struct atmosData
        {
            float3 ro;
            float3 rd;
            float noise; // 用于消除光线步进的分层感
            float rayLength;// 气体距离
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
        float3 mAtomsScattering(atmosData m)
        {
            float ds = m.rayLength / m.numSamples;
            float3 p = m.ro + ( m.rd * ds)*0.5; // 初始化位置
            float3 RayF = float3(0,0,0);// 累积的瑞利散射
            float3 MieF = float3(0,0,0);// 累积的米尔散射
            // 储存视线方向的上一步数据，用于梯形采样
            float2 prevDens;
            float3 prevRayScatter;
            float3 prevMieScatter;
            // 累积的视角光路透射率
            float2 accDens;

            // 这个用于计算rd方向的总透射率，并混合所有透射率
            // 我们假设视线从A进入大气层，之后沿着rd到B穿过大气层，其中每步的采样点为P，P逆着太阳光与大气层在C点到达边界
            for (int i=0 ; i < m.numSamples ; i++)
            {
                // 当前点的海拔高度
                float h = length(p - m.planetCenter) - m.planetRadius;

                // 计算视线rd深度
                float RayAtmosDens = exp( m.atmosIntensity*(-h / m.assHeightScale.x));
                float RayDensity = ds*(RayAtmosDens + prevDens.x)*0.5;
                float MieAtmosDens = exp( m.atmosIntensity*(-h / m.assHeightScale.y));
                float MieDensity = ds*(MieAtmosDens + prevDens.y)*0.5;

                // 计算光学深度
                float2 inter = raySphereIntersect(p , m.sunDir , m.planetCenter,m.planetRadius + m.atmosHeight);
                // 也是跟上面一样，计算纯大气层气体厚度
                float rayLen = inter.x>0 && inter.y>0 && inter.y>inter.x ? (inter.y-inter.x) : inter.y;

                // ============================== 光学深度 ================================    
                float lds = rayLen / m.numLigSamples;


                float edgeFactor = length(p + m.sunDir*(inter.x+rayLen*0.5));
                //edgeFactor = smoothstep(m.planetRadius , m.planetRadius+m.atmosHeight , edgeFactor)
                //lds = 0.5;
                float3 lp = p + (m.sunDir * lds)*0.5; // 光学深度的初始位置
                float lRayDensity = 0;
                float lMieDensity = 0; // 初始化光学深度

                int lstep =0;
                bool earthBlock = false; // 这里直接用RayLength排除掉遮挡的情况了,所以没用
                while (lstep < m.numLigSamples && !earthBlock)
                {
                    // 当前光学深度采样点处的海拔高度
                    float lh = length(lp - m.planetCenter) - m.planetRadius;
                    lRayDensity += lds*exp( m.atmosIntensity*(-lh / m.assHeightScale.x));
                    lMieDensity += lds*exp(m.atmosIntensity*(-lh / m.assHeightScale.y));
                    lp += lds * m.sunDir;
                    lstep += 1;
                }
                //lRayDensity += accDens.x ;
                //lMieDensity += accDens.y ;
                // ============================= 统计数据 ========================================
                // 计算透射率
                float3 transmittance = 1.0*exp(-(m.rayleighScattering*(RayDensity+lRayDensity)+
                                    m.mieScattering*(MieDensity+lMieDensity)));

                float cos = dot(m.sunDir , m.rd); // 角度
                // 计算方法是：采样点大气密度 * 步长 * 散射系数 * 相位函数 * 光路透射率 * 视线透射率
                RayF += RayAtmosDens* ds * m.rayleighScattering * RayleighPhase(cos) * transmittance; // 添加相位函数的变量
                //RayF = (RayF + prevRayScatter)*0.5;
                MieF += MieAtmosDens* ds  * m.mieScattering * MiePhase(cos) * transmittance; // 添加相位函数的变量
                //MieF = (MieF + prevMieScatter)*0.5;

                p += m.rd * ds; // 更新采样点位置

                // 更新上一帧数据
                prevDens.x = RayAtmosDens;
                prevDens.y = MieAtmosDens;
                prevRayScatter = RayF;
                prevMieScatter = MieF;
                // 累积
                accDens += float2(RayDensity,MieDensity);
            }
            return (RayF + MieF);
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
            float2 aspectScreenUV = float2(screenUV.x , screenUV.y/(_ScreenParams.x/_ScreenParams.y));
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
            furDis = min(furDis,sceneDepth);
            float rayLen2 = inter.x>0 && inter.y>0 && inter.y>inter.x ? (furDis - inter.x) : furDis;

            
            // =============================== 大气层参数 ===================================
            atmosData data;
            data.ro = rayStart + 0.5*(rayLen2/_NumSamples)*blueN*rd; // 根据蓝噪波随机增加采样距离
            data.rd = rd;
            data.noise = blueN;
            data.rayLength = rayLen2;// 气体距离
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

            float3 scatter = mAtomsScattering(data);
            //scatter = pow(scatter,2.2);

            // ========================= 远处的天空调成黑色 =============================
            originalColor.xyz *= step(yvzhi,0.001);

            // ========================== 合成颜色 ==================================
            float3 finalCol = _Brightness * _SunColor * scatter*step(0.0,rayLen) + originalColor;
            //finalCol = (originalColor / (originalColor + scatter*50.0*step(0.0,rayLen)))*originalColor + scatter*1.0;

            return float4(finalCol*float3(1,1,1),1.0);

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