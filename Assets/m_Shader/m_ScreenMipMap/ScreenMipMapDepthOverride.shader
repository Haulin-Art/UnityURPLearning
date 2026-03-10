Shader "Hidden/ScreenMipMap/DepthOverride"
{
    Properties
    {
    }
    
    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        LOD 100
        ColorMask R
        ZTest LEqual
        ZWrite On
        Cull Off
        
        Pass
        {
            HLSLPROGRAM
                #pragma vertex Vert
                #pragma fragment Frag
                
                #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
                
                struct Attributes
                {
                    float4 positionOS : POSITION;
                };
                
                struct Varyings
                {
                    float4 positionCS : SV_POSITION;
                    float viewSpaceZ : TEXCOORD0;
                };
                
                Varyings Vert(Attributes input)
                {
                    Varyings output;
                    
                    float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                    output.positionCS = TransformWorldToHClip(positionWS);
                    
                    float3 viewPos = TransformWorldToView(positionWS);
                    output.viewSpaceZ = -viewPos.z;
                    
                    return output;
                }
                
                float Frag(Varyings input) : SV_Target
                {
                    return input.viewSpaceZ;
                }
            ENDHLSL
        }
    }
}
