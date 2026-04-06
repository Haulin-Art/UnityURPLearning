Shader "Unlit/FinalAtmosSkyBox"
{
    Properties
    {
        [Header(Environment)]
        _EnvPanoramic ("环境反射全景贴图",2D ) = "white" {}
        _PanoramicRotation ("全景贴图旋转角度", Range(0.0, 1.0)) = 0.0
        [Header(Cloud)]
        _CloudData ("云数据", 2D) = "white" {}
        _CloudAlpha ("云混合系数", Range(0.0, 1.0)) = 0.5
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
            

            TEXTURE2D(_EnvPanoramic);SAMPLER(sampler_EnvPanoramic);
            TEXTURE2D(_CloudData);SAMPLER(sampler_CloudData);
        
            CBUFFER_START(UnityPerMaterial)

                float _PanoramicRotation;
                float _CloudAlpha;

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
                
                // 基础数据
                Light mainLight = GetMainLight();
                float3 sunDir = mainLight.direction;
                float3 sunColor = mainLight.color;
                float3 ro = _WorldSpaceCameraPos;
                float3 rd = normalize(i.viewDir);
                float2 screenUV = i.screenPos.xy/i.screenPos.w;


                float3 envColor = SAMPLE_TEXTURE2D(_EnvPanoramic, sampler_EnvPanoramic, DirToPanoramicUV(-rd)).xyz;
                float2 cloudData = SAMPLE_TEXTURE2D(_CloudData, sampler_CloudData, screenUV).xy;
                float3 cloudColor = cloudData.x * sunColor;
                float cloudAlpha = cloudData.y;

                float3 mixColor = manualLerp(manualLerp(cloudColor,envColor.xyz,_CloudAlpha),envColor, smoothstep(0.6,1.0,cloudAlpha));
                return float4(mixColor, 1.0); 
            }
            ENDHLSL
        }
    }
    FallBack Off
}
