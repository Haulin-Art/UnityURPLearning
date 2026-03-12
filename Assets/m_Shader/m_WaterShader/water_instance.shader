Shader "FluidFlux/water_instance"
{
    Properties
    {
        // 这个3D纹理是用于正常水面起伏的，x是Voronoi分形的海面高度，yz是法向
        [Space(15)]
        _3DDisMap ("3D水面置换纹理", 3D) = "white" {}
        _SurfScale01 ("水面置换强度1", Range(-1.0,1.0)) = 0.05
        _SurfScale02 ("水面置换强度2", Range(-1.0,1.0)) = 0.025
        _SurfSpeed ("水面置换速度", Range(-5.0,5.0)) = 0.2
        _SurfNorScale ("水面法线强度", Range(0.0,5.0)) = 3.32

        [Space(15)]
        _VectorDisMap ("矢量置换纹理", 2D) = "white" {}
        [Space(15)]
        _VectorDisMapScale ("矢量置换整体强度", Float) = 3.0
        _VDMXScale ("矢量置换x强度", Range(-2,2)) = -0.44
        _VDMYScale ("矢量置换y强度", Range(-2,2)) = 0.12

        [Space(15)]
        _WavePos ("浪花位置",Range(-2.0,2.0))= 1.79
        _WaveAngle ("浪花角度",Range(0.0,5.0)) = 1.33
        _WaveScale ("浪花出现范围",Range(0.0,2.0)) = 0.26

        [Space(15)]
        _VDMXOffset ("矢量置换x偏移", Float) = 0.0
        _VDMYOffset ("矢量置换y偏移", Float) = 0.0
        _OceanNorTex ("海面法线", 2D) = "white" {}
        _Speed ("波动速度", Range(-5.0,5.0)) = -0.5
        _SineCount ("正弦波数量", Range(0.0,5.0)) = 2.0
        _sineScale ("正弦波幅度", Range(-1.0,1.0)) = 0.05

        // 这个是用于获取海洋离岸边距离的贴图，主要是根据这形成近岸海浪UV的x轴
        _SDFTex ("SDF距离图", 2D) = "white" {}
        _GradientTex ("梯度图", 2D) = "white" {}

        // 单纯用于调试的临时参数，什么地方需要就临时用一下测试效果
        _CES ("CES参数",Range(-1.0,5.0)) = 0.0
        
        [Space(15)]
        //[Header("菲涅尔设置")]
        _FresnelF0 ("菲涅尔F0", Range(0.0, 0.1)) = 0.02
        _FresnelPower ("菲涅尔强度", Range(1.0, 10.0)) = 5.0
        
        //[Header("折射设置")]
        [Space(15)]
        _RefractionStrength ("折射强度", Range(0.0, 0.1)) = 0.02
        _AbsorptionColor ("折射吸收颜色", Color) = (0.53, 0.7, 0.86)
        _RefractionBlurStart ("折射模糊开始深度", Range(0.0, 10.0)) = 0.3
        _RefractionBlurEnd ("折射模糊结束深度", Range(0.1, 50.0)) = 5.0
        _RefractionBlurStrength ("折射模糊强度", Range(0.0,10.0)) = 2.0
        
        //[Header("反射设置")]
        [Space(15)]
        _EnvReflectionStrength ("环境反射强度", Range(0.0, 10.0)) = 1.2
        _Roughness ("粗糙度", Range(0.0, 1.0)) = 0.18
        
        //[Header("高光设置")]
        [Space(15)]
        _SpecularPower ("高光锐度", Range(8.0, 256.0)) = 64.0
        _SpecularIntensity ("高光强度", Range(0.0, 3.0)) = 1.0
        
        //[Header("BSDF设置")]
        [Space(15)]
        _ScatterColor ("散射颜色", Color) = (0.2, 0.5, 0.8)
        _BSDFAbsorptionColor ("BSDF吸收颜色", Color) = (0.1, 0.2, 0.3)
        _PhaseG ("相位参数G", Range(-1.0, 1.0)) = 0.8
        _Thickness ("厚度", Range(0.0, 1.0)) = 0.5
        _DepthScale ("深度缩放", Range(0.1, 50.0)) = 10.0
        
        //[Header("光线步进设置")]
        [Space(15)]
        [Toggle(_USE_RAY_MARCHING)] _UseRayMarching ("启用光线步进", Float) = 0
        _RayMarchSteps ("步进次数", Range(1, 16)) = 6
        _RayMarchIntensity ("步进强度", Range(0.0, 3.0)) = 2.71
        _RayMarchMaxDistance ("最大步进距离", Range(0.1, 50.0)) = 5.0
        
        //[Header("次表面散射设置")]
        [Space(15)]
        [Toggle(_USE_SSS)] _UseSSS ("启用次表面散射", Float) = 1
        _SSSColor ("次表面散射颜色", Color) = (0.53, 0.52, 0.5, 1.0)
        _SSSStrength ("次表面散射强度", Range(0.0, 5.0)) = 3.72
        _SSSDepthScale ("次表面散射深度缩放", Range(0.1, 50.0)) = 5.0
        _SSSFade ("次表面散射衰减", Color) = (1.0, 1.0, 1.0, 1.0)
        _SunGlitterIntensity ("太阳闪烁强度", Range(0.0, 2.0)) = 2.0
        _SunGlitterSpeed ("太阳闪烁速度", Range(0.0, 10.0)) = 2.0
    }
    SubShader
    {
        Tags { 
            "RenderType" = "Transparent"
            "Queue" = "Transparent"
            "IgnoreProjector" = "True"
            "RenderPipeline" = "UniversalPipeline"
        }
        Cull Off

        HLSLINCLUDE
            #pragma shader_feature _USE_RAY_MARCHING
            #pragma shader_feature _USE_SSS
            #pragma multi_compile_instancing // 开启GPU Instancing支持


            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "ff_WaterCommon.hlsl"
            #include "ff_WaterFresnel.hlsl"
            #include "ff_WaterRefraction.hlsl"
            #include "ff_WaterReflection.hlsl"
            #include "ff_WaterSpecular.hlsl"
            #include "ff_WaterPhase.hlsl"
            #include "ff_WaterBSDF.hlsl"
            #include "ff_WaterRayMarching.hlsl"
            #include "ff_WaterForwardScatter.hlsl"
            
            #pragma vertex vert
            #pragma fragment frag
            
            CBUFFER_START(UnityPerMaterial)
                float4 _VectorDisMap_ST;
                float4 _OceanNorTex_ST;
                float4 _CameraOpaqueTexture_TexelSize;


                float _VectorDisMapScale;
                float _VDMXScale;
                float _VDMYScale;
                float _WavePos;
                float _WaveScale;
                float _WaveAngle;
                float _VDMXOffset;
                float _VDMYOffset;

                float _SurfScale01;
                float _SurfScale02;
                float _SurfSpeed;
                float _SurfNorScale;

                float _Speed;
                float _SineCount;
                float _sineScale;
                float _CES;
                float _FresnelF0;
                float _FresnelPower;
                float _RefractionStrength;
                float3 _AbsorptionColor;

                float _RefractionBlurStart;
                float _RefractionBlurEnd;
                float _RefractionBlurStrength;

                float _EnvReflectionStrength;
                float _Roughness;
                float _SpecularPower;
                float _SpecularIntensity;
                float3 _ScatterColor;
                float3 _BSDFAbsorptionColor;
                float _PhaseG;
                float _Thickness;
                float _DepthScale;
                float _UseRayMarching;
                float _RayMarchSteps;
                float _RayMarchIntensity;
                float _RayMarchMaxDistance;
                float _UseSSS;
                float3 _SSSColor;
                float _SSSStrength;
                float _SSSDepthScale;
                float3 _SSSFade;
                float _SunGlitterIntensity;
                float _SunGlitterSpeed;
            CBUFFER_END
            
            
            TEXTURE2D(_VectorDisMap);SAMPLER(sampler_VectorDisMap); 
            TEXTURE2D(_OceanNorTex);SAMPLER(sampler_OceanNorTex); 
            

            TEXTURE3D(_3DDisMap);SAMPLER(sampler_3DDisMap); 
            

            TEXTURE2D(_SDFTex);SAMPLER(sampler_SDFTex);
            TEXTURE2D(_GradientTex);SAMPLER(sampler_GradientTex); 

            TEXTURE2D(_CameraOpaqueTexture);SAMPLER(sampler_CameraOpaqueTexture);
            

            // 自定义的带有Mipmap的屏幕不透明物体纹理
            TEXTURE2D(_ScreenMipMapRT);SAMPLER(sampler_ScreenMipMapRT); // 只用这个实现伪前向散射模糊效果
            //TEXTURE2D(_ScreenMipMapDepthRT);SAMPLER(sampler_ScreenMipMapDepthRT);

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal : NORMAL;
                float4 tangent : TANGENT;

                // 通过这个ID，着色器可以访问每个实例的属性（如变换矩阵）。
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            
            struct v2f
            {
                float2 uv : TEXCOORD0;
                float3 worldPos : TEXCOORD1;
                float4 pos : SV_POSITION;
                float3 deformWSPos : TEXCOORD2;
                float2 newUV : TEXCOORD5;
                float uvMask : TEXCOORD10;
                float4 screenUV : TEXCOORD6;
                float3 norWS : TEXCOORD7;
                float3 ttt : TEXCOORD8;
                float3 viewDirWS : TEXCOORD9;

                float3 tanWave : TEXCOORD11;
                float3 bitWave : TEXCOORD12;

                // GPU Instancing：传递实例ID到片元着色器
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            
            float3 decodeDisp(float3 disp)
            {
                disp = pow(abs(disp),0.45);
                disp -= 0.5;
                disp *= float3(_VDMXScale,_VDMYScale,0.5);
                disp = float3(disp.x,0.0,disp.y);
                disp *= _VectorDisMapScale;
                disp += float3(_VDMXOffset,0.0,_VDMYOffset);
                return disp;
            }
            
            // 这个是我自创的方法，感觉效果更好
            float2 animUV(float2 uv,float sinBase ,float time,float4 uv_ST)
            {
                float w = 0.01;
                float2 newUV = uv*uv_ST.xy + uv_ST.zw;
                float nu = frac(newUV.x - time*_Speed);
                nu += -_sineScale * sin(((sinBase - time*_Speed)*2.0 - 1.0) * PI*_SineCount);
                nu = clamp(frac(nu),w,1.0-w);
                float nv02m = pow(abs(frac(newUV.y)-0.5),_WaveScale);
                float nv01m = pow(abs(frac(newUV.y)-0.5),1);
                // 这里我用了两个，是因为在循环处要么过于尖锐，要么分裂，这样感觉才好
                // _WavePos 用于控制海浪出现的位置，_WaveAngle用于控制海浪横向出现的角度大小
                float nv01 = clamp(((uv.x+_WavePos)*_WaveAngle - nv01m),w,1.0-w);
                float nv02 = clamp(((uv.x+_WavePos*1.5)*_WaveAngle - nv02m),w,1.0-w);
                float nv = lerp(nv01,nv02,smoothstep(0.05,0.3,nv01m));
                newUV = float2(nu,-nv);
                return newUV;
            }
            float3 getVdmSelf(float2 UV)
            {
                float2 gradient = SAMPLE_TEXTURE2D_LOD(_GradientTex,sampler_GradientTex,UV,0.0).xy;
                float sdf = SAMPLE_TEXTURE2D_LOD(_SDFTex,sampler_SDFTex,UV,0.0).x;
                float3 forward = float3(gradient.x,0,gradient.y);

                float ji = (atan2(UV.x-0.5,UV.y-0.5)+PI)/(2*PI); // 采样的y轴根据极坐标
                float2 sdfUV = float2(sdf*10,frac(ji*10.0));
                float2 sdfAUV = animUV(sdfUV*1.0,ji*10,- _Time.y, _VectorDisMap_ST);

                float3 ddisp = SAMPLE_TEXTURE2D_LOD(_VectorDisMap,sampler_VectorDisMap,sdfAUV,0.0).xyz;
                float3 vdm = decodeDisp(ddisp).x*forward + decodeDisp(ddisp).z*float3(0,1,0);
                return vdm;
            }

            // 这个是FluidFlux2中用到的方法
            float2 waveUV(float dis,float offset,float duanshu,float qingxie)
            {
                float u = frac(dis-_Time.y*_Speed+qingxie);
                float v = u - dis + offset ;
                v /= duanshu;
                return clamp(float2(u,v),0.01,0.99);
            }
            
            float3 getVdm(float2 UV)
            {
                // ================================= 获取世界位置偏移 ==================================
                // 根据梯度或者TS空间的向前轴
                float2 gradient = SAMPLE_TEXTURE2D_LOD(_GradientTex,sampler_GradientTex,UV,0.0).xy;
                float sdf = SAMPLE_TEXTURE2D_LOD(_SDFTex,sampler_SDFTex,UV,0.0).x;
                float3 forward = float3(gradient.x,0,gradient.y);

                float dis = -sdf*15.0;
                float3 dir = forward;
                float2 UUVV = waveUV(UV.x*5.0,3.0,2.0,-1.5*UV.y);
                UUVV = 1-waveUV( dis , 2.0  , 2.0 , 0.2*gradient.y - 0.2*gradient.x) ;
                float3 ddisp = SAMPLE_TEXTURE2D_LOD(_VectorDisMap,sampler_VectorDisMap,UUVV,0.0).xyz;
                float3 vdm = decodeDisp(ddisp).x*dir + decodeDisp(ddisp).z*float3(0,1,0);
                return vdm;
            }
            
            v2f vert (appdata v)
            {
                v2f o;
                // 传递实例ID到片元着色器（GPU Instancing必需）
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);
                // 自动处理GPU Instancing的矩阵
                VertexPositionInputs vertexInput = GetVertexPositionInputs(v.vertex.xyz);

                o.worldPos = vertexInput.positionWS;
                o.uv = v.uv;
                float scale = 20.0;
                float2 worldUV=1.0- (o.worldPos/scale + 0.5).xz;
                float2 UV = worldUV;
                UV = o.uv;
                UV = v.vertex.xz;
                UV = saturate(worldUV);

                float2 gradient = SAMPLE_TEXTURE2D_LOD(_GradientTex,sampler_GradientTex,UV,0.0).xy;
                float sdf = SAMPLE_TEXTURE2D_LOD(_SDFTex,sampler_SDFTex,UV,0.0).x;
                float3 forward = float3(gradient.x,0,gradient.y);

                float ji = (atan2(UV.x-0.5,UV.y-0.5)+PI)/(2*PI); // 采样的y轴根据极坐标
                float2 sdfUV = float2(sdf*5,frac(ji*10.0));
                float2 sdfAUV = animUV(sdfUV,ji*10,- _Time.y, _VectorDisMap_ST);
                float dis = -sdf*7.0;
                float3 dir = forward;
                float2 UUVV = 1-waveUV( dis , 1.0  , 2.0 , -1.5*gradient.y) ;
                //float3 ddisp = SAMPLE_TEXTURE2D_LOD(_VectorDisMap,sampler_VectorDisMap,UUVV,0.0).xyz;
                //float3 vdm =  decodeDisp(ddisp).x*dir + decodeDisp(ddisp).z*float3(0,1,0);

                o.newUV = UUVV;

                float3 vdm = getVdm(UV);
                vdm = getVdmSelf(UV);

                float3 vdmR = getVdm(UV+float2(0.01,0.0));
                vdmR = getVdmSelf(UV+float2(0.01,0.0));
                float3 vdmU = getVdm(UV+float2(0.0,0.01));
                vdmU = getVdmSelf(UV+float2(0.0,0.01));
                // 计算法线，这里需要注意的是，计算法线用的是世界坐标采样，因此，用这个映射过的世界坐标采样后
                // 得到的矢量位移信息转换到世界空间后，得在加上偏移后的世界位置，这样差分得到的法向才是对的
                float mask = step(sdf,0);
                mask *= smoothstep(0.5,0.45,abs(UV.x-0.5)) * smoothstep(0.5,0.45,abs(UV.y-0.5));
                o.uvMask = mask;
                float3 wp  = o.worldPos+TransformObjectToWorld(vdm*mask);
                float3 wpr = o.worldPos-float3(0.01*scale,0,0)+TransformObjectToWorld(vdmR*mask);
                float3 wpu = o.worldPos-float3(0,0,0.01*scale)+TransformObjectToWorld(vdmU*mask);
                //o.norWS = normalize(cross((wpu-wp),(wpr-wp)));
                //o.norWS = lerp(o.norWS, float3(0,1,0), 1.0);
                // 变换后的画面的TBN矩阵
                float3 waveT = normalize(wpu-wp);
                float3 waveB = normalize(wpr-wp);
                float3 waveN = cross(waveT,waveB);
                float3x3 waveTBN = float3x3(waveT,waveB,waveN);

                o.tanWave = waveT;
                o.bitWave = waveB;
                o.norWS = waveN;


                // 正常的水面起伏置换与法线计算
                float waterSurfMask = smoothstep(0.05,0.15,-sdf); // 在接近岸边的地方没有
                float4 waterSurf = waterSurfMask * SAMPLE_TEXTURE3D_LOD(_3DDisMap, sampler_3DDisMap, float3(v.uv,frac(_Time.y*_SurfSpeed)),0.0);
                float4 waterSurfR = waterSurfMask * SAMPLE_TEXTURE3D_LOD(_3DDisMap, sampler_3DDisMap, float3(v.uv+float2(0.01,0),frac(_Time.y*_SurfSpeed)),0.0);
                float4 waterSurfU = waterSurfMask * SAMPLE_TEXTURE3D_LOD(_3DDisMap, sampler_3DDisMap, float3(v.uv+float2(0,0.01),frac(_Time.y*_SurfSpeed)),0.0);
                //float3 surfNor = normalize(cross(waterSurfU.x-waterSurf.x, waterSurfR.x-waterSurf.x));
                float3 surfNor;
                float waveSurY = waterSurfU.x*_SurfScale01-waterSurf.x*_SurfScale01;
                float waveSurX = waterSurfR.x*_SurfScale01-waterSurf.x*_SurfScale01;
                surfNor.x = waveSurX*_SurfNorScale*10.0;
                surfNor.y = waveSurY*_SurfNorScale*50.0;
                surfNor.z = sqrt(1-pow(surfNor.x,2) - pow(surfNor.y,2));

                surfNor = mul(surfNor,waveTBN);
                //o.norWS = normalize(surfNor);
                o.ttt = float3(sdfAUV,0);
                //o.ttt = newpos;

                float3 newPos = v.vertex.xyz + vdm*mask + (waterSurf.x*_SurfScale01 + waterSurf.y*_SurfScale02) * waveN;;
                float3 deformWSPos = TransformObjectToWorld(newPos);

                o.pos = TransformObjectToHClip(newPos);

                o.screenUV = ComputeScreenPos(o.pos);
                
                o.viewDirWS = normalize(_WorldSpaceCameraPos - deformWSPos);
                o.deformWSPos = deformWSPos;
                
                return o;
            }
        ENDHLSL

        Pass
        {
            Tags {"LightMode" = "SRPDefaultUnlit"}
            ZWrite On
            ColorMask 0
            HLSLPROGRAM
            float4 frag (v2f i) : SV_Target
            {   
                return 0;
            }
            ENDHLSL
        }
        
        Pass
        {
            Tags { 
                "LightMode" = "UniversalForward"
            }
            ZWrite Off
            Cull Off
            Blend SrcAlpha OneMinusSrcAlpha

            HLSLPROGRAM
            
            #pragma multi_compile _ _ENVIRONMENTREFLECTIONS_OFF
            #pragma multi_compile _ _REFLECTION_PROBE_BLENDING
            #pragma multi_compile _ _REFLECTION_PROBE_BOX_PROJECTION


            float foamMask(float2 fuv,float2 fanimUV, float fDefaultFoam,float fFoamTex)
            {
                fDefaultFoam = pow(abs(fDefaultFoam),0.77);
                float midFoam = pow(abs(fanimUV.x),0.7) * pow(abs(fuv.x),4.8);
                midFoam = pow(abs(midFoam),0.9);
                float nearFoam = smoothstep(0.85,1.0,abs(fuv.x));
                float foam = midFoam + nearFoam + fDefaultFoam;
                foam = clamp(foam,0.0,1.0);
                foam *= fFoamTex;
                return foam;
            }

            float4 frag (v2f i) : SV_Target
            {
                // GPU Instancing：在片元着色器中设置实例ID
                // 如果需要访问实例属性，这是必须的
                UNITY_SETUP_INSTANCE_ID(i);


                float2 newUV = animUV(i.uv,1, _Time.y, _VectorDisMap_ST);
                newUV = i.newUV;
                float scale = 20.0;
                float2 worldUV=1.0- (i.worldPos/scale + 0.5).xz;
                
                // 还是在Frag Shader中计算水面起伏的法线，这样可以得到更准确的法线信息，之前在顶点着色器中计算的法线在这里做了一个修正
                float3 WaveNor = SAMPLE_TEXTURE3D(_3DDisMap, sampler_3DDisMap, float3(i.uv,frac(_Time.y*_SurfSpeed))).xyz;
                float3 Nor = float3((WaveNor.y*2.0-1.0)*_SurfNorScale,(WaveNor.z*2.0-1.0)*_SurfNorScale,0.0);
                Nor.z = sqrt(1-pow(Nor.x,2)-pow(Nor.y,2));
                float3x3 waveTBN = float3x3(i.tanWave,i.bitWave,i.norWS);
                Nor = mul(Nor,waveTBN);
                Nor = normalize(float3(Nor.z,Nor.y,-Nor.x));
            
                //return float4(float3(Nor.z,Nor.y,-Nor.x)*float3(1,1,1),1.0);

                // ========================= 基础数据准备 ==========================
                float3 viewDirWS = normalize(i.viewDirWS);
                float3 normal = normalize(i.norWS);
                normal = Nor;

                // 这个贴图的xy是矢量置换信息，z是海浪会出现浮沫的遮罩信息
                float3 dispCol = SAMPLE_TEXTURE2D(_VectorDisMap, sampler_VectorDisMap,newUV).rgb;
                float sdf = SAMPLE_TEXTURE2D(_SDFTex,sampler_SDFTex,worldUV).x;
                float foamM = smoothstep(0.2,0.0,-sdf); // 只有靠近岸边的地方采油浮沫

                // 这个贴图的xyz存储法线信息，w储存浮沫信息
                float4 waveTex = SAMPLE_TEXTURE2D(_OceanNorTex,sampler_OceanNorTex, i.uv * _OceanNorTex_ST.xy + _OceanNorTex_ST.zw);
                float foam = foamMask(worldUV, newUV, dispCol.z, waveTex.w) * foamM;

                // 用于修正浮沫在贴图边缘的白边问题
                float xz = (1.0-step(newUV.x,0.05))*(1.0-step(0.95,newUV.x));
                xz += smoothstep(0.45,1.0,i.uv.x);
                xz = clamp(xz,0.0,1.0);
                foam *= xz;
                foam *= i.uvMask;

                // 屏幕UV
                float2 screenUV = i.screenUV.xy/i.screenUV.w;

                // ==================== 折射效果 ====================
                // 根据法线偏移屏幕UV来模拟折射
                float2 refractionOffset = FFGetRefractionOffset(normal, viewDirWS, _RefractionStrength);
                float2 refractedScreenUV = screenUV + refractionOffset;
                refractedScreenUV = saturate(refractedScreenUV);
                
                // 采样折射后的背景深度
                float3 refractionDepth = SAMPLE_TEXTURE2D(_CameraDepthTexture,  sampler_CameraDepthTexture , refractedScreenUV).rgb;
                float depthLinear = LinearEyeDepth(refractionDepth.r,_ZBufferParams);
                float selfDepthLinear = LinearEyeDepth(i.pos.z,_ZBufferParams);
                float waterDepth = depthLinear - selfDepthLinear;
                float rampMask = smoothstep(0.0,2.0,waterDepth);

                float3 screenColor = SAMPLE_TEXTURE2D(_ScreenMipMapRT, sampler_ScreenMipMapRT, screenUV).rgb;
                //return float4(screenColor, 1.0);

                // 采样折射后的背景颜色
                // 使用自定义的带有Mipmap的屏幕不透明物体纹理，根据水深选择不同的Mipmap级别来采样颜色，以模拟水下物体的模糊效果
                //float3 refractionColor = SAMPLE_TEXTURE2D(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, refractedScreenUV).rgb;
                float mipmapDepRamp = smoothstep(_RefractionBlurStart,_RefractionBlurEnd,waterDepth);
                float3 mipmapScreenColor = SAMPLE_TEXTURE2D_LOD(_ScreenMipMapRT, sampler_ScreenMipMapRT, refractedScreenUV, mipmapDepRamp*_RefractionBlurStrength).rgb;
                float3 refractionColor = mipmapScreenColor;

                Light ld = GetMainLight();
                float3 lightDir = normalize(ld.direction);
                float3 lightColor = ld.color;
                
                // 根据水深应用水的吸收效果
                refractionColor = FFApplyWaterAbsorption(refractionColor, waterDepth, _AbsorptionColor);
                // 混合浅水与深水颜色，得到最终颜色
                //float3 albedo = lerp(_WaterCol,_DeepWaterCol,rampMask);
                
                // 将折射颜色与水体颜色混合
                //albedo = lerp(refractionColor, albedo, saturate(rampMask * 1.0));
                float3 albedo = refractionColor;
                

                // ==================== BSDF水体散射 ====================
                // 计算厚度（基于水深）
                float thickness = saturate(waterDepth / _DepthScale);
                
                // 计算消光系数和散射反照率
                float3 extinctionCoeff = _ScatterColor + _BSDFAbsorptionColor;
                float3 scatterAlbedo = _ScatterColor / max(extinctionCoeff, 1e-6);
                
                float3 bsdfScattering;
                
                #ifdef _USE_RAY_MARCHING
                    // 使用Ray Marching进行体积散射
                    FFRayMarchConfig rmConfig = FFCreateDefaultRayMarchConfig();
                    rmConfig.stepCount = (int)_RayMarchSteps;
                    rmConfig.maxDistance = min(waterDepth, _RayMarchMaxDistance);
                    
                    float3 rayDir = -viewDirWS;
                    rayDir.y = -abs(rayDir.y);
                    rayDir = normalize(rayDir);
                    
                    bsdfScattering = FFRayMarchVolumeScattering(
                        i.worldPos, rayDir, rmConfig.maxDistance,
                        extinctionCoeff, scatterAlbedo,
                        lightDir, viewDirWS, lightColor,
                        _PhaseG, 0.0, rmConfig
                    );
                    
                    bsdfScattering *= _RayMarchIntensity;
                    
                    float T_exit = FFFresnelExit(_FresnelF0, normal, viewDirWS);
                    bsdfScattering *= T_exit;
                #else
                    // 使用简化的BSDF计算
                    bsdfScattering = FFEvaluateWaterScattering(
                        normal, viewDirWS, lightDir, lightColor,
                        _ScatterColor, _BSDFAbsorptionColor,
                        thickness, _FresnelF0, _PhaseG,
                        0.0
                    );
                #endif
                
                // ==================== 高光计算 ====================
                // Blinn-Phong高光模型
                /*
                float3 specCol = FFCalculateSpecularBlinnPhong(
                    normal, viewDirWS, lightDir, lightColor,
                    _SpecularPower, _SpecularIntensity
                );
                */
                // GGX高光模型
                float3 specCol = FFCalculateSpecularGGXSimple(
                    normal, viewDirWS, lightDir, lightColor,
                    _Roughness,_SpecularIntensity
                );

                float fresnel = FFFresnelWater(normal, viewDirWS, _FresnelF0);
                fresnel = pow(abs(fresnel), _FresnelPower);

                // ==================== 环境反射 ====================
                float3 reflectDir = reflect(-viewDirWS, normal);
                float3 envReflection = FFSampleEnvReflection(reflectDir, _Roughness, _EnvReflectionStrength);
                float3 reflectionColor = FFBlendReflection(albedo, envReflection, fresnel, 1.0);

                // ==================== 最终颜色合成 ====================
                // 将BSDF散射与反射混合
                float3 finalColor = reflectionColor + lerp(float3(0,0,0), bsdfScattering, rampMask);
                finalColor += specCol;

                // ==================== SSS次表面散射 ====================
                #ifdef _USE_SSS
                {
                    float3 sss = FFComputeWaterSSSFull(
                        normal, normal, viewDirWS,
                        lightDir, lightColor, waterDepth,
                        _SSSColor, _SSSStrength, _SSSDepthScale, _SSSFade
                    );
                    finalColor += sss;
                    
                    float3 sunGlitter = FFComputeSunGlitterAnimated(
                        normal, viewDirWS, lightDir, lightColor,
                        _Roughness, _SunGlitterIntensity,
                        _Time.y, _SunGlitterSpeed
                    );
                    finalColor += sunGlitter;
                }
                #endif

                float alpha = lerp(saturate(rampMask*50.0), 1.0, fresnel * 0.5);

                return float4((finalColor+foam*4.0)*float3(1,1,1), alpha);
            }
            ENDHLSL
        }
            
    }
}
