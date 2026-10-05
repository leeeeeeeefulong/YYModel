import Foundation
import YYModelSwift

// P2-4: decodeWithReport preserves absorbed losses when it throws. The thrown
// DecodingError keeps its original case/path; YYModelLossReport.attached(from:)
// recovers the report that had been accumulated before the failure.
struct LR2: Codable { var values: [Int]; var count: Int }

@main struct LossyAttachmentConsumer {
    static func main() throws {
        var rows: [[String: Any]] = []
        func observe(_ name: String, _ body: () throws -> Any) {
            do { rows.append(["name": name, "result": try body()]) }
            catch { rows.append(errorRow(name, error)) }
        }
        func data(_ text: String) -> Data { Data(text.utf8) }
        let rules = try YYJSONRules().forType(LR2.self) { $0.lossy(\.values) }
        observe("lossy-then-strict-missing") {
            try YYJSONDecoder.compatible(rules: rules).decodeWithReport(LR2.self, from: data(#"{"values":[1,"bad",3]}"#))
        }
        observe("lossy-then-type-mismatch") {
            try YYJSONDecoder.compatible(rules: rules).decodeWithReport(LR2.self, from: data(#"{"values":[1,"bad",3],"count":"x"}"#))
        }
        observe("clean-with-report") {
            let (v, r) = try YYJSONDecoder.compatible(rules: rules).decodeWithReport(LR2.self, from: data(#"{"values":[1,3],"count":2}"#))
            return "\(v.values.map(String.init).joined(separator: ","))|\(r.losses.count)"
        }

        try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}

/// Structured error fields (C12) + P2-4 attachment recovery: the error row gets an
/// "attached" array listing the property[ index ] entries absorbed before the throw.
func errorRow(_ name: String, _ error: Error) -> [String: Any] {
    var row: [String: Any] = ["name": name, "error": String(describing: error)]
    if let report = YYModelLossReport.attached(from: error) {
        row["attachedLosses"] = report.losses.count
        row["attached"] = report.losses.map { "\($0.property)[\($0.index)]" }
    }
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