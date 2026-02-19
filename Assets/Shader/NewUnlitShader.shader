Shader "Unlit/NewUnlitShader"
{
    Properties
    {
        //_MainTex ("Texture", 2D) = "white" {}
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100
        Cull Back
        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            // make fog work

            //#include "UnityCG.cginc"
            //#include "Lighting.cginc"
            //#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

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


            //sampler2D _MainTex;
            //float4 _MainTex_ST;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = TransformObjectToHClip(v.vertex.xyz);
                return o;
            }

            float4 frag (v2f i) : SV_Target
            {
                float4 col = float4(1,1,1,1);

                return col;
            }
            ENDHLSL
        }
    }
}
