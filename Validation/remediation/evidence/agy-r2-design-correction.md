# YYModel Swift 架构收敛审查纠偏与最小 R-2 路线

---

## 1. 偏差纠正与事实核对

1. **Export 链路调用次数纠偏**：
   - 审查冻结源码（[`YYModelEncoder.swift:18-21`](file:///tmp/yymodel-remediation-integrated-20261005-4/source/YYModelSwift/YYModelEncoder.swift#L18-L21)）确认：旧实现先以 `skipHook: true` 执行一次模型 `encode` 生成 Data 并转为字典，Hook 处理后，最后写回 Encoder 的是 `YYModelJSONValue(object).encode(to: encoder)`。
   - 写入的是已完成解析的 Primitive/String AST，**不会再次调用用户模型或其 Date 策略闭包**。原报告称“必然调用两次用户 Model/Date Callback”确系推论过界，前次提供的示例代码也存在 Encoder 实例混淆与 Swift 6 并发捕获问题，在此纠正。
2. **Double 截断与位模式事实纠偏**：
   - `1.000000000000000031251` 经 IEEE 754 Binary64 解析后直接等于 `1.0`（位模式 `0x3ff0000000000000`，即尾数以 408 结尾）。
   - 导致 ULP 跨越（跃迁到 `...409`，即 `1.0000000000000002`）的长 token 实为 `1.000000000000000111022302462515654042363166809082031251`（大于中点）。测试用例必须使用确切的长 token，方可断言位模式为 409。
3. **否定新造 JSONParser / Writer**：
   - 严禁另起炉灶自研 JSON 词法解析器与字符串写出器。数据流直接使用 `Foundation.JSONEncoder` 编码物化后的 `YYModelJSONValue` 树；确定性键序与格式交给官方机制处理。
   - 不承诺未经实测的“30%~50% 提升”，树容器包装本身有 Swift 结构体开销，核心收益定位于**消灭多余的序列化往返与收敛架构**。

---

## 2. 确证缺陷：`FloatMidpointE2E` 中点中转丢失与修复

在冻结代码 [`YYModelJSONValue.swift:128-136`](file:///tmp/yymodel-remediation-integrated-20261005-4/source/YYModelSwift/YYModelJSONValue.swift#L128-L136) 中存在确证逻辑漏洞：

### 缺陷根因
当遇到超过 38 位或大整数浮点 token（如 `16777217.000...000001`、$2^{24}+1$ 临界点、`9007199791611904.000...000001`）时：
1. `Decimal` 容量截断导致尾数归零，`Int64(text)` 判定成立且 $\ge 2^{53}$，值被强行归类为 `.signed(Int64)`；
2. 或因 `exact == NSDecimalNumber(value: double)` 归类为 `.number(double)`；
3. **后果**：直接抛弃了容器原生的 `try? c.decode(Float.self)`，导致后续在读取 `Float` 时退化为 `Float(Double)` 的二次舍入，在 Hook 路径下产生 1 ULP 偏差。

### 修复规则（判定顺序前移）
在解码数值进入分类前，**优先对比原生 Float 与 Double 转换值**：
```swift
let directDouble = try c.decode(Double.self)
let directFloat = try? c.decode(Float.self)

// 若直接 Float 与 Double 窄化后的 Float 位模式不一致，说明存在中点精度分歧，强制保留三态
if let directFloat, directFloat.bitPattern != Float(directDouble).bitPattern {
    self = .decimalDouble(v, directDouble, directFloat)
} else if let integer = Int64(text), integer >= (1 << 53) || integer <= -(1 << 53) {
    self = .signed(integer)
} else if let integer = UInt64(text), integer >= (1 << 53) {
    self = .unsigned(integer)
} else if exact == NSDecimalNumber(value: directDouble) {
    self = .number(directDouble)
} else {
    self = .decimalDouble(v, directDouble, directFloat)
}
```

---

## 3. 最小 R-2 落地架构

保持“只在必要处介入”原则，收敛改动面：

```
                    ┌─────────────────────────────────┐
                    │       Encodable Model           │
                    └────────────────┬────────────────┘
                                     │
             ┌───────────────────────┴───────────────────────┐
             │                                               │
   [无 Hook 常规 Data 输出]                     [JSONObject 输出 / Export Hook]
             │                                               │
             ▼                                               ▼
  Foundation 原生容器管线                         YYModelTreeEncoder (直接产出树)
  (零包装，不走 TreeEncoder)                                    │
                                                             ▼
                                                    YYModelJSONValue (AST)
                                                             │
                                             ┌───────────────┴───────────────┐
                                             ▼                               ▼
                                     [String: Any] 原生字典         Foundation.JSONEncoder
                                     (经 Boundary Registry)         (对 AST 直接编码为 Data)
```

1. **窄化 `YYModelTreeEncoder` 职责**：
   - 仅作为底层直出 `YYModelJSONValue` 的 Encoder，**不自行重写**字段映射（mapper）、黑白名单过滤等业务逻辑。
   - 直接复用现有 [`YYModelEncoder`](file:///tmp/yymodel-remediation-integrated-20261005-4/source/YYModelSwift/YYModelEncoder.swift#L122) 的策略控制层，把底层 `base: Encoder` 替换为写入 `YYModelJSONValue` 节点的容器。
2. **常规路径完全不动**：
   - 无 Hook 的普通 `Data.encode`/`decode` 继续走现有的 Foundation 容器直通路径。
3. **物理键跳过二次变换的保障机制**：
   - 当前在 [`YYModelJSONValue.swift:192`](file:///tmp/yymodel-remediation-integrated-20261005-4/source/YYModelSwift/YYModelJSONValue.swift#L192) 中：
     `case .object(let v): var c = encoder.singleValueContainer(); try c.encode(v)`
   - **原理说明**：Swift 标准库对于 `Dictionary<String, V>` 的 `encode` 实现，走的是字典私有 Key 处理路径，Foundation 的 `_JSONEncoder` 不会对已物化的字典键重复应用 `keyEncodingStrategy`。
   - **防护点**：需确保 Hook 返回的 `[String: Any]` 重新组装为 `YYModelJSONValue.object` 后，写出时绝不重新套用 `YYModelKeyedEncoder`，彻底切断 custom key callback 的二次触发。

---

## 4. Boundary Registry 强持有与指针复用防御

为退役 `objc_setAssociatedObject` 并防止指针重用导致的数值串扰，Boundary Registry 的设计规范如下：

```swift
final class YYModelBoundaryRegistry: @unchecked Sendable {
    // 必须强持有实例对象本身，防止 ARC 回收后地址被新创建的 NSNumber 复用
    private var entries: [ObjectIdentifier: (instance: NSNumber, value: YYModelJSONValue)] = [:]
    private let lock = os_unfair_lock_t.allocate(capacity: 1)

    init() { lock.initialize(to: os_unfair_lock()) }
    deinit { lock.deallocate() }

    func register(_ instance: NSNumber, canonical: YYModelJSONValue) {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        entries[ObjectIdentifier(instance)] = (instance, canonical)
    }

    func resolve(_ instance: NSNumber) -> YYModelJSONValue? {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return entries[ObjectIdentifier(instance)]?.value
    }
}
```

1. **指针复用防御**：通过同时持有 `instance: NSNumber` 强引用，保证在当次 Hook 处理期间，原对象绝对不会被析构，内存地址不可被重分配，杜绝 `ObjectIdentifier` 碰撞。
2. **并发与生命周期隔离**：Registry 实例挂载于单次解析的上下文（Invocation-scoped），同一任务内的并发子操作有轻量锁保护，任务完成后随调用栈清空而释放。

---

## 5. 生命周期行为差异与迁移风险决策

必须清晰揭示退役 Associated Object 后的契约差异，不得模糊处理：

| 行为维度 | 既有实现（Associated Object） | 新实现（Invocation Boundary Registry） |
|---|---|---|
| **元数据存储位置** | 全局 Objective-C Runtime 关联对象表 | 单次解析调用内的局部 Registry |
| **正常 Hook 移动/改名** | 支持（只要对象不变即保真） | **支持**（通过引用在 Registry 中查得三态值） |
| **跨调用/缓存字典复用** | **静默有效**：用户在 Hook 中缓存了 `[String: Any]`，数分钟后传入另一次 `yy_model(with: cachedDict)`，Associated Metadata 依然挂在 `NSDecimalNumber` 上，长 token 仍可还原位模式。 | **降级退化**：由于新 Registry 随上次调用已销毁，二次调用无法命中 Registry，该数字降级为普通 `NSDecimalNumber` 消费。对于普通数值无感，但长 token 的 Double 位模式将从 409 退化为 408。 |

### 决策建议
1. **风险定性**：这属于**明确的新增契约约束**，但符合现代 Swift 内存隔离与生命周期规范（不可假设不可见元数据随对象无限制逃逸）。
2. **迁移文档说明**：
   > “`willTransform` / `didTransform` 提供的 `[String: Any]` 仅在当前解析调用栈内维持 Float/Double 原生位模式保真。若将该字典脱离当前调用持久化或跨调用重入，其中的数值将按标准 `NSDecimalNumber` 语义消费，不再保留历史解析瞬态。”
3. **兼容性保障**：退化表现仅为无 Associated Metadata 的标准 Foundation 行为，**绝不发生崩溃或数据错乱**，属于完全可控的语义收敛。
