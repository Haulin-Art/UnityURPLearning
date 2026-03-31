Shader "SurfaceFluidSystem/SurfFluid_Template"
{
    Properties
    {
        _BaseMap ("基础纹理", 2D) = "white" {}
        _BaseColor ("基础颜色", Color) = (1, 1, 1, 1)
        
        _JumpMap ("跳跃纹理", 2D) = "black" {}
        _FluidTex ("流体数据 (RG=速度, B=高度)", 2D) = "black" {}
        _NormalTex ("法线图", 2D) = "blue" {}
        
        _NormalStrength ("法线强度", Range(0.0, 2.0)) = 1.0
        _Smoothness ("基础光滑度", Range(0.0, 1.0)) = 0.5
        _WaterSmoothness ("水面光滑度", Range(0.0, 1.0)) = 0.9
        _WaterTrans ("水体透射率", Range(0.0,5.0)) = 1.0
        _Metallic ("金属度", Range(0.0, 1.0)) = 0.0
        
        [Enum(None, 0, Lighting, 1, Height, 2, Velocity, 3, Normal, 4)] 
        _DebugMode ("调试模式", Float) = 1
    }
    
    SubShader
    {
        Tags 
        { 
            "RenderType" = "Opaque" 
            "RenderPipeline" = "UniversalPipeline" 
        }
        LOD 100

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            // URP光照变体
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fog
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
                float4 tangentWS : TEXCOORD3;
                float fogFactor : TEXCOORD4;
            };

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);
            
            TEXTURE2D(_FluidTex);
            SAMPLER(sampler_FluidTex);
            
            TEXTURE2D(_NormalTex);
            SAMPLER(sampler_NormalTex);

            TEXTURE2D(_JumpMap);
            SAMPLER(sampler_JumpMap);   

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                float4 _BaseColor;
                float _NormalStrength;
                float _Smoothness;
                float _WaterSmoothness;
                float _WaterTrans;
                float _Metallic;
                float _DebugMode;
            CBUFFER_END

            Varyings vert(Attributes input)
            {
                Varyings output = (Varyings)0;
                
                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);
                
                output.positionCS = vertexInput.positionCS;
                output.positionWS = vertexInput.positionWS;
                output.normalWS = normalInput.normalWS;
                
                // 副切线
                real sign = input.tangentOS.w * GetOddNegativeScale();
                output.tangentWS = float4(normalInput.tangentWS.xyz, sign);
                
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                output.fogFactor = ComputeFogFactor(vertexInput.positionCS.z);
                
                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                // ========== 跳跃处理 ==========
                half4 jumpData = SAMPLE_TEXTURE2D(_JumpMap, sampler_JumpMap, input.uv);

                if (jumpData.a < 0.5) discard; // 没有跳跃数据的像素直接丢弃

                // 采样流体数据
                half4 fluidData = SAMPLE_TEXTURE2D(_FluidTex, sampler_FluidTex, input.uv);
                half2 velocity = fluidData.rg;
                half height = fluidData.b;
                half hasWater = smoothstep(0.001, 0.01, saturate(height));
                
                // 采样基础纹理
                half4 baseColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv) * _BaseColor;
                
                // 解码法线（从[0,1]映射到[-1,1]）
                half3 normalTS = SAMPLE_TEXTURE2D(_NormalTex, sampler_NormalTex, input.uv).rgb;
                normalTS = normalTS * 2.0 - 1.0;
                normalTS.xy *= _NormalStrength;
                normalTS = normalize(normalTS);
                
                // 构建TBN矩阵
                float sgn = input.tangentWS.w;
                float3 bitangent = sgn * cross(input.normalWS.xyz, input.tangentWS.xyz);
                float3x3 tangentToWorld = float3x3(input.tangentWS.xyz, bitangent.xyz, input.normalWS.xyz);
                half3 normalWS = TransformTangentToWorld(normalTS, tangentToWorld);
                normalWS = normalize(normalWS);
                

                


                // ========== 调试模式 ==========
                // None(0): 直接输出基础纹理
                if (_DebugMode < 0.5)
                {
                    return baseColor;
                }
                // Height(2): 显示高度数据
                else if (_DebugMode > 1.5 && _DebugMode < 2.5)
                {
                    half h = height * 0.5 + 0.5;
                    h = height;
                    return half4(h, h, h, 1.0);
                }
                // Velocity(3): 显示速度数据
                else if (_DebugMode > 2.5 && _DebugMode < 3.5)
                {
                    return half4(velocity * 0.5 + 0.5, 0.0, 1.0);
                }
                // Normal(4): 显示法线数据
                else if (_DebugMode > 3.5)
                {
                    return half4(normalTS * 0.5 + 0.5, 1.0);
                }
                
                // ========== Lighting(1): URP标准PBR光照 ==========
                
                // 构建InputData
                InputData inputData = (InputData)0;
                inputData.positionWS = input.positionWS;
                inputData.normalWS = normalWS;
                inputData.viewDirectionWS = GetWorldSpaceNormalizeViewDir(input.positionWS);
                inputData.shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                inputData.fogCoord = input.fogFactor;
                inputData.bakedGI = SampleSH(input.normalWS);
                inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(input.positionCS);
                
                // 构建SurfaceData
                float3 water_albedo = lerp(baseColor.rgb,float3(1.0,0.0,0.0), 1.0-exp(-abs(height)*_WaterTrans));
                SurfaceData surfaceData = (SurfaceData)0;
                surfaceData.albedo = lerp(baseColor.rgb, water_albedo, hasWater);
                surfaceData.alpha = baseColor.a;
                surfaceData.metallic = _Metallic;
                // 有水的地方光滑度更高（更光滑，高光更集中）
                surfaceData.smoothness = lerp(_Smoothness, _WaterSmoothness, hasWater);
                surfaceData.normalTS = normalTS;
                
                // URP标准PBR光照计算
                half4 color = UniversalFragmentPBR(inputData, surfaceData);
                
                // 应用雾效
                color.rgb = MixFog(color.rgb, inputData.fogCoord);
                

                return color;
                //return float4(color.rgb*lerp(1.0,0.2,step(0.0001,jumpData.z*(1.0-jumpData.w))), color.a);
            }
            ENDHLSL
        }
        
        // 阴影投射Pass
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"

            ENDHLSL
        }
        
        // 深度Pass
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }

            ZWrite On
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthOnlyPass.hlsl"

            ENDHLSL
        }
    }
    
    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}
