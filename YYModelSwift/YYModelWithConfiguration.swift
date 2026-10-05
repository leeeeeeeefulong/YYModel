import Foundation

// ============================================================================
//  官方外部配置通道：DecodableWithConfiguration / EncodableWithConfiguration
//
//  定位（重要，勿误解）
//  --------------------
//  这是**可选能力，不是本框架的架构缺陷**。官方机制解决的是「模型构造需要外部
//  上下文」（例如需要另一个接口的数据才能初始化），它**不**解决别名、脏数字、
//  缺失默认值 —— 那些仍然是外部规则（YYJSONRules）的主战场。
//
//  接入成本（必须明示）
//  --------------------
//  使用本入口的模型**必须**：
//    1. 采纳 `DecodableWithConfiguration`（或 `EncodableWithConfiguration`）
//    2. 手写 `init(from:configuration:)`（或 `encode(to:configuration:)`）
//  也就是说，**模型不再零侵入** —— 这是官方机制本身的代价，不是本框架强加的。
//  主入口（普通 Codable + 外部规则）完全不受影响，两者可以并存于同一工程。
//
//  可用性
//  ------
//  协议本身 iOS 15 / macOS 12 起可用；官方的顶层
//  `JSONDecoder.decode(_:from:configuration:)` 要 iOS 17 / macOS 14。
//  本实现用 `userInfo` 传递配置（与官方 `assumesTopLevelDictionary` 的实现方式
//  相同 —— 它也是把选项塞进 `userInfo`），因此**在 iOS 15 即可用**，
//  不需要等到 iOS 17。
//
//  代价：配置类型必须是 `Sendable`
//  --------------------------------
//  因为配置经 `userInfo` 传递，而 Foundation 把 `userInfo` 的值类型限制为
//  `any Sendable`（Swift 6 语言模式下是硬性错误）。官方 iOS 17+ 入口走内部通道，
//  没有这个约束 —— 这是我们用 iOS 15 兼容性换来的代价，已在签名上显式声明。
//  绝大多数配置是「若干基础类型的结构体」，天然满足 `Sendable`。
// ============================================================================

@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
private enum YYModelConfigurationKeys {
    /// 解码配置的 `userInfo` 槽位。
    static let decoding = CodingUserInfoKey(rawValue: "YYModelSwift.DecodingConfiguration")!
    /// 编码配置的 `userInfo` 槽位。
    static let encoding = CodingUserInfoKey(rawValue: "YYModelSwift.EncodingConfiguration")!
}

@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
private struct YYModelDecodingConfigurationBox<T: DecodableWithConfiguration>: Decodable {
    let wrapped: T
    init(from decoder: Decoder) throws {
        guard let configuration = decoder.userInfo[YYModelConfigurationKeys.decoding] as? T.DecodingConfiguration else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Missing DecodingConfiguration for \(T.self); use decode(_:from:configuration:)"))
        }
        // R2: route through T's own rule flow (mapper/required/will/finish) instead of
        // calling T(from:configuration:) on the raw decoder, where the context would
        // only see the BOX (which has no rules).
        wrapped = try YYModelConfigurationDecode.value(T.self, from: decoder,
                                                       date: YYJSONContext.from(decoder).defaults.date,
                                                       configuration: configuration)
    }
}

@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
private struct YYModelEncodingConfigurationBox<T: EncodableWithConfiguration>: Encodable {
    let value: T
    func encode(to encoder: Encoder) throws {
        guard let configuration = encoder.userInfo[YYModelConfigurationKeys.encoding] as? T.EncodingConfiguration else {
            throw EncodingError.invalidValue(value, .init(
                codingPath: encoder.codingPath,
                debugDescription: "Missing EncodingConfiguration for \(T.self); use encode(_:configuration:)"))
        }
        // R2: run T's export hooks (transformTo) via the same encode pipeline the
        // ordinary entry uses, then let T write through the policy-carrying adapter.
        try YYModelEncode.value(value, to: encoder,
                                date: YYJSONContext.from(encoder).defaults.date,
                                configuration: configuration)
    }
}

// MARK: - 解码

@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
public extension YYJSONDecoder {

    /// 用官方 `DecodableWithConfiguration` 协议解码，配置由调用方显式传入。
    ///
    /// ```swift
    /// struct Reading: DecodableWithConfiguration {
    ///     typealias DecodingConfiguration = UnitContext
    ///     init(from decoder: Decoder, configuration: UnitContext) throws { … }
    /// }
    /// let reading = try decoder.decode(Reading.self, from: data,
    ///                                  configuration: UnitContext(unit: "°C"))
    /// ```
    ///
    /// 模型需要采纳协议并手写 `init(from:configuration:)` —— **不再是零侵入**。
    /// 普通 Codable 模型继续用 `decode(_:from:)` + 外部规则即可。
    func decode<T: DecodableWithConfiguration>(
        _ type: T.Type,
        from data: Data,
        configuration: T.DecodingConfiguration
    ) throws -> T where T.DecodingConfiguration: Sendable {
        var decoder = self
        decoder.userInfo[YYModelConfigurationKeys.decoding] = configuration
        return try decoder.decode(YYModelDecodingConfigurationBox<T>.self, from: data).wrapped
    }

    /// 配置由类型自身通过 `DecodingConfigurationProviding` 提供，调用方无需传参。
    func decode<T: DecodableWithConfiguration & DecodingConfigurationProviding>(
        _ type: T.Type,
        from data: Data
    ) throws -> T where T.DecodingConfiguration: Sendable {
        try decode(type, from: data, configuration: T.decodingConfiguration)
    }
}

// MARK: - 编码

@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
public extension YYJSONEncoder {

    /// 用官方 `EncodableWithConfiguration` 协议编码，配置由调用方显式传入。
    func encode<T: EncodableWithConfiguration>(
        _ value: T,
        configuration: T.EncodingConfiguration
    ) throws -> Data where T.EncodingConfiguration: Sendable {
        var encoder = self
        encoder.userInfo[YYModelConfigurationKeys.encoding] = configuration
        return try encoder.encode(YYModelEncodingConfigurationBox(value: value))
    }

    /// 配置由类型自身通过 `EncodingConfigurationProviding` 提供。
    func encode<T: EncodableWithConfiguration & EncodingConfigurationProviding>(
        _ value: T
    ) throws -> Data where T.EncodingConfiguration: Sendable {
        try encode(value, configuration: T.encodingConfiguration)
    }
}
