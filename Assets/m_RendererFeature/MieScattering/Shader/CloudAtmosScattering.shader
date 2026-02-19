Shader "PostProcessing/CloudAtmosScattering"
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

        _AtmosBake ("大气层烘焙",2D) = "black"{}
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

        // 云参数
        TEXTURE2D(_Cloud2Tex);SAMPLER(sampler_Cloud2Tex);

        TEXTURE2D(_AtmosBake);SAMPLER(sampler_AtmosBake);
        TEXTURE2D(_AtmosUV);SAMPLER(sampler_AtmosUV);

        
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
            float3 SunF = float3(0,0,0);// 太阳
            // 储存视线方向的上一步数据，用于梯形采样
            float2 prevDens;
            float3 prevRayScatter;
            float3 prevMieScatter;
            // 累积的视角光路透射率
            float2 accDens;

           //m.atmosHeight -= 12.0;


            //float3 cuuu = m.ro + m.rd*m.rayLength*0.5;
            //float tttt = length(cuuu - m.planetCenter);
            //float blockMi = 1.0;

            // 这个用于计算rd方向的总透射率，并混合所有透射率
            // 我们假设视线从A进入大气层，之后沿着rd到B穿过大气层，其中每步的采样点为P，P逆着太阳光与大气层在C点到达边界
            for (int i=0 ; i < m.numSamples ; i++)
            {
                //if(tttt<10.0) blockMi = 0.0 ;
                //if (dot(-m.rd,normalize(m.ro-m.planetCenter))<0.8) return 0;



                // 当前点的海拔高度
                float h = length(p - m.planetCenter) - m.planetRadius;
                //h = length(p - m.planetCenter);

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



                float3 kkkkk = p + 0.5*m.sunDir*rayLen;
                float jjjjj = length(kkkkk - m.planetCenter);



                //float edgeFactor = length(p + m.sunDir*(inter.x+rayLen*0.5));
                //edgeFactor = smoothstep(m.planetRadius , m.planetRadius+m.atmosHeight , edgeFactor)
                //lds = 0.5;
                float3 lp = p + (m.sunDir * lds)*0.5; // 光学深度的初始位置
                float lRayDensity = 0;
                float lMieDensity = 0; // 初始化光学深度

                int lstep =0;
                bool earthBlock = false; // 这里直接用RayLength排除掉遮挡的情况了,所以没用
                while (lstep < m.numLigSamples && !earthBlock)
                {

                    //if(jjjjj<10.0) blockMi = 0.0 ;

                    // 当前光学深度采样点处的海拔高度
                    float lh = length(lp - m.planetCenter) - m.planetRadius;
                    lRayDensity += lds*exp( m.atmosIntensity*(-lh / m.assHeightScale.x));
                    lMieDensity += lds*exp(m.atmosIntensity*(-lh / m.assHeightScale.y));
                    
                    if(lh<0.0)lRayDensity=1000.0;
                    
                    lp += lds * m.sunDir;
                    lstep += 1;
                }
                //lRayDensity += accDens.x ;
                //lMieDensity += accDens.y ;
                // ============================= 统计数据 ========================================
                // 计算透射率
                float3 transmittance = 1.0*exp(-(m.rayleighScattering*(accDens.x+lRayDensity)+
                                    m.mieScattering*(accDens.y+lMieDensity)));

                float cos = dot(m.sunDir , m.rd); // 角度
                // 计算方法是：采样点大气密度 * 步长 * 散射系数 * 相位函数 * 光路透射率 * 视线透射率
                RayF += RayAtmosDens* ds * m.rayleighScattering * RayleighPhase(cos) * transmittance; // 添加相位函数的变量
                //RayF = (RayF + prevRayScatter)*0.5;
                float3 mie = MieAtmosDens* ds  * m.mieScattering * transmittance; // 添加相位函数的变量
                MieF += mie * MiePhase(cos,_MieG); // 添加相位函数的变量
                //MieF = (MieF + prevMieScatter)*0.5;
                SunF += mie * MiePhase(cos,0.95); // 添加相位函数的变量


                //MieF *= step(accDens.y+lMieDensity,6.0);
                //RayF *= step(accDens.x+lRayDensity,5.0);


                p += m.rd * ds; // 更新采样点位置

                // 更新上一帧数据
                prevDens.x = RayAtmosDens;
                prevDens.y = MieAtmosDens;
                prevRayScatter = RayF;
                prevMieScatter = MieF;
                // 累积
                accDens += float2(RayDensity,MieDensity);
            }
            return (RayF + MieF + SunF);
        }


        float TransformCloudDens(float2 StartEndHeight,float2 MinMaxFactor,float value,float cuH)
        {
            float intensity = cuH - (StartEndHeight.y + StartEndHeight.x)*0.5;
            intensity = cuH < StartEndHeight.y && cuH > StartEndHeight.x ? 1.0 : 0.0 ;
            float rate = (cuH-StartEndHeight.x)/(StartEndHeight.y - StartEndHeight.x);
            float tValue = smoothstep(MinMaxFactor.x + rate*(MinMaxFactor.y-MinMaxFactor.x), MinMaxFactor.y , value);
            return tValue*intensity;          
        }
        // 优化版三平面映射 - 带平滑权重，无接缝，输入参数与基础版一致
        float TriPlanarMappingSmooth(float3 normalWS, float3 posWS, float _TexScale = 1.0, float2 _TexOffset = float2(0,0))
        {
            // 1. 归一化法线
            normalWS = normalize(normalWS);
            // 2. 计算平滑权重：先取绝对值，再用smoothstep过渡，最后归一化（核心：消除平面接缝）
            float3 weights = abs(normalWS);
            weights = smoothstep(0.0, 1.0, weights); // 平滑权重过渡，避免硬边
            weights = weights / (weights.x + weights.y + weights.z + 1e-6); // 归一化权重和为1
        
            // 3. 生成三个平面的UV（Unity纹理原点在左下角，Y轴翻转需取负，根据需求可选）
            float2 uvXY = posWS.xy * _TexScale + _TexOffset;
            float2 uvXZ = float2(posWS.x, -posWS.z) * _TexScale + _TexOffset; // Y轴翻转
            float2 uvYZ = float2(posWS.y, -posWS.z) * _TexScale + _TexOffset; // Y轴翻转
        
            // 4. 采样三个平面的纹理（可加mipmap采样优化，如tex2Dlod）
            float colXY = SAMPLE_TEXTURE2D(_Cloud2Tex,sampler_Cloud2Tex,uvXY).r;
            float colXZ = SAMPLE_TEXTURE2D(_Cloud2Tex,sampler_Cloud2Tex,uvXZ).r;
            float colYZ = SAMPLE_TEXTURE2D(_Cloud2Tex,sampler_Cloud2Tex,uvYZ).r;
        
            // 5. 权重混合最终颜色
            float finalCol = weights.x * colYZ + weights.y * colXZ + weights.z * colXY;
        
            return finalCol;
        }

        Varyings vert(Attributes v)
        {
            Varyings o;
            o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
            o.uv = v.uv;
            o.screenPos = ComputeScreenPos(o.positionCS);
            return o;
        }
        // 这个版本假设n与z轴不平行，否则会有数值问题
        float3 DirectionFromZenithAzimuthSimple(float3 n, float theta, float phi)
        {
            n = normalize(n);

            // 默认使用z轴作为参考
            float3 t = float3(0, 0, 1);

            // 如果n接近z轴，使用x轴
            t = (abs(dot(n, t)) > 0.999) ? float3(1, 0, 0) : t;

            // 构建局部坐标系
            float3 e_x = normalize(t - dot(t, n) * n);
            float3 e_y = cross(n, e_x);

            float sinTheta = sin(theta);
            float cosTheta = cos(theta);

            return sinTheta * cos(phi) * e_x + sinTheta * sin(phi) * e_y + cosTheta * n;
        }
        float4 frag(Varyings i) : SV_Target
        {
            // 参数改写区域
            //_AtmosphereHeight += -12.0;




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
            newPlanetCenter = float3(0,0,0);
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




            // ========================== LUT 03 ===============================
            // 其实这两个变量就是 theta天顶角 与 phi方位角 的映射，因此求出他就可以求出方向
            float3 c2p = newPlanetCenter - ro;//摄像机到星球中心
            float c2pLen = length(c2p);
            float d = 0.1 * 2.5 + 20.0;
            //d = screenUV.x * 23;
            //d = screenUV.x *15.0 + 10.0;
            //d = screenUV.x *20.0 + 10.0;
            d = screenUV.x * _AtmosphereHeight + _PlanetRadius;
            d = screenUV.x * _AtmosphereHeight/4.0 + _PlanetRadius;
            //d = length((ro + rd *(inter.x+(inter.y-inter.x)*0.5)) - newPlanetCenter);
            float lingbian = sqrt(pow(c2pLen,2.0)-pow(d,2.0));
            float cosTheta = lingbian / c2pLen; // 邻边/斜边
            float theta = acos(cosTheta);

            float3 sphereSurface = ro + rd * inter.x;
            float phi = atan2(sphereSurface.x,-sphereSurface.y) + 1.0*PI;
            phi = screenUV.y*PI + 1.0*PI;
            //phi = 1.5*PI + PI;
            

            float3 ll = DirectionFromZenithAzimuthSimple(normalize(c2p),theta,phi);
            float2 hitT = raySphereIntersect(ro,ll.yxz,newPlanetCenter,planetR+atmosH);
            float3 hitPos = ro + ll.yxz * hitT.x;
            float interactLen = hitT.y - hitT.x; // 计算的位置的视线深度
            float2 hitTP = raySphereIntersect(ro,ll.yxz,newPlanetCenter,planetR);
            //interactLen *= step(hitTP.x,0.0);
            float3 xianZhongDian = hitPos + rd*0.5*interactLen;
            float gao = length(xianZhongDian - newPlanetCenter);

            // length((yuandian + t * direction) - planetCenter)=planetRadius

            float uvLen = length(screenUV*2.0-1.0);

            //return float4(step(hitTP.x,0.0)*float3(1,1,1),1);
            // =============================== 大气层参数 ===================================
            atmosData data;
            data.ro = rayStart + 0.0*0.5*(rayLen2/_NumSamples)*blueN*rd; // 根据蓝噪波随机增加采样距离
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

            // 重构
            
            //data.ro = hitPos;
            //data.rd = ll.yxz;
            //data.rayLength = interactLen;// 气体距离
            //data.sunDir = normalize(float3(0,1,0));// 光方向
            //data.rd = rd;
            //return float4(d*float3(1,1,1),1);

            float3 scatter = mAtomsScattering(data);
            //scatter = pow(scatter,2.2);
            // ========================== 计算太阳形状 ================================
            float Sun = 2.0*step(0.9998,dot(rd,_SunDirection)) + 1.0;
            scatter *= Sun;
            // ========================= 远处的天空调成黑色 =============================
            originalColor.xyz *= step(yvzhi,0.001);

            // ========================== 合成颜色 ==================================
            float3 finalCol = _Brightness * _SunColor * scatter*step(0.0,rayLen) + originalColor;
            finalCol = (originalColor / (originalColor + scatter*50.0*step(0.0,rayLen)))*originalColor + scatter*1.0;

            //return float4(finalCol,1.0);
            // =========================== LUT 01 ===============================
            
            float3 AtmosBake = SAMPLE_TEXTURE2D(_AtmosBake,sampler_AtmosBake,screenUV.xy);

            // 逆运算，改为求d值时的变化
            // d2 = x2 + y2，但此时其实x与y相同，所以,d2 = 2x2 ,d=根号(2)*x , x = d/根号(2)
            // 同时我们假设x、y都在第一象限
            // 我们需要先算出xy的比值，假设xy仅在第一和第四象限
            // 坐标系转换
            //float daxis = (length( (data.ro + data.rd * data.rayLength * 0.5) - data.planetCenter) - data.planetRadius ) / data.atmosHeight;
            float daxis = (length( (data.ro + data.rd * (inter.y - inter.x) * 0.5) - data.planetCenter) - data.planetRadius ) / data.atmosHeight;
            float haxis = 0.5 + 0.5 * dot(data.sunDir,normalize(inter.x*data.rd + ro - data.planetCenter));
            //float2 intermin = raySphereIntersect(ro,rd,newPlanetCenter,planetR+2);
            float dhmask = step(0,inter.x) * step(inter2.x,0);
            // 屏幕正方形uv变换系数,从屏幕UV到自定义
            float hTransf = haxis/screenUV.y;
            float dTransf = daxis/length(screenUV.xy - 0.5);
            // 因此我们需要从d与h两个变量变换到屏幕uv，
            float2 cesParam = float2(0.5,0.7);
            float2 cesParam2SUV = float2( 0.5 / dTransf , 0.7/hTransf );


            float2 cuv = screenUV*2.0 - 1.0;


            // 我们用这个映射h
            float maph = atan2(cuv.x,cuv.y)/(2.0*PI);
            maph = 0.9; // 这里时测试值
            maph = screenUV.y;
            // 所以我们可以得到 cuv.x与cuv.y的比值
            float xyRatio = tan(maph*2.0*PI);
            // 我们得到了xy的比值就可以求d对应的屏幕uv的位置了
            float mapd2 = pow(cuv.x,2.0) + pow(cuv.y,2.0);
            mapd2 = pow(cuv.x,2.0) + pow(cuv.x / xyRatio,2.0);
            // 0.855 0.96 经过测试的合理范围
            mapd2 = pow(0.96,2.0); 
            mapd2 = pow((screenUV.x-0.855),2.0); 
            // 即pow(c,2) = pow(x,2) + pow(x/b,2)
            // 可以转换为x关于d的表达式
            float x = (sqrt(mapd2) * xyRatio) / sqrt(pow(xyRatio,2.0)+1);
            x = cuv.y > 0 ? x:-x; // 修正符号
            float y = x / xyRatio;
            float2 uv = abs(float2(x,y))*0.5 + 0.5;

            float disSurf = length(ro-data.planetCenter)<= data.planetRadius+data.atmosHeight ? 0.0:inter.x;
            float xiangao = (length((ro + rd*disSurf + rd*data.rayLength*0.5)-data.planetCenter)-data.planetRadius)/data.atmosHeight*1.0;
            float guangAngle = dot(normalize(sphereSurface-data.planetCenter),data.sunDir);
            guangAngle = length(ro-data.planetCenter)<= data.planetRadius+data.atmosHeight ?  dot(normalize(ro-data.planetCenter),data.sunDir) : guangAngle;
            guangAngle = guangAngle*0.5 + 0.5;
            float2 AtmosUV = float2(saturate(xiangao+0.0),guangAngle);
            
            float3 cesLUT = SAMPLE_TEXTURE2D(_AtmosBake,sampler_AtmosBake,AtmosUV);

            //return float4(xiangao/20*float3(1,1,1),1);
            //return float4(cesLUT*step(0.0,inter.x)*2.0,1);
            //return float4(AtmosBake*2.0,1);
            //return float4(AtmosUV.y*float3(1,1,1),1.0);

            //return float4(ll.yxz*float3(1,1,1),1);

            /*
            // 云部分
            // 初始值
            float cloudDis = inter.x>0 && inter.y>0 && inter.y>inter.x ? inter.x : inter.y ;
            float3 cloudSurPos = ro + rd*cloudDis;
            float3 cloudSurNor = normalize(cloudSurPos - newPlanetCenter);

            // 循环参数
            float accDens;
            float cloudCol;
            float stepSize = rayLen2/16;
            float3 p = rayStart + 0.5*(rayLen2/16)*blueN*rd;;
            
            float yy;

            for(int l =0;l<8;l++)
            {
                float ch = length(p - newPlanetCenter) - planetR;
                float3 nn = normalize(p - newPlanetCenter);
                float cn = TriPlanarMappingSmooth(nn,p,0.1);
                float tcn = TransformCloudDens(float2(0.2,0.7),float2(0.0,1.0),cn,ch);
                

                // 计算光学深度
                //float2 inter = raySphereIntersect(p,_SunDirection,newPlanetCenter,planetR + atmosH);
                // 也是跟上面一样，计算纯大气层气体厚度
                //float rayLen = inter.x>0 && inter.y>0 && inter.y>inter.x ? (inter.y-inter.x) : inter.y; 
                //float lds = rayLen / 8;
                float lds = 0.05;
                float sunCloudExt = 0.0;
                float3 cup = p;
                
                for (int o=0;o<8;o++)
                {
                    float lch  = length(cup - newPlanetCenter) - planetR;
                    float3 lnn = normalize(cup - newPlanetCenter);
                    float lcn = TriPlanarMappingSmooth(lnn,cup,0.1);
                    float ltcn = TransformCloudDens(float2(0.2,0.7),float2(0.0,1.0),lcn,lch);
                
                    sunCloudExt += ltcn*lds;
                    cup += lds*_SunDirection;
                }
                
                float transm = exp(-(accDens + sunCloudExt)*5);
                yy += (accDens + sunCloudExt);
                float scatterCloud = tcn * stepSize * transm;
                cloudCol += scatterCloud;

                accDens += tcn*stepSize;
                p += stepSize*rd;
            }
            */

            //return float4((cloudCol+finalCol)*float3(1,1,1),0.0);
            return float4(pow(finalCol,1.0/2.2)*float3(1,1,1),1.0);

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