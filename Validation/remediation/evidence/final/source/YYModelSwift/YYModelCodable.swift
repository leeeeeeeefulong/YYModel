import Foundation

public protocol _YYModelCodableBase {
    static func _yy_baseConfiguration() -> Any
}

/// Optional convenience for model-owned rules. Ordinary Codable needs no YY protocol.
public protocol YYModelCodable: Codable, _YYModelCodableBase {
    static var yy_modelConfiguration: YYModelConfiguration<Self> { get }
}
extension YYModelCodable {
    public static func _yy_baseConfiguration() -> Any {
        return Self.yy_modelConfiguration
    }
}

/// A dot path, ordered alternatives, or an explicitly literal JSON key.
public struct YYModelKey: ExpressibleByStringLiteral, ExpressibleByArrayLiteral, Sendable {
    let paths: [[String]]
    public init(stringLiteral value: String) { paths = [value.components(separatedBy: ".")] }
    public init(arrayLiteral elements: String...) { paths = elements.map { $0.components(separatedBy: ".") } }
    public static func key(_ literal: String) -> Self { Self(paths: [[literal]]) }
    public static func path(_ components: String...) -> Self { Self(paths: [components]) }
    public static func alternatives(_ paths: [String]...) -> Self { Self(paths: paths) }
    /// 每个元素是一个**候选键**，各自按 `.` 拆成路径分量（与数组字面量写法语义一致）。
    /// 供 KeyPath 版 API 把 `from:` 的可变参数转成多个候选键；
    /// 注意与 `alternatives` 不同：后者把每个元素当成一条完整路径。
    public static func aliases(_ literals: [String]) -> Self { Self(paths: literals.map { $0.components(separatedBy: ".") }) }
    private init(paths: [[String]]) { self.paths = paths }
}

public enum YYModelDateStrategy: Sendable {
    /// Recognize seconds, large millisecond timestamps, and common textual formats. Export seconds.
    case native, automatic, secondsSince1970, millisecondsSince1970, microsecondsSince1970, iso8601
}

public enum YYJSONMissingStrategy: Sendable { case inherit, strict, zeroFill }

/// Keys refer to CodingKeys (property names when CodingKeys is synthesized).
/// External rules snapshot this value; there is no process-wide business configuration cache.
/// Captured state in hooks must be thread safe when a decoder is shared.
public struct YYModelConfiguration<Model> {
    public var mapper: [String: YYModelKey]
    public var blacklist: [String]
    public var whitelist: [String]?
    public var requiredProperties: [String]
    public var defaultValues: [String: Any]
    public var dateStrategy: YYModelDateStrategy
    public var missingStrategy: YYJSONMissingStrategy = .inherit
    public var fieldDateStrategies: [String: YYModelDateStrategy] = [:]
    /// Properties whose array elements are decoded leniently: a failing element is
    /// skipped (and recorded in `YYModelLossReport`) instead of failing the whole array.
    /// Empty by default — strict, matching Foundation.
    public var lossyProperties: [String] = []
    /// Properties with a registered fallback value. See `fallback(_:to:)`:
    /// unlike `defaultValues`, this also covers a value that exists but cannot be decoded.
    public var fallbackValues: [String: Any] = [:]
    /// Typed business defaults from the KeyPath `default(_:to:)` API (R5). Handed back
    /// to the decoded property verbatim — no JSON reinterpretation. `defaultValues`
    /// holds their JSON snapshots for Decoder-consuming access paths.
    public var typedDefaultValues: [String: Any] = [:]
    /// Typed hooks do not request or materialize a raw JSON dictionary.
    public var validate: ((Model) throws -> Void)?
    public var transform: ((inout Model) throws -> Void)?
    public var willTransform: (([String: Any]) throws -> [String: Any]?)?
    public var didTransform: ((inout Model, [String: Any]) throws -> Bool)?
    public var transformTo: ((Model, inout [String: Any]) throws -> Bool)?
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
        let tree = try YYJSONEncoder(mode: .legacy).encodeTree(self)
        guard let dictionary = tree.raw as? [String: Any] else { throw YYModelFailure.invalidObject("Model must export an object") }
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
        try YYJSONDecoder(mode: .legacy).decode(type, from: json)
    }
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        try YYJSONEncoder(mode: .legacy).encode(value)
    }
}

enum YYModelFailure: Error, CustomStringConvertible {
    case invalidObject(String)
    var description: String { switch self { case .invalidObject(let message): return message } }
}
