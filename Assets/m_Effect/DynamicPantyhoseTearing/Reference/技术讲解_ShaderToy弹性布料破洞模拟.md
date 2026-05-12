# ShaderToy 弹性布料破洞模拟 — 技术架构详解

> 原项目作者: fenix (2022)  
> License: CC BY-NC-SA 3.0  
> 四个 Shader Pass: Common / Buffer A / Buffer B / Image
> 项目链接：https://www.shadertoy.com/view/NlKBW3

---

## 一、总体架构

该项目利用 **ShaderToy 的多 Pass（Multi-Pass/Buffer）机制** 实现了一个完整的弹性布料物理模拟 + 渲染管线。四个 Pass 的职责如下：

```
┌──────────┐    ┌──────────┐    ┌──────────┐
│  Common  │    │ Buffer A │    │ Buffer B │
│  公共函数 │◄───│ 物理模拟  │───►│Voronoi索引│
│  数据结构 │    │ (粒子位置) │    │(最近粒子) │
└──────────┘    └──────────┘    └─────┬────┘
                                      │
                                ┌─────▼────┐
                                │  Image   │
                                │ 最终渲染  │
                                └──────────┘
```

- **Common**: 所有 Pass 共享的基础函数、数据结构、Hash 函数、相机系统
- **Buffer A**: 核心物理模拟 — 更新每个粒子的位置、处理约束、检测撕裂
- **Buffer B**: 空间索引 — 为屏幕每个像素找到最近的 4 个粒子（类 Voronoi 追踪）
- **Image**: 最终渲染 — 基于 Buffer B 的结果绘制粒子间的连线

**ShaderToy 数据流关系**:
- `iChannel0` = Buffer A（粒子位置数据）
- `iChannel1` = Buffer B（每像素最近粒子索引）
- `iChannel3` = 键盘输入

---

## 二、数据结构设计

### 2.1 粒子缓冲区布局

所有粒子数据存储在一张 **一维 2D 纹理** 中，这是一种经典的 GPU 数据压缩策略：

```
纹理宽度 = iResolution.x
每个粒子占用 2 个 texel（POS 和 PREV）
粒子在纹理中的布局:

  X=0       X=1       X=2       X=3       X=4    ...
┌─────────┬─────────┬─────────┬─────────┬───────┐
│ P0.POS  │ P0.PREV │ P1.POS  │ P1.PREV │ P2... │  Row 0
├─────────┼─────────┼─────────┼─────────┼───────┤
│   ...   │   ...   │   ...   │   ...   │       │  Row 1
└─────────┴─────────┴─────────┴─────────┴───────┘
```

从粒子 ID 计算纹理坐标：

```glsl
// POS=0, PREV=1
ivec2 fxLocFromIDInternal(int width, int id, int dataType) {
    int index = id * 2 + dataType;  // 每个粒子2个数据槽
    return ivec2(index % width, index / width);
}
```

### 2.2 粒子数据结构 (fxParticle)

```glsl
struct fxParticle {
    vec3 pos;       // 当前位置 (存于 POS 槽位的 xyz)
    vec3 prev;      // 上一帧位置 (存于 PREV 槽位的 xyz)
    bool pinned;    // 是否被固定 (存于 PREV 槽位的 w 分量)
    bool disabled;  // 是否已撕裂/失活 (存于 POS 槽位的 w 分量)
};
```

- **pinned 粒子**: 布料边缘的粒子被钉住，不受重力影响，用于模拟挂起的布料
- **disabled 粒子**: 被撕裂后标记为失活，不再参与物理和渲染

### 2.3 状态纹理 (Buffer B 像素 (0,0))

Buffer B 的 `(0,0)` 像素用作全局状态存储：

```glsl
state.x = 分辨率信息（负值表示需要重置）
state.yz = 鼠标位置（用于交互撕裂）
state.w = 自动吸引模式的计时器
```

---

## 三、粒子网格与邻居系统

### 3.1 布料网格初始化

布料是一个 **CLOTH_SIDE × CLOTH_SIDE** 的正方形粒子阵列：

```glsl
CLOTH_SIDE = int(sqrt(res.x * res.y / 2) * particleUse);
MAX_PARTICLES = CLOTH_SIDE * CLOTH_SIDE;
```

- `particleUse` 根据分辨率动态调整（0.7 基础值，高分辨率下略微降低至 ~0.58）
- 粒子初始排列在一个 **旋转 45° 的正方形** 中：

```glsl
p.pos = vec3(x + y, x - y, 0.) * SIDE_LEN / sqrt(2.);
// 形成典型的布料悬挂形状 — 上边水平，两侧下垂
```

### 3.2 邻居查找函数

粒子网格是规则排列的，因此通过纯算术即可找到四向邻居：

```glsl
above(i):  return i - CLOTH_SIDE   // 上邻居（行号-1）
below(i):  return i + CLOTH_SIDE   // 下邻居（行号+1）
left(i):   return i - 1            // 左邻居（列号-1）
right(i):  return i + 1            // 右邻居（列号+1）
```

每个函数都包含边界检查，边界外的返回 `-1`。**关键设计**：如果输入已经是 `-1`（失活邻居链），继续返回 `-1`，这样后续的迭代约束循环不需要立即终止。

---

## 四、物理模拟（Buffer A）— 核心算法

### 4.1 Verlet 积分器

使用速度无关的 Verlet 积分方案，速度隐含在位移中：

```glsl
p.prev = p.pos;
p.pos += (p.pos - p.prev) + GRAVITY;
```

- `(p.pos - p.prev)` 隐含了上一帧的速度
- Verlet 比 Euler 更稳定，不需要显式存储速度
- 重力 `GRAVITY = vec3(0, -1, 0)` 每帧直接作用

### 4.2 风力模拟

```glsl
p.pos.z += WIND_SPEED * sin(float(id % CLOTH_SIDE) * WIND_RIPPLE + iTime * WIND_CHANGE_RATE);
```

- 沿 Z 轴施加正弦风力
- 风力随粒子列号 (`id % CLOTH_SIDE`) 变化产生波纹效果（`WIND_RIPPLE = 0.01`）
- 随时间缓慢变化 (`WIND_CHANGE_RATE = 0.5`)

### 4.3 多距离约束系统（核心创新）

这是该项目**最关键的算法创新** — 不是只约束相邻粒子，而是沿四个方向**迭代延伸到更远的粒子**：

```
传统方案: 只约束直接邻居
         ○───○───○
         │   │   │
         ○───●───○     ● 仅约束4个邻居
         │   │   │
         ○───○───○

本方案: 约束多级邻居
         ○───○───○
         │\  │  /│
         ○───●───○     约束范围沿四个方向逐层延伸
         │/  │  \│     i=1,2,...,CARDINAL_ITERATIONS
         ○───○───○
```

**基数方向约束（上下左右）**：

```glsl
for (float i = 1.; i < 45.; ++i) {
    a = above(a);  b = below(b);
    r = right(r);  l = left(l);

    float sLen = EDGE_LEN * i;     // 距离越远，期望长度越大
    constraint(a, p, sLen);        // 约束上方第 i 个粒子
    constraint(b, p, sLen);        // 约束下方第 i 个粒子
    constraint(r, p, sLen);        // 约束右方第 i 个粒子
    constraint(l, p, sLen);        // 约束左方第 i 个粒子
}
```

**对角线约束**（可选，默认开启）：

```glsl
for (float i = 1.; i < 25.; ++i) {
    ar = above(right(ar));  // 右上
    al = above(left(al));   // 左上
    br = below(right(br));  // 右下
    bl = below(left(bl));   // 左下

    float dLen = EDGE_LEN * i * sqrt(2.);  // 对角线期望长度
    // ...约束4个对角方向
}
```

**为什么要多级约束？**

- 传统近邻约束的布料非常"柔软"，大范围弯曲阻力弱
- 多级约束让每个粒子"知道"它和远处粒子应有的距离关系
- 相当于同时施加了 **拉伸约束** 和 **弯曲约束**
- 迭代 45 层 + 25 层对角 = 每个粒子每帧求解 **280 个约束**，这是稳定性的代价

### 4.4 约束求解器（Position-Based Dynamics 风格）

```glsl
void constraint(inout int nid, inout fxParticle p, float edgeLen) {
    if (nid < 0) return;  // 无效邻居，跳过

    fxParticle n = fxGetParticle(nid);

    if (n.disabled) {     // 邻居已撕裂，标记为无效
        nid = -1;
        return;
    }

    vec3 deltaPos = n.pos - p.pos;
    float len = length(deltaPos);
    vec3 dir = deltaPos / len;

    float error = len - edgeLen;

    // 仅轻微抵抗压缩（布料可以被挤压）
    if (error < 0.) error *= COMPRESSION_RESIST;  // 0.005

    // 撕裂检测：如果邻居粒子位移超过阈值，当前粒子撕裂
    if (distance(p.prev, n.pos) > edgeLen * EDGE_BREAK_LEN)
        p.disabled = true;

    // 位置修正：固定粒子权重更高（f=1.0 vs f=0.7）
    float f = n.pinned ? 1.0 : 0.7;
    p.pos += dir * error * f;
}
```

**关键设计决策**：

| 特性 | 处理方式 | 原因 |
|------|---------|------|
| 拉伸（正误差） | 完全修正 | 布料不应被明显拉长 |
| 压缩（负误差） | 仅 0.5% 修正 | 允许布料自然折叠/起皱 |
| 固定粒子 | 权重 1.0 | pinned 粒子不可移动，对方全量修正 |
| 普通粒子 | 权重 0.7 | 双边各修正一部分，避免过冲 |

### 4.5 撕裂机制

```glsl
if (distance(p.prev, n.pos) > edgeLen * EDGE_BREAK_LEN)
    p.disabled = true;
```

- 比较**当前粒子上一帧位置**与**邻居当前位置**的距离
- 超过 `edgeLen × 5` 即判定为断裂
- 断裂的粒子被标记 `disabled = true`
- 一旦 disable，粒子不再参与约束求解，其邻居的连接也会逐级断裂
- 这种级联效应导致裂缝可以自然**传播**

### 4.6 鼠标/自动交互撕裂

有两种模式切割布料：

1. **鼠标拖拽模式**：检测粒子投影到屏幕后是否位于鼠标拖拽线附近
2. **自动吸引模式**：预设一条旋转的线段，周期性横扫布料表面

```glsl
// 粒子投影到屏幕空间，检测是否接近切割线
float dist2 = fxLinePointDist2(from, to, posCamera.xy);
if (dist2 < 0.0005) p.disabled = true;
```

---

## 五、空间索引（Buffer B）— Voronoi 追踪

Buffer B 借鉴了 [Gijs 的 Voronoi Tracking 技术](https://www.shadertoy.com/view/WltSz7)，为每个屏幕像素维护**最近的 4 个粒子 ID**。

### 5.1 为什么需要空间索引？

渲染时，Image Pass 需要知道每个屏幕像素附近有哪些粒子才能画线。如果每个像素遍历所有粒子（~6000+），性能无法接受。Buffer B 将搜索收敛到 O(1) 的纹理查询。

### 5.2 核心算法

**每个像素存储 4 个最近粒子**（RGBA 四个通道各存一个 ID），通过 `insertion_sort` 维护距离排序：

```glsl
void insertion_sort(inout ivec4 ids, inout vec4 dists, int newId, float newDist) {
    // 如果新的距离比第4近的还小，插入到正确位置
    // ids[0] 总是最近的，ids[3] 是第4近的
}
```

**搜索策略（三种来源混合）**：

| 阶段 | 搜索范围 | 搜索次数 | 作用 |
|------|---------|---------|------|
| 时间一致性 | 上一帧该像素的4个粒子 + 各随机选1个邻居 | 8 个候选 | 利用帧间连续性，绝大多数情况已覆盖 |
| 空间一致性 | 周围 15×15 范围内的随机像素 | 32 个候选 | 相邻像素的最近粒子大概率也在本像素附近 |
| 随机全局搜索 | 随机粒子 ID | 1 次/帧（首帧100次）| 确保覆盖新出现的粒子，防止遗漏 |

```glsl
// 时间一致性
ivec4 old = fxGetClosest(iFragCoord);
for(int j=0; j<4; j++){
    insertion_sort(new, dis, old[j], distance2Particle(old[j], p, w2c));
    // 再抽查该粒子的一个随机方向邻居
    int nid = [above|below|left|right](old[j]);
    insertion_sort(new, dis, nid, distance2Particle(nid, p, w2c));
}

// 空间一致性
for(uint i=0; i<32; ++i) {
    // 周围随机像素的第1近粒子
    ivec4 neighborBest = fxGetClosest(iFragCoord + randomOffset);
    insertion_sort(new, dis, neighborBest[0], ...);
}

// 全局随机
int randomId = hash(...) * MAX_PARTICLES;
insertion_sort(new, dis, randomId, distance2Particle(randomId, p, w2c));
```

**距离计算**：粒子 3D 世界坐标 → 投影到屏幕 → 与像素坐标比较欧氏距离。已撕裂粒子（`worldPos.w != 0`）返回无穷远。

### 5.3 (0,0) 像素的特殊作用

该像素不参与 Voronoi 追踪，而是用作全局状态寄存器，存储分辨率、鼠标位置、模式计时器等。

---

## 六、渲染（Image Pass）

### 6.1 渲染流程

```
对于每个屏幕像素:
  1. 从 Buffer B 获取该像素的最近粒子
  2. 获取该粒子的位置和状态
  3. 绘制该粒子与其 4 个直接邻居之间的连线
     (above, below, left, right)
```

### 6.2 线段绘制

```glsl
void drawLine(vec3 from, vec3 to, vec2 p, mat4 w2c, inout vec4 fragColor) {
    // 1. 3D 世界坐标 → 3D 相机坐标
    // 2. 透视除法 → 2D 屏幕坐标
    // 3. 线段到像素的距离 ← fxLinePointDist2
    // 4. 距离小于线宽则加深颜色
}
```

- 背景色为浅灰 `vec4(0.7)`
- 线段经过的像素颜色值减小（`fragColor = min(fragColor, 1.0 - alpha)`）
- 越靠近线段中心，颜色越深
- 线宽自适应分辨率：`PARTICLE_SIZE = 2.0 / iResolution.y`

### 6.3 相机系统

固定相机位置 `(0, 1, 3)` 看向原点，使用标准的 LookAt + 透视投影矩阵。相机矩阵通过 `fxCalcCamera` 和 `fxCalcCameraMat` 计算。

---

## 七、关键参数速查表

| 参数 | 值 | 作用 |
|------|-----|------|
| `GRAVITY` | (0, -1, 0) | 重力方向与强度 |
| `WIND_SPEED` | 100.0 | 风力大小 |
| `WIND_CHANGE_RATE` | 0.5 | 风速变化频率 |
| `WIND_RIPPLE` | 0.01 | 风力空间波纹密度 |
| `SIDE_LEN` | 4.0 | 布料总边长（世界单位） |
| `EDGE_BREAK_LEN` | 5.0 | 撕裂阈值（×edgeLen） |
| `COMPRESSION_RESIST` | 0.005 | 压缩刚度（极低=允许褶皱） |
| `CARDINAL_ITERATIONS` | 45.0 | 基数方向约束层数 |
| `DIAGONAL_ITERATIONS` | 25.0 | 对角方向约束层数 |
| `MAX_TEMP` | 1000.0 | （未使用） |

---

## 八、算法精华总结

### 8.1 为什么这个方案稳定？

1. **Verlet 积分**天然比 Euler 稳定，适合大时间步长
2. **超量约束**（每个粒子每帧 ~280 个约束）从根本上抑制了弹簧振荡
3. **多级约束**相当于给布料内置了"弯曲刚度"，不需要额外的弯曲力计算
4. **压缩低阻力**的设计避免了布料在约束求解中"弹跳"

### 8.2 为什么能实现自然撕裂？

1. 撕裂基于**相对位移**而非绝对应力，更直观
2. `disabled` 粒子的连锁反应使得裂缝沿布料纹理自然传播
3. 多级约束意味着一个粒子的断裂会影响周围大范围粒子的约束拓扑

### 8.3 性能权衡

- **计算密集**：每粒子每帧 ~280 次约束求解 → 适合 GPU 大规模并行
- **存储紧凑**：所有粒子数据在单张 2D 纹理中，利用 GPU 纹理缓存
- **空间索引**：Buffer B 的 Voronoi 追踪将渲染复杂度从 O(N²) 降到 O(1)

### 8.4 可移植到 Unity 的要点

1. 用 `ComputeBuffer` 或 `RenderTexture` 替代 ShaderToy Buffer
2. Buffer A → Compute Shader（物理模拟）
3. Buffer B → Compute Shader（空间索引）
4. Image → 顶点/几何着色器或屏幕空间后处理
5. 鼠标交互 → `Input.mousePosition`
6. 键盘 → `Input.GetKey`
7. `iTime` → `Time.time`
8. `iFrame` → 自行维护帧计数器

---

## 九、文件对应关系

| 文件 | 对应 ShaderToy Pass | 代码行数 | 主要功能 |
|------|-------------------|---------|---------|
| `Common` | 所有 Pass 共享 | 161 | 哈希、相机、粒子IO、邻居系统 |
| `BufferA` | Buffer A | 153 | 物理模拟（Verlet + 约束 + 撕裂） |
| `BufferB` | Buffer B | 142 | Voronoi 空间索引（最近粒子追踪） |
| `Image` | Image | 101 | 最终渲染（连线绘制） |
