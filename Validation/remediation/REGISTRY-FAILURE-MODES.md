# 缺陷登记册公开 API E2E 失效模式与探针契约（实现前）

> 文档依据：[DEFECT-REGISTRY-20261005](../../docs/DEFECT-REGISTRY-20261005.md) 与 [REMEDIATION-ACCEPTANCE-PLAN-20261005](../../docs/REMEDIATION-ACCEPTANCE-PLAN-20261005.md)。  
> 角色定位：独立公开 API 端到端 consumer（`Validation/remediation/RegistryE2E.swift`）的先验失效设计说明与断言规约。不修改任何生产代码，不复制内部算法，完全使用已公开且可编译 API。

---

## 1. 规约与执行协议

1. **执行入口**：`@main struct RegistryE2E`，通过 `CommandLine.arguments[1]` 接收输出 JSON 文件路径。
2. **退出码契约**：观察与记录完成即退出 `0`（Exit Code 0）。不使用 `fatalError`、不使用 force-try（`try!`）或 force-unwrap（`!`），每个测试用例独立捕获 `Error`，保证全量结果写入 JSON。
3. **判定分离**：由外部 runner 或测试流水线解析输出 JSON 中的 `passed: Bool` 进行门禁判定。
4. **输出记录格式**：
   ```json
   [
     {
       "id": "P-02",
       "scenario": "negative-decimal-truncation-data",
       "passed": true,
       "actual": "-1",
       "expected": "-1"
     }
   ]
   ```
5. **Swift 6 并发安全**：全文件在 `-swift-version 6 -strict-concurrency=complete -warnings-as-errors` 下编译无任何 warning。禁用 static mutable global 状态，所有测试用例封装于 Sendable 或局部作用域中。

---

## 2. 数值精度类失效模式（P-xx）

### P-01：大整数保真与环境范围控制
- **失效机理**：>2^53 大整数（如雪花 ID `9007199254740993`）在 iOS < 16 / macOS < 13 等旧系统 Foundation 上，`Decimal` decodable 实现经 `Double` 中转导致末位静默失真为 `9007199254740992`。
- **环境验证边界说明**：当前运行环境为现代 macOS（具备 swift-foundation 精确字面量解码能力），当前机上整数探针作为**基线控制用例**预期通过。本用例明确注明：**旧 OS 运行时无法在本机无模拟器环境中伪称验证**，其实际验证需由 CI/真机旧 OS 矩阵通过 G5 验收。

### P-02：负数小数→整数截断方向对照（处方复核）
- **争议焦点**：登记册描述指出 `copy.isSignMinus ? .up : .down` 中负数分支用了 `.up`。然而经官方 NSDecimalNumber 文档及运行时实测核验：
  - NSDecimalNumber 的 `.up` 含义为「向正无穷方向（朝大）取整」：`-1.9` 取整后结果正是 **`-1`**（向零截断）；
  - 若将其改为 `.down`（向负无穷取整），`-1.9` 会变成 **`-2`**（远离零，破坏截断契约）。
- **探针期望**：契约规定为「向零截断（toward-zero）」，因此 **`-1.9 -> -1`** 与 **`+1.9 -> 1`** 才是真正的正确期望。
- **三态全矩阵**：覆盖 Data 输入、`NSNumber(value: -1.9)`（Double）输入、`NSDecimalNumber(string: "-1.9")` 输入，正负共 6 态对比，验证向零截断的一致性与现有实现的实际行为。

### P-03：导出/Hook 链路 Decimal 往返保持
- **失效机理**：高精度 Decimal（如 `1.000000000000000031251`）在经过 `yy_modelToJSONObject()` 或 `YYModelEncoder` 的 `transformTo` hook 阶段时，需经由 `JSONSerialization` 重解析为字典。
- **探针验证**：测试 `Decimal` 字段经过模型导出字典、以及 `transformTo` 钩子入参时，是否保持原始 `NSDecimalNumber` 字面量与精度，或是否因转为 Double 发生塌缩（`1.0`）。

### P-04：Custom Date/Data 策略内 Decimal 精确度
- **失效机理**：当解码器配置了 `.custom` 的 `dataDecodingStrategy` 或 `dateDecodingStrategy` 时，native 桥接重入机制在重新序列化时若将数值转换为 Double，会导致其中的 Decimal 高精度信息丢失。
- **探针验证**：在自定义 data 解码回调中，从 decoder 单值容器或包含 Decimal 的负载中解码 `1.000000000000000031251`，验证是否精确保留。

### P-06：Float 直接文本位模式
- **失效机理**：在 raw / numericText 解码管线中，数值先按 `Double` 宽精度解析，再窄化为 `Float`（即 `Float(Double(token))`）。对于超过 9 位有效数字的 token（如 `1.0000000596046448`），直接解析 `Float(token)` 的 bitPattern 为 `1065353217`，而经 `Double` 中转窄化后为 `1065353216`，存在 1 ULP 舍入差异。
- **探针验证**：对比 raw 输入解出 Float 的 bitPattern 与直接解析期望值，捕捉该 1 ULP 偏差。

---

## 3. 字段读取与键解析类失效模式（F-xx）

### F-01：Raw 键冲突胜者确定性与精确键优先
- **失效机理**：Raw 字典管线在 `_YYDecoder.container(keyedBy:)` 中遍历字典键值对并转换键名。当输入字典同时包含转换前与转换后的同名键（例如 `["user_name": "A", "userName": "B"]`），胜者取决于 Swift Dictionary 的哈希迭代顺序，跨运行/跨进程结果不确定。
- **探针期望**：根据 D3-1 选项 A 确定性规约，精确匹配逻辑属性名的物理键（`"userName"`）必须优先于别名/蛇形转换键（`"user_name"`），期望值为 `"B"`。当前实现因哈希遍历顺序导致无法保证精确键胜出。

### F-02：外部规则与模型配置合成 / 重复注册
- **失效机理**：模型自身声明了 `static var yy_modelConfiguration`（如 `id <- uid` 映射）。当外部通过 `rules.forType(Model.self) { $0.require(\.name) }` 添加校验时，`YYJSONRules.forType` 重新构造了全新的配置对象并覆盖，导致模型原有的 `mapper` 映射**整体丢失**，读取 `{"uid": 7, "name": "foo"}` 时因 `uid` 无法映射到 `id` 而抛出 `keyNotFound`。
- **探针期望**：外部规则与模型内生配置应进行基底合成（Base composition），既保留原有键映射，又施加外部必填校验；重复注册 `forType` 应累加而非全量覆盖。

### F-03：字典数据键策略免疫与 Int 键合并冲突
- **失效机理**：
  1. `[String: Int]` 字典中的键属于**业务数据**而非结构性 CodingKeys。在启用 `convertFromSnakeCase` 时，字典键不应被自动转换为驼峰。
  2. `[Int: String]` 字典中，`"01"` 与 `"1"` 经 `Int(name)` 解析后映射到同一个整数键 `1`。在 Data 入口与 Raw 入口中，因底层容器遍历顺序不同，胜出项相反（Data 得 `"a"`，Raw 得 `"b"`）。
- **探针期望**：两入口对同义整数键必须具备一致、确定性的行为。

### F-04：Fallback / TypedDefault 容器存在性查询分裂
- **失效机理**：对于注册了 `fallback` 的字段，在输入为空 `{}` 时，`container.contains(key)` 会返回 `true`（认定逻辑存在）；但手写 `init(from:)` 调用 `superDecoder(forKey:)` 或 `nestedContainer(forKey:)` 时，低层实现只检查物理键与 `defaults`，未将 `fallbacks` 纳入存在性判定，从而抛出 `keyNotFound` 异常。
- **探针期望**：`contains` 判定为存在时，容器级子解码器查询不应抛出 `keyNotFound`，两者应保持契约自洽。

### F-05：错误路径形状被吞（吞错与静默缺失）
- **失效机理**：当模型配置了多级路径映射（如 `mapper: ["b": "a.b"]`），而实际 JSON 为 `{"a": 5}`（中间节点 `a` 是标量 Int 而非 Dictionary 时），`YYModelDecoder.field()` 使用 `try? current.nestedContainer(...)` 将容器类型不匹配（`typeMismatch`）完全吞掉，误判为「键缺失」，在 legacy 模式下静默补零 `b = 0`，在 strict 模式下报 `keyNotFound: b` 而非 `typeMismatch: a`。
- **探针期望**：遇到中间节点结构非法时，应如实报告路径形状错误（`typeMismatch`），杜绝静默零填充或误报字段缺失。

### F-06：嵌套 Hook 快照与模型解码键解析分歧
- **失效机理**：父子嵌套模型中，若子树同时存在别名与原名（如 `{"sub_item": {"val": 1}, "subItem": {"val": 2}}`），模型解码遵循序列化序（解码了 `sub_item`，`val = 1`），而 `YYModelJSONValue.object(at:context:)` 快照路径在定位子节点时无条件优先精确查找 `dictionary[key.stringValue]`，导致 hook 拿到的是 `subItem`（`val = 2`）的字典。
- **探针期望**：`didTransform`/`willTransform` 观测到的快照字典必须与模型实际解析的节点完全一致，不能发生子树错位。

### F-07：Presence 三态在数组 / 字典 / 单值容器中的 Null 拦截
- **失效机理**：
  1. `YYModelPresence<T>` 仅在 Keyed 容器顶层做了 null 拦截；在 `[YYModelPresence<String>]` 数组中，遇到 `[null]` 元素时直接抛出 `valueNotFound` 失败；
  2. 在 `[String: YYModelPresence<Int>]` 字典中，`{"a": null}` 同样抛出 `valueNotFound`；
  3. 在 `lossy` 数组中，`null` 元素被误当成数据损坏记入损失丢弃，而非解析为 `.null`。
- **探针期望**：Unkeyed 与 Dictionary 容器能正常解析 `YYModelPresence.null`，支持增量更新的清空语义。

### F-08：Lossy 与 Fallback 优先级倒置及错误容器抛错
- **失效机理**：
  1. 当属性同时配置了 `lossy(\.items)` 和 `fallback(\.items, to: [...])` 时，当前解码器在循环前优先命中 fallback 分支，一个脏元素直接导致整个数组被回退为兜底值，使 lossy 逐元素容错机制完全失效；
  2. 若字段整体类型错误（如期望数组却传入字符串 `{"items": "abc"}`），`nestedUnkeyedContainer` 在 try-catch 外执行，直接抛错导致整个模型失败，未进入 lossy 记录。
- **探针期望**：字段为数组时逐元素过滤，lossy 优先于 fallback 生效；损坏元素被记录于报告中。

### F-09：业务 "super" 键劫持
- **失效机理**：`YYJSONDecoder.superDecoder()` 采用 `dictionary["super"] ?? dictionary`。若模型含有合法业务字段名为 `super: String`（如 `{"super": "VIP", "title": "Admin"}`），当子类调用 `superDecoder()` 时，会将字符串 `"VIP"` 误当作父类容器，从而抛出 `typeMismatch: expected Dictionary<String, Any>`。
- **探针期望**：业务字段 `super` 不应干扰扁平继承或父类解码流程。

### F-10：多态判别符分歧与 Null 零填充
- **失效机理**：
  1. 多态判别符在 Data 入口遇到数字 `{"type": 1}` 时严格抛出 `typeMismatch`；但在 Raw 入口中被隐式转换为字符串 `"1"`；
  2. 当判别符为 `{"type": null}` 时，Raw 零填充机制将其填为空字符串 `""`，抛出误导性错误 `"Unknown model discriminator: "`，无法明确提示调用方判别符为 null。
- **探针期望**：多态判别符在各入口应具有一致且可诊断的错误报告。

### F-11：低危集合
- **F-11a**：整数快路径溢出/越界（如 UInt64 遇到 -1）时，抛出的错误 `codingPath` 为空，无法定位具体出错属性。
- **F-11b**：在 zeroFill / legacy 模式下，针对缺失字段调用 `decodeNil` 返回 `true`（声称是 null），而随后调用 `decode(YYModelPresence.self)` 却返回 `.absent`，两接口互相矛盾。
- **F-11c**：`YYModelEncoder.nestedContainer` 与 `superEncoder` 创建了独立的全新状态对象，其内部的键冲突或编码错误未能向上传递，导致字段静默丢失。
- **F-11f**：`KeyedDecodingContainer.allKeys` 同时包含了物理 JSON 别名键与模型属性名，动态解码遍历时会枚举出不存在的虚拟属性名。

---

## 4. 交付清单与状态跟踪

| 缺陷 ID | 探针场景名 | 当前预期状态 | 备注 |
|---|---|---|---|
| P-01 | `p01_large_integer_control` | 当前环境通过 | 注明旧 OS 范围限制 |
| P-02 | `p02_neg_decimal_trunc_data` 等 (6态) | 当前实现通过 | 核验向零截断处方 |
| P-03 | `p03_decimal_export_literal` | 当前环境验证 | 观测 JSONSerialization 行为 |
| P-04 | `p04_custom_strategy_decimal` | 当前环境验证 | 观测桥接 callback 内部 Decimal |
| P-06 | `p06_float_text_bitpattern` | **当前失败** (1 ULP 偏差) | `1065353216` vs `1065353217` |
| F-01 | `f01_raw_key_conflict_exact_first` | **当前失败** (哈希序非精确) | `"A"` vs `"B"` |
| F-02 | `f02_model_external_rule_merge` | **当前失败** (外部规则覆盖模型映射) | 抛 `keyNotFound: id` |
| F-03 | `f03_int_key_dict_data_raw_order` | **当前失败** (Data/Raw 歧义) | Data `1:"a"` vs Raw `1:"b"` |
| F-04 | `f04_fallback_superdecoder_container` | **当前失败** (contains 与 super 矛盾) | 抛 `keyNotFound: x` |
| F-05 | `f05_path_shape_error_swallowed` | **当前失败** (标量中间节点补零) | 补零 `0` 而非 `typeMismatch` |
| F-06 | `f06_hook_snapshot_subtree_divergence` | **当前失败** (Hook 子树取错节点) | Hook 读到 `val:2`，模型读到 `val:1` |
| F-07 | `f07_presence_null_unkeyed_dict` | **当前失败** (数组/字典内 null 报错) | 抛 `valueNotFound` |
| F-08 | `f08_lossy_fallback_priority_inversion` | **当前失败** (Fallback 抢先吃掉整组) | 得 `[999]` 而非 `[1, 2]` |
| F-09 | `f09_business_super_key_hijack` | **当前失败** (super 键劫持 superDecoder) | 抛 `typeMismatch` 崩溃 |
| F-10 | `f10_polymorphic_null_discriminator` | **当前失败** (null 变成空字符串) | `"Unknown model discriminator: "` |
| F-11b | `f11b_zerofill_decodenil_presence_conflict` | **当前失败** (decodeNil 与 decode 矛盾) | `decodeNil: true` vs `.absent` |
| F-11f | `f11f_allkeys_leaking_physical_aliases` | **当前失败** (allKeys 泄漏别名) | `allKeys` 含 `alias_name` |
