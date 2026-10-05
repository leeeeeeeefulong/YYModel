# 缺陷登记册（Defect Registry）— 2026-10-05

> **文档定位**：本文件是 2026-10-05 对 `YYModelSwift/` 全部 20 个源文件系统性审计的**缺陷唯一登记源**。
> 配套文档：[REMEDIATION-DESIGN](REMEDIATION-DESIGN-20261005.md)（修复方案）、
> [REMEDIATION-IMPLEMENTATION-PLAN](REMEDIATION-IMPLEMENTATION-PLAN-20261005.md)（落地计划）、
> [REMEDIATION-ACCEPTANCE-PLAN](REMEDIATION-ACCEPTANCE-PLAN-20261005.md)（验收计划）。
>
> **行号基准**：HEAD `7605086`（tag 2.3.0）+ 当日未提交改动。后续行号可能漂移，以缺陷描述中的符号名（函数/类型）为辅助定位。
>
> **审计方法**：全部源文件逐行核查 + `docs/` 十轮历史审查复盘。高危项均经审计人逐处复核源码；
> 涉及 Foundation 外部行为的两处（NSDecimalNumber 取整语义、`convertFromSnakeCase` 官方实现）经官方源码/文档验证。
> 置信度标注：`已验证`＝审计人亲读源码确认；`代理核验`＝探索代理引用行号、审计人抽查确认；`文档佐证`＝历史审查文档记录。

---

> **执行证据更新**：当前修复进度以 [公开 E2E 状态表](../Validation/remediation/STATUS.md) 和冻结源码回执为准。
> 下文“位置/复现”保留审计基线；源码疑点不等同于已复现运行缺陷。正式外部签署及旧 OS 运行验收未完成。


## 本轮最终处置索引（覆盖全部22项原登记与5项组合）

以下是当前状态，后面的源码位置与失败叙述保留历史审计证据。公开 E2E 共555项通过；
可重放源码、SHA-256、编译/运行命令和观察值见
[`Validation/remediation/evidence/final/`](../Validation/remediation/evidence/final/receipt.json)。
“已修复”指本机公开用例与实现收敛；不是外部签署或旧 OS 运行验收。

| ID | 处置与验收依据 |
|---|---|
| P-01 | 缓存能力探测、整数 token 路由已实施，54项数值边界及路由/负零对照通过；真实旧 OS G5仍待证，浮点形式大整数限制已公告 |
| P-02 | 排除错误处方，原向零截断行为锁定；Registry/Numeric控制通过 |
| P-03/P-04 | 本机原已通过；R-2 删除导出/桥的文本重解析，Decimal与策略对照通过；原旧 OS 推断不冒称复现 |
| P-05 | 显式微秒策略已实现，DateAndCoercion控制通过；automatic及毫秒格式限制保持并公告 |
| P-06 | Float原类型/直接字面量投影与长尾修复，Numeric/FloatMidpoint通过 |
| P-07 | 幽灵代码误报关闭；真实Set问题归K-02 |
| P-08 | 默认关闭的线程安全元数据报告已实现，DateAndCoercion含并发/默认关闭控制 |
| F-01 | raw精确键优先再UTF-8；Registry/HookAncestor确定胜者与hook同源控制通过 |
| F-02 | 模型规则为基底、重复注册合成；Registry/ExternalRules通过 |
| F-03 | A排除误报；B规范Int键优先、坏值仍严格拒绝；Registry/Extended通过 |
| F-04/F-05 | 共享字段解析、无效中间路径保留错误；FieldResolution/BridgePaths通过 |
| F-06 | 记录实际Foundation映射，以逻辑祖先索引并同步物理游标；HookAncestor及K组合通过 |
| F-07 | Presence/null贯穿数组与字典，业务初始化错误保留；Registry/FieldResolution通过 |
| F-08 | lossy报告、逐元素优先与调用隔离；Registry/FieldResolution通过 |
| F-09 | raw扁平继承与Data/Foundation差异文档化，super策略/节点对照通过 |
| F-10 | 判别符严格String、错误包含判别键；Registry/Composition通过 |
| F-11 | b/f及可变子树d已修；a/c/e原误推断不冒称运行失败，共享状态维护收敛；Extended/FieldResolution通过 |
| A-01 | R-1统一字段解析已实施；重复mapper owner控制通过，独立架构审查新增祖先问题已修 |
| A-02 | R-2直接树导出、集中标量投影已实施；公开NSNumber边界仅保留不可变节点；BoundaryLifetime/TreeFoundationParity/TreeProtocol通过 |
| A-03 | 历史consumer入库、失败模式先行、冻结源码可重放；两名独立自动审查者发现的问题均有红绿证据；CI远端与正式独立人员签署待完成 |
| K-01–05 | 五类均明确入册：物理祖先、Set逐元素后建集、模型codingPath、泛型递归、结构化keyMap；12组hook前后两态全部通过 |

## 0. 编号与等级定义

- **P-xx**：数值精度类（Precision）
- **F-xx**：字段读取/键解析类（Field）
- **A-xx**：架构根因（Architectural）——不是单点缺陷，而是 P/F 类反复复发的结构性原因

| 等级 | 定义 |
|---|---|
| 高 | 静默数据损坏或字段值错误/不确定，常规业务输入可触发 |
| 中 | 特定但常见的配置/入口组合下行为错误或入口间互相矛盾 |
| 低 | 边角输入、诊断质量、或已文档化的宽松行为 |

---

## 1. 缺陷汇总表

| ID | 标题 | 等级 | 置信度 | 修复设计 |
|---|---|---|---|---|
| P-01 | 旧系统上整数快路径 Decimal 经 Double 中转，>2^53 静默失真 | 高（平台条件） | 源码确认（本机未复现/旧OS待证） | R-3 |
| P-02 | 负数小数→整数截断方向（原文档称-2；实测原实现即向零截断得-1） | 误报 | 已实测排除（处方严重错误） | 保持现状（撤销D2-1） |
| P-03 | 字典输出/hook 导出经 JSONSerialization 往返塌缩 Decimal | 中 | 源码分析（本机未复现/旧OS待证） | R-2 |
| P-04 | native 桥 `.custom` 策略重序列化丢失 Decimal 双表示 | 中 | 源码分析（本机未复现/旧OS待证） | R-2 |
| P-05 | 时间戳单位启发式 `abs>1e11`（µs 误判、ISO8601 毫秒截断） | 中低 | 源码确认 | D3-7 |
| P-06 | Float 经 Double 二次舍入，可差 1 ULP（Hook 路径明确失败） | 低 | 已复现（Hook 路径） | R-2 |
| P-07 | Set 匹配 `Double($0.stringValue) ?? 0` 静默匹配零 | 误报 | 幽灵代码（当前源码不存在） | 关闭（撤销D2-2） |
| P-08 | legacy 宽松互转（`1`→true 等）完全静默 | 低 | 源码确认 | D3-8 |
| F-01 | raw 管线物理键冲突胜者 = 字典哈希序（跨运行不确定） | 高 | 源码确认 | D3-1 |
| F-02 | 外部 `forType` 规则整体替换模型规则与先前注册，无警告 | 高 | 已复现（/tmp探针） | D3-2 |
| F-03A| 字典数据键策略两入口相反（原称 Data 入口改写字典键） | 误报 | 已实测排除（Foundation不改写）| 关闭（精简D3-3） |
| F-03B| 裸 `[Int:V]` 键合并不确定（"01" 与 "1" 无序覆盖） | 高 | 源码确认 | D3-3 |
| F-04 | `contains()` 与 `superDecoder/nestedContainer` 存在性判定相反 | 中 | 源码确认 | R-1 |
| F-05 | `field()` 用 `try?` 吞掉策略错误，字段静默判缺失→零填充 | 中 | 源码确认 | R-1 |
| F-06 | hook 快照键解析与模型解码不一致（精确键优先 + 哈希序 + 混合路径） | 中 | 源码确认 | R-1 |
| F-07 | Presence/null 拦截仅 keyed 路径；数组/字典内 null 抛错崩溃 | 中 | 已复现（/tmp探针） | R-1 |
| F-08 | lossy 无报告时静默丢弃；fallback 优先于 lossy；取容器在 catch 外 | 中 | 源码确认 | D3-4 |
| F-09 | `superDecoder()` 两入口语义相反；`"super"` 键劫持 | 中 | 源码确认 | D3-5 |
| F-10 | 多态判别符：Data 严格 / 对象宽松 / null→`""` | 中 | 源码确认 | D3-6 |
| F-11 | 低危集合（b/f 复现，d 可变子树复现，a/c/e 原推断待证） | 低 | 部分确认 / 部分待证 | D2-3 |
| K-01 | NativeBridge 物理祖先路径解析（renamed-parent, snake-parent） | 高 | 已验证（基线通过原样本） | Bridge 路径映射 |
| K-02 | Set 正确值去重（set-distinct, set-single, set-float-distinct） | 中 | 部分复现（扩展浮点去重失败） | Bridge Set去重纠偏 |
| K-03 | 模型 codingPath 完整贯穿（model-array/optional/dictionary-path） | 中 | 已验证（基线通过原样本） | Bridge 路径传递 |
| K-04 | 泛型递归与容器嵌套游标推进（optional-nested-array, int-dictionary, unkeyed-cursor）| 高 | 已复现（基线与扩展失败） | Bridge 递归数值恢复 |
| K-05 | 结构化 keyMap 分隔符碰撞（path-collision） | 高 | 当前原样本通过；历史回归锁定| Bridge 结构路径解析 |
| A-01 | 五条键解析管线并存（3 份蛇形副本、3 种缺失语义） | 根因 | 源码确认 | R-1 |
| A-02 | 数值恢复/数学存在多表示旁路（公开 NSNumber 边界兼容性须保留） | 根因 | 源码确认 | R-2 |
| A-03 | 审查探针不入库、测试盲区、修复者=验证者 | 根因 | 历史审查/事实核验 | Phase 0 |

---

## 2. 数值精度类缺陷详情

### P-01【高·平台条件】旧系统整数快路径 Decimal 经 Double 中转

- **位置**：`YYModelSwift/YYModelDecoder.swift:118-119`、`:353-357`（整数快路径 `base.decode(Decimal.self)`）；`YYModelSwift/YYModelJSONValue.swift:108-136`（hook 快照分类同源）；`Package.swift:18-21`（部署下限 iOS 11 / macOS 10.13）
- **问题**：整数精确性（>2^53 雪花 ID 保真）依赖 Foundation JSONDecoder 对 `Decimal` 的**精确字面量解码**。该性质仅新 swift-foundation 实现（iOS 16+ / macOS 13+）具备；旧系统（iOS 11-15 / macOS 10.13-12）的 `Decimal` Decodable 经 `Double` 中转。`YYModelDecoder.swift:349-350` 注释断言"Foundation 对 JSON 数字 token 的 Decimal 解码是精确的"，未限定 OS 版本。
- **复现与当前环境限制**：在真实旧 OS（如 iOS 14）下：`{"id": 9007199254740993}` → Int64 字段 = **9007199254740992**（无任何报错）。**特别声明**：当前宿主环境为 macOS 26.7（搭载现代 swift-foundation），底层 Decimal 解码天然精确，**当前本机环境无法直接复现此平台缺陷**，严禁在现代 macOS 上冒充旧 OS 验收通过。
- **影响**：声明部署范围内的所有旧系统用户；静默数据损坏。
- **附注**：旧系统上浮点拼写的整数 token（`9007199254740993.0`）连 JSONSerialization 也会解析为 Double，属更深的残留决策点，见修复设计 R-3。

#### P-01 补充：现代系统 hook 快照的 UInt64 表示丢失（不同于旧 OS 缺陷）

公开 `NumericBoundaryE2E` 在当前 macOS 上的 54 项数值边界中有两项失败：
Data + hook 的 `9223372036854775808` → `9223372036854776000`，
`18446744073709551615` → `18446744073709550000`。hook 收到的 NSNumber
已是 `objCType=d`；完整观察见 `Validation/remediation/evidence/numeric-boundary-baseline/`。
独立 Foundation 控制证明 `NSDecimalNumber(value: Double(token))` 的值比较不能证明
该原始整数适合转存为 Double：前者在这些边界可能与原 Decimal 相等，但 Double 的
字符串表示再解成整数已经失真。数值树应先保留大整数的 signed/unsigned 分类。
此项是现代系统已复现的 A-02 数值表示问题，不能用“旧 OS 待证”关闭。

### P-02【误报·处方严重错误】负数小数→整数截断方向（原文档判断相反）

- **位置**：`YYModelSwift/YYJSONDecoder.swift:417-424`（`integer(_:_)` 的 NSDecimalNumber 分支）
- **复核结论**：**误报（原源码实现正确，原登记册及修复设计 D2-1 存在严重事实错误）**。
- **事实分析**：在 Apple Foundation API 中，`NSRoundingMode` 的官方语义为：
  - `.down`（`NSRoundDown`）= **向负无穷方向取整（floor / Toward -Infinity）**；
  - `.up`（`NSRoundUp`）= **向正无穷方向取整（ceil / Toward +Infinity）**。
  原登记册误以为 `.down` 是朝零截断、`.up` 是远离零。实际上：
  - 对正数 `1.9`：向零截断需要向下取整（floor），使用 `.down` 得到 `1`（正确）；
  - 对负数 `-1.9`：向零截断需要向上取整（ceil），使用 `.up` 得到 `-1`（正确）！
  源码 `let mode: NSDecimalNumber.RoundingMode = copy.isSignMinus ? .up : .down` 精确实现了**向零截断（Toward Zero）**，与兄弟分支（:428 `.towardZero`）完全一致。
- **实测证据**：在独立消费者探针中实测，`{"delta": -1.9}` 走 Decimal 快路径精准输出 **`-1`**。
- **处方纠正**：若采纳原修复设计 D2-1（将取整方式改为无条件 `.down`），对负数 `-1.9` 将执行 floor 得到 `-2`，**反而会亲手引入重大回归 Bug**！因此撤销 D2-1，代码保持现状，仅增加正负数截断的回归锁用例。

### P-03【中·待证】导出/hook 链路 JSONSerialization 往返塌缩 Decimal

- **位置**：`YYModelSwift/YYModelEncoder.swift:19`、`:71`；`YYModelSwift/YYModelCodable.swift:80`（`yy_modelToJSONObject`）；`YYModelSwift/YYModelPolymorphic.swift:17`、`:47`
- **问题**：JSONEncoder 写出完整 Decimal 文本后，若经 `JSONSerialization.jsonObject(with:)` 重解析为 `[String: Any]`，在特定 Foundation 历史版本中带小数点的 token 可能被解析为 Double NSNumber 导致超精度 Decimal 塌缩。
- **当前实测与状态**：在当前环境运行主代理公开 consumer（`/tmp/yymodel-remediation-numeric-baseline-20261005/NumericE2E.json`）实测，`decimal-object-export` 与 `decimal-encoder-object` 针对 `1.000000000000000031251` 均保持原值输出，**本机未直接复现**。但源码逻辑上多余的序列化往返仍构成性能负担与历史系统上的潜在风险，保留 R-2 作为架构清理目标，标注为源码分析/旧环境待证。

#### R-2 实施中新增的公开编码回归（已修复，保留失败基线）

首版树编码后，`TreeFoundationParityE2E` 的16项 Foundation 对照仅4项通过。
失败观察已保存于 `Validation/remediation/evidence/tree-foundation-baseline/`。
包括：顶层 native Date/Data 与字典 Date/Data 绕过策略、非对象键字典被误拒绝、
Foundation ISO8601 格式改变、根无写入 Encodable 被误导出 null、Float 短文本/负零
丢失、根数据字典被 keyStrategy 改名，以及三层 export hook 的 codingPath 重复前缀。
这些是**首版实施引入的回归**，归 R-2 与 G6 门禁处理；不冒称 P-03/P-04 原审计的
旧 OS Decimal 精度猜测被复现。最终 `TreeFoundationParityE2E` 扩展22项全部通过；独立审查新增35项协议对照和10项重复编码/冲突控制也全部通过。失败基线继续保留，不修改期望隐藏回归。

### P-04【中·待证】native 桥重序列化丢失 Decimal 双表示

- **位置**：`YYModelSwift/YYModelNativeBridge.swift:46`（`JSONSerialization.data(withJSONObject: raw.value, ...)`）
- **问题**：`.custom` 日期/数据策略下，桥把原始树经 JSONSerialization 重序列化可能导致 Decimal 半边丢失。
- **当前实测与状态**：主代理公开 consumer `NumericE2E.json` 实测 `bridge-decimal-hook-false` 与 `bridge-decimal-hook-true` 针对超精度 Decimal token 均输出通过，**本机未直接复现**。标记为源码分析/旧环境待证。（注：NativeBridge 具体实现由主代理维护）。

### P-05【中低】时间戳单位启发式

- **位置**：`YYModelSwift/YYModelJSONValue.swift:226-228`、`YYModelSwift/YYJSONDecoder.swift:491-495`（`abs(seconds) > 1e11` 判定 ms）；`YYModelJSONValue.swift:209-238`（ISO8601 导出仅毫秒）
- **问题**：`.automatic` 下 µs 时间戳（1699999999999999）被判为 ms，日期差 1000 倍；`.millisecondsSince1970` 的 ×1000/÷1000 引入 Double 舍入；亚毫秒日期 ISO8601 导出被截断。启发式是设计选择，但**静默**且不可关闭。

### P-06【低】Float 经 Double 二次舍入（已复现）

- **位置**：`YYModelSwift/YYJSONDecoder.swift:234-238`（`F(number)`，number 为 Double）；`YYModelNativeBridge.swift:301-313`
- **问题**：>9 位有效数字的 token 先按 Double 解析再窄化为 Float，与直接 `Float("...")` 解析可差 1 ULP。
- **复现实测证据**：主代理公开 consumer `NumericE2E.json` 明确证实，在 `hook=true` 路径下 3 项 Float 探针失败：
  - `float-1.0000000596046448-hook-true`：实际得到 `1065353216`，期望 `1065353217`（失败）；
  - `float-1.00000005960464477...001-hook-true`：实际得到 `1065353216`，期望 `1065353217`（失败）；
  - `float--1.0000000596046448-hook-true`：实际得到 `3212836864`，期望 `3212836865`（失败）。
  确证二次舍入在 Hook 路径下导致 1 ULP 精度偏差。

补充公开证据：`FloatMidpointE2E` 的 16777217 / -16777217 / 9007199791611904
各加超过 Decimal 容量的极小正尾巴，hook 三例均比直接 Float(token) 少 1 ULP。
此时 Decimal 分类可能变为整数或“精确 Double”，不能先归类后丢弃原始 Float 位模式。
证据见 `Validation/remediation/evidence/float-midpoint-baseline/`。

### P-07【误报·幽灵代码】Set 匹配静默匹配零（代码不存在）

- **位置**：原文档标注 `YYModelNativeBridge.swift:364-367`
- **复核结论**：**误报（幽灵代码）**。经对当前代码库全局检索，该位置为 `YYModelPrefixEncoder`，全工程任何文件均不存在 `Double($0.stringValue) ?? 0` 这行代码。系探索代理误引用历史分支切片或代理幻觉，**关闭此缺陷，撤销 D2-2**。

### P-08【低】legacy 宽松互转静默

- **位置**：`YYModelSwift/YYJSONDecoder.swift:191-232`（bool/double coercion）、`:412-415`（Bool→1/0）、`:182-189`（number→digits）
- **问题**：`{"flag":1}`→true、`{"n":true}`→1、`{"s":123}`→"123" 等。边界守住了（2→Bool 失败、-1→UInt64 失败），属文档化的 YYModel 传统语义；缺陷点在**无任何诊断通道**（无开关、无告警钩子）。

---

## 3. 字段读取类缺陷详情

### F-01【高】物理键冲突胜者不确定（哈希序）

- **位置**：`YYModelSwift/YYJSONDecoder.swift:539-542`（`_YYDecoder.container(keyedBy:)`）
- **代码**：
  ```swift
  for (key, value) in dictionary {
      let transformed = context?.decodingKey(key, at: codingPath) ?? key
      if keys[transformed] == nil { keys[transformed] = value }
  }
  ```
- **问题**：JSON 同时含映射到同一逻辑键的两个物理键（如 `"user_name"` + `"userName"`，或 custom 键策略下任意同映射键）时，胜者 = Swift Dictionary 哈希迭代序首个 = **跨运行/跨设备不确定**。Foundation（Data 入口）按序列化序 first-wins；native 桥刻意复刻了序列化序（`YYModelNativeBridge.swift:22-23` 有注释自证团队知晓该规则）——仅 raw 管线违反。
- **影响**：旗舰 API `yy_model(with:)` / `yy_model(withJSON:)`；同 JSON 两次运行字段值可不同。
- **结构性约束**：`[String: Any]` 输入本身已丢失序列化序，无法完全对齐 Foundation——修复须**定义新的确定性规则**并文档化（见设计 D3-1）。

### F-02【高】外部规则整体替换模型规则

- **位置**：`YYModelSwift/YYJSONRules.swift:26-40`（`forType` 的 `result.entries[ObjectIdentifier(type)] = rule`，仅保留多态钩子）；`:133-144`（`rule()` 中外部条目 `:135` 短路于模型 `_yyRule()` `:138` 之前）
- **复现**：模型声明 `static var yy_modelConfiguration`（如 `id ← uid`）+ 外部 `rules.forType(Model.self) { $0.require(\.name) }` → 模型 mapper **整体失效**：`{"uid": 7}` 读不到 `id`（legacy 得 0，strict 抛 keyNotFound）。两次 `forType` 同理后者覆盖前者。
- **影响**：任何同时使用模型内配置与外部规则的消费者；静默错误键序。

### F-03【拆分：A误报 / B高】字典数据键策略两入口相反 + Int 键合并不确定

- **位置**：`YYModelSwift/YYModelDictionary.swift:89-104`（raw 分支 vs Foundation 分支）；`:26-42`（`make` 键转换，裸 `Key == Int` 走 `Int(name)`）
- **问题 A（数据键策略相反·误报）**：原文档宣称 Data 分支经 Foundation 会对 `[String: V]` 应用 `keyDecodingStrategy`（导致 Data 入口得驼峰、raw 入口得下划线）。**实测复核排除**：经官方 Foundation 源码及实测探针验证，Foundation 的 `JSONDecoder` 解码 `Dictionary<String, V>` 时，将字典键视为**数据值**而非类型 CodingKeys，不论是 `.convertFromSnakeCase` 还是 `.custom`，Foundation 原生**均不会改写字典键**！两入口均输出原始 `"snake_case"` 键，不存在策略相反问题。
- **问题 B（Int 键合并·源码确认）**：裸 `[Int: V]` 走 `Int(name)`——`"01"`、`"1"`、`"+1"` 均解析为 Int `1`，在 `result[try key(for: name)] = box.value` 中，合并覆盖顺序取决于底层无序字典的哈希迭代序（跨运行不确定）；`"1.0"` → nil → 整字典 `typeMismatch`。`CodingKeyRepresentable` 路径（:29-40）已修复字面量保留，**裸 Int 键未修**（`YYModelScalarDecoding.swift:44-46`、`YYModelNativeBridge.swift:216` 同病）。

### F-04【中】contains 与 superDecoder/nestedContainer 判定相反

- **位置**：`YYModelSwift/YYModelDecoder.swift:251-257`（`contains` 把 fallback/typedDefaults 算"存在"）vs `:426-437`（`superDecoder(forKey:)` 只看 field + defaults，**不含 fallbacks/typedDefaults** → 抛 `keyNotFound`）
- **影响**：手写 `init(from:)` 中 `contains==true` 但 `nestedContainer(forKey:)`/`superDecoder(forKey:)` 抛错；与合成路径行为分裂。历史 F3（INDEPENDENT 轮）、R7（FOLLOWUP 轮）的残余。

### F-05【中】field() 吞掉一切中间错误

- **位置**：`YYModelSwift/YYModelDecoder.swift:241`（`try? current.nestedContainer(...)`）
- **问题**：「中间层是标量/数组/null」（路径形状无效）与「custom 键策略抛错」被同一 `try?` 吞掉 → 字段判缺失 → legacy 零填充。策略错误被吞成"字段不存在"。另：KeyPath 语言不支持数组索引（`"items.0.name"` 静默失败）、不支持转义（点号键须用 `.key()`），均无诊断。

### F-06【中】hook 快照键解析与模型解码不一致

- **位置**：`YYModelSwift/YYModelJSONValue.swift:281-284`
- **问题**：(a) 无条件先取精确逻辑键，与模型解码的序列化序 first-wins 不同——`{"user_name":1,"userName":2}` 模型得 1、`willTransform/didTransform` 看到 2；(b) `dictionary.keys.first(where:)` 哈希序；(c) custom 策略下传给用户回调的是「逻辑父路径 + 物理键」混合路径，与 Foundation 的物理路径约定不同。

### F-07【中·已复现】Presence/null 拦截只在 keyed 路径成立

- **位置**：拦截仅在 `YYModelDecoder.swift:361-377`；其余路径走 `:147-150` 的 strict/zeroFill 分支
- **复现实测**：在 `/tmp/f07_probe` 中构造 `[YYModelPresence<String>]` 解码 `["hello", null, "world"]`，因单值/元素解码在 `:147-150` 未适配 Presence，遇到 `null` 立即抛出 `DecodingError.valueNotFound: Null value` 导致整数组崩溃！在 lossy 数组中亦会被误记为损失丢弃。

### F-08【中】lossy/fallback 交互缺陷

- **位置**：`YYModelSwift/YYModelLossy.swift:119-121`（`report?.record`，report 未注册则**静默**丢弃，违反模块「绝不静默」契约）；`YYModelDecoder.swift:291`（fallback 分支）先于 `:315`（lossy 分支）——一个坏元素导致整数组回退而非逐元素跳过、无损失记录；`:318` `nestedUnkeyedContainer` 获取在 catch 之外——lossy 字段值类型整体错误时失败整个模型。

### F-09【中】superDecoder() 两入口语义相反 + "super" 键劫持

- **位置**：`YYModelSwift/YYJSONDecoder.swift:601-605`（`dictionary["super"] ?? dictionary`）
- **问题**：raw 入口把当前层整个字典当父负载（YYModel 扁平继承），Foundation 语义是找 `"super"` 键——同一类层级 JSON：`yy_model(with:)` 解出父字段，`decode(from:)` 抛错。且 JSON 恰含业务字段 `"super"` 时被误读为父类负载。

### F-10【中】多态判别符分歧

- **位置**：`YYModelSwift/YYModelPolymorphic.swift:29-31`
- **问题**：`"type": 1` → Data 入口 typeMismatch 整体失败、对象入口 coerce 成 `"1"`；`null` → 零填充 `""` → 报误导性 "Unknown model discriminator: "。

### F-11【低·集合】六项低危（复核细化）

| 子项 | 位置 | 现状核验与评级 | 问题说明 |
|---|---|---|---|
| a | `YYModelDecoder.swift:357` | **待证（风险局限）** | 源码虽传入 `codingPath: []`，但整段位于 `let result = try? ...` 快路径尝试中；尝试失败会自然 fallback 到下方携带完整 `codingPath + [key]` 的完整路径。不能仅凭该行断言用户最终看到的错误路径必为空，降级为待证。 |
| b | `YYModelDecoder.swift:279-282` vs `:377` | 源码确认 | 零填充下 `decodeNil` 对 presence 报"null"（返回 true）、`decode` 报"absent"，两接口判定矛盾。 |
| c | `YYModelEncoder.swift:145`、`:155-159` | 未复现，防御收敛 | ExtendedE2E 的嵌套 mapper 冲突在修复前已正确拒绝；独立 state 的源码疑点不足以证明公开导出静默丢字段。 |
| d | `YYModelJSONValue.swift:290` | **可变子树已复现（顶层 COW 安全）** | Swift `Dictionary` 为值类型，具备写时复制（COW）特性，在 hook 内就地修改字典键会触发复制，不会反向污染调用方的原始字典。ExtendedE2E 中 NSMutableArray 子树由 hook 改动后，调用方源数组 count 从 1 变 2，确诊；必须递归隔离可变 JSON 子树。 |
| e | `YYModelDictionary.swift:98-99` | 公开并发未复现，维护性收敛 | 每次公开 decode 创建独立 context，100 次并发不同字段策略控制已通过；删除隐式 date 槽位仍能降低维护风险，不把结构疑点写成确诊串扰。 |
| f | `YYModelDecoder.swift:225-229` | 源码确认 | `allKeys` 同时暴露物理别名键与映射后属性名，动态 init 迭代会读到源键伪属性。 |

---

## 3.5 五类 Keymap 组合缺陷详情（K-01 ~ K-05，主代理 E2E 证据对齐）

> **编号说明**：K 系列为 NativeBridge 键映射、集合与路径组合引发的专项缺陷，由主代理负责专项组合与 E2E runner 验收，此处建立正式编号以保持跨代理对齐。
> **基准证据出处**：
> - 当前基线（`/tmp/yymodel-remediation-current-baseline-20261005/receipt.json`，9 组：7 通过，2 失败）；
> - 扩展基线（`/tmp/yymodel-remediation-expanded-baseline-20261005/receipt.json`，12 组：8 通过，4 失败）；
> - 桥接已修复（`/tmp/yymodel-remediation-bridge-green-20261005/receipt.json`，12 组：全部转绿通过）。

| 编号 | 类别名称 | 涵盖场景 | 基线表现 | 修复回执状态 | 验收界限 |
|---|---|---|---|---|---|
| **K-01** | **物理祖先路径解析** | `renamed-parent`、`snake-parent` | 该类别原样本在当前基线通过（bits=4607182418800017409） | 保持通过 | **已修复原样本**（锁定回归） |
| **K-02** | **Set 正确值去重** | `set-distinct`、`set-single`、`set-float-distinct` | 标量去重基线通过；扩展场景 `set-float-distinct` 在 hook 路径下因 Double 二次舍入导致去重碰撞（期望 count=2，实际 count=1） | bridge-green 已转绿 | **原样本已修复；扩展场景需后续验收** |
| **K-03** | **模型 codingPath 完整贯穿** | `model-array-path`、`model-optional-path`、`dictionary-model-path` | 9 组基线与扩展基线全通过（路径均正确保留如 `value.Index 0`、`value.key`） | 保持通过 | **已修复原样本**（锁定回归） |
| **K-04** | **泛型递归与容器嵌套游标推进** | `optional-nested-array`、`int-dictionary`、`unkeyed-nested-cursor` | 基线中 `optional-nested-array` hook 路径失败（...7408 vs ...7409）；扩展中 `unkeyed-nested-cursor` 游标推进丢失精度失败 | bridge-green 已转绿 | **原样本已修复；扩展场景需后续验收** |
| **K-05** | **结构化 keyMap** | `path-collision` | `path-collision` 当前基线通过；保留历史分隔符碰撞回归用例 | bridge-green 已转绿 | **原样本已修复；扩展场景需后续验收** |

---

## 4. 架构根因

### A-01 五条键解析管线并存

| # | 管线 | 入口 | 键转换 | 缺失/null 语义 |
|---|---|---|---|---|
| A | Foundation | `decode(from: Data)` | Foundation 内部 | 严格 |
| B | raw 对象 | `yy_model(with:)` 等 | `decodingKey` 副本 1（`YYJSONRules.swift:186`） | 零填充（`YYJSONDecoder.swift:582`） |
| C | hook 重入 | `willTransform` 输出 | 副本再应用 | 同 B |
| D | 策略桥 | `.custom` date/data | 副本 2（`yy_bridgeSnakeCase`）+ keyMap | Foundation 严格 |
| E | 纯 native | `.native()` | 仅 Foundation | Foundation 抛错 |

蛇形转换 3 份实现、缺失/null 语义 3 种。F-01/02/03/04/05/06/09/10 全部是管线间分歧的直接产物。历史审查 FOLLOWUP/REREVIEW/SOLUTIONS/BRIDGE/KEYMAP 均已书面指出需收敛，未执行；`.workbuddy-ai/memory/2026-10-05.md` 记录「11→7 文件合并方案已提出但放弃」。

### A-02 精确数值走旁路而非主干

精确值通过 associated object（preserved Double）挂在 NSDecimalNumber 上，只有逐个打过补丁的调用点读它。历史时间线 F1→L1→S1→R3→REREVIEW→SOLUTIONS→BRIDGE→KEYMAP 即"每轮给下一个入口打补丁"：L1 修 F1 引入浮点回归（0.9999999999999999→1.0、-0.0→+0.0）；S1 阈值分类器让 -9223372036854775809 变合法 Int64.min；KEYMAP 记录 Mirror 白名单 + 类型名前缀分发本身成为新回归源。SOLUTIONS 轮原话「长期应收敛为一个内部数值解析入口」。数值类问题已被至少 6 轮宣布"修复"。

### A-03 探针不入库 + 自证结构

- `Tests/YYJSONDecoderTests/` 8 个文件 **0 处**出现：`willTransform`、`Decimal`、`Float`、`convertFromSnakeCase`/`keyDecodingStrategy`、`codingPath`、`superDecoder`、`nestedContainer`、`decodeNil`、`contains`、`bitPattern`。
- 对照证据：`CODE-REVIEW-KEYMAP-COLLECTIONS-20261005-WORKTREE.md` 记录同一份代码 `swift test` 93/93 通过、新增 9 组对照探针 8 组不一致。
- 项目复盘（.workbuddy-ai memory）：「修复者同时是验证者，会系统性漏掉两类问题：①既有契约 ②非默认配置……每轮交付必须附带先失败的探针」——探针由审查方写、存于 `docs/review-*/` 树外，从未迁入测试目标。

---

## 5. 已排除的误报（复核记录，防止后续重复报告）

| 疑点 | 复核结论 |
|---|---|
| **P-02** 负数取整方向错误 | **误报（处方事实错误）**。Foundation API 中 `.down` 为 floor（向负无穷）、`.up` 为 ceil（向正无穷）。源码对负数取 `.up` 正是数学向零截断，实测 `{"delta":-1.9}` 准确输出 `-1`。D2-1 处方若执行反致回归 |
| **P-07** Set 匹配 `Double($0.stringValue) ?? 0` | **误报（幽灵代码）**。引用的代码行在当前仓库根本不存在，系早期探索代理引用历史切片或幻觉产生，撤销 D2-2 |
| **F-03A** Data 入口改写字典数据键 | **误报（错误假设）**。经官方 Foundation 源码及实测验证，Foundation `JSONDecoder` 解码字典键时不应用任何 `keyDecodingStrategy`，两入口均保持原始键名，无需额外重解析机制 |
| `YYJSONRules.swift:196` 的 `.capitalized` 与 Foundation 蛇形转换分歧 | **不成立**。经 swift-foundation 官方源码核验，Foundation 实现逐字使用 `$0.capitalized`，两份一致 |
| 存在 `Int(truncating:)` / `numericCast` / `strtod` / locale 型 NumberFormatter | 不存在。字符串→整数（numericText）有显式溢出保护；Int8/16/32 全走 `I(exactly:)` 报错不截断 |
| 别名声明序解析不确定 | 不确定。`paths` 有序数组按声明序解析 |
| unkeyed 容器游标推进缺陷 | 未发现。copy-attempt-commit 模式正确 |
| 显式 null 覆盖 default 的三态表实现错误 | 实现忠实（`default` vs `fallback` 语义表、decodeIfPresent 镜像均正确） |
| 规则表线程安全 | 除 `dictionaryDate`（F-11e）外均有锁保护 |

---

## 附录 A：历史审查轮次与两类问题复发对照（外部评审人参考）

十轮审查的时间线与判定（详细原文见 docs/ 各审查文档；此处为缺陷登记册的证据底账）：

| # | 审查轮（docs/ 文档名关键词） | 数值类发现 | 字段类发现 | 状态 |
|---|---|---|---|---|
| 1 | SWIFT-ARCHITECTURE-REVIEW-20261004 | — | 「入口规则分裂，会产生'成功但字段错误'」 | 设计期预警，未收敛 |
| 2 | CODE-REVIEW-20261005（2.2.0） | 宣布"大整数不经 Double 中转——已满足" | 字符串键拼错无编译期报错 | 已过时 |
| 3 | INDEPENDENT（7a65125） | **F1**: hook 丢 Int64（9007199254740993.0→…992） | F2 字段日期策略在嵌套容器丢失；F3 defaults 对 superDecoder 不可见；F4 decodeNil 缺失==null | CHANGELOG 称已修 |
| 4 | LATEST | **L1**: F1 的修复引入浮点回归（0.9999999999999999→1.0、-0.0→+0.0，84 token 中 53 个变值） | L2 配置缓存；L3 入口/模型不匹配 | CHANGELOG 称已修 |
| 5 | IDIOMATIC | **S1**: ≥2^53 阈值丢小数、越界 -9223372036854775809 被吸收为 Int64.min | S2 点号键误拒；S3 反射元数据缺失→静默 0；S4 typed defaults 抛错 | 8 项全部修复 |
| 6 | FOLLOWUP（R1–R8） | **R3**: 阈值判据丢小数（0.123456789012345678） | R1 快路径跳过存在性/null 检查（空 JSON 得 0）；R2 配置入口绕过 mapper/required/validate；R6/R7/R8 | 2.3.1.1 全修 |
| 7 | REREVIEW | **P2**: 全 Decimal 存储丢 1 ULP（17+ 位 token） | 配置入口 .native 回退 legacy；"01"与"1" 键冲突；typedDefaults 不可读 | 本轮即发现轮 |
| 8 | SOLUTIONS | **P2 残余**: custom Date/Data 策略读 JSONSerialization 值，高精度 token 被 Decimal 有限精度替代 | — | 仅开方子 |
| 9 | BRIDGE-PATHS | **P2**: `[Double]`/`Double?` 绕过数值恢复 | **P1**: 物理键查找用转换后 CodingKey →「静默返回另一个字段」（串值） | 仅开方子 |
| 10 | KEYMAP-COLLECTIONS（最新） | **P2**: Set 去重先于纠正；`[[Double]]?`/`[Int:Double]` 1 ULP（Mirror 白名单） | **P1**: 仅最后键解析到物理路径（祖先键改名即串值）；keyMap 编码碰撞；类型名前缀分发 | **在库测试 93/93 通过，9 组新探针 8 组不一致** |

### A.1 数值类复发模式

| 问题形状 | 出现轮次 | 处方 | 复发原因 |
|---|---|---|---|
| >2^53 整数在某入口被 Double 中转 | 3→4→5→6 | 每轮移动分类阈值（F1→L1→S1→R3） | 修的是「阈值」不是「表示」：每轮修好探针 token、破坏相邻 token；无回归测试入库 |
| Double 位保真 / -0.0 | 4→5→7→8→9→10 | 每轮把 preserved 值挂到多一个路径（associated object） | 精确值在旁路、主干仍读有损树；每个新容器/快捷路径重新踩坑 |
| 越界整数应拒绝而非吸收 | 3→5 | 范围检查 | 同阈值类问题 |

**旁证**：数值类问题在 CHANGELOG 已被宣布修复 ≥6 次（2.1.8 "Strict Numeric Architecture"、2.1.9 "Unified Numeric Lexer"、F1、S1、R3、P2-4）。字符串→数字 coercion 是唯一**有测试**（s1/s4/s5 fixtures）且**停止复发**的子域——反证「探针入库」有效。

### A.2 字段类复发模式

| 问题形状 | 出现轮次 | 处方 | 复发原因 |
|---|---|---|---|
| 逻辑键↔物理键错位（串值/换字段） | 1→6→9→10 | 每轮修容器层的键查找 | 键→节点解析在每个容器层重复实现，各修各的；字符串编码路径键不单射 |
| 缺失/null/零填充语义漂移 | 3→6→7 | 统一"逻辑存在/null" | 旧语义沉在低层 `YYKeyedContainer`，新增快路径反复重新引入；Presence 又加第四套状态机 |
| 规则在新入口失效 | 3→6→7 | 修各入口 | 每个新入口克隆解码流程、漏掉部分规则应用步骤（配置 box 被修两次） |
| 点号/数字键 | 5→8→7→6 | 保留字面量 | 键归一化在读时急切应用；解码/编码各自维护支持列表 |
| 规则注册静默失效 | 5→6 | 构造期校验 | `validate()` 的键集合是手工清单，新 API（lossy/fallback）忘记登记 |

### A.3 历史审查自身的架构结论（均未执行收敛）

- FOLLOWUP：「两套默认值/兜底来源、Foundation/raw 两种容器以及新的配置 box，使相同策略落在多个分支……应先统一入口和字段解析的规则应用」
- REREVIEW：「新增局部判断能够修好一个复现，但容易影响另一个入口」
- INDEPENDENT：「逐个 API 增加独立分支会继续积累规则不对称」
- SOLUTIONS：「长期应收敛为一个内部数值解析入口，减少普通字段与原生策略两条路径各自补丁」
- BRIDGE-PATHS：「应收敛到'实际节点定位 + 按目标类型读取数值'的内部桥接，而不是继续追加特判」
- KEYMAP：「继续堆叠 Mirror 白名单与类型名字符串分支会提高维护成本，也容易只覆盖报告里的单一样本」
- 流程复盘（.workbuddy-ai memory）：「根因不是'不够仔细'，而是'自证'这个结构本身……每轮交付必须附带'先失败的探针'」——探针始终留在 `docs/review-*/` 树外，未入测试目标。

本登记册的 R-1/R-2/R-3 即对上述六条收敛建议的落地方案；A.1/A.2 的复发原因表是实施计划 Phase 0（探针先行）与验收独立性原则（验收人≠修复人）的直接依据。
