Shader "Unlit/s_Atmosphere"
{
    Properties
    {
        _MainTex ("主纹理", 2D) = "white" {}
        _Density ("体积密度", Range(0.0,5.0)) = 0.01
        _MainAbsorption ("体积吸收率",Range(0.0,1.0)) = 0.3
        _VolColor ("体积颜色",Color) = (1,0,0,0)
        _ShadowColor ("暗部颜色",Color) = (0,0,0,0)
        _Step ("步进步数",Float) = 64
        _InStepSize ("步长（处于体积内时）",Range(0.0,10.0)) = 2.0
        _DitherScale ("步进抖动强度",Range(0.0,2.0)) = 1.0
        _AABBMax ("AABBMax",Vector) = (1,1,1,1)
        _AABBMin ("AABBMin",Vector) = (-1,-1,-1,1)

        _NoiseScale ("噪波缩放",Range(0.01,2.0)) = 0.5
        _NoiseOctaves ("噪波级数",Range(1,10)) = 4
        _NoiseOffset ("噪波偏移",Vector) = (200,200,200,200)

        //_EnableShadow ("EnableShadow",Bool)
        _ShadowSteps ("阴影步进步数",Float) = 16
        _ShadowStepSize("阴影步长",Range(0.0,5.0)) = 0.1
        _ShadowAbsorption ("阴影吸收率",Range(0.0,1.0)) = 0.7
        _ShadowPow ("阴影强度",Range(0.001,6.0)) = 3
        _ShadowThreshold("阴影阈值",Range(0.0,1.0)) = 0.1
        
        // ========== 新增：相位函数可调节参数，实现背光轮廓得效果 ==========
        _EnablePhase ("启用相位函数",Float) = 1
        _G1 ("相位函数g", Range(-0.99, 0.99)) = 0.7   // 前向散射系数（云常用0.7~0.9）

        // 实现云折角处更亮得效果，beer’s powder
        _FoldMax ("折角高亮峰值处密度",Range(0.0,10.0)) = 5.0
        _FoldScale ("折角高亮强度",Range(0.0,10.0)) = 3.0

        // 远处得云变淡，避免乱码
        _CloudFog ("远处云变淡，x为开始点，y为结束点，z为是否启用",Vector) = (50.0,200.0,1.0,1.0)
    }
    SubShader
    {
        Tags { "RenderType"="Opaque"
              "RenderPipeline"="UniversalPipeline" // URP管线标签（必须）
              "Queue"="Overlay" 
              }
        LOD 100
        ZTest Always
        ZWrite Off
        Cull Off

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            //#include "UnityCG.cginc"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Assets/Shader/Include/NoiseShaderLib.hlsl"
            // URP 主方向光内置参数（需包含对应头文件）
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            float _Density;
            float _MainAbsorption;
            float3 _VolColor;
            float3 _ShadowColor;
            int _Step;
            float _InStepSize;
            float _DitherScale;
            float3 _AABBMax;
            float3 _AABBMin;
            float _NoiseScale;
            float3 _NoiseOffset;
            int _NoiseOctaves;

            int _ShadowSteps;
            float _ShadowAbsorption;
            float _ShadowThreshold;
            float _ShadowStepSize;
            float _ShadowPow;

            // ========== 新增：相位函数参数声明 ==========
            bool _EnablePhase;
            float _G1;

            // 折角增强
            float _FoldMax;
            float _FoldScale;

            //远处云变淡
            float3 _CloudFog;

            // 在frag函数前添加：4x4 Bayer有序抖动矩阵（低成本抗锯齿）
            static const float dither4x4[16] = {
                0.0f/16.0f,  8.0f/16.0f,  2.0f/16.0f, 10.0f/16.0f,
                12.0f/16.0f, 4.0f/16.0f, 14.0f/16.0f, 6.0f/16.0f,
                3.0f/16.0f, 11.0f/16.0f,  1.0f/16.0f,  9.0f/16.0f,
                15.0f/16.0f,7.0f/16.0f, 13.0f/16.0f, 5.0f/16.0f
            };


            // ========== AABB核心定义（复制到这里） ==========
            struct AABB
            {
                float3 min;
                float3 max;
            };

            float2 RayAABBIntersect(float3 ro, float3 rd, AABB aabb)
            {
                float t_enter = 0.0;
                float t_exit = 1e6;

                float inv_rd_x = 1.0 / rd.x;
                float t_x1 = (aabb.min.x - ro.x) * inv_rd_x;
                float t_x2 = (aabb.max.x - ro.x) * inv_rd_x;
                t_enter = max(t_enter, min(t_x1, t_x2));
                t_exit = min(t_exit, max(t_x1, t_x2));

                float inv_rd_y = 1.0 / rd.y;
                float t_y1 = (aabb.min.y - ro.y) * inv_rd_y;
                float t_y2 = (aabb.max.y - ro.y) * inv_rd_y;
                t_enter = max(t_enter, min(t_y1, t_y2));
                t_exit = min(t_exit, max(t_y1, t_y2));

                float inv_rd_z = 1.0 / rd.z;
                float t_z1 = (aabb.min.z - ro.z) * inv_rd_z;
                float t_z2 = (aabb.max.z - ro.z) * inv_rd_z;
                t_enter = max(t_enter, min(t_z1, t_z2));
                t_exit = min(t_exit, max(t_z1, t_z2));

                if (isinf(t_enter) || isinf(t_exit))
                {
                    return float2(1e6, 0.0);
                }
                return float2(t_enter, t_exit);
            }
            // 辅助函数：判断点是否在AABB内（复用）
            bool InAABB(float3 pos, AABB aabb)
            {
                return pos.x >= aabb.min.x && pos.x <= aabb.max.x &&
                        pos.y >= aabb.min.y && pos.y <= aabb.max.y &&
                        pos.z >= aabb.min.z && pos.z <= aabb.max.z;
            }
            // ========== AABB定义结束 ==========


            // ========== 2. 体积密度函数（自定义体积规则） ==========
            // 计算当前位置的体积密度（0~1，0=无体积，1=最大密度）
            float GetVolumeDensity(float3 pos, AABB aabb)
            {
                /*
                //高度衰减
                float len = abs(aabb.max.y - aabb.min.y);
                float yy = abs(aabb.max.y - (aabb.min.y+len*0.5));
                float hei = (pos.y - (aabb.min.y+len*0.5))/yy;
                hei = 1.0-hei;
                */
                float cloudDensity = CloudNoise(pos + _NoiseOffset + float3(_Time.y,0,0), _NoiseScale, _NoiseOctaves);
                return saturate(cloudDensity * _Density );

            }
            // 米氏相位函数
            float MiePhaseFunction(float cosTheta, float g = 0.7) {
                float g2 = g * g;
                // 前向散射为主的米氏函数（无负值，适合大气/云）
                return (3.0 / (8.0 * PI)) * (1.0 - g2) * 
                    (1.0 + cosTheta * cosTheta) / 
                    pow(2.0 + g2 - 2.0 * g * cosTheta, 1.5);
            }
            
            // ========== 相位函数：单Lobe HG（基础版） ==========
            float HenyeyGreenstein(float cosTheta, float g) {
                float g2 = g * g;
                float denom = 1.0 + g2 - 2.0 * g * cosTheta;
                return (1.0 - g2) / (4.0 * PI * pow(denom, 1.5));
            }

            // ========== 3. 光线步进核心函数 ==========
            // 参数：ro=光线原点，rd=光线方向，aabb=体积包围盒，maxSteps=最大步数，stepSize=步长
            // 返回值：累计的体积颜色贡献
            float4 RayMarch(float3 ro, float3 rd, AABB aabb, int maxSteps,float dither,float linearDep)
            { 
                // 第一步：检测光线与AABB的相交范围
                float2 tRange = RayAABBIntersect(ro, rd, aabb);
                float t_enter = tRange.x;
                float t_exit = tRange.y;

                //UnityWorldSpaceLightDir()
                // 2. 获取主方向光参数（URP内置）
                Light mainLight = GetMainLight();
                float3 lightDir = normalize(mainLight.direction); // 灯光方向（从采样点指向灯光）
                float3 lightColor = mainLight.color.rgb;          // 灯光颜色

                // 摄像机是否在体积内，若在,总距离就是aabb远点，若不在，就是aabb远减去近
                bool isIn = InAABB(ro,aabb);
                // 步长依据进入点与出点的距离除以步进次数计算
                float stepSize = abs(t_exit - t_enter)/maxSteps;
                
                if(isIn)
                {
                    // 当摄像机在体积内时的计算方法
                    // 方法一、平均法，适合小范围
                    //stepSize = abs(t_exit)/maxSteps;
                    // 方法二、近距离步进，适合大范围
                    stepSize = _InStepSize;
                }
                //stepSize = 0.25;// 使用固定步进
                // 第二步：初始化步进参数
                float t = t_enter + dither*stepSize; // 当前步进的距离,加上一个随机值，避免分层
                float3 totalColor = float3(0,0,0); // 累计体积颜色
                float cloudAlpha;// 用于与背景色混合的mask
                float transmittance = 1.0; // 透光率（步进越远，透光率越低）

                // 第三步：逐步采样体积
                for (int i = 0; i < maxSteps; i++)
                {
                    // 超出AABB范围：终止步进
                    if (t > t_exit) break;
                    if (t > linearDep) break; // 当距离超出场景中物体的距离，就停止

                    // 计算当前步进位置
                    float3 currPos = ro + rd * t;

                    // 采样当前位置的密度
                    // 乘以单次步长，避免最大层数发生变换的时候变得密度不一样
                    float density = GetVolumeDensity(currPos, aabb);

                    // 仅当密度>0时，累加体积贡献
                    if (density > 0.0)
                    {
                        // 阴影计算

                        float st = 0.0;// 阴影距离
                        float strans = 1.0;// 初始阴影透光率
                        for (int j = 0; j < _ShadowSteps; j++)
                        {
                            float3 shadowPos = currPos + (st+dither*0.0)*_ShadowStepSize*lightDir;
                            float shadowDensity = GetVolumeDensity(shadowPos, aabb);
                            if (!InAABB(shadowPos, aabb)) shadowDensity = 0.0;
                            if (shadowDensity > _ShadowThreshold)
                            {
                                //strans *= 1.0 - shadowDensity*_ShadowStepSize;
                                // 以下是更物理的，基于Beer-Lambert Lawd的衰减
                                // 遵循Beer定律的阴影透光率（指数衰减，平滑）
                                //float sigma_a_shadow = 0.7; // 阴影吸收系数（可略大，让阴影更明显）
                                strans *= exp(-_ShadowAbsorption * shadowDensity); 
                                //strans *= 0.9;
                                if (strans < 0.02) break;
                            }
                            st += _ShadowStepSize;
                            strans = saturate(strans);
                        }
                        float lightVisibility = strans;

                        // ========== 核心：米氏散射相位函数 ==========
                        // 1. 计算视线方向：采样点→相机（与rd相反，rd是相机→采样点）
                        float3 viewDir = -rd;
                        // 2. 计算光源方向与视线方向的夹角余弦（θ是散射角）
                        float cosTheta = dot(lightDir, viewDir);
                        float phase = MiePhaseFunction(cosTheta, _G1);
                        // 是否启用相位函数，*20是相位函数归一化系数（抵消PI带来的衰减）
                        phase = _EnablePhase? phase*20.0 : 1.0;
                               
                        // ========== 核心：瑞丽散射相关 ============
                        // 以下瑞丽散射仅发生在在体积外
                        // 瑞利散射系数（σ ∝ 1/λ⁴，蓝>绿>红，已归一化）
                        float3 sigma_rayleigh = float3(0.17f, 0.43f, 1.0f); // 红=0.17（长波，散射弱），蓝=1.0（短波，散射强）
                        // 瑞利吸收系数（大气对光的吸收，可略小于散射系数）
                        float3 sigma_rayleigh_abs = sigma_rayleigh * 0.1f;
                        // 光程长度L，采样点到大气顶部距离,归一化0-1
                        float ruiliLightPathLength = (t-t_enter)/(t_exit - t_enter);
                        // 1. 瑞利相位函数（对称，对方向不敏感，保持大气颜色均匀）
                        float rayleighPhase = 0.75f * (1.0f + cosTheta * cosTheta); // 标准瑞利相位函数
                        // 2. 瑞利散射的衰减（光程越长，短波衰减越厉害）
                        float3 rayleighAttenuation = exp(-(sigma_rayleigh + sigma_rayleigh_abs) * ruiliLightPathLength * 5.0f); 
                        // （10.0f是光程缩放系数，可调：值越大，颜色变化越明显）
                        // 3. 瑞利散射颜色（短波保留，长波穿透）
                        // 瑞丽散射颜色= 瑞丽散射系数 * 瑞丽衰减 * 瑞丽相位函数
                        // 瑞利衰减 = exp(-（瑞利散射系数+瑞利散射系数偏移）*深度比例*变化强度)
                        float tt = (t_exit - t_enter)/30.0 ;//length(aabb.max-aabb.min);
                        float3 rayleighColor = 2.0*sigma_rayleigh*exp(-(sigma_rayleigh + sigma_rayleigh_abs) * tt * 5.0f)* rayleighPhase;
                        // （关键：光程长时，rayleighAttenuation的蓝通道衰减快，只剩红通道，颜色偏红）


                        transmittance *= exp(-_MainAbsorption * density *stepSize );  
                        // 提前终止（透光率过低，无更多贡献）
                        if (transmittance < 0.01) break;

                        // 【关键修改2：正确使用“折角亮”公式——作为散射增强因子】        
                        float x = density * stepSize * _FoldMax; // 5.0是缩放系数，控制峰值位置（可调）
                        float foldBrightFactor = 2.0 * exp(-x) * (1.0 - exp(-2.0 * x));
                        foldBrightFactor = saturate(foldBrightFactor * _FoldScale); // 3.0是增强强度（可调）
                        
                        // 暗部
                        lightVisibility = pow(lightVisibility,_ShadowPow);

                        // 物理逻辑：体积颜色 = 基色 × 灯光色 × 单位长度密度 × 步长 × 透光率 × 受光率 × 相位函数 × 折角增强
                        float3 cloudColor = _VolColor.rgb * lightColor * density * 
                                            transmittance * lightVisibility* stepSize*
                                            phase * (1.0+foldBrightFactor) ;
                        totalColor += cloudColor + rayleighColor*0.005;
                        //totalColor += rayleighColor*0.05;
                        
                        //totalColor =  rayleighColor; 
                        cloudAlpha += density*stepSize ;//* transmittance;
                    }
                    // 步进下一步
                    t += stepSize;
                }

                return float4(totalColor,saturate(cloudAlpha));
            }

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                float4 screenPos : TEXCOORD1;
            };
            // URP 规范：声明纹理+采样器（替代传统 sampler2D）
            TEXTURE2D(_MainTex); 
            SAMPLER(sampler_MainTex); 
            float4 _MainTex_ST;
            
            TEXTURE2D(_CameraDepthTexture);
            SAMPLER(sampler_CameraDepthTexture); 
            
            // C#传递的参数
            float3 _CameraWorldPos;       // ro：相机世界位置
            float4x4 _InvViewProj;        // 逆视投影矩阵

            v2f vert (appdata v)
            {
                v2f o;
                o.uv = v.uv;
                o.vertex = TransformObjectToHClip(v.vertex.xyz); 
                // // 错误修正：ComputeScreenPos的参数是裁剪空间顶点（o.vertex），而非v.screenPos（appdata无此成员）
                o.screenPos = ComputeScreenPos(o.vertex);
                return o;
            }

            float4 frag (v2f i) : SV_Target
            {
                // 屏幕UV
                float2 screenUV = i.screenPos.xy / i.screenPos.w;
                float depth = SAMPLE_TEXTURE2D(_CameraDepthTexture,sampler_CameraDepthTexture,screenUV).x;
                // float4 _ZBufferParams; Unity内置深度参数（x=1-far/near, y=far/near, z=x/far, w=y/far）
                // 方式1：转换为「0（近裁面）~1（远裁面）」的线性相对深度（推荐）
                float linear01Depth = Linear01Depth(depth, _ZBufferParams);
                // 方式2：转换为「实际世界空间距离（米）」（比如近裁面1米，远裁面100米，值为1~100）
                float linearWorldDepth = LinearEyeDepth(depth, _ZBufferParams); // 视空间深度（相机空间）

                // ========== 步骤1：获取ro（光线原点） ==========
                float3 ro = _CameraWorldPos; // 直接使用相机世界位置
                // ========== 步骤3：计算基础rd（光线方向，未结合深度） ==========
                // 1. 把屏幕UV转成裁剪空间坐标（范围：x/y∈[-1,1]）
                float4 clipPos = float4(screenUV * 2.0 - 1.0, 1.0, 1.0);
                // 2. 逆视投影矩阵：裁剪空间 → 世界空间
                float4 worldPos = mul(_InvViewProj, clipPos);
                worldPos /= worldPos.w; // 透视除法
                // 3. 计算光线方向并单位化
                float3 rd = normalize(worldPos.xyz - ro);

                float4 col = SAMPLE_TEXTURE2D(_MainTex,sampler_MainTex, i.uv);

                // 2. 构建大气AABB包围盒
                AABB volumeAABB;
                volumeAABB.min = _AABBMin;
                volumeAABB.max = _AABBMax;

                // 3. 检测光线是否与大气AABB相交
                float2 t = RayAABBIntersect(ro, rd, volumeAABB);
                bool isIntersect = t.x < t.y && t.y > 0.0;

                // 计算随机抖动，减弱分层感
                //float di = (aHashFloat(float3(screenUV,0.0))-0.5)*2.0;
                // 新有序dither：基于屏幕像素坐标采样抖动矩阵
                float2 pixelCoord = screenUV * _ScreenParams.xy; // 屏幕像素坐标（整数）
                int ditherIdx = (int(pixelCoord.x) % 4) + (int(pixelCoord.y) % 4) * 4;
                float dither = (dither4x4[ditherIdx] - 0.5)*_DitherScale; // 力度0.3，避免过度抖动
                //dither += di*0.1;
                

                float4 volumeColor = RayMarch(ro, rd, volumeAABB,_Step,dither,linearWorldDepth);
                
                // 远处得云消散，避免乱码
                float cloudFog = smoothstep(_CloudFog.y,_CloudFog.x,t.x);
                // 是否开启远处云减淡
                cloudFog = _CloudFog.z==1.0? cloudFog:1.0;

                
                // 暗部颜色映射
                float3 shadowC = lerp(_ShadowColor*volumeColor.xyz,volumeColor.xyz,length(volumeColor.xyz));
                
                // 步骤4：采样原屏幕纹理，混合体积效果
                float4 baseColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv);
                //float3 finalColor = lerp(baseColor.xyz,volumeColor.xyz,volumeColor.w*cloudFog);
                float3 finalColor = lerp(baseColor.xyz,shadowC,volumeColor.w*cloudFog);

                return float4(finalColor,1.0);
            }
            ENDHLSL
        }
    }
}
