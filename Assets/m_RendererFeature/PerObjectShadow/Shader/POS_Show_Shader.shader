Shader "Unlit/POS_Show_Shader"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "black" {}
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                float4 screenPos :TEXCOORD4;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;
            sampler2D _POSMap;
            sampler2D _POSpcf;
            sampler2D _CSShadow;
            sampler2D _CES;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.screenPos = ComputeScreenPos(o.vertex);
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                // sample the texture
                float2 screenUV = i.screenPos.xy / i.screenPos.w;
                fixed4 col = tex2D(_POSMap, i.uv).r;
                //col = tex2D(_CSPCF, screenUV);
                // apply fog
                return col*float4(1,1,1,1);
            }
            ENDCG
        }
    }
}
