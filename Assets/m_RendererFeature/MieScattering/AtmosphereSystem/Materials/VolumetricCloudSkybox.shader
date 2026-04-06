Shader "Custom/VolumetricCloudSkybox"
{
    Properties
    {
        // ========== 基础参数 ==========
        _PlanetRadius("星球半径(m)", Float) = 6360000.0
        _CloudBottomRadius("云层底部半径(m)", Float) = 6360600.0
        _CloudTopRadius("云层顶部半径(m)", Float) = 6360700.0
        _CloudLayerCenter("云层中心(m)", Vector) = (0, 0, 0)
        
        [Space(10)]
        // ========== 光线步进参数 ==========
        _SampleCountMax("最大采样数", Int) = 128
        _SampleCountMin("最小采样数", Int) = 16
        _InvDistanceToSampleCountMax("距离到采样数倒数", Float) = 0.00001
        _TracingMaxDistance("最大追踪距离(m)", Float) = 100000.0
        _TracingStartDistance("起始追踪距离(m)", Float) = 0.0
        
        [Space(10)]
        // ========== 云密度参数 ==========
        _CloudDensity3DTex("云密度噪声图3D", 3D) = "white" {}
        _CloudDensityTex("云密度噪声图", 2D) = "white" {}
        _CloudDensityScale("密度缩放", Float) = 0.001
        _CloudDensityOffset("密度偏移", Float) = 0.0
        _CloudDetailTex("云细节噪声图", 2D) = "white" {}
        _DetailScale("细节缩放", Float) = 0.01
        _DetailStrength("细节强度", Range(0, 1)) = 0.3
        _CloudDensityThreshold("云密度阈值", Range(0, 1)) = 0.1
        
        [Space(10)]
        // ========== 光照参数 ==========
        _SunColor("太阳颜色", Color) = (1, 0.95, 0.9, 1)
        _SunIntensity("太阳强度", Float) = 1.0
        _SunDirection("太阳方向", Vector) = (0, 1, 0, 0)
        _SkyLightColor("天空光颜色", Color) = (0.5, 0.6, 0.8, 1)
        _SkyLightIntensity("天空光强度", Float) = 0.5
        _GroundAlbedo("地面反照率", Color) = (0.3, 0.3, 0.3, 1)
        
        [Space(10)]
        // ========== 散射参数 ==========
        _ExtinctionCoefficient("消光系数", Float) = 0.1
        _ScatteringCoefficient("散射系数", Float) = 0.8
        _Albedo("云反照率", Color) = (0.9, 0.9, 0.9, 1)
        _PhaseG("相位函数G参数", Range(-0.999, 0.999)) = 0.7
        _PhaseG2("相位函数G2参数", Range(-0.999, 0.999)) = 0.3
        _PhaseBlend("相位混合", Range(0, 1)) = 0.5
        
        [Space(10)]
        // ========== 多重散射参数 ==========
        _MsScattFactor("多重散射衰减因子", Range(0, 1)) = 0.5
        _MsExtinFactor("多重消光衰减因子", Range(0, 1)) = 0.3
        _MsPhaseFactor("多重相位衰减因子", Range(0, 1)) = 0.7
        _MaxScatteringOrder("最大散射阶数", Int) = 2
        
        [Space(10)]
        // ========== 外观参数 ==========
        _CloudColor("云基础颜色", Color) = (1, 1, 1, 1)
        _CloudEmission("云自发光", Color) = (0, 0, 0, 1)
        _HeightGradient("高度渐变", 2D) = "white" {}
        _WindDirection("风向", Vector) = (1, 0, 0, 0)
        _WindSpeed("风速", Float) = 1.0
        _TimeScale("时间缩放", Float) = 1.0
        
        [Space(10)]
        // ========== 性能优化参数 ==========
        _UseConservativeDensity("使用保守密度", Float) = 1.0
        _EmptySpaceSkipThreshold("空域跳过阈值", Float) = 0.001
        _LODDistance("LOD距离", Float) = 100000.0
        _LODFactor("LOD因子", Float) = 0.5
        
        [Space(10)]
        // ========== 调试参数 ==========
        _DebugMode("调试模式", Int) = 0
        _DebugStep("调试步进", Float) = 0.0
    }
    
    SubShader
    {
        Tags { "Queue"="Background" "RenderType"="Background" "PreviewType"="Skybox" }
        Cull Off
        ZWrite Off
        
        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.5
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            
            // ========== 常量定义 ==========
            #define PI 3.14159265359
            #define MAX_FLOAT 3.402823466e+38
            
            // ========== 属性变量 ==========
            float _PlanetRadius;
            float _CloudBottomRadius;
            float _CloudTopRadius;
            float3 _CloudLayerCenter;
            
            int _SampleCountMax;
            int _SampleCountMin;
            float _InvDistanceToSampleCountMax;
            float _TracingMaxDistance;
            float _TracingStartDistance;
            
            TEXTURE3D(_CloudDensity3DTex);
            SAMPLER(sampler_CloudDensity3DTex);

            TEXTURE2D(_CloudDensityTex);
            SAMPLER(sampler_CloudDensityTex);
            float4 _CloudDensityTex_ST;
            float _CloudDensityScale;
            float _CloudDensityOffset;
            TEXTURE2D(_CloudDetailTex);
            SAMPLER(sampler_CloudDetailTex);
            float _DetailScale;
            float _DetailStrength;
            float _CloudDensityThreshold;
            
            float4 _SunColor;
            float _SunIntensity;
            float3 _SunDirection;
            float4 _SkyLightColor;
            float _SkyLightIntensity;
            float4 _GroundAlbedo;
            
            float _ExtinctionCoefficient;
            float _ScatteringCoefficient;
            float4 _Albedo;
            float _PhaseG;
            float _PhaseG2;
            float _PhaseBlend;
            
            float _MsScattFactor;
            float _MsExtinFactor;
            float _MsPhaseFactor;
            int _MaxScatteringOrder;
            
            float4 _CloudColor;
            float4 _CloudEmission;
            TEXTURE2D(_HeightGradient);
            SAMPLER(sampler_HeightGradient);
            float3 _WindDirection;
            float _WindSpeed;
            float _TimeScale;
            
            float _UseConservativeDensity;
            float _EmptySpaceSkipThreshold;
            float _LODDistance;
            float _LODFactor;
            
            int _DebugMode;
            float _DebugStep;
            
            // ========== 结构体定义 ==========
            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };
            
            struct v2f
            {
                float4 vertex : SV_POSITION;
                float3 worldPos : TEXCOORD0;
                float3 viewDir : TEXCOORD1;
            };
            
            // 云层参数结构体（参考UE5的FCloudLayerParameters）
            struct CloudLayerParams
            {
                float3 CloudLayerCenter;    // 云层中心（米）
                float PlanetRadius;         // 星球半径（米）
                float BottomRadius;         // 底部半径（米）
                float TopRadius;            // 顶部半径（米）
                float ToNormAltitude;       // 到标准化高度的转换因子
                float LayerThickness;       // 云层厚度（米）
            };
            
            // 参与介质相位上下文（参考UE5的ParticipatingMediaPhaseContext）
            struct ParticipatingMediaPhaseContext
            {
                float Phase0[8];  // 各阶散射的相位函数值
            };
            
            // 参与介质上下文（参考UE5的ParticipatingMediaContext）
            struct ParticipatingMediaContext
            {
                float3 Albedo;
                float ExtinctionCoefficient;
                float ScatteringCoefficient;
                float MsScattFactor;
                float MsExtinFactor;
                float3 AtmosphereTransmittanceToLight;
                float3 TransmittanceToView;
            };
            
            // ========== 辅助函数 ==========
            
            /**
             * 射线与球体求交（参考UE5的RayIntersectSphereSolution）
             * @param RayOrigin 射线起点（米）
             * @param RayDirection 射线方向（归一化）
             * @param Sphere 球体参数（xyz=中心，w=半径，单位米）
             * @param Solutions 输出交点距离（两个解，单位米）
             * @return 是否相交
             */
            bool RayIntersectSphereSolution(float3 RayOrigin, float3 RayDirection, float4 Sphere, inout float2 Solutions)
            {
                // 将射线起点转换到球体局部空间
                float3 LocalPosition = RayOrigin - Sphere.xyz;
                float LocalPositionSqr = dot(LocalPosition, LocalPosition);
                
                // 构建二次方程系数：at² + bt + c = 0
                float3 QuadraticCoef;
                QuadraticCoef.x = dot(RayDirection, RayDirection);  // a = D·D
                QuadraticCoef.y = 2.0 * dot(RayDirection, LocalPosition);  // b = 2D·(O-C)
                QuadraticCoef.z = LocalPositionSqr - Sphere.w * Sphere.w;  // c = (O-C)² - R²
                
                // 计算判别式
                float Discriminant = QuadraticCoef.y * QuadraticCoef.y - 4.0 * QuadraticCoef.x * QuadraticCoef.z;
                
                // 只有判别式非负时才相交
                if (Discriminant >= 0.0)
                {
                    float SqrtDiscriminant = sqrt(Discriminant);
                    // 求根公式：t = (-b ± √Δ) / 2a
                    Solutions = (-QuadraticCoef.y + float2(-1, 1) * SqrtDiscriminant) / (2.0 * QuadraticCoef.x);
                    return true;
                }
                
                return false;
            }
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
            /**
             * Henyey-Greenstein相位函数（参考UE5实现）
             * 描述米氏散射的角度分布
             * @param G 非对称参数，-1为完全后向散射，1为完全前向散射
             * @param CosTheta 入射光与出射光夹角的余弦值
             * @return 相位函数值
             */
            float HenyeyGreensteinPhase(float G, float CosTheta)
            {
                // 参考实现（非Schlick近似）
                // 参见《Physically Based Rendering》第11章
                float Numer = 1.0 - G * G;
                float Denom = 1.0 + G * G + 2.0 * G * CosTheta;
                return Numer / (4.0 * PI * Denom * sqrt(Denom));
            }
            
            /**
             * 采样相位函数（参考UE5的SamplePhaseFunction）
             * 支持两个HG函数的混合
             */
            float SamplePhaseFunction(float PhaseCosTheta, float PhaseG, float PhaseG2, float PhaseBlend)
            {
                // 限制参数范围避免数值问题
                PhaseG = clamp(PhaseG, -0.999, 0.999);
                PhaseG2 = clamp(PhaseG2, -0.999, 0.999);
                PhaseBlend = clamp(PhaseBlend, 0.0, 1.0);
                
                // 计算两个HG函数的值（注意：WorldDir是"进入"方向，需要取反cosTheta）
                float MiePhaseValueLight0 = HenyeyGreensteinPhase(PhaseG, -PhaseCosTheta);
                float MiePhaseValueLight1 = HenyeyGreensteinPhase(PhaseG2, -PhaseCosTheta);
                
                // 混合两个相位函数
                const float Phase = MiePhaseValueLight0 + PhaseBlend * (MiePhaseValueLight1 - MiePhaseValueLight0);
                return Phase;
            }
            
            /**
             * 设置参与介质相位上下文（参考UE5的SetupParticipatingMediaPhaseContext）
             * 计算各阶散射的相位函数值
             */
            ParticipatingMediaPhaseContext SetupParticipatingMediaPhaseContext(float BasePhase0, float BasePhase1, float MsPhaseFactor)
            {
                ParticipatingMediaPhaseContext PMPC;
                PMPC.Phase0[0] = BasePhase0;
                
                // 各向同性相位函数：1/(4π)
                float IsotropicPhaseValue = 1.0 / (4.0 * PI);
                
                // 计算高阶散射的相位函数（逐渐趋向各向同性）
                [unroll]
                for (int ms = 1; ms < 8; ++ms)
                {
                    if (ms < _MaxScatteringOrder)
                    {
                        PMPC.Phase0[ms] = lerp(IsotropicPhaseValue, PMPC.Phase0[0], MsPhaseFactor);
                        MsPhaseFactor *= MsPhaseFactor;  // 指数衰减
                    }
                    else
                    {
                        PMPC.Phase0[ms] = 0.0;
                    }
                }
                
                return PMPC;
            }
            
            /**
             * 获取云层参数（参考UE5的GetCloudLayerParams）
             * 统一单位转换
             */
            CloudLayerParams GetCloudLayerParams()
            {
                CloudLayerParams Params;
                Params.CloudLayerCenter = _CloudLayerCenter; // 云层中心（米）
                Params.PlanetRadius = _PlanetRadius;         // 星球半径（米）
                Params.BottomRadius = _CloudBottomRadius;    // 底部半径（米）
                Params.TopRadius = _CloudTopRadius;          // 顶部半径（米）
                Params.LayerThickness = Params.TopRadius - Params.BottomRadius; // 云层厚度
                Params.ToNormAltitude = 1.0 / Params.LayerThickness; // 到标准化高度的转换因子
                return Params;
            }
            
            /**
             * 计算云密度（核心函数）
             * 结合基础噪声和细节噪声
             * @param WorldPos 世界位置（米）
             * @param CloudParams 云层参数
             * @return 密度值[0,1]
             */
            float CalculateCloudDensity(float3 WorldPos, CloudLayerParams CloudParams)
            {
                // 计算相对于云层中心的高度
                float3 LocalPos = WorldPos - CloudParams.CloudLayerCenter;
                float Height = length(LocalPos) - CloudParams.BottomRadius;
                float NormHeight = Height * CloudParams.ToNormAltitude;
                
                // 高度裁剪：超出云层范围密度为0
                if (NormHeight <= 0.0 || NormHeight >= 1.0)
                    return 0.0;
                
                // 应用高度渐变
                float HeightFactor = SAMPLE_TEXTURE2D_LOD(_HeightGradient, sampler_HeightGradient, float2(NormHeight, 0.5), 0).r;
                
                // 计算UV坐标（考虑风动画）
                float3 WindOffset = _WindDirection * _WindSpeed * _Time.y * _TimeScale;
                
                // 使用3D纹理采样（避免平铺问题）
                // 缩放因子：将世界坐标映射到合适的纹理坐标范围
                // 例如，每1000米采样一次纹理
                float3 SamplePos = (WorldPos + WindOffset) * 0.001;  // 缩放因子，调整这个值控制云朵大小
                
                // 方法1：使用2D纹理采样（xz平面）
                // float2 BaseUV = SamplePos.xz * _CloudDensityScale;
                // float BaseDensity = SAMPLE_TEXTURE2D_LOD(_CloudDensityTex, sampler_CloudDensityTex, BaseUV, 0).r;
                
                // 方法2：使用3D纹理采样（更好的体积感）
                float BaseDensity = SAMPLE_TEXTURE3D_LOD(_CloudDensity3DTex, sampler_CloudDensity3DTex, SamplePos, 0).r;
                
                // 采样细节噪声
                float2 DetailUV = SamplePos.xz * _DetailScale;
                float DetailNoise = SAMPLE_TEXTURE2D_LOD(_CloudDetailTex, sampler_CloudDetailTex, DetailUV, 0).r;
                
                // 混合基础噪声和细节噪声
                float CombinedDensity = BaseDensity + (DetailNoise - 0.5) * _DetailStrength;
                
                // 应用高度因子和参数调整
                float FinalDensity = CombinedDensity * HeightFactor * _CloudDensityScale + _CloudDensityOffset;
                
                // 应用密度阈值
                FinalDensity = smoothstep(_CloudDensityThreshold, 1.0, FinalDensity);
                
                // 保守密度优化：低于阈值时返回0
                if (_UseConservativeDensity > 0.5 && FinalDensity < _EmptySpaceSkipThreshold)
                    return 0.0;
                
                return saturate(FinalDensity);
            }
            
            /**
             * 计算大气透射率（简化版）
             * 真实实现需要预计算LUT，这里使用近似
             * @param WorldPos 世界位置（米）
             * @param LightDir 光源方向
             * @return 透射率[0,1]
             */
            float3 CalculateAtmosphereTransmittance(float3 WorldPos, float3 LightDir)
            {
                // 简化实现：基于高度和角度的指数衰减
                float Height = length(WorldPos) - _PlanetRadius;
                float NormHeight = saturate(Height / 10000.0);  // 10km大气高度
                
                // 光线穿过大气的距离（近似）
                float CosTheta = dot(normalize(WorldPos), LightDir);
                float OpticalDepth = exp(-NormHeight * (1.0 - CosTheta * 0.5));
                
                // 瑞利散射颜色（天空蓝色）
                float3 RayleighColor = float3(0.5, 0.6, 0.8);
                
                return lerp(RayleighColor, float3(1, 1, 1), OpticalDepth);
            }
            
            /**
             * 计算地面反射贡献
             * @param WorldPos 采样点位置（米）
             * @param LightDir 光源方向
             * @param ViewDir 视线方向
             * @return 地面反射光强
             */
            float3 CalculateGroundReflection(float3 WorldPos, float3 LightDir, float3 ViewDir)
            {
                // 计算到地面的距离
                float ToGroundDistance = length(WorldPos) - _PlanetRadius;
                if (ToGroundDistance > 0.0)
                    return float3(0, 0, 0);
                
                // 简化地面BRDF（朗伯漫反射）
                float3 GroundNormal = normalize(WorldPos);
                float NdotL = saturate(dot(GroundNormal, LightDir));
                
                // 地面反射光 = 太阳光 * 地面反照率 * cosθ
                float3 GroundReflection = _SunColor.rgb * _SunIntensity * _GroundAlbedo.rgb * NdotL;
                
                // 考虑大气衰减
                float3 Transmittance = CalculateAtmosphereTransmittance(WorldPos, -GroundNormal);
                
                return GroundReflection * Transmittance;
            }
            
            // ========== 顶点着色器 ==========
            v2f vert(appdata v)
            {
                v2f o;
                o.vertex = TransformObjectToHClip(v.vertex.xyz);
                
                // 计算世界位置（天空盒使用摄像机位置作为原点）
                o.worldPos = TransformObjectToWorld(v.vertex.xyz);
                
                // 计算视线方向（从摄像机指向天空盒表面）
                o.viewDir = normalize(o.worldPos - _WorldSpaceCameraPos);
                
                return o;
            }
            
            // ========== 片段着色器 ==========
            float4 frag(v2f i) : SV_Target
            {
                // 调试模式：直接显示某种颜色
                if (_DebugMode == 1) return float4(1, 0, 0, 1);
                if (_DebugMode == 2) return float4(0, 1, 0, 1);
                if (_DebugMode == 3) return float4(0, 0, 1, 1);
                
                // ===== 1. 初始化参数 =====
                // 摄像机位置（米）
                float3 RayWorldOrigin = _WorldSpaceCameraPos;
                // 视线方向（从摄像机指向像素）
                float3 RayDir = normalize(i.viewDir);
                
                // 获取主光源方向（太阳方向）
                Light mainLight = GetMainLight();
                float3 sunDir = mainLight.direction;
                float3 sunColor = mainLight.color;
                _SunDirection = normalize(sunDir);
                _SunColor.rgb = sunColor;
                
                // 云层参数
                CloudLayerParams CloudParams = GetCloudLayerParams();
                
                // ===== 2. 计算光线与云层的交点（Tmin/Tmax）=====
                // 参考UE5的MainCommon算法
                float TMin = -MAX_FLOAT;
                float TMax = -MAX_FLOAT;
                float2 tTop2, tBottom2;
                
                // 顶部球体求交
                bool bHitTop = RayIntersectSphereSolution(
                    RayWorldOrigin, 
                    -RayDir, 
                    float4(CloudParams.CloudLayerCenter, CloudParams.TopRadius), 
                    tTop2);
                
                //float2 inter = RaySphereIntersect(RayWorldOrigin, -RayDir, float3(0,-6360000,0), CloudParams.TopRadius);
                //float3 poss = (RayWorldOrigin + RayDir * inter.y)/_PlanetRadius;
                //return float4(float3(1,1,1)*RayDir,1.0);
                // 底部球体求交
                bool bHitBottom = RayIntersectSphereSolution(
                    RayWorldOrigin, 
                    -RayDir, 
                    float4(CloudParams.CloudLayerCenter, CloudParams.BottomRadius), 
                    tBottom2);
                
                // 根据相交情况确定步进范围
                if (bHitTop && bHitBottom)
                {
                    // 与两个球体都相交
                    float TempTop = all(tTop2 > 0.0) ? min(tTop2.x, tTop2.y) : max(tTop2.x, tTop2.y);
                    float TempBottom = all(tBottom2 > 0.0) ? min(tBottom2.x, tBottom2.y) : max(tBottom2.x, tBottom2.y);
                    
                    if (all(tBottom2 > 0.0))
                    {
                        // 能看到云层底部，使用摄像机或最高顶部交点
                        TempTop = max(0.0, min(tTop2.x, tTop2.y));
                    }
                    
                    TMin = min(TempBottom, TempTop);
                    TMax = max(TempBottom, TempTop);
                }
                else if (bHitTop)
                {
                    // 只与顶部相交（在大气层中看向外太空）
                    TMin = tTop2.x;
                    TMax = tTop2.y;
                }
                else
                {
                    // 无相交（在外太空或无云）
                    return float4(0, 0, 0, 1);
                }
                
                // 限制最小值为0（从摄像机开始）
                TMin = max(0.0, TMin);
                TMax = max(0.0, TMax);
                
                // 限制最大追踪距离
                float MarchingDistance = min(_TracingMaxDistance, TMax - TMin);
                TMax = TMin + MarchingDistance;
                
                // 应用起始距离
                TMin = max(TMin, _TracingStartDistance);
                TMax = max(TMin, TMax);
                
                // ===== 3. 光线步进准备 =====
                // 计算步进次数（基于距离动态调整）
                float Distance = TMax - TMin;
                
                float3 pos = (RayWorldOrigin + RayDir * TMin)/_PlanetRadius;
                float cloudDens = SAMPLE_TEXTURE3D(_CloudDensity3DTex,sampler_CloudDensity3DTex,pos).r;
                //return float4(float3(1,1,1)*cloudDens,1.0);

                // 调试：显示距离
                if (_DebugMode == 4) return float4(Distance / 100000.0, Distance / 100000.0, Distance / 100000.0, 1.0);
                
                uint IStepCount = max(_SampleCountMin, _SampleCountMax * saturate(Distance * _InvDistanceToSampleCountMax));
                // IStepCount = _SampleCountMax; // 固定采样数
                float StepCount = float(IStepCount);
                float StepT = Distance / StepCount;  // 步长（米）
                
                // 调试：显示步进
                if (_DebugMode == 5) return float4(StepT / 100.0, StepT / 100.0, StepT / 100.0, 1.0);
                
                // 初始化累加变量
                float3 TotalLuminance = float3(0, 0, 0);
                float TotalTransmittance = 1.0;
                
                // 计算相位函数（视线与太阳方向的夹角）
                float PhaseCosTheta = dot(_SunDirection, RayDir);
                float BasePhase = SamplePhaseFunction(PhaseCosTheta, _PhaseG, _PhaseG2, _PhaseBlend);
                
                // 设置多重散射相位上下文
                ParticipatingMediaPhaseContext PMPC = SetupParticipatingMediaPhaseContext(BasePhase, 0.0, _MsPhaseFactor);
                
                float totalDens = 0.0;
                float stepCount = 0.0;
                
                // ===== 4. 光线步进循环 =====
                for (uint step = 0; step < IStepCount; ++step)
                {
                    // 计算当前采样点位置
                    float t = TMin + StepT * (float(step) + 0.5);  // 中点采样
                    float3 SampleWorldPos = RayWorldOrigin + RayDir * t;
                    
                    // 调试：显示特定步进
                    if (_DebugMode == 6 && step == _DebugStep) 
                        return float4(1, 0, 0, 1);
                    
                    // ===== 5. 计算云密度 =====
                    float Density = CalculateCloudDensity(SampleWorldPos, CloudParams);
                    totalDens += Density;
                    stepCount += 1.0;
                    
                    // 空域跳过优化：密度为0时跳过计算
                    if (Density <= 0.0)
                        continue;
                    
                    // ===== 6. 计算光学参数 =====
                    // 消光系数 = 基础系数 × 密度
                    float Extinction = _ExtinctionCoefficient * Density;
                    // 散射系数 = 消光系数 × 反照率
                    float Scattering = Extinction * _Albedo.r;
                    
                    // ===== 7. 计算光照贡献 =====
                    // 7.1 直接光照（太阳光）
                    float3 SunLight = _SunColor.rgb * _SunIntensity;
                    
                    // 计算大气透射率（从采样点到太阳）
                    float3 AtmosphereTransmittance = CalculateAtmosphereTransmittance(SampleWorldPos, _SunDirection);
                    
                    // 计算阴影（向太阳方向步进累加消光）
                    float ShadowDensity = 0.0;
                    const uint ShadowSteps = 8;
                    float ShadowStepSize = 10.0;  // 米
                    
                    for (uint shadowStep = 0; shadowStep < ShadowSteps; ++shadowStep)
                    {
                        float3 ShadowPos = SampleWorldPos + _SunDirection * ShadowStepSize * float(shadowStep);
                        float ShadowSampleDensity = CalculateCloudDensity(ShadowPos, CloudParams);
                        ShadowDensity += ShadowSampleDensity * _ExtinctionCoefficient * ShadowStepSize;
                    }
                    
                    float ShadowTransmittance = exp(-ShadowDensity);
                    
                    // 7.2 间接光照（天空光）
                    float3 SkyLight = _SkyLightColor.rgb * _SkyLightIntensity;
                    
                    // 7.3 地面反射
                    float3 GroundLight = CalculateGroundReflection(SampleWorldPos, _SunDirection, RayDir);
                    
                    // ===== 8. 多重散射计算 =====
                    float3 ScatteredLight = float3(0, 0, 0);
                    
                    // 单次散射（直接光照）
                    float3 SingleScatter = SunLight * AtmosphereTransmittance * ShadowTransmittance * PMPC.Phase0[0];
                    
                    // 多重散射（近似）
                    if (_MaxScatteringOrder > 1)
                    {
                        // 二次散射（简化：使用各向同性近似）
                        float3 SecondScatter = (SunLight + SkyLight + GroundLight) * 0.5 * PMPC.Phase0[1];
                        ScatteredLight += SecondScatter * _MsScattFactor;
                    }
                    
                    if (_MaxScatteringOrder > 2)
                    {
                        // 三次散射（进一步衰减）
                        float3 ThirdScatter = (SkyLight + GroundLight) * 0.3 * PMPC.Phase0[2];
                        ScatteredLight += ThirdScatter * _MsScattFactor * _MsScattFactor;
                    }
                    
                    // 合并所有散射贡献
                    float3 TotalScattered = (SingleScatter + ScatteredLight) * Scattering;
                    
                    // ===== 9. Beer-Lambert定律计算透射率 =====
                    // 当前步的透射率：T = exp(-σ_t * dt)
                    float StepTransmittance = exp(-Extinction * StepT);
                    
                    // ===== 10. 累加光照贡献 =====
                    // 当前采样点的贡献 = 散射光 × 到摄像机的透射率
                    float3 SampleContribution = TotalScattered * TotalTransmittance;
                    TotalLuminance += SampleContribution;
                    
                    // 更新到摄像机的透射率
                    TotalTransmittance *= StepTransmittance;
                    
                    // 俄罗斯轮盘赌提前终止（性能优化）
                    if (TotalTransmittance < 0.01)
                        break;
                }
                
                // 调试模式
                if (_DebugMode == 7)
                {
                    // 显示平均密度
                    float avgDensity = (stepCount > 0) ? totalDens / stepCount : 0.0;
                    return float4(avgDensity, avgDensity, avgDensity, 1.0);
                }
                else if (_DebugMode == 8)
                {
                    // 显示总密度
                    return float4(totalDens / 10.0, totalDens / 10.0, totalDens / 10.0, 1.0);
                }
                else if (_DebugMode == 9)
                {
                    // 显示步进次数
                    return float4(stepCount / float(_SampleCountMax), stepCount / float(_SampleCountMax), stepCount / float(_SampleCountMax), 1.0);
                }
                
                // ===== 11. 最终颜色合成 =====
                // 应用云颜色和自发光
                float3 FinalColor = TotalLuminance * _CloudColor.rgb + _CloudEmission.rgb;
                
                // 确保颜色在合理范围内
                FinalColor = clamp(FinalColor, 0.0, 10.0);
                
                // 与背景混合（透射率作为Alpha）
                // 注意：天空盒通常需要不透明，这里透射率仅用于内部计算
                return float4(float3(1,1,1)*totalDens,1);
                return float4(FinalColor, 1.0);
            }
            ENDHLSL
        }
    }
    
    FallBack "Skybox/Cubemap"
    CustomEditor "VolumetricCloudShaderEditor"
}