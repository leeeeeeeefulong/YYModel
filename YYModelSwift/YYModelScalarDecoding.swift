import Foundation

// Integer collections need exact scalar conversion, but not a model adapter and
// optional-rule lookup for every element. Foundation retains scanning and indexing.
protocol YYModelScalarCollection {
    static var scalarCompatible: Bool { get }
    static func decodeScalars(from decoder: Decoder) throws -> Any
}
private struct YYModelScalarBox<Value: Decodable>: Decodable {
    let value: Value
    init(from decoder: Decoder) throws { value = try YYModelDecode.scalar(Value.self, from: decoder) }
}
private func isScalarCompatible<Value>(_ type: Value.Type) -> Bool {
    if type == Date.self || type == Data.self { return false }
    return YYJSONValueDecoder.isLeaf(type) || (type as? YYModelScalarCollection.Type)?.scalarCompatible == true
}
extension Optional: YYModelScalarCollection where Wrapped: Decodable {
    static var scalarCompatible: Bool { isScalarCompatible(Wrapped.self) }
    static func decodeScalars(from decoder: Decoder) throws -> Any {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { return Self.none as Any }
        return Self.some(try container.decode(YYModelScalarBox<Wrapped>.self).value) as Any
    }
}
extension Array: YYModelScalarCollection where Element: Decodable {
    static var scalarCompatible: Bool { isScalarCompatible(Element.self) }
    static func decodeScalars(from decoder: Decoder) throws -> Any {
        try decoder.singleValueContainer().decode([YYModelScalarBox<Element>].self).map(\.value)
    }
}
extension Set: YYModelScalarCollection where Element: Decodable {
    static var scalarCompatible: Bool { isScalarCompatible(Element.self) }
    static func decodeScalars(from decoder: Decoder) throws -> Any {
        Set(try decoder.singleValueContainer().decode([YYModelScalarBox<Element>].self).map(\.value))
    }
}
extension Dictionary: YYModelScalarCollection where Key: Decodable, Value: Decodable {
    static var scalarCompatible: Bool { (Key.self == String.self || Key.self == Int.self) && isScalarCompatible(Value.self) }
    static func decodeScalars(from decoder: Decoder) throws -> Any {
        let values = try decoder.singleValueContainer().decode([String: YYModelScalarBox<Value>].self)
        var result: Self = [:]; result.reserveCapacity(values.count)
        for (name, box) in values {
            let key: Key
            if Key.self == String.self { key = name as! Key }
            else if let index = Int(name) { key = index as! Key }
            else { throw DecodingError.typeMismatch(Key.self, .init(codingPath: decoder.codingPath, debugDescription: "Invalid integer dictionary key: \(name)")) }
            result[key] = box.value
        }
        return result
    }
}
