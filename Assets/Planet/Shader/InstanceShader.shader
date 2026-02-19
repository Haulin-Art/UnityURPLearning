Shader "Custom/InstanceShader"
{
    Properties
    {
        _Color ("Color", Color) = (1,1,1,1)
        _Radius ("Radius", Float) = 5.0
        [Toggle] _UseLighting ("Use Lighting", Float) = 1
    }
    
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100
        
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #pragma instancing_options procedural:setup
            
            #include "UnityCG.cginc"
            #include "Lighting.cginc"
            
            struct InstanceData
            {
                float3 position;
                float3 forward;
                float3 right;
                float3 up;
                float scale;
                int isVisible;
            };
            
            StructuredBuffer<InstanceData> _InstanceBuffer;
            
            struct appdata
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float2 uv : TEXCOORD0;
                uint instanceID : SV_InstanceID;
            };
            
            struct v2f
            {
                float4 vertex : SV_POSITION;
                float3 worldPos : TEXCOORD0;
                float3 worldNormal : TEXCOORD1;
                float2 uv : TEXCOORD2;
            };
            
            float4 _Color;
            float _Radius;
            float _UseLighting;
            
            v2f vert (appdata v, uint instanceID : SV_InstanceID)
            {
                v2f o;
                
                // 从缓冲区获取实例数据
                InstanceData data = _InstanceBuffer[instanceID];
                
                // 构建变换矩阵
                float3x3 rotationMatrix = float3x3(data.right, data.up, data.forward);
                
                // 应用实例变换
                float3 worldPos = mul(rotationMatrix, v.vertex.xyz * data.scale) + data.position;
                
                // 转换到裁剪空间
                o.vertex = UnityObjectToClipPos(float4(worldPos, 1.0));
                o.worldPos = worldPos;
                o.worldNormal = mul(rotationMatrix, v.normal);
                o.uv = v.uv;
                
                return o;
            }
            
            // Unity需要这个函数用于实例化设置
            void setup()
            {
            }
            
            fixed4 frag (v2f i) : SV_Target
            {
                // 基础颜色
                fixed4 col = _Color;
                
                // 简单的照明
                if (_UseLighting > 0.5)
                {
                    float3 lightDir = normalize(_WorldSpaceLightPos0.xyz);
                    float3 normal = normalize(i.worldNormal);
                    float diff = max(0, dot(normal, lightDir));
                    
                    // 环境光 + 漫反射
                    col.rgb *= (0.3 + 0.7 * diff);
                }
                
                // 基于到球心的距离添加一些变化
                float dist = length(i.worldPos);
                float t = saturate(dist / _Radius);
                col.rgb = lerp(col.rgb, col.rgb * 1.2, t);
                
                return col;
            }
            ENDCG
        }
    }
    FallBack "Diffuse"
}