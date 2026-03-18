Shader "Unlit/SimpleGrass"
{
    Properties
    {
        _MainTex ("颜色纹理", 2D) = "white" {}
        _NormalTex ("法线贴图", 2D) = "bump" {}
        _RoughnessTex ("粗糙度贴图", 2D) = "white" {}
        
        [Space(15)]
        _TotalScale ("整体大小缩放", Range(0.0, 5.0)) = 1.0
        _GrassScale ("大小缩放", Vector) = (1, 1, 1, 1)
        
        [Space(15)]
        _UpCol ("草尖颜色", Color) = (1, 1, 1, 1)
        _DownCol ("草根颜色", Color) = (0, 0, 0, 0)
        _ColRamp ("颜色渐变控制", Range(-2.0, 2.0)) = 1.0
        
        [Space(15)]
        _Roughness ("粗糙度", Range(0.0, 1.0)) = 0.5
        _Metallic ("金属度", Range(0.0, 1.0)) = 0.0
    }
    SubShader
    {
        Tags { "RenderType" = "Opaque" "Queue" = "AlphaTest" }
        LOD 100
        Cull Off

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile _ _SHADOWS_SOFT
            #pragma multi_compile_fog

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal : NORMAL;
                float4 tangent : TANGENT;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                float3 normal : TEXCOORD1;
                float3 worldPos : TEXCOORD2;
                float grassHeight : TEXCOORD3;
                float3 tangent : TEXCOORD4;
                float3 bitangent : TEXCOORD5;
            };

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            float4 _MainTex_ST;

            TEXTURE2D(_NormalTex);
            SAMPLER(sampler_NormalTex);

            TEXTURE2D(_RoughnessTex);
            SAMPLER(sampler_RoughnessTex);

            CBUFFER_START(UnityPerMaterial)
                float _TotalScale;
                float3 _GrassScale;
                float3 _UpCol;
                float3 _DownCol;
                float _ColRamp;
                float _Roughness;
                float _Metallic;
            CBUFFER_END

            StructuredBuffer<float3> _GrassPositions;
            int _Grass_Instance_Offset;

            v2f vert(appdata v, uint instanceID : SV_InstanceID)
            {
                v2f o;

                v.vertex.xyz *= _GrassScale * _TotalScale;
                float height = v.vertex.y;

                float3 worldOffset = _GrassPositions[instanceID + _Grass_Instance_Offset];

                float3 worldPos = worldOffset + v.vertex.xyz;

                o.vertex = TransformWorldToHClip(worldPos);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.normal = TransformObjectToWorldNormal(v.normal);
                o.worldPos = worldPos;
                o.grassHeight = saturate(height);
                o.tangent = TransformObjectToWorldDir(v.tangent.xyz);
                o.bitangent = cross(o.normal, o.tangent) * v.tangent.w;

                return o;
            }

            float4 frag(v2f i) : SV_Target
            {
                float4 albedo = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv);

                float3 normalTS = UnpackNormal(SAMPLE_TEXTURE2D(_NormalTex, sampler_NormalTex, i.uv));
                float3x3 TBN = float3x3(i.tangent, i.bitangent, i.normal);
                float3 normal = TransformTangentToWorld(normalTS, TBN);
                normal = normalize(normal);

                float roughness = SAMPLE_TEXTURE2D(_RoughnessTex, sampler_RoughnessTex, i.uv).r * _Roughness;

                float3 grassCol = lerp(_DownCol, _UpCol, i.grassHeight * _ColRamp);
                albedo.rgb = saturate(albedo.rgb*2.0);
                albedo.rgb *= grassCol;

                Light mainLight = GetMainLight(TransformWorldToShadowCoord(i.worldPos));
                float3 lightDir = normalize(mainLight.direction);
                float3 lightColor = mainLight.color.rgb;
                float shadowAttenuation = mainLight.shadowAttenuation;

                float3 viewDir = normalize(_WorldSpaceCameraPos - i.worldPos);
                float3 halfDir = normalize(lightDir + viewDir);

                float NdotL = max(0.0, dot(normal, lightDir));
                NdotL = lerp(1.0,NdotL,0.5);
                float NdotH = max(0.0, dot(normal, halfDir));

                float3 ambient = 0.1;
                float3 diffuse = albedo.rgb * lightColor * NdotL * (shadowAttenuation + ambient);

                float specularPower = lerp(256.0, 16.0, roughness);
                float specular = pow(NdotH, specularPower);
                float3 spec = specular * lightColor * (1.0 - roughness);

                float3 finalColor = diffuse + spec;

                return float4(finalColor, 1.0);
            }
            ENDHLSL
        }
    }
}
