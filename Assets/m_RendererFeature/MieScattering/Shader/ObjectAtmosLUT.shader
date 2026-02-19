Shader "Unlit/ObjectAtmosLUT"
{
    Properties
    {
        [NoScaleOffset]_AtmosLUT ("大气LUT",2D) = "black"{}
        _PlanetRadius ("星球半径",Float) = 5.0
        _AtmosphereHeight ("大气层厚度",Float) = 3.0
        [Space(10.0)]
        _Saturation ("饱和度",Float) = 1.0
        _Brightness ("亮度",Float) = 1.0
        _Transparence ("透明度",Float) = 10.0
        [Space(10.0)]
        _TwilightLine ("黄昏线-起始-强度-形状",Vector) = (0.6,0.2,0.4,2.0)
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" 
            "RenderPipeline"="UniversalPipeline"
            "Queue"="Transparent"
            "IgnoreProjector"="True" }
        LOD 100
        Cull Off

        // 第一个Pass用于写入深度，避免深度错误
        Pass
        {
            Tags{"LightMode" = "SRPDefaultUnlit"}
            ZWrite On
            ColorMask 0
        }
        // 第二个则是主函数
        Pass{
            Tags{ "LightMode" = "UniversalForward"}
            ZWrite Off
            Blend SrcAlpha OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            //#pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            //#pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            //#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/SpaceTransforms.hlsl"

            TEXTURE2D(_AtmosLUT);SAMPLER(sampler_AtmosLUT);
            // 传递的摄像机深度贴图
            TEXTURE2D(_CameraDepthTexture);SAMPLER(sampler_CameraDepthTexture);

            CBUFFER_START(UnityPerMaterial)
                float3 _PlanetCenter;
                float _PlanetRadius;
                float _AtmosphereHeight;
                float _Saturation;
                float _Brightness;
                float _Transparence;
                float4 _TwilightLine;
            CBUFFER_END

            // 自定义函数区域开始

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
            // 射线与球相交函数
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
            // 自定义函数区域结束

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD1;
                float2 uv : TEXCOORD0;
                float4 screenPos : TEXCOORD2;
            };
            Varyings vert(Attributes v)
            {
                Varyings o;
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                o.positionWS = TransformObjectToWorld(v.positionOS.xyz);
                o.uv = v.uv;
                o.screenPos = ComputeScreenPos(o.positionCS);
                return o;
            }

            float4 frag (Varyings i) : SV_Target
            {
                // 获取参数
                float2 screenUV = i.screenPos.xy/i.screenPos.w; // 屏幕UV
                float depth = SAMPLE_TEXTURE2D(_CameraDepthTexture,sampler_CameraDepthTexture,screenUV).r;
                float toSurf = LinearEyeDepth(i.positionCS.z/i.positionCS.w,_ZBufferParams); // 到物体表面的线性距离
                float3 objectOrig = TransformObjectToWorld(float3(0,0,0)); // 物体原点距离
                Light ld = GetMainLight();
                float3 sunDir = normalize(ld.direction);
                float3 ro = _WorldSpaceCameraPos; // 摄像机原点
                float3 rd = normalize(i.positionWS-ro); // 摄像机向量
                
                // 采样大气LUT的UV，x是视线与球交线弦的中点的海拔，y是射线起点处法向与光线的dot
                float3 planetCenter = objectOrig;
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
                float3 xianZhongDian = ro + rd*disSurf + rd*rayLength*0.5;
                float xiangao = (length((ro + rd*disSurf + rd*rayLength*0.5)-planetCenter)-planetRadius)/atmosHeight*1.0;
                // 需要注意的是，当我们位于大气层，此时的视线弦应该是反着来的，海拔越低越薄
                xiangao = inAtmos && step(0.0,inter2.x) ? 1.0-xiangao : xiangao;

                float guangAngle = dot(planetNor,sunDir);
                // 这里错误了，我重新做了，发现应该是弦中点处作为法向再dot才对
                guangAngle = dot(normalize(xianZhongDian-planetCenter),sunDir);
                guangAngle = inAtmos ? dot(normalize(ro-planetCenter),sunDir) : guangAngle;
                guangAngle = guangAngle*0.5 + 0.5;

                // 在黄昏线处，把彩光下压到贴近球面
                // 原理是在黄昏线的位置将u增加，避免黄昏线处底部没颜色
                float huanhun = smoothstep(_TwilightLine.x,_TwilightLine.y,guangAngle)*step(inter2.x,0.0);
                xiangao += _TwilightLine.z*pow(huanhun,_TwilightLine.w);

                // 最终UV
                float2 AtmosUV = float2(saturate(pow((xiangao+0.1),2.0)),saturate(pow(guangAngle,1.0)));
                
                // 采样LUT
                float3 AtmosLUT = SAMPLE_TEXTURE2D(_AtmosLUT,sampler_AtmosLUT,AtmosUV);
                AtmosLUT = AdjustSaturation(AtmosLUT,_Saturation);
                // 颜色转换为灰度，作为透明度
                float trans = max(0.0,dot(AtmosLUT,float3(0.299, 0.587, 0.114)));
                trans = saturate(trans*_Transparence);

                //return float4(depth*float3(1,1,1),1);
                return float4(AtmosLUT*_Brightness,trans);
            }
            ENDHLSL
        }
    }
}
