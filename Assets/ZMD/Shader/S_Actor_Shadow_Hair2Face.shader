Shader "Unlit/S_Actor_Shadow_Hair2Face"
{
    Properties
    {
        _ShadowCol ("阴影颜色",Color) = (0.5,0.5,0.5,0.5)
    }
    SubShader
    {
        // 这里这个渲染循序设置在头发前，同时关闭深度写入，就能直接让头发将其覆盖
        Tags { "RenderType"="Transparent" "Queue"="Transparent-20" }
        LOD 100

        // 检测面部的蒙版层，只在有面部的区域显示
        Stencil
        {
            Ref 2
            Comp Equal
            Pass Keep
        }

        Pass
        {
            Tags{"LightMode" = "UniversalForward"}
            Blend DstColor Zero

            ZWrite Off

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
                //float4 col = tex2D(_MainTex, i.uv);
                return float4(_ShadowCol,1.0);
            }
            ENDHLSL
        }
    }
}
