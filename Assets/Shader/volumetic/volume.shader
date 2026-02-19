Shader "Custom/VisibleVolumeRaymarching"
{
    Properties
    {
        _VolumeSize ("VolumScale", Vector) = (1,1,1,0)  // 关键：和物体缩放一致
        _BaseDensity ("Density", Float) = 0.2          // 增大默认密度，避免太透明
        _StepCount ("step", Int) = 40                     // 足够采样次数
        _StepSize ("stepsize", Float) = 0.08                  // 小步长确保采样充分
        _VolumeColor ("color", Color) = (0.2, 0.8, 0.6, 1.0) // 高饱和度颜色，易观察
        _NoiseIntensity ("noiseStrength", Float) = 0.5                     // 适当噪波，不破坏可见性
    }

    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent+10" "IgnoreProjector"="True" }
        LOD 100
        Blend SrcAlpha OneMinusSrcAlpha  // 标准透明混合
        ZWrite Off                       // 不写深度，避免遮挡
        ZTest Less                       // 只渲染在相机前面的部分
        Cull Off                         // 双面渲染，无死角
        Lighting Off                     // 关闭固定光照，避免干扰

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            // 全局参数
            float3 _VolumeSize;
            float _BaseDensity;
            int _StepCount;
            float _StepSize;
            float4 _VolumeColor;
            float _NoiseIntensity;

            struct v2f
            {
                float4 pos : SV_POSITION;
                float3 worldPos : TEXCOORD0;
                float3 objPos : TEXCOORD1; // 物体空间位置（关键：和物体绑定）
            };

            // 简单3D噪波（确保有明显扰动）
            float random(float3 p)
            {
                return frac(sin(dot(p, float3(12.9898, 78.233, 45.5431))) * 43758.5453);
            }

            float smoothNoise(float3 p)
            {
                float3 i = floor(p);
                float3 f = frac(p);
                f = f * f * (3.0 - 2.0 * f); // 平滑插值

                float a = random(i);
                float b = random(i + float3(1.0, 0.0, 0.0));
                float c = random(i + float3(0.0, 1.0, 0.0));
                float d = random(i + float3(1.0, 1.0, 0.0));
                float e = random(i + float3(0.0, 0.0, 1.0));
                float f2 = random(i + float3(1.0, 0.0, 1.0));
                float g = random(i + float3(0.0, 1.0, 1.0));
                float h = random(i + float3(1.0, 1.0, 1.0));

                // 8个角的3D插值（之前是2D，导致噪波无深度）
                float xy1 = lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
                float xy2 = lerp(lerp(e, f2, f.x), lerp(g, h, f.x), f.y);
                return lerp(xy1, xy2, f.z);
            }

            // 关键：用物体空间位置计算体积（和物体绑定，物体移动/缩放都生效）
            bool isInsideVolume(float3 objPos)
            {
                // 物体空间下，体积是中心在原点、大小为_VolumeSize的立方体
                return abs(objPos.x) < _VolumeSize.x/2 
                    && abs(objPos.y) < _VolumeSize.y/2 
                    && abs(objPos.z) < _VolumeSize.z/2;
            }

            float getDensity(float3 objPos)
            {
                if (!isInsideVolume(objPos)) return 0.0;

                // 用物体空间采样噪波（物体移动时噪波不偏移）
                float noise = smoothNoise(objPos * 3.0); // 3.0放大噪波细节
                float density = _BaseDensity * (0.7 + noise * _NoiseIntensity);
                return clamp(density, 0.0, 0.5); // 限制最大密度，避免过暗
            }

            // 修复：准确的光线相交检测（处理射线方向为负的情况）
            bool rayVolumeIntersect(float3 rayOriginObj, float3 rayDirObj, out float tEnter, out float tExit)
            {
                float3 halfSize = _VolumeSize * 0.5;
                float3 tMin = (-halfSize - rayOriginObj) / rayDirObj;
                float3 tMax = (halfSize - rayOriginObj) / rayDirObj;

                // 关键：对tMin和tMax排序，确保tMin是较小值
                float3 t1 = min(tMin, tMax);
                float3 t2 = max(tMin, tMax);

                tEnter = max(max(t1.x, t1.y), t1.z);
                tExit = min(min(t2.x, t2.y), t2.z);

                tEnter = max(tEnter, 0.0); // 只考虑相机前方
                return tEnter < tExit && tExit > 0.0;
            }

            v2f vert(appdata_base v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.objPos = v.vertex.xyz; // 直接用物体空间顶点位置（关键绑定）
                return o;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                // 转换光线到物体空间（确保采样和物体绑定）
                float3 camObjPos = mul(unity_WorldToObject, float4(_WorldSpaceCameraPos, 1.0)).xyz;
                float3 rayOriginObj = camObjPos;
                float3 rayDirObj = normalize(i.objPos - camObjPos); // 物体空间射线方向

                // 计算光线与物体空间体积的相交
                float tEnter, tExit;
                if (!rayVolumeIntersect(rayOriginObj, rayDirObj, tEnter, tExit))
                {
                    discard; // 不相交，透明
                }

                // 初始化采样
                float3 currentPosObj = rayOriginObj + rayDirObj * tEnter;
                float totalAlpha = 0.0;
                fixed3 totalColor = fixed3(0,0,0);
                float totalDistance = tEnter;

                // 光线步进（确保覆盖整个体积）
                for (int step = 0; step < _StepCount; step++)
                {
                    if (totalDistance > tExit) break;

                    // 计算密度
                    float density = getDensity(currentPosObj);
                    if (density > 0.01) // 只处理有效密度
                    {
                        float alpha = density * _StepSize * 5.0; // 放大透明度贡献
                        totalColor = totalColor * (1 - alpha) + _VolumeColor.rgb * alpha;
                        totalAlpha = min(totalAlpha + alpha, 1.0);
                    }

                    // 步进
                    currentPosObj += rayDirObj * _StepSize;
                    totalDistance += _StepSize;

                    if (totalAlpha >= 0.9) break; // 透明度足够则退出
                }

                // 确保颜色可见（增加亮度）
                totalColor *= 1.2;
                return fixed4(totalColor, totalAlpha * _VolumeColor.a);
            }
            ENDCG
        }
    }
    // 去掉FallBack，避免冲突
}