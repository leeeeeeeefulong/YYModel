# 2.1.9 交付验证方案与先行失败判定

目标：交付可复跑的中文选型文档，以 ibireme c7df275 为 OC 基准，以当前 2.1.9 / 00329f2 为交付版本。只扩展现有组件公开 API E2E 和文档，不修改库实现，不使用正式业务项目。

## 在新验收程序前固定的失败场景

1. 跨语言程序编译成功却调用了不同模型/库版本：复用 WeatherE2E.m 的同一组 OC 类，记录输入、两组库源码、验收源码和生成头文件的 SHA；原版没有 Swift 解码器，不虚构“原版 Swift API”。
2. Swift→OC 结果少字段、容器元素/顺序变化、keyPath 导出错误：完整 Model JSON 逐字段与 Python oracle 比较，OC 往返再比较；失败不计时。
3. 混合链接中 OC 被链接器删除或只测到 Swift：检查二进制中 OC 天气类、调用公开 API；混合程序支持并实际验收两套引擎，分别测各自调用，不能把两次解析之和称为编译损耗。
4. 原生 JSONDecoder 对 dirty/sparse 的拒绝被当成更快：将拒绝作为正确性检查，排除失败解码计时；YYJSONDecoder 使用完全相同的 Codable struct。
5. 错把已解析字典当 Data→Model，或忽略 Any 重编码/桥接：分别列出 data、object、encode；object 的 JSONSerialization 在计时外，但 YYJSONDecoder Any 内部的重新编码在计时内。
6. 跨语言数据被重复无意义转换：不测试 struct→JSON→OC 的重复解析链。Swift 调 OC 使用 NSObject 模型和公开 API。
7. 热缓存、单次微小计时或无消费结果误导结论：输入读取排除，预热 5 次、7 轮采样、消费字段或导出字节并释放对象；两轮正/反顺序，保存 14 样本、冷首调、median/min/max/P95。
8. Swift decoder 复用影响对比：原生默认复用 decoder，另列 new-decoder 路径；YYJSONDecoder 的内部 JSONDecoder 每次新建按实际代码计入，不隐藏。
9. IO、网络、后台编译污染性能：固定归属清楚的 Open-Meteo 快照；正确性与构建先完成，随后单进程顺序测量；模拟器/宿主平台单列，不声明实体 iPhone 性能。
10. 归档版本、测试源码与交付字节不一致：验收前后复查源码 SHA；文档以结果 JSON 生成表格，保留失败回执，不根据表现修改固定正确性期望。

性能复核口径：预先以相同路径/载荷下中位数慢于原版 10% 作为追加交替测量的观察线。该线用于定位差异，不等同于统计学等效界限或通用 SLA；如复测仍慢，交付文档如实报告，不能预设“全面更快”。

## 依次执行

- 写 `Validation/InteropSupport.h/.m` 和 `Validation/InteropRunner.swift/.m`：调用真实公开 API、输出完整正确性结果及分阶段采样。构建时从 WeatherE2E.m 提取 OC 头声明、从 WeatherE2E.swift 提取 Codable 类型，不复制实现。
- 写 `Validation/run_delivery.py`：构建 OC-only、Swift-only、mixed-current、mixed-original 五个独立程序（原版/当前各有 OC-only 与 mixed，另有当前 Swift-only）；先验收全部 5 类载荷/阶段/路径，再顺序测性能。任何意外错误/不等价使程序非零退出。
- macOS 与 iOS arm64 模拟器运行，性能任务不并行。普通载荷每轮 100 次，大载荷每轮 8 次。先记录一轮，再反序复测，合并样本。
- 核对 native 优先/容错回退和 Swift/OC 特性源码；跑既有边界、数值和组件回归，区分新鲜证据与历史回执。
- 写 `docs/DELIVERY-2.1.9-zh.md`、机器可读交付回执和 CSV：功能、调用建议、完整阶段数据、性能差异与限制、示例、复跑命令。
- 复查文档每项结论能对应源码或回执；只提交文档/验证包，推送 master，不移动版本标签。
