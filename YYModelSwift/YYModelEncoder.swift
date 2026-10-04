import Foundation

struct YYModelEncodingBox<T: Encodable>: Encodable {
    let value: T
    let date: YYModelDateStrategy
    let skipHook: Bool
    func encode(to encoder: Encoder) throws { try YYModelEncode.value(value, to: encoder, date: date, skipHook: skipHook) }
}
enum YYModelEncode {
    static func value<T: Encodable>(_ value: T, to input: Encoder, date: YYModelDateStrategy, skipHook: Bool = false) throws {
        let encoder = (input as? YYModelEncoder)?.base ?? input
        let context = YYJSONContext.from(input)
        var defaults = context.defaults; defaults.date = date
        let rule = try context.rule(T.self)
        let policy = rule?.resolved(defaults: defaults) ?? defaults
        if !skipHook, let hook = rule?.export {
            let native = context.exportEncoder(at: encoder)
            let data = try native.encode(YYModelEncodingBox(value: value, date: date, skipHook: true))
            guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw YYModelFailure.invalidObject("Expected export object") }
            guard try hook(value, &object) else { throw YYModelFailure.invalidObject("transformTo rejected model") }
            try YYModelJSONValue(object).encode(to: encoder)
            return
        }
        if let dispatch = rule?.polymorphicEncode { try dispatch(value, encoder); return }
        if let value = value as? Date {
            if policy.date == .native { var c = encoder.singleValueContainer(); try c.encode(value); return }
            let seconds = value.timeIntervalSince1970
            guard seconds.isFinite else { throw EncodingError.invalidValue(value, .init(codingPath: encoder.codingPath, debugDescription: "Non-finite date")) }
            var c = encoder.singleValueContainer()
            if policy.date == .iso8601 { try c.encode(YYModelDates.shared.text(value)) }
            else { try c.encode(policy.date == .millisecondsSince1970 ? seconds * 1000 : seconds) }
            return
        }
        if YYJSONValueDecoder.isLeaf(T.self) {
            var container = encoder.singleValueContainer(); try container.encode(value); return
        }
        if let dictionary = value as? YYModelDictionaryEncoding, try dictionary.encodeDictionary(to: encoder, date: policy.date) { return }
        let state = YYModelEncodingState()
        try value.encode(to: YYModelEncoder(base: encoder, policy: policy, state: state))
        if let error = state.error { throw error }
    }
}

// One state per model object, shared by containers obtained from the same Encoder.
final class YYModelEncodingState {
    var paths: [[String]] = []
    var error: Error?
    func reserve(_ path: [String]) throws {
        if let error { throw error }
        guard !path.isEmpty, path.allSatisfy({ !$0.isEmpty }) else { throw YYModelFailure.invalidObject("Empty export path") }
        if paths.contains(where: { $0.starts(with: path) || path.starts(with: $0) }) {
            throw YYModelFailure.invalidObject("Conflicting export path: \(path.joined(separator: "."))")
        }
        paths.append(path)
    }
}
struct YYModelEncoder: Encoder {
    let base: Encoder
    let policy: YYModelPolicy
    var state = YYModelEncodingState()
    var codingPath: [CodingKey] { base.codingPath }
    var userInfo: [CodingUserInfoKey: Any] { base.userInfo }
    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        KeyedEncodingContainer(YYModelKeyedEncoder<Key>(base: base.container(keyedBy: YYModelCodingKey.self), policy: policy, state: state))
    }
    func unkeyedContainer() -> UnkeyedEncodingContainer { YYModelUnkeyedEncoder(base: base.unkeyedContainer(), date: policy.date) }
    func singleValueContainer() -> SingleValueEncodingContainer { YYModelSingleEncoder(base: base, date: policy.date) }
}
struct YYModelKeyedEncoder<Key: CodingKey>: KeyedEncodingContainerProtocol {
    var base: KeyedEncodingContainer<YYModelCodingKey>
    let policy: YYModelPolicy
    let state: YYModelEncodingState
    var codingPath: [CodingKey] { base.codingPath }
    mutating func destination(_ key: Key) throws -> (KeyedEncodingContainer<YYModelCodingKey>, YYModelCodingKey)? {
        guard policy.allows(key.stringValue) else { return nil }
        let path = policy.paths(key.stringValue).first ?? []
        if !policy.mapper.isEmpty { try state.reserve(path) }
        var container = base
        for component in path.dropLast() { container = container.nestedContainer(keyedBy: YYModelCodingKey.self, forKey: YYModelCodingKey(component)) }
        return (container, YYModelCodingKey(path.last!))
    }
    mutating func encodeNil(forKey key: Key) throws {
        guard var field = try destination(key) else { return }; try field.0.encodeNil(forKey: field.1)
    }
    mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
        guard var field = try destination(key) else { return }
        if YYModelDecode.isNativeValue(T.self) { try field.0.encode(value, forKey: field.1) }
        else { try field.0.encode(YYModelEncodingBox(value: value, date: policy.fieldDates[key.stringValue] ?? policy.date, skipHook: false), forKey: field.1) }
    }
    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> {
        do {
            if var field = try destination(key) { return KeyedEncodingContainer(YYModelKeyedEncoder<NestedKey>(base: field.0.nestedContainer(keyedBy: YYModelCodingKey.self, forKey: field.1), policy: .init(date: policy.date), state: YYModelEncodingState())) }
        } catch { state.error = error }
        // A discarded container for excluded keys, never attached to the result.
        return YYModelDiscardEncoder().container(keyedBy: type)
    }
    mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        do { if var field = try destination(key) { return YYModelUnkeyedEncoder(base: field.0.nestedUnkeyedContainer(forKey: field.1), date: policy.date) } }
        catch { state.error = error }
        return YYModelDiscardEncoder().unkeyedContainer()
    }
    mutating func superEncoder() -> Encoder { YYModelEncoder(base: base.superEncoder(), policy: .init(date: policy.date)) }
    mutating func superEncoder(forKey key: Key) -> Encoder {
        do { if var field = try destination(key) { return YYModelEncoder(base: field.0.superEncoder(forKey: field.1), policy: .init(date: policy.date)) } }
        catch { state.error = error }
        return YYModelDiscardEncoder()
    }
}
struct YYModelUnkeyedEncoder: UnkeyedEncodingContainer {
    var base: UnkeyedEncodingContainer
    let date: YYModelDateStrategy
    var codingPath: [CodingKey] { base.codingPath }
    var count: Int { base.count }
    mutating func encodeNil() throws { try base.encodeNil() }
    mutating func encode<T: Encodable>(_ value: T) throws {
        if YYModelDecode.isNativeValue(T.self) { try base.encode(value) }
        else { try base.encode(YYModelEncodingBox(value: value, date: date, skipHook: false)) }
    }
    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> {
        KeyedEncodingContainer(YYModelKeyedEncoder<NestedKey>(base: base.nestedContainer(keyedBy: YYModelCodingKey.self), policy: .init(date: date), state: YYModelEncodingState()))
    }
    mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer { YYModelUnkeyedEncoder(base: base.nestedUnkeyedContainer(), date: date) }
    mutating func superEncoder() -> Encoder { YYModelEncoder(base: base.superEncoder(), policy: .init(date: date)) }
}
struct YYModelSingleEncoder: SingleValueEncodingContainer {
    let base: Encoder
    let date: YYModelDateStrategy
    var codingPath: [CodingKey] { base.codingPath }
    mutating func encodeNil() throws { var c = base.singleValueContainer(); try c.encodeNil() }
    mutating func encode<T: Encodable>(_ value: T) throws { try YYModelEncode.value(value, to: base, date: date) }
}

// Container factories cannot throw. Excluded custom nested containers use an unattached sink.
private final class YYModelDiscardEncoder: Encoder {
    var codingPath: [CodingKey] = []
    var userInfo: [CodingUserInfoKey: Any] = [:]
    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> { KeyedEncodingContainer(DiscardKeyed<Key>()) }
    func unkeyedContainer() -> UnkeyedEncodingContainer { DiscardUnkeyed() }
    func singleValueContainer() -> SingleValueEncodingContainer { DiscardSingle() }
}
private struct DiscardKeyed<Key: CodingKey>: KeyedEncodingContainerProtocol {
    var codingPath: [CodingKey] = []
    mutating func encodeNil(forKey key: Key) throws {}
    mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {}
    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> { YYModelDiscardEncoder().container(keyedBy: type) }
    mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer { DiscardUnkeyed() }
    mutating func superEncoder() -> Encoder { YYModelDiscardEncoder() }
    mutating func superEncoder(forKey key: Key) -> Encoder { YYModelDiscardEncoder() }
}
private struct DiscardUnkeyed: UnkeyedEncodingContainer {
    var codingPath: [CodingKey] = []; var count = 0
    mutating func encodeNil() throws { count += 1 }
    mutating func encode<T: Encodable>(_ value: T) throws { count += 1 }
    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> { count += 1; return YYModelDiscardEncoder().container(keyedBy: type) }
    mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer { count += 1; return DiscardUnkeyed() }
    mutating func superEncoder() -> Encoder { count += 1; return YYModelDiscardEncoder() }
}
private struct DiscardSingle: SingleValueEncodingContainer {
    var codingPath: [CodingKey] = []
    mutating func encodeNil() throws {}
    mutating func encode<T: Encodable>(_ value: T) throws {}
}
