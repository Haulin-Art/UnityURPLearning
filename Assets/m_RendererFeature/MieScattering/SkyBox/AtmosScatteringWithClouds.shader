Shader "Custom/AtmosScatteringWithClouds"
{
    Properties
    {
        [Header(Atmosphere Parameters)]
        _TotalScale ("整体缩放", Float) = 1
        _PlanetRadius ("行星半径", Float) = 6371000
        _AtmosphereHeight ("大气层厚度", Float) = 100000
        _Altitude ("海拔(km)", Float) = 0.0

        [Header(Atmosphere Density)]
        _RayleighScaleHeight ("瑞利散射高度", Float) = 8000
        _MieScaleHeight ("米氏散射高度", Float) = 1200
        _OzoneScaleHeight ("臭氧层高度", Float) = 25000
        _OzoneCenterHeight ("臭氧层中心高度", Float) = 25000
        _AtmosIntensity ("大气密度", Range(0.0, 3.0)) = 1.0

        [Header(Scattering Coefficients)]
        _ScatterScale ("散射强度(X:Rayleigh Y:Mie)", Vector) = (1, 1, 1, 1)
        _RayleighScattering ("瑞利散射系数", Vector) = (0.0000058, 0.0000135, 0.0000331, 0)
        _MieScattering ("米氏散射系数", Float) = 0.0000021
        _MieExtinction ("米氏消光系数", Float) = 0.0000025
        _OzoneAbsorption ("臭氧吸收系数", Vector) = (0.00000065, 0.000001881, 0.000000085, 0)

        [Header(Phase Function)]
        _MieG ("Mie相位函数G值", Range(0, 0.99)) = 0.76
        _SunMieG ("太阳Mie相位函数G值", Range(0, 0.999)) = 0.98
        _SunMieIntensity ("太阳Mie散射强度", Range(0, 10)) = 1.0

        [Header(Sun)]
        _SunSize ("太阳大小", Range(0.00001, 0.005)) = 0.001
        _SunColor ("太阳颜色", Color) = (1, 1, 1, 1)
        _SunBrightness ("太阳亮度", Float) = 1.0

        [Header(Sampling)]
        _NumSamples ("视线采样数", Range(4, 64)) = 32
        _NumSamplesLight ("太阳光采样数", Range(1, 16)) = 8


        [Header(Volumetric Clouds)]
        [Toggle(_VOLUMETRIC_CLOUDS)] _EnableClouds ("启用体积云", Float) = 0
        _CloudBottomHeight ("云层底高度(km)", Float) = 2.0
        _CloudTopHeight ("云层顶高度(km)", Float) = 4.0
        _CloudDensityScale ("云密度缩放", Range(0, 2)) = 1.0
        _CloudSamples ("云采样数", Range(4, 64)) = 16
        _CloudLightSamples ("云光照采样数", Range(1, 8)) = 4

        [Header(Cloud Noise)]
        _CloudNoiseScale ("云噪波缩放", Float) = 1000.0
        _CloudNoiseOctaves ("噪波叠加层数", Range(1, 8)) = 4
        _CloudNoiseSpeed ("云移动速度", Float) = 1.0

        [Header(Cloud Appearance)]
        _CloudColor ("云颜色", Color) = (1, 1, 1, 1)
        _CloudBrightness ("云亮度", Float) = 1.0
        _CloudAbsorption ("云吸收系数", Range(0, 2)) = 0.5

        [Header(Debug)]
        [Enum(Normal,0, RayLength,1, OpticalDepth,2, Transmittance,3, ScatterOnly,4, SunOnly,5, CloudRegion,6, CloudNoise,7, CloudDensity,8, CloudOnly,9, CloudAndAtmos,10)] 
        _DebugMode ("Debug模式", Float) = 0
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "Background"
            "RenderType" = "Background"
            "PreviewType" = "Skybox"
            "IgnoreProjector" = "True"
        }
        
        LOD 100
        Cull Off
        ZWrite Off
        ZTest LEqual
        Blend One Zero

        Pass
        {
            Name "AtmosScatteringSkybox"

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #pragma shader_feature _VOLUMETRIC_CLOUDS

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 vertex : POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 vertex : SV_POSITION;
                float3 viewDir : TEXCOORD0;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            CBUFFER_START(UnityPerMaterial)
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

                float _SunSize;
                float3 _SunColor;
                float _SunBrightness;
                
                int _NumSamples;
                int _NumSamplesLight;
                float _DebugMode;

                // Cloud parameters
                float _CloudBottomHeight;
                float _CloudTopHeight;
                float _CloudDensityScale;
                int _CloudSamples;
                int _CloudLightSamples;
                float _CloudNoiseScale;
                int _CloudNoiseOctaves;
                float _CloudNoiseSpeed;
                float4 _CloudColor;
                float _CloudBrightness;
                float _CloudAbsorption;
            CBUFFER_END

            // 瑞利散射系数 (单位: 1/m)
            static const float3 kBetaR = float3(5.8e-6, 13.5e-6, 33.1e-6);
            
            // 米氏散射系数 (单位: 1/m)
            static const float3 kBetaM = float3(21e-6, 21e-6, 21e-6);
            
            // 臭氧吸收系数 (单位: 1/m)
            static const float3 kOzone = float3(0.65e-6, 1.881e-6, 0.085e-6);

            // 射线与球体相交检测
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
            float MiePhase(float cosTheta, float g)
            {
                float g2 = g * g;
                float numerator = 1.0 - g2;
                float denominator = pow(1.0 + g2 - 2.0 * g * cosTheta, 1.5);
                return numerator / (4.0 * PI * denominator);
            }

            // 计算光学深度（Optical Depth）
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

            // 修复的Perlin噪波（真正的梯度噪声）
            float3 mod289(float3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
            float4 mod289(float4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
            float4 permute(float4 x) { return mod289(((x * 34.0) + 1.0) * x); }
            float4 taylorInvSqrt(float4 r) { return 1.79284291400159 - 0.85373472095314 * r; }

            float snoise(float3 v)
            {
                const float2 C = float2(1.0 / 6.0, 1.0 / 3.0);
                const float4 D = float4(0.0, 0.5, 1.0, 2.0);

                // 第一层网格
                float3 i  = floor(v + dot(v, C.yyy));
                float3 x0 = v - i + dot(i, C.xxx);

                // 其他网格
                float3 g = step(x0.yzx, x0.xyz);
                float3 l = 1.0 - g;
                float3 i1 = min(g.xyz, l.zxy);
                float3 i2 = max(g.xyz, l.zxy);

                float3 x1 = x0 - i1 + C.xxx;
                float3 x2 = x0 - i2 + C.yyy;
                float3 x3 = x0 - D.yyy;

                // 排列
                i = mod289(i);
                float4 p = permute(permute(permute(
                            i.z + float4(0.0, i1.z, i2.z, 1.0))
                          + i.y + float4(0.0, i1.y, i2.y, 1.0))
                          + i.x + float4(0.0, i1.x, i2.x, 1.0));

                // 梯度值: 7x7点在网格上 (49个方向)
                float n_ = 0.142857142857; // 1/7
                float3 ns = n_ * D.wyz - D.xzx;

                float4 j = p - 49.0 * floor(p * ns.z * ns.z);

                float4 x_ = floor(j * ns.z);
                float4 y_ = floor(j - 7.0 * x_);

                float4 x = x_ * ns.x + ns.yyyy;
                float4 y = y_ * ns.x + ns.yyyy;
                float4 h = 1.0 - abs(x) - abs(y);

                float4 b0 = float4(x.xy, y.xy);
                float4 b1 = float4(x.zw, y.zw);

                float4 s0 = floor(b0) * 2.0 + 1.0;
                float4 s1 = floor(b1) * 2.0 + 1.0;
                float4 sh = -step(h, 0.0);

                float4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
                float4 a1 = b1.xzyw + s1.xzyw * sh.zzww;

                float3 p0 = float3(a0.xy, h.x);
                float3 p1 = float3(a0.zw, h.y);
                float3 p2 = float3(a1.xy, h.z);
                float3 p3 = float3(a1.zw, h.w);

                // 归一化
                float4 norm = taylorInvSqrt(float4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
                p0 *= norm.x;
                p1 *= norm.y;
                p2 *= norm.z;
                p3 *= norm.w;

                // 混合贡献
                float4 m = max(0.5 - float4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
                m = m * m;
                m = m * m;

                // 梯度值
                float4 px = float4(dot(x0, p0), dot(x1, p1), dot(x2, p2), dot(x3, p3));
                return 130.0 * dot(m, px);
            }

            // 改进的FBM函数
            float FBM(float3 p, int octaves, float lacunarity = 2.0, float gain = 0.5)
            {
                float value = 0.0;
                float amplitude = 1.0;
                float frequency = 1.0;
                
                for (int i = 0; i < octaves; i++)
                {
                    float noise = snoise(p * frequency) * 0.5 + 0.5;
                    value += amplitude * noise;
                    amplitude *= gain;
                    frequency *= lacunarity;
                }
                
                return value;
            }

            // 改进的云密度函数
            float GetCloudDensity(float3 p, float3 planetCenter, float cloudBottomRadius, float cloudTopRadius)
            {
                float dist = length(p - planetCenter);
                
                if (dist < cloudBottomRadius || dist > cloudTopRadius)
                    return 0.0;
                
                // 高度梯度
                float heightFraction = (dist - cloudBottomRadius) / (cloudTopRadius - cloudBottomRadius);
                
                // 改进的高度分布
                float baseGradient = smoothstep(0.0, 0.2, heightFraction) * (1.0 - smoothstep(0.7, 1.0, heightFraction));
                
                // 云顶的卷云效果
                float cirrus = smoothstep(0.7, 0.9, heightFraction);
                
                // 3层噪声
                float3 wind = float3(0, 0, _Time.y * _CloudNoiseSpeed);
                float scale = 0.0001 * _CloudNoiseScale; // 调整缩放
                
                // 基础形状
                float shape = FBM(p * scale + wind, _CloudNoiseOctaves, 2.0, 0.5);
                
                // 细节
                float detail = FBM(p * scale * 3.0 + wind * 1.5, 3, 2.5, 0.3) * 0.3;
                
                // 合并
                float noise = shape + detail;
                
                // 密度阈值
                noise = saturate((noise - 0.2) * 2.0); // 调整阈值
                
                // 应用高度梯度
                float density = noise * baseGradient * (1.0 - cirrus * 0.3) * _CloudDensityScale;
                
                return saturate(density);
            }

            // 计算云的光照（考虑自阴影）
            float GetCloudLighting(float3 p, float3 planetCenter, float3 sunDir, float cloudBottomRadius, float cloudTopRadius)
            {
                // 光线步进计算云内自阴影
                float lightEnergy = 1.0;
                float stepSize = (cloudTopRadius - cloudBottomRadius) * 0.05;
                float3 currentPos = p;
                
                for (int i = 0; i < 4; i++) // 减少采样数以提高性能
                {
                    currentPos += sunDir * stepSize;
                    
                    // 检查是否仍在云层内
                    float dist = length(currentPos - planetCenter);
                    if (dist < cloudBottomRadius || dist > cloudTopRadius)
                        break;
                    
                    float cloudDensity = GetCloudDensity(currentPos, planetCenter, cloudBottomRadius, cloudTopRadius);
                    lightEnergy *= exp(-cloudDensity * _CloudAbsorption * stepSize);
                    
                    if (lightEnergy < 0.01)
                        break;
                }
                
                return lightEnergy;
            }

            // 核心大气散射计算（包含体积云）
            float3 ComputeAtmosScattering(float3 rayOrigin, float3 rayDir, float rayLength,
                                          float3 planetCenter, float planetRadius, float atmosHeight,
                                          float3 sunDir, int numSamples, int numLightSamples,
                                          out float3 outViewTransmittance)
            {
                float ds = rayLength / (float)numSamples;
                float3 p = rayOrigin + rayDir * ds * 0.5;
                
                float3 accumRayleigh = float3(0, 0, 0);
                float3 accumMie = float3(0, 0, 0);
                
                // 云相关变量
                float3 accumCloud = float3(0, 0, 0);
                float cloudTransmittance = 1.0;
                
                float3 totalRayleighDepth = float3(0, 0, 0);
                float3 totalMieDepth = float3(0, 0, 0);
                float3 totalOzoneDepth = float3(0, 0, 0);

                float3 betaR = _ScatterScale.x * kBetaR;
                float3 betaM = _ScatterScale.y * kBetaM;
                float mieExtinction = _MieExtinction > 0 ? _MieExtinction : 1.1 * _ScatterScale.y * 21e-6;

                // 计算相位函数
                float cosTheta = dot(rayDir, sunDir);
                float phaseR = RayleighPhase(cosTheta);
                float phaseM = MiePhase(cosTheta, _MieG);

                // 计算云层半径
                float cloudBottomRadius = planetRadius + _CloudBottomHeight * 1000.0 / _TotalScale;
                float cloudTopRadius = planetRadius + _CloudTopHeight * 1000.0 / _TotalScale;

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
                    float2 planetInter = RaySphereIntersect(p, sunDir, planetCenter, planetRadius);
                    bool sunBlocked = false;
                    if (planetInter.x > 0.0)
                    {
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
                        
                        // 累积散射光
                        accumRayleigh += rayleighDensity * ds * betaR * phaseR * transmittance;
                        accumMie += mieDensity * ds * betaM * phaseM * transmittance;
                    }

                    // 计算体积云
                    #ifdef _VOLUMETRIC_CLOUDS
                    float cloudDensity = GetCloudDensity(p, planetCenter, cloudBottomRadius, cloudTopRadius);
                    if (cloudDensity > 0.0)
                    {
                        // 计算云的消光
                        float cloudExtinction = cloudDensity * _CloudAbsorption;
                        float cloudStepTransmittance = exp(-cloudExtinction * ds);
                        
                        // 累积云的消光
                        cloudTransmittance *= cloudStepTransmittance;
                        
                        // 计算云的光照（考虑自阴影）
                        float lighting = GetCloudLighting(p, planetCenter, sunDir, cloudBottomRadius, cloudTopRadius);
                        
                        // 计算太阳光衰减
                        float sunAttenuation = 1.0;
                        float2 sunPlanetInter = RaySphereIntersect(p, sunDir, planetCenter, planetRadius);
                        if (sunPlanetInter.x > 0.0)
                            sunAttenuation = 0.2; // 被地球遮挡
                        
                        // 累积云的散射
                        float3 cloudScatter = _CloudColor.rgb * cloudDensity * lighting * sunAttenuation * ds * 0.1;
                        accumCloud += cloudScatter;
                    }
                    #endif

                    // 更新累积光学深度
                    totalRayleighDepth.x += rayleighDensity * ds;
                    totalMieDepth.y += mieDensity * ds;
                    totalOzoneDepth.z += ozoneDensity * ds;
                    
                    p += rayDir * ds;
                }

                // 计算视线方向的透射率
                float3 viewTau = betaR * totalRayleighDepth.x 
                               + mieExtinction * totalMieDepth.y 
                               + kOzone * totalOzoneDepth.z;
                outViewTransmittance = exp(-viewTau);
                
                // 应用云的透射率
                #ifdef _VOLUMETRIC_CLOUDS
                outViewTransmittance *= cloudTransmittance;
                #endif
                
                return accumRayleigh + accumMie + accumCloud * _CloudBrightness;
            }

            Varyings vert(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                
                o.vertex = TransformObjectToHClip(v.vertex.xyz);
                
                // 获取世界空间视图方向
                float3 worldPos = TransformObjectToWorld(v.vertex.xyz);
                o.viewDir = worldPos - _WorldSpaceCameraPos;
                
                return o;
            }

            float4 frag(Varyings i) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                
                // 获取主光源方向（太阳方向）
                Light mainLight = GetMainLight();
                float3 sunDir = mainLight.direction;
                
                // 相机位置作为射线起点
                float3 ro = _WorldSpaceCameraPos;
                
                // 视线方向
                float3 rd = normalize(i.viewDir);
                
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

                // 确保射线长度有效
                rayLen = max(rayLen, 0.0);

                // 计算云层半径
                float cloudBottomRadius = planetR + _CloudBottomHeight * 1000.0 / scaleFactor;
                float cloudTopRadius = planetR + _CloudTopHeight * 1000.0 / scaleFactor;

                // Debug模式：云层区域
                if (_DebugMode == 6.0)
                {
                    // 光线步进检测云层区域
                    float3 p = rayStart;
                    float ds = rayLen / 100.0;
                    bool inCloudRegion = false;
                    for (int i = 0; i < 100; i++)
                    {
                        float dist = length(p - planetCenter);
                        if (dist >= cloudBottomRadius && dist <= cloudTopRadius)
                        {
                            inCloudRegion = true;
                            break;
                        }
                        p += rd * ds;
                    }
                    return float4(inCloudRegion ? 1 : 0, 0, 0, 1);
                }

                // Debug模式：云噪波
                if (_DebugMode == 7.0)
                {
                    // 使用固定的世界坐标，避免相机移动过快
                    float3 worldPos = ro + rd * 10000.0;  // 固定距离
                    float3 noisePos = worldPos * 0.001;  // 调整缩放
                    
                    // 3层噪波
                    float noise1 = snoise(noisePos) * 0.5;
                    float noise2 = snoise(noisePos * 2.0 + float3(0, _Time.y * 0.1, 0)) * 0.25;
                    float noise3 = snoise(noisePos * 4.0 + float3(0, _Time.y * 0.05, 0)) * 0.125;
                    
                    float noise = 0.5 + 0.5 * (noise1 + noise2 + noise3);
                    noise = saturate(noise * 1.2 - 0.1);
                    
                    return float4(noise, noise, noise, 1);
                }

                // Debug模式：云密度
                if (_DebugMode == 8.0)
                {
                    // 光线步进计算云密度 - 使用更多采样点
                    float totalDensity = 0.0;
                    int sampleCount = 0;
                    float3 p = rayStart;
                    float ds = rayLen / 100.0; // 更小的步长
                    for (int i = 0; i < 100; i++)
                    {
                        float cloudDensity = GetCloudDensity(p, planetCenter, cloudBottomRadius, cloudTopRadius);
                        if (cloudDensity > 0.01)
                        {
                            totalDensity += cloudDensity;
                            sampleCount++;
                        }
                        p += rd * ds;
                    }
                    float avgDensity = sampleCount > 0 ? totalDensity / (float)sampleCount : 0.0;
                    return float4(avgDensity, avgDensity, avgDensity, 1);
                }

                // 计算大气散射
                float3 viewTransmittance;
                float3 scatter = ComputeAtmosScattering(
                    rayStart, rd, rayLen,
                    planetCenter, planetR, atmosH,
                    sunDir, _NumSamples, _NumSamplesLight,
                    viewTransmittance
                );

                // 计算云（无论是否启用_VOLUMETRIC_CLOUDS，都计算以支持Debug模式）
                float3 cloudColor = float3(0, 0, 0);
                float cloudTransmittance = 1.0;
                
                // 计算与云层的交点
                float2 cloudInter = RaySphereIntersect(rayStart, rd, planetCenter, cloudTopRadius);
                if (cloudInter.y > 0.0)
                {
                    float enterDist = max(0.0, cloudInter.x);
                    float exitDist = cloudInter.y;
                    
                    // 检查是否与云层底部相交
                    float2 bottomInter = RaySphereIntersect(rayStart, rd, planetCenter, cloudBottomRadius);
                    if (bottomInter.x > 0.0)
                    {
                        exitDist = min(exitDist, bottomInter.x);
                    }
                    
                    float cloudLen = exitDist - enterDist;
                    if (cloudLen > 0.0)
                    {
                        int samples = max(_CloudSamples, 8);
                        float ds = cloudLen / samples;
                        float3 p = rayStart + rd * (enterDist + ds * 0.5);
                        
                        for (int i = 0; i < samples; i++)
                        {
                            float density = GetCloudDensity(p, planetCenter, cloudBottomRadius, cloudTopRadius);
                            
                            if (density > 0.0)
                            {
                                // 计算云内自阴影
                                float lighting = GetCloudLighting(p, planetCenter, sunDir, cloudBottomRadius, cloudTopRadius);
                                
                                // 计算太阳光衰减
                                float sunAttenuation = 1.0;
                                float2 sunPlanetInter = RaySphereIntersect(p, sunDir, planetCenter, planetR);
                                if (sunPlanetInter.x > 0.0)
                                    sunAttenuation = 0.2;
                                
                                // 体积散射
                                float3 inScatter = _CloudColor.rgb * density * lighting * sunAttenuation;
                                cloudColor += inScatter * cloudTransmittance * ds;
                                
                                // 消光
                                float extinction = density * _CloudAbsorption;
                                cloudTransmittance *= exp(-extinction * ds);
                            }
                            
                            p += rd * ds;
                        }
                        
                        cloudColor *= _CloudBrightness;
                    }
                }
                
                // Debug模式：CloudAndAtmos
                if (_DebugMode == 10.0)
                {
                    // 大气散射 + 云
                    float3 finalColor = scatter + cloudColor;
                    return float4(finalColor, 1.0);
                }

                // 额外的太阳Mie散射
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

                // 太阳圆盘
                float sunArea = 1.0 - smoothstep(1.0 - _SunSize + 0.0001, 1.0 - _SunSize, dot(rd, sunDir));
                float3 sun = _SunBrightness * _SunColor * sunArea * smoothstep(-0.05,0.0,rd.y);

                // 正常的最终颜色计算
                float3 finalCol = _SunBrightness * _SunColor * (scatter + sunScatter);
                
                // 如果启用了体积云，添加云
                #ifdef _VOLUMETRIC_CLOUDS
                finalCol = finalCol * cloudTransmittance + cloudColor;
                #endif
                
                finalCol += sun * finalCol;

                // Debug模式
                if (_DebugMode == 1.0)
                {
                    // RayLength: 显示射线长度
                    float normalizedLen = rayLen / (atmosH * 2.0);
                    return float4(normalizedLen.rrr, 1.0);
                }
                else if (_DebugMode == 2.0)
                {
                    // OpticalDepth: 显示光学深度
                    float3 debugOpticalDepth = ComputeOpticalDepth(rayStart, rd, rayLen, 4, planetCenter, planetR);
                    return float4(debugOpticalDepth * 0.001, 1.0);
                }
                else if (_DebugMode == 3.0)
                {
                    // Transmittance: 显示透射率
                    return float4(viewTransmittance, 1.0);
                }
                else if (_DebugMode == 4.0)
                {
                    // ScatterOnly: 仅显示散射光
                    return float4(max(scatter, 0.0), 1.0);
                }
                else if (_DebugMode == 5.0)
                {
                    // SunOnly: 仅显示太阳
                    return float4(sun * sunVisible, 1.0);
                }
                else if (_DebugMode == 9.0)
                {
                    // 计算与云层的交点
                    float2 topInter = RaySphereIntersect(rayStart, rd, planetCenter, cloudTopRadius);
                    if (topInter.y < 0.0)
                        return float4(0, 0, 0, 1);
                    
                    float enterDist = max(0.0, topInter.x);
                    float exitDist = topInter.y;
                    
                    // 检查是否与云层底部相交
                    float2 bottomInter = RaySphereIntersect(rayStart, rd, planetCenter, cloudBottomRadius);
                    if (bottomInter.x > 0.0)
                    {
                        exitDist = min(exitDist, bottomInter.x);
                    }
                    
                    float cloudLen = exitDist - enterDist;
                    if (cloudLen <= 0.0)
                        return float4(0, 0, 0, 1);
                    
                    // 光线步进
                    int samples = max(_CloudSamples, 16);
                    float ds = cloudLen / samples;
                    float3 p = rayStart + rd * (enterDist + ds * 0.5);
                    
                    float3 totalLight = float3(0, 0, 0);
                    float transmittance = 1.0;
                    
                    for (int i = 0; i < samples; i++)
                    {
                        float density = GetCloudDensity(p, planetCenter, cloudBottomRadius, cloudTopRadius);
                        
                        if (density > 0.0)
                        {
                            // 计算云内自阴影
                            float lighting = GetCloudLighting(p, planetCenter, sunDir, cloudBottomRadius, cloudTopRadius);
                            
                            // 计算太阳光衰减
                            float sunAttenuation = 1.0;
                            float2 sunPlanetInter = RaySphereIntersect(p, sunDir, planetCenter, planetR);
                            if (sunPlanetInter.x > 0.0)
                                sunAttenuation = 0.2; // 被地球遮挡
                            
                            // 体积散射
                            float3 inScatter = _CloudColor.rgb * density * lighting * sunAttenuation;
                            totalLight += inScatter * transmittance * ds;
                            
                            // 消光
                            float extinction = density * _CloudAbsorption;
                            transmittance *= exp(-extinction * ds);
                        }
                        
                        p += rd * ds;
                    }
                    
                    return float4(totalLight * _CloudBrightness, 1.0);
                }

                // 星星
                float azi_scale = 60.0;
                float azimuth = (atan2(rd.z,rd.x)+PI)/(2.0*PI);
                float j_azimuth = floor(azimuth*azi_scale)/azi_scale;
                float zen_scale = 20.0;
                float zenithAngle = acos(rd.y);
                float j_zenithAngle = floor(zenithAngle*zen_scale)/zen_scale;
                float2 j_uv = float2(j_azimuth,j_zenithAngle);
                float2 n_uv = float2(azimuth*azi_scale-j_azimuth*azi_scale,zenithAngle*zen_scale-j_zenithAngle*zen_scale)-0.5;
                float noise1 = frac(sin(dot(j_uv, float2(12.9898, 78.233))) * 43758.5453);
                float noise2 = frac(sin(dot(j_uv, float2(92.9898, 35.233))) * 43758.5453);
                float2 offset = float2(noise1,noise2)*2.0-1.0;
                float star = step(length(n_uv+offset*0.5),noise1*0.015 + 0.01);
                
                return float4(max(finalCol, star*0.15), 1.0);
            }
            ENDHLSL
        }
    }
    FallBack Off
}