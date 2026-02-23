Shader "Unlit/NewUnlitShader"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _MainColor ("颜色",Color) = (1,1,1,1)
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            // 多编译宏：支持主光阴影（根据项目设置自动编译不同版本）
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE // 主光级联阴影（用于大场景）
            // 多编译宏：支持额外光源（点光、聚光等）
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS // 额外光源阴影
            #pragma multi_compile _ _SHADOWS_SOFT // 软阴影
            //#include "UnityCG.cginc"
            // 包含URP的核心着色器库（提供矩阵、光照、雾效等工具函数）
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            float3 _MainColor;
            struct appdata
            {
                float4 vertex : POSITION;
                float4 normal : NORMAL ; 
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                float3 worldPos :TEXCOORD2;
                float3 normal : TEXCOORD1;
            };


            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = TransformObjectToHClip(v.vertex);
                o.uv = v.uv;
                o.normal = TransformObjectToWorldNormal(v.normal);
                o.worldPos = TransformObjectToWorld(v.vertex);
                return o;
            }

            float4 frag (v2f i) : SV_Target
            {
                Light mainLight = GetMainLight(TransformWorldToShadowCoord(i.worldPos));
                float3 lightDir = normalize(mainLight.direction); // 灯光方向（从采样点指向灯光）
                float3 lightColor = mainLight.color.rgb;          // 灯光颜色
                float shadowAttenuation = mainLight.shadowAttenuation;  // 阴影衰减值（0=全阴影，1=无阴影）
                float diff = max(0,dot(i.normal,lightDir));
                return (diff*shadowAttenuation+0.1)*float4(_MainColor,1);
            }
            ENDHLSL
        }
    }
}
