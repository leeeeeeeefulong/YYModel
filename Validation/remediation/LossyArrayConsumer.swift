import Foundation
import YYModelSwift

// Top-level lossy array entry (D3 / C⑧):
//  - decodeLossyArray skips bad elements into YYModelLossReport at property "(root)".
//  - works from Data / String / Any.
//  - all-bad → empty array with per-index losses.
//  - clean input → no losses.
//  - the ordinary strict decode is unchanged (still fails on a bad element).
struct LElement: Codable { var n: Int }

@main struct LossyArrayConsumer {
    static func main() throws {
        var rows: [[String: Any]] = []
        func observe(_ name: String, _ body: () throws -> Any) {
            do { rows.append(["name": name, "result": try body()]) }
            catch { rows.append(errorRow(name, error)) }
        }
        func data(_ text: String) -> Data { Data(text.utf8) }
        observe("lossy-array-data") {
            let (v, r) = try YYJSONDecoder.compatible().decodeLossyArray([Int].self, from: data(#"[1,"bad",3]"#))
            return "\(v.map(String.init).joined(separator: ","))|\(r.losses.count)"
        }
        observe("lossy-array-string") {
            let (v, r) = try YYJSONDecoder.compatible().decodeLossyArray([Int].self, from: #"[1,"bad",3]"#)
            return "\(v.map(String.init).joined(separator: ","))|\(r.losses.count)"
        }
        observe("lossy-array-raw") {
            let (v, r) = try YYJSONDecoder.compatible().decodeLossyArray([Int].self, from: [1, "bad", 3] as [Any])
            return "\(v.map(String.init).joined(separator: ","))|\(r.losses.count)"
        }
        observe("lossy-array-all-bad") {
            let (v, r) = try YYJSONDecoder.compatible().decodeLossyArray([Int].self, from: data(#"["a","b"]"#))
            return "\(v.map(String.init).joined(separator: ","))|\(r.losses.count)"
        }
        observe("lossy-array-clean") {
            let (v, r) = try YYJSONDecoder.compatible().decodeLossyArray([Int].self, from: data(#"[1,2,3]"#))
            return "\(v.map(String.init).joined(separator: ","))|\(r.losses.count)"
        }
        observe("lossy-array-model") {
            let (v, r) = try YYJSONDecoder.compatible().decodeLossyArray([LElement].self, from: data(#"[{"n":1},{"n":"bad"},{"n":3}]"#))
            return "\(v.map(\.n).map(String.init).joined(separator: ","))|\(r.losses.count)"
        }
        observe("strict-decode-unchanged") { try YYJSONDecoder.compatible().decode([Int].self, from: data(#"[1,"bad",3]"#)) }

        try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}

/// Structured error fields (C①): consumers emit errorType / errorPath (Foundation codingPath
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