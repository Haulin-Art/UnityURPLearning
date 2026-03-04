Shader "Unlit/ulit"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _GradientTex ("梯度图", 2D) = "white" {}
        _VDMTex ("矢量置换图", 2D) = "blue" {}
        _CESFloat ("测试",Range(0.0,1.0)) = 0.0
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
            sampler2D _HeightTex;
            float4 _HeightTex_ST;
            sampler2D _VDMTex;
            float4 _VDMTex_ST;
            sampler2D _GradientTex;
            float4 _GradientTex_ST;

            float _CESFloat;

            float2 animUV(float2 uv,float time)
            {
                float _Speed = 0.1;

                float w = 0.01;
                float2 newUV = uv;//uv*uv_ST.xy + uv_ST.zw;
                float nu = frac(newUV.x - time*_Speed);
                //nu += -_sineScale * sin(((worldXZ.y - time*_Speed)*2.0 - 1.0) * PI*_SineCount);
                nu = clamp(frac(nu),w,1.0-w);
                float nv = pow(abs(frac(newUV.y)-0.5),0.97);
                nv = -1.0*clamp(uv.x*1.5 - nv,w,1.0-w);
                newUV = float2(nu,nv);
                return newUV;
            }

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
                fixed col = tex2D(_MainTex, i.uv).x;
                fixed cr = tex2D(_MainTex, i.uv+float2(0.01,0)).x;
                fixed2 gradient = tex2D(_GradientTex, i.uv).xy;
                //fixed2 gr = tex2D(_GradientTex, i.uv+float2(0.03,0)).xy;
                //fixed2 gu = tex2D(_GradientTex, i.uv+float2(0.0,0.03)).xy;
                //gradient = (gradient+gr+gu)/3.0;
                //gradient = gradient*0.5+0.5;
                fixed yy = frac((gradient.x+gradient.y)*5.0);
                yy = frac(5*abs(gradient.y))*frac(abs(gradient.x));
                yy = frac(5*abs(gradient.x));
                yy = pow(yy,1.0/3);
                //yy *= smoothstep(0.1,0.05,-col);
                yy = pow(yy,3.0);
                fixed xx = frac((col-0*_Time.y/10.0)*20.0);
                fixed yyy = pow(1-saturate(col*8.0),2.0);
                fixed2 uuvv = fixed2(xx,yy);
                fixed2 newuv = animUV(uuvv,_Time.y);
                //uuvv = clamp(uuvv,0.001,0.999);

                fixed3 dis = tex2D(_VDMTex,uuvv);
                // apply fog
                UNITY_APPLY_FOG(i.fogCoord, col);
                //return fixed4(frac(abs(gradient.y))*frac(abs(gradient.x)),0,0,1);
                //return fixed4(smoothstep(0.1,0.04,-col),0,0,1);
                return fixed4(dis*fixed3(1,1,1),1);
                return frac((col+_Time.y/10.0)*20.0)*fixed4(1,1,1,1);
            }
            ENDCG
        }
    }
}
