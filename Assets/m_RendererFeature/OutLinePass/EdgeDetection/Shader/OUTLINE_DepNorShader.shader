Shader "Unlit/OUTLINE_DepNorShader"
{
    Properties
    {
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

            //#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal : NORMAL;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                float3 nor : TEXCOORD1;
            }; 

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = TransformObjectToHClip(v.vertex);
                o.uv = v.uv;
                o.nor = TransformObjectToWorldNormal(v.normal);
                return o;
            }



            float4 frag (v2f i) : SV_Target
            {
                float3 normal = normalize(i.nor);
                return float4(normal.xy*0.5 + 0.5,0.0,1.0);

            }
            ENDHLSL
        }
    }
}
