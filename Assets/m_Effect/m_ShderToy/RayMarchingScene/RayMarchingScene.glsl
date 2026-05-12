// 材质结构体 - 包含漫反射和高光所需属性
struct Material {
    vec3 albedo;     // 漫反射颜色
    float roughness; // 粗糙度 (0-1，值越小高光越集中)
    vec3 F0;         //直射角反射率
};
// 光线结构体
struct Ray {
    vec3 origin;
    vec3 direction;
    int maxSteps;
    float maxDist;
};
//材质输出体
struct MatOut{
    vec3 diffuse;
    vec3 specular;
    float shadow;
    vec3 ambient;
};
// 击中信息结构体
struct HitInfo {
    float t;           // 光线行进距离
    vec3 position;     // 击中位置
    vec3 normal;       // 法向量
    Material material; // 材质
    bool hit;          // 是否击中
};
//------------------------------光源参数----------------------------
// 光源参数
vec3 lightPosition = vec3(4.0, 6.0, -3.0);
vec3 lightColor = vec3(1.0, 0.95, 0.9) * 1.8;

//---------------------------材质参数-------------------------------
// 球体材质 (高粗糙度，高光较分散)
Material sphereMaterial = Material(vec3(0.9, 0.9, 1.0), 0.9,vec3(0.003)); 
// 地面材质 (低粗糙度，高光较集中)
Material groundMaterial = Material(vec3(0.9), 0.1,vec3(0.04)); 
// 立方体材质 (高粗糙度，高光较分散)
Material boxMaterial1 = Material(vec3(1.0, 0.0, 0.0), 0.7,vec3(0.1)); 
Material boxMaterial2 = Material(vec3(0.0, 0.0, 1.0), 0.7,vec3(0.1)); 

//------------------------------SDF函数定义--------------------------------
// 球体距离场函数
float sphereSDF(vec3 p, vec3 center, float radius) {
    return length(p - center) - radius;
}
// 平面距离场函数
float planeSDF(vec3 p, float y) {
    return p.y - y;
}
//立方体距离场
float boxSDF(vec3 p,vec3 s){
    return length(max(abs(p)-s,0.0));

}
//----------------------------------获取SDF距离---------------------------
// 计算场景中最近的物体
HitInfo getDistance(vec3 p) {
    HitInfo info;
    info.hit = true;
    
    // 球体
    vec3 sphereCenter = vec3(0.0, 1.0, 0.0);
    float sphereRadius = 1.0;
    float sphereDist = sphereSDF(p, sphereCenter, sphereRadius);
    
    // 地面
    float planeDist = planeSDF(p, 0.0);

    //立方体
    float boxDist1 = boxSDF(p-vec3(0.0,1.0,1.25),vec3(1.0,1.25,0.01));
    float boxDist2 = boxSDF(p-vec3(-1.25,1.0,0.0),vec3(0.01,1.25,0.9));
    
    float d=min(sphereDist,planeDist);
    d=min(d,boxDist1);
    d=min(d,boxDist2);
    info.t = d;
    // // 确定哪个物体更近
    if (d==sphereDist) {
        //info.t = sphereDist;
        info.position = sphereCenter + normalize(p - sphereCenter) * sphereRadius;
        info.normal = normalize(p - sphereCenter);
        info.material = sphereMaterial;

    } else if(d==planeDist) {
        //info.t = planeDist;
        info.position = p - vec3(0.0, planeDist, 0.0);
        info.normal = vec3(0.0, 1.0, 0.0);
        
        // 地面棋盘格图案
        vec2 grid = floor(info.position.xz * 0.5);
        float checker = mod(grid.x + grid.y, 2.0);
        //checker=smoothstep(0.4,0.6,fract(grid.y));
        info.material = groundMaterial;
        info.material.albedo *= mix(1.0, 0.3, checker);
    } else if(d==boxDist1){
        info.normal = normalize(p - sphereCenter);
        info.material = boxMaterial1;
    } else if(d==boxDist2){
        info.normal = normalize(p - sphereCenter);
        info.material = boxMaterial2;
    }
    
    return info;
}
//--------------------------------------计算法线-------------------------------------------
vec3 calculateNormal(vec3 p, float eps) {
    // 获取当前点的距离场值
    float d = getDistance(p).t;
    
    // 计算三个坐标轴方向的偏导数（梯度）
    float dx = getDistance(p + vec3(eps, 0.0, 0.0)).t - d;
    float dy = getDistance(p + vec3(0.0, eps, 0.0)).t - d;
    float dz = getDistance(p + vec3(0.0, 0.0, eps)).t - d;
    
    // 梯度向量就是法向量的近似，归一化后返回
    vec3 normal = vec3(dx, dy, dz);
    return normalize(normal);
}
//---------------------------------------GI框架函数--------------------------------------
// 生成伪随机数：常规随机数生成
float rand(vec2 co) {
    return fract(sin(dot(co.xy ,vec2(12.9898,78.233))) * 43758.5453);
}
// 生成随机向量
vec3 randomVec3(vec2 seed) {
    return vec3(
        rand(seed),
        rand(seed + vec2(1.2345, 6.7890)),
        rand(seed + vec2(9.8765, 4.3210))
    );
}

// 在法线半球上生成随机点
// 先随机生成点，再用dot判断是否在正半球
vec3 hemisphereSampleSimple(vec3 normal, vec2 seed) {
    // 生成一个[-1, 1]范围内的随机向量
    vec3 randomDir = randomVec3(seed) * 2.0 - 1.0;
    // 归一化
    randomDir = normalize(randomDir);//只有这样才能跟判断是不是在法线半球
    // 使用点积判断是否在正半球
    // 如果点积为负，说明在反方向，翻转向量
    if (dot(randomDir, normal) < 0.0) {
        randomDir = -randomDir;
    }
    return randomDir;
}

// 光线步进求交
HitInfo GIrayMarch(Ray ray) {
    HitInfo hit;
    hit.hit = false;
    int maxSteps = ray.maxSteps;
    const float minDist = 0.001;//发现得这个调小
    float maxDist = ray.maxDist;
    float t = minDist+0.1;//这个初始值增大，不然会有黑色波纹
    
    for (int i = 0; i < maxSteps; i++) {
        vec3 p = ray.origin + ray.direction * t;
        HitInfo info = getDistance(p);
        
        if (info.t < minDist) {
            info.position=p;
            hit = info;
            hit.t = t;
            hit.hit = true;
            break;
        }
        if (t > maxDist) {
            break;
        }
        t += info.t;
    }
    return hit;
}
//--------------------------------------光线步进函数--------------------------------------
// 光线步进求交
HitInfo rayMarch(Ray ray) {
    HitInfo hit;
    hit.hit = false;
    int maxSteps = ray.maxSteps;
    const float minDist = 0.01;
    float maxDist = ray.maxDist;
    float t = minDist;
    
    for (int i = 0; i < maxSteps; i++) {
        vec3 p = ray.origin + ray.direction * t;
        HitInfo info = getDistance(p);
        
        if (info.t < minDist) {
            info.position=p;
            hit = info;
            hit.t = t;
            hit.hit = true;
            break;
        }
        if (t > maxDist) {
            break;
        }
        t += info.t;
    }
    return hit;
}
//-------------------------------------阴影投射函数---------------------------------------
// 计算阴影
float calculateShadow(vec3 origin, vec3 normal, vec3 lightDir, float lightDist, float k) {
    Ray shadowRay;
    shadowRay.origin = origin + normal * 0.01;
    shadowRay.direction = lightDir;
    lightDir = normalize(lightDir);
    
    float t = 0.01;
    const int maxSteps = 50;
    const float minDist = 0.001;
    float res = 1.0;
    float ph = 1e20;
    
    for (int i = 0; i < maxSteps; i++) {
        vec3 p = shadowRay.origin + shadowRay.direction * t;
        float dist = getDistance(p).t;
        
        if (dist < minDist) {
            return 0.0;
        }
        
        if (t > lightDist) {
            break;
        }
        float y = dist * dist / (2.0 * ph);
        float d = sqrt(dist * dist - y * y);
        float w = 1.0 / k;
        res = min(res, d / (w * max(0.0, t - y)));
        ph = dist;
        t += dist;
    }
    return res;
}
// Lambert漫反射模型
vec3 lambertDiffuse(Material mat, vec3 normal, vec3 lightDir) {
    float NdotL = max(dot(normal, lightDir), 0.0);
    return mat.albedo / 3.1415926 * NdotL;
}

// ----------------------- Cook-Torrance高光模型组件 ---------------------------

// 菲涅尔方程 (Schlick近似) - 描述不同角度下反射光的比例
vec3 fresnelSchlick(float cosTheta, vec3 F0) {
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

// 正态分布函数 (GGX) - 描述微平面的分布，决定高光的集中程度
float distributionGGX(vec3 N, vec3 H, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH = max(dot(N, H), 0.0);
    float NdotH2 = NdotH * NdotH;
    
    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    denom = 3.1415926 * denom * denom;
    
    return a2 / denom;
}

// 几何函数 (Smith) - 描述微平面相互遮挡的程度
float geometrySmith(vec3 N, vec3 V, vec3 L, float roughness) {
    float r = (roughness + 1.0);
    float k = (r * r) / 8.0; // 直接光照下的k值
    
    float NdotV = max(dot(N, V), 0.0);
    float ggxV = NdotV / (NdotV * (1.0 - k) + k);
    
    float NdotL = max(dot(N, L), 0.0);
    float ggxL = NdotL / (NdotL * (1.0 - k) + k);
    
    return ggxV * ggxL;
}

// Cook-Torrance高光计算
vec3 cookTorranceSpecular(Material mat, vec3 N, vec3 V, vec3 L) {
    // 计算半程向量 (光线方向与视线方向的中间向量)
    vec3 H = normalize(V + L);
    
    // 基础反射率 (非金属使用0.04，金属使用自身颜色)
    vec3 F0 = mat.F0;
    
    // 菲涅尔项
    float cosTheta = max(dot(H, V), 0.0);
    vec3 F = fresnelSchlick(cosTheta, F0);
    
    // 正态分布项
    float D = distributionGGX(N, H, mat.roughness);
    
    // 几何项
    float G = geometrySmith(N, V, L, mat.roughness);
    
    // Cook-Torrance公式
    vec3 numerator = F * D * G;
    float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001;
    vec3 specular = numerator / denominator;
    
    return specular;
}
//--------------------------------------相机射线函数----------------------------------------
// 生成相机射线
Ray getCameraRay(vec2 uv, vec3 cameraPos, vec3 lookAt) {
    Ray ray;
    ray.origin = cameraPos;
    
    vec3 forward = normalize(lookAt - cameraPos);
    vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), forward));
    vec3 up = cross(forward, right);
    
    float aspect = iResolution.x / iResolution.y;
    float fov = 60.0 * 3.1415926535 / 180.0;
    float tanHalfFov = tan(fov / 2.0);
    
    vec3 rayDir = forward + right * uv.x * tanHalfFov * aspect + up * uv.y * tanHalfFov;
    ray.direction = normalize(rayDir);

    ray.maxDist=100.0;
    ray.maxSteps=50;
    
    return ray;
}
//---------------------------------------SDF AO------------------------------------------
float SDFAO(vec3 p,vec3 normal){
    float ao;
    float perStep=0.05;
    float scale=0.5;
    float k=15.0;
    for(int i=0;i<=5;i++){
        float distDelta=perStep*float(i);
        float distField=getDistance(p+distDelta*normal).t;
        ao += (distDelta-distField)*scale;
        scale*=0.5;
        if(ao>0.2)break;
    }
    return clamp((1.0-k*ao),0.0,1.0);
}
//-----------------------------------云-分型布朗运动-----------------------
// 基础伪随机函数
vec2 rand2(vec2 co) {
    return fract(sin(vec2(dot(co, vec2(12.9898, 78.233)),
                          dot(co, vec2(63.7264, 10.8885)))) * 43758.5453);
}
// 基础2D噪波函数
float noise2D(vec2 st) {
    vec2 i = floor(st);
    vec2 f = fract(st);
    // 四个角的随机值
    float a = rand2(i).x;
    float b = rand2(i + vec2(1.0, 0.0)).x;
    float c = rand2(i + vec2(0.0, 1.0)).x;
    float d = rand2(i + vec2(1.0, 1.0)).x;
    // 平滑插值曲线
    vec2 u = f * f * (3.0 - 2.0 * f);
    // 双线性插值
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
// 2D分形布朗运动(FBM)
float fbm2D(vec2 st, int octaves, float lacunarity, float gain) {
    // st/p：2D/3D 坐标输入
    // octaves：叠加的噪波层数（八度数量），值越高细节越丰富（通常 3-8）
    // lacunarity：频率倍增因子，控制每次迭代的频率增长（通常 1.5-3.0）
    // gain：振幅衰减因子，控制每次迭代的振幅衰减（通常 0.4-0.6）
    float total = 0.0;    // 累积结果
    float amplitude = 1.0; // 振幅，每次迭代乘以gain，
    float frequency = 1.0; // 频率，每次迭代乘以。
    float maxAmplitude = 0.0; // 用于归一化结果
    
    for(int i = 0; i < octaves; i++) {
        total += noise2D(st * frequency) * amplitude;
        maxAmplitude += amplitude;
        amplitude *= gain;
        frequency *= lacunarity;
    }
    
    // 归一化结果到[-1, 1]范围
    return total / maxAmplitude;
}
//--------------------------------材质输出函数---------------------------------------------------------------
MatOut getOut(HitInfo hit,vec3 viewDir,vec3 lightDir){
    MatOut outm;
    lightDir = normalize(lightDir);
    float lightDist = length(lightDir);
    // 计算阴影
    //float shadow = calculateShadow(hit.position, hit.normal, lightDir, lightDist, 10.0);
        
    // 计算漫反射
    outm.diffuse = lambertDiffuse(hit.material, hit.normal, lightDir);
        
    // 计算Cook-Torrance高光
    outm.specular = cookTorranceSpecular(hit.material, hit.normal, viewDir, lightDir);
        
    // 添加环境光
    outm.ambient = hit.material.albedo * 0.05;
    return outm;
}

// ------------------------------------------------主函数----------------------------
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = (fragCoord * 2.0 - iResolution.xy) / iResolution.y;
    uv.x/=iResolution.x/iResolution.y;
    // 相机动画
    float time = iTime * 0.3;
    vec3 cameraPos = vec3(5.0 * cos(time), 3.0, 5.0 * sin(time));
    vec3 lookAt = vec3(0.0, 1.0, 0.0);
    
    Ray ray = getCameraRay(uv, cameraPos, lookAt);
    HitInfo hit = rayMarch(ray);
    

    // 基础天空色
    vec3 sky = mix(vec3(0.8, 0.9, 1.0), vec3(0.1, 0.25, 0.5), uv.y *0.5 + 0.5);
    //底部天空颜色
    vec3 farSky=vec3(0.5,0.55,0.65);//远处天空颜色
    sky = mix(farSky,sky,pow(smoothstep(0.5,0.8,uv.y),1.0));//两天混合
    //设置太阳
    vec3 sunPos=normalize(vec3(0.8,0.2,-0.75));//太阳位置朝向
    float sunlight =max(0.,dot(ray.direction,sunPos));//太阳方向与视角点积
    sunlight=pow(smoothstep(0.96,1.0,sunlight),2.0)*0.2+  //外围光晕
             pow(smoothstep(0.998,1.0,sunlight),20.0)*0.5;//内部太阳
    vec3 color = mix(sky,vec3(1),sunlight);//太阳合成

    //云
    float cloudHeight=200.;//云的高度
    //云的UV位置计算
    //射线击中云的长度t
    float cloudDepth=(cloudHeight-ray.origin.y)/ray.direction.y;
    vec3 cloudUV=ray.origin + cloudDepth * ray.direction;
    //乘以朝上的射线方向是为了只取顶部的云，不然地下也会有
    float cloud=fbm2D(cloudUV.xz*0.0015,3,2.0,0.5)*max(0.,sign(ray.direction.y));
    cloud=smoothstep(0.3,1.0,cloud)*0.5;//云的强度调整
    cloud*=ray.direction.y*10.0;//远处的云变淡
    //把云合成进去
    color=mix(color,vec3(1.0,0.9,1.0),cloud);
    
    vec3 hitPos;

    if (hit.hit) {
        hit.normal=calculateNormal(hit.position, 0.01);
        // 计算光源方向和距离
        vec3 lightDir = lightPosition - hit.position;
        float lightDist = length(lightDir);
        lightDir = normalize(lightDir);

        // 计算视线方向 (从表面指向相机)
        vec3 BaseViewDir = normalize(cameraPos - hit.position);

        //反射光光线追踪
        Ray reflection = Ray(hit.position,reflect(-BaseViewDir,hit.normal),50,25.0);
        HitInfo bounce = rayMarch(reflection);
        vec3 reflectLightDir = lightPosition - bounce.position;
        float reflectLightDist = length(reflectLightDir);
        reflectLightDir=normalize(reflectLightDir);


        // 计算视线方向 (从表面指向相机)
        vec3 viewDir = normalize(cameraPos - hit.position);

        float ao=SDFAO(hit.position,hit.normal);

        MatOut output1 = getOut(hit,BaseViewDir,lightDir);//基础漫反射
        MatOut output2 = getOut(bounce,viewDir,reflectLightDir);//反射
        //MatOut output3 = getOut(bounce,viewDir,lightDir,lightDist);//反射
        //output2.diffuse=mix(sky,output2.diffuse,float(bounce.hit));


        // 计算阴影
        float shadow = calculateShadow(hit.position, hit.normal, lightDir, lightDist, 10.0);
        float shadow2 = calculateShadow(bounce.position, bounce.normal, reflectLightDir, reflectLightDist, 10.0);
        //hit.material.shadow=shadow;
        

        //GI
        HitInfo GI;
        MatOut GIout;
        int giCount=10;
        for(int g=1;g<=giCount;g++){
            // 关键：用Halton序列生成种子（index = g + 偏移量，避免重复）
            // 加一个基于像素坐标的偏移，确保不同像素的采样序列不同
            // 用像素坐标和时间生成随机扰动种子
            float rndSeed = fract(fragCoord.x * 0.123 + fragCoord.y * 45.678 + iTime * 9.012);
            int index = g;
            //vec2 haltonSeed = halton2D(index,rndSeed); // 替换随机seed为Halton序列
            vec2 seed=vec2(float(g)*hit.position.x*hit.position.z,float(giCount)*hit.position.x);
           
            vec3 randDir=hemisphereSampleSimple(hit.normal,seed);

            Ray GIRay = Ray(hit.position,randDir,20,5.0);
            HitInfo GIperhit = GIrayMarch(GIRay);
            
            GI.normal+=GIperhit.normal/float(giCount);
            GI.position+=GIperhit.position/float(giCount);

            MatOut perGIout=getOut(GIperhit,viewDir,lightDir);

            //间接光照的贡献应是采样点的辐射度 × 当前材质的漫反射系数（即albedo/π）。
            // 在GI循环中，计算采样点的总辐射度（直接+间接）
            // vec3 sampleRadiance = (perGIout.diffuse + perGIout.specular) * lightColor * shadow + perGIout.ambient;
            // 间接光照贡献 = 采样点辐射度 × 当前材质的漫反射BRDF（albedo/π）
            // GIout.diffuse += sampleRadiance * (hit.material.albedo / 3.14159) / float(giCount);
            
            GI.material.albedo += GIperhit.material.albedo/float(giCount);
            GI.material.albedo/=pow(length(GIperhit.position-hit.position)*2.0,2.0);
            float NdotL = max(dot(GIperhit.normal, normalize(lightPosition - GIperhit.position)), 0.0);
            vec3 diffuse = GIperhit.material.albedo/3.1415926*NdotL+0.4*GIperhit.material.albedo;

            GIout.diffuse+=diffuse/float(giCount);
        }
        //根据击中点跟发射点的距离衰减辐射强度
        float k=1.25;//衰减强度
        GIout.diffuse/=max(1.0,(pow(length(GI.position-hit.position)*k,2.0)));

        //击中阴影区不直接反射光,所以先计算间接光的阴影
        // vec3 GILightDir = lightPosition - GI.position;
        // float GILightDist = length(lightDir);
        // lightDir = normalize(GILightDir);
        // float shadow3 = calculateShadow(GI.position, GI.normal, GILightDir, GILightDist, 10.0);
        //GIout.diffuse*=clamp(shadow3+0.2,0.0,1.0);

        // 最终颜色 = (漫反射 + 高光) * 光源颜色 * 阴影 + 环境光
        vec3 out1 = (output1.diffuse + output1.specular) * lightColor*shadow + output1.ambient;
        vec3 out2 = (output2.diffuse + output2.specular) * lightColor*shadow2 + 0.2*bounce.material.albedo;
        out2=mix(sky,out2,float(bounce.hit));

        vec3 H = normalize(viewDir + lightDir);
        vec3 Fresnel = fresnelSchlick(max(dot(hit.normal, viewDir), 0.0), hit.material.F0);

        color=out1+(out2*Fresnel*pow((hit.material.roughness*-1.0+1.0),4.0));
        color+=GIout.diffuse*pow((hit.material.roughness),4.0)*ao;//加上间接光
        color*=ao;
        
        //float distField=getDistance(hit.position+hit.normal*0.1).t;

        //场景雾气
        vec3 frogCol=vec3(0.3,0.4,0.5);//雾气颜色
        float FrogMDist=40.0;float FrogNDist=20.0;//雾气变化最远跟最近距离
        float frogDepth=clamp(hit.t-FrogNDist,0.0,FrogMDist)/FrogMDist;
        color=mix(color,0.6*frogCol,frogDepth);

        //Gamma校正
        color = pow(color, vec3(0.4545));
        

    }
    //color=hit.t/100.0*vec3(1);
    //color =vec3(1)*fbm2D(uv*20.0,3,2.0,0.5);
    //color=cloud*vec3(1);
    //color=max(0.,sign(ray.direction.y))*vec3(1);
    //color=ray.direction.y*10.0*vec3(1);
    fragColor = vec4(color,1.0);
}
