Shader "ElasticTearing/Display"
{
    Properties
    {
        _MainTex ("Fabric Texture", 2D) = "white" {}
        _HoleTex ("Hole", 2D) = "black" {}
        _DispTex ("Displacement", 2D) = "gray" {}

        [Header(Edge Highlight)]
        _EdgeColor ("Edge Color", Color) = (1, 1, 1, 1)
        _EdgeWidth ("Edge Width", Range(0, 10)) = 3

        [Header(Displacement)]
        _DispScale ("Displacement Scale", Range(0, 10)) = 1

        [Header(Normal)]
        _NormalStrength ("Normal Strength", Range(0, 5)) = 1

        [Space(15)]
        _FactorA ("Factor A", Range(0, 1)) = 0.0
        _FactorB ("Factor B", Range(0, 1)) = 1.0
        [Enum(hole,0,tensileForce,1,disp,2,velocity,3)]
        _DisplayMode ("Display Mode", Float) = 0
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" 
               "RenderPipeline"="UniversalPipeline"}
        //Blend SrcAlpha OneMinusSrcAlpha
        Cull Off
        //ZWrite Off

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 4.5

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
            };

            TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);
            TEXTURE2D(_HoleTex); SAMPLER(sampler_HoleTex);
            TEXTURE2D(_DispTex); SAMPLER(sampler_DispTex);

            float4 _MainTex_ST;
            float4 _EdgeColor;
            float  _EdgeWidth;
            float  _DispScale;
            float  _NormalStrength;
            float  _TexSize;

            float  _FactorA;
            float  _FactorB;
            int    _DisplayMode;

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.uv = IN.uv;
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                float2 uv = IN.uv;
                float h = 1.0 / _TexSize;

                // 空洞场
                float2 hole = SAMPLE_TEXTURE2D(_HoleTex, sampler_HoleTex, uv);

                // 位移场
                float4 disp = SAMPLE_TEXTURE2D(_DispTex, sampler_DispTex, uv);

                // UV 偏移（空洞边缘材料堆积的效果）
                float2 warpedUV = uv + disp.xy * _DispScale * h * 50.0;

                // 采面料纹理
                half4 tex = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, warpedUV);

                // 空洞梯度 → 边缘高亮
                float h_l = SAMPLE_TEXTURE2D(_HoleTex, sampler_HoleTex, uv - float2(h, 0)).r;
                float h_r = SAMPLE_TEXTURE2D(_HoleTex, sampler_HoleTex, uv + float2(h, 0)).r;
                float h_d = SAMPLE_TEXTURE2D(_HoleTex, sampler_HoleTex, uv - float2(0, h)).r;
                float h_u = SAMPLE_TEXTURE2D(_HoleTex, sampler_HoleTex, uv + float2(0, h)).r;
                float2 holeGrad = float2(h_r - h_l, h_u - h_d);
                float edge = saturate(length(holeGrad) * _EdgeWidth);

                // 位移梯度 → 重建法线
                float2 u_l = SAMPLE_TEXTURE2D(_DispTex, sampler_DispTex, uv - float2(h, 0)).rg;
                float2 u_r = SAMPLE_TEXTURE2D(_DispTex, sampler_DispTex, uv + float2(h, 0)).rg;
                float2 u_d = SAMPLE_TEXTURE2D(_DispTex, sampler_DispTex, uv - float2(0, h)).rg;
                float2 u_u = SAMPLE_TEXTURE2D(_DispTex, sampler_DispTex, uv + float2(0, h)).rg;
                float2 dispGrad = float2(length(u_r - u_l), length(u_u - u_d)) * _NormalStrength * 50.0;
                float3 normal = normalize(float3(-dispGrad, 1.0));

                // 简单漫反射光
                float3 lightDir = normalize(float3(0.5, 0.8, 1.0));
                float NdotL = saturate(dot(normal, lightDir));
                float3 ambient = float3(0.15, 0.15, 0.2);

                // 合成
                float3 baseColor = tex.rgb * (ambient + NdotL);
                float3 rimColor = _EdgeColor.rgb * edge;
                float3 finalColor = baseColor + rimColor;

                // 空洞区域变暗（保留半透明细线可见: smoothstep 阈值为 0.5~0.95）
                float alphaMod = 1.0 - smoothstep(0.5, 0.95, hole.x);
                finalColor *= lerp(0.3, 1.0, alphaMod);

                //return float4(abs(disp),0,1);
                if (_DisplayMode == 0)
                {
                    return float4(float3(1,1,1)*smoothstep(_FactorA,_FactorB,hole.x),1);
                }
                else if (_DisplayMode == 1)
                {
                    return float4(float3(1,1,1)*hole.y,1);
                }
                else if (_DisplayMode == 2)
                {
                    return float4(disp.xy,0,1);
                }
                else if (_DisplayMode == 3)
                {
                    return float4(normalize(disp.xy-disp.zw),0,1);
                }
                else
                {
                    return float4(float3(1,1,1),1);
                }
            }
            ENDHLSL
        }
    }
}
