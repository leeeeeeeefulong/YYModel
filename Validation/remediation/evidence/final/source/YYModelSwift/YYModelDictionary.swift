import Foundation

// String/Int dictionary keys are data, not model CodingKeys. Let Foundation's
// specialized dictionary path retain them while contextual boxes adapt each value.

/// JSON 对象的键只能出现在 `String` / `Int` / `CodingKeyRepresentable` 三种字典键上。
///
/// `CodingKeyRepresentable`（iOS 15.4+ / macOS 12.3+）是官方给出的扩展路径：
/// 让自定义类型无损地在「自定义键」与 `CodingKey` 之间转换，
/// 从而参与 keyed container 编解码，而不是退化成 key-value 交替的数组。
/// 官方已让 `String` / `Int` 采纳该协议。
enum YYModelDictionaryKey {

    /// 该字典键类型能否映射到 JSON 对象。
    @inline(__always)
    static func isSupported<Key>(_ type: Key.Type) -> Bool {
        if Key.self == String.self || Key.self == Int.self { return true }
        if #available(iOS 15.4, macOS 12.3, tvOS 15.4, watchOS 8.5, *) {
            return (Key.self as? any CodingKeyRepresentable.Type) != nil
        }
        return false
    }

    /// JSON 键名 → 字典键。返回 nil 表示该键无法映射。
    @inline(__always)
    static func make<Key>(_ name: String, _ type: Key.Type) -> Key? {
        if Key.self == String.self { return name as? Key }
        if Key.self == Int.self { return Int(name) as? Key }
        if #available(iOS 15.4, macOS 12.3, tvOS 15.4, watchOS 8.5, *),
           let representable = Key.self as? any CodingKeyRepresentable.Type {
            // R6: numeric JSON keys must expose intValue, exactly like Foundation's own
            // dictionary path — CodingKeyRepresentable implementations (e.g. a NumberKey)
            // build their key from codingKey.intValue, not by re-parsing stringValue.
            // P1-3: preserve the literal spelling ("01" vs "1") while exposing intValue.
            // Rebuilding from intValue would normalize "01" to "1" and merge entries.
            let codingKey = Int(name).map { YYModelCodingKey(preserving: name, intValue: $0) } ?? YYModelCodingKey(name)
            if let converted = representable.init(codingKey: codingKey) {
                return converted as? Key
            }
        }
        return nil
    }

    /// 字典键 → JSON 键名。返回 nil 表示该键无法映射。
    @inline(__always)
    static func name<Key>(_ key: Key) -> String? {
        if Key.self == String.self { return key as? String }
        if Key.self == Int.self { return (key as? Int).map(String.init) }
        if #available(iOS 15.4, macOS 12.3, tvOS 15.4, watchOS 8.5, *),
           let representable = key as? any CodingKeyRepresentable {
            return representable.codingKey.stringValue
        }
        return nil
    }
}

protocol YYModelDictionaryDecoding {
    static func decodeDictionary(from decoder: Decoder, date: YYModelDateStrategy) throws -> Any?
}

// The date policy is immutable and belongs to this generic decoding operation.
// Foundation may reuse a Decoder while traversing dictionary values; never retain it.
private protocol YYDictionaryDate { static var strategy: YYModelDateStrategy { get } }
private struct NativeDate: YYDictionaryDate { static let strategy: YYModelDateStrategy = .native }
private struct AutomaticDate: YYDictionaryDate { static let strategy: YYModelDateStrategy = .automatic }
private struct SecondsDate: YYDictionaryDate { static let strategy: YYModelDateStrategy = .secondsSince1970 }
private struct MillisecondsDate: YYDictionaryDate { static let strategy: YYModelDateStrategy = .millisecondsSince1970 }
private struct MicrosecondsDate: YYDictionaryDate { static let strategy: YYModelDateStrategy = .microsecondsSince1970 }
private struct ISODate: YYDictionaryDate { static let strategy: YYModelDateStrategy = .iso8601 }
private struct YYModelDictionaryValue<Value: Decodable, DatePolicy: YYDictionaryDate>: Decodable {
    let value: Value
    init(from decoder: Decoder) throws {
        value = try YYModelDecode.value(Value.self, from: decoder, date: DatePolicy.strategy)
    }
}

enum YYModelDictionarySelection {
    static func winners<Key: Hashable, Value>(_ values: [String: Value],
                                              key: (String) throws -> Key) rethrows -> [(String, Key, Value)] {
        var selected: [Key: String] = [:]
        for name in values.keys.sorted(by: { $0.utf8.lexicographicallyPrecedes($1.utf8) }) {
            let converted = try key(name)
            if let previous = selected[converted] {
                let canonical = YYModelDictionaryKey.name(converted)
                if name == canonical && previous != canonical { selected[converted] = name }
            } else { selected[converted] = name }
        }
        return selected.map { ($0.value, $0.key, values[$0.value]!) }
            .sorted { $0.0.utf8.lexicographicallyPrecedes($1.0.utf8) }
    }
}

extension Dictionary: YYModelDictionaryDecoding where Key: Decodable, Value: Decodable {
    static func decodeDictionary(from decoder: Decoder, date: YYModelDateStrategy) throws -> Any? {
        // 不支持的键类型交回调用方（它会按普通模型处理）。
        guard YYModelDictionaryKey.isSupported(Key.self) else { return nil }

        let context = YYJSONContext.from(decoder)
        var result: [Key: Value] = [:]

        @inline(__always)
        func key(for name: String) throws -> Key {
            guard let key = YYModelDictionaryKey.make(name, Key.self) else {
                throw DecodingError.typeMismatch(
                    Key.self,
                    .init(codingPath: decoder.codingPath,
                          debugDescription: "Dictionary key \"\(name)\" is not representable as \(Key.self)")
                )
            }
            return key
        }

        if let raw = decoder as? _YYDecoder {
            guard let dictionary = raw.value as? [String: Any] else {
                throw DecodingError.typeMismatch(Self.self, .init(codingPath: decoder.codingPath, debugDescription: "Expected dictionary"))
            }
            var values: [String: Value] = [:]
            for (name, rawValue) in dictionary {
                let child = context.rawDecoder(rawValue, path: decoder.codingPath + [YYModelCodingKey(name)], userInfo: decoder.userInfo)
                values[name] = try YYModelDecode.value(Value.self, from: child, date: date)
            }
            for (_, k, value) in try YYModelDictionarySelection.winners(values, key: key) { result[k] = value }
        } else {
            func decodeValues<P: YYDictionaryDate>(_ policy: P.Type) throws -> [String: Value] {
                try decoder.singleValueContainer().decode([String: YYModelDictionaryValue<Value, P>].self).mapValues(\.value)
            }
            let values: [String: Value]
            switch date {
            case .native: values = try decodeValues(NativeDate.self)
            case .automatic: values = try decodeValues(AutomaticDate.self)
            case .secondsSince1970: values = try decodeValues(SecondsDate.self)
            case .millisecondsSince1970: values = try decodeValues(MillisecondsDate.self)
            case .microsecondsSince1970: values = try decodeValues(MicrosecondsDate.self)
            case .iso8601: values = try decodeValues(ISODate.self)
            }
            for (_, k, value) in try YYModelDictionarySelection.winners(values, key: key) { result[k] = value }
        }
        return result
    }
}

protocol YYModelDictionaryEncoding {
    func encodeDictionary(to encoder: Encoder, date: YYModelDateStrategy) throws -> Bool
}

extension Dictionary: YYModelDictionaryEncoding where Value: Encodable {
    func encodeDictionary(to encoder: Encoder, date: YYModelDateStrategy) throws -> Bool {
        guard YYModelDictionaryKey.isSupported(Key.self) else { return false }
        var values: [String: YYModelEncodingBox<Value>] = [:]
        for (key, value) in self {
            guard let name = YYModelDictionaryKey.name(key) else {
                throw EncodingError.invalidValue(
                    key,
                    .init(codingPath: encoder.codingPath,
                          debugDescription: "Dictionary key \(key) is not representable as a JSON key")
                )
            }
            values[name] = YYModelEncodingBox(value: value, date: date, skipHook: false)
        }
        var container = encoder.singleValueContainer(); try container.encode(values)
        return true
    }
}
