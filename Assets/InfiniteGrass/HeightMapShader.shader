Shader "Unlit/HeightMapShader"
{
    Properties
    {
    }
    SubShader
    {
        Tags { "RenderType"="Opaque"}
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                half4 color : COLOR;
            };
            struct v2f
            {
                float2 color : TEXCOORD0;
                float4 vertex : SV_POSITION; 
            };

            // 外部变量（由C#脚本传递）：存储Y轴的“最小-最大值”范围
            float2 _BoundsYMinMax;

            // 重映射函数：将值从一个范围转换到另一个范围
            float Remap(float In, float2 InMinMax, float2 OutMinMax)
            {
                return OutMinMax.x + (In - InMinMax.x) * (OutMinMax.y - OutMinMax.x) / (InMinMax.y - InMinMax.x);
            }

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                // 计算顶点的“世界空间位置”（模型→世界空间转换）
                float4 worldPos = mul(unity_ObjectToWorld, v.vertex);
                // 红框逻辑1：把世界空间Y坐标，从_BoundsYMinMax范围映射到0~1
                float rChannel = Remap(worldPos.y, _BoundsYMinMax, float2(0, 1));
                // 红框逻辑2：取顶点颜色的R通道值，作为gChannel
                float gChannel = v.color.r;
                // 红框逻辑3：把两个值存到v2f的color里，传递给片段着色器
                o.color = float2(rChannel, gChannel);
                o.color = _BoundsYMinMax;
                return o;
            }
            float2 frag (v2f i) : SV_Target
            {
                // 直接返回顶点着色器传递来的color值，作为最终像素颜色
                return i.color;
            }
            ENDCG
        }
    }
}
