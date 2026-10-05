import Foundation

// A raw scalar still uses Foundation's strict containers for a caller's custom
// strategy. Only that scalar is serialized; the owning model is never retried.
enum YYModelNativeBridge {
    static let key = CodingUserInfoKey(rawValue: "YYModelSwift.NativeStrategy")!
    static func custom<T: Decodable>(_ type: T.Type, raw: _YYDecoder, options: JSONDecoder,
                                      transform: @escaping (Decoder) throws -> Any) throws -> T {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = options.nonConformingFloatDecodingStrategy
        decoder.dateDecodingStrategy = options.dateDecodingStrategy; decoder.dataDecodingStrategy = options.dataDecodingStrategy
        decoder.userInfo = options.userInfo
        let state = YYModelNativeStrategyState(path: raw.codingPath, rawValue: raw.value, options: options, transform: transform)
        decoder.userInfo[key] = state
        switch options.keyDecodingStrategy {
        case .useDefaultKeys:
            decoder.keyDecodingStrategy = .useDefaultKeys
        case .convertFromSnakeCase:
            decoder.keyDecodingStrategy = .custom { bridgePath in
                let physical = bridgePath.last!.stringValue
                let logical = yy_bridgeSnakeCase(physical)
                let physicalParent = yy_bridgeResolvePhysicalParent(Array(bridgePath.dropLast()), state: state)
                if state.keyMap[physicalParent]?[logical] == nil {
                    if state.keyMap[physicalParent] == nil { state.keyMap[physicalParent] = [:] }
                    state.keyMap[physicalParent]![logical] = physical
                }
                return YYBridgeKey(logical)
            }
        case .custom(let callback):
            decoder.keyDecodingStrategy = .custom { bridgePath in
                let result = callback(state.path + bridgePath)
                let physical = bridgePath.last!.stringValue
                let logical = result.stringValue
                let physicalParent = yy_bridgeResolvePhysicalParent(Array(bridgePath.dropLast()), state: state)
                if state.keyMap[physicalParent]?[logical] == nil {
                    if state.keyMap[physicalParent] == nil { state.keyMap[physicalParent] = [:] }
                    state.keyMap[physicalParent]![logical] = physical
                }
                return result
            }
        @unknown default:
            decoder.keyDecodingStrategy = options.keyDecodingStrategy
        }
        if case .custom(let callback) = options.dateDecodingStrategy { decoder.dateDecodingStrategy = .custom { try callback(YYModelPrefixDecoder(base: $0, prefix: state.path)) } }
        if case .custom(let callback) = options.dataDecodingStrategy { decoder.dataDecodingStrategy = .custom { try callback(YYModelPrefixDecoder(base: $0, prefix: state.path)) } }
        let data = try JSONEncoder().encode(yy_decodingJSONValue(at: raw.codingPath) { try YYModelJSONValue(raw.value) })
        return try decoder.decode(YYModelNativeStrategyResult<T>.self, from: data).value
    }
}
private struct YYBridgeKey: CodingKey {
    var stringValue: String; var intValue: Int?
    init(_ s: String) { stringValue = s; intValue = nil }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { return nil }
}
private struct YYBridgeComponent: Hashable {
    let string: String
    let int: Int?
    init(_ key: CodingKey) { string = key.stringValue; int = key.intValue }
    init(string: String, int: Int?) { self.string = string; self.int = int }
}
private typealias YYBridgePath = [YYBridgeComponent]
func yy_bridgeSnakeCase(_ key: String) -> String {
    guard let first = key.firstIndex(where: { $0 != "_" }), let last = key.lastIndex(where: { $0 != "_" }) else { return key }
    let words = key[first...last].split(separator: "_")
    guard words.count > 1 else { return key }
    return String(key[..<first]) + words[0].lowercased() + words.dropFirst().map { $0.capitalized }.joined() + String(key[key.index(after: last)...])
}
private final class YYModelNativeStrategyState: @unchecked Sendable {
    let path: [CodingKey]
    let rawValue: Any
    let transform: (Decoder) throws -> Any
    let customDate: Bool
    let customData: Bool
    var keyMap: [YYBridgePath: [String: String]] = [:]
    init(path: [CodingKey], rawValue: Any, options: JSONDecoder, transform: @escaping (Decoder) throws -> Any) {
        self.path = path; self.rawValue = rawValue; self.transform = transform
        if case .custom = options.dateDecodingStrategy { customDate = true } else { customDate = false }
        if case .custom = options.dataDecodingStrategy { customData = true } else { customData = false }
    }
    func customStrategy<T>(_ type: T.Type) -> Bool {
        (type == Date.self && customDate) || (type == Data.self && customData)
    }
    func location(at path: [CodingKey]) -> (Any?, YYBridgePath) {
        var node: Any? = rawValue
        var physicalPath: YYBridgePath = []
        for key in path {
            if let array = node as? [Any], let index = key.intValue {
                node = array.indices.contains(index) ? array[index] : nil
                physicalPath.append(YYBridgeComponent(key))
            } else if let dictionary = node as? [String: Any] {
                let physical = keyMap[physicalPath]?[key.stringValue] ?? key.stringValue
                node = dictionary[physical]
                physicalPath.append(YYBridgeComponent(string: physical, int: nil))
            } else { return (nil, physicalPath) }
        }
        return (node, physicalPath)
    }
}
private func yy_bridgeResolvePhysicalParent(_ bridgeParent: [CodingKey], state: YYModelNativeStrategyState) -> YYBridgePath {
    state.location(at: bridgeParent).1
}
private struct YYModelNativeStrategyResult<T: Decodable>: Decodable {
    let value: T
    init(from decoder: Decoder) throws {
        guard let state = decoder.userInfo[YYModelNativeBridge.key] as? YYModelNativeStrategyState,
              let result = try state.transform(YYModelPrefixDecoder(base: decoder, prefix: state.path, physical: state.rawValue, physicalPath: [])) as? T else {
            throw DecodingError.yy_corrupted(decoder.codingPath, "Unexpected native strategy result")
        }
        value = result
    }
}
private func yy_preserved(_ physical: Any?) -> Double? {
    guard let num = physical as? NSDecimalNumber else { return nil }
    return YYModelNumberBoundary.node(from: num)?.doubleProjection
}
private func yy_float<T>(type: T.Type, preserved: Double, physical: Any?) -> T? {
    guard preserved.isFinite else { return nil }
    if T.self == Double.self { return preserved as? T }
    if T.self == Float.self {
        let f = (physical as? NSDecimalNumber).flatMap { YYModelNumberBoundary.node(from: $0)?.floatProjection ?? Float($0.stringValue) } ?? Float(preserved)
        return f.isFinite ? f as? T : nil
    }
    if T.self == CGFloat.self {
        let c = CGFloat(preserved)
        return Double(c).isFinite ? c as? T : nil
    }
    return nil
}
private struct PrefixDecodingValue<T: Decodable>: Decodable {
    let value: T
    init(from decoder: Decoder) throws {
        let state = decoder.userInfo[YYModelNativeBridge.key] as? YYModelNativeStrategyState
        let prefix = state?.path ?? []
        if YYJSONValueDecoder.isLeaf(T.self) {
            value = try YYModelPrefixDecoder(base: decoder, prefix: prefix).singleValueContainer().decode(T.self)
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
        let state = decoder.userInfo[YYModelNativeBridge.key] as? YYModelNativeStrategyState
        let prefix = state?.path ?? []
        let physical = state?.location(at: decoder.codingPath).0
        guard physical is [String: Any] else {
            let context = DecodingError.Context(codingPath: prefix + decoder.codingPath, debugDescription: "Expected dictionary")
            if physical is NSNull { throw DecodingError.valueNotFound(Self.self, context) }
            throw DecodingError.typeMismatch(Self.self, context)
        }
        let values = try decoder.singleValueContainer().decode([String: PrefixDecodingValue<Value>].self)
        func key(_ name: String) throws -> Key {
            if Key.self == String.self { return name as! Key }
            if let index = Int(name) { return index as! Key }
            throw DecodingError.typeMismatch(Key.self, .init(codingPath: prefix + decoder.codingPath, debugDescription: "Invalid integer dictionary key"))
        }
        var result: [Key: Value] = [:]
        for (_, key, box) in try YYModelDictionarySelection.winners(values, key: key) {
            result[key] = box.value
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
            return .init(codingPath: prefix + c.codingPath, debugDescription: c.debugDescription, underlyingError: c.underlyingError)
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
    let physical: Any?
    let physicalPath: YYBridgePath
    let state: YYModelNativeStrategyState?
    init(base: Decoder, prefix: [CodingKey], physical: Any? = nil, physicalPath: YYBridgePath? = nil) {
        self.base = base; self.prefix = prefix
        let s = base.userInfo[YYModelNativeBridge.key] as? YYModelNativeStrategyState
        self.state = s
        if let physical {
            self.physical = physical
            self.physicalPath = physicalPath ?? []
        } else {
            let location = s?.location(at: base.codingPath)
            self.physical = location?.0
            self.physicalPath = physicalPath ?? location?.1 ?? []
        }
    }
    var codingPath: [CodingKey] { prefix + base.codingPath }
    var userInfo: [CodingUserInfoKey: Any] { base.userInfo }
    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        try rebasing(prefix) { KeyedDecodingContainer(PrefixKeyedDecoder(base: try base.container(keyedBy: type), prefix: prefix, physical: physical, physicalPath: physicalPath, state: state)) }
    }
    func unkeyedContainer() throws -> UnkeyedDecodingContainer { try rebasing(prefix) { PrefixUnkeyedDecoder(base: try base.unkeyedContainer(), prefix: prefix, physical: physical, physicalPath: physicalPath, state: state) } }
    func singleValueContainer() throws -> SingleValueDecodingContainer { try rebasing(prefix) { PrefixSingleDecoder(base: try base.singleValueContainer(), prefix: prefix, physical: physical, physicalPath: physicalPath, state: state) } }
}
private struct PrefixKeyedDecoder<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let base: KeyedDecodingContainer<Key>
    let prefix: [CodingKey]
    let physical: Any?
    let physicalPath: YYBridgePath
    let state: YYModelNativeStrategyState?
    init(base: KeyedDecodingContainer<Key>, prefix: [CodingKey], physical: Any? = nil, physicalPath: YYBridgePath? = nil, state: YYModelNativeStrategyState? = nil) {
        self.base = base; self.prefix = prefix; self.physical = physical
        self.physicalPath = physicalPath ?? []
        self.state = state
    }
    var codingPath: [CodingKey] { prefix + base.codingPath }
    var allKeys: [Key] { base.allKeys }
    func contains(_ key: Key) -> Bool { base.contains(key) }
    func decodeNil(forKey key: Key) throws -> Bool { try rebasing(prefix) { try base.decodeNil(forKey: key) } }
    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        if T.self == Double.self || T.self == Float.self || T.self == CGFloat.self {
            let validated: T = try rebasing(prefix) { try base.decode(type, forKey: key) }
            guard let st = state else { return validated }
            guard let physKey = st.keyMap[physicalPath]?[key.stringValue] else {
                if let dict = physical as? [String: Any], let child = dict[key.stringValue],
                   let p = yy_preserved(child), let r: T = yy_float(type: type, preserved: p, physical: child) { return r }
                return validated
            }
            guard let dict = physical as? [String: Any], let child = dict[physKey],
                  let p = yy_preserved(child), let r: T = yy_float(type: type, preserved: p, physical: child) else { return validated }
            return r
        }
        if state?.customStrategy(type) == true { return try base.decode(type, forKey: key) }
        if YYJSONValueDecoder.isLeaf(type) { return try rebasing(prefix) { try base.decode(type, forKey: key) } }
        guard base.contains(key) else {
            throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "Missing key"))
        }
        return try base.decode(PrefixDecodingValue<T>.self, forKey: key).value
    }
    func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> {
        let validated = try rebasing(prefix) { try base.nestedContainer(keyedBy: type, forKey: key) }
        guard let st = state else { return validated }
        guard let physKey = st.keyMap[physicalPath]?[key.stringValue] else {
            if let dict = physical as? [String: Any], let child = dict[key.stringValue] {
                let childPath = physicalPath + [YYBridgeComponent(string: key.stringValue, int: key.intValue)]
                return KeyedDecodingContainer(PrefixKeyedDecoder<NestedKey>(base: validated, prefix: prefix, physical: child, physicalPath: childPath, state: state))
            }
            return validated
        }
        guard let dict = physical as? [String: Any], let child = dict[physKey] else { return validated }
        let childPath = physicalPath + [YYBridgeComponent(string: physKey, int: nil)]
        return KeyedDecodingContainer(PrefixKeyedDecoder<NestedKey>(base: validated, prefix: prefix, physical: child, physicalPath: childPath, state: state))
    }
    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        let validated = try rebasing(prefix) { try base.nestedUnkeyedContainer(forKey: key) }
        guard let st = state else { return validated }
        guard let physKey = st.keyMap[physicalPath]?[key.stringValue] else {
            if let dict = physical as? [String: Any], let child = dict[key.stringValue] {
                let childPath = physicalPath + [YYBridgeComponent(string: key.stringValue, int: key.intValue)]
                return PrefixUnkeyedDecoder(base: validated, prefix: prefix, physical: child, physicalPath: childPath, state: state)
            }
            return validated
        }
        guard let dict = physical as? [String: Any], let child = dict[physKey] else { return validated }
        let childPath = physicalPath + [YYBridgeComponent(string: physKey, int: nil)]
        return PrefixUnkeyedDecoder(base: validated, prefix: prefix, physical: child, physicalPath: childPath, state: state)
    }
    func superDecoder() throws -> Decoder { try rebasing(prefix) { YYModelPrefixDecoder(base: try base.superDecoder(), prefix: prefix) } }
    func superDecoder(forKey key: Key) throws -> Decoder {
        let validated = try rebasing(prefix) { try base.superDecoder(forKey: key) }
        guard let st = state, let physKey = st.keyMap[physicalPath]?[key.stringValue],
              let dict = physical as? [String: Any], let child = dict[physKey] else {
            if let dict = physical as? [String: Any], let child = dict[key.stringValue],
               state?.keyMap[physicalPath]?[key.stringValue] == nil {
                let childPath = physicalPath + [YYBridgeComponent(string: key.stringValue, int: key.intValue)]
                return YYModelPrefixDecoder(base: validated, prefix: prefix, physical: child, physicalPath: childPath)
            }
            return validated
        }
        let childPath = physicalPath + [YYBridgeComponent(string: physKey, int: nil)]
        return YYModelPrefixDecoder(base: validated, prefix: prefix, physical: child, physicalPath: childPath)
    }
}
private struct PrefixUnkeyedDecoder: UnkeyedDecodingContainer {
    var base: UnkeyedDecodingContainer
    let prefix: [CodingKey]
    let physical: Any?
    let physicalPath: YYBridgePath
    let state: YYModelNativeStrategyState?
    init(base: UnkeyedDecodingContainer, prefix: [CodingKey], physical: Any? = nil, physicalPath: YYBridgePath? = nil, state: YYModelNativeStrategyState? = nil) {
        self.base = base; self.prefix = prefix; self.physical = physical
        self.physicalPath = physicalPath ?? []
        self.state = state
    }
    var codingPath: [CodingKey] { prefix + base.codingPath }
    var count: Int? { base.count }; var isAtEnd: Bool { base.isAtEnd }; var currentIndex: Int { base.currentIndex }
    mutating func decodeNil() throws -> Bool { try rebasing(prefix) { try base.decodeNil() } }
    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
        if T.self == Double.self || T.self == Float.self || T.self == CGFloat.self {
            let fullPhysical = physical as? [Any]
            let child = (currentIndex < (fullPhysical?.count ?? 0)) ? fullPhysical?[currentIndex] : nil
            if let p = yy_preserved(child), let r: T = yy_float(type: type, preserved: p, physical: child) {
                _ = try rebasing(prefix) { try base.decode(type) }
                return r
            }
        }
        if state?.customStrategy(type) == true { return try base.decode(type) }
        if YYJSONValueDecoder.isLeaf(type) { return try rebasing(prefix) { try base.decode(type) } }
        guard !base.isAtEnd else {
            throw DecodingError.valueNotFound(type, .init(codingPath: codingPath + [YYModelCodingKey(intValue: currentIndex)], debugDescription: "Unkeyed container is at end"))
        }
        return try base.decode(PrefixDecodingValue<T>.self).value
    }
    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> {
        let index = currentIndex
        let validated = try rebasing(prefix) { try base.nestedContainer(keyedBy: type) }
        let child = (physical as? [Any]).flatMap { index < $0.count ? $0[index] : nil }
        let childPath = physicalPath + [YYBridgeComponent(string: "\(index)", int: index)]
        return KeyedDecodingContainer(PrefixKeyedDecoder<NestedKey>(base: validated, prefix: prefix, physical: child, physicalPath: childPath, state: state))
    }
    mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        let index = currentIndex
        let validated = try rebasing(prefix) { try base.nestedUnkeyedContainer() }
        let child = (physical as? [Any]).flatMap { index < $0.count ? $0[index] : nil }
        let childPath = physicalPath + [YYBridgeComponent(string: "\(index)", int: index)]
        return PrefixUnkeyedDecoder(base: validated, prefix: prefix, physical: child, physicalPath: childPath, state: state)
    }
    mutating func superDecoder() throws -> Decoder {
        let index = currentIndex
        let validated = try rebasing(prefix) { try base.superDecoder() }
        let child = (physical as? [Any]).flatMap { index < $0.count ? $0[index] : nil }
        let childPath = physicalPath + [YYBridgeComponent(string: "\(index)", int: index)]
        return YYModelPrefixDecoder(base: validated, prefix: prefix, physical: child, physicalPath: childPath)
    }
}
private struct PrefixSingleDecoder: SingleValueDecodingContainer {
    let base: SingleValueDecodingContainer
    let prefix: [CodingKey]
    let physical: Any?
    let physicalPath: YYBridgePath
    let state: YYModelNativeStrategyState?
    init(base: SingleValueDecodingContainer, prefix: [CodingKey], physical: Any? = nil, physicalPath: YYBridgePath? = nil, state: YYModelNativeStrategyState? = nil) {
        self.base = base; self.prefix = prefix; self.physical = physical
        self.physicalPath = physicalPath ?? []
        self.state = state
    }
    var codingPath: [CodingKey] { prefix + base.codingPath }
    func decodeNil() -> Bool { base.decodeNil() }
    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        if T.self == Double.self || T.self == Float.self || T.self == CGFloat.self {
            if let p = yy_preserved(physical), let r: T = yy_float(type: type, preserved: p, physical: physical) {
                _ = try rebasing(prefix) { try base.decode(type) }; return r
            }
        }
        if state?.customStrategy(type) == true { return try base.decode(type) }
        if YYJSONValueDecoder.isLeaf(type) { return try rebasing(prefix) { try base.decode(type) } }
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

public struct YYModelCapability: Sendable {
    public static let foundationExactDecimal: Bool = {
        struct Probe: Decodable { let a: Decimal; let b: Decimal }
        let data = Data(#"{"a":9007199254740993,"b":18446744073709551615}"#.utf8)
        guard let result = try? JSONDecoder().decode(Probe.self, from: data) else { return false }
        return "\(result.a)" == "9007199254740993" && "\(result.b)" == "18446744073709551615"
    }()
}
