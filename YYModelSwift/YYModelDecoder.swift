import Foundation

struct YYModelDecodingBox<T: Decodable>: Decodable {
    let value: T
    init(from decoder: Decoder) throws { value = try YYModelDecode.value(T.self, from: decoder, date: YYJSONContext.from(decoder).defaults.date) }
}

// Native scalar collections have no user model hooks; a failed attempt is safe to retry by field.
protocol YYModelNativeCollection {
    static var nativeCompatible: Bool { get }
    func validateScalars(at path: [CodingKey]) throws
}
extension Optional: YYModelNativeCollection {
    static var nativeCompatible: Bool { YYModelDecode.isNativeValue(Wrapped.self) }
    func validateScalars(at path: [CodingKey]) throws { if let value = self { _ = try YYModelDecode.validateScalar(value, path: path) } }
}
extension Array: YYModelNativeCollection {
    static var nativeCompatible: Bool { YYModelDecode.isNativeValue(Element.self) }
    func validateScalars(at path: [CodingKey]) throws {
        for (index, value) in enumerated() { _ = try YYModelDecode.validateScalar(value, path: path + [YYModelCodingKey(intValue: index)]) }
    }
}
extension Set: YYModelNativeCollection {
    static var nativeCompatible: Bool { YYModelDecode.isNativeValue(Element.self) }
    func validateScalars(at path: [CodingKey]) throws {
        for value in self { _ = try YYModelDecode.validateScalar(value, path: path) }
    }
}
extension Dictionary: YYModelNativeCollection {
    static var nativeCompatible: Bool { (Key.self == String.self || Key.self == Int.self) && YYModelDecode.isNativeValue(Value.self) }
    func validateScalars(at path: [CodingKey]) throws {
        for (key, value) in self { _ = try YYModelDecode.validateScalar(value, path: path + [YYModelCodingKey(String(describing: key))]) }
    }
}
enum YYModelDecode {
    static func isInteger<T>(_ type: T.Type) -> Bool {
        type == Int.self || type == Int8.self || type == Int16.self || type == Int32.self || type == Int64.self ||
        type == UInt.self || type == UInt8.self || type == UInt16.self || type == UInt32.self || type == UInt64.self
    }
    static func isNativeValue<T>(_ type: T.Type) -> Bool {
        if type == Date.self || type == Data.self || isInteger(type) { return false }
        return YYJSONValueDecoder.isLeaf(type) || (type as? YYModelNativeCollection.Type)?.nativeCompatible == true
    }
    static func validateScalar<T>(_ result: T, path: [CodingKey]) throws -> T {
        if T.self == Double.self, !(result as! Double).isFinite { throw DecodingError.dataCorrupted(.init(codingPath: path, debugDescription: "Non-finite Double")) }
        if T.self == Float.self, !(result as! Float).isFinite { throw DecodingError.dataCorrupted(.init(codingPath: path, debugDescription: "Non-finite Float")) }
        if T.self == CGFloat.self, !(result as! CGFloat).isFinite { throw DecodingError.dataCorrupted(.init(codingPath: path, debugDescription: "Non-finite CGFloat")) }
        if T.self == Decimal.self, (result as! Decimal).isNaN { throw DecodingError.dataCorrupted(.init(codingPath: path, debugDescription: "Non-finite Decimal")) }
        if let collection = result as? YYModelNativeCollection { try collection.validateScalars(at: path) }
        return result
    }
    // This path has no model policy/hooks. Integer tokens still pass through Decimal;
    // accepting a small native integer can silently round a long fractional token up.
    static func scalar<T: Decodable>(_ type: T.Type, from decoder: Decoder) throws -> T {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            if let optional = type as? ExpressibleByNilLiteral.Type { return optional.init(nilLiteral: ()) as! T }
            if YYJSONContext.from(decoder).defaults.missing == .zeroFill, let zero = YYJSONValueDecoder.zero(type) { return zero }
            throw DecodingError.valueNotFound(type, .init(codingPath: decoder.codingPath, debugDescription: "Null scalar"))
        }
        if !(decoder is _YYDecoder), let collection = type as? YYModelScalarCollection.Type, collection.scalarCompatible {
            guard let value = try collection.decodeScalars(from: decoder) as? T else { throw YYModelFailure.invalidObject("Unexpected scalar collection") }
            return value
        }
        if let raw = decoder as? _YYDecoder { return try YYJSONValueDecoder.decode(type, from: raw.value, codingPath: decoder.codingPath) }
        if isInteger(type), let decimal = try? container.decode(Decimal.self) {
            return try YYJSONValueDecoder.decode(type, from: NSDecimalNumber(decimal: decimal), codingPath: decoder.codingPath)
        }
        if !isInteger(type), let result = try? container.decode(type) { return try validateScalar(result, path: decoder.codingPath) }
        if let text = try? container.decode(String.self) { return try YYJSONValueDecoder.decode(type, from: text, codingPath: decoder.codingPath) }
        if let boolean = try? container.decode(Bool.self) { return try YYJSONValueDecoder.decode(type, from: NSNumber(value: boolean), codingPath: decoder.codingPath) }
        return try YYJSONValueDecoder.decode(type, from: YYModelJSONValue(from: decoder).raw, codingPath: decoder.codingPath)
    }
    static func value<T: Decodable>(_ type: T.Type, from input: Decoder, date: YYModelDateStrategy) throws -> T {
        let decoder = (input as? YYModelDecoder)?.base ?? input
        let context = YYJSONContext.from(input)
        var defaults = context.defaults; defaults.date = date
        let rule = try context.rule(type)
        let policy = rule?.resolved(defaults: defaults) ?? defaults
        var source = decoder
        var object: [String: Any]?
        if let rule, rule.needsInput {
            guard let dictionary = try YYModelJSONInput.object(from: decoder) as? [String: Any] else { throw YYModelFailure.invalidObject("Expected rule object") }
            object = dictionary
            if let hook = rule.will {
                guard let transformed = try hook(dictionary) else { throw YYModelFailure.invalidObject("willTransform rejected model") }
                object = transformed
                source = context.rawDecoder(transformed, path: decoder.codingPath, userInfo: decoder.userInfo)
            }
        }
        let result: T
        if let dispatch = rule?.polymorphicDecode {
            guard let value = try dispatch(source) as? T else { throw YYModelFailure.invalidObject("Unexpected polymorphic type") }
            result = value
        } else if (try? source.singleValueContainer().decodeNil()) == true {
            if let optional = type as? ExpressibleByNilLiteral.Type { result = optional.init(nilLiteral: ()) as! T }
            else if policy.missing == .zeroFill, let zero = YYJSONValueDecoder.zero(type) { result = zero }
            else { throw DecodingError.valueNotFound(type, .init(codingPath: source.codingPath, debugDescription: "Null value")) }
        } else if type == Date.self {
            if policy.date == .native {
                if let raw = source as? _YYDecoder {
                    if case .custom(let transform) = context.nativeDecoder.dateDecodingStrategy {
                        result = try YYModelNativeBridge.custom(type, raw: raw, options: context.nativeDecoder) { try transform($0) }
                    } else {
                        let data = try JSONSerialization.data(withJSONObject: raw.value, options: [.fragmentsAllowed])
                        result = try context.decodeNative(type, data: data, path: source.codingPath)
                    }
                } else { result = try source.singleValueContainer().decode(type) }
            } else {
                let raw = try (source as? _YYDecoder)?.value ?? YYModelJSONValue(from: source).raw
                guard let value = YYModelDates.shared.date(raw, strategy: policy.date) as? T else { throw DecodingError.dataCorrupted(.init(codingPath: source.codingPath, debugDescription: "Invalid date")) }
                result = value
            }
        } else if type == Data.self {
            // Foundation custom Data strategies are caller code: execute once, do not swallow its error.
            if let raw = source as? _YYDecoder {
                if case .custom(let transform) = context.nativeDecoder.dataDecodingStrategy {
                    result = try YYModelNativeBridge.custom(type, raw: raw, options: context.nativeDecoder) { try transform($0) }
                } else {
                    result = try context.decodeNative(type, data: JSONSerialization.data(withJSONObject: raw.value, options: [.fragmentsAllowed]), path: source.codingPath)
                }
            } else { result = try source.singleValueContainer().decode(type) }
        } else if YYJSONValueDecoder.isLeaf(type) {
            result = try scalar(type, from: source)
        } else if rule == nil, !(source is _YYDecoder), (type as? YYModelNativeCollection.Type)?.nativeCompatible == true,
                  let value = try? source.singleValueContainer().decode(type) {
            result = try validateScalar(value, path: source.codingPath)
        } else if rule == nil, !(source is _YYDecoder), let collection = type as? YYModelScalarCollection.Type,
                  collection.scalarCompatible {
            guard let value = try collection.decodeScalars(from: source) as? T else { throw YYModelFailure.invalidObject("Unexpected scalar collection") }
            result = value
        } else if let dictionary = type as? YYModelDictionaryDecoding.Type,
                  let value = try dictionary.decodeDictionary(from: source, date: policy.date) as? T { result = value }
        else {
            let adapter = YYModelDecoder(base: source, policy: policy)
            if !policy.required.isEmpty { try adapter.validateRequired() }
            result = try T(from: adapter)
        }
        if let finish = rule?.finish {
            guard let value = try finish(result, object) as? T else { throw YYModelFailure.invalidObject("Unexpected transformed type") }
            return value
        }
        return result
    }
}

struct YYModelDecoder: Decoder {
    let base: Decoder
    let policy: YYModelPolicy
    var codingPath: [CodingKey] { base.codingPath }
    var userInfo: [CodingUserInfoKey: Any] { base.userInfo }
    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        KeyedDecodingContainer(YYModelKeyedDecoder<Key>(base: try base.container(keyedBy: YYModelCodingKey.self), policy: policy, context: YYJSONContext.from(base), userInfo: userInfo))
    }
    func unkeyedContainer() throws -> UnkeyedDecodingContainer { YYModelUnkeyedDecoder(base: try base.unkeyedContainer(), date: policy.date, context: YYJSONContext.from(base), userInfo: userInfo) }
    func singleValueContainer() throws -> SingleValueDecodingContainer { YYModelSingleDecoder(base: base, date: policy.date) }
    func validateRequired() throws {
        let container = YYModelKeyedDecoder<YYModelCodingKey>(base: try base.container(keyedBy: YYModelCodingKey.self), policy: policy, context: YYJSONContext.from(base), userInfo: userInfo)
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
    let context: YYJSONContext
    let userInfo: [CodingUserInfoKey: Any]
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
                if let optional = type as? ExpressibleByNilLiteral.Type { return optional.init(nilLiteral: ()) as! T }
                if policy.missing == .zeroFill { return try zeroFilled(type, forKey: key) }
                throw DecodingError.valueNotFound(type, .init(codingPath: codingPath + [key], debugDescription: "Null property"))
            }
            if YYJSONValueDecoder.isLeaf(type), YYModelDecode.isNativeValue(type), let result = try? field.0.decode(type, forKey: field.1) {
                return try YYModelDecode.validateScalar(result, path: codingPath + [key])
            }
            return try YYModelDecode.value(type, from: field.0.superDecoder(forKey: field.1), date: policy.fieldDates[key.stringValue] ?? policy.date)
        }
        if let value = policy.defaults[key.stringValue], policy.allows(key.stringValue) {
            return try YYModelDecode.value(type, from: context.rawDecoder(value, path: codingPath + [key], userInfo: userInfo), date: policy.fieldDates[key.stringValue] ?? policy.date)
        }
        guard policy.missing == .zeroFill else { throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "Missing property; supply an explicit default")) }
        return try zeroFilled(type, forKey: key)
    }
    private func zeroFilled<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        if let zero = YYJSONValueDecoder.zero(type) { return zero }
        let empty: Any = String(describing: type).hasPrefix("Array<") || String(describing: type).hasPrefix("Set<") ? [Any]() : [String: Any]()
        return try YYModelDecode.value(type, from: context.rawDecoder(empty, path: codingPath + [key], userInfo: userInfo), date: policy.fieldDates[key.stringValue] ?? policy.date)
    }
    func decodeIfPresent<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        return try decode(type, forKey: key)
    }
    func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> {
        try superDecoder(forKey: key).container(keyedBy: type)
    }
    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer { try superDecoder(forKey: key).unkeyedContainer() }
    func superDecoder() throws -> Decoder { YYModelDecoder(base: try base.superDecoder(), policy: YYModelPolicy(date: policy.date, missing: context.defaults.missing)) }
    func superDecoder(forKey key: Key) throws -> Decoder {
        guard let field = field(key.stringValue) else { throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "Missing container")) }
        return YYModelDecoder(base: try field.0.superDecoder(forKey: field.1), policy: YYModelPolicy(date: policy.date, missing: context.defaults.missing))
    }
}

struct YYModelUnkeyedDecoder: UnkeyedDecodingContainer {
    var base: UnkeyedDecodingContainer
    let date: YYModelDateStrategy
    let context: YYJSONContext
    let userInfo: [CodingUserInfoKey: Any]
    var codingPath: [CodingKey] { base.codingPath }
    var count: Int? { base.count }
    var isAtEnd: Bool { base.isAtEnd }
    var currentIndex: Int { base.currentIndex }
    mutating func decodeNil() throws -> Bool { try base.decodeNil() }
    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
        // Commit the index only after success, allowing a custom Codable to try another type.
        var attempt = base
        if YYJSONValueDecoder.isLeaf(type), YYModelDecode.isNativeValue(type),
           (try? attempt.decodeNil()) == false, let result = try? attempt.decode(type) {
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
        let result = KeyedDecodingContainer(YYModelKeyedDecoder<NestedKey>(base: try attempt.nestedContainer(keyedBy: YYModelCodingKey.self), policy: YYModelPolicy(date: date, missing: context.defaults.missing), context: context, userInfo: userInfo))
        base = attempt; return result
    }
    mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        var attempt = base
        let result = YYModelUnkeyedDecoder(base: try attempt.nestedUnkeyedContainer(), date: date, context: context, userInfo: userInfo)
        base = attempt; return result
    }
    mutating func superDecoder() throws -> Decoder { YYModelDecoder(base: try base.superDecoder(), policy: YYModelPolicy(date: date, missing: context.defaults.missing)) }
}
struct YYModelSingleDecoder: SingleValueDecodingContainer {
    let base: Decoder
    let date: YYModelDateStrategy
    var codingPath: [CodingKey] { base.codingPath }
    func decodeNil() -> Bool { (try? base.singleValueContainer().decodeNil()) ?? false }
    func decode<T: Decodable>(_ type: T.Type) throws -> T { try YYModelDecode.value(type, from: base, date: date) }
}
