Shader "PBDClothTearing/Display"
{
    Properties
    {
        _MainTex ("Fabric Texture / 布料纹理", 2D) = "white" {}
        _HoleTex ("Hole Map / 空洞图", 2D) = "black" {}
        _PosTex ("Position Map / 位置图", 2D) = "gray" {}

        [Header(Edge Highlight)]
        _EdgeColor ("Edge Color / 边缘颜色", Color) = (1, 1, 1, 1)
        _EdgeWidth ("Edge Width / 边缘宽度", Range(0, 10)) = 3

        [Header(Displacement)]
        _DispScale ("Displacement Scale / 位移缩放", Range(0, 10)) = 1

        [Header(Normal)]
        _NormalStrength ("Normal Strength / 法线强度", Range(0, 5)) = 1

        [Space(15)]
        _FactorA ("Factor A", Range(0, 1)) = 0.0
        _FactorB ("Factor B", Range(0, 1)) = 1.0
        [Enum(Hole,0,Position,1,Displacement,2,FullRender,3)]
        _DisplayMode ("Display Mode / 显示模式", Float) = 3

    }

    SubShader
    {
        Tags { "RenderType"="Opaque"
               "RenderPipeline"="UniversalPipeline"}
        Cull Off

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
            TEXTURE2D(_PosTex);  SAMPLER(sampler_PosTex);

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

                // ── 空洞场 / hole map ──
                float2 hole = SAMPLE_TEXTURE2D(_HoleTex, sampler_HoleTex, uv).rg;

                // ── 位置场（质点当前 UV 坐标）/ position map（current particle UV）──
                float2 pos = SAMPLE_TEXTURE2D(_PosTex, sampler_PosTex, uv).rg;

                // ── 位移：当前位置 - 原始UV / displacement: current - original ──
                float2 disp = pos - uv;

                // ── UV 扭曲（材料堆积效果）/ UV warp（material bunching）──
                // 使用近似逆映射：uv - disp * scale
                float2 warpedUV = uv - disp * _DispScale;

                // ── 采样布料纹理 / sample fabric texture ──
                half4 tex = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, warpedUV);

                // ── 空洞梯度 → 边缘高亮 / hole gradient → edge highlight ──
                float h_l = SAMPLE_TEXTURE2D(_HoleTex, sampler_HoleTex, uv - float2(h, 0)).r;
                float h_r = SAMPLE_TEXTURE2D(_HoleTex, sampler_HoleTex, uv + float2(h, 0)).r;
                float h_d = SAMPLE_TEXTURE2D(_HoleTex, sampler_HoleTex, uv - float2(0, h)).r;
                float h_u = SAMPLE_TEXTURE2D(_HoleTex, sampler_HoleTex, uv + float2(0, h)).r;
                float2 holeGrad = float2(h_r - h_l, h_u - h_d);
                float edge = saturate(length(holeGrad) * _EdgeWidth);

                // ── 位移梯度 → 法线 / displacement gradient → normal ──
                float2 p_l = SAMPLE_TEXTURE2D(_PosTex, sampler_PosTex, uv - float2(h, 0)).rg;
                float2 p_r = SAMPLE_TEXTURE2D(_PosTex, sampler_PosTex, uv + float2(h, 0)).rg;
                float2 p_d = SAMPLE_TEXTURE2D(_PosTex, sampler_PosTex, uv - float2(0, h)).rg;
                float2 p_u = SAMPLE_TEXTURE2D(_PosTex, sampler_PosTex, uv + float2(0, h)).rg;
                float2 dispGrad = float2(length(p_r - p_l), length(p_u - p_d)) * _NormalStrength * 50.0;
                float3 normal = normalize(float3(-dispGrad, 1.0));

                // ── 简单漫反射光 / simple diffuse lighting ──
                float3 lightDir = normalize(float3(0.5, 0.8, 1.0));
                float NdotL = saturate(dot(normal, lightDir));
                float3 ambient = float3(0.15, 0.15, 0.2);

                // ── 合成 / compose ──
                float3 baseColor = tex.rgb * (ambient + NdotL);
                float3 rimColor = _EdgeColor.rgb * edge;
                float3 finalColor = baseColor + rimColor;

                // ── 空洞区域变暗 / darken hole regions ──
                float alphaMod = 1.0 - smoothstep(0.5, 0.95, hole.x);
                finalColor *= lerp(0.3, 1.0, alphaMod);

                // ── 调试显示模式 / debug display modes ──
                if (_DisplayMode == 0)
                {
                    // 空洞遮罩 / hole mask
                    return float4(float3(1,1,1) * smoothstep(_FactorA, _FactorB, hole.x), 1);
                }
                else if (_DisplayMode == 1)
                {
                    // 位置场 / position map
                    return float4(pos, 0, 1);
                }
                else if (_DisplayMode == 2)
                {
                    // 位移场 / displacement
                    float dispMag = length(disp) * 50.0;
                    return float4(dispMag, -dispMag, 0, 1);
                }
                else
                {
                    // 完整渲染 / full render
                    return float4(finalColor, 1);
                }
            }
            ENDHLSL
        }
    }
}
