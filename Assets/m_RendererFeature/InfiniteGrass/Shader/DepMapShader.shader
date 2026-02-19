Shader "InfiniteGrass/HeightMapShader"
{
    Properties
    {
    }
    SubShader
    {
        Tags { 
            "RenderType"="Opaque"
        }

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
                float4 vertex : SV_POSITION;
                float2 color : TEXCOORD0;
            };
            
            float2 _BoundsYMinMax;

            float Remap(float In, float2 InMinMax, float2 OutMinMax)
            {
                return OutMinMax.x + (In - InMinMax.x) * 
                    (OutMinMax.y - OutMinMax.x) / 
                    (InMinMax.y - InMinMax.x);
            }// 即 归一化输出 = 输出最小值 + (输入 - 输入最小值) * (输出最大值 - 输出最小值) / (输入最大值 - 输入最小值)

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);

                float3 worldPos = mul(unity_ObjectToWorld, v.vertex);

                float rChannel = Remap(worldPos.y, _BoundsYMinMax, float2(0, 1)); //We store here the altitude
                float gChannel = v.color.r; //We store here the mask from the RED in the vertex color

                o.color = float2(rChannel, step(0.001,rChannel));

                return o;
            }

            float2 frag (v2f i) : SV_Target
            {
                return i.color;
            }
            ENDCG
        }
    }
}
