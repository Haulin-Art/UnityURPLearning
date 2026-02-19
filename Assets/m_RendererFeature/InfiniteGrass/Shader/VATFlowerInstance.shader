Shader "Unlit/VATFlowerInstance"
{
    Properties
    {
        _MainTex ("颜色纹理", 2D) = "white" {}
        _UpCol ("草尖颜色",Color) = (1,1,1,1)
        _DownCol ("草根颜色",Color) = (0,0,0,0)
        _GrassDown ("草受力下垂程度",Range(0.0,5.0)) = 2.0
        _MaxForce ("最大力限制",Range(0.0,5.0)) = 0.8
        _ActorWindFieldStrangth ("角色风场强度",Range(0.0,2.0)) = 1.5
        _WindTex ("风场贴图", 2D) = "black" {}
        _WindStrength ("风强度",Range(0.0,5.0)) = 2.0
        _WindSpeed ("风速",Range(0.0,1.0)) = 0.25
        _ClumpTex ("簇场" , 2D) = "black" {}
        _ClumpPoint ("簇向心力",Range(0.0,2.0)) = 1.0
        _ClumpUseCenter ("簇使用中间力",Range(0.0,2.0)) = 1.0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque""Queue"="AlphaTest" }// AlphaTest队列
        LOD 100
        Cull Off

        Pass
        {
            //CGPROGRAM
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            // 多编译宏：支持主光阴影（根据项目设置自动编译不同版本）
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE // 主光级联阴影（用于大场景）
            // 多编译宏：支持额外光源（点光、聚光等）
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS // 额外光源阴影
            #pragma multi_compile _ _SHADOWS_SOFT // 软阴影
            #pragma multi_compile_fog // 雾效（URP 雾效系统）

            //#include "UnityCG.cginc"
            // 包含URP的核心着色器库（提供矩阵、光照、雾效等工具函数）
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            // 定义PI常量（HLSL内置有PI，但部分环境可能需要手动定义，兼容更优）
            #ifndef PI
            #define PI 3.14159265358979323846
            #endif
            #ifndef TWO_PI
            #define TWO_PI (2.0 * PI)
            #endif

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal :NORMAL;
                
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                float3 normal : TEXCOORD1;
                float3 worldPos : TEXCOORD2;
                float grassHeight : TEXCOORD4;

                float3 cesCol : TEXCOORD3;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;
            float3 _UpCol;
            float3 _DownCol;
            float _MaxForce;
            float _ActorWindFieldStrangth;
            float _GrassDown;
            sampler2D _WindTex;
            float4 _WindTex_ST;
            float _WindStrength;
            float _WindSpeed;

            sampler2D _ClumpTex;
            float4 _ClumpTex_ST;
            float _ClumpPoint;
            float _ClumpUseCenter;

            // ns流体参数
            sampler2D _NSVelocityTex;
            float4 _NSVelocityParams;

            // 实例的位置
            StructuredBuffer<float3> _GrassPositions;
            // MurmurHash3 哈希算法（简化版）：将整数输入转换为无符号整数哈希值，用于生成均匀的伪随机数
            uint murmurHash3(int input) {
                uint h = abs(input);          // 取输入的绝对值（避免负数）
                h ^= h >> 16;                 // 右移16位后异或，打乱高位
                h *= 0x85ebca6b;              // 乘以大质数，增加随机性
                h ^= h >> 13;                 // 右移13位后异或
                h *= 0xc2b2ae3d;              // 乘以另一个大质数
                h ^= h >> 16;                 // 最终异或，得到最终哈希值
                return h;
            }
            // ====================================== 辅助函数：生成0~1的伪随机数 ======================================
            // 输入：索引值（网格的X/Z索引），输出：0~1的浮点数随机数
            float random(int index)
            {
                // 将哈希值除以 uint 的最大值（4294967295=2^32-1），得到0~1的浮点数
                return murmurHash3(index) / 4294967295.0;
            }
            //-------------------------------------------------------------------------------------
            // 函数1：输入int型ID，生成0~1之间的均匀随机浮点数（基础核心函数）
            // 参数：id - 唯一标识（如顶点ID、实例ID、纹理坐标整数部分等）
            // 返回：0.0 ~ 1.0的随机值（闭区间）
            //-------------------------------------------------------------------------------------
            float RandomFloat01(int id)
            {
                // 使用PCG哈希算法（伪随机数生成器，随机性好、计算高效，适合GPU）
                // 步骤1：位运算哈希，打散ID的二进制分布
                id = (id ^ 61) ^ (id >> 16);
                id *= 9;
                id = id ^ (id >> 4);
                id *= 0x27d4eb2d;
                id = id ^ (id >> 15);
            
                // 步骤2：将哈希后的整数映射到0~1的浮点数（使用uint保证无符号，避免负数）
                uint uId = (uint)id;
                float random = frac((float)uId / 4294967295.0); // 4294967295是2^32-1，映射到0~1
            
                // 确保返回值在0~1之间（防止浮点精度问题导致超出范围）
                return saturate(random);
            }
            // 贝塞尔曲线计算函数
            // B(t) = (1-t)²P0 + 2(1-t)tP1 + t²P2
            float3 QuadraticBezier(float3 p0, float3 p1, float3 p2, float t)
            {
                // B(t) = (1-t)²P0 + 2(1-t)tP1 + t²P2
                float oneMinusT = 1.0 - t;
                float3 result = 
                    (oneMinusT * oneMinusT) * p0 + 
                    (2.0 * oneMinusT * t) * p1 + 
                    (t * t) * p2;
                return result;
            }
            v2f vert (appdata v, uint instanceID : SV_InstanceID)
            {
                v2f o;
                int onlyInt = ceil(_GrassPositions[instanceID].x)+ceil(_GrassPositions[instanceID].z);
                float ran = random(onlyInt);
                float ranScale = pow(ran,0.5) + 0.4;;

                v.vertex *= 1.5;
                //v.vertex *= ranScale * 1.5;
                //v.vertex.xz *= 3.0; // 为了让草更粗点，好观察

                // 获取 Buffer 记录的偏移
                float3 worldOffset = _GrassPositions[instanceID*100] ;//- float3(0,0,4); // test
                
                // ======================= Bill Board 部分，让草始终沿着y轴旋转 =============
                float3 lookDir = _WorldSpaceCameraPos - worldOffset;
                // 计算 lookDir 在 xz平面的投影的标准向量
                //lookDir -= dot(lookDir,float3(0,1,0))*lookDir;
                lookDir = normalize(float3(lookDir.x,0.0,lookDir.z));
                float3 rightDir = normalize(cross(float3(0,1,0),lookDir));
                float3x3 BillBoardMatrix = float3x3(rightDir,float3(0,1,0),lookDir);
                
                float3 verPosWS = mul( v.vertex.xyz,BillBoardMatrix);

                // =============== 采样簇贴图 =================================
                float3 clumpTex = tex2Dlod(_ClumpTex,float4(worldOffset.xz/_ClumpTex_ST.x,0,0)).xyz;
                float2 clumpUVOffset = (clumpTex.xy*2.0 - 0.5);
                clumpUVOffset = float2(clumpUVOffset.x,-clumpUVOffset.y);
                
                // =============== 风场贴图力 ===============================
                // 同一簇的草可以控制是否使用一个方向
                float2 windUV = worldOffset.xz/_WindTex_ST.x + float2(_Time.x*_WindSpeed,0) - 
                    clumpUVOffset * (1.0-clumpTex.z) * _ClumpUseCenter / _WindTex_ST.x;
                float3 windTex = tex2Dlod(_WindTex,float4(worldOffset.xz/_WindTex_ST.x + float2(_Time.x*_WindSpeed,0),0,0)).xyz;
                windTex = windTex*2.0 - 1.0;
                //o.cesCol = float3(windUV,0);
                // ================计算贝塞尔曲线影响的弯曲，通过NS流体计算================
                // 获取NS
                float2 nsUV = ( _NSVelocityParams.xy - worldOffset.xz ) / _NSVelocityParams.z;
                float nsUVMask = step(abs(nsUV.x),0.5) * step(abs(nsUV.y),0.5);
                nsUV *= nsUVMask;
                nsUV += float2(0.5,0.5);
                //o.cesCol = float3(nsUV,0);
                // 靠近边界力缩小
                float nsUVbianjie = nsUVMask*smoothstep(0.5,0.3,abs(nsUV.x-0.5)) * smoothstep(0.5,0.3,abs(nsUV.y-0.5));
                float2 nsVel = 100 * _ActorWindFieldStrangth * 
                    nsUVbianjie * tex2Dlod(_NSVelocityTex,float4(nsUV,0,0)).xy;
                o.cesCol = float3(nsVel,0);
                // 计算角色的排挤力
                float2 actorForce = normalize(nsUV-0.5) * smoothstep(0.08,0.02,length(nsUV-0.5));
                actorForce = clamp(0,1.0,actorForce) * nsUVMask;
                

                // ================== 最终传递 =========================================
                float4 pp = TransformWorldToHClip( worldOffset +  verPosWS );
                o.normal = normalize(v.normal);
                o.vertex = pp;
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.worldPos = worldOffset + verPosWS;
                return o;
            }

            float4 frag (v2f i, uint instanceID : SV_InstanceID) : SV_Target
            {
                /*
                float4 col = tex2D(_MainTex, i.uv);


                Light mainLight = GetMainLight(TransformWorldToShadowCoord(i.worldPos));
                float3 lightDir = normalize(mainLight.direction); // 灯光方向（从采样点指向灯光）
                float3 lightColor = mainLight.color.rgb;          // 灯光颜色
                float shadowAttenuation = mainLight.shadowAttenuation;  // 阴影衰减值（0=全阴影，1=无阴影）
                float3 ro = _WorldSpaceCameraPos;
                float3 rd = normalize(i.worldPos - _WorldSpaceCameraPos);
                float3 h = normalize(rd+lightDir);
                
                // ================= 漫反射 ==============================
                float3 ambient = 0.1;//UNITY_LIGHTMODEL_AMBIENT.rgb;
                float diff = max(0.0,dot(i.normal,lightDir));
                diff = lerp(diff,1.0,0.5)*(shadowAttenuation+ambient);

                // ================= 高光 ===============================
                float specular = pow(max(dot(i.normal,h),0.0),5.0);
                specular = smoothstep(0.7,1.0,specular)*1.5;

                float3 albedo = lerp(_DownCol,_UpCol,i.grassHeight);
                */
                return float4(1,1,1,1);
                //return float4((diff+specular)*(i.cesCol/100 + albedo)*float3(1,1,1),1);

            }
            //ENDCG
            ENDHLSL
        }
    }
}