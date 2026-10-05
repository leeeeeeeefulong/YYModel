import Foundation

// ============================================================================
//  显式入口：把「选哪种模式」变成看得见的选择
//
//  背景
//  ----
//  无参构造 `YYJSONDecoder()` 保持已发布语义（`.legacy`：旧零值 + 自动日期）。
//  但 `.legacy` 同时也是**最慢**的路径 —— 实测约为官方的 3.6 倍，而 `.native`
//  约 1.0 倍。使用者写 `YYJSONDecoder()` 时并不知道自己选了哪条路。
//
//  为什么**不**直接改默认值
//  ------------------------
//  改默认值会静默改变既有调用契约（缺失字段是否补零、日期如何解释），
//  这类语义变更需要版本迁移安排与业务数据对照，不能靠单场景基准数字决定。
//  因此这里只**新增**显式入口，不动旧默认。
//
//  实测（release -O，70 字段负载）：
//    .native      ≈ 1.0× 官方   —— 标准、类型规整的数据
//    .compatible  ≈ 3.5× 官方   —— 需要字段级容错 / 外部规则
//    .legacy      ≈ 3.6× 官方   —— 2.x 迁移兼容
//  比值只用于**同机同次比较**，不代表跨设备或跨负载的绝对性能。
// ============================================================================

public extension YYJSONDecoder {

    /// **原生模式**：直接交给 Foundation，零适配开销。
    ///
    /// 适合字段类型规整、不需要别名/容错/默认值的数据。实测 ≈ 官方 JSONDecoder。
    /// 注意：本模式不接受非空 `YYJSONRules`（会明确报错，而不是静默忽略配置）。
    ///
    /// ```swift
    /// let user = try YYJSONDecoder.native().decode(User.self, from: data)
    /// ```
    static func native() -> YYJSONDecoder { YYJSONDecoder(mode: .native) }

    /// **兼容模式**：字段级容错（`"30"` → `30`）+ 外部规则（别名、默认值、required、钩子）。
    ///
    /// 接口数据不规整时用这个。代价是逐字段适配的开销 —— 不要把它当作原生性能的替代品。
    ///
    /// ```swift
    /// let rules = try YYJSONRules().forType(User.self) { $0.map(\.id, from: "uid") }
    /// let user = try YYJSONDecoder.compatible(rules: rules).decode(User.self, from: data)
    /// ```
    static func compatible(rules: YYJSONRules = .init()) -> YYJSONDecoder {
        YYJSONDecoder(mode: .compatible, rules: rules)
    }

    /// **旧语义模式**：保留已发布的 2.x 行为（缺失字段补零、空容器、自动日期）。
    ///
    /// 从 2.x 迁移、且尚未核对新语义差异时使用。新项目建议从 `.native` 或
    /// `.compatible` 起步。与无参构造等价，但把选择写在了调用处。
    static func legacy(rules: YYJSONRules = .init()) -> YYJSONDecoder {
        YYJSONDecoder(mode: .legacy, rules: rules)
    }
}

public extension YYJSONEncoder {

    /// **原生模式**：直接交给 Foundation。
    static func native() -> YYJSONEncoder { YYJSONEncoder(mode: .native) }

    /// **兼容模式**：与 `YYJSONDecoder.compatible(rules:)` 配对使用，保证往返对称。
    static func compatible(rules: YYJSONRules = .init()) -> YYJSONEncoder {
        YYJSONEncoder(mode: .compatible, rules: rules)
    }

    /// **旧语义模式**：与无参构造等价（日期导出为秒，保证与旧解码器配对）。
    static func legacy(rules: YYJSONRules = .init()) -> YYJSONEncoder {
        YYJSONEncoder(mode: .legacy, rules: rules)
    }
}
