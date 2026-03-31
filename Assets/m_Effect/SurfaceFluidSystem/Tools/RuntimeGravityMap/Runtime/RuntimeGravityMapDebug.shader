Shader "Hidden/RuntimeGravityMap/DebugView"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _GravityMap ("Gravity Map", 2D) = "white" {}
        _DebugMode ("Debug Mode", Float) = 0
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;
            sampler2D _GravityMap;
            float _DebugMode;

            v2f vert (appdata v)
            {
                v2f o;
                UNITY_SETUP_INSTANCE_ID(v);
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

            // HSV到RGB转换
            float3 hsv2rgb(float3 c)
            {
                float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
                float3 p = abs(frac(c.xxx + K.xyz) * 6.0 - K.www);
                return c.z * lerp(K.xxx, saturate(p - K.xxx), c.y);
            }

            // 方向到颜色（使用HSV色轮）
            float3 DirectionToColor(float2 dir)
            {
                float angle = atan2(dir.y, dir.x);
                float hue = (angle / (2.0 * 3.14159) + 0.5);
                return hsv2rgb(float3(hue, 1.0, 1.0));
            }

            fixed4 frag (v2f i) : SV_Target
            {
                float4 gravityData = tex2D(_GravityMap, i.uv);

                // 检查是否有效区域
                if (gravityData.a < 0.1)
                {
                    return float4(0.1, 0.1, 0.1, 1);
                }

                // 根据调试模式选择显示方式
                int debugMode = (int)_DebugMode;

                if (debugMode == 0)
                {
                    // 默认模式：方向用颜色编码，强度用亮度
                    float2 flowDir = gravityData.xy;
                    float intensity = gravityData.z;

                    // 方向映射到颜色
                    float3 dirColor = DirectionToColor(flowDir);

                    // 强度调整亮度
                    float brightness = 0.3 + intensity * 0.7;
                    float3 finalColor = dirColor * brightness;

                    return float4(finalColor, 1);
                }
                else if (debugMode == 1)
                {
                    // 显示流动方向XY
                    float2 flowDir = gravityData.xy;
                    return float4(flowDir * 0.5 + 0.5, 0, 1);
                }
                else if (debugMode == 2)
                {
                    // 显示强度
                    float intensity = gravityData.z;
                    return float4(intensity, intensity, intensity, 1);
                }
                else if (debugMode == 3)
                {
                    // 显示有效区域
                    return float4(gravityData.aaa, 1);
                }
                else if (debugMode == 4)
                {
                    // 箭头可视化（简化版）
                    float2 flowDir = gravityData.xy;
                    float intensity = gravityData.z;

                    // 创建网格图案
                    float2 grid = frac(i.uv * 20);
                    float2 gridCenter = float2(0.5, 0.5);
                    float dist = length(grid - gridCenter);

                    // 绘制箭头
                    float arrow = 0;
                    if (dist < 0.4)
                    {
                        // 箭头方向
                        float2 arrowDir = flowDir;
                        float2 toCenter = normalize(gridCenter - grid);
                        float alignment = dot(toCenter, arrowDir);
                        arrow = smoothstep(0.3, 0.5, alignment) * smoothstep(0.4, 0.2, dist);
                    }

                    float3 bgColor = DirectionToColor(flowDir) * (0.3 + intensity * 0.3);
                    float3 arrowColor = float3(1, 1, 1);

                    return float4(lerp(bgColor, arrowColor, arrow), 1);
                }

                return float4(gravityData.rgb, 1);
            }
            ENDCG
        }
    }
}
