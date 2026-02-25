Shader "Unlit/InstanceCES"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            StructuredBuffer<float3> _CES;
            StructuredBuffer<int> _CES2;
            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                float isActive : TEXCOORD1;
            };

            v2f vert (appdata v, uint instanceID : SV_InstanceID)
            {
                // 每个实例都有自己的变换矩阵，直接用是错误的，我们只能直接定义世界坐标，再转换到HClip
                v2f o;
                float3 worldOffset = _CES[instanceID] ;
                //o.vertex = TransformWorldToHClip(v.vertex);
                //float3 posWS = TransformObjectToWorld(v.vertex);
                o.vertex = TransformWorldToHClip(v.vertex.xyz + worldOffset);
                o.uv = v.uv;
                o.isActive = _CES2[instanceID];
                return o;
            }

            float4 frag (v2f i, uint instanceID : SV_InstanceID) : SV_Target
            {
                float3 col = _CES2[instanceID] * float3(1,1,1);
                return float4(i.isActive,0,0,1);
            }
            ENDHLSL
        }
    }
}
