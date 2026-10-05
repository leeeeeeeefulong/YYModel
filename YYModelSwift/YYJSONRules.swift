import Foundation

#if compiler(>=6.0)
public typealias YYJSONUserInfoValue = any Sendable
#else
public typealias YYJSONUserInfoValue = Any
#endif

public enum YYJSONMode: Sendable {
    /// Foundation semantics, with no YY rules or model retries.
    case native
    /// Field-local conversions; absent nonoptional values require explicit defaults.
    case compatible
    /// Published 2.x zero-fill and automatic-date semantics, without whole-model retries.
    case legacy
}

/// Immutable, invocation-independent rules. Models remain ordinary Codable.
/// JSON defaults are copied on registration. Hooks must synchronize their captured mutable state.
public struct YYJSONRules: @unchecked Sendable {
    fileprivate var entries: [ObjectIdentifier: YYJSONTypeRule] = [:]
    public init() {}
    public var isEmpty: Bool { entries.isEmpty }

    /// Names refer to CodingKey.stringValue. The first existing alias wins, including null.
    public func forType<Model>(_ type: Model.Type, configure: (inout YYModelConfiguration<Model>) throws -> Void) throws -> Self {
        guard !YYJSONValueDecoder.isLeaf(type), !(type is YYModelNativeCollection.Type) else {
            throw YYJSONRulesError.rule(.ruleTargetNotModel, type, "Register rules on model types; scalar/collection policies belong to their containing model")
        }
        var configuration: YYModelConfiguration<Model>
        if let previous = entries[ObjectIdentifier(type)],
           let prevConfig = previous.typedSnapshot as? YYModelConfiguration<Model> {
            configuration = prevConfig
        } else if let baseHelper = type as? _YYModelCodableBase.Type,
                  let baseConfig = baseHelper._yy_baseConfiguration() as? YYModelConfiguration<Model> {
            configuration = baseConfig
        } else {
            configuration = YYModelConfiguration<Model>()
        }
        try configure(&configuration)
        var result = self
        var rule = try YYJSONTypeRule(configuration)
        if let previous = entries[ObjectIdentifier(type)], previous.polymorphicDecode != nil {
            try rule.validatePolymorphic(for: type)
            rule.polymorphicDecode = previous.polymorphicDecode; rule.polymorphicEncode = previous.polymorphicEncode
        }
        result.entries[ObjectIdentifier(type)] = rule
        return result
    }

    /// Dispatch an ordinary Codable enum/base value using explicit payload registrations.
    public func polymorphic<Root: Codable>(_ type: Root.Type, discriminator: YYModelKey = "type", variants: [String: YYModelVariant<Root>]) throws -> Self {
        try YYModelPolicy(mapper: ["discriminator": discriminator]).validate(for: type)
        guard !variants.isEmpty else { throw YYJSONRulesError.rule(.emptyPolymorphicVariants, type, "Empty polymorphic variants") }
        var result = self
        var rule = result.entries[ObjectIdentifier(type)] ?? YYJSONTypeRule()
        try rule.validatePolymorphic(for: type)
        rule.polymorphicDecode = { try YYModelPolymorphism.decode(from: $0, discriminator: discriminator, variants: variants) }
        rule.polymorphicEncode = { value, encoder in
            guard let root = value as? Root else { throw YYJSONRulesError.encoding(.unexpectedValue, encoder.codingPath, "Unexpected polymorphic value") }
            try YYModelPolymorphism.encode(root, to: encoder, discriminator: discriminator, variants: variants)
        }
        result.entries[ObjectIdentifier(type)] = rule
        return result
    }
}

struct YYJSONTypeRule {
    var policy = YYModelPolicy(date: .native, missing: .inherit)
    /// True until the configuration assigns `dateStrategy`; `resolved` then takes the mode's date.
    var inheritsDate = true
    var will: (([String: Any]) throws -> [String: Any]?)?
    var needsInput = false
    /// Typed transform/didTransform/validate. Decode-time rejections are `dataCorrupted` at `codingPath`.
    var finish: ((Any, [String: Any]?, [CodingKey]) throws -> Any)?
    var export: ((Any, inout [String: Any]) throws -> Bool)?
    var polymorphicDecode: ((Decoder) throws -> Any)?
    var polymorphicEncode: ((Any, Encoder) throws -> Void)?
    var typedSnapshot: Any?
    init() {}
    init<M>(_ configuration: YYModelConfiguration<M>) throws {
        // Snapshot JSON values, rather than retaining mutable NSMutableDictionary/Array defaults.
        let defaults: [String: Any]
        do { defaults = try configuration.defaultValues.mapValues { try YYModelJSONValue($0).raw } }
        catch let failure as YYModelFailure { throw YYJSONRulesError.rule(.invalidDefaultValue, M.self, failure.description) }
        var snapshot = configuration
        snapshot.defaultValues = defaults
        self.typedSnapshot = snapshot
        policy = YYModelPolicy(mapper: configuration.mapper, blacklist: Set(configuration.blacklist),
                               whitelist: configuration.whitelist.map(Set.init), required: Set(configuration.requiredProperties),
                               defaults: defaults, date: configuration.explicitDateStrategy ?? .native, missing: configuration.missingStrategy,
                               fieldDates: configuration.fieldDateStrategies,
                               lossy: Set(configuration.lossyProperties),
                               fallbacks: configuration.fallbackValues,
                               // Business values are returned verbatim (R5); they are NOT
                               // validated as JSON and never pass through YYModelJSONValue.
                               typedDefaults: configuration.typedDefaultValues)
        inheritsDate = configuration.explicitDateStrategy == nil
        try policy.validate(for: M.self)
        will = configuration.willTransform
        needsInput = configuration.didTransform != nil || will != nil
        if configuration.transform != nil || configuration.validate != nil || configuration.didTransform != nil {
            finish = { value, input, codingPath in
                guard var model = value as? M else { throw DecodingError.yy_corrupted(codingPath, "Unexpected rule type") }
                try configuration.transform?(&model)
                if let hook = configuration.didTransform, let input, try !hook(&model, input) { throw DecodingError.yy_corrupted(codingPath, "didTransform rejected model") }
                try configuration.validate?(model)
                return model
            }
        }
        if let hook = configuration.transformTo {
            export = { value, object in
                guard let model = value as? M else { throw YYJSONRulesError.encoding(.unexpectedValue, [], "Unexpected export type") }
                return try hook(model, &object)
            }
        }
    }
    func validatePolymorphic(for type: Any.Type) throws {
        guard policy.mapper.isEmpty, policy.blacklist.isEmpty, policy.whitelist == nil,
              policy.required.isEmpty, policy.defaults.isEmpty, policy.typedDefaults.isEmpty,
              policy.fallbacks.isEmpty, policy.lossy.isEmpty, policy.missing == .inherit,
              policy.fieldDates.isEmpty,
              inheritsDate || policy.date == .native || policy.date == .automatic else {
            throw YYJSONRulesError.rule(.polymorphicRootPolicy, type, "Declare polymorphic field/date policies on payload types")
        }
    }
    func resolved(defaults: YYModelPolicy) -> YYModelPolicy {
        var result = policy
        if result.missing == .inherit { result.missing = defaults.missing }
        // P0-1: an unassigned date strategy follows the mode (or the containing field),
        // so registering a mapper never moves `.legacy` dates onto Foundation's 2001 epoch.
        if inheritsDate { result.date = defaults.date }
        return result
    }
}

/// One context per call. It carries immutable external rules and lazily snapshots optional model rules.
/// No model probing, process-wide schema cache, or speculative custom initialization.
final class YYJSONContext: @unchecked Sendable {
    static let key = CodingUserInfoKey(rawValue: "YYModelSwift.Context")!
    private static let encodingPrefixKey = CodingUserInfoKey(rawValue: "YYModelSwift.EncodingPrefix")!
    let rules: YYJSONRules
    let defaults: YYModelPolicy
    let nativeDecoder: JSONDecoder
    let nativeEncoder: JSONEncoder
    private var optionalRules: [ObjectIdentifier: YYJSONTypeRule] = [:]
    private let lock = NSLock()
    init(mode: YYJSONMode, rules: YYJSONRules = .init(), decoder: JSONDecoder = JSONDecoder(), encoder: JSONEncoder = JSONEncoder()) {
        self.rules = rules; nativeDecoder = decoder; nativeEncoder = encoder
        defaults = YYModelPolicy(date: mode == .legacy ? .automatic : .native, missing: mode == .legacy ? .zeroFill : .strict)
    }
    static func from(_ decoder: Decoder) -> YYJSONContext { decoder.userInfo[key] as? YYJSONContext ?? YYJSONContext(mode: .legacy) }
    static func from(_ encoder: Encoder) -> YYJSONContext { encoder.userInfo[key] as? YYJSONContext ?? YYJSONContext(mode: .legacy) }
    func rule<T>(_ type: T.Type) throws -> YYJSONTypeRule? {
        let id = ObjectIdentifier(type)
        if let rule = rules.entries[id] { return rule }
        lock.lock(); let cached = optionalRules[id]; lock.unlock()
        if let rule = cached { return rule }
        if let model = type as? any YYModelCodable.Type {
            let rule = try model._yyRule()
            lock.lock(); optionalRules[id] = rule; lock.unlock()
            return rule
        }
        return nil
    }
    func rawDecoder(_ value: Any, path: [CodingKey], userInfo: [CodingUserInfoKey: Any]) -> _YYDecoder {
        let decoder = _YYDecoder(value: value, codingPath: path)
        decoder.userInfo = userInfo; decoder.userInfo[Self.key] = self
        return decoder
    }
    func exportEncoder(at source: Encoder) -> JSONEncoder {
        let encoder = JSONEncoder()
        let prefix = (source is YYModelPrefixEncoder || source is YYModelTreeEncoder) ? source.codingPath : (source.userInfo[Self.encodingPrefixKey] as? [CodingKey] ?? []) + source.codingPath
        encoder.outputFormatting = nativeEncoder.outputFormatting; encoder.dateEncodingStrategy = nativeEncoder.dateEncodingStrategy
        encoder.dataEncodingStrategy = nativeEncoder.dataEncodingStrategy; encoder.keyEncodingStrategy = nativeEncoder.keyEncodingStrategy
        encoder.nonConformingFloatEncodingStrategy = nativeEncoder.nonConformingFloatEncodingStrategy
        encoder.userInfo = nativeEncoder.userInfo; encoder.userInfo[Self.key] = self
        encoder.userInfo[Self.encodingPrefixKey] = prefix
        if case .custom(let transform) = nativeEncoder.keyEncodingStrategy {
            encoder.keyEncodingStrategy = .custom { transform(prefix + $0) }
        }
        if case .custom(let transform) = nativeEncoder.dateEncodingStrategy {
            encoder.dateEncodingStrategy = .custom { date, base in try transform(date, YYModelPrefixEncoder(base: base, prefix: prefix)) }
        }
        if case .custom(let transform) = nativeEncoder.dataEncodingStrategy {
            encoder.dataEncodingStrategy = .custom { data, base in try transform(data, YYModelPrefixEncoder(base: base, prefix: prefix)) }
        }
        return encoder
    }
    func exportTreeEncoder(at source: Encoder) -> YYModelTreeEncoder {
        let prefix = (source is YYModelPrefixEncoder || source is YYModelTreeEncoder) ? source.codingPath : (source.userInfo[Self.encodingPrefixKey] as? [CodingKey] ?? []) + source.codingPath
        let options = YYModelTreeOptions(
            dateEncodingStrategy: nativeEncoder.dateEncodingStrategy,
            dataEncodingStrategy: nativeEncoder.dataEncodingStrategy,
            keyEncodingStrategy: nativeEncoder.keyEncodingStrategy,
            nonConformingFloatEncodingStrategy: nativeEncoder.nonConformingFloatEncodingStrategy
        )
        var info = nativeEncoder.userInfo
        info[Self.key] = self
        info[Self.encodingPrefixKey] = prefix
        return YYModelTreeEncoder(box: YYModelTreeBox(), codingPath: prefix, options: options, userInfo: info)
    }
    func decodeNative<T: Decodable>(_ type: T.Type, data: Data, path: [CodingKey]) throws -> T {
        // Foundation's object-less API reports a scalar-local path. Restore the containing path;
        // arbitrary errors from a caller's custom strategy pass through unchanged.
        do { return try nativeDecoder.decode(type, from: data) }
        catch let error as DecodingError {
            func rebased(_ context: DecodingError.Context) -> DecodingError.Context {
                .init(codingPath: path + context.codingPath, debugDescription: context.debugDescription, underlyingError: context.underlyingError)
            }
            switch error {
            case .dataCorrupted(let c): throw DecodingError.dataCorrupted(rebased(c))
            case .typeMismatch(let t, let c): throw DecodingError.typeMismatch(t, rebased(c))
            case .valueNotFound(let t, let c): throw DecodingError.valueNotFound(t, rebased(c))
            case .keyNotFound(let k, let c): throw DecodingError.keyNotFound(k, rebased(c))
            @unknown default: throw error
            }
        }
    }
    func decodingKey(_ key: String, at path: [CodingKey]) -> String {
        switch nativeDecoder.keyDecodingStrategy {
        case .useDefaultKeys: return key
        case .custom(let transform): return transform(path + [YYModelCodingKey(key)]).stringValue
        case .convertFromSnakeCase:
            // Follow Foundation's documented handling of boundary underscores and word case.
            // https://github.com/swiftlang/swift-foundation/blob/a211bea22b6fa5b041c37592aaf50c7b3db5c354/Sources/FoundationEssentials/JSON/JSONDecoder.swift
            guard let first = key.firstIndex(where: { $0 != "_" }), let last = key.lastIndex(where: { $0 != "_" }) else { return key }
            let words = key[first...last].split(separator: "_")
            guard words.count > 1 else { return key }
            return String(key[..<first]) + words[0].lowercased() + words.dropFirst().map { $0.capitalized }.joined() + String(key[key.index(after: last)...])
        @unknown default: return key
        }
    }
}

extension YYModelCodable {
    static func _yyRule() throws -> YYJSONTypeRule {
        let rule = try YYJSONTypeRule(yy_modelConfiguration)
        if Self.self is any YYModelPolymorphic.Type { try rule.validatePolymorphic(for: Self.self) }
        return rule
    }
}
