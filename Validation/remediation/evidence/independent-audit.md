# YYModelSwift 独立只读审查报告（2026-10-05）

> **审查性质**：独立只读审查。未修改仓库内任何源码、测试或文档。
> **基准代码库**：`/Users/lee/Desktop/本地项目调试计划/projects/YYModel`（HEAD `7605086`，tag 2.3.0 + 未提交改动）。
> **目标对标文档**：
> - `docs/DEFECT-REGISTRY-20261005.md`（缺陷登记册）
> - `docs/REMEDIATION-DESIGN-20261005.md`（修复设计）
> **探针环境**：仅在 `/tmp` 构建独立消费者可执行文件探针，严禁污染工程测试 target。
> **审查分工边界**：主代理负责五类 NativeBridge 组合问题及 E2E runner，本报告不重复展开 NativeBridge 组合矩阵，专注于核心 Swift 编解码管线、数值模型及修复处方事实性核验。

---

## 0. 核心重大发现速览（Executive Summary）

1. **P-02 是误报，且推荐处方 D2-1 存在严重事实错误**：
   - `DEFECT-REGISTRY` 宣称：`.down = 朝零截断`，`.up = 远离零`，指责源码 `copy.isSignMinus ? .up : .down` 导致负数得 `-2`。
   - **实际事实**：在 Apple Foundation 中，`NSRoundDown` 是 **向负无穷取整 (floor)**，`NSRoundUp` 是 **向正无穷取整 (ceil)**。对负数 `-1.9`，向零截断必须使用 `.up`（`-1.9` 向上即 `-1`）；对正数 `1.9`，向零截断必须使用 `.down`（`1.9` 向下即 `1`）。
   - **实测验证**：当前代码 `copy.isSignMinus ? .up : .down` 对 `-1.9` 准确输出 `-1`。若按 D2-1 改为无条件 `.down`，负数将变成 `-2`，**反而亲手引入严重 Bug**！
2. **P-07 是误报（幽灵代码 / 审计代理幻觉）**：
   - 登记册指控 `YYModelNativeBridge.swift:364-367` 存在 `Double($0.stringValue) ?? 0` 静默匹配零。
   - **源码核验**：当前仓库该位置及全仓库任何源文件中**根本不存在这行代码**。D2-2 的修改方案是针对不存在代码开出的无效处方。
3. **F-03 问题 A 属于错误假设（误报）**：
   - 登记册宣称 Foundation 对 `[String: V]` 键会执行 `keyDecodingStrategy`（导致 Data 入口得 camelCase，raw 入口得 snake_case）。
   - **实测验证**：Apple 官方 Foundation `JSONDecoder` 解码 `Dictionary<String, V>` 时，将字典键视为**数据**，无论是 `.convertFromSnakeCase` 还是 `.custom` 策略，**一律不转换字典键**！两入口均输出原始键名。D3-3 试图用 `JSONSerialization` 重新解析 Data 绕开 Foundation 是无谓的过度设计。
   - **但 F-03 问题 B 真实存在**：裸 `[Int: V]` 键解析中，`"01"` 与 `"1"` 会无序覆盖，依赖字典哈希迭代序。
4. **F-02 / F-07 已通过独立探针完全复现**：
   - F-02：外部 `forType` 注册规则整体吞噬模型静态 `yy_modelConfiguration`（已写探针证实 `uid` 映射失效）。
   - F-07：`YYModelPresence` 仅在 keyed 容器做了特判，数组 `[YYModelPresence<T>]` 遇到 `null` 元素在 `YYModelDecode.value` 抛出 `valueNotFound` 崩溃（已写探针证实）。
5. **当前宿主环境（macOS 26.7）无法直接验证 P-01 的旧 OS 缺陷**：
   - 当前 macOS 26.7 使用 swift-foundation，`Decimal` 解码直接解析 token 字符串，不会丢精度。
   - 旧 Foundation（iOS 11-15 / macOS 10.13-12）中 `Decimal` 经 `Double` 中转属于已知历史行为，但**当前机型无旧系统模拟器，严禁冒充旧 OS 验收**。

---

## 1. 缺陷逐项核对表（P-01 ~ P-08、F-01 ~ F-11、A-01 ~ A-03）

| 缺陷 ID | 审计判定 | 涉及文件与符号 | 真实证据与关键分析 | 最小建议 |
|---|---|---|---|---|
| **P-01** | **源码确认 / 无法在当前环境验证（旧 OS）** | `YYModelSwift/YYModelDecoder.swift:349-357`<br>`Package.swift:18-21` | 源码注释坚称"Foundation 对 JSON 数字 token 的 Decimal 解码是精确的"，未限定 OS。在 iOS 16 前（C/ObjC Foundation）`Decimal(from: decoder)` 内部通过 `decode(Double.self)` 中转。但当前宿主系统为 macOS 26.7（Darwin 26），系统库已是 swift-foundation，字面量解码精确，无法在本地重现 9007199254740993 丢精度。 | 严禁冒充旧系统通过测试；在旧系统支持生命周期内，采用运行时环境探测或静态降级路由（R-3），若放弃旧系统则抬高 deployment target 到 iOS 16。 |
| **P-02** | **误报（处方存在重大事实错误）** | `YYModelSwift/YYJSONDecoder.swift:417-424`<br>`integer<I>(_:_:)` | **登记册与处方 D2-1 严重翻车**。Foundation 中 `NSRoundDown` 是 floor，`NSRoundUp` 是 ceil。源码 `copy.isSignMinus ? .up : .down`：对负数用 ceil（`-1.9 -> -1`），正数用 floor（`1.9 -> 1`），**本就已经在向零截断**！`/tmp` 探针实测 `{"delta": -1.9}` 准确解析为 `-1`。若按 D2-1 改成无条件 `.down`，负数将变成 `-2`！ | **坚决撤销 D2-1 处方，保持原代码逻辑不变**。补充针对正负浮点数向零截断的测试用例。 |
| **P-03** | **源码确认** | `YYModelSwift/YYModelEncoder.swift:19, 71`<br>`YYModelSwift/YYModelCodable.swift:80`<br>`YYModelSwift/YYModelPolymorphic.swift:17, 47` | 导出时将 JSONEncoder 产出的 Data 通过 `JSONSerialization.jsonObject(with:)` 解析为 `[String: Any]`。在 ObjC `NSJSONSerialization` 内部，任何带有小数点的数值都被还原为 `Double` 支撑的 `NSNumber`，导致 `1.000000000000000031251` 塌缩为 `1.0`。 | 如 R-2 所述，编码器导出直出 `YYModelJSONValue` 树，避免 `Data -> JSONSerialization` 的损耗性往返。 |
| **P-04** | **源码确认** | `YYModelSwift/YYModelNativeBridge.swift:46`<br>`YYModelNativeBridge.custom` | 在 `.custom` 日期/数据策略下，桥接层调用 `JSONSerialization.data(withJSONObject: raw.value)` 重组 Data，使得 raw 中挂载的精确数值及 associated object 丢失。（注：本项涉及 NativeBridge，主代理负责，已对齐边界）。 | 桥接层改由 `YYModelJSONValue.encode()` 输出标准化字节流。 |
| **P-05** | **源码确认** | `YYModelSwift/YYJSONDecoder.swift:491-495`<br>`date(fromTimestamp:)` | 源码 `abs(seconds) > 1e11 ? seconds / 1000.0 : seconds`，直接将微秒时间戳（如 `1699999999999999`）除以 1000 误当成毫秒，导致时间相差 1000 倍。且此启发式不可配置。 | 维持 legacy 兼容行为，但新增显式时间戳策略配置（如 `.microsecondsSince1970`），并补充诊断日志。 |
| **P-06** | **源码确认** | `YYModelSwift/YYJSONDecoder.swift:234-238`<br>`floating<F>(from:_:)` | `floating` 先调用 `double(from: value)` 取得 `Double`，再通过 `F(number)` 窄化为 `Float`。超过 9 位有效数字的输入会经历两次 IEEE 754 舍入（先 53 位再 24 位），相比单次舍入可能相差 1 ULP。 | 若具备文本字面量优先使用 `Float(text)`，未命中时再使用 `Float(double)`。 |
| **P-07** | **误报（幽灵代码）** | `YYModelSwift/YYModelNativeBridge.swift:364-367` | 登记册声称此处有 `Double($0.stringValue) ?? 0`。经全面检索，当前代码库该处是 `YYModelPrefixEncoder`，全工程没有任何一处包含该表达式。系探索代理引用了历史草稿或幻觉。 | **驳回 D2-2 处方，关闭该缺陷条目**。 |
| **P-08** | **源码确认** | `YYModelSwift/YYJSONDecoder.swift:182-232`<br>`YYModelSwift/YYJSONDecoder.swift:412-415` | `bool(from:)` 将 `"1"`/`1` 转为 true，`string(from:)` 将数值转字符串，`integer` 将布尔转 1/0。虽然这是 YYModel 的传统宽容语义，但全过程没有任何诊断开关或日志通道。 | 保持现有宽容转换，但在 Debug 环境或开启诊断标记时向诊断通道输出 coercion 事件。 |
| **F-01** | **源码确认** | `YYModelSwift/YYJSONDecoder.swift:539-542`<br>`_YYDecoder.container(keyedBy:)` | `for (key, value) in dictionary` 直接遍历 Swift `[String: Any]`，由于 Swift 字典每次运行哈希种子随机，若 JSON 中存在映射到同一属性的两个物理键（如 `"user_name"` 与 `"userName"`），胜者完全由哈希迭代序决定，跨运行不稳定。 | 规范化迭代序，如按 `dictionary.keys.sorted()` 确定性胜者规则，或精确键绝对优先（D3-1 选项 A）。 |
| **F-02** | **已复现** | `YYModelSwift/YYJSONRules.swift:30-38, 135-142`<br>`YYJSONRules.forType`<br>`YYJSONContext.rule` | **已通过 `/tmp/f02_probe` 复现**：模型通过 `yy_modelConfiguration` 映射 `id <- uid`，外部设置 `rules.forType(UserModel.self) { $0.require(\.name) }`。解码时外部规则直接覆盖并短路模型自带规则，导致 `{"uid": 42}` 无法读取 `id`（结果为 0）。 | 修复 `forType`：以模型自带规则（`_yyRule()`）为底座进行增量合并，而非直接 new 空配置覆盖（D3-2 选项 A）。 |
| **F-03** | **部分误报 / 部分源码确认** | `YYModelSwift/YYModelDictionary.swift:89-104`<br>`decodeDictionary` | **A. 策略相反（误报）**：经官方 Foundation 实测，Foundation 对 `Dictionary<String, V>` 根本不应用 `keyDecodingStrategy`（始终保持 raw 键名）。因此两入口键名表现其实一致。<br>**B. Int 键合并（源码确认）**：`YYModelDictionaryKey.make` 对裸 `Int` 键直接使用 `Int(name)`，`"01"` 与 `"1"` 均解析为 `1`，在 `result[try key(for: name)] = ...` 中因无序字典遍历产生不确定覆盖。 | 驳回针对 Problem A 的 JSONSerialization 重新解析设计；专注于修复 Problem B（Int 键保留字面量拼写以判定冲突与确定性排序）。 |
| **F-04** | **源码确认** | `YYModelSwift/YYModelDecoder.swift:251-257`<br>`YYModelSwift/YYModelDecoder.swift:426-437` | `contains` 方法在键命中 `policy.typedDefaults` 或 `fallbacks` 时返回 `true`；但后续若调用 `superDecoder(forKey:)` 或 `nestedContainer(forKey:)`，该处只检查 `field` 和 `defaults`，未包含 `typedDefaults`/`fallbacks`，直接抛出 `keyNotFound`！存在性判断出现两面派。 | 统一存在性判定与容器物化逻辑，使 `superDecoder(forKey:)` 能够物化 `typedDefaults`/`fallbacks`（收敛于 R-1）。 |
| **F-05** | **源码确认** | `YYModelSwift/YYModelDecoder.swift:241`<br>`field(_:)` | 路径查找时 `guard let child = try? current.nestedContainer(...)` 使用 `try?` 吞掉所有错误。无论是中间路径节点非对象（类型不匹配），还是自定义 keyDecodingStrategy 抛错，全被折叠为 nil，在 legacy 模式下触发 zeroFill 补零，掩盖数据异常。 | 区分「键不存在」与「结构性解析错误/策略抛错」，仅对前者继续遍历候选，后者显式抛出或记录损失。 |
| **F-06** | **源码确认** | `YYModelSwift/YYModelJSONValue.swift:281-284`<br>`YYModelJSONInput.object(at:context:)` | Hook 获取输入快照时，先无条件取精确键 `dictionary[key.stringValue]`；未命中再走 `dictionary.keys.first(where:)`（哈希迭代序）。与解码主流程的序列化序/映射序不一致，且向用户闭包传递了混杂路径。 | 统一由主干解码器在遍历时顺带产出节点映射信息（keyMap），Hook 快照直接查表，不再二次猜测键名。 |
| **F-07** | **已复现** | `YYModelSwift/YYModelPresence.swift:120`<br>`YYModelSwift/YYModelDecoder.swift:147-150, 361-377` | **已通过 `/tmp/f07_probe` 复现**：`[YYModelPresence<String>]` 遇到 `["hello", null, "world"]` 时，元素解码直接走 `YYModelDecode.value`，因未针对 Presence 下沉判断，命中 `:147` 的 `decodeNil() == true` 且非 Optional，抛出 `DecodingError.valueNotFound` 导致整组解码失败。在 lossy 数组中亦会被误当作错误丢弃。 | 将 Presence 的 `.null` / `.absent` 识别逻辑从仅在 `YYModelKeyedDecoder` 拦截下沉到 `YYModelDecode.value` 单点，使数组元素与字典值均支持三态。 |
| **F-08** | **源码确认** | `YYModelSwift/YYModelDecoder.swift:291-322`<br>`YYModelSwift/YYModelLossy.swift:119-121` | 1. `lossy` 遇到错误元素记录报告时，若调用方未传 `YYModelLossReport`，元素被静默丢弃。<br>2. `fallback` 检查在 `:291` 先于 `lossy`（`:315`），同属性配置两者时，整数组直接回退兜底，逐元素 lossy 永远无法执行。<br>3. `:318` 获取 `nestedUnkeyedContainer` 在 do-catch 外，非数组字段直接炸毁整个模型解码。 | 调整判定优先级：lossy 优先于 fallback；无报告时创建默认报告或告警；将 unkeyed 容器获取移入 do-catch。 |
| **F-09** | **源码确认** | `YYModelSwift/YYJSONDecoder.swift:601-605`<br>`superDecoder()` | `let value = dictionary["super"] ?? dictionary`：当 JSON 存在正常业务属性 `"super"` 时（如权限字段），父类解码器直接被劫持为该字段的值，造成类型崩溃；且与 Foundation 查找嵌套 `"super"` 的语义相反。 | 移除对业务键 `"super"` 的读取特判，继承体系使用扁平字典或者显式规范化父类路径，消灭键劫持漏洞。 |
| **F-10** | **源码确认** | `YYModelSwift/YYModelPolymorphic.swift:28-31`<br>`YYModelPolymorphism.decode` | 判别字段解码时：在 Data 入口走严格 String 校验（数字直接 typeMismatch）；在 raw 入口走宽容解码（数字转 `"1"`，null 转 `""`），甚至在 null 时抛出 `"Unknown model discriminator: "` 这样令人费解的空错误。 | 统一多态判别符的读取策略，严格要求 String 类型或统一宽容转换，并在 null 时抛出清晰的 `discriminatorNull` 错误。 |
| **F-11a** | **源码确认** | `YYModelSwift/YYModelDecoder.swift:357` | 整数快路径中调用 `YYJSONValueDecoder.decode(..., codingPath: [])`，丢失了字段上下文路径，抛错时错误路径为空数组。 | 传入 `codingPath + [key]`。 |
| **F-11b** | **源码确认** | `YYModelSwift/YYModelDecoder.swift:282, 377` | 零填充模式下，`decodeNil` 对缺失键返回 `true`（视为 null），而 `decode` 对 Presence 返回 `.absent`，两接口对同一缺失键的判定互相矛盾。 | 统一三态收敛判断（`logicalNull`），零填充下对 Presence 统一返回 `.absent`。 |
| **F-11c** | **源码确认** | `YYModelSwift/YYModelEncoder.swift:145, 155-159` | `nestedContainer` 与 `superEncoder` 各自重新 `new` 了 `YYModelEncodingState`，嵌套编码器的错误未汇聚至顶层 state，导致编码错误被吞噬。 | 将 `state` 改为引用语义并在子容器间共享传递。 |
| **F-11d** | **源码确认** | `YYModelSwift/YYModelJSONValue.swift:290` | `willTransform` 直接将 `_YYDecoder.value`（如果是字典指针）传给用户闭包，用户可原地修改入参，污染外部数据源。 | 对传入 Hook 的对象进行浅拷贝隔离。 |
| **F-11e** | **源码确认** | `YYModelSwift/YYModelDictionary.swift:98-99` | 在共享的 `context` 上无锁读写 `context.dictionaryDate`，在多线程并发解码字典时存在严重数据竞争（Data Race）。 | 移除共享 context 状态，沿解码调用栈参数传递 DateStrategy。 |
| **F-11f** | **源码确认** | `YYModelSwift/YYModelDecoder.swift:225-229` | `allKeys` 将底层的物理键（如 `uid`）和上层映射的属性名（如 `id`）混在一起输出。 | 过滤物理别名，`allKeys` 仅暴露模型声明的属性名。 |
| **A-01** | **源码确认（根因）** | 全局 5 条键解析链路并存 | Foundation、raw 对象、hook、桥接、native 5 条链路各自实现一套键转换与判空，是 F-01~F-10 缺陷反复出现的结构性根因。 | 落地 R-1：统一构建内部 `YYFieldResolver`，收敛键查找与缺失判定。 |
| **A-02** | **源码确认（根因）** | 旁路数值保留机制 | 使用 Associated Object 旁路挂载 preserved Double，主干仍然是 NSDecimalNumber，导致新增容器时频繁遗漏数值恢复。 | 落地 R-2：由 `YYModelJSONValue` 单一树承载数值字面量，贯穿主干。 |
| **A-03** | **源码确认（根因）** | 测试盲区与自证循环 | 现有 93 项单元测试未覆盖 `Decimal`、`Float` 精度、`convertFromSnakeCase` 冲突及多态判别符边界；验证者与修复者同角色。 | 探针入库，建立独立验证集，实行红绿 TDD。 |

---

## 2. 深度专题验证与事实性纠偏

### 2.1 P-02：NSDecimalNumber 取整语义真相与 D2-1 严重处方错误

#### 事实调查
在 Objective-C / Swift Foundation 中，`NSRoundingMode` 的底层定义如下：
- `NSRoundPlain`：四舍五入。
- `NSRoundDown`：**向负无穷大方向取整 (Floor / Toward -Infinity)**。
- `NSRoundUp`：**向正无穷大方向取整 (Ceil / Toward +Infinity)**。
- `NSRoundBankers`：银行家舍入（偶数舍入）。

#### 原型探测（执行于 `/tmp` 独立 Swift 运行时）
```swift
let pos = NSDecimalNumber(string: "1.9")
let neg = NSDecimalNumber(string: "-1.9")
// NSRoundUp:
pos -> 2, neg -> -1
// NSRoundDown:
pos -> 1, neg -> -2
```

#### 当前源码实现（`YYJSONDecoder.swift:420`）
```swift
let mode: NSDecimalNumber.RoundingMode = copy.isSignMinus ? .up : .down
NSDecimalRound(&truncated, &copy, 0, mode)
```
- 当输入为 `1.9`（正数）时：`copy.isSignMinus == false` $\to$ 选择 `.down` $\to$ 向负无穷取整得 `1`（**朝零截断**）。
- 当输入为 `-1.9`（负数）时：`copy.isSignMinus == true` $\to$ 选择 `.up` $\to$ 向正无穷取整得 `-1`（**朝零截断**）。

#### 审查结论
1. **源码逻辑完全正确**：当前代码实现的正是**向零截断 (Toward Zero)**！
2. **文档与设计颠倒**：`DEFECT-REGISTRY-20261005` 以为 `.down` 是朝零截断，得出源码负数算错的荒谬结论；
3. **严重事实错误**：`REMEDIATION-DESIGN-20261005` 中的 **D2-1 方案** 要求"将 `copy.isSignMinus ? .up : .down` 改为无条件 `.down`"。如果照此修复，负数 `-1.9` 将立刻被截断成 `-2`，直接破坏向零截断契约并引入严重回归！**必须立即驳回 D2-1**。

---

### 2.2 F-03：Dictionary 键解析策略机制澄清

#### 事实调查
`DEFECT-REGISTRY` 宣称：
> Data 分支（`:100 decode([String: YYModelDictionaryValue<Value>].self)`）经 Foundation 会应用 `keyDecodingStrategy`，破坏不变量。`{"data": {"snake_case": 1}}` 解码 `[String: Int]`：Data 入口得 `"snakeCase"`，对象入口得 `"snake_case"`。

#### 原型探测（执行于 `/tmp` 独立 Swift 运行时）
测试 Foundation 原生 `JSONDecoder` 与 `YYJSONDecoder` 对 `[String: Int]` 在 `.convertFromSnakeCase` 及 `.custom` 策略下的表现：
```swift
let json = "{\"snake_case\": 1}".data(using: .utf8)!
let decoder = JSONDecoder()
decoder.keyDecodingStrategy = .convertFromSnakeCase
let dict = try decoder.decode([String: Int].self, from: json)
// 输出：["snake_case": 1]
```
探测结果表明：**Apple Foundation 本身就将字典的 Key 视为数据内容，在解码 `[String: T]` 时根本不会触发 `keyDecodingStrategy`！**无论是 Foundation 还是 YYModel，Data 入口与 raw 入口解出的 Key 都是原始的 `"snake_case"`。

#### 审查结论
1. **F-03 Problem A 是误报**，两入口行为原本一致，并不存在数据键被 Foundation 意外转换的问题。
2. **驳回 D3-3 选项 A1 中通过 `JSONSerialization` 重读字典键的过渡设计**：Foundation 既未改写键名，额外增加 JSONSerialization 只会白白浪费内存与 CPU。
3. **F-03 Problem B（裸 `[Int: V]` 键合并）确实存在**：因 Swift 字典迭代顺序随机，`"01"` 与 `"1"` 映射至同一 Int 键时胜者不确定，应按规范增加字面量冲突校验与确定性排序。

---

### 2.3 F-02：规则组合整体覆盖（已复现）

#### 失效场景
用户在 Model 内通过 `static var yy_modelConfiguration` 定义了主键映射（如 `id <- uid`）。业务端在使用 `YYJSONDecoder` 时，尝试通过外部 Rules 为该类型添加校验或必填项（如 `require(\.name)`）。

#### 探测结果
编译并运行 `/tmp/f02_probe`：
- 无外部 Rule 时：`id = 42, name = Alice`（映射生效）。
- 加入外部 Rule 后：`id = 0, name = Alice`（**模型自带的 `id <- uid` 映射被整体丢弃，退化为默认值 0**）。

#### 根因与修复建议
- **根因**：`YYJSONRules.forType` 在初始化时使用全新的空 `YYModelConfiguration`，且在 `YYJSONContext.rule()` 中，一旦外部字典命中，直接短路返回，从未读取模型的 `_yyRule()`。
- **裁定建议**：采纳 **D3-2 选项 A**。`forType` 必须以 `Model._yyRule()` 为基础进行增量叠加（Overlay），保证模型自带配置不丢失。

---

### 2.4 F-07：Presence 遇到 null 崩溃（已复现）

#### 失效场景
用户定义三态模型数组 `var items: [YYModelPresence<String>]`，输入 JSON 为 `{"items": ["hello", null, "world"]}`。

#### 探测结果
编译并运行 `/tmp/f07_probe`：
- 控制台抛出异常：
  `DecodingError.valueNotFound: Expected value of type YYModelPresence<String> but found null instead. Path: items[1]. Debug description: Null value`
- 数组解码直接失败崩溃！

#### 根因与修复建议
- **根因**：`YYModelPresence` 的三态捕获被狭隘地放在 `YYModelKeyedDecoder.decode` 中，底层容器和 `YYModelDecode.value` 根本不知道 Presence 的存在。当单值容器遇到 `null` 时，直接走非 Optional 的抛错分支。
- **裁定建议**：采纳 R-1 建议，将三态类型（`YYModelPresenceType`）判定下沉到 `YYModelDecode.value` 顶层分支，让数组、字典值及单值容器天然享有三态保护。

---

### 2.5 F-08、F-09、F-10 源码确认结论

- **F-08（lossy 数组）**：
  - 源码第 291 行（fallback）位于第 315 行（lossy）之前，同一字段同时配置两者时，fallback 必然强行劫持整数组，lossy 被完全架空。
  - 第 318 行获取 `nestedUnkeyedContainer` 未包裹在 do-catch 内，遇非数组直接造成整个顶层模型解码失败。
- **F-09（superDecoder）**：
  - 源码第 603 行 `let value = dictionary["super"] ?? dictionary`，若 JSON 包含业务键 `"super"`，父类解码器将直接读取该业务字段，导致严重的数据类型劫持。
- **F-10（多态判别符）**：
  - Data 入口与 Raw 入口在对待数字或 null 判别符时表现截然不同，null 在 raw 入口被 zeroFill 为 `""`，生成误导性错误信息 `"Unknown model discriminator: "`。

---

## 3. 契约裁定评估（D3 组推荐方案分析）

> 依据用户授权要求，以下对 D3 系列推荐方案进行可行性与风险评估，供决策人审阅参考，**本审查不越权代表用户签名**。

### 3.1 D3-1（物理键冲突胜者确定性）
- **推荐方案**：选项 A（精确相等者优先；否则按 UTF-8 字典序最小胜出）。
- **可行性评估**：优秀。因为 `[String: Any]` 输入本身已无序列化序，排序是唯一能跨运行、跨设备保证结果确定性的方案，消灭哈希随机波动。

### 3.2 D3-2（外部规则合成语义）
- **推荐方案**：选项 A（以模型自带规则为基底进行叠加合并）。
- **可行性评估**：必须实施。当前外部规则整体替换模型配置是严重的设计缺陷（已实测复现 F-02）。

### 3.3 D3-3（字典数据键与裸 Int 键）
- **评估意见**：**修正推荐处方**。
  - 对问题 A（数据键）：无需实施绕开 Foundation 的繁琐方案，因 Foundation 根本不改写字典键。
  - 对问题 B（Int 键）：实施裸 Int 键字面量保留与确定性合并规则，避免 `"01"` 与 `"1"` 随机覆盖。

### 3.4 D3-4（lossy/fallback 优先级与可见性）
- **推荐方案**：lossy 提升到 fallback 前；容器获取放入 do-catch；默认补足 LossReport。
- **可行性评估**：优秀。符合"不静默丢弃"设计原则，增强数组容错能力。

### 3.5 D3-5（superDecoder 扁平继承与键劫持）
- **推荐方案**：移除 `dictionary["super"]` 特判。
- **可行性评估**：优秀。彻底杜绝业务字段 `"super"` 导致的解码器劫持。

### 3.6 D3-6（多态判别符严格化）
- **推荐方案**：两入口统一要求判别符为严格 String，null 时报明确错误。
- **可行性评估**：优秀。消灭两入口多态分流的不对称性。

---

## 4. 长期维护风险与错误验收假设预警

### 4.1 错误验收假设警告：严禁在现代 macOS 上冒充旧 OS 验收 P-01
- **环境事实**：当前运行环境为 macOS 26.7，Swift 6.3.3，Xcode 26.6。系统搭载的 Foundation 均为现代 swift-foundation。
- **风险警告**：在当前机器上运行 `Decimal` 针对大整数（>2^53）的解码，**由于现代 Foundation 本身就保真，测试永远是绿色的**！
- **红线要求**：测试工程中严禁编写一个在 macOS 26 上跑通就声称"已在 iOS 11/旧系统上验证 P-01"的伪用例。如果需要支持旧系统降级，必须通过 Mock 底层双精度中转容器，或在具备旧 OS Simulator（iOS 14/15）的专用 CI 节点上运行验证。

### 4.2 长期维护风险：审查文档与代码漂移（Phantom Defects）
- 本次审查发现了两个严重的文档与代码脱节：
  1. **P-02**：文档作者对基础 Foundation API 语义理解反转，开出具有破坏性的毒药处方（D2-1）；
  2. **P-07**：文档中记录的代码位置与代码片段在当前仓库中完全不存在（幽灵条目）。
- **维护建议**：
  - 严禁"文档驱动假象修复"；所有缺陷合入前必须先建立**可失败的独立复现探针**；
  - 清理 `docs/` 目录中冗余的历史 worktree 审查切片，建立单一权威事实源。

### 4.3 架构收敛（R-1/R-2）的实施节奏
- 当前主代理负责 NativeBridge 组合及 E2E runner，核心库同时面临 5 条管线割裂的难题。
- 实施 R-1（统一 `YYFieldResolver`）时，务必通过内部特性开关（`unifiedFieldResolution = false`）分步灰度替换，防止对现有 93 项单元测试和 49 项 ObjC 契约造成非预期冲击。

---

## 5. 审查结论与后续行动建议

1. **纠偏清单**：
   - 立即从待修复列表中剔除 **P-02**（代码已正确，作废 D2-1）；
   - 立即关闭 **P-07**（代码不存在，作废 D2-2）；
   - 剔除 **F-03 Problem A**（Foundation 原生无此缺陷，简化 D3-3）。
2. **重点修复推进**：
   - 高优先级落地 **F-02**（外部规则合并）、**F-07**（Presence 下沉支持集合）、**F-08**（lossy 优先级及健壮性）；
   - 规范化 **F-01**（键冲突排序）与 **F-09**（superDecoder 键劫持）；
   - 实施低危集合 **F-11（a~f）** 的安全微调。
3. **交付物归档**：
   - 本报告已保存在 `/tmp/yymodel-agy-current-audit.md`，可作为后续重构与方案裁定的权威输入依据。
