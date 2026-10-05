import Foundation
import YYModelSwift

enum Kind: String, Codable { case ready }
struct EnumValue: Codable { var value: Kind }
struct OptionalEnum: Codable { var value: Kind? }
struct Child: Codable { var value: Int }
struct OptionalChild: Codable { var value: Child? }
struct DateValue: Codable { var value: Date }
struct OptionalDate: Codable { var value: Date? }
struct Parent: Codable { var child: Child }
struct FallbackDirect: Decodable { var value: Int }
struct FallbackContains: Decodable {
    var value: Int
    enum K: String, CodingKey { case value }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        value = c.contains(.value) ? try c.decode(Int.self, forKey: .value) : -1
    }
}
struct FallbackNil: Decodable {
    var value: Int
    enum K: String, CodingKey { case value }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        value = try c.decodeNil(forKey: .value) ? -1 : c.decode(Int.self, forKey: .value)
    }
}
struct Group: Codable { var child: Child; var items: [Child] }
struct NestedGroup: Codable { var group: Group }
struct NumberKey: Codable, Hashable, CodingKeyRepresentable {
    var id: Int
    struct Key: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue; intValue = Int(stringValue) }
        init?(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
    }
    var codingKey: any CodingKey { Key(intValue: id)! }
    init?<K: CodingKey>(codingKey: K) {
        guard let id = codingKey.intValue else { return nil }
        self.id = id
    }
}
struct DictionaryValue: Codable { var value: [NumberKey: Int] }
struct Config: Sendable { var unit: String }
struct Reading: Codable, DecodableWithConfiguration, EncodableWithConfiguration {
    typealias DecodingConfiguration = Config
    typealias EncodingConfiguration = Config
    var value: Int
    var unit: String
    enum K: String, CodingKey { case value, unit }
    init(value: Int, unit: String) { self.value = value; self.unit = unit }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        value = try c.decode(Int.self, forKey: .value); unit = "plain"
    }
    init(from decoder: Decoder, configuration: Config) throws {
        let c = try decoder.container(keyedBy: K.self)
        value = try c.decode(Int.self, forKey: .value); unit = configuration.unit
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self); try c.encode(value, forKey: .value)
    }
    func encode(to encoder: Encoder, configuration: Config) throws {
        var c = encoder.container(keyedBy: K.self); try c.encode(value, forKey: .value)
        try c.encode(configuration.unit, forKey: .unit)
    }
}

@main struct CompositionConsumer {
    static func main() throws {
        var rows: [[String: Any]] = []
        func observe(_ name: String, expected: Any, _ body: () throws -> Any) {
            do { rows.append(["name": name, "expected": expected, "result": try body()]) }
            catch { rows.append(["name": name, "expected": expected, "error": String(describing: error)]) }
        }
        let empty = Data("{}".utf8)
        observe("enum-default-control", expected: "ready") {
            let rules = try YYJSONRules().forType(EnumValue.self) { $0.default(\.value, to: .ready) }
            return try YYJSONDecoder.compatible(rules: rules).decode(EnumValue.self, from: empty).value.rawValue
        }
        observe("optional-enum-default", expected: "ready") {
            let rules = try YYJSONRules().forType(OptionalEnum.self) { $0.default(\.value, to: .ready) }
            return try YYJSONDecoder.compatible(rules: rules).decode(OptionalEnum.self, from: empty).value?.rawValue ?? "nil"
        }
        observe("optional-child-default", expected: 7) {
            let rules = try YYJSONRules().forType(OptionalChild.self) { $0.default(\.value, to: Child(value: 7)) }
            return try YYJSONDecoder.compatible(rules: rules).decode(OptionalChild.self, from: empty).value?.value ?? -1
        }
        observe("optional-date-default", expected: 7) {
            let rules = try YYJSONRules().forType(OptionalDate.self) { $0.default(\.value, to: Date(timeIntervalSince1970: 7)) }
            return try YYJSONDecoder.compatible(rules: rules).decode(OptionalDate.self, from: empty).value?.timeIntervalSince1970 ?? -1
        }
        observe("optional-nil-default-control", expected: true) {
            let rules = try YYJSONRules().forType(OptionalEnum.self) { $0.default(\.value, to: nil) }
            return try YYJSONDecoder.compatible(rules: rules).decode(OptionalEnum.self, from: empty).value == nil
        }
        for strategy in ["deferred", "seconds", "milliseconds", "iso8601", "automatic"] {
            observe("date-default-" + strategy, expected: 7) {
                let rules = try YYJSONRules().forType(DateValue.self) {
                    $0.default(\.value, to: Date(timeIntervalSince1970: 7))
                    if strategy == "milliseconds" { $0.fieldDateStrategies = ["value": .millisecondsSince1970] }
                    if strategy == "iso8601" { $0.fieldDateStrategies = ["value": .iso8601] }
                    if strategy == "automatic" { $0.fieldDateStrategies = ["value": .automatic] }
                }
                var decoder = YYJSONDecoder.compatible(rules: rules)
                if strategy == "seconds" { decoder.dateDecodingStrategy = .secondsSince1970 }
                return try decoder.decode(DateValue.self, from: empty).value.timeIntervalSince1970
            }
        }
        observe("child-default-with-child-mapping", expected: 7) {
            let rules = try YYJSONRules().forType(Child.self) { $0.mapper = ["value": .key("v")] }
                .forType(Parent.self) { $0.default(\.child, to: Child(value: 7)) }
            return try YYJSONDecoder.compatible(rules: rules).decode(Parent.self, from: empty).child.value
        }
        let keyedData = Data(#"{"value":{"7":9}}"#.utf8)
        observe("representable-key-foundation-control", expected: 9) {
            return try JSONDecoder().decode(DictionaryValue.self, from: keyedData).value.first!.value
        }
        for raw in [false, true] {
            observe("representable-key-yy-\(raw)", expected: 9) {
                let source: Any = raw ? ["value": ["7": 9]] : keyedData
                return try YYJSONDecoder.compatible().decode(DictionaryValue.self, from: source).value.first!.value
            }
        }
        let config = Config(unit: "K")
        let mapped = try YYJSONRules().forType(Reading.self) { $0.mapper = ["value": .key("v")] }
        let alias = Data(#"{"v":7}"#.utf8)
        observe("configured-mapping-ordinary-control", expected: 7) {
            try YYJSONDecoder.compatible(rules: mapped).decode(Reading.self, from: alias).value
        }
        observe("configured-mapping", expected: 7) {
            try YYJSONDecoder.compatible(rules: mapped).decode(Reading.self, from: alias, configuration: config).value
        }
        let rejection = try YYJSONRules().forType(Reading.self) { $0.validate = { _ in throw NSError(domain: "review-validation", code: 1) } }
        let seven = Data(#"{"value":7}"#.utf8)
        observe("configured-validation-ordinary-control", expected: "review-validation error") {
            try YYJSONDecoder.compatible(rules: rejection).decode(Reading.self, from: seven).value
        }
        observe("configured-validation", expected: "review-validation error") {
            try YYJSONDecoder.compatible(rules: rejection).decode(Reading.self, from: seven, configuration: config).value
        }
        observe("configured-encoding-ordinary-control", expected: #"{"v":7}"#) {
            try YYJSONEncoder(mode: .compatible, rules: mapped).encodeString(Reading(value: 7, unit: "K"))
        }
        observe("configured-encoding", expected: #"{"v":7,"unit":"K"}"#) {
            String(decoding: try YYJSONEncoder(mode: .compatible, rules: mapped).encode(Reading(value: 7, unit: "K"), configuration: config), as: UTF8.self)
        }
        let fb = try YYJSONRules().forType(FallbackDirect.self) { $0.fallback(\.value, to: 7) }
            .forType(FallbackContains.self) { $0.fallback(\.value, to: 7) }
            .forType(FallbackNil.self) { $0.fallback(\.value, to: 7) }
        let fd = YYJSONDecoder.compatible(rules: fb)
        observe("fallback-synthesized-control", expected: 7) { try fd.decode(FallbackDirect.self, from: empty).value }
        observe("fallback-contains", expected: 7) { try fd.decode(FallbackContains.self, from: empty).value }
        observe("fallback-decodeNil", expected: 7) { try fd.decode(FallbackNil.self, from: empty).value }
        observe("nested-lossy-registration", expected: "configuration error") {
            _ = try YYJSONRules().forType(NestedGroup.self) { $0.lossy(\.group.items) }; return "accepted"
        }
        observe("nested-fallback-registration", expected: "configuration error") {
            _ = try YYJSONRules().forType(NestedGroup.self) { $0.fallback(\.group.child.value, to: 7) }; return "accepted"
        }
        try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        print(String(decoding: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]), as: UTF8.self))
    }
}
