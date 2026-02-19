在2025年12月开始的Unity URP学习项目
目前已经包括：
1. 无限草，已经无限草的流体场交互
2. NS 角色流体场
3. 终末地史尔特尔渲染模拟，其下包括
- Per Object Shadow Renderer Feature，具体构架是Renderer Feature执行渲染灯光空间深度图，然后绘制一张屏幕空间的PCSS阴影，再用Compute Shader降噪
- Edge Detect Renderer Feature，有两个，一个使用后处理边缘检测，一个是实体化描边，设置了专门的描边数据Class，可以控制每个的粗细颜色等等，还可以传递基础颜色贴图，目前用的是实体化的方法
- 角色表面流水模拟
