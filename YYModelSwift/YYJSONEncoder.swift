import Foundation

/// Ordinary Encodable values with an explicit Foundation path or external YY rules.
/// Like Foundation's encoder, configure before sharing; synchronize captured hook state.
public struct YYJSONEncoder: @unchecked Sendable {
    public let mode: YYJSONMode
    public let rules: YYJSONRules
    public var outputFormatting: JSONEncoder.OutputFormatting = []
    public var dateEncodingStrategy: JSONEncoder.DateEncodingStrategy = .deferredToDate
    public var dataEncodingStrategy: JSONEncoder.DataEncodingStrategy = .base64
    public var keyEncodingStrategy: JSONEncoder.KeyEncodingStrategy = .useDefaultKeys
    public var nonConformingFloatEncodingStrategy: JSONEncoder.NonConformingFloatEncodingStrategy = .throw
    public var userInfo: [CodingUserInfoKey: YYJSONUserInfoValue] = [:]
    /// No-argument encoder/decoder share legacy date semantics. Choose the same
    /// explicit mode and rules on both sides for native or enhanced contracts.
    public init(mode: YYJSONMode = .legacy, rules: YYJSONRules = .init()) { self.mode = mode; self.rules = rules }
    private func foundationEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = outputFormatting; encoder.dateEncodingStrategy = dateEncodingStrategy
        encoder.dataEncodingStrategy = dataEncodingStrategy; encoder.keyEncodingStrategy = keyEncodingStrategy
        encoder.nonConformingFloatEncodingStrategy = nonConformingFloatEncodingStrategy; encoder.userInfo = userInfo
        return encoder
    }
    public func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = foundationEncoder()
        if mode == .native {
            guard rules.isEmpty else { throw YYJSONRulesError.rule(.rulesRequireCompatibleMode, T.self, "YY rules require compatible mode") }
            return try encoder.encode(value)
        }
        let context = YYJSONContext(mode: mode, rules: rules, encoder: foundationEncoder())
        encoder.userInfo[YYJSONContext.key] = context
        return try encoder.encode(YYModelEncodingBox(value: value, date: context.defaults.date, skipHook: false))
    }
    func encodeTree<T: Encodable>(_ value: T) throws -> YYModelJSONValue {
        let treeEncoder = YYModelTreeEncoder(
            options: YYModelTreeOptions(
                dateEncodingStrategy: dateEncodingStrategy,
                dataEncodingStrategy: dataEncodingStrategy,
                keyEncodingStrategy: keyEncodingStrategy,
                nonConformingFloatEncodingStrategy: nonConformingFloatEncodingStrategy
            ),
            userInfo: userInfo
        )
        if mode == .native {
            guard rules.isEmpty else { throw YYJSONRulesError.rule(.rulesRequireCompatibleMode, T.self, "YY rules require compatible mode") }
            try YYModelTreeBoxer.encode(value, into: treeEncoder.box, at: [], options: treeEncoder.options, userInfo: treeEncoder.userInfo)
            guard treeEncoder.box.hasValue else {
                throw EncodingError.invalidValue(value, .init(codingPath: [], debugDescription: "Top-level value did not encode any values"))
            }
            return treeEncoder.value
        }
        let context = YYJSONContext(mode: mode, rules: rules, encoder: foundationEncoder())
        treeEncoder.userInfo[YYJSONContext.key] = context
        try YYModelEncodingBox(value: value, date: context.defaults.date, skipHook: false).encode(to: treeEncoder)
        guard treeEncoder.box.hasValue else {
            throw EncodingError.invalidValue(value, .init(codingPath: [], debugDescription: "Top-level value did not encode any values"))
        }
        return treeEncoder.value
    }
    public func encodeJSONObject<T: Encodable>(_ value: T) throws -> Any {
        try encodeTree(value).raw
    }
    public func encodeString<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try encode(value), as: UTF8.self)
    }
}
