import Foundation

// A raw scalar still uses Foundation's strict containers for a caller's custom
// strategy. Only that scalar is serialized; the owning model is never retried.
enum YYModelNativeBridge {
    static let key = CodingUserInfoKey(rawValue: "YYModelSwift.NativeStrategy")!
    static func custom<T: Decodable>(_ type: T.Type, raw: _YYDecoder, options: JSONDecoder,
                                      transform: @escaping (Decoder) throws -> Any) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = options.keyDecodingStrategy
        decoder.nonConformingFloatDecodingStrategy = options.nonConformingFloatDecodingStrategy
        decoder.dateDecodingStrategy = options.dateDecodingStrategy; decoder.dataDecodingStrategy = options.dataDecodingStrategy
        decoder.userInfo = options.userInfo
        let state = YYModelNativeStrategyState(path: raw.codingPath, transform: transform)
        decoder.userInfo[key] = state
        if case .custom(let callback) = options.keyDecodingStrategy { decoder.keyDecodingStrategy = .custom { callback(state.path + $0) } }
        if case .custom(let callback) = options.dateDecodingStrategy { decoder.dateDecodingStrategy = .custom { try callback(YYModelPrefixDecoder(base: $0, prefix: state.path)) } }
        if case .custom(let callback) = options.dataDecodingStrategy { decoder.dataDecodingStrategy = .custom { try callback(YYModelPrefixDecoder(base: $0, prefix: state.path)) } }
        let data = try JSONSerialization.data(withJSONObject: raw.value, options: [.fragmentsAllowed])
        return try decoder.decode(YYModelNativeStrategyResult<T>.self, from: data).value
    }
}
private final class YYModelNativeStrategyState: @unchecked Sendable {
    let path: [CodingKey]
    let transform: (Decoder) throws -> Any
    init(path: [CodingKey], transform: @escaping (Decoder) throws -> Any) { self.path = path; self.transform = transform }
}
private struct YYModelNativeStrategyResult<T: Decodable>: Decodable {
    let value: T
    init(from decoder: Decoder) throws {
        guard let state = decoder.userInfo[YYModelNativeBridge.key] as? YYModelNativeStrategyState,
              let result = try state.transform(YYModelPrefixDecoder(base: decoder, prefix: state.path)) as? T else {
            throw YYModelFailure.invalidObject("Unexpected native strategy result")
        }
        value = result
    }
}
private struct PrefixDecodingValue<T: Decodable>: Decodable {
    let value: T
    init(from decoder: Decoder) throws {
        let prefix = (decoder.userInfo[YYModelNativeBridge.key] as? YYModelNativeStrategyState)?.path ?? []
        if YYJSONValueDecoder.isLeaf(T.self) || (T.self as? YYModelNativeCollection.Type)?.nativeCompatible == true {
            value = try rebasing(prefix) { try decoder.singleValueContainer().decode(T.self) }
        } else if let dictionary = T.self as? PrefixDictionaryDecoding.Type,
                  let result = try dictionary.decodePrefixDictionary(from: decoder) as? T { value = result }
        else { value = try T(from: YYModelPrefixDecoder(base: decoder, prefix: prefix)) }
    }
}
private struct PrefixEncodingValue<T: Encodable>: Encodable {
    let value: T
    let prefix: [CodingKey]
    func encode(to encoder: Encoder) throws {
        if YYJSONValueDecoder.isLeaf(T.self) || (T.self as? YYModelNativeCollection.Type)?.nativeCompatible == true {
            var c = encoder.singleValueContainer(); try c.encode(value)
        } else if let dictionary = value as? PrefixDictionaryEncoding, try dictionary.encodePrefixDictionary(to: encoder, prefix: prefix) { return }
        else { try value.encode(to: YYModelPrefixEncoder(base: encoder, prefix: prefix)) }
    }
}
private protocol PrefixDictionaryDecoding { static func decodePrefixDictionary(from decoder: Decoder) throws -> Any? }
extension Dictionary: PrefixDictionaryDecoding where Key: Decodable, Value: Decodable {
    fileprivate static func decodePrefixDictionary(from decoder: Decoder) throws -> Any? {
        guard Key.self == String.self || Key.self == Int.self else { return nil }
        let values = try decoder.singleValueContainer().decode([String: PrefixDecodingValue<Value>].self)
        var result: [Key: Value] = [:]
        for (name, value) in values {
            if Key.self == String.self { result[name as! Key] = value.value }
            else if let index = Int(name) { result[index as! Key] = value.value }
            else { throw DecodingError.typeMismatch(Key.self, .init(codingPath: decoder.codingPath, debugDescription: "Invalid integer dictionary key")) }
        }
        return result
    }
}
private protocol PrefixDictionaryEncoding { func encodePrefixDictionary(to encoder: Encoder, prefix: [CodingKey]) throws -> Bool }
extension Dictionary: PrefixDictionaryEncoding where Value: Encodable {
    fileprivate func encodePrefixDictionary(to encoder: Encoder, prefix: [CodingKey]) throws -> Bool {
        guard Key.self == String.self || Key.self == Int.self else { return false }
        var values: [String: PrefixEncodingValue<Value>] = [:]
        for (key, value) in self { values[Key.self == String.self ? key as! String : String(key as! Int)] = PrefixEncodingValue(value: value, prefix: prefix) }
        var c = encoder.singleValueContainer(); try c.encode(values); return true
    }
}

private func rebasing<T>(_ prefix: [CodingKey], _ body: () throws -> T) throws -> T {
    do { return try body() }
    catch let error as DecodingError {
        func context(_ c: DecodingError.Context) -> DecodingError.Context {
            let alreadyPrefixed = c.codingPath.count >= prefix.count && zip(prefix, c.codingPath).allSatisfy { $0.stringValue == $1.stringValue && $0.intValue == $1.intValue }
            return .init(codingPath: alreadyPrefixed ? c.codingPath : prefix + c.codingPath, debugDescription: c.debugDescription, underlyingError: c.underlyingError)
        }
        switch error {
        case .dataCorrupted(let c): throw DecodingError.dataCorrupted(context(c))
        case .keyNotFound(let k, let c): throw DecodingError.keyNotFound(k, context(c))
        case .typeMismatch(let t, let c): throw DecodingError.typeMismatch(t, context(c))
        case .valueNotFound(let t, let c): throw DecodingError.valueNotFound(t, context(c))
        @unknown default: throw error
        }
    }
}
private struct YYModelPrefixDecoder: Decoder {
    let base: Decoder
    let prefix: [CodingKey]
    var codingPath: [CodingKey] { prefix + base.codingPath }
    var userInfo: [CodingUserInfoKey: Any] { base.userInfo }
    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        try rebasing(prefix) { KeyedDecodingContainer(PrefixKeyedDecoder(base: try base.container(keyedBy: type), prefix: prefix)) }
    }
    func unkeyedContainer() throws -> UnkeyedDecodingContainer { try rebasing(prefix) { PrefixUnkeyedDecoder(base: try base.unkeyedContainer(), prefix: prefix) } }
    func singleValueContainer() throws -> SingleValueDecodingContainer { try rebasing(prefix) { PrefixSingleDecoder(base: try base.singleValueContainer(), prefix: prefix) } }
}
private struct PrefixKeyedDecoder<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let base: KeyedDecodingContainer<Key>
    let prefix: [CodingKey]
    var codingPath: [CodingKey] { prefix + base.codingPath }
    var allKeys: [Key] { base.allKeys }
    func contains(_ key: Key) -> Bool { base.contains(key) }
    func decodeNil(forKey key: Key) throws -> Bool { try rebasing(prefix) { try base.decodeNil(forKey: key) } }
    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        if YYJSONValueDecoder.isLeaf(type) || (type as? YYModelNativeCollection.Type)?.nativeCompatible == true { return try rebasing(prefix) { try base.decode(type, forKey: key) } }
        return try base.decode(PrefixDecodingValue<T>.self, forKey: key).value
    }
    func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> { try rebasing(prefix) { KeyedDecodingContainer(PrefixKeyedDecoder<NestedKey>(base: try base.nestedContainer(keyedBy: type, forKey: key), prefix: prefix)) } }
    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer { try rebasing(prefix) { PrefixUnkeyedDecoder(base: try base.nestedUnkeyedContainer(forKey: key), prefix: prefix) } }
    func superDecoder() throws -> Decoder { try rebasing(prefix) { YYModelPrefixDecoder(base: try base.superDecoder(), prefix: prefix) } }
    func superDecoder(forKey key: Key) throws -> Decoder { try rebasing(prefix) { YYModelPrefixDecoder(base: try base.superDecoder(forKey: key), prefix: prefix) } }
}
private struct PrefixUnkeyedDecoder: UnkeyedDecodingContainer {
    var base: UnkeyedDecodingContainer
    let prefix: [CodingKey]
    var codingPath: [CodingKey] { prefix + base.codingPath }
    var count: Int? { base.count }; var isAtEnd: Bool { base.isAtEnd }; var currentIndex: Int { base.currentIndex }
    mutating func decodeNil() throws -> Bool { try rebasing(prefix) { try base.decodeNil() } }
    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
        if YYJSONValueDecoder.isLeaf(type) || (type as? YYModelNativeCollection.Type)?.nativeCompatible == true { return try rebasing(prefix) { try base.decode(type) } }
        return try base.decode(PrefixDecodingValue<T>.self).value
    }
    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> { try rebasing(prefix) { KeyedDecodingContainer(PrefixKeyedDecoder<NestedKey>(base: try base.nestedContainer(keyedBy: type), prefix: prefix)) } }
    mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer { try rebasing(prefix) { PrefixUnkeyedDecoder(base: try base.nestedUnkeyedContainer(), prefix: prefix) } }
    mutating func superDecoder() throws -> Decoder { try rebasing(prefix) { YYModelPrefixDecoder(base: try base.superDecoder(), prefix: prefix) } }
}
private struct PrefixSingleDecoder: SingleValueDecodingContainer {
    let base: SingleValueDecodingContainer
    let prefix: [CodingKey]
    var codingPath: [CodingKey] { prefix + base.codingPath }
    func decodeNil() -> Bool { base.decodeNil() }
    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        if YYJSONValueDecoder.isLeaf(type) || (type as? YYModelNativeCollection.Type)?.nativeCompatible == true { return try rebasing(prefix) { try base.decode(type) } }
        return try base.decode(PrefixDecodingValue<T>.self).value
    }
}

// Export hooks encode a subtree separately. Rebase both Encoder and its public
// containers so custom strategy callbacks see the original field position.
struct YYModelPrefixEncoder: Encoder {
    let base: Encoder
    let prefix: [CodingKey]
    var codingPath: [CodingKey] { prefix + base.codingPath }
    var userInfo: [CodingUserInfoKey: Any] { base.userInfo }
    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> { KeyedEncodingContainer(PrefixKeyedEncoder(base: base.container(keyedBy: type), prefix: prefix)) }
    func unkeyedContainer() -> UnkeyedEncodingContainer { PrefixUnkeyedEncoder(base: base.unkeyedContainer(), prefix: prefix) }
    func singleValueContainer() -> SingleValueEncodingContainer { PrefixSingleEncoder(base: base.singleValueContainer(), prefix: prefix) }
}
private struct PrefixKeyedEncoder<Key: CodingKey>: KeyedEncodingContainerProtocol {
    var base: KeyedEncodingContainer<Key>
    let prefix: [CodingKey]
    var codingPath: [CodingKey] { prefix + base.codingPath }
    mutating func encodeNil(forKey key: Key) throws { try base.encodeNil(forKey: key) }
    mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
        if YYJSONValueDecoder.isLeaf(T.self) || (T.self as? YYModelNativeCollection.Type)?.nativeCompatible == true { try base.encode(value, forKey: key) }
        else { try base.encode(PrefixEncodingValue(value: value, prefix: prefix), forKey: key) }
    }
    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> { KeyedEncodingContainer(PrefixKeyedEncoder<NestedKey>(base: base.nestedContainer(keyedBy: type, forKey: key), prefix: prefix)) }
    mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer { PrefixUnkeyedEncoder(base: base.nestedUnkeyedContainer(forKey: key), prefix: prefix) }
    mutating func superEncoder() -> Encoder { YYModelPrefixEncoder(base: base.superEncoder(), prefix: prefix) }
    mutating func superEncoder(forKey key: Key) -> Encoder { YYModelPrefixEncoder(base: base.superEncoder(forKey: key), prefix: prefix) }
}
private struct PrefixUnkeyedEncoder: UnkeyedEncodingContainer {
    var base: UnkeyedEncodingContainer
    let prefix: [CodingKey]
    var codingPath: [CodingKey] { prefix + base.codingPath }; var count: Int { base.count }
    mutating func encodeNil() throws { try base.encodeNil() }
    mutating func encode<T: Encodable>(_ value: T) throws {
        if YYJSONValueDecoder.isLeaf(T.self) || (T.self as? YYModelNativeCollection.Type)?.nativeCompatible == true { try base.encode(value) }
        else { try base.encode(PrefixEncodingValue(value: value, prefix: prefix)) }
    }
    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> { KeyedEncodingContainer(PrefixKeyedEncoder<NestedKey>(base: base.nestedContainer(keyedBy: type), prefix: prefix)) }
    mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer { PrefixUnkeyedEncoder(base: base.nestedUnkeyedContainer(), prefix: prefix) }
    mutating func superEncoder() -> Encoder { YYModelPrefixEncoder(base: base.superEncoder(), prefix: prefix) }
}
private struct PrefixSingleEncoder: SingleValueEncodingContainer {
    var base: SingleValueEncodingContainer
    let prefix: [CodingKey]
    var codingPath: [CodingKey] { prefix + base.codingPath }
    mutating func encodeNil() throws { try base.encodeNil() }
    mutating func encode<T: Encodable>(_ value: T) throws {
        if YYJSONValueDecoder.isLeaf(T.self) || (T.self as? YYModelNativeCollection.Type)?.nativeCompatible == true { try base.encode(value) }
        else { try base.encode(PrefixEncodingValue(value: value, prefix: prefix)) }
    }
}
