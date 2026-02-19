#ifndef FLOW_DROP_FUNC_LIBRARY_HLSL
#define FLOW_DROP_FUNC_LIBRARY_HLSL

//#ifndef S(a,b,t)
#define S(a,b,t) smoothstep(a,b,t)
//#endif                                                       


float3 N13(float p) {
    // 来自DAVE HOSKINS的哈希函数
    float3 p3 = frac(float3(p,p,p) * float3(0.1031, 0.11369, 0.13787));
    p3 += dot(p3, p3.yzx + 19.19);
    return frac(float3((p3.x + p3.y)*p3.z, (p3.x+p3.z)*p3.y, (p3.y+p3.z)*p3.x));
}

float4 N14(float t) {
    return frac(sin(t*float4(123.0, 1024.0, 1456.0, 264.0)) * float4(6547.0, 345.0, 8799.0, 1564.0));
}

float N(float t) {
    return frac(sin(t*12345.564)*7658.76);
}

float Saw(float b, float t) {
    return S(0.0, b, t) * S(1.0, b, t);
}

float2 DropLayer2(float2 uv, float t,float scale=1.0) {
    float2 UV = uv;
    uv.y += t * 0.75;
    float2 a = float2(6.0, 1.0);
    float2 grid = a * 2.0;
    float2 id = floor(uv * grid);
    
    float colShift = N(id.x); 
    uv.y += colShift;
    id = floor(uv * grid);
    float3 n = N13(id.x * 35.2 + id.y * 2376.1);
    float2 st = frac(uv * grid) - float2(0.5, 0.0);
    
    float x = n.x - 0.5;
    float y = UV.y * 20.0;
    float wiggle = sin(y + sin(y));
    x += wiggle * (0.5 - abs(x)) * (n.z - 0.5);
    x *= 0.7;
    
    float ti = frac(t + n.z);
    y = (Saw(0.85, ti) - 0.5) * 0.9 + 0.5;
    float2 p = float2(x, y);
    
    float d = length((st - p) * a.yx);
    float mainDrop = S(0.3*scale, 0.0, d);
    
    float r = sqrt(S(1.0, y, st.y));
    float cd = abs(st.x - x);
    float trail = S((0.15*scale) * r , 0.0 * r * r, cd);
    float trailFront = S(-0.02, 0.02, st.y - y);
    trail *= trailFront * r * r;
    
    y = UV.y;
    float trail2 = S(0.2 * r, 0.0, cd);
    float droplets = max(0.0, (sin(y * (1.0 - y) * 120.0) - st.y)) * trail2 * trailFront * n.z;
    y = frac(y * 10.0) + (st.y - 0.5);
    float dd = length(st - float2(x, y));
    droplets = S(0.3, 0.0, dd);
    float m = mainDrop ;//;+ droplets * r * trailFront;
    
    return float2(mainDrop, trail);
}

float StaticDrops(float2 uv, float t,float scale=1.0) {
    uv *= 40.0;
    float2 id = floor(uv);
    uv = frac(uv) - 0.5;
    float3 n = N13(id.x * 107.45 + id.y * 3543.654);
    float2 p = (n.xy - 0.5) * 0.7;
    float d = length(uv - p);
    float fade = Saw(0.025, frac(t/2.0 + n.z));
    float c = S(saturate(0.2*scale - fade*0.2*scale), 0.0, d) * frac(n.z * 10.0) ;
    c = pow(c,0.5);
    return c;
}

float2 Drops(float2 uv, float t, float l0, float l1, float l2) {
    float s = StaticDrops(uv/3.0, t) * l0; 
    float2 m1 = DropLayer2(uv, t) * l1;
    float2 m2 = DropLayer2(uv * 1.85, t) * l2;
    float c = s + m1.x + m2.x;
    c = pow(S(0.20, 1.0, c),0.5)*0.5;
    return float2(s, max(m1.y * l0, m2.y * l1));
}
// 定制的角色水滴函数
// 以下参数中两个uv，第一个是动态的，第一个是静态的
// t 为时间
// l0，l1，l2 为水滴的大小
// stMask 为静态水滴的遮罩，默认为1.0，不影响效果
// dyMask 为动态水滴的遮罩，默认为1.0，不影响效果
float2 ActorDrops(float2 uv, float2 suv,float t, float l0, float l1, float l2,float stMask = 1.0,float dyMask = 1.0) {
    float s = StaticDrops(suv, t , l0)*2.0; 
    float2 m1 = DropLayer2(uv, t, l1)*0.5;
    m1.x = S(0.3,1.0,m1.x);
    float2 m2 = DropLayer2(uv * 1.85, t , l2)*0.5;
    m2.x = S(0.3,1.0,m2.x);
    float c = max( stMask*s , dyMask*max( m1.x , m2.x ) );
    //c = pow(S(0.20, 1.0, c),0.5)*1.0;
    c = pow(c,0.5);
    return float2(c, S(0.0,0.3,dyMask*max(m1.y, m2.y)));
}
#endif // FLOW_DROP_FUNC_LIBRARY_HLSL