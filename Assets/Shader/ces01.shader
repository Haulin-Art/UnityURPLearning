Shader "Custom/ces01"
{
    Properties
    {
        _Color("Color Tint",Color)=(1.0,1.0,1.0,1.0)
    }
    SubShader
    {
        Pass{
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag 

            #include "UnityCG.cginc"
            #include "Lighting.cginc"

            fixed4 _Color;

            struct a2v
            {
                float4 vertex:POSITION;//模型空间的顶点坐标
                float3 normal:NORMAL;//该模型的顶点法向信息
                float4 texcoord:TEXCOORD0;//该模型的的第一套纹理坐标
                // 结构体内的变量书写格式：
                // Type Name:Semantic;（类型 名称：语义；）
                // unity支持的语义有：POSITION,NORMAL,TANGENT,TEXCOORD0....等等
                // 这些语义由该材质的Mesh Render组件提供
            };
            struct v2f
            {
                float4 pos:SV_POSITION;// 裁切空间位置的语义
                fixed3 color:COLOR0;// 颜色的语义
            };

            v2f vert(a2v v)//使用结构体不用声明返回的语义，因为结构体内已经声明
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.color = v.normal *0.5 + fixed3(0.5,0.5,0.5);
                return o;
            }
            fixed4 frag(v2f i):SV_Target
            {
                return fixed4(_Color.rgb,1);
            }
            ENDCG
        }
    }
}

