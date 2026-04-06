Shader "Hidden/Voronoi3DPreview"
{
    Properties
    {
        _VolumeTex ("Volume Texture", 3D) = "" {}
        _Slice ("Slice", Range(0, 1)) = 0.5
        _Channel ("Channel", Int) = 0
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
            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
                float3 texcoord : TEXCOORD0;
            };

            sampler3D _VolumeTex;
            float _Slice;
            int _Channel;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.texcoord = float3(v.uv, _Slice);
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                float4 value = tex3D(_VolumeTex, i.texcoord);
                
                if (_Channel == 0)
                    return fixed4(value.r, value.r, value.r, 1.0);
                else if (_Channel == 1)
                    return fixed4(value.g, value.g, value.g, 1.0);
                else if (_Channel == 2)
                    return fixed4(value.b, value.b, value.b, 1.0);
                else
                    return fixed4(value.a, value.a, value.a, 1.0);
            }
            ENDCG
        }
    }
}
