# 2.1.8 独立验收结果（2026-10-04）

待审版本：518c405a51ab46cb6e6a39e22a36ab9d9788f78c（远端 master 与 tag 2.1.8 一致）。原版基准：ibireme c7df27538c043e5f54f5b6605958544bb529892f。

结论：此前 38 个公开 API 复现检查全部通过；新增数值验收未通过，不能宣称数值契约完整。没有读取、构建或修改 PPLive，没有把正式业务 App 作为本组件验收标准。库生产源码没有改动；新增文件只在 Validation。

## 已确认缺陷

| 编号 | 级别 | 输入 / 目标 | 实际 / 期望 | 源码位置 |
|---|---|---|---|---|
| F1 | P1 | `123e-000001` → Int64 | 0 / 12 | YYJSONDecoder.swift:370–371 |
| F1 | P1 | `9223372036854775808e-000000` → Int64 | 0 / 拒绝越界 | 同上 |
| F2 | P1 | `0x20000000000001p0` → Int64 | 9007199254740992 / 9007199254740993 | YYJSONDecoder.swift:344–346 |
| F2 | P1 | `-0x8000000000000001p0` → Int64 | Int64.min / 拒绝越界 | 同上 |
| F3 | P2 | `1\u0301e0`、`1\uFE0Fe0` → Int64 | 1 / 拒绝非法数字语法 | YYJSONDecoder.swift:212–213 |
| F4 | P2 | `0e+999999` → Int64 | 抛错 / 0 | YYJSONDecoder.swift:378–386 |

F1 使用原始指数位数推断量级，前导零使正常数甚至越界数被清零。F2 先转 Double，随后 exactly 已无法找回丢失的精度；UInt64 最大值的合法十六进制表示也被拒绝，Decimal 十六进制输入同样失真。F3 Character 比较范围不是 ASCII 数字校验，组合字符进入 Foundation 的前缀解析。F4 有限精度 Decimal 的指数上限被错误当成目标整数边界，系数为零仍误拒绝。

建议：统一按 ASCII 字节校验并提取符号、有效系数、基数、规范化指数；在精确整数空间完成向零截断和范围检查。不能用 Double 作为精确整数或 Decimal 的中介。零系数先归一化，再检查指数。测试语料已经先于任何后续修复写好；修复者应直接复跑，不能把期望改成当前错误输出。

## 验收证据

- 新增公开 API 数值案例：1,742 个唯一输入组合（目标类型、输入通道、字符串）；macOS 与 iOS 模拟器各 1,412 通过、330 失败，结果一致。这是 4 类根因的多组变体，不是 330 个独立缺陷。Python ASCII 语法与任意精度整数计算独立生成期望。
- 保留的 R/N/D/E 检查：38/38。
- swift test -c release：16/16；Demo：84/84，编译日志无警告；Framework 官方 XCTest：27/27。
- Open-Meteo 三城市快照 + clean/dirty/nullable/sparse/large：两个平台各 20/20 验收判定通过。包括原版 OC、2.1.8 OC、原生 Swift、YY Swift 的共同业务模型逐字段和逐数组元素核对，以及 OC 嵌套 JSON 导出往返。20 项中包含原生 JSONDecoder 对 dirty/sparse 的两项预期拒绝，不表示所有引擎均成功解析所有数据。
- 大载荷为合成扩容：96 城市、9,216 小时记录、501,555 字节。公开 API 原始快照、许可、获取 URL/时间和 SHA 已保存。

## 重复解析性能

单位 ms/次，中位数；只测 Data → Model，不含网络或文件读取。OC -O2，Swift -O，预热 5 次、7 轮；普通每轮 100 次、大载荷每轮 8 次。所有正确性检查先完成，性能任务串行运行。

| 环境 / 场景 | 原版 OC | 2.1.8 OC | 原生 JSONDecoder | YYJSONDecoder |
|---|---:|---:|---:|---:|
| macOS / clean | 0.2643 | 0.2835 | 0.8018 | 0.8164 |
| macOS / large | 9.0236 | 8.9851 | 25.7450 | 26.4592 |
| iOS Simulator / clean | 0.3103 | 0.2768 | 0.7672 | 0.7964 |
| iOS Simulator / large | 9.3371 | 9.5948 | 23.9065 | 23.5820 |

Swift YY 的 dirty 天气载荷：macOS 4.5831 ms（clean 0.8164 ms），模拟器 3.9645 ms（clean 0.7964 ms），约 5–5.6 倍。这是指定脏数据及当前慢路径的观测结果，不能推广成所有脏数据固定倍数。原生 JSONDecoder 的失败耗时不进入成功解析比较。

这些数据不支持“全面比原版更快”或“已发生稳定 OC 性能回退”的结论。没有锁定 CPU 频率、温度或后台负载，且 OC/Swift 模型表示不同。保存每轮样本、最小/最大值以便复核。测试在 Apple Silicon macOS 和 iOS 26.5 arm64 模拟器完成；未在实体 iPhone 或 iOS 27 上测量，也未测峰值内存/长期泄漏/TSan。

## 复跑

按 README 使用固定源码与原版基准：

```sh
python3 Validation/run.py --source-root /path/to/2.1.8 --original-source /path/to/original/YYModel --output /tmp/yymodel-validation-mac
python3 Validation/run.py --source-root /path/to/2.1.8 --original-source /path/to/original/YYModel --simulator SIMULATOR_UUID --output /tmp/yymodel-validation-ios
```

两条命令应依次运行。当前整体预期退出 1（数值验收失败），仍会完成天气验收；不能将正常执行到末尾当成通过。修复后应整体退出 0。无需业务工程、账号、网络请求或外部依赖包。日志与 JSON 是可复验回执，旧业务 App 的绿色记录不作为本次发布证据。
