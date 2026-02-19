Shader "Unlit/AtmosLUT"
{
    Properties
    {
        [HideInInspector]_MainTex ("原始场景颜色", 2D) = "white" {} // 使用C#自动传递
        [NoScaleOffset]_AtmosLUT ("大气LUT",2D) = "black"{}
        _PlanetCenter ("行星中心位置",Vector) = (0,0,0,0)
        _PlanetRadius ("星球半径",Float) = 10.0
        _AtmosphereHeight ("大气层厚度",Float) = 3.0
        [Space(10.0)]
        _Saturation ("饱和度",Float) = 1.0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        LOD 100
        
        Pass{
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_MainTex);SAMPLER(sampler_MainTex);
            TEXTURE2D(_AtmosLUT);SAMPLER(sampler_AtmosLUT);
            // 传递的摄像机深度贴图
            TEXTURE2D(_CameraDepthTexture);SAMPLER(sampler_CameraDepthTexture);
            CBUFFER_START(UnityPerMaterial)
                float3 _PlanetCenter;
                float _PlanetRadius;
                float _AtmosphereHeight;

                float _Saturation;
                // 从C#传递
                float3 _CameraWorldPos;
                float3 _SunDirection;
                float4x4 _InvViewProj;  // 逆视投影矩阵
            CBUFFER_END        

            // 自定义函数区域
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
            // 自定义函数结束

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


                // 采样大气LUT的UV，x是视线与球交线弦的中点的海拔，y是射线起点处法向与光线的dot
                float3 planetCenter = _PlanetCenter;
                float planetRadius = _PlanetRadius;
                float atmosHeight = _AtmosphereHeight;

                // inter是摄像机向量与大气层的交点，inter2是与星球的交点
                float2 inter = RaySphereIntersect(ro,rd,planetCenter,planetRadius+atmosHeight);
                float2 inter2 = RaySphereIntersect(ro,rd,planetCenter,planetRadius);
                bool inAtmos = length(ro-planetCenter)<planetRadius+atmosHeight ? true : false;
                float rayLength = inAtmos ? 
                    lerp( inter.y , inter2.x , step(0.0,inter2.x)) 
                    //inter.y
                    : lerp(inter.y- inter.x,inter2.x-inter.x,step(0.0,inter2.x)) ;
                
                //rayLength = inAtmos ? inter.y :inter.y- inter.x;
                float3 hitPos = ro + rd * inter.x; // 摄像机向量击中球体的表面位置
                float3 planetNor = normalize(hitPos-planetCenter); // 星球法线

                float disSurf = inAtmos ? 0.0 : inter.x; // 距离表面的距离，当在大气层内部的时候是0
                // 计算视线弦中点处的海拔
                float xiangao = (length((ro + rd*disSurf + rd*rayLength*0.5)-planetCenter)-planetRadius)/atmosHeight*1.0;
                // 需要注意的是，当我们位于大气层，此时的视线弦应该是反着来的，海拔越低越薄
                xiangao = inAtmos && step(0.0,inter2.x) ? 1.0-xiangao : xiangao;


                float guangAngle = dot(planetNor,_SunDirection);
                guangAngle = inAtmos ? dot(normalize(ro-planetCenter),_SunDirection) : guangAngle;
                guangAngle = guangAngle*0.5 + 0.5;

                // 在黄昏线处，把彩光下压到贴近球面
                xiangao += 0.4*smoothstep(0.5,0.4,guangAngle)*step(inter2.x,0.0);
                //guangAngle = pow(guangAngle,2.0);
                float2 AtmosUV = float2(saturate(pow((xiangao+0.1),2.0)),saturate(pow(guangAngle,1.0)));
                
                float3 AtmosLUT = SAMPLE_TEXTURE2D(_AtmosLUT,sampler_AtmosLUT,AtmosUV);
                AtmosLUT = AdjustSaturation(AtmosLUT,_Saturation);

                //return float4(smoothstep(0.4,0.5,guangAngle)* float3(1,1,1),1);
                return float4(inter.x* float3(1,1,1),1);
            }
            ENDHLSL
        }
    }
}
