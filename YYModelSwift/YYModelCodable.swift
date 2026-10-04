import Foundation

/// A Swift value model with synthesized Codable and YYModel mapping semantics.
public protocol YYModelCodable: Codable {
    static var yy_modelConfiguration: YYModelConfiguration<Self> { get }
}

/// A dot path, ordered alternatives, or an explicitly literal JSON key.
public struct YYModelKey: ExpressibleByStringLiteral, ExpressibleByArrayLiteral, Sendable {
    let paths: [[String]]
    public init(stringLiteral value: String) { paths = [value.components(separatedBy: ".")] }
    public init(arrayLiteral elements: String...) { paths = elements.map { $0.components(separatedBy: ".") } }
    public static func key(_ literal: String) -> Self { Self(paths: [[literal]]) }
    public static func path(_ components: String...) -> Self { Self(paths: [components]) }
    public static func alternatives(_ paths: [String]...) -> Self { Self(paths: paths) }
    private init(paths: [[String]]) { self.paths = paths }
}

public enum YYModelDateStrategy: Sendable {
    /// Recognize seconds, large millisecond timestamps, and common textual formats. Export seconds.
    case automatic, secondsSince1970, millisecondsSince1970, iso8601
}

/// Keys refer to CodingKeys (property names when CodingKeys is synthesized).
/// Configuration is cached per type. Captured state in hooks must be thread safe.
public struct YYModelConfiguration<Model> {
    public let mapper: [String: YYModelKey]
    public let blacklist: [String]
    public let whitelist: [String]?
    public let requiredProperties: [String]
    public let defaultValues: [String: Any]
    public let dateStrategy: YYModelDateStrategy
    public let willTransform: (([String: Any]) throws -> [String: Any]?)?
    public let didTransform: ((inout Model, [String: Any]) throws -> Bool)?
    public let transformTo: ((Model, inout [String: Any]) throws -> Bool)?
    public init(mapper: [String: YYModelKey] = [:], blacklist: [String] = [], whitelist: [String]? = nil,
                requiredProperties: [String] = [], defaultValues: [String: Any] = [:],
                dateStrategy: YYModelDateStrategy = .automatic,
                willTransform: (([String: Any]) throws -> [String: Any]?)? = nil,
                didTransform: ((inout Model, [String: Any]) throws -> Bool)? = nil,
                transformTo: ((Model, inout [String: Any]) throws -> Bool)? = nil) {
        self.mapper = mapper; self.blacklist = blacklist; self.whitelist = whitelist
        self.requiredProperties = requiredProperties; self.defaultValues = defaultValues
        self.dateStrategy = dateStrategy; self.willTransform = willTransform
        self.didTransform = didTransform; self.transformTo = transformTo
    }
}

public extension YYModelCodable {
    static var yy_modelConfiguration: YYModelConfiguration<Self> { .init() }
    static func yy_decode(withJSON json: Any) throws -> Self { try YYModelJSON.decode(Self.self, from: json) }
    static func yy_model(withJSON json: Any) -> Self? { try? yy_decode(withJSON: json) }
    static func yy_model(with dictionary: [String: Any]) -> Self? { yy_model(withJSON: dictionary) }
    static func yy_decodeArray(withJSON json: Any) throws -> [Self] { try YYModelJSON.decode([Self].self, from: json) }
    static func yy_modelArray(withJSON json: Any) -> [Self]? { try? yy_decodeArray(withJSON: json) }
    func yy_encode() throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: YYModelJSON.encode(self))
        guard let dictionary = object as? [String: Any] else { throw YYModelFailure.invalidObject("Model must export an object") }
        return dictionary
    }
    func yy_modelToJSONObject() -> [String: Any]? { try? yy_encode() }
    func yy_modelToJSONData() -> Data? { try? YYModelJSON.encode(self) }
    func yy_modelToJSONString() -> String? { yy_modelToJSONData().flatMap { String(data: $0, encoding: .utf8) } }
}

public extension Array where Element: YYModelCodable {
    func yy_modelToJSONObject() -> [[String: Any]]? { try? map { try $0.yy_encode() } }
    func yy_modelToJSONData() -> Data? { try? YYModelJSON.encode(self) }
    func yy_modelToJSONString() -> String? { yy_modelToJSONData().flatMap { String(data: $0, encoding: .utf8) } }
}

/// Generic entry points also support arrays and dictionaries containing YYModel values.
public enum YYModelJSON {
    public static func decode<T: Decodable>(_ type: T.Type, from json: Any) throws -> T {
        if let data = json as? Data {
            let decoder = JSONDecoder()
            decoder.userInfo[YYModelJSONInput.key] = YYModelJSONInput(data: data)
            return try decoder.decode(YYModelDecodingBox<T>.self, from: data).value
        }
        if let text = json as? String { return try decode(type, from: Data(text.utf8)) }
        return try YYModelDecode.value(type, from: _YYDecoder(value: json, codingPath: []), date: .automatic)
    }
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(YYModelEncodingBox(value: value, date: .automatic, skipHook: false))
    }
}

enum YYModelFailure: Error, CustomStringConvertible {
    case invalidObject(String)
    var description: String { switch self { case .invalidObject(let message): return message } }
}
