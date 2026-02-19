Shader "Unlit/SoftShadowShader"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _PoissonCount ("泊松盘采样次数",Float) = 5
        _initPCSS ("PCSS初始模糊",Float) = 0.0005
        _distancePCSS ("PCSS距离模糊",Float) = 0.015
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            ZTest LEqual
            ZWrite On
            Cull Back
            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_MainTex);SAMPLER(sampler_MainTex);
            int _PoissonCount;
            float _initPCSS;
            float _distancePCSS;

            float4x4 _POSvpM;
            float3 _POSLightDir;
            //float4x4 _POSpM;
            TEXTURE2D(_POSMap);
            SAMPLER(sampler_POSMap);
            //SAMPLER(sampler_POSMap_LinearClamp); 

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float3 Nor : NORMAL;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                float3 posWS : TEXCOORD1;
                float3 norWS : TEXCOORD3;
                float4 shadowCoord : TEXCOORD2;
            };
            // 高斯权重函数
            float GaussianWeight(float offset, float sigma)
            {
                float weight = exp(-(offset * offset) / (2.0 * sigma * sigma));
                return weight;
            }
            // 16个泊松盘采样点
             static const float2 PoissonDisk16[16] = {
                float2(-0.94201624, -0.39906216),
                float2(0.94558609, -0.76890725),
                float2(-0.09418410, -0.92938870),
                float2(0.34495938, 0.29387760),
                float2(-0.91588581, 0.45771432),
                float2(-0.81544232, -0.87912464),
                float2(-0.38277543, 0.27676845),
                float2(0.97484398, 0.75648379),
                float2(0.44323325, -0.97511554),
                float2(0.53742981, -0.47373420),
                float2(-0.26496911, -0.41893023),
                float2(0.79197514, 0.19090188),
                float2(-0.24188840, 0.99706507),
                float2(-0.81409955, 0.91437590),
                float2(0.19984126, 0.78641367),
                float2(0.14383161, -0.14100790)
             };
            // 生成屏幕空间噪声用于旋转采样
            float2 GetRandomRotation(float2 screenPos)
            {
                float randomAngle = frac(sin(dot(screenPos, float2(12.9898, 78.233))) * 43758.5453) * 6.2831853;
                return float2(cos(randomAngle), sin(randomAngle));
            }
            // 软阴影PCF，使用软比较替代硬比较
            float2 SoftPCF(float2 uv, float compareDepth, float2 screenPos, float2 radius)
            {
                float shadow = 0.0;
                float GRadius = 0.0;//用于第一次PCF输出估算的深度
                float2 rotation = GetRandomRotation(screenPos);
                int cs = _PoissonCount;
                
                // 使用13个泊松采样点
                for(int i = 0; i < cs; i++)
                {
                    // 旋转采样点
                    float2 poissonOffset = float2(
                        PoissonDisk16[i].x * rotation.x - PoissonDisk16[i].y * rotation.y,
                        PoissonDisk16[i].x * rotation.y + PoissonDisk16[i].y * rotation.x
                    ) * radius;
                    
                    float2 sampleUV = uv + poissonOffset;
                    sampleUV = clamp(sampleUV,0.0,1.0);

                     //边界检查
                    if(any(sampleUV < 0.0) || any(sampleUV > 1.0))
                    {
                        shadow += 1.0;
                        continue;
                    }

                    float shadowDepth = SAMPLE_TEXTURE2D(_POSMap, sampler_POSMap, sampleUV).r;
                    shadow += step(shadowDepth , compareDepth);
                    GRadius += pow(saturate(shadowDepth - compareDepth),1.0);
                }
                return float2(shadow/cs,GRadius/cs);
            }

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = TransformObjectToHClip(v.vertex);
                //o.vertex.z = 1.0 - o.vertex.z;
                o.posWS = TransformObjectToWorld(v.vertex).xyz;
                o.norWS = TransformObjectToWorldDir(v.Nor).xyz;
                o.shadowCoord = mul(_POSvpM,float4(o.posWS,1.0))*float4(1,1,-1,1);
                return o;
            }

            float4 frag (v2f i) : SV_Target
            {
                // 透视除法，这他妈是正交的！！！不需要
                float3 shadowCoord = i.shadowCoord.xyz/i.shadowCoord.w; 
                shadowCoord = mul(_POSvpM,float4(i.posWS,1.0)).xyz;
                
                // 从-1 ~ 1 映射到 0 ~ 1
                float3 reRamp = saturate(shadowCoord.xyz*0.5+0.5);
                float cActDep = abs(1.0-reRamp.z); // 重映射
                
                // 法向法向的Shadow Bais
                // 改进的法线偏移
                float cosTheta = saturate(dot(i.norWS, -_POSLightDir));
                float normalBias = 0.002 * sqrt(1.0 - cosTheta * cosTheta);
                normalBias = clamp(normalBias, 0.001, 0.01);
                // Shadow Bais
                cActDep = saturate(cActDep  + normalBias);
                // 计算新的屏幕uv
                float2 newUV = clamp(shadowCoord.xy*0.5 + 0.5,0.0,1.0);
                
                float shad = SAMPLE_TEXTURE2D(_POSMap, sampler_POSMap, newUV+float2(0.0,0.0)).r;
                float radius = pow(saturate(shad-cActDep),3.0);
                // PCF
                // 通过第一次PCF估算阴影半径
                radius =  SoftPCF(newUV,cActDep,i.shadowCoord.xy,0.01).y;
                // 第二次PCF使用第一次估算的半径实现PCSS
                float2 shadowPCF = SoftPCF(newUV,cActDep,i.shadowCoord.xy,radius*_distancePCSS+_initPCSS).x;
                //shadowPCF= step(shadowPCF,0.05);

                //float shad = SAMPLE_TEXTURE2D(_POSMap, sampler_POSMap, newUV+float2(0.0,0.0)).r;

                // 用于处理后续采样中的白边问题,不知道为什么后续模糊采样时，尽管限制的最大值差距采样
                // 但是在明暗交界线边缘仍会出现白边，覆盖上一层Lambert可以有效减弱这个问题
                // 再覆盖一层兰伯特解决
                Light ld = GetMainLight();
                float3 lightDir = normalize(ld.direction); // 主光源方向（世界空间，ForwardBase通道）
                float lambert = dot(lightDir,i.norWS);
                float lamMask = step(-0.5,lambert);// 取明暗交界线往后一点，避免与后续的shaderModel的光照产生冲突

                // 合成最终的阴影图
                float shadow = shadowPCF.x*lamMask;

                // 不在灯光空间屏幕范围内的另做处理
                float overCoord = step(abs(shadowCoord),1.0).x*step(abs(shadowCoord),1.0).y;
                float finalShadow = lerp(1.0,shadow,overCoord);


                //return float4(shadowPCF.x*lamMask*float3(1,1,1),1.0);
                //return float4(radius,0.0,0.0,0.0);
                //return float4(step(shad,cActDep),newUV,1.0);
                //return float4(finalShadow,0.5,1.0,1.0);
                return float4(finalShadow,1.0,1.0,1.0);
                //return float4(finalShadow,LinearEyeDepth(i.vertex.z/i.vertex.w,_ZBufferParams),1.0,1.0);
            }
            ENDHLSL
        }
    }
}
