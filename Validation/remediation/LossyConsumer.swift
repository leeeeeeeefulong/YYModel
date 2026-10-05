import Foundation
import YYModelSwift

// Lossy array contract (C②):
//  - lossy(\.field): bad elements are skipped and recorded in YYModelLossReport.
//  - without lossy, a bad element fails the whole array with a typeMismatch.
struct LResp: Codable { var values: [Int] }

@main struct LossyConsumer {
    static func main() throws {
        var rows: [[String: Any]] = []
        func observe(_ name: String, _ body: () throws -> Any) {
            do { rows.append(["name": name, "result": try body()]) }
            catch { rows.append(errorRow(name, error)) }
        }
        func data(_ text: String) -> Data { Data(text.utf8) }
        let lossyRules = try YYJSONRules().forType(LResp.self) { $0.lossy(\.values) }
        observe("lossy-skips-bad") {
            let report = YYModelLossReport()
            var d = YYJSONDecoder.compatible(rules: lossyRules)
            d.userInfo[YYModelLossReport.key] = report
            let v = try d.decode(LResp.self, from: data(#"{"values":[1,"bad",3]}"#))
            return "\(v.values.map(String.init).joined(separator: ","))|\(report.losses.count)"
        }
        observe("lossy-all-bad") {
            let report = YYModelLossReport()
            var d = YYJSONDecoder.compatible(rules: lossyRules)
            d.userInfo[YYModelLossReport.key] = report
            let v = try d.decode(LResp.self, from: data(#"{"values":["x","y"]}"#))
            return "\(v.values.map(String.init).joined(separator: ","))|\(report.losses.count)"
        }
        observe("lossy-not-enabled") { try YYJSONDecoder.compatible().decode(LResp.self, from: data(#"{"values":[1,"bad",3]}"#)) }

        try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}

/// Structured error fields (C2): consumers emit errorType / errorPath (Foundation codingPath
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