Shader "RendererFeature/Atmosphere/CompsiteCloudAndAtoms"
{
    Properties
    {
        [Header(Environment)]
        [Space(10)]
        _EnvPanoramic ("环境反射全景贴图",2D ) = "white" {}
        _PanoramicRotation ("全景贴图旋转角度", Range(0.0, 1.0)) = 0.0
        _SunSize ("太阳大小", Range(0.00001,0.001)) = 0.0002


        [Space(15)]
        // ========== 基础参数 ==========
        [Header(BasicParameters)]
        [Space(10)]
        _PlanetRadius("行星半径(m)", Float) = 6371000.0
        _CloudLayerCenter("云层中心", Vector) = (0, 0, 0)
        _CloudBaseHeight("云底高度(m)", Float) = 2000.0
        _CloudThickness("云厚度(m)", Float) = 1000.0
        _TotalScale("整体缩放", Float) = 1.0
        _CloudAlpha ("云层透明度", Range(0.0, 1.0)) = 0.5
        
        [Space(15)]
        // ========== 光线步进参数 ==========
        [Header(RayMarchingParameters)]
        [Space(10)]
        _NumViewSamples("视线采样数", Range(4, 128)) = 32
        _NumLightSamples("光照采样数", Range(1, 16)) = 8
        _StepSizeMultiplier("步长乘数", Range(0.1, 5.0)) = 1.0
        _BlueNoise("蓝噪声纹理", 2D) = "black" {}
        
        [Space(15)]
        // ========== 云密度参数 ==========
        [Header(CloudDensityParameters)]
        [Space(10)]
        _2Dor3DCloudTexMix("2D/3D云纹理混合", Range(0, 1)) = 1.0
        _CloudTex2D("云纹理(2D)", 2D) = "white" {}
        _CloudTex("云纹理(3D)", 3D) = "white" {}
        _CloudTiling ("云纹理(3D)平铺", Float) = 1.0
        _CloudAxisScale("云纹理(3D)轴缩放", Vector) = (1, 1.0, 1)
        _CloudDetailTex("云纹理(3D)细节纹理", 3D) = "white" {}
        _CloudDetailTiling ("云纹理(3D)细节纹理平铺", Float) = 1.0
        [Space(10)]
        _CloudDensityScale("密度缩放", Float) = 0.001
        _CloudDensityThreshold("密度阈值", Range(0, 1)) = 0.1
        _CloudEdgeSharpness("边缘锐度", Range(0, 1)) = 0.5
        _CloudDensityMultiplier("密度乘数", Range(0.01, 10.0)) = 1.0
        [Space(10)]
        _CloudDetailMix("云细节混合强度", Range(0, 1)) = 1.0
        _MixEdgeFieldFactor("边缘范围定义因子", Range(0, 1)) = 0.5
        _OnlyOnEdgeErosion ("仅在边缘进行侵蚀", Range(0, 1)) = 0.0
        _CloudDetailThreshold("云细节阈值", Range(0, 1)) = 0.5
        _CloudDetailSharpness("云细节锐度", Range(0, 1)) = 0.5

        [Space(15)] // 这部分通过c#端的曲线调整
        _CloudHeightGradient("高度渐变纹理", 2D) = "white" {}
        
        [Space(15)]
        // ========== 光照参数 ==========
        [Header(LightingParameters)]
        [Space(10)]
        _SunBrightness("太阳亮度", Float) = 1.0
        _SunColor("太阳颜色", Color) = (1, 0.95, 0.9, 1)
        _SunDirection("太阳方向", Vector) = (0, 1, 0, 0)
        
        [Space(15)]
        // ========== 散射参数 ==========
        [Header(ScatteringParameters)]
        [Space(10)]
        _ExtinctionCoefficient("消光系数", Range(0.1, 10.0)) = 0.1
        _ScatteringCoefficient("散射系数", Float) = 0.8
        _Albedo("云反照率", Color) = (0.9, 0.9, 0.9, 1)
        _PhaseG("相位函数G参数", Range(-0.999, 0.999)) = 0.8
        _PhaseG2("相位函数G2参数", Range(-0.999, 0.999)) = 0.3
        _PhaseBlend("相位混合", Range(0, 1)) = 0.5
        
        [Space(15)]
        // ========== 多重散射参数 ==========
        [Header(MultipleScatteringParameters)]
        [Space(10)]
        _MsScattFactor("多重散射衰减因子", Range(0, 1)) = 0.5
        _MsExtinFactor("多重消光衰减因子", Range(0, 1)) = 0.3
        _MsPhaseFactor("多重相位衰减因子", Range(0, 1)) = 0.7
        _MaxScatteringOrder("最大散射阶数", Int) = 2
        
        [Space(15)]
        // ========== 外观参数 ==========
        [Header(AppearanceParameters)]
        [Space(10)]
        _CloudColor("云基础颜色", Color) = (1, 1, 1, 1)
        _CloudEmission("云自发光", Color) = (0, 0, 0, 1)
        _WindDirection("风向", Vector) = (1, 0, 0, 0)
        _WindSpeed("风速", Float) = 1.0
        _TimeScale("时间缩放", Float) = 1.0
        
        [Space(15)]
        // ========== 调试参数 ==========
        [Header(DebugParameters)]
        [Space(10)]
        _DebugMode("调试模式", Int) = 0
        _ShowNormals("显示法线", Range(0, 1)) = 0
        _ShowDensity("显示密度", Range(0, 1)) = 0
    
        [Space(15)]
        // ========== 夜间参数 ==========
        [Header(NightParameters)]
        [Space(10)]
        _NightBrightness("夜间亮度", Float) = 0.5
        _NightColor("夜间天顶颜色", Color) = (0.5, 0.5, 0.5, 1)
        _NightSkyLineColor("夜间天空线颜色", Color) = (0.5, 0.5, 0.5, 1)

        [Space(15)]
        _CES ("测试用",Range(0,1)) = 0.0
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
            Name "VolumetricCloudSkybox"
            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile_instancing

            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            
            // ========== 常量定义 ==========
            //#define PI 3.14159265359
            #define MAX_FLOAT 3.402823466e+38
            #define IS_SKYBOX // 是否为天空盒
            //#define USE_TYNDALL_EFFECT
            #define USE_STARS_EFFECT
            
            // ========== 纹理定义 ==========
            TEXTURE2D(_EnvPanoramic);
            SAMPLER(sampler_EnvPanoramic);
            TEXTURE3D(_CloudTex);
            SAMPLER(sampler_CloudTex);
            TEXTURE3D(_CloudDetailTex);
            SAMPLER(sampler_CloudDetailTex);
            TEXTURE2D(_CloudTex2D);
            SAMPLER(sampler_CloudTex2D);
            TEXTURE2D(_BlueNoise);
            SAMPLER(sampler_BlueNoise);
            TEXTURE2D(_CloudHeightGradient);
            SAMPLER(sampler_CloudHeightGradient);
            
            // 来自 Renderer Feature 的体积云渲染的纹理
            TEXTURE2D(_AtmosRFCloudTex);SAMPLER(sampler_AtmosRFCloudTex);

            // ========== 属性变量 ==========
            CBUFFER_START(UnityPerMaterial)
                float _PanoramicRotation;
                float _CloudAlpha;
                float _SunSize;

                float _PlanetRadius;
                float3 _CloudLayerCenter;
                float _CloudBaseHeight;
                float _CloudThickness;
                float _TotalScale;
                
                float _NumViewSamples;
                float _NumLightSamples;
                float _StepSizeMultiplier;
                
                float _2Dor3DCloudTexMix;
                float _CloudTiling;
                float3 _CloudAxisScale;
                float _CloudDetailTiling;
                float _CloudDensityScale;
                float _CloudDensityThreshold;
                float _CloudEdgeSharpness;
                float _CloudDensityMultiplier;

                float _CloudDetailMix;
                float _MixEdgeFieldFactor;
                float _OnlyOnEdgeErosion;
                float _CloudDetailSharpness;
                float _CloudDetailThreshold;
                
                float _SunBrightness;
                float4 _SunColor;
                float3 _SunDirection;
                
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
                float3 _WindDirection;
                float _WindSpeed;
                float _TimeScale;
                
                int _DebugMode;
                float _ShowNormals;
                float _ShowDensity;

                float _NightBrightness;
                float3 _NightColor;
                float3 _NightSkyLineColor;

                float _CES;

                float4x4 _InvViewProj; 
            CBUFFER_END
            
            // ========== 结构体定义 ==========
            struct Attributes
            {
                float4 vertex : POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            
            struct Varyings
            {
                float4 vertex : SV_POSITION;
                float3 worldPos : TEXCOORD0;
                float3 viewDir : TEXCOORD1;
                float4 screenUV : TEXCOORD2;
                UNITY_VERTEX_OUTPUT_STEREO
            };
            
            // 云层参数结构体
            struct CloudLayerParams
            {
                float3 Center;          // 云层中心
                float PlanetRadius;     // 行星半径
                float InnerRadius;      // 内层半径（云底）
                float OuterRadius;      // 外层半径（云顶）
                float Thickness;        // 云层厚度
                float ToNormHeight;     // 到标准化高度的转换因子
            };
            
            // 颜色转亮度
            float GetLuminance(float3 color)
            {
                // 方法1：标准感知亮度（人眼对绿色最敏感）
                return dot(color, float3(0.2126, 0.7152, 0.0722));

                // 方法2：简化版
                // return dot(color, float3(0.299, 0.587, 0.114));

                // 方法3：平均值
                // return (color.r + color.g + color.b) * 0.3333;
            }


            // ======================== 全景图相关 ========================
            // 绕 Y 轴旋转函数
            float3 RotateAroundY(float3 position, float angle)
            {
                float sinAngle, cosAngle;
                sincos(angle, sinAngle, cosAngle);

                float3 rotatedPos;
                rotatedPos.x = position.x * cosAngle - position.z * sinAngle;
                rotatedPos.z = position.x * sinAngle + position.z * cosAngle;
                rotatedPos.y = position.y;

                return rotatedPos;
            }
            // 全景图UV转换
            float2 DirToPanoramicUV(float3 dir)
            {
                dir = RotateAroundY(dir,6.0*_PanoramicRotation);
                //dir = normalize(dir);
                float phi = atan2(dir.z, dir.x);
                float theta = acos(dir.y);
                
                float rotationRad = _PanoramicRotation * 3.14159265 / 180.0;
                phi += rotationRad;
                
                float2 uv;
                uv.x = phi / (2.0 * 3.14159265) + 0.5;
                uv.y = theta / 3.14159265;
                
                return uv;
            }


            // ======================== 云相关 ========================
            // 相位函数上下文
            struct PhaseContext
            {
                float Phase[8];  // 各阶散射的相位函数值
            };
            
            // ========== 辅助函数 ==========
            
            /**
             * Henyey-Greenstein相位函数
             * 用于计算云的前向散射
             */
            float HenyeyGreensteinPhase(float G, float CosTheta)
            {
                float Numer = 1.0 - G * G;
                float Denom = 1.0 + G * G - 2.0 * G * CosTheta;
                return Numer / (4.0 * PI * sqrt(Denom) * Denom);
            }
            
            /**
             * 混合相位函数
             * 支持两个HG函数的混合
             */
            float BlendPhaseFunction(float CosTheta, float G1, float G2, float Blend)
            {
                float Phase1 = HenyeyGreensteinPhase(G1, -CosTheta);
                float Phase2 = HenyeyGreensteinPhase(G2, -CosTheta);
                return lerp(Phase1, Phase2, Blend);
            }
            
            /**
             * 初始化相位上下文
             * 计算各阶散射的相位函数
             */
            PhaseContext SetupPhaseContext(float BasePhase, float MsPhaseFactor, int MaxOrder)
            {
                PhaseContext ctx;
                ctx.Phase[0] = BasePhase;
                
                // 各向同性相位：1/(4π)
                float IsotropicPhase = 1.0 / (4.0 * PI);
                
                for (int i = 1; i < 8; i++)
                {
                    if (i < MaxOrder)
                    {
                        ctx.Phase[i] = lerp(IsotropicPhase, ctx.Phase[0], MsPhaseFactor);
                        MsPhaseFactor *= MsPhaseFactor;  // 指数衰减
                    }
                    else
                    {
                        ctx.Phase[i] = 0.0;
                    }
                }
                
                return ctx;
            }
            
            /**
             * 射线与球体求交
             * 返回最近和最远交点距离
             */
            float2 RaySphereIntersect(float3 RayOrigin, float3 RayDir, float3 SphereCenter, float SphereRadius)
            {
                float3 oc = RayOrigin - SphereCenter;
                float b = dot(oc, RayDir);
                float c = dot(oc, oc) - SphereRadius * SphereRadius;
                float discriminant = b * b - c;
                
                if (discriminant < 0.0)
                    return float2(-1.0, -1.0);
                
                float sqrtDisc = sqrt(discriminant);
                return float2(-b - sqrtDisc, -b + sqrtDisc);
            }
            
            /**
             * 获取云层参数
             */
            CloudLayerParams GetCloudLayerParams()
            {
                CloudLayerParams params;
                params.Center = _CloudLayerCenter;
                params.PlanetRadius = _PlanetRadius;
                params.InnerRadius = _PlanetRadius + _CloudBaseHeight;
                params.OuterRadius = params.InnerRadius + _CloudThickness;
                params.Thickness = params.OuterRadius - params.InnerRadius;
                params.ToNormHeight = 1.0 / params.Thickness;
                return params;
            }
            
            /**
             * 计算云密度（核心函数）
             * 结合3D噪声纹理和高度渐变
             */
            float CalculateCloudDensity(float3 WorldPos,float sunHeight , CloudLayerParams CloudParams)
            {
                // 计算相对高度
                float Height = length(WorldPos - CloudParams.Center) - CloudParams.InnerRadius;
                float NormHeight = Height * CloudParams.ToNormHeight;
                
                // 高度裁剪
                if (NormHeight < 0.0 || NormHeight > 1.0)
                    return 0.0;
                
                // 应用高度渐变
                float HeightFactor = SAMPLE_TEXTURE2D_LOD(_CloudHeightGradient, sampler_CloudHeightGradient, 
                                                        float2(NormHeight, 0.5), 0).r;

                // 风动画
                float3 WindOffset = _WindDirection * _WindSpeed * _Time.y * _TimeScale;
                
                // 采样3D噪声纹理
                // 缩放因子很重要：控制云朵的大小和平铺
                float3 TexCoord = (WorldPos + WindOffset*100 + float3(0,300*_Time.y,0)) * _CloudDensityScale;
                float3 TexCoord_detail = (WorldPos + WindOffset*100) * _CloudDensityScale;
                float4 Noise3D = SAMPLE_TEXTURE3D_LOD(_CloudTex, sampler_CloudTex, TexCoord.xzy*_CloudAxisScale/(20.0*_CloudTiling), 0);
                float4 Noise2D = SAMPLE_TEXTURE2D_LOD(_CloudTex2D, sampler_CloudTex2D, TexCoord.xz/20.0, 0);
                
                float4 NoiseDetail = SAMPLE_TEXTURE3D_LOD(_CloudDetailTex, sampler_CloudDetailTex, TexCoord_detail/(2.5*_CloudDetailTiling), 0);
                
                // 组合噪声通道
                // 使用大尺度和小尺度噪声组合
                float LargeScale = lerp(Noise3D.r, Noise3D.g * 1.5, 0.3);
                float FineDetail = lerp(Noise3D.b, Noise3D.a * 1.5, 0.3);
                
                // 组合密度
                float Density = LargeScale * lerp(0.4, 1.0, FineDetail) ;
                Density = Noise3D.r + Noise3D.g*0.5 + Noise3D.b*0.2  + Noise3D.a*0.1;
                Density /= 1.8;

                // 应用阈值和边缘锐化
                float Edge = max(_CloudEdgeSharpness, _CloudDensityThreshold + 0.001);
                float Edge2 = max(_MixEdgeFieldFactor , _CloudDensityThreshold + 0.001); // 用于定义侵蚀范围
                float erosion = smoothstep(_CloudDensityThreshold, Edge2, Density );
                Density = smoothstep(_CloudDensityThreshold, Edge, Density * HeightFactor );

                // 细节噪声
                float detailFactor = NoiseDetail.r * saturate(1.0 - NoiseDetail.b + 0.0);
                float detailEdge = max(_CloudDetailSharpness, _CloudDetailThreshold + 0.001);
                detailFactor = smoothstep(_CloudDetailThreshold, detailEdge, detailFactor);
                detailFactor = lerp(1.0, detailFactor, _CloudDetailMix);
                detailFactor = lerp(detailFactor,1.0, _OnlyOnEdgeErosion * erosion); // 仅在边缘进行侵蚀

                
                // 最终密度
                return Density * lerp(1.0,detailFactor,sunHeight) * sunHeight * _CloudDensityMultiplier ;//* HeightFactor ;//* NoiseDetail.r;
            }
            
            /**
             * 计算多重散射贡献
             * 参考UE5的实现
             */
            float3 CalculateMultipleScattering(float3 Density, float3 Transmittance, 
                                               PhaseContext PhaseCtx, float3 LightColor,
                                               float3 SkyLight, float MsFactor)
            {
                float3 TotalScatter = float3(0, 0, 0);
                
                // 单次散射
                float3 SingleScatter = Density * PhaseCtx.Phase[0] * LightColor;
                TotalScatter += SingleScatter;
                
                // 多重散射（近似）
                if (_MaxScatteringOrder > 1)
                {
                    float3 SecondScatter = (LightColor + SkyLight) * 0.5 * PhaseCtx.Phase[1];
                    TotalScatter += SecondScatter * MsFactor;
                }
                
                if (_MaxScatteringOrder > 2)
                {
                    float3 ThirdScatter = SkyLight * 0.3 * PhaseCtx.Phase[2];
                    TotalScatter += ThirdScatter * MsFactor * MsFactor;
                }
                
                return TotalScatter * Transmittance;
            }
            
            /**
             * 计算云阴影
             * 向太阳方向步进计算光学深度
             */
            float CalculateCloudShadow(float3 SamplePos, float3 LightDir, float sunHeight, CloudLayerParams CloudParams, 
                                       int NumSamples, float StepSize)
            {
                float OpticalDepth = 0.0;
                float3 CurrentPos = SamplePos;
                float baseStepSize = StepSize;
                
                for (int i = 0; i < NumSamples; i++)
                {
                    CurrentPos += LightDir * StepSize;
                    
                    // 计算当前点密度
                    float Density = CalculateCloudDensity(CurrentPos, sunHeight, CloudParams);
                    OpticalDepth += Density * StepSize;
                    
                    // 提前终止优化
                    if (OpticalDepth > 10.0)
                        break;
                    // 自适应步长
                    StepSize = lerp(baseStepSize*2.0, baseStepSize*0.05, Density);
                }
                
                return exp(-_ExtinctionCoefficient * OpticalDepth);
            }
            
            // 增强版星星生成函数
            // 输入：
            //   rd: 视线方向
            //   azi_scale: 方位角密度
            //   zen_scale: 天顶角密度
            //   star_size_min: 星星最小尺寸
            //   star_size_max: 星星最大尺寸
            //   offset_strength: 偏移强度
            //   star_threshold: 星星生成阈值 (0-1，越大星星越少)
            // 输出：0-1之间的星星亮度
            float GenerateStarsAdvanced(
                float3 rd, 
                float azi_scale, 
                float zen_scale,
                float star_size_min,
                float star_size_max,
                float offset_strength,
                float star_threshold
            )
            {
                //const float PI = 3.14159265359;
                
                // 计算方位角和天顶角
                float azimuth = (atan2(rd.z, rd.x) + PI) / (2.0 * PI);
                float j_azimuth = floor(azimuth * azi_scale) / azi_scale;
                
                float zenithAngle = acos(rd.y);
                float j_zenithAngle = floor(zenithAngle * zen_scale) / zen_scale;
                
                // 计算UV
                float2 j_uv = float2(j_azimuth, j_zenithAngle);
                float2 n_uv = float2(
                    azimuth * azi_scale - j_azimuth * azi_scale,
                    zenithAngle * zen_scale - j_zenithAngle * zen_scale
                ) - 0.5;
                
                // 生成多个随机数用于不同效果
                float noise1 = frac(sin(dot(j_uv, float2(12.9898, 78.233))) * 43758.5453);
                float noise2 = frac(sin(dot(j_uv, float2(92.9898, 35.233))) * 43758.5453);
                float noise3 = frac(sin(dot(j_uv, float2(37.123, 12.456))) * 43758.5453);
                
                // 只有超过阈值的区域生成星星
                if (noise3 > star_threshold)
                    return 0.0;
                
                // 使用随机数生成偏移
                float2 offset = float2(noise1, noise2) * 2.0 - 1.0;
                offset *= offset_strength;
                
                // 计算星星大小（基于噪声）
                float star_size = lerp(star_size_min, star_size_max, noise1);
                
                // 使用smoothstep实现柔和的星星边缘
                float distance_to_star = length(n_uv + offset);
                float star = 1.0 - smoothstep(star_size * 0.7, star_size, distance_to_star);
                
                return star;
            }

            // ========== 顶点着色器 ==========
            Varyings vert(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                
                o.vertex = TransformObjectToHClip(v.vertex.xyz);
                
                // 世界位置
                o.worldPos = TransformObjectToWorld(v.vertex.xyz);
                
                // 视线方向
                o.viewDir = normalize(o.worldPos - _WorldSpaceCameraPos);
                
                // 屏幕UV
                o.screenUV = ComputeScreenPos(o.vertex);
                
                return o;
            }
            
            // ========== 片段着色器 ==========
            float4 frag(Varyings i) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                
                // 获取太阳方向
                Light mainLight = GetMainLight();
                float3 SunDir = normalize(mainLight.direction);
                float3 SunColor = mainLight.color * _SunBrightness;
                
                // 相机和视线
                float3 RayOrigin = _WorldSpaceCameraPos;
                float3 RayDir = normalize(i.viewDir);
                
                // 如果不是天空盒，才计算视线方向
                #ifndef IS_SKYBOX
                    // 非skybox的话用这个
                    float2 screenUV = i.screenUV.xy/i.screenUV.w;
                    // 1. 把屏幕UV转成裁剪空间坐标（范围：x/y∈[-1,1]）
                    float4 clipPos = float4(screenUV * 2.0 - 1.0, 1.0, 1.0);
                    // 2. 逆视投影矩阵：裁剪空间 → 世界空间
                    float4 worldPos = mul(_InvViewProj, clipPos);
                    worldPos /= worldPos.w; // 透视除法
                    // 3. 计算光线方向并单位化
                    float3 rd = normalize(worldPos.xyz - RayOrigin);
                    RayDir = rd;
                #endif

                // 以下用于测试
                #if defined(_IS_SKYBOX)
                    return float4(0, 0, 0, 1);
                #endif

                // 计算太阳高度
                float sunHeight = smoothstep(0.0,0.01, RayDir.y); // 用于剔除太靠近地平线的云
                //sunHeight = 1.0;
                //return float4(sunHeight*float3(1,1,1), 0);

                // 采样大气层散射
                float3 EnvColor = SAMPLE_TEXTURE2D_LOD(_EnvPanoramic,sampler_EnvPanoramic, DirToPanoramicUV(RotateAroundY(-RayDir, _PanoramicRotation)), 0.0).rgb;
                //return float4(EnvColor,1.0);
                float sun = dot(RayDir, SunDir);
                sun = step(1.0-_SunSize, sun);
                //sun *= smoothstep(-0.01,0.05,rd.y);
                EnvColor += 4.0 * sun * EnvColor * smoothstep(-0.01,0.05,RayDir.y);
                //return float4(EnvColor,1.0);
                // 云层参数
                CloudLayerParams CloudParams = GetCloudLayerParams();
                


                float4 RFCloudData = SAMPLE_TEXTURE2D(_AtmosRFCloudTex,sampler_AtmosRFCloudTex, (i.screenUV.xy/i.screenUV.w));
                float3 FinalColor = RFCloudData.rgb;
                float TotalTransmittance = lerp(1.0,RFCloudData.a,smoothstep(0.01,0.03,RayDir.y));
                //return float4(float3(1,1,1)*TyndallEffect/float(NumSamples),1);

                #ifndef IS_SKYBOX
                    FinalColor = TotalLuminance * _CloudColor.rgb  + _CloudEmission.rgb;
                #endif
                
                FinalColor = clamp(FinalColor, 0.0, 10.0);
                
                
                // 混合颜色
                float3 nightColor = _NightBrightness * lerp( _NightSkyLineColor.rgb,_NightColor.rgb,pow(abs(RayDir.y),0.5));


                // 混合夜色
                float3 mixColor = EnvColor ;//+ nightColor;//*smoothstep(0.0,0.1,saturate(SunDir.y));
                //return float4(float3(1,1,1)*smoothstep(0.0,0.1,saturate(SunDir.y)),1);
                // 混合星星
                #ifdef USE_STARS_EFFECT
                    float star = GenerateStarsAdvanced(RayDir,
                        50.0, // 方位角密度
                        20.0,  // 天顶角密度
                        0.005, // 最小尺寸
                        0.02, // 最大尺寸
                        0.7,   // 偏移强度
                        0.3    // 生成阈值
                    );
                    float starAlpha = saturate(GetLuminance(mixColor)-star*0.01);
                    starAlpha = smoothstep(0.0,0.1,starAlpha);
                    mixColor = lerp(star*float3(1,1,1)*TotalTransmittance,mixColor,starAlpha);
                #endif

                // 混合云
                float3 cloudColor = lerp(FinalColor, EnvColor, _CloudAlpha);
                mixColor = lerp(cloudColor, mixColor, TotalTransmittance);
                
                #ifdef USE_TYNDALL_EFFECT
                    mixColor +=_CES*20.0*TyndallEffect/float(NumSamples)*0.5*SunColor;
                #endif

                



                //return float4(float3(1,1,1)*nightAlpha,1);
                //return float4(float3(1,1,1)*lerp(nightColor,mixColor,nightAlpha),1);  
                return float4(mixColor,1.0);
            }
            
            ENDHLSL
        }
    }
    
    FallBack "Skybox/Cubemap"
}