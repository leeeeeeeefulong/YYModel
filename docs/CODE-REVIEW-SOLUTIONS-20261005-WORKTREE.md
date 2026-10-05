# YYModel 最新改动独立复审与解决方案

审查日期：2026-10-05。结论：上轮 7 项原始复现均已通过，但尚有 1 项新增工具链兼容缺陷和 1 项精度问题的遗漏入口，暂不能宣告全部修复。

## 1. [P1] 为新增并发注解补齐 Swift 5.9 编译器分支

位置：`YYModelSwift/YYModelJSONValue.swift:10`。

新增的全局关联对象 key 无条件使用 `nonisolated(unsafe)`，但 Package.swift 声明最低 Swift 5.9，podspec 也说明工具链为 5.9+。该注解由 Swift 5.10 实现的 [SE-0412](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0412-strict-concurrency-for-global-variables.md) 引入，因此当前改动超出了对外声明的最低编译器能力，影响仍使用 Swift 5.9 的接入者。项目在 YYJSONDecoder.swift:449 已有相同能力的版本分支，可直接保持一致。

证据等级：源码与官方能力版本已核对；本轮没有实际运行 Swift 5.9 编译器。Swift 6 的 `-swift-version 5` 不能替代这一验证。

**解决方案：**

```swift
#if compiler(>=5.10)
private nonisolated(unsafe) var YYPreservedDoubleKey: UInt8 = 0
#else
private var YYPreservedDoubleKey: UInt8 = 0
#endif
```

这是一项局部兼容修复，维护成本低。无需为此提高用户接入门槛，也不改变公共 API。验收必须分别使用真实 Swift 5.9 工具链和当前 Swift 6 严格并发配置编译；如果旧 SDK 另有兼容问题，需要单独定位，不能用这一个分支宣称全包已兼容旧 SDK。

## 2. [P2] 将双数值表示贯穿自定义 Date/Data 策略

新增表示位置：`YYModelSwift/YYModelJSONValue.swift:168–171`；信息丢失位置：`YYModelSwift/YYModelNativeBridge.swift:19`。这是上轮精度问题的残余入口。

本次给 NSDecimalNumber 附加原始 Double，并在普通 Double 解码时取回，已经修复普通字段。但自定义 Date/Data 策略仍先调用 JSONSerialization 再交给 Foundation，关联对象不会进入 JSON；高精度原始 token 被 Decimal 的有限精度表示替代。空操作 will hook 仍能改变策略回调读取到的值。

输入 token：

```text
1.000000000000000111022302462515654042363166809082031251
```

公开 API consumer 的实测结果：

| 路径 | 无 hook 的 Double bitPattern | 空操作 hook 的 Double bitPattern |
| --- | --- | --- |
| 普通 Double 字段 | 4607182418800017409 | 4607182418800017409 |
| Data.custom 回调读取 Double | 4607182418800017409 | 4607182418800017408 |
| Date.custom 回调读取 Double | 4607182418800017409 | 4607182418800017408 |

Date 样本使用 timeIntervalSinceReferenceDate，避免基准日期换算的消减误差掩盖差异。实际影响是特定舍入边界的 1 ULP，并不是所有日期或所有数字都无法解析。

**解决方案：**在当前严格 Foundation 桥接中加入每次解码独立的数值上下文，将原始子树及 Double/Decimal 双表示带进策略解码器，在确定目标类型后再选择表示。

1. 扩展 YYModelNativeStrategyState 与现有 Prefix 容器，使单值、keyed、unkeyed、嵌套及 super 路径都能定位当前原始数值。
2. 目标为 Double 且原始节点是数字时，恢复保存的 literal Double；Decimal 使用 Decimal 表示，整数沿用范围检查。Foundation 严格类型验证仍应保留。
3. 保持 codingPath、userInfo 和策略回调次数；不要为修复精度而重跑整个模型。

不要把整个子树先转 Double 再序列化：这会破坏 Decimal 和大 UInt64。也不要直接把容错 _YYDecoder 交给原生 custom strategy：会重新引入字符串自动转数字等严格性差异。

近期可复用现有桥接结构局部修改，公共 API 不变。长期应收敛为一个内部数值解析入口，减少普通字段与原生策略两条路径各自补丁；若改用纯 Swift 的数值上下文，必须限定在单次解码生命周期内，不能使用跨请求全局对象地址表。

**验收条件：**上述两类 custom strategy 在 hook 前后 bitPattern 相同；普通 Double 样本继续一致；Decimal 小数和 UInt64.max 保真；严格策略读取数字字符串仍拒绝；嵌套容器、codingPath、userInfo 和回调一次性契约均保持。先定义这些失败场景，再修改实现。

## 上轮 7 项问题复核

| 上轮问题 | 本轮原始样本结果 | 结论 |
| --- | --- | --- |
| configured native 意外启用增强规则 | 缺失、类型及日期行为与原生一致 | 原始场景修复 |
| configured export hook 丢配置 | configured-only 类型和双协议类型均保持配置 | 原始场景修复 |
| 数字 CodingKey 把 01 合并为 1 | 两个键均保留 | 原始场景修复 |
| 长小数 Double 舍入变化 | 普通字段原始样本通过 | 部分修复；见问题 2 |
| 默认值改为 nil 仍保留旧 typed 值 | 返回 nil | 原始场景修复 |
| 无 JSON 快照的 typed 默认值被忽略 | 取回 7 | 原始场景修复 |
| fallback 显式 null 的 decodeNil 不一致 | 查询与直接读取均使用 fallback | 原始场景修复 |

## 范围、实测与限制

基准 HEAD：`7605086c9ad71c1b61740bceb8c3f4fa65d486f1`。审查的是该 HEAD 上最新未提交修复；具体 17 个 Swift 文件 SHA-256 见 [manifest.json](review-solutions-20261005-worktree/manifest.json)。本轮以此前冻结的复审源码为增量对照，检查新增修复及关联调用路径，没有把历史报告的结论直接当作事实。

编译环境：Apple Silicon macOS，Swift 6.3.3，`-O -swift-version 6 -strict-concurrency=complete -warnings-as-errors`。冻结源码和公开 API consumer 的完整独立重跑已完成：

- Swift 外部规则契约：37/37。
- 普通 Double 样本：84/84 位级一致。
- 上轮 7 项原始复现：通过。
- 新增自定义 Data/Date 精度样本：2 项不一致，均保留原始输出。

本轮未运行 iOS 真机/模拟器、旧 Swift 5.9 编译器或 Objective-C 性能基准；上述结果不能推导为全平台无缺陷，也不能证明性能与 ibireme 一致。没有使用或修改 PPLive。没有修改生产源码、提交或推送。

[复现说明及冻结源码](review-solutions-20261005-worktree/README.md) · [测试回执](review-solutions-20261005-worktree/receipt.json) · [精度差异原始输出](review-solutions-20261005-worktree/BridgeConsumer.json)

建议先落实问题 1 的局部编译保护，再统一问题 2 的数值传递；完成后运行上述明确的验收，不需要先扩大到大量无关测试。
