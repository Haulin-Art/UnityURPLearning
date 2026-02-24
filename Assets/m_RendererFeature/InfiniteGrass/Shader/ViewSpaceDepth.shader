Shader "Unlit/ViewSpaceDepth"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            
            struct Attributes
            {
                float4 positionOS : POSITION;
                float4 normal : NORMAL ;
            };
            
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float depthVS : TEXCOORD0;
            };
            
            Varyings vert(Attributes input)
            {
                Varyings output;
                //input.positionOS.xyz -= 0.05 * input.normal.xyz;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 positionVS = TransformWorldToView(positionWS);
                output.depthVS = positionVS.z; // 摄像机空间的Z坐标（原始线性深度）
                return output;
            }
            
            float frag(Varyings input) : SV_Target
            {
                return input.depthVS;
            }
            ENDHLSL
        }
    }
}
