import Foundation
import YYModelSwift

// Transform hooks contract (C②):
//  - transformTo rewrites the exported object (value + added keys) once.
//  - transformTo returning false → YYJSONRulesError.transformToRejected (encode path).
//  - willTransform returning nil → dataCorrupted (decode path).
//  - didTransform returning false → dataCorrupted (decode path).
struct TNum: Codable { var n: Int }
struct TWrap: Codable { var item: TNum }

@main struct TransformConsumer {
    static func main() throws {
        var rows: [[String: Any]] = []
        func observe(_ name: String, _ body: () throws -> Any) {
            do { rows.append(["name": name, "result": try body()]) }
            catch { rows.append(errorRow(name, error)) }
        }
        func data(_ text: String) -> Data { Data(text.utf8) }
        let toMap = try YYJSONRules().forType(TNum.self) { $0.transformTo = { _, dict in dict["n"] = 42; dict["extra"] = "added"; return true } }
        observe("transformTo-rewrites") { String(decoding: try YYJSONEncoder.compatible(rules: toMap).encode(TWrap(item: TNum(n: 1))), as: UTF8.self) }
        let toFalse = try YYJSONRules().forType(TNum.self) { $0.transformTo = { _, _ in false } }
        observe("transformTo-false") { String(decoding: try YYJSONEncoder.compatible(rules: toFalse).encode(TWrap(item: TNum(n: 1))), as: UTF8.self) }
        let willNil = try YYJSONRules().forType(TNum.self) { $0.willTransform = { _ in nil } }
        observe("willTransform-nil") { try YYJSONDecoder.compatible(rules: willNil).decode(TWrap.self, from: data(#"{"item":{"n":1}}"#)) }
        let didFalse = try YYJSONRules().forType(TNum.self) { $0.didTransform = { _, _ in false } }
        observe("didTransform-false") { try YYJSONDecoder.compatible(rules: didFalse).decode(TWrap.self, from: data(#"{"item":{"n":1}}"#)) }

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