import Foundation

struct YYModelDecodingBox<T: Decodable>: Decodable {
    let value: T
    init(from decoder: Decoder) throws { value = try YYModelDecode.value(T.self, from: decoder, date: .automatic) }
}

// Native scalar collections have no user model hooks; a failed attempt is safe to retry by field.
protocol YYModelNativeCollection {
    static var nativeCompatible: Bool { get }
}
extension Optional: YYModelNativeCollection {
    static var nativeCompatible: Bool { YYModelDecode.isNativeValue(Wrapped.self) }
}
extension Array: YYModelNativeCollection {
    static var nativeCompatible: Bool { YYModelDecode.isNativeValue(Element.self) }
}
extension Set: YYModelNativeCollection {
    static var nativeCompatible: Bool { YYModelDecode.isNativeValue(Element.self) }
}
extension Dictionary: YYModelNativeCollection {
    static var nativeCompatible: Bool { (Key.self == String.self || Key.self == Int.self) && YYModelDecode.isNativeValue(Value.self) }
}
enum YYModelDecode {
    static func isNativeValue<T>(_ type: T.Type) -> Bool {
        if type == Date.self { return false }
        return YYJSONValueDecoder.isLeaf(type) || (type as? YYModelNativeCollection.Type)?.nativeCompatible == true
    }
    static func validateScalar<T>(_ result: T, path: [CodingKey]) throws -> T {
        if T.self == Double.self, !(result as! Double).isFinite { throw DecodingError.dataCorrupted(.init(codingPath: path, debugDescription: "Non-finite Double")) }
        if T.self == Float.self, !(result as! Float).isFinite { throw DecodingError.dataCorrupted(.init(codingPath: path, debugDescription: "Non-finite Float")) }
        return result
    }
    static func value<T: Decodable>(_ type: T.Type, from decoder: Decoder, date: YYModelDateStrategy) throws -> T {
        if (type as? YYModelNativeCollection.Type)?.nativeCompatible == true,
           let result = try? decoder.singleValueContainer().decode(type) { return result }
        if let model = type as? any YYModelCodable.Type {
            guard let value = try model._yyDecode(from: decoder) as? T else { throw YYModelFailure.invalidObject("Unexpected model type") }
            return value
        }
        if type == Date.self {
            let raw = try (decoder as? _YYDecoder)?.value ?? YYModelJSONValue(from: decoder).raw
            guard let result = YYModelDates.shared.date(raw, strategy: date) as? T else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid date"))
            }
            return result
        }
        if YYJSONValueDecoder.isLeaf(type) {
            let container = try decoder.singleValueContainer()
            do {
                let result = try container.decode(type)
                return try validateScalar(result, path: decoder.codingPath)
            } catch {
                let raw = try (decoder as? _YYDecoder)?.value ?? YYModelJSONValue(from: decoder).raw
                return try YYJSONValueDecoder.decode(type, from: raw, codingPath: decoder.codingPath)
            }
        }
        return try T(from: YYModelDecoder(base: decoder, policy: .init(date: date)))
    }
}

extension YYModelCodable {
    static func _yyDecode(from decoder: Decoder) throws -> Self {
        let schema = YYModelSchemaCache.shared.schema(Self.self)
        let policy = try schema.policy()
        // A model is always a JSON object, including a polymorphic variant.
        _ = try decoder.container(keyedBy: YYModelCodingKey.self)
        let config = schema.configuration
        var input: [String: Any]?
        var source = decoder
        if config.willTransform != nil || config.didTransform != nil {
            guard let dictionary = try YYModelJSONInput.object(from: decoder) as? [String: Any] else { throw YYModelFailure.invalidObject("Expected model object") }
            input = dictionary
            if let will = config.willTransform {
                guard let transformed = try will(dictionary) else { throw YYModelFailure.invalidObject("willTransform rejected model") }
                input = transformed
                source = _YYDecoder(value: transformed, codingPath: decoder.codingPath)
            }
        }
        let adapter = YYModelDecoder(base: source, policy: policy)
        try adapter.validateRequired()
        var model = try Self(from: adapter)
        if let hook = config.didTransform, let input, try !hook(&model, input) { throw YYModelFailure.invalidObject("didTransform rejected model") }
        return model
    }
}

struct YYModelDecoder: Decoder {
    let base: Decoder
    let policy: YYModelPolicy
    var codingPath: [CodingKey] { base.codingPath }
    var userInfo: [CodingUserInfoKey: Any] { base.userInfo }
    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        KeyedDecodingContainer(YYModelKeyedDecoder<Key>(base: try base.container(keyedBy: YYModelCodingKey.self), policy: policy))
    }
    func unkeyedContainer() throws -> UnkeyedDecodingContainer { YYModelUnkeyedDecoder(base: try base.unkeyedContainer(), date: policy.date) }
    func singleValueContainer() throws -> SingleValueDecodingContainer { YYModelSingleDecoder(base: base, date: policy.date) }
    func validateRequired() throws {
        let container = YYModelKeyedDecoder<YYModelCodingKey>(base: try base.container(keyedBy: YYModelCodingKey.self), policy: policy)
        for key in policy.required {
            guard let field = container.field(key), try !field.0.decodeNil(forKey: field.1) else {
                throw DecodingError.keyNotFound(YYModelCodingKey(key), .init(codingPath: codingPath, debugDescription: "Required property missing or null"))
            }
        }
    }
}

struct YYModelKeyedDecoder<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let base: KeyedDecodingContainer<YYModelCodingKey>
    let policy: YYModelPolicy
    var codingPath: [CodingKey] { base.codingPath }
    var allKeys: [Key] {
        let names = Set(base.allKeys.map(\.stringValue)).union(policy.mapper.keys).union(policy.defaults.keys)
        return names.filter { policy.allows($0) && (field($0) != nil || policy.defaults[$0] != nil) }.compactMap { Key(stringValue: $0) }
    }
    func field(_ name: String) -> (KeyedDecodingContainer<YYModelCodingKey>, YYModelCodingKey)? {
        guard policy.allows(name) else { return nil }
        if policy.mapper[name] == nil {
            let key = YYModelCodingKey(name)
            return base.contains(key) ? (base, key) : nil
        }
        for path in policy.paths(name) {
            guard let last = path.last else { continue }
            var current = base
            var valid = true
            for component in path.dropLast() {
                guard let child = try? current.nestedContainer(keyedBy: YYModelCodingKey.self, forKey: YYModelCodingKey(component)) else { valid = false; break }
                current = child
            }
            let key = YYModelCodingKey(last)
            if valid && current.contains(key) { return (current, key) }
        }
        return nil
    }
    // Missing nonoptional fields still reach decode() so synthesized Codable can zero-fill them.
    func contains(_ key: Key) -> Bool { field(key.stringValue) != nil || (policy.allows(key.stringValue) && policy.defaults[key.stringValue] != nil) }
    func decodeNil(forKey key: Key) throws -> Bool {
        if let field = field(key.stringValue) { return try field.0.decodeNil(forKey: field.1) }
        if let value = policy.defaults[key.stringValue], policy.allows(key.stringValue) { return value is NSNull }
        return true
    }
    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        if let field = field(key.stringValue) {
            if try field.0.decodeNil(forKey: field.1) {
                if let zero = YYJSONValueDecoder.zero(type) { return zero }
                throw DecodingError.valueNotFound(type, .init(codingPath: codingPath + [key], debugDescription: "Null property"))
            }
            if YYModelDecode.isNativeValue(type), let result = try? field.0.decode(type, forKey: field.1) {
                return try YYModelDecode.validateScalar(result, path: codingPath + [key])
            }
            return try YYModelDecode.value(type, from: field.0.superDecoder(forKey: field.1), date: policy.date)
        }
        if let value = policy.defaults[key.stringValue], policy.allows(key.stringValue) {
            return try YYModelDecode.value(type, from: _YYDecoder(value: value, codingPath: codingPath + [key]), date: policy.date)
        }
        if let zero = YYJSONValueDecoder.zero(type) { return zero }
        let empty: Any = String(describing: type).hasPrefix("Array<") || String(describing: type).hasPrefix("Set<") ? [Any]() : [String: Any]()
        return try YYModelDecode.value(type, from: _YYDecoder(value: empty, codingPath: codingPath + [key]), date: policy.date)
    }
    func decodeIfPresent<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        return try decode(type, forKey: key)
    }
    func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> {
        try superDecoder(forKey: key).container(keyedBy: type)
    }
    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer { try superDecoder(forKey: key).unkeyedContainer() }
    func superDecoder() throws -> Decoder { YYModelDecoder(base: try base.superDecoder(), policy: .init(date: policy.date)) }
    func superDecoder(forKey key: Key) throws -> Decoder {
        guard let field = field(key.stringValue) else { throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "Missing container")) }
        return YYModelDecoder(base: try field.0.superDecoder(forKey: field.1), policy: .init(date: policy.date))
    }
}

struct YYModelUnkeyedDecoder: UnkeyedDecodingContainer {
    var base: UnkeyedDecodingContainer
    let date: YYModelDateStrategy
    var codingPath: [CodingKey] { base.codingPath }
    var count: Int? { base.count }
    var isAtEnd: Bool { base.isAtEnd }
    var currentIndex: Int { base.currentIndex }
    mutating func decodeNil() throws -> Bool { try base.decodeNil() }
    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
        // Commit the index only after success, allowing a custom Codable to try another type.
        var attempt = base
        if YYModelDecode.isNativeValue(type), let result = try? attempt.decode(type) {
            let value = try YYModelDecode.validateScalar(result, path: codingPath + [YYModelCodingKey(intValue: currentIndex)])
            base = attempt
            return value
        }
        attempt = base
        let value = try YYModelDecode.value(type, from: attempt.superDecoder(), date: date)
        base = attempt
        return value
    }
    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> {
        var attempt = base
        let result = KeyedDecodingContainer(YYModelKeyedDecoder<NestedKey>(base: try attempt.nestedContainer(keyedBy: YYModelCodingKey.self), policy: .init(date: date)))
        base = attempt; return result
    }
    mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        var attempt = base
        let result = YYModelUnkeyedDecoder(base: try attempt.nestedUnkeyedContainer(), date: date)
        base = attempt; return result
    }
    mutating func superDecoder() throws -> Decoder { YYModelDecoder(base: try base.superDecoder(), policy: .init(date: date)) }
}
struct YYModelSingleDecoder: SingleValueDecodingContainer {
    let base: Decoder
    let date: YYModelDateStrategy
    var codingPath: [CodingKey] { base.codingPath }
    func decodeNil() -> Bool { (try? base.singleValueContainer().decodeNil()) ?? false }
    func decode<T: Decodable>(_ type: T.Type) throws -> T { try YYModelDecode.value(type, from: base, date: date) }
}
