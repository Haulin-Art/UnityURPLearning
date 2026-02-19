Shader "Unlit/Volume"
{
    Properties
    {
        [HideInInspector]_MainTex ("原始场景颜色", 2D) = "white" {}
        _SDFVolume ("SDFVolume",3D) = "black"{}
        _BlueNoise ("蓝噪波纹理",2D) = "black"{}
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        LOD 100
        
        Pass{
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/SpaceTransforms.hlsl"
            
            // 常数定义
            #define NUM_STEPS 16       // Ray Marching步数，影响细节和性能
            #define SHADOW_STEPS 4      // 阴影计算步数
            #define EXTINCTION 0.1      // 光消光系数，控制云层透明度
            #define SCATTERING 0.8      // 光散射系数
            #define G 0.1               // Henyey-Greenstein相位函数不对称参数（-1为后向散射，1为前向散射）
            #define CLOUD_COLOR float3(1.0, 1.0, 1.0)  // 云基础颜色（白色）


            TEXTURE2D(_MainTex);SAMPLER(sampler_MainTex);
            TEXTURE3D(_SDFVolume);SAMPLER(sampler_SDFVolume);
            TEXTURE2D(_BlueNoise);SAMPLER(sampler_BlueNoise);
            // 传递的摄像机深度贴图
            TEXTURE2D(_CameraDepthTexture);SAMPLER(sampler_CameraDepthTexture);
            CBUFFER_START(UnityPerMaterial)   
                // 从C#传递
                float3 _CameraWorldPos;
                float3 _SunDirection;
                float4x4 _InvViewProj;  // 逆视投影矩阵
            CBUFFER_END                

            // 自定义函数区开始
            // 光线与球体相交计算
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
            float2 RaySphereIntersect(float3 rayOrigin, float3 rayDirection, 
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
            float GetDensity(float3 pos)
            {
                float scale = 20.0;
                float4 sdf = SAMPLE_TEXTURE3D(_SDFVolume,sampler_SDFVolume,(pos-0*float3(_Time.x*2.0,0,0))/scale);
                float4 volume2 = SAMPLE_TEXTURE3D(_SDFVolume,sampler_SDFVolume,(pos-0*float3(_Time.x*2.0,0,0))/scale *3.0);
                
                float large = saturate(sdf.x - 0.5 );
                float largeWorly = saturate(0.2 - sdf.z);
                float shape = lerp(1.0,saturate( 0.3 - volume2.x ),0.7);
                
                float dens = saturate(sdf.x - 0.5 ) * lerp(1.0,saturate( 0.3 - volume2.z ),0.5);
                return large*shape*1.0;
            }
            // 比尔-粉末定律：计算云朵的光透射率（基础版）
            // 参数说明：
            // sigmaS: 散射系数（云朵吸收可忽略，消光≈散射，单位：1/米）
            // distance: 光线穿过云朵的几何厚度（Ray Marching单步长/总长度，单位：米）
            // powderK: 粉末系数（适配糖堆效应，常规云朵取2~5，积云3~4，层云2~3，卷云5+）
            // 返回值：透射率（0~1，0完全遮挡，1完全通透）
            float BeerPowderLaw(float sigmaS, float distance, float powderK)
            {
                // 核心公式：T = (1 / (1 + σs·d / k))^k
                float denominator = 1.0 + (sigmaS * distance) / powderK;
                float transmittance = pow(1.0 / denominator, powderK);
                // 钳制值范围，避免数值异常（如sigmaS/distance为负）
                return saturate(transmittance);
            }
            // 参数结构体（根据用户要求传入）
            struct CloudParams {
                float3 sunDir;     // 归一化的太阳方向
                float3 ro;         // 摄像机起点（世界坐标）
                float3 rd;
                float3 planetCenter;
                float startRadius;
                float endRadius;
                float3 rayStart;   // 射线与云层包围盒的交点（世界坐标）
                float rayLength;   // 射线在包围盒内的总行进距离
                int numSamples;
                int numShadowSamples;
            };

            // Henyey-Greenstein相位函数（模拟光散射方向）
            float HenyeyGreenstein(float cosTheta, float g) {
                float g2 = g * g;
                return (1 - g2) / (4 * 3.1415926 * pow(1 + g2 - 2 * g * cosTheta, 1.5));
            }

            // 计算光照贡献（包括阴影和散射）
            float CalculateLight(float3 pos, CloudParams params) {
                // 相位函数：计算光散射强度
                float cosTheta = dot(params.sunDir, params.rd);
                float phase = HenyeyGreenstein(cosTheta, G);

                float2 rayLen = RaySphereIntersect(pos,params.sunDir,params.planetCenter,params.endRadius);
                float maxDis = rayLen.y;

                // 阴影计算：向太阳方向步进，累积密度以模拟光衰减
                float shadow = 1.0;
                float shadowStepSize = rayLen/(SHADOW_STEPS*12.0); // 阴影步长，根据场景调整
                float3 shadowPos = pos + params.sunDir * shadowStepSize; // 避免自相交
                for (int i = 0; i < SHADOW_STEPS; i++) {
                    float density = GetDensity(shadowPos)*1000.0;
                    // 距离星球中心的距离
                    float h = length(shadowPos-params.planetCenter);
                    // 归一化海拔，用于模拟低处的云多，高处云少
                    float norh = (h-params.startRadius)/(params.endRadius-params.startRadius);
                    norh = pow(norh,4.0);

                    shadowStepSize *= 1.5; // 步长越来越大
                    float effect = min(2.0,0.05/shadowStepSize); // 阴影影响系数，越远影响越小
                    effect = 1.0;
                    //shadow *= exp(-density * norh * effect * shadowStepSize * EXTINCTION);
                    shadow *= BeerPowderLaw(EXTINCTION,density/10.0,3.0);
                    shadowPos += params.sunDir * shadowStepSize;

                    if (shadow < 0.01) break; // 提前终止优化
                    if (length(shadowPos-pos)>maxDis) break; // 超过包围盒，提前结束
                }

                return phase * shadow;
                //return 1.0;
            }

            // 主体积云渲染函数
            float4 RenderClouds(CloudParams params) {
                if (params.rayLength <= 0.0) return 0.0; // 若是光线距离小于等于0，直接结束，因为在包围盒外 

                float3 dir = params.rd;
                float stepSize = params.rayLength / NUM_STEPS;       // 动态步长
                //stepSize = 10.0/NUM_STEPS;
                float3 currentPos = params.rayStart;                 // 起始点
                float4 result = float4(0, 0, 0, 0);                  // 累积颜色（RGB）和透明度（A）

                [unroll(NUM_STEPS)] // 循环展开优化（可选）
                for (int i = 0; i < NUM_STEPS; i++) {
                    // 获取当前点的云密度
                    float density = GetDensity(currentPos);
                    float h = length(currentPos-params.planetCenter);
                    float norh = (h-params.startRadius)/(params.endRadius-params.startRadius);
                    norh = pow(norh,4.0);

                    density *= norh;
                    if (h<params.startRadius || h>params.endRadius) density = 0.0;
                    if (density > 0) {
                        // 计算光照：结合散射和阴影
                        float lightEnergy = CalculateLight(currentPos, params);

                        // 当前采样点的颜色贡献
                        float3 color = CLOUD_COLOR * lightEnergy * density * SCATTERING;
                        float alpha = density * stepSize * EXTINCTION;

                        // 体积混合：使用 alpha 混合模拟光传输
                        result.rgb += color * (1 - result.a);
                        result.a += alpha * (1 - result.a);
                        //result.a = saturate(result.a);

                        // 提前终止：如果云层已不透明
                        if (result.a > 0.99) break;
                    }
                    currentPos += dir * stepSize;
                }
                return result;
            }

            // 自定义函数区结束

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
            

                float blueN = SAMPLE_TEXTURE2D(_BlueNoise, sampler_BlueNoise, i.uv).r;
                // 光线步进测试
                float3 planetCenter = float3(0,0,0);
                float planetRadius = 10.0;
                float startRadius = 12.5;
                float endRadius = 15.0;

                float ro2c = length(ro-planetCenter);
                bool inCloud = ro2c<endRadius?true:false;

                // 以下分别是云层最高、云层最低、星球表面
                float2 sphereDis = RaySphereIntersect(ro,rd,planetCenter,endRadius);
                float2 sphereDis2 = RaySphereIntersect(ro,rd,planetCenter,startRadius);
                float2 sphereDis3 = RaySphereIntersect(ro,rd,planetCenter,planetRadius);

                //float rayLen = inCloud ? sphereDis.y : sphereDis.y - sphereDis.x;
                //float3 rayStart = inCloud ? ro : ro + sphereDis.x * rd;

                float rayLen = ro2c > endRadius ? lerp(sphereDis.y - sphereDis.x , sphereDis2.x-sphereDis.x, step(0.0,sphereDis3.x)) 
                    : lerp(sphereDis.y,sphereDis2.x,step(0.0,sphereDis3.x));
                rayLen = ro2c < startRadius ? sphereDis.y - sphereDis2.x : rayLen;
                rayLen = min(rayLen,(endRadius-startRadius)*2.0);

                float3 rayStart = ro2c > endRadius ?  ro + sphereDis.x * rd : ro;
                rayStart = ro2c < startRadius ? ro + sphereDis2.y * rd : rayStart;

                CloudParams cd;
                cd.sunDir=_SunDirection;     // 归一化的太阳方向
                cd.ro = ro ;         // 摄像机起点（世界坐标）
                cd.rd = rd;
                cd.planetCenter = planetCenter;
                cd.startRadius = startRadius;
                cd.endRadius = endRadius;
                cd.rayStart = rayStart+ 0.5*(rayLen/NUM_STEPS)*rd*blueN;   // 射线与云层包围盒的交点（世界坐标）
                cd.rayLength = rayLen;   // 射线在包围盒内的总行进距离

                cd.numSamples = floor(lerp(6,36,smoothstep(0.7,3.0,rayLen)));
                

                float4 cloud = RenderClouds(cd);
                float jiaozheng = rayLen/(endRadius-startRadius);

                float3 finalCol = cloud.xyz*jiaozheng*100 *cloud.a*500.0;
                
                //return float4(float3(1,1,1),1);
                return float4(lerp(originalColor.xyz ,finalCol,saturate(cloud.a*500)) , 1.0);
                //return float4( cloud.xyz*jiaozheng*100 *cloud.a*500.0* float3(1,1,1),1);
                //return float4((originalColor.xyz + cloud.xyz*cloud.a*1000.0)*float3(1,1,1),1);
            }
            ENDHLSL
        }
    }
}
