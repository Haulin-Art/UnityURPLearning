Shader "Unlit/NorOutLine"
{
    Properties
    {
        _KDTex("颜色贴图",2D) = "white" {}
        _Thickness ("描边厚度",Float) = 1.0
        _LineCol ("描边颜色",Color) = (0,0,0,0)
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100
        Cull Front
        Pass
        {
            Tags { "LightMode"="UniversalForward" }

            // 这个蒙版测试用于刘海阴影
            Stencil
            {
                Ref 1
                Comp NotEqual
                Pass Keep
            }
            HLSLPROGRAM
            
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            float _Thickness;
            float3 _LineCol;

            TEXTURE2D(_KDTex);SAMPLER(sampler_KDTex);

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float4 nor :NORMAL;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                float3 nor : TEXCOORD1 ;
            };

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = TransformObjectToHClip(v.vertex + 0.01*_Thickness*v.nor);
                o.uv = v.uv;
                o.nor = TransformObjectToWorldDir(v.nor);
                return o;
            }

            float4 frag (v2f i) : SV_Target
            {
                float3 col = SAMPLE_TEXTURE2D(_KDTex,sampler_KDTex,i.uv);

                Light lg = GetMainLight();
                float3 lightDir = normalize(lg.direction);

                float lambert = saturate(dot(i.nor,lightDir));
                lambert = lerp(lambert,1.0,0.5);

                //return float4(lambert*float3(1,1,1),1.0);
                return float4(_LineCol * col * lambert,1);
            }
            ENDHLSL
        }
    }
}
