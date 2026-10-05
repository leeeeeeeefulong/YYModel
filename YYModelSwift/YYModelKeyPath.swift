import Foundation

// ============================================================================
//  KeyPath 版配置 API
//
//  为什么要有它
//  ------------
//  原来的配置只有字符串键：
//
//      rule.mapper = ["cityID": "cityid"]     // "cityID" 拼错 → 编译通过
//                                             //             → 运行时静默不生效
//
//  Swift 的核心价值是「编译期发现问题」，字符串键把这层保护丢掉了。
//  改成 KeyPath 之后：
//
//      rule.map(\.cityID, from: "cityid")     // \.cityId 拼错 → 编译失败
//
//  设计约束
//  --------
//  · **纯增量**：字符串 API 原样保留。KeyPath 只是往同一个 mapper 里写，
//    两者可以混用；后者覆盖前者。CodingKey 与属性名不一致时仍用字符串版。
//  · **零模型侵入**：不要求模型采纳任何协议，模型不需要改一行。
//  · **失败早**：不可用的 KeyPath（嵌套路径、或推导出非标识符）返回空名，
//    由 YYModelPolicy.validate() 在**规则构造时**抛错，不会静默生成无效规则。
//
//  已知限制（重要，勿过度宣传）
//  --------------------------
//  1. 属性名推导依赖 `String(describing: keyPath)` 形如 "\Type.property" 的输出。
//     该格式多年稳定（本机 Swift 6.3.3 实测：同模块与跨模块均不含模块名，
//     泛型类型展开为 \Box<Int>.value），但 **Apple 未正式承诺**。
//  2. **它确实依赖运行时反射元数据。** Swift 标准库在生成存储属性的 KeyPath 描述时
//     会读取字段反射元数据；查不到时输出的是布局偏移（实测
//     `-Xfrontend -disable-reflection-metadata` 下得到 "<offset 16 (Int)>"）。
//     因此本文件**不能**声称"不依赖运行时反射"。
//     `propertyName` 会拒绝这类不可识别的描述，避免生成匹配不到任何 CodingKey 的规则，
//     但这属于**构造期拒绝**，不等于该用法可用。
//  3. 编译器检查的是「属性存在、Value 类型匹配」，**没有**证明该属性对应某个实际
//     CodingKey。自定义 CodingKeys（`case value = "v.dot"`）或自定义编解码仍需
//     显式字符串规则。
//  4. 本仓库的格式断言只覆盖 SDK 默认构建配置，**覆盖不到消费端的元数据裁剪**。
//  5. 若需要更稳的字段标识，方向是表达式宏（SE-0382）在编译期从 KeyPath 表达式
//     生成标识；这属于可选工具层，核心字符串规则继续独立可用。**本版本未实现。**
// ============================================================================

public extension YYModelConfiguration {

    // MARK: - 键映射

    /// 把一个属性映射到一个或多个 JSON 键（按声明顺序回退，取第一个存在的）。
    ///
    /// ```swift
    /// try rule.map(\.cityID, from: "cityid")
    /// try rule.map(\.tem, from: "tem", "temperature")
    /// ```
    mutating func map<Value>(_ keyPath: KeyPath<Model, Value>, from jsonKeys: String...) {
        // 每个参数是一个候选键（各自可按 "." 拆成路径），与数组字面量写法一致。
        // 不能用 alternatives —— 那会把整串别名当成一条多段路径。
        mapper[Self.propertyName(keyPath)] = .aliases(jsonKeys)
    }

    /// 映射到嵌套 JSON 路径。
    ///
    /// ```swift
    /// try rule.map(\.companyName, at: "company", "name")
    /// ```
    mutating func map<Value>(_ keyPath: KeyPath<Model, Value>, at path: String...) {
        mapper[Self.propertyName(keyPath)] = .alternatives(path)
    }

    /// 映射到**字面含点号**的 JSON 键（不按路径拆分）。
    ///
    /// ```swift
    /// try rule.map(\.createdAt, literalKey: "created.at")
    /// ```
    mutating func map<Value>(_ keyPath: KeyPath<Model, Value>, literalKey: String) {
        mapper[Self.propertyName(keyPath)] = .key(literalKey)
    }

    // MARK: - 默认值

    /// 类型安全的缺失默认值 —— 不需要 `[String: Any]`。
    ///
    /// 只在「键不存在」时生效；显式 `null` 不会被默认值覆盖。
    ///
    /// ```swift
    /// try rule.default(\.alarm, to: [])
    /// try rule.default(\.tem, to: 0)
    /// try rule.default(\.nickname, to: nil)              // 默认 null
    /// try rule.default(\.created, to: Date(timeIntervalSince1970: 7))  // 业务类型
    /// try rule.default(\.kind, to: Kind?.some(.unknown)) // Optional.some 同样可用
    /// ```
    ///
    /// 取值语义（R4/R5）：
    /// 1. Optional.none → `NSNull`（与字符串版 `NSNull()` 语义一致）
    /// 2. 其余值作为**业务值原样保存**：解码时直接交还调用方给定的实例，
    ///    不经 JSON 往返，也不再套用日期策略或子模型 mapper ——
    ///    `default(\.created, to: Date(...))` 无论消费端用什么日期策略都得到同一个时刻。
    /// 3. 同时尽力保留一份 JSON 快照（`defaultValues`），供 `superDecoder(forKey:)`
    ///    等 Decoder 消费入口使用；完全无法 JSON 表示的业务值只有原样通道。
    mutating func `default`<Value: Encodable>(_ keyPath: KeyPath<Model, Value>, to value: Value) {
        let name = Self.propertyName(keyPath)
        // 属性是 Optional 时，Swift 会把 nil 装成 Optional.none 传进来；
        // 直接塞进 [String: Any] 会变成「不支持的 JSON 值」。这里解包成 NSNull。
        // P2-5: nil 覆盖必须同步清除旧的 typed 业务值，否则后续配置无法清除前面值。
        if let optional = value as? _YYAnyOptional, optional._yy_isNil {
            defaultValues[name] = NSNull()
            typedDefaultValues.removeValue(forKey: name)
            return
        }
        // R4：Optional.some 解包后与普通值走同一条业务值通道，不再提前 return。
        let business = (value as? _YYAnyOptional)?._yy_unwrappedOrNull ?? value
        // R5：业务值原样保存；解码时 `typed as? T` 直接命中，零转换。
        typedDefaultValues[name] = business
        // Replacement must not leave a stale snapshot when the new value cannot be encoded.
        defaultValues.removeValue(forKey: name)
        // JSON 快照尽力而为（供 superDecoder 等 Decoder 消费入口）：
        // 直接可装箱的走精确路径，其余经 JSONEncoder 往返。
        if let direct = try? YYModelJSONValue(value).raw {
            defaultValues[name] = direct
        } else if let encoded = Self.jsonObject(value) {
            defaultValues[name] = encoded
        }
    }

    /// 把任意 `Encodable` 经 JSON 往返成 JSON 原生对象。
    private static func jsonObject<Value: Encodable>(_ value: Value) -> Any? {
        guard let data = try? JSONEncoder().encode(value),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else { return nil }
        return object
    }

    /// 注册**兜底值**：该字段在任何失败情况下都退回它，而不是让解析失败。
    ///
    /// 与 `default(_:to:)` 的区别：
    ///
    /// | | 键缺失 | 值为 null | 值存在但解不出 |
    /// |---|:---:|:---:|:---:|
    /// | `default` | ✅ 用默认值 | ❌ 按原语义（Optional→nil / 抛错） | ❌ 抛错 |
    /// | `fallback` | ✅ 用兜底值 | ✅ 用兜底值 | ✅ **用兜底值** |
    ///
    /// 「值存在但解不出」正是两个真实痛点：
    /// - **枚举未知值**：服务端新增了 `case`，老版本 App 会抛 `dataCorrupted` ——
    ///   即使属性声明为 `Optional` 也一样抛，Optional 救不了。
    /// - **无效 URL**：空字符串会抛 `dataCorrupted`（"Invalid URL string."）。
    ///
    /// ```swift
    /// try rule.fallback(\.kind, to: .unknown)     // 未知枚举值 → unknown
    /// try rule.fallback(\.site, to: nil)          // 无效 URL → nil（属性需为 Optional）
    /// ```
    ///
    /// 注意：该字段**至多尝试解码一次**。失败即返回兜底值，不会重试，
    /// 因此不存在「模型 `init(from:)` 被执行两次」的副作用风险。
    mutating func fallback<Value>(_ keyPath: KeyPath<Model, Value>, to value: Value) {
        // 与 default 同样要处理 Optional：Swift 会把 nil 装成 Optional.none 传进来，
        // 直接存进 [String: Any] 会变成「不支持的 JSON 值」。解包成 NSNull。
        if let optional = value as? _YYAnyOptional {
            fallbackValues[Self.propertyName(keyPath)] = optional._yy_unwrappedOrNull
            return
        }
        fallbackValues[Self.propertyName(keyPath)] = value
    }

    // MARK: - 校验

    /// 标记为必填。缺失或为 null 时解析失败，而不是悄悄补零。
    ///
    /// ```swift
    /// try rule.require(\.city)
    /// ```
    mutating func require<Value>(_ keyPath: KeyPath<Model, Value>) {
        requiredProperties.append(Self.propertyName(keyPath))
    }

    // MARK: - 过滤

    /// 排除若干属性，不参与解析与导出。
    ///
    /// ```swift
    /// try rule.exclude(\.internalNote, \.debugInfo)
    /// ```
    mutating func exclude(_ keyPaths: PartialKeyPath<Model>...) {
        blacklist.append(contentsOf: keyPaths.map(Self.propertyName))
    }

    /// 只保留列出的属性。
    ///
    /// ```swift
    /// try rule.only(\.city, \.tem)
    /// ```
    mutating func only(_ keyPaths: PartialKeyPath<Model>...) {
        whitelist = keyPaths.map(Self.propertyName)
    }

    // MARK: - 属性名推导

    /// 从 KeyPath 推导属性名。
    ///
    /// 返回**根类型之后的部分**：
    /// - 顶层属性 `\Model.cityID` → `"cityID"`
    /// - 嵌套 KeyPath `\Model.inner.deep` → `"inner.deep"`
    ///
    /// 嵌套情况刻意保留点号 —— Swift 属性名不可能含点号，于是
    /// `YYModelPolicy.validate()` 能明确拒绝它，而不是静默映射到错误的属性。
    /// 推导失败返回空字符串，同样会被 validate() 拒绝。
    static func propertyName(_ keyPath: PartialKeyPath<Model>) -> String {
        let description = String(describing: keyPath)
        let parts = description.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return "" }
        let name = parts[1]
        // Reject anything that is not a plain Swift identifier, returning "" so that
        // YYModelPolicy.validate() reports it at rule-construction time instead of
        // silently creating a rule that matches no real CodingKey.
        //
        // Two concrete failure modes this catches:
        //  · `\.nested.deep`        → "nested.deep": a nested key path (top-level only).
        //  · `\.value` compiled with `-Xfrontend -disable-reflection-metadata`
        //    → "<offset 16 (Int)>": the description falls back to a layout dump because
        //    the field name is not available. The SDK's own build never exercises that
        //    consumer configuration, so a format assertion in this repo cannot catch it.
        guard !name.isEmpty,
              let first = name.first, first.isLetter || first == "_",
              name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" })
        else { return "" }
        return name
    }
}

// ============================================================================
//  Optional 解包辅助
//
//  只为 `default(_:to:)` 服务：把 Optional.none 转成 NSNull，
//  把 Optional.some(v) 递归解包成 v，从而与 JSON 值层（YYModelJSONValue）对齐。
//  嵌套 Optional（Int??）同样适用。
// ============================================================================

private protocol _YYAnyOptional {
    /// 是否为 `.none`
    var _yy_isNil: Bool { get }
    /// `.none` → NSNull；`.some(v)` → v（继续解包嵌套 Optional）
    var _yy_unwrappedOrNull: Any { get }
}

extension Optional: _YYAnyOptional {
    var _yy_isNil: Bool { self == nil }
    var _yy_unwrappedOrNull: Any {
        switch self {
        case .none:
            return NSNull()
        case .some(let wrapped):
            if let nested = wrapped as? _YYAnyOptional { return nested._yy_unwrappedOrNull }
            return wrapped
        }
    }
}
