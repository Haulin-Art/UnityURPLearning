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
        
        TEXTURE2D(_ScreenMipMapDepthRT);
        SAMPLER(sampler_ScreenMipMapDepthRT);
        
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
        
        float4 FragColor(Varyings input) : SV_Target
        {
            float4 color = SAMPLE_TEXTURE2D_LOD(_ScreenMipMapRT, sampler_ScreenMipMapRT, input.uv, _MipLevel);
            return color;
        }
        
        float4 FragDepth(Varyings input) : SV_Target
        {
            float viewSpaceZ = SAMPLE_TEXTURE2D_LOD(_ScreenMipMapDepthRT, sampler_ScreenMipMapDepthRT, input.uv, _MipLevel).r;
            float linearDepth = viewSpaceZ / _ProjectionParams.z;
            return float4(linearDepth, linearDepth, linearDepth, 1.0);
        }
        
    ENDHLSL
    
    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        LOD 100
        
        Pass
        {
            Name "ColorMipMap"
            
            HLSLPROGRAM
                #pragma vertex Vert
                #pragma fragment FragColor
            ENDHLSL
        }
        
        Pass
        {
            Name "DepthMipMap"
            
            HLSLPROGRAM
                #pragma vertex Vert
                #pragma fragment FragDepth
            ENDHLSL
        }
    }
}
