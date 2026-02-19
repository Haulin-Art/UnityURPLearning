Shader "PostProcessing/备份_AtmosScattering"
{
    Properties
    {
        [HideInInspector]_MainTex ("Base (RGB)", 2D) = "white" {}
        _BlueNTex ("随机蓝噪波纹理",2D ) = "black"{}
        
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
        float3 AtomsScattering(float3 ro, float3 rd, 
                float rayLength, float3 planetCenter, float3 sunDir)
        {
            float ds = rayLength/_NumSamples;
            float3 p = ro + (rd*ds)*0.5; // 初始化位置
            float3 RayF=float3(0,0,0);// 累积的瑞利散射
            float3 MieF=float3(0,0,0);// 累积的米尔散射
            // 储存的上一帧数据
            float2 prevDensity = 0; //上一帧的密度，x是ray，y是mie
            float3 prevScatterR = 0; // 上一帧散射
            float3 prevScatterM = 0; // 上一帧散射
            // 计算大气层被地球遮挡的部分，这部分很难接收到太阳光
            float3 jiaodain = ro + rayLength*rd;
            float2 jd =  RaySphereIntersect(jiaodain, -normalize(sunDir), planetCenter, _PlanetRadius+5000);
            float earthBlock = jd.x < 0.0 && jd.y < 0 ? 0.0 : abs(jd.y-jd.x);
            earthBlock = smoothstep(0.0,0.5,(jd.y - jd.x)*2.0/(_PlanetRadius ));
            earthBlock = pow(earthBlock,1.5);
            earthBlock = 1.0;

            float mmm = 0.0;

            for (int i=0;i<_NumSamples;i++)
            {
                // 当前点的海拔高度
                float h = length(p - planetCenter) - _PlanetRadius;


                // 地平线斜切系数，在地平线处，mie散射系数会被累积暴涨
                // 就会出现看不见地平线的感觉，因为散射的光太多了，这里给一个限制
                // 推荐修正值 0.00008 - 0.00005
                float xq = smoothstep(0.0,0.15,dot(normalize(ro-p),float3(0,1,0)));
                float mieCorrect = lerp(0.00005/_MieScattering,_MieScattering,xq);
                //mieCorrect = 1.0;

                // 计算视线深度，混合上一帧数据
                float RayDensity = (ds*exp( _AtmosIntensity*(-h / _RayleighScaleHeight)) + prevDensity.x)*0.5;
                float MieDensity = (ds*exp( _AtmosIntensity*(-h / _MieScaleHeight)) + prevDensity.y)*0.5;
                
                // 计算光学深度
                // 计算光学深度总深度
                float2 intersect =  RaySphereIntersect(p, sunDir, planetCenter, _PlanetRadius + _AtmosphereHeight);
                float len2 = intersect.x > 0 && intersect.y > 0 &&  
                    intersect.y > intersect.x
                    ? intersect.x : intersect.y; // 简化写法
                
                // 计算光线是否被地球遮挡
                float2 blockIntersect =  RaySphereIntersect(p, sunDir, planetCenter, _PlanetRadius);
                float maskBlock = blockIntersect.x > 0 && blockIntersect.y > blockIntersect.x ? 0.0:1.0;
                mmm += maskBlock;
                len2 = lerp(blockIntersect.x,len2,maskBlock);
                //len2 = blockIntersect.x > 0 && blockIntersect.y > blockIntersect.x && blockIntersect.x > intersect.x ? blockIntersect.x : len2;
                
                // 此时起点是当前的P，终点是沿光线反方向与大气层的交点 
                float lds = len2/_NumSamplesLight; // 计算光学深度的步长
                float3 lp = p + (sunDir*lds)*0.5; // 光学深度的初始位置
                float3 lRayDensity=float3(0,0,0);
                float3 lMieDensity=float3(0,0,0); // 初始化光学深度
                for (int j = 0;j<_NumSamplesLight;j++)
                {
                    float lh = length(lp - planetCenter) - _PlanetRadius;
                    lRayDensity += lds*exp( _AtmosIntensity*(-lh / _RayleighScaleHeight));
                    lMieDensity += lds*exp( _AtmosIntensity*(-lh / _MieScaleHeight));
                    lp += lds*sunDir;
                }
                // 计算透射率
                float3 transmittance = exp(-(_RayleighScattering*(RayDensity+lRayDensity)+
                                    _MieScattering*(MieDensity+lMieDensity) + 0 ));
                // 应用散射，混合上一帧
                float3 RayScatter = (ds*_RayleighScattering*transmittance + prevScatterR)*0.5;
                // 加入地平线斜切修正
                float3 MieScatter = (ds*_MieScattering*mieCorrect*transmittance + prevScatterM)*0.5;
                // 应用相位
                float cos = dot(sunDir,rd); // 角度
                RayF += earthBlock*RayleighPhase(cos)*RayScatter; // 添加相位函数的变量
                MieF += earthBlock*MiePhase(cos)*MieScatter; // 添加相位函数的变量

                // 更新上一帧数据
                prevDensity.xy = float2(RayDensity,MieDensity);
                prevScatterR = RayScatter;
                prevScatterM = MieScatter;
                
                p += rd*ds; // 更新采样点位置
            }
            //return mmm/_NumSamples;
            return RayF + MieF;
        }


        // 以下为可以在太空中看的        
        struct atmosData
        {
            float3 ro;
            float3 rd;
            bool inAtmos;
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
            float viewAssRatio = 0.0;// 视角位置的大气密度，用于过渡

            // 这个用于计算rd方向的总透射率，并混合所有透射率
            // 我们假设视线从A进入大气层，之后沿着rd到B穿过大气层，其中每步的采样点为P，P逆着太阳光与大气层在C点到达边界
            for (int i=0 ; i < m.numSamples ; i++)
            {
                // 当前点的海拔高度
                float h = length(p - m.planetCenter) - m.planetRadius;

                // 计算视线rd深度
                float RayDensity = ds*exp( m.atmosIntensity*(-h / m.assHeightScale.x));
                RayDensity = (RayDensity + prevDens.x)*0.5;
                float MieDensity = ds*exp( m.atmosIntensity*(-h / m.assHeightScale.y));
                MieDensity = (MieDensity + prevDens.y)*0.5;

                viewAssRatio += RayDensity + MieDensity;
                // 计算光学深度
                // 计算光学深度总深度
                float2 intersect =  RaySphereIntersect(p, m.sunDir, m.planetCenter, m.planetRadius + m.atmosHeight);
                float len2 = intersect.x < 0 ? intersect.y : intersect.x; // 简化写法
                
                // 计算光线与大气层的交点
                float2 inter = raySphereIntersect(p , m.sunDir , m.planetCenter,m.planetRadius + m.atmosHeight);
                // 计算在大气层上的起点，要是在大气层外，则起点在大气层表面，如果在内部，则等于摄像机位置
                //float3 lrayStart = inter.x>0 && inter.y>0 && inter.y>inter.x ? (p + inter.x*sunDir ) : p;
                // 也是跟上面一样，计算纯大气层气体厚度
                float rayLen = inter.x>0 && inter.y>0 && inter.y>inter.x ? (inter.y-inter.x) : inter.y;
                // 计算光线与行星的交点
                float2 inter2 = raySphereIntersect(p , m.sunDir , m.planetCenter,m.planetRadius);
                // 大气层厚度-考虑星球遮挡
                // 这个是求终点距离
                float furDis = lerp( inter.y, inter2.x , step(0.0,inter2.x));
                float rayLen2 = inter.x>0 && inter.y>0 && inter.y>inter.x ? (furDis - inter.x) : furDis;

                // ============================== 光学深度 ================================
                // 这里有两端深度，总的来说是光线从大气层打到现在的采样点p，再从p打到摄像机
                // 所以是采样点到大气层，加上上一帧的视线深度
                // 此时起点是当前的P，终点是沿光线反方向与大气层的交点 
                float lds = len2/m.numLigSamples; // 计算光学深度的步长
                //lds = rayLen / m.numLigSamples;
                //lds = 0.5;
                float3 lp = p + (m.sunDir * lds)*0.5; // 光学深度的初始位置
                float lRayDensity = 0;
                float lMieDensity = 0; // 初始化光学深度

                int lstep =0;
                bool earthBlock = false;
                while (lstep < m.numLigSamples && !earthBlock)
                {
                    float lh = length(lp - m.planetCenter) - m.planetRadius;
                    //float nextLh = length(lp+ lds * m.sunDir- m.planetCenter) - m.planetRadius;
                    //earthBlock = nextLh < 0 ? true : earthBlock;
                    lRayDensity += lds*exp( m.atmosIntensity*(-lh / m.assHeightScale.x));
                    lMieDensity += lds*exp(m.atmosIntensity*(-lh / m.assHeightScale.y));
                    lp += lds * m.sunDir;
                    lstep += 1;
                }
                // ligDep = D（P，C）+ D（P，A）
                // 这里是三条光路当中的两个，相当与沿着光线方向达到采样点的光到了眼睛里面多少
                lRayDensity += accDens.x;
                lMieDensity += accDens.y;


                // ============================= 统计数据 ========================================
                // 计算透射率
                float3 transmittance = 1.0*exp(-(m.rayleighScattering*(RayDensity+lRayDensity)+
                                    m.mieScattering*(MieDensity+lMieDensity)));

                float cos = dot(m.sunDir , m.rd); // 角度
                // 计算方法是：采样点大气密度 * 步长 * 散射系数 * 相位函数 * 光路透射率 * 视线透射率
                // 我这里的 RayDensity 就是 采样点大气密度 * 步长
                // 透射率以及合并
                RayF += RayDensity * m.rayleighScattering * RayleighPhase(cos) * transmittance; // 添加相位函数的变量
                RayF = (RayF + prevRayScatter)*0.5;
                MieF += MieDensity  * m.mieScattering * MiePhase(cos) * transmittance; // 添加相位函数的变量
                MieF = (MieF + prevMieScatter)*0.5;

                p += m.rd * ds; // 更新采样点位置

                // 更新上一帧数据
                prevDens.x = RayDensity;
                prevDens.y = MieDensity;
                prevRayScatter = RayF;
                prevMieScatter = MieF;
                // 累积
                accDens += float2(RayDensity,MieDensity);
            }
            viewAssRatio = m.inAtmos ? saturate(viewAssRatio) : 1.0; 
            //viewAssRatio = 
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
            


            


            float atmosH = _AtmosphereHeight;
            float planetR = 18.0;
            float3 planetCenter = float3(0, -planetR , 0);
            // 计算光线与大气层的交点
            float2 inter = raySphereIntersect(ro,rd,planetCenter,planetR+atmosH);
            // 计算在大气层上的起点，要是在大气层外，则起点在大气层表面，如果在内部，则等于摄像机位置
            float3 rayStart = inter.x>0 && inter.y>0 && inter.y>inter.x ? (ro + inter.x*rd ) : ro;
            // 也是跟上面一样，计算纯大气层气体厚度
            float rayLen = inter.x>0 && inter.y>0 && inter.y>inter.x ? (inter.y-inter.x) : inter.y;
            // 计算光线与行星的交点
            float2 inter2 = raySphereIntersect(ro,rd,planetCenter,planetR);
            // 大气层厚度-考虑星球遮挡
            // 这个是求终点距离
            float furDis = lerp( inter.y, inter2.x , step(0.0,inter2.x));
            float rayLen2 = inter.x>0 && inter.y>0 && inter.y>inter.x ? (furDis - inter.x) : furDis;

            

            atmosData data;
            data.ro = rayStart;
            data.rd = rd;
            data.inAtmos = inter.x>0 && inter.y>0 && inter.y>inter.x ? true : false;
            //data.inAtmos = true;
            data.rayLength = rayLen2;// 气体距离
            data.planetCenter = planetCenter;// 行星中心位置
            data.planetRadius = planetR;// 行星半径
            data.atmosHeight = atmosH;// 大气层厚度
            data.atmosIntensity = pow(_AtmosIntensity,-1);// 大气密度
            data.assHeightScale = 1.0*float2(_RayleighScaleHeight,_MieScaleHeight);// 米尔与瑞丽散射的高度,x是瑞利
            data.rayleighScattering = _ScatterScale.x*float3(0.000058, 0.000135, 0.00033);// 瑞利散射系数
            data.mieScattering = _ScatterScale.y*float3(0.00002,0.00002,0.00002); // 米尔散射系数
            data.sunDir = normalize(_SunDirection);// 光方向
            data.numSamples = _NumSamples; // 视线方向采样次数
            data.numLigSamples = _NumSamplesLight; // 光线方向采样次数

            float3 scatter = mAtomsScattering(data);

            float yuanchu = step(Linear01Depth(depth,_ZBufferParams),0.99);
            originalColor.xyz *= yuanchu;

            float3 finalCol;

            finalCol = scatter*5.0*step(0.0,rayLen) + originalColor;


                //finalCol = scatter*step(0.0,rayLen) + originalColor;


            //return float4(edgeFactor*float3(1,1,1),1.0);
            return float4(finalCol*float3(1,1,1),1.0);
            //return float4((saturate(scatter)+originalColor.xyz)*float3(1,1,1),1.0);
            //return float4(lerp(originalColor.xyz,scattering*sun,linearDep) + saturate(scatter),1.0);
            //return float4( (scattering+originalColor)*float3(1,1,1), originalColor.a);
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