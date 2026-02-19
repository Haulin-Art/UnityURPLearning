Shader "Unlit/DistanceFogPass"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _RO ("RO", Vector) = (0,0,0,0)
    }
    SubShader
    {
        Tags { 
            "RenderType"="Opaque"
            "Queue"="Overlay" 
        }
        LOD 100
        ZTest Always
        ZWrite Off
        Cull Off

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
                float4 screenPos : TEXCOORD1;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;
            
            // Unity会自动提供的深度纹理
            sampler2D _CameraDepthTexture;

            v2f vert (appdata v)
            {
                v2f o;
                o.uv = v.uv;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.screenPos = ComputeScreenPos(o.vertex);
                return o;
            }

            float4 frag (v2f i) : SV_Target
            {
                // 屏幕UV
                float2 screenUV = i.screenPos.xy / i.screenPos.w;
                
                // 采样深度纹理（Unity会自动处理多重采样纹理）
                float depth = tex2D(_CameraDepthTexture, screenUV).r;
                
                // 转换为线性深度
                float linear01Depth = Linear01Depth(depth);
                float linearWorldDepth = LinearEyeDepth(depth);

                float4 col = tex2D(_MainTex, i.uv);
                float3 newCol = tex2D(_MainTex, screenUV).rgb;

                // 远处雾气
                float fogMask = smoothstep(30.0, 80.0, linearWorldDepth);
                float3 finalCol = lerp(newCol, float3(0.7, 0.7, 0.7), fogMask);

                return float4(finalCol, 1);
            }
            ENDCG
        }
    }
}