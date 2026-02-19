Shader "Unlit/S_Actor_Shadow_Eye"
{
    Properties
    {
        _ShadowCol ("阴影颜色",Color) = (1.0,1.0,1.0,1.0)
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent+20" }
        LOD 100

        Pass
        {
            Tags{"LightMode" = "UniversalForward"}
            Blend DstColor Zero

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            
            float3 _ShadowCol;
            
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
                o.uv = v.uv;
                return o;
            }

            float4 frag (v2f i) : SV_Target
            {
                float gradient = saturate(1.0 - i.uv.y*1.5);
                gradient = saturate(gradient);
                //gradient = pow(saturate(gradient),2.0);
                return float4(_ShadowCol*gradient,1.0);
            }
            ENDHLSL
        }
    }
}
