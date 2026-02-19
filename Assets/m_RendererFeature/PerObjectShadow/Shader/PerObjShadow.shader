Shader "Unlit/PerObjShadow"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
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

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_MainTex);SAMPLER(sampler_MainTex);

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };


            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = TransformObjectToHClip(v.vertex);
                return o;
            }

            float4 frag (v2f i) : SV_Target
            {
                float4 col = SAMPLE_TEXTURE2D(_MainTex,sampler_MainTex, i.uv);
                //float dep = i.vertex.z 
                return float4(i.vertex.z/4.0 ,0.0,0.0,0.0);
            }
            ENDHLSL
        }
    }
}
