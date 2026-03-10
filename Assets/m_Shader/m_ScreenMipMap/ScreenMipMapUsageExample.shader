Shader "Example/ScreenMipMapUsage"
{
    Properties
    {
        _MipLevel ("Mip Level", Range(0, 8)) = 0
    }
    
    HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        
        TEXTURE2D(_ScreenMipMapRT);
        SAMPLER(sampler_ScreenMipMapRT);
        
        float _MipLevel;
        
        struct Attributes
        {
            float4 positionOS : POSITION;
            float2 uv : TEXCOORD0;
        };
        
        struct Varyings
        {
            float4 positionCS : SV_POSITION;
            float2 uv : TEXCOORD0;
        };
        
        Varyings Vert(Attributes input)
        {
            Varyings output;
            output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
            output.uv = input.uv;
            return output;
        }
        
        float4 Frag(Varyings input) : SV_Target
        {
            float4 color = SAMPLE_TEXTURE2D_LOD(_ScreenMipMapRT, sampler_ScreenMipMapRT, input.uv, _MipLevel);
            return color;
        }
        
    ENDHLSL
    
    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        LOD 100
        
        Pass
        {
            HLSLPROGRAM
                #pragma vertex Vert
                #pragma fragment Frag
            ENDHLSL
        }
    }
}
