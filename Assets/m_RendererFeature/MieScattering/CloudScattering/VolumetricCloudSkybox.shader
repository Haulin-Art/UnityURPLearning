Shader "Custom/AtmosScatteringSkybox"
{
    Properties
    {
        [Header(Atmosphere Parameters)]
        _TotalScale ("整体缩放", Float) = 1
        _PlanetRadius ("行星半径", Float) = 6371000
        _Altitude ("海拔(km)", Float) = 0.0

        [Header(Sun)]
        _SunBrightness ("太阳亮度", Float) = 1.0

        [Header(Sampling)]
        _NumSamples ("视线采样数", Range(4, 64)) = 32
        _NumSamplesLight ("太阳光采样数", Range(1, 16)) = 8

        [Header(Environment)]
        _EnvPanoramic ("环境反射全景贴图",2D ) = "white" {}
        _PanoramicRotation ("全景贴图旋转角度", Range(0.0, 1.0)) = 0.0

        [Header(Cloud)]
        _CloudTex ("云纹理", 3D) = "black" {}
        _BlueNoise ("蓝噪声", 2D) = "black" {}
        _CloudBaseHeight ("云底高度", Float) = 2000.0
        _CloudThickness ("云厚度", Float) = 1000.0
        _CloudAlpha ("云透明度", Range(0.0, 1.0)) = 0.5
        _CloudScatterCoeff ("云散射系数", Float) = 1.0
        _CloudExtinctionCoeff ("云消光系数", Float) = 0.05
        _CloudPhaseG ("云相位函数G值", Range(0, 0.99)) = 0.8
        _CloudDensityThreshold ("云密度阈值", Range(0, 1)) = 0.1
        _CloudDensityMultiplier ("云密度乘数", Range(0.001, 30.0)) = 0.1
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

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "PerlinNoise3D.hlsl"

            struct Attributes
            {
                float4 vertex : POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 vertex : SV_POSITION;
                float3 viewDir : TEXCOORD0;
                float4 screenPos : TEXCOORD1;
                UNITY_VERTEX_OUTPUT_STEREO
            };
            

            TEXTURE3D(_CloudTex);SAMPLER(sampler_CloudTex);
            TEXTURE2D(_EnvPanoramic);SAMPLER(sampler_EnvPanoramic);
            TEXTURE2D(_BlueNoise);SAMPLER(sampler_BlueNoise);
        
            CBUFFER_START(UnityPerMaterial)
                float _TotalScale;
                float _PlanetRadius;
                float _AtmosphereHeight;
                float _Altitude;

                float _SunBrightness;
                
                int _NumSamples;
                int _NumSamplesLight;
                float _DebugMode;
                
                // Environment parameters
                float _PanoramicRotation;
                // Cloud parameters
                float _CloudBaseHeight;
                float _CloudThickness;
                float _CloudAlpha;
                float _CloudScatterCoeff;
                float _CloudExtinctionCoeff;
                float _CloudPhaseG;
                float _CloudDensityThreshold;
                float _CloudDensityMultiplier;
            CBUFFER_END

            // ???? 某种编译错误导致了lerp函数无法混合颜色和float3，暂时只能手动实现lerp
            float3 manualLerp(float3 a, float3 b, float t)
            {
                return a * (1.0 - t) + b * t;
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


             // 云相位函数 - Henyey-Greenstein相位函数，更适合云的前向散射
            float CloudPhase(float cosTheta, float g)
            {
                float g2 = g * g;
                float numerator = 1.0 - g2;
                float denominator = pow(1.0 + g2 - 2.0 * g * cosTheta, 1.5);
                return numerator / (4.0 * PI * denominator);
            }

            // 计算云密度 - 指数衰减模型
            // 计算云密度 - 指数衰减模型
            float GetCloudDensity(float h, float cloudBaseHeight, float cloudThickness)
            {
                // 归一化高度 (0=云底, 1=云顶)
                float normalizedHeight = (h - cloudBaseHeight) / cloudThickness;

                // 使用smoothstep替代硬边界，让边缘过渡更自然
                float edgeFactor = smoothstep(0.0, 0.2, normalizedHeight) * 
                                  (1.0 - smoothstep(0.8, 1.0, normalizedHeight));

                // 在0.1处密度最大的非对称分布
                float peakHeight = 0.1;

                // 改进的密度分布
                float density = 0.0;

                if (normalizedHeight < peakHeight)
                {
                    // 上升段：二次曲线快速上升
                    float t = normalizedHeight / peakHeight;
                    density = 1.0 - (1.0 - t) * (1.0 - t);
                }
                else
                {
                    // 下降段：指数衰减
                    float t = (normalizedHeight - peakHeight) / (1.0 - peakHeight);
                    density = exp(-t * 4.0);
                }

                return density * edgeFactor;
            }

            // 云纹理采样函数 - 处理云纹理的采样和密度计算
            float SampleCloudTexture(float3 pos, float cloudBaseHeight, float cloudThickness, float height)
            {
                // 采样云纹理
                float3 texCoord = pos / 10000.0; // 简单的纹理坐标缩放
                float cloudTex = SAMPLE_TEXTURE3D(_CloudTex, sampler_CloudTex, texCoord).r;
                
                // 计算云密度
                float cloudDensity = GetCloudDensity(height, cloudBaseHeight, cloudThickness);
                
                // 调整云密度阈值和强度
                float densityThreshold = _CloudDensityThreshold; // 云密度阈值
                float densityMultiplier = _CloudDensityMultiplier; // 云密度强度乘数
                
                // 应用阈值和乘数
                float finalDensity = cloudDensity * cloudTex;
                finalDensity = smoothstep(densityThreshold,1.0,finalDensity ) * densityMultiplier;
                //float cloudNoise = cloudNoise3D(pos, 1.0/5000.0, 1.0, 1.0) * cloudDensity;
                //float finalDensity = smoothstep(densityThreshold,1.0,cloudNoise ) * densityMultiplier;
                
                return finalDensity;
            }


            // 修改后的云散射计算
            float3 ComputeAtmosScattering(float3 rayOrigin, float3 rayDir, float rayLength,
                                          float3 planetCenter, float planetRadius, float cloudEndHeight,
                                          float3 sunDir, int numSamples, int numLightSamples,float2 screenUV,
                                          out float3 outViewTransmittance)
            {
                float blueNoise = SAMPLE_TEXTURE2D(_BlueNoise, sampler_BlueNoise, screenUV*3.0).r;
                float ds = rayLength / (float)numSamples;
                ds = ds*(0.8 + blueNoise*0.3);
                float3 p = rayOrigin + rayDir * ds * 0.5;

                float3 accumScatter = float3(0, 0, 0);
                float totalCloudDepth = 0.0;

                // 云参数
                float scaleFactor = _TotalScale;
                float cloudBaseHeight = _CloudBaseHeight / scaleFactor;  // 云底高度 (米)
                float cloudThickness = _CloudThickness / scaleFactor;   // 云厚度 (米)
                float cloudScatterCoeff = _CloudScatterCoeff;  // 云散射系数
                float cloudExtinctionCoeff = _CloudExtinctionCoeff; // 云消光系数

                // 云的相位函数参数 - 使用较大的g值模拟云的前向散射
                float cloudPhaseG = _CloudPhaseG;

                // 计算相位函数
                float cosTheta = dot(rayDir, sunDir);
                float phaseCloud = CloudPhase(cosTheta, cloudPhaseG);
                // 视线方向
                //[unroll(12)]
                for (int i = 0; i < 16; i++)
                {
                    float h = length(p - planetCenter) - planetRadius;

                    // 如果低于行星表面，则跳过
                    if (h < 0.0)
                        break;

                    // 计算实际云密度（使用新的采样函数）
                    float actualCloudDensity = SampleCloudTexture(p, cloudBaseHeight, cloudThickness, h);
                    
                    if (actualCloudDensity > 0.0)
                    {
                        // 计算从当前点到大气层边界的光线长度
                        float2 lightInter = RaySphereIntersect(p, sunDir, planetCenter, planetRadius + cloudEndHeight);
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
                            // 计算光线方向的光学深度（增加采样点数量以获得更好的阴影效果）
                            float lightOpticalDepth = 0.0;
                            int lightSamples = 12; // 增加采样点数量
                            float lightDs = lightRayLength / (float)lightSamples;
                            lightDs = 200.0;
                            float3 lightPos = p + sunDir * lightDs * 0.5;
                            //[unroll(8)]
                            for (int j = 0; j < 12; j++)
                            {
                                // 采用指数步长
                                lightDs = exp(j/6.0)*15.0;
                                float lightH = length(lightPos - planetCenter) - planetRadius;
                                // 使用新的采样函数计算光线方向的云密度
                                float lightActualCloudDensity = SampleCloudTexture(lightPos, cloudBaseHeight, cloudThickness, lightH);
                                if (lightActualCloudDensity > 0.0)
                                {
                                    lightOpticalDepth += lightActualCloudDensity * lightDs;
                                }
                                lightPos += sunDir * lightDs;
                            }
                            
                            // 视线方向到当前点的光学深度
                            float viewOpticalDepth = totalCloudDepth + actualCloudDensity * ds * 0.5;
                            
                            // 总光学深度
                            float totalOpticalDepth = viewOpticalDepth + lightOpticalDepth;
                            
                            // 计算透射率 T = exp(-τ)
                            float transmittance = exp(-cloudExtinctionCoeff * totalOpticalDepth * 10.0);
                            
                            // 累积散射光: 密度 × 步长 × 散射系数 × 相位函数 × 透射率
                            accumScatter += actualCloudDensity * ds * cloudScatterCoeff * phaseCloud * transmittance;
                        }
                    }

                    // 更新累积光学深度
                    totalCloudDepth += actualCloudDensity * ds;
                    p += rayDir * ds;
                }

                // 计算视线方向的透射率
                outViewTransmittance = exp(-cloudExtinctionCoeff * totalCloudDepth);

                // 云的颜色为白色，但乘以太阳颜色以获得更好的光照效果
                //float sunLuminance = dot(float3(1,1,1), float3(0.299, 0.587, 0.114));
                return accumScatter ;
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
                o.screenPos = ComputeScreenPos(o.vertex);

                return o;
            }

            float4 frag(Varyings i) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                
                // 获取主光源方向（太阳方向）
                Light mainLight = GetMainLight();
                float3 sunDir = mainLight.direction;
                float3 sunColor = mainLight.color;

                // 相机位置作为射线起点
                float3 ro = _WorldSpaceCameraPos;
                
                // 视线方向
                float3 rd = normalize(i.viewDir);
                
                float2 screenUV = i.screenPos.xy/i.screenPos.w;
                float blueNoise = SAMPLE_TEXTURE2D(_BlueNoise, sampler_BlueNoise, screenUV*4.0).r;

                // 计算缩放后的大气参数
                float scaleFactor = _TotalScale;

                
                float planetR = _PlanetRadius / scaleFactor;
                float altitudeScaled = _Altitude * 1000.0 / scaleFactor;
                float3 planetCenter = float3(0.0, -planetR - altitudeScaled, 0.0);

                float cloudStartHeight = _CloudBaseHeight / scaleFactor;
                float cloudEndHeight = (_CloudThickness + _CloudBaseHeight) / scaleFactor;

                // 计算视线与clodu outer edge 
                float2 inter = RaySphereIntersect(ro, rd, planetCenter, planetR + cloudEndHeight);
                
                float rayLen = 0.0;
                float3 rayStart = ro;
                //rayLen = inter.y - inter.y;

                // 检测与 cloud inter edge
                float2 planetInter = RaySphereIntersect(ro, rd, planetCenter, planetR + cloudStartHeight);
                rayLen = inter.y - planetInter.y;
                // 确保射线长度有效y
                rayLen = max(rayLen, 0.0);

                rayStart += rd * (blueNoise-0.5) * rayLen/48.0;
                //return float4(float3(1,1,1)*(rayLen/10000), 1.0);
                // 计算大气散射
                float3 viewTransmittance;
                float3 scatter = ComputeAtmosScattering(
                    rayStart, rd, rayLen,
                    planetCenter, planetR, cloudEndHeight,
                    sunDir, _NumSamples, _NumSamplesLight, screenUV,
                    viewTransmittance
                );

                // 最终颜色 = 散射光 + 太阳
                float3 finalCol = _SunBrightness * sunColor * (scatter);
                //finalCol += sun * finalCol;
                float3 envColor = SAMPLE_TEXTURE2D(_EnvPanoramic, sampler_EnvPanoramic, DirToPanoramicUV(-rd)).xyz;
                
                //return float4(finalCol,1.0);
                //float3 mixColor = lerp(finalCol.xyz, envColor.xyz, 1);
                float3 mixColor = manualLerp(manualLerp(finalCol.xyz,envColor.xyz,_CloudAlpha),envColor, smoothstep(0.6,1.0,viewTransmittance.x));
                return float4(mixColor, 1.0); 
            }
            ENDHLSL
        }
    }
    FallBack Off
}
