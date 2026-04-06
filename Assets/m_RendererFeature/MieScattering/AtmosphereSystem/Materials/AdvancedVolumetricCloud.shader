Shader "Custom/AdvancedVolumetricCloud"
{
    Properties
    {
        [Header(Environment)]
        _EnvPanoramic ("环境反射全景贴图",2D ) = "white" {}
        _PanoramicRotation ("全景贴图旋转角度", Range(0.0, 1.0)) = 0.0

        // ========== 基础参数 ==========
        //[Header(基础参数)]
        _PlanetRadius("行星半径(m)", Float) = 6371000.0
        _CloudLayerCenter("云层中心", Vector) = (0, 0, 0)
        _CloudBaseHeight("云底高度(m)", Float) = 2000.0
        _CloudThickness("云厚度(m)", Float) = 1000.0
        _TotalScale("整体缩放", Float) = 1.0
        
        [Space(15)]
        // ========== 光线步进参数 ==========
        //[Header(光线步进参数)]
        _NumViewSamples("视线采样数", Range(4, 128)) = 32
        _NumLightSamples("光照采样数", Range(1, 16)) = 8
        _StepSizeMultiplier("步长乘数", Range(0.1, 5.0)) = 1.0
        _BlueNoise("蓝噪声纹理", 2D) = "black" {}
        
        [Space(15)]
        // ========== 云密度参数 ==========
        //[Header(云密度参数)]
        _2Dor3DCloudTexMix("2D/3D云纹理混合", Range(0, 1)) = 1.0
        _CloudTex2D("云纹理(2D)", 2D) = "white" {}
        _CloudTex("云纹理(3D)", 3D) = "white" {}
        _CloudDetailTex("云纹理(3D)细节纹理", 3D) = "white" {}
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
        //[Header(光照参数)]
        _SunBrightness("太阳亮度", Float) = 1.0
        _SunColor("太阳颜色", Color) = (1, 0.95, 0.9, 1)
        _SunDirection("太阳方向", Vector) = (0, 1, 0, 0)
        
        [Space(15)]
        // ========== 散射参数 ==========
        //[Header(散射参数)]
        _ExtinctionCoefficient("消光系数", Range(0.1, 10.0)) = 0.1
        _ScatteringCoefficient("散射系数", Float) = 0.8
        _Albedo("云反照率", Color) = (0.9, 0.9, 0.9, 1)
        _PhaseG("相位函数G参数", Range(-0.999, 0.999)) = 0.8
        _PhaseG2("相位函数G2参数", Range(-0.999, 0.999)) = 0.3
        _PhaseBlend("相位混合", Range(0, 1)) = 0.5
        
        [Space(15)]
        // ========== 多重散射参数 ==========
        //[Header(多重散射参数)]
        _MsScattFactor("多重散射衰减因子", Range(0, 1)) = 0.5
        _MsExtinFactor("多重消光衰减因子", Range(0, 1)) = 0.3
        _MsPhaseFactor("多重相位衰减因子", Range(0, 1)) = 0.7
        _MaxScatteringOrder("最大散射阶数", Int) = 2
        
        [Space(15)]
        // ========== 外观参数 ==========
        //[Header(外观参数)]
        _CloudColor("云基础颜色", Color) = (1, 1, 1, 1)
        _CloudEmission("云自发光", Color) = (0, 0, 0, 1)
        _WindDirection("风向", Vector) = (1, 0, 0, 0)
        _WindSpeed("风速", Float) = 1.0
        _TimeScale("时间缩放", Float) = 1.0
        
        [Space(15)]
        // ========== 调试参数 ==========
        //[Header(调试参数)]
        _DebugMode("调试模式", Int) = 0
        _ShowNormals("显示法线", Range(0, 1)) = 0
        _ShowDensity("显示密度", Range(0, 1)) = 0
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
            #define PI 3.14159265359
            #define MAX_FLOAT 3.402823466e+38
            
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
            
            // ========== 属性变量 ==========
            CBUFFER_START(UnityPerMaterial)
                float _PanoramicRotation;

                float _PlanetRadius;
                float3 _CloudLayerCenter;
                float _CloudBaseHeight;
                float _CloudThickness;
                float _TotalScale;
                
                float _NumViewSamples;
                float _NumLightSamples;
                float _StepSizeMultiplier;
                
                float _2Dor3DCloudTexMix;
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
            float CalculateCloudDensity(float3 WorldPos, CloudLayerParams CloudParams, float2 ScreenUV)
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
                float3 TexCoord = (WorldPos + WindOffset*100) * _CloudDensityScale;
                float4 Noise3D = SAMPLE_TEXTURE3D_LOD(_CloudTex, sampler_CloudTex, TexCoord.xzy/20.0, 0);
                float4 Noise2D = SAMPLE_TEXTURE2D_LOD(_CloudTex2D, sampler_CloudTex2D, TexCoord.xz/20.0, 0);
                
                float4 NoiseDetail = SAMPLE_TEXTURE3D_LOD(_CloudDetailTex, sampler_CloudDetailTex, TexCoord/2.5, 0);
                
                // 组合噪声通道
                // 使用大尺度和小尺度噪声组合
                float LargeScale = lerp(Noise3D.r, Noise3D.g * 1.5, 0.3);
                float FineDetail = lerp(Noise3D.b, Noise3D.a * 1.5, 0.3);
                
                // 组合密度
                float Density = LargeScale * lerp(0.4, 1.0, FineDetail) ;
                Density = Noise3D.r ;

                // 应用阈值和边缘锐化
                float Edge = max(_CloudEdgeSharpness, _CloudDensityThreshold + 0.001);
                float Edge2 = max(_MixEdgeFieldFactor , _CloudDensityThreshold + 0.001); // 用于定义侵蚀范围
                float erosion = smoothstep(_CloudDensityThreshold, Edge2, Density );
                Density = smoothstep(_CloudDensityThreshold, Edge, Density );

                // 细节噪声
                float detailFactor = NoiseDetail.r * saturate(1.0 - NoiseDetail.b + 0.0);
                float detailEdge = max(_CloudDetailSharpness, _CloudDetailThreshold + 0.001);
                detailFactor = smoothstep(_CloudDetailThreshold, detailEdge, detailFactor);
                detailFactor = lerp(1.0, detailFactor, _CloudDetailMix);
                detailFactor = lerp(detailFactor,1.0, _OnlyOnEdgeErosion * erosion); // 仅在边缘进行侵蚀

                
                // 最终密度
                return Density * detailFactor * _CloudDensityMultiplier * HeightFactor ;//* NoiseDetail.r;
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
            float CalculateCloudShadow(float3 SamplePos, float3 LightDir, CloudLayerParams CloudParams, 
                                       int NumSamples, float StepSize, float2 ScreenUV)
            {
                float OpticalDepth = 0.0;
                float3 CurrentPos = SamplePos;
                float baseStepSize = StepSize;
                
                for (int i = 0; i < NumSamples; i++)
                {
                    CurrentPos += LightDir * StepSize;
                    
                    // 计算当前点密度
                    float Density = CalculateCloudDensity(CurrentPos, CloudParams, ScreenUV);
                    OpticalDepth += Density * StepSize;
                    
                    // 提前终止优化
                    if (OpticalDepth > 10.0)
                        break;
                    // 自适应步长
                    StepSize = lerp(baseStepSize*2.0, baseStepSize*0.05, Density);
                }
                
                return exp(-_ExtinctionCoefficient * OpticalDepth);
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
                
                // 云层参数
                CloudLayerParams CloudParams = GetCloudLayerParams();
                
                // 计算射线与云层的交点
                float2 InnerIntersect = RaySphereIntersect(RayOrigin, RayDir, 
                                                          CloudParams.Center, CloudParams.InnerRadius);
                float2 OuterIntersect = RaySphereIntersect(RayOrigin, RayDir, 
                                                          CloudParams.Center, CloudParams.OuterRadius);
                
                // 确定步进范围
                float EntryDist = max(0.0, InnerIntersect.y);
                float ExitDist = OuterIntersect.y;
                
                if (EntryDist <= 0.0 || ExitDist <= EntryDist)
                {
                    // 无云，返回透明
                    return float4(0, 0, 0, 0);
                }
                
                float RayLength = ExitDist - EntryDist;
                
                // 蓝噪声抖动
                float BlueNoise = SAMPLE_TEXTURE2D(_BlueNoise, sampler_BlueNoise, (i.screenUV.xy/i.screenUV.w) * 3.0).r;
                float Dither = (BlueNoise - 0.5) * 2.0;
                //return float4(Dither, 0, 0, 0);
                // 步进设置
                int NumSamples = int(_NumViewSamples);
                float StepSize = RayLength / float(NumSamples) * _StepSizeMultiplier;
                
                // 初始化相位函数
                float CosTheta = dot(RayDir, SunDir);
                float BasePhase = BlendPhaseFunction(CosTheta, _PhaseG, _PhaseG2, _PhaseBlend);
                PhaseContext PhaseCtx = SetupPhaseContext(BasePhase, _MsPhaseFactor, _MaxScatteringOrder);
                
                // 初始化累加变量
                float3 TotalLuminance = float3(0, 0, 0);
                float TotalTransmittance = 1.0;
                float TotalDensity = 0.0;
                
                // 光线步进循环
                float CurrentDist = EntryDist + StepSize * 0.5;  // 从中间开始
                CurrentDist += StepSize * Dither * 1.0;  // 应用抖动
                
                for (int step = 0; step < NumSamples; step++)
                {
                    // 当前位置
                    float3 SamplePos = RayOrigin + RayDir * CurrentDist;
                    
                    // 计算云密度
                    float Density = CalculateCloudDensity(SamplePos, CloudParams, i.screenUV);
                    
                    if (Density > 0.0)
                    {
                        // 计算阴影
                        float Shadow = CalculateCloudShadow(SamplePos, SunDir, CloudParams, 
                                                           int(_NumLightSamples), StepSize * 2.0, i.screenUV);
                        
                        // 计算消光和散射
                        float Extinction = Density * _ExtinctionCoefficient;
                        float Scattering = Density * _ScatteringCoefficient;
                        
                        // 计算光照贡献
                        float3 LightContrib = SunColor * Shadow;
                        float3 ScatterContrib = CalculateMultipleScattering(
                            float3(Scattering, Scattering, Scattering),
                            TotalTransmittance,
                            PhaseCtx,
                            LightContrib,
                            float3(0.5, 0.6, 0.8),  // 天光颜色
                            _MsScattFactor
                        );
                        
                        // 累加贡献
                        TotalLuminance += ScatterContrib * StepSize;
                        
                        // 更新透射率
                        float StepTransmittance = exp(-Extinction * StepSize);
                        TotalTransmittance *= StepTransmittance;
                        
                        // 累加密度（用于调试）
                        TotalDensity += Density;
                    }
                    
                    // 自适应步长
                    StepSize = lerp(StepSize*1.0, StepSize * 0.05, Density);
                    // 步进
                    CurrentDist += StepSize + StepSize * Dither * 0.5;
                    
                    // 提前终止
                    if (TotalTransmittance < 0.01)
                        break;
                    
                    if (CurrentDist > ExitDist)
                        break;
                }
                
                // 最终颜色合成
                float3 FinalColor = TotalLuminance * _CloudColor.rgb * SunColor + _CloudEmission.rgb;
                FinalColor = clamp(FinalColor, 0.0, 10.0);
                
                // 调试模式
                if (_DebugMode == 1)
                {
                    // 显示密度
                    float NormalizedDensity = TotalDensity / float(NumSamples);
                    return float4(NormalizedDensity, NormalizedDensity, NormalizedDensity, 1.0);
                }
                else if (_DebugMode == 2)
                {
                    // 显示步进距离
                    float NormDist = RayLength / 10000.0;
                    return float4(NormDist, NormDist, NormDist, 1.0);
                }
                else if (_DebugMode == 3)
                {
                    // 显示透射率
                    return float4(TotalTransmittance, TotalTransmittance, TotalTransmittance, 1.0);
                }
                
                // 正常输出
                //return float4(float3(1,1,1),1);
                //return float4(FinalColor, 1.0 - TotalTransmittance);
                float3 EnvColor = SAMPLE_TEXTURE2D_LOD(_EnvPanoramic,sampler_EnvPanoramic, DirToPanoramicUV(RotateAroundY(-RayDir, _PanoramicRotation)), 0.0).rgb;

                //return float4(EnvColor, 1.0);
                return float4(lerp(lerp(FinalColor, EnvColor, 0.5), EnvColor, TotalTransmittance),1.0);
            }
            
            ENDHLSL
        }
    }
    
    FallBack "Skybox/Cubemap"
}