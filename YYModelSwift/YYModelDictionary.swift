import Foundation

// String/Int dictionary keys are data, not model CodingKeys. Let Foundation's
// specialized dictionary path retain them while contextual boxes adapt each value.
protocol YYModelDictionaryDecoding {
    static func decodeDictionary(from decoder: Decoder, date: YYModelDateStrategy) throws -> Any?
}
private struct YYModelDictionaryValue<Value: Decodable>: Decodable {
    let value: Value
    init(from decoder: Decoder) throws {
        let context = YYJSONContext.from(decoder)
        value = try YYModelDecode.value(Value.self, from: decoder, date: context.dictionaryDate ?? context.defaults.date)
    }
}
extension Dictionary: YYModelDictionaryDecoding where Key: Decodable, Value: Decodable {
    static func decodeDictionary(from decoder: Decoder, date: YYModelDateStrategy) throws -> Any? {
        guard Key.self == String.self || Key.self == Int.self else { return nil }
        let context = YYJSONContext.from(decoder)
        var result: [Key: Value] = [:]
        if let raw = decoder as? _YYDecoder {
            guard let dictionary = raw.value as? [String: Any] else { throw DecodingError.typeMismatch(Self.self, .init(codingPath: decoder.codingPath, debugDescription: "Expected dictionary")) }
            for (name, value) in dictionary {
                let key: Key
                if Key.self == String.self { key = name as! Key }
                else if let index = Int(name) { key = index as! Key }
                else { throw DecodingError.typeMismatch(Key.self, .init(codingPath: decoder.codingPath, debugDescription: "Invalid integer dictionary key: \(name)")) }
                let child = context.rawDecoder(value, path: decoder.codingPath + [YYModelCodingKey(name)], userInfo: decoder.userInfo)
                result[key] = try YYModelDecode.value(Value.self, from: child, date: date)
            }
        } else {
            let previous = context.dictionaryDate; context.dictionaryDate = date
            defer { context.dictionaryDate = previous }
            let values = try decoder.singleValueContainer().decode([String: YYModelDictionaryValue<Value>].self)
            for (name, box) in values {
                if Key.self == String.self { result[name as! Key] = box.value }
                else if let index = Int(name) { result[index as! Key] = box.value }
                else { throw DecodingError.typeMismatch(Key.self, .init(codingPath: decoder.codingPath, debugDescription: "Invalid integer dictionary key: \(name)")) }
            }
        }
        return result
    }
}

protocol YYModelDictionaryEncoding {
    func encodeDictionary(to encoder: Encoder, date: YYModelDateStrategy) throws -> Bool
}
extension Dictionary: YYModelDictionaryEncoding where Value: Encodable {
    func encodeDictionary(to encoder: Encoder, date: YYModelDateStrategy) throws -> Bool {
        guard Key.self == String.self || Key.self == Int.self else { return false }
        var values: [String: YYModelEncodingBox<Value>] = [:]
        for (key, value) in self {
            let name = Key.self == String.self ? key as! String : String(key as! Int)
            values[name] = YYModelEncodingBox(value: value, date: date, skipHook: false)
        }
        var container = encoder.singleValueContainer(); try container.encode(values)
        return true
    }
}
