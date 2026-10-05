import Foundation
import YYModelSwift

// String→number coercion contract (C②):
//  - "7" → Int 7, "7.5" → Double 7.5 (compatible mode).
//  - unparseable numeric string → typeMismatch at the property (strict).
struct SN: Codable { var n: Int; var d: Double }

@main struct StringNumberConsumer {
    static func main() throws {
        var rows: [[String: Any]] = []
        func observe(_ name: String, _ body: () throws -> Any) {
            do { rows.append(["name": name, "result": try body()]) }
            catch { rows.append(errorRow(name, error)) }
        }
        func data(_ text: String) -> Data { Data(text.utf8) }
        observe("string-to-int") { try YYJSONDecoder.compatible().decode(SN.self, from: data(#"{"n":"7","d":1}"#)).n }
        observe("string-to-double") { try YYJSONDecoder.compatible().decode(SN.self, from: data(#"{"n":1,"d":"7.5"}"#)).d }
        observe("string-to-int64-oob") { try YYJSONDecoder.compatible().decode(SN.self, from: data(#"{"n":"9223372036854775808","d":1}"#)).n }
        observe("int-invalid-string") { try YYJSONDecoder.compatible().decode(SN.self, from: data(#"{"n":"abc","d":1}"#)).n }

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