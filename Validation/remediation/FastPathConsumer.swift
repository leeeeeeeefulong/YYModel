import Foundation
import YYModelSwift
struct Integer: Codable { var value: Int }
struct Text: Codable { var value: String }
struct Boolean: Codable { var value: Bool }
struct Floating: Codable { var value: Double }
@main struct FastPathConsumer {
    static func main() throws {
        var rows: [[String: Any]] = []
        func observe(_ name: String, _ body: () throws -> Any) {
            do { rows.append(["name": name, "result": try body()]) }
            catch { rows.append(errorRow(name, error)) }
        }
        for null in [false, true] {
            let object: [String: Any] = null ? ["value": NSNull()] : [:]
            for raw in [false, true] {
                let source: Any = raw ? object : try JSONSerialization.data(withJSONObject: object)
                let decoder = YYJSONDecoder(mode: .compatible)
                let label = "null=\(null)-raw=\(raw)"
                observe("int-" + label) { try decoder.decode(Integer.self, from: source).value }
                observe("string-" + label) { try decoder.decode(Text.self, from: source).value }
                observe("bool-" + label) { try decoder.decode(Boolean.self, from: source).value }
                observe("double-" + label) { try decoder.decode(Floating.self, from: source).value }
            }
        }
        let defaults = try YYJSONRules().forType(Integer.self) { $0.defaultValues = ["value": 7] }
            .forType(Text.self) { $0.defaultValues = ["value": "fallback"] }
        for raw in [false, true] {
            let source: Any = raw ? [:] as [String: Any] : Data("{}".utf8)
            let decoder = YYJSONDecoder(mode: .compatible, rules: defaults)
            observe("default-int-raw=\(raw)") { try decoder.decode(Integer.self, from: source).value }
            observe("default-string-raw=\(raw)") { try decoder.decode(Text.self, from: source).value }
        }
        let hook = try YYJSONRules().forType(Integer.self) { $0.willTransform = { $0 } }
        observe("data-with-willTransform-missing") {
            try YYJSONDecoder(mode: .compatible, rules: hook).decode(Integer.self, from: Data("{}".utf8)).value
        }
        observe("data-with-willTransform-null") {
            try YYJSONDecoder(mode: .compatible, rules: hook).decode(Integer.self, from: Data(#"{"value":null}"#.utf8)).value
        }
        try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}

/// Structured error fields (C12): consumers emit errorType / errorPath (Foundation codingPath
/// semantics) and errorKey for keyNotFound, so run.py can assert them in the expectations.
func errorRow(_ name: String, _ error: Error) -> [String: Any] {
    var row: [String: Any] = ["name": name, "error": String(describing: error)]
    func put(_ type: String, _ context: DecodingError.Context) {
        row["errorType"] = type; row["errorPath"] = context.codingPath.map(\.stringValue)
    }
    switch error {
    case DecodingError.keyNotFound(let key, let context): put("keyNotFound", context); row["errorKey"] = key.stringValue
    case DecodingError.valueNotFound(_, let context): put("valueNotFound", context)
    case DecodingError.typeMismatch(_, let context): put("typeMismatch", context)
    case DecodingError.dataCorrupted(let context): put("dataCorrupted", context)
    case let rules as YYJSONRulesError:
        row["errorType"] = "YYJSONRulesError." + rules.code.rawValue
        if case .encodingRejected(_, let path, _) = rules { row["errorPath"] = path }
    default: row["errorType"] = String(describing: type(of: error))
    }
    return row
}