Shader "Unlit/depthces"
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
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                float4 screenPos : TEXCOORD6;
            };

            //TEXTURE2D(_CameraDepthTexture);SAMPLER(sampler_CameraDepthTexture); 

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = TransformObjectToHClip(v.vertex);
                o.uv = v.uv;
                o.screenPos = ComputeScreenPos(o.vertex);
                return o;
            }

            float4 frag (v2f i) : SV_Target
            {
                float2 screenUV = i.screenPos.xy / i.screenPos.w;
                //float depth = SAMPLE_TEXTURE2D(_CameraDepthTexture,sampler_CameraDepthTexture,screenUV).r;
                float depth = SampleSceneDepth(screenUV);
                return float4(depth*float3(1,1,1),1.0);
            }
            ENDHLSL
        }
    }
}
