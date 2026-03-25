Shader "Unlit/cesss"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _JumpTex ("JumpTex",2D) = "black"{}
        _GravTex ("重力图",2D) = "black"{}
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
            // make fog work
            #pragma multi_compile_fog

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                UNITY_FOG_COORDS(1)
                float4 vertex : SV_POSITION;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;
            sampler2D _JumpTex;
            sampler2D _GravTex;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                UNITY_TRANSFER_FOG(o,o.vertex);
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                // sample the texture
                fixed4 col = tex2D(_MainTex, i.uv);
                fixed4 jump = tex2D(_JumpTex,i.uv*8);

                fixed vail = dot(jump,i.uv) >= 0.05 ? 0.0 : 1.0 ; 
                // apply fog
                UNITY_APPLY_FOG(i.fogCoord, col);
                fixed3 grav = tex2D(_GravTex,i.uv).xyz*2.0-1.0;


                //return fixed4(grav*0.2 + col.xyz,1);
                //return fixed4(jump.a*fixed3(1,1,1),1);
                //return fixed4(vail*fixed3(1,1,1),1);
                return fixed4(col.xyz+0.2*jump.xy,0,1);
            }
            ENDCG
        }
    }
}
