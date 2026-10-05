# 修复方案设计（Remediation Design）— 2026-10-05

> **文档定位**：针对 [DEFECT-REGISTRY-20261005](DEFECT-REGISTRY-20261005.md) 全部缺陷的修复设计。
> 实施顺序与排期见 [REMEDIATION-IMPLEMENTATION-PLAN](REMEDIATION-IMPLEMENTATION-PLAN-20261005.md)；
> 每项设计的验收标准见 [REMEDIATION-ACCEPTANCE-PLAN](REMEDIATION-ACCEPTANCE-PLAN-20261005.md)。
> 本文只做设计，不含代码改动。设计分四层：
> **D2 快速修复**（低风险单点）→ **D3 契约决策**（行为确定化，需评审裁定）→ **R-1/R-2/R-3 架构收敛**（根治复发）。

---

> **执行证据更新**：当前修复进度以 [公开 E2E 状态表](../Validation/remediation/STATUS.md) 和冻结源码回执为准。
> 下文“位置/复现”保留审计基线；源码疑点不等同于已复现运行缺陷。正式外部签署及旧 OS 运行验收未完成。


## 本轮已实施的设计与边界

R-1共享字段解析、R-2直接树导出与集中规范标量投影、R-3缓存能力探测及顶层整数路由均已实施。
公开验收555项通过，含独立审查补充的逻辑祖先、整数负零、Unicode蛇形编码、重复容器、
super键策略及自定义字典CodingKey。保留普通无hook Data的Foundation快速编码路线，
避免为架构整齐给普通业务添加树分配。NSNumber仅在公开交互边界挂载不可变规范节点；
不暴露元数据修改API，也不保留另一套内部Double/Float数学旁路。

`.integerTokens` 在载荷可能包含 `-0` 时同步读取符号并补回JSONSerialization丢失的负零，
不经第二套数值解析器重建整数。现代默认精确路径无需此补读。G5真实旧 OS运行与G7外部签署
仍未完成；可核验结果与性能数字统一见[公开状态表](../Validation/remediation/STATUS.md)。

## 1. 设计原则

1. **先安全网后修复**：任何修复合入前，对应探针测试必须已存在且先行失败（治 A-03「自证」）。
2. **行为变更显式公告**：D3 组每一项都有"行为变化"性质，必须在 CHANGELOG 与 `UPGRADE-COMPAT-GUIDE` 中列出旧→新行为对照，禁止静默变更。
3. **收敛优于补丁**：根治两类问题的路径是减少管线与数值表示的数量（R-1/R-2），与历史审查（FOLLOWUP/REREVIEW/SOLUTIONS/BRIDGE/KEYMAP）书面建议一致；任何"再给一个入口打补丁"的方案一律不采纳。
4. **性能不回退**：历史 `.compatible` 记录为 3.50×；本轮同工具链修复前实测 3.81×（目标 ≤3.00× 未达）。R-2 收敛数值链预期改善性能；任何阶段回退超 ±10% 即阻断（验收门禁 G4）。
5. **可回滚**：每阶段保留冻结源码及完整 E2E 回执，源码快照可重放/恢复；本轮不为回滚而维护两套字段/数值管线。R-3 提供公开的逐 decoder 路由选项。发布回滚采用先前已验收的发行版本。

---

## 2. D2 快速修复组（低风险，无需契约裁定）

### D2-1【已作废·维持原代码】P-02 负数截断方向

- **复核纠偏结论**：**原处方作废，生产代码保持现状**。
- **原因**：在 Apple Foundation API 中，`NSRoundDown` 为 floor（向负无穷取整），`NSRoundUp` 为 ceil（向正无穷取整）。源码 `let mode: NSDecimalNumber.RoundingMode = copy.isSignMinus ? .up : .down` 对负数取 `.up`（`-1.9 -> -1`）、正数取 `.down`（`1.9 -> 1`），**数学上已准确实现了向零截断（Toward Zero）**。
- **事实危险性**：若执行原处方 D2-1（将模式改为无条件 `.down`），对负数 `-1.9` 将向下取整得到 `-2`，反而会**破坏向零截断契约并引入严重回归**。
- **行动**：撤销对 `YYJSONDecoder.swift:420` 的修改；在测试套件中补充正负数浮点转整数的回归锁定探针（`{"delta":-1.9} -> -1`，`{"delta":1.9} -> 1`）。

### D2-2【已作废·条目关闭】P-07 Set 匹配静默匹配零

- **复核纠偏结论**：**处方作废，缺陷条目关闭**。
- **原因**：原处方引用的 `YYModelNativeBridge.swift:364-367` 及全仓库任何源文件中，均不存在 `Double($0.stringValue) ?? 0` 这行代码（系早期探索代理引用历史切片或幻觉产生）。代码库中不存在该缺陷，无需修改。

### D2-3 修复 F-11 六项低危

| 子项 | 方案 | 现状与风险说明 |
|---|---|---|
| a（codingPath 空） | `YYModelDecoder.swift:357` 的 `codingPath: []` 改为 `codingPath + [key]` | **待证/局部风险**：该行位于 `try?` 快路径内，失败会自然回退至带完整 codingPath 的常规路径。修补可保证快路径自身抛错信息的完整性 |
| b（decodeNil/presence 矛盾） | 抽一个 `logicalNull(forKey:) -> Bool` 单点实现，`decodeNil` 与 `decode` 共用（零填充下统一报 **absent**，与 strict 语义对齐） | 源码已确认存在矛盾，按原设计修复 |
| c（编码侧错误落空） | `YYModelEncoder` 的 `state` 改为引用语义贯穿嵌套容器与 superEncoder（init 传入同一 state 实例），顶层 `:40` 统一抛出 | 公开 E2E 嵌套 mapper 冲突在修复前已正确拒绝；原源码推断尚未得到失败样本，不按确诊缺陷计数 |
| d（willTransform 活字典） | 对传入 hook 的字典对象进行递归隔离 JSON 可变引用子树 | **公开 E2E 已复现**：Swift 顶层 Dictionary 的 COW 安全，但 hook 修改 NSMutableArray 子树会令原数组 count 从 1 变 2；浅拷贝不足以修复 |
| e（dictionaryDate 无锁） | 移除共享 context 槽位，改为沿解码调用链显式传参（`YYModelDictionaryValue` 已持 `date`，删除 `:98-99` 的全局写） | 100 次并发公开解码修复前已通过；每次公开调用有独立 context。移除隐式槽位属于维护性收敛，不声称已复现公开 API 串扰 |
| f（allKeys 混露） | `YYModelKeyedDecoder.allKeys` 只返回映射后的属性名（逻辑键），物理别名键不暴露；如需源键提供独立 API `yy_sourceKeys` | 源码已确认混杂物理别名，按原设计修复 |

---

## 3. D3 契约决策组（行为确定化/变更，需评审裁定后实施）

> **授权与签署说明**：用户已授权按本文档技术路线推进全部修复；推荐契约方案已完成技术评估，但正式签署仍未完成（待外部专业评审人与项目负责人正式签字确认）。

### D3-1 修复 F-01：物理键冲突确定性规则

- **约束**：`[String: Any]`（NSDictionary）输入本质上已丢失序列化序，**无法**完全对齐 Foundation 的"序列化序 first-wins"。
- **选项 A（推荐）**：定义确定性规则——①逻辑键与某物理键**精确相等**者优先；②否则**UTF-8 字节序最小**的物理键胜。实现：`_YYDecoder.container` 按 `dictionary.keys.sorted()` 迭代后再应用 first-wins。文档明示与 Foundation 序列化序的差异及原因。
- **选项 B**：改走"键序探测"——消费端传入有序结构（`[(String, Any)]` 新入口），旧行为保留。成本高、面窄，仅当评审认为精确对齐 Foundation 是硬需求时选用。
- **探针**：同输入重复 100 次结果稳定；`["user_name":"A","userName":"B"]` 在 raw 入口恒定得 B（精确逻辑键 `userName` 优先；且 UTF-8 中 `_` 大于 `N`）；Data 入口保持序列化序胜者（不回归）。

### D3-2 修复 F-02：外部规则与模型规则的合成语义

- **选项 A（推荐）**：`YYJSONRules.forType` 当类型符合 `YYModelCodable` 时，以模型 `_yyRule()` 结果为**基底**构造 `YYModelConfiguration` 再执行 configure 闭包——外部配置**增改**而非替换（显式覆盖模型 mapper 的仍然后写优先）；二次 `forType` 同理以已注册条目为基底。语义文档化。
- **选项 B**：保持替换语义，但在 DEBUG 下于 `forType` 检测到模型自有规则/先前注册时打印警告，并在 README 标注。改动最小，但"静默失效"主诉仍在。
- **推荐理由**：选项 A 消灭整类"配置互相吞"事故（含 R2 轮"配置入口绕过模型规则"同根问题），且无破坏性——显式覆盖语义不变，只是不再丢弃未提及的字段规则。探针 `/tmp/f02_probe` 已证实旧实现会吞噬模型自带规则。
- **探针**：模型 `id←uid` + 外部 `require(\.name)` 两条同时生效；二次 forType 叠加生效。

### D3-3 修复 F-03：裸 Int 键合并确定性（排除字典数据键误报）

- **纠偏说明**：原设计 D3-3 试图通过 `JSONSerialization` 重读 Data 绕开 Foundation 对数据键的策略改写。经官方 Foundation 源码及实测验证，Foundation 原生**根本不会改写 `Dictionary<String, V>` 的数据键**（F-03A 为误报），故**作废任何额外的字典数据键重读设计**，避免带来严重的额外内存与反序列化开销。
- **聚焦修复 F-03B（裸 `[Int:V]` 键合并）**：
  - 与 `CodingKeyRepresentable` 路径（`YYModelDictionary.swift:29-40` 已修）拉齐：裸 Int 键保留字面量拼写参与合并判定：`"01"` 与 `"1"` 视为**冲突**，确定性胜者（`String(Int(key)) == key` 的规范拼写优先，再按 UTF-8 字节序），strict 模式可选抛 `dataCorrupted`；`"1.0"` 依旧 typeMismatch。
  - 同步修 `YYModelScalarDecoding.swift:44-46`、`YYModelNativeBridge.swift:216` 三处同病。
- **探针**：`{"m":{"01":"a","1":"b"}}` 结果稳定且与声明一致；`{"data":{"snake_case":1}}` 两入口均保持原始键名。

### D3-4 修复 F-08：lossy/fallback 优先级与可见性

- **方案**（三项，均为确定性行为修复）：
  1. **默认报告**：注册了 `lossy` 的字段在 userInfo 无 `YYModelLossReport` 时**自动创建**并挂回 context，暴露 `decoder.lastLossReport`（或 decode 结果携带）——静默丢弃通道关闭。
  2. **优先级**：lossy 分支提到 fallback 之前——声明 lossy 即逐元素跳过；fallback 仅当字段**未声明** lossy 时生效。文档化该优先级表。
  3. **取容器入 catch**：`YYModelDecoder.swift:318` 的 `nestedUnkeyedContainer` 移入 do/catch——容器获取失败视为整字段损失，按 lossy/fallback 语义处理，不再炸整个模型。
- **探针**：`[Int]` 含一个 "x" → lossy 得其余元素 + 报告记录索引；同字段同时声明 lossy+fallback 时 fallback 不吞好元素；值为对象（应为数组）时走损失记录。

### D3-5 修复 F-09：superDecoder 语义

- **选项 A（推荐）**：raw 入口**移除 `dictionary["super"]` 读取**（`:603` 改为恒 `dictionary`），保留 YYModel 扁平继承语义并文档化其与 Foundation 的差异；"super" 键劫持即消失。
- **选项 B**：对齐 Foundation（找 "super" 键，缺失即空容器）——破坏 YYModel 扁平继承消费场景，**不推荐**。
- **探针**：含业务字段 `"super"` 的模型 raw 入口正确读到该字段；类层级扁平继承用例不回归。

### D3-6 修复 F-10：多态判别符统一严格

- **方案**：判别字段统一走严格 String 解码（对象入口移除 coercion）；null/数字给出**可行动**错误（`dataCorrupted`，debugDescription 指明期望 string、实际类型、判别键名）。
- **探针**：`{"type":1}` 两入口同错同文案；`{"type":null}` 错误信息含判别键与实际 null。

### D3-7 P-05 时间戳启发式：文档化 + 显式策略（行为不变）

- **方案**：本轮**不改变** `.automatic` 启发式（避免行为变更），做三件事：①README/文档明示 `abs>1e11` 规则与 µs 场景的误判风险；②新增显式 `.microsecondsSince1970` 日期策略供业务选用；③ISO8601 导出截断到毫秒的事实写入文档。µs 自动识别作为向后兼容提案留待大版本。
- **探针**：新策略 1699999999999999 → 正确日期；`.automatic` 行为快照锁定（防隐变）。

### D3-8 P-08 宽松互转：诊断开关

- **方案**：新增 `YYJSONContext.coercionDiagnostics`（默认关）或 `YYModelLossReport` 扩展记录 coercion 事件；DEBUG 构建默认开启。行为本身不变（YYModel 传统语义），只加**可见性**。
- **探针**：开启诊断后 `{"flag":1}`→true 产生一条记录。

### D3-9 五类 NativeBridge 组合映射规范（K-01 ~ K-05，对齐主代理 E2E）

- **背景与分工边界**：主代理负责 NativeBridge 专项组合问题与 E2E runner 验收。为杜绝历史审查中"针对单一样本打补丁、引入相邻样本回归"的问题，四份文档将五类组合缺陷正式命名为 K-01 ~ K-05，明确对应关系与验收界限：
  1. **K-01 物理祖先路径**（`renamed-parent`, `snake-parent`）：确保祖先键别名转换正确传递至物理字典查询。基线已通过原样本。
  2. **K-02 Set 正确值去重**（`set-distinct`, `set-single`, `set-float-distinct`）：Set 去重必须发生在数值纠偏与类型适配之后。扩展场景中 Float 在 Hook 路径下二次舍入导致碰撞已暴露（count=1 vs count=2），最终两态验收已通过。
  3. **K-03 模型 codingPath**（`model-array-path`, `model-optional-path`, `dictionary-model-path`）：确保嵌套结构中模型解码持有的 codingPath 完整包含物理前缀。基线已通过原样本。
  4. **K-04 泛型递归/容器嵌套**（`optional-nested-array`, `int-dictionary`, `unkeyed-nested-cursor`）：解决 `[[Double]]?` 及 unkeyed 容器嵌套游标推进中的数值保留丢失。基线及扩展场景中已复现丢位，bridge-green 回执已提供完整递归恢复方案。
  5. **K-05 结构化 keyMap**（`path-collision`）：物理路径以 CodingKey 的键名/数组下标组成 Hashable 结构，避免字符串拼接中的 `/`、`#` 分隔符与真实键名发生碰撞。`int-dictionary` 属于 K-04 泛型递归。
- **验收界限标注**：
  - **已修复原样本**：K-01（全部）、K-02（标量）、K-03（全部）、K-04（原样本）、K-05（路径别名）；
  - **扩展最终通过**：K-02的 `set-float-distinct`、K-04的 `unkeyed-nested-cursor` / `int-dictionary`；K-05分隔符碰撞与新增hook祖先碰撞均通过。

---

## 4. R-1 统一字段解析器（治 A-01；覆盖 F-04/F-05/F-06/F-07 残余）

### 目标

把「物理节点定位 + 存在性判定 + null 语义 + 默认/回退物化」收敛为**一个内部组件**，五条管线中 A/B/C/D 全部复用（E 保持纯 Foundation，作为对照基线而非收敛目标）。

### 设计

1. **新内部类型 `YYFieldResolver`**（文件可并入 `YYModelDecoder.swift` 或新文件）：
   ```
   职责：逻辑键 → 物理节点游标（携带：物理路径、序列化序/键序信息、来源 Data 预解析树引用）
   接口（草案）：
     resolve(logicalKey, in: node) -> FieldLocation?     // 唯一的物理定位入口
     isPresent(logicalKey) -> Bool                        // 唯一的存在性判定（含 fallback/typedDefault）
     logicalNull(logicalKey) -> Bool                       // 唯一的 null 语义判定
     materialize(logicalKey, as: Type) -> Decoder          // 唯一的默认值/回退物化
   ```
2. **消费方改造**：`YYModelDecoder` 的 `contains`/`decodeNil`/`decode`/`decodeIfPresent`/`superDecoder(forKey:)`/`nestedContainer`/`field()`（F-04、F-11b）全部改为调用 resolver——判定矛盾类缺陷（F-04）从结构上消灭。
3. **错误传播**（F-05）：`resolve` 内区分「形状无效」（中间层标量/数组 → 返回 nil）与「策略抛错」（custom 回调 throw → **rethrow**），消灭 `try?` 一把抓；路径首个组件在 JSON 中存在但解析失败时，向 loss report 记一条诊断。
4. **hook 快照**（F-06）：pipeline A/D 解码时由 resolver 顺带产出 `keyMap`（物理→逻辑，按序列化序）；`YYModelJSONInput.snapshot` 改为**按 keyMap 反查**，不再自行 `decodingKey` 重推导 + 哈希序 `first(where:)`。
5. **Presence/null 下沉**（F-07）：null/缺失对 `YYModelPresence` 的解释从 keyed 容器下沉到 `YYModelDecode.value` 单点（`:147-150` 分支识别 Presence 类型）——数组元素、字典值、单值容器全部获得三态语义；lossy 不再把 null 记为损失。
6. **蛇形副本合并**：`yy_bridgeSnakeCase` 删除，`decodingKey` 成为唯一副本（已核验与 Foundation 逐字一致）。
7. **过渡开关**：`enum YYModelInternals { static var unifiedFieldResolution = false }`——默认 false 走旧路径，Phase 3 验收通过后置 true，观察一个版本再删除旧路径。

### 风险与兼容

- 改动集中于 `YYModelDecoder/YYJSONDecoder/YYModelJSONValue/YYModelNativeBridge` 四文件内部，公开 API 不变。
- 主要回归风险是既有 93 测试 + ObjC 49 契约 + 三 demo——全部纳入 Phase 3 门禁（G0/G4）。
- 性能：resolver 是纯查表重构，预期持平；门禁 G4 兜底。

---

## 5. R-2 单一数值表示贯穿（治 A-02；覆盖 P-03/P-04/P-06）

### 目标与最新实测证据

`YYModelJSONValue` 树成为**唯一**的内部数值中转：现代Foundation普通Data入口保留原生快路径；需规则/hook/raw时使用规范节点，任何出口（编码/导出/hook/桥）直接消费树，不再出现「编码成 JSON 文本 → JSONSerialization 重解析成 NSNumber」的往返。标量数学与 bridge 恢复统一读树节点；公开 NSNumber 交互边界保留不可变元数据，避免跨调用使用 hook 返回对象时丢失精度。

- **实测证据更新**：
  - 主代理公开 consumer（`/tmp/yymodel-remediation-numeric-baseline-20261005/NumericE2E.json`）实测证实，P-03（`decimal-object-export`, `decimal-encoder-object`）与 P-04（`bridge-decimal-hook-false/true`）在当前环境**全部通过**（超精度 Decimal 保持保真），本机未直接复现塌缩；但保留 R-2 作为架构清理以消除旧环境潜在风险。
  - P-06 在 `NumericE2E.json` 中，Hook 路径下 3 项 Float 探针**明确失败**（`1.0000000596046448` 得 1065353216 而非 1065353217；负数得 3212836864 而非 3212836865，差 1 ULP），确证 Float 二次舍入导致真实精度损失，R-2 必须优先保障 Float 字面量直解析。

### 设计

1. **导出直出树**（P-03）：`YYModelEncoder` 增加值树输出模式——`yy_encode()`/`yy_modelToJSONObject()`/多态导出从「`native.encode` → Data → JSONSerialization」改为「`YYModelEncoder` 树 → `.raw`（NSDecimalNumber 保留 Decimal）」。Data 输出 = `tree.encode(to:)`；字典输出 = `tree.raw`。删除 5 处 JSONSerialization 往返（`YYModelEncoder.swift:19,71`、`YYModelCodable.swift:80`、`YYModelPolymorphic.swift:17,47`）。
2. **桥消费树**（P-04）：`YYModelNativeBridge.swift:46` 的 `JSONSerialization.data(withJSONObject: raw.value)` 改为 `try raw.encode()`（YYModelJSONValue 自身可编码为精确 JSON 文本）。
3. **Float 直解析**（P-06）：树中保留字面量文本（`decimalDouble` 已有 Decimal 半边），`Float` 消费优先 `Float(literalText)`，失败再走 Double 窄化，修复 Hook 路径下的 1 ULP 失败。
4. **旁路收敛与兼容修订**：全部内部恢复/数学读取统一树；NSNumber 投影与重新摄入经单一边界封装，挂载不可变规范标量节点。`BoundaryLifetimeE2E` 已证明：删除所有挂载会使上一调用 hook 捕获的 NSNumber 在下一调用解码中差 1 ULP，违反 G6；因此撤销“全部删除挂载”的原处方。保留的挂载只服务公开对象边界，不是第二套数值运算实现。泛型递归已替代 `[Double]?` 白名单。
5. **性能红利**：删两次序列化往返 + 精确整数链中「Decimal→NSDecimalNumber→舍入→字符串→解析」可在树内短路为「树节点 → 目标类型」，向 ≤3.00× 目标推进（不承诺本轮达标）。

### 风险与兼容

- 树的 `.raw` 与 JSONSerialization 产物在**键序**上可能不同；对象输出的键顺序不是 API 契约，比较 JSON 内容。D3-1 定义的是冲突胜者，不是普通对象迭代序。
- hook 消费方依赖 NSNumber 具体类时需要迁移提示；`as? NSNumber` 仍成立。Float 原标量种类、负零、公开对象跨调用生命周期以及 Foundation 策略回调路径均须有独立 E2E 对照，不能只验证最终 Float 转换位相等。

---

## 6. R-3 旧系统能力探测与路由（治 P-01）

### 目标

部署下限 iOS 11/macOS 10.13 不变的前提下，让旧系统上整数解码恢复精确，且新系统零损失。

### 设计

1. **能力探测（一次，进程内缓存）**：启动后首次整数解码前，用独立 JSONDecoder 解码 `Data("9007199254740993")` 为 `Decimal`：
   - 等于 9007199254740993 → 新 Foundation（精确路径，现状保持）；
   - 等于 9007199254740992 → 旧 Foundation（降级路径）。
   探测覆盖 2^53+1 与 UInt64.max 的 Decimal 解码，结果缓存静态变量；默认不打印调用信息。
2. **旧系统路由**：降级路径下，`YYJSONDecoder.decode(from: Data)` 对**顶层载荷**先经 JSONSerialization 预解析（对象、数组及片段）（NSJSONSerialization 对整数 token 产 int64/uint64 NSNumber，**精确**），再走既有 raw 管线 B（其 NSNumber 读取链 `int64Value/uint64Value + I(exactly:)` 已核验精确）。即：旧系统上 A 管线自动降级为 B 管线实现。
3. **已知残留（须评审决策）**：旧系统上**浮点拼写的整数 token**（`9007199254740993.0`）经 JSONSerialization 也是 Double，无法精确——三个选项：
   - A（推荐）：接受并文档化（"旧系统上超过 2^53 的浮点形式整数不保证精确，请服务端输出整数字面量"）；
   - B：旧系统路由引入自研 JSON 词法器（成本高，性能风险）；
   - C：抬高部署下限到 iOS 16+（产品决策，README 声明的 iOS 11 支持作废）。
4. **hook 快照**：探测为降级时，`YYModelJSONValue.init(from:)` 的 Decimal 分类（`:108-136`）同步使用已选路由的数值来源；现代系统保持 Foundation 原容器，避免额外解析。公开 `.numberParsingStrategy` 可选择 `.automatic` / `.foundation` / `.integerTokens` 来验证或回退该分支；`.native` 保持 Foundation 路由。

### 风险与兼容

- raw 管线自身缺陷（F-01/F-03 等）必须在 Phase 2 **之前或同阶段**完成确定化——这是实施顺序上 Phase 2 先于 Phase 4 的原因。
- JSONSerialization 预解析有一次性成本；仅旧系统承担，新系统零开销。性能门禁 G4 在旧 OS 模拟器上以相对值评估。

---

## 7. 设计与缺陷覆盖核对表

| 缺陷 | 修复设计 | 实施阶段 | 状态说明 |
|---|---|---|---|
| P-01 | R-3 | Phase 4 | 旧系统环境探测与路由（当前环境不伪造验收） |
| P-02 | 保持现状（撤销 D2-1） | Phase 1 | 误报排除；原实现向零截断正确；补回归锁定测试 |
| P-03 | R-2 | Phase 4 | 统一数值树直出，消灭 JSONSerialization 往返 |
| P-04 | R-2 | Phase 4 | 桥消费数值树编码 |
| P-05 | D3-7 | Phase 2 | 时间戳启发式文档化 + `.microsecondsSince1970` |
| P-06 | R-2 | Phase 4 | Float 文本字面量直解析（修复 Hook 路径 1 ULP 失败） |
| P-07 | 关闭（撤销 D2-2） | Phase 1 | 误报排除；幽灵代码不存在 |
| P-08 | D3-8 | Phase 2 | 宽松互转诊断日志开关 |
| F-01 | D3-1 | Phase 2 | raw 管线字典键确定性胜者排序 |
| F-02 | D3-2 | Phase 2 | 外部规则以模型配置为基底叠加合成 |
| F-03 | D3-3（排除A，专注B） | Phase 2 | 裸 Int 键字面量冲突判定与确定性合并 |
| F-04 | R-1 | Phase 3 | 统一字段解析器存在性与容器物化 |
| F-05 | R-1 | Phase 3 | 错误分类透传，消灭 `try?` 吞噬 |
| F-06 | R-1 | Phase 3 | Hook 快照按 keyMap 反查 |
| F-07 | R-1 | Phase 3 | Presence 三态判定下沉顶层标量/集合 |
| F-08 | D3-4 | Phase 2 | lossy 优先于 fallback + 容器获取入 catch |
| F-09 | D3-5 | Phase 2 | 移除 `"super"` 键特判，保留扁平继承 |
| F-10 | D3-6 | Phase 2 | 统一严格 String 判别符 |
| F-11 a–f | D2-3 | Phase 1 | 低危集合微调（a 为待证防御修补，c/e 为维护性收敛，b/d/f 已复现修复） |
| K-01~05 | D3-9 / Bridge 专修 | Phase 2/3 | 对齐主代理 E2E（原样本与扩展 12 组已通过冻结源码验收） |
| A-01 | R-1 | Phase 3 | 统一字段解析器，收敛五管线 |
| A-02 | R-2 | Phase 4 | 单一数值树贯穿主干 |
| A-03 | Phase 0 | Phase 0 | 探针入库，红绿 TDD，独立验收 |
