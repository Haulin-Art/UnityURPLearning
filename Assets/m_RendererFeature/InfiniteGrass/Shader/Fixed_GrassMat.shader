Shader "Unlit/Fixed_cesPosBuffer"
{
    Properties
    {
        _MainTex ("颜色纹理", 2D) = "white" {}
        [Toggle]_UseNorTex ("使用法线贴图",int) = 1
        _NorTex ("法线贴图",2D) = "blue" {}
        [Space(15)]
        _TotalScale ("整体大小缩放",Range(0.0,5.0)) = 1.0
        _GrassScale ("大小缩放",Vector) = (1,1,1,1)
        _PosOffset ("高度偏移",Range(-2.0,2.0)) = 0.0
        [Space(15)]
        _UpCol ("草尖颜色",Color) = (1,1,1,1)
        _DownCol ("草根颜色",Color) = (0,0,0,0)
        _ColRamp ("颜色渐变控制",Range(-2.0,2.0))=1.0
        [Space(15)]
        [Toggle]_UseBillBoard ("使用广告牌变形",int) = 1
        [Toggle]_OnlyMove ("随力移动的同时发生变形",int) = 1
        _TerrainUpAxisScale ("草朝向随地形法向强度",Range(0.0,1.0)) = 5.0
        _GrassDown ("草受力下垂程度",Range(0.0,5.0)) = 2.0
        _MaxForce ("最大力限制",Range(0.0,5.0)) = 0.8
        _ActorWindFieldStrangth ("角色风场强度",Range(0.0,10.0)) = 1.5
        _WindTex ("风场贴图", 2D) = "black" {}
        _WindStrength ("风强度",Range(0.0,5.0)) = 2.0
        _WindSpeed ("风速",Range(0.0,1.0)) = 0.25
        [Space(15)]
        _ClumpTex ("簇场" , 2D) = "black" {}
        _ClumpPoint ("簇向心力",Range(-5.0,5.0)) = 1.0
        _ClumpUseCenter ("簇使用中间力",Range(0.0,2.0)) = 1.0
        _ClumpUseSamePos ("同簇的位置接近程度",Range(-1.0,1.0)) = 0.0
        [Space(15)]
        [Enum(None,0,Normal,1,Tangent,2,Bitangent,3)]_DebugMode ("调试模式",int) = 0
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
                float3 normal : TEXCOORD6;
                float3 bezNormal : TEXCOORD1;      // 贝塞尔变形后的法线
                float3 bezTangent : TEXCOORD5;     // 贝塞尔变形后的切线
                float3 bezBitangent : TEXCOORD7;   // 贝塞尔变形后的副切线
                float3 worldPos : TEXCOORD2;
                float3 cesCol : TEXCOORD3;
                float grassHeight : TEXCOORD4;

                
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;

            sampler2D _NorTex;
            CBUFFER_START(UnityPerMaterial)
                float _TotalScale;
                float3 _GrassScale;
                int _UseNorTex;
                float _PosOffset;
                float3 _UpCol;
                float3 _DownCol;
                float _ColRamp;

                int _UseBillBoard;
                int _OnlyMove;
                float _TerrainUpAxisScale;
                float _MaxForce;
                float _ActorWindFieldStrangth;
                float _GrassDown;

                float _WindStrength;
                float _WindSpeed;

                float _ClumpPoint;
                float _ClumpUseCenter;
                float _ClumpUseSamePos;
                int _DebugMode;
            CBUFFER_END

            sampler2D _WindTex;
            float4 _WindTex_ST;

            sampler2D _ClumpTex;
            float4 _ClumpTex_ST;


            // ns流体参数
            sampler2D _NSVelocityTex;
            float4 _NSVelocityParams;

            // 实例的位置
            StructuredBuffer<float3> _GrassPositions;
            sampler2D _GrassHeightMap;
            float4 _GrassUVParams;
            int _Grass_Instance_Offset;

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
            
            // 贝塞尔曲线导数（切线）计算函数
            // B'(t) = 2(1-t)(P1-P0) + 2t(P2-P1)
            float3 QuadraticBezierTangent(float3 p0, float3 p1, float3 p2, float t)
            {
                float oneMinusT = 1.0 - t;
                float3 tangent = 2.0 * oneMinusT * (p1 - p0) + 2.0 * t * (p2 - p1);
                return normalize(tangent);
            }
            
            v2f vert (appdata v, uint instanceID : SV_InstanceID)
            {
                v2f o;
                int onlyInt = ceil(_GrassPositions[instanceID].x)+ceil(_GrassPositions[instanceID].z);
                float ran = random(onlyInt);
                float ranScale = pow(ran,0.5) + 0.4;;

                
                v.vertex.xyz *= _GrassScale * _TotalScale;
                float height = v.vertex.y;

                // 获取 Buffer 记录的偏移
                float3 worldOffset = _GrassPositions[instanceID + _Grass_Instance_Offset] ;
                
                // 根据地形法向更新草的上朝向，根据深度计算法线朝向，勾股定理
                float2 grassWorldUV = (worldOffset.xz-_GrassUVParams.xy)/(_GrassUVParams.z+_GrassUVParams.w);
                grassWorldUV = clamp(grassWorldUV*0.5+0.5,0,1);
                float midDepth = tex2Dlod(_GrassHeightMap,float4(grassWorldUV,0,0)).r;
                float rightDepth = tex2Dlod(_GrassHeightMap,float4(grassWorldUV+float2(0.01,0.0),0,0)).r;
                float upDepth = tex2Dlod(_GrassHeightMap,float4(grassWorldUV+float2(0.0,0.01),0,0)).r;
                float2 xyNor = float2(midDepth-rightDepth,midDepth-upDepth)*_TerrainUpAxisScale*50.0;
                float3 grassUPAxis = normalize(float3(xyNor.x,sqrt(1-dot(xyNor,xyNor)),xyNor.y));


                // ======================= Bill Board 部分，让草始终沿着y轴旋转 =============
                float3 verPosWS = v.vertex;
                float3 lookDir = _WorldSpaceCameraPos - worldOffset;
                // 计算 lookDir 在 xz平面的投影的标准向量
                float3 upDir = grassUPAxis;
                lookDir = normalize(float3(lookDir.x,0.0,lookDir.z));
                float3 rightDir = normalize(cross(upDir,lookDir));
                
                // 保存广告牌矩阵用于后续法线变换
                float3x3 BillBoardMatrix = float3x3(rightDir,upDir,lookDir);
                if (_UseBillBoard){
                    verPosWS = mul( v.vertex.xyz,BillBoardMatrix);
                }
                
                // =============== 采样簇贴图 =================================
                float3 clumpTex = tex2Dlod(_ClumpTex,float4(worldOffset.xz/_ClumpTex_ST.x,0,0)).xyz;
                float2 clumpUVOffset = (clumpTex.xy*2.0 - 0.5);
                clumpUVOffset = float2(clumpUVOffset.x,-clumpUVOffset.y);
                // 受一簇草的影响，草比较靠近
                worldOffset.xz -= clumpUVOffset*_ClumpUseSamePos;

                // =============== 风场贴图力 ===============================
                // 同一簇的草可以控制是否使用一个方向
                float2 windUV = worldOffset.xz/_WindTex_ST.x + float2(_Time.x*_WindSpeed,0) - 
                    clumpUVOffset * (1.0-clumpTex.z) * _ClumpUseCenter / _WindTex_ST.x;
                float3 windTex = tex2Dlod(_WindTex,float4(worldOffset.xz/_WindTex_ST.x + float2(_Time.x*_WindSpeed,0),0,0)).xyz;
                windTex = windTex*2.0 - 1.0;
                
                // ================计算贝塞尔曲线影响的弯曲，通过NS流体计算================
                // 获取NS
                float2 nsUV = ( _NSVelocityParams.xy - worldOffset.xz ) / _NSVelocityParams.z;
                float nsUVMask = step(abs(nsUV.x),0.5) * step(abs(nsUV.y),0.5);
                nsUV *= nsUVMask;
                nsUV += float2(0.5,0.5);
                // 靠近边界力缩小
                float nsUVbianjie = nsUVMask*smoothstep(0.5,0.3,abs(nsUV.x-0.5)) * smoothstep(0.5,0.3,abs(nsUV.y-0.5));
                float2 nsVel = 100 * _ActorWindFieldStrangth * 
                    nsUVbianjie * tex2Dlod(_NSVelocityTex,float4(nsUV,0,0)).xy;
                o.cesCol = float3(nsVel,0);
                // 计算角色的排挤力
                float2 actorForce = normalize(nsUV-0.5) * smoothstep(0.08,0.02,length(nsUV-0.5));
                actorForce = clamp(0,1.0,actorForce) * nsUVMask;
                
                // 合并所有力
                float2 force = nsVel + actorForce + windTex.xy*_WindStrength + clumpUVOffset*_ClumpPoint*10.0;
                float maxForce = _MaxForce; // 限制最大力
                force = length(force)>maxForce? normalize(force)*maxForce : force;
                
                // 计算贝塞尔曲线参数
                float t = (_PosOffset + height*_OnlyMove) * (_PosOffset + height*_OnlyMove) ;
                float3 p0 = float3(0,0,0);  // 起点（草根）
                float3 p1 = float3(-force.x * 0.5, 0.5, -force.y * 0.5);  // 控制点
                float3 p2 = float3(-force.x, 1.0, -force.y);  // 终点（草尖）
                
                // 计算贝塞尔曲线上的位置偏移
                float3 bezierOffset = QuadraticBezier(p0, p1, p2, t);
                verPosWS += bezierOffset; // 应用力
                verPosWS.y -= length(bezierOffset) * t * _GrassDown; // 长度守恒，偏移的越狠，高度越低
                
                // ================ 修正后的法线计算 ====================
                // 步骤1：使用贝塞尔导数公式计算正确的切线（在草的局部空间）
                float3 localTangent = QuadraticBezierTangent(p0, p1, p2, t);
                
                // 步骤2：副切线是草片的宽度方向
                // 对于广告牌草，宽度方向是 rightDir
                // 如果没有使用广告牌，使用默认的X方向
                float3 localBitangent = _UseBillBoard ? float3(1,0,0) : float3(1,0,0);
                
                // 步骤3：计算法线（切线 × 副切线）
                float3 localNormal = normalize(cross(localTangent, localBitangent));
                
                // 步骤4：如果使用广告牌，需要将切线、副切线、法线变换到世界空间
                float3 worldTangent, worldBitangent, worldNormal;
                if (_UseBillBoard) {
                    // 广告牌矩阵的列向量：rightDir, upDir, lookDir
                    // 切线主要沿着upDir方向（草的生长方向），但被力弯曲
                    // 我们需要将局部空间的切线变换到广告牌空间
                    worldTangent = mul(localTangent, BillBoardMatrix);
                    worldBitangent = mul(localBitangent, BillBoardMatrix);
                    worldNormal = normalize(cross(worldTangent, worldBitangent));
                } else {
                    worldTangent = localTangent;
                    worldBitangent = localBitangent;
                    worldNormal = localNormal;
                }

                // ================== 最终传递 =========================================
                float4 pp = TransformWorldToHClip( worldOffset + _PosOffset*grassUPAxis +  verPosWS );

                o.normal = TransformObjectToWorldNormal(v.normal);
                o.bezNormal = worldNormal;
                o.bezTangent = worldTangent;
                o.bezBitangent = worldBitangent;
                o.grassHeight = t;
                o.vertex = pp;
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.worldPos = worldOffset + verPosWS;
                return o;
                
            }

            float4 frag (v2f i, uint instanceID : SV_InstanceID) : SV_Target
            {
                float4 col = tex2D(_MainTex, i.uv);

                // ================ 修正后的TBN矩阵构建 ====================
                // TBN矩阵：用于将法线贴图从切线空间变换到世界空间
                // 正确的顺序是：T(切线), B(副切线), N(法线)
                float3 T = normalize(i.bezTangent);
                float3 B = normalize(i.bezBitangent);
                float3 N = normalize(i.bezNormal);
                float3x3 TBNMatrix = float3x3(T, B, N);
                
                // 采样并解包法线贴图
                float3 tangentNormal = UnpackNormal(tex2D(_NorTex, i.uv));
                
                // 将切线空间的法线变换到世界空间
                float3 nor = mul(tangentNormal, TBNMatrix);
                
                // 如果不使用法线贴图，直接使用顶点法线
                if (_UseNorTex == 0) {
                    nor = N;
                }

                // ================ Debug模式可视化 ====================
                if (_DebugMode == 1) {
                    // 可视化法线（映射到0-1范围显示）
                    return float4(nor * 0.5 + 0.5, 1.0);
                } else if (_DebugMode == 2) {
                    // 可视化切线
                    return float4(T * 0.5 + 0.5, 1.0);
                } else if (_DebugMode == 3) {
                    // 可视化副切线
                    return float4(B * 0.5 + 0.5, 1.0);
                }

                Light mainLight = GetMainLight(TransformWorldToShadowCoord(i.worldPos));
                float3 lightDir = normalize(mainLight.direction); // 灯光方向（从采样点指向灯光）
                float3 lightColor = mainLight.color.rgb;          // 灯光颜色
                float shadowAttenuation = mainLight.shadowAttenuation;  // 阴影衰减值（0=全阴影，1=无阴影）
                float3 ro = _WorldSpaceCameraPos;
                float3 rd = normalize(i.worldPos - _WorldSpaceCameraPos);
                float3 h = normalize(rd+lightDir);
                
                // ================= 漫反射 ==============================
                float3 ambient = 0.1;
                float diff = max(0.0, dot(nor, lightDir));
                diff = lerp(diff, 1.0, 0.25) * (shadowAttenuation + ambient);

                // ================= 高光 ===============================
                float specular = pow(max(dot(nor, h), 0.0), 15.0);
                specular = smoothstep(0.0, 1.0, specular) * 1.0;

                float3 albedo = lerp(_DownCol, _UpCol, i.grassHeight * _ColRamp);
                // 远处的暗部颜色变弱
                float dep = length(i.worldPos - _WorldSpaceCameraPos);
                albedo = lerp(albedo, _UpCol, smoothstep(20.0, 50.0, dep) * 0.08);
                specular = specular * (1.0 - smoothstep(10.0, 40.0, dep)); // 远处高光消失

                return float4((diff + specular) * (i.cesCol/100 + albedo) * 1.3 * float3(1,1,1), 1);
            }
            //ENDCG
            ENDHLSL
        }
    }
}
