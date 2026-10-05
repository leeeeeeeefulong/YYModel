import Foundation
import YYModelSwift

// Presence contract (C②):
//  - value/null/absent three-state decoding in compatible/legacy mode.
//  - compatible encode: .absent omits the key entirely; .null writes null.
//  - native mode: .absent/.null both encode as null; missing key throws keyNotFound.
struct PDirect: Codable { var file: YYModelPresence<String> }

@main struct PresenceConsumer {
    static func main() throws {
        var rows: [[String: Any]] = []
        func observe(_ name: String, _ body: () throws -> Any) {
            do { rows.append(["name": name, "result": try body()]) }
            catch { rows.append(errorRow(name, error)) }
        }
        func data(_ text: String) -> Data { Data(text.utf8) }
        let compatible = YYJSONDecoder.compatible()
        observe("presence-compatible-value") { try compatible.decode(PDirect.self, from: data(#"{"file":"x.txt"}"#)).file.description }
        observe("presence-compatible-null") { try compatible.decode(PDirect.self, from: data(#"{"file":null}"#)).file.description }
        observe("presence-compatible-absent") { try compatible.decode(PDirect.self, from: data(#"{}"#)).file.description }
        observe("presence-compatible-encode-absent") { let v = PDirect(file: .absent); return String(decoding: try YYJSONEncoder.compatible().encode(v), as: UTF8.self) }
        observe("presence-compatible-encode-null") { let v = PDirect(file: .null); return String(decoding: try YYJSONEncoder.compatible().encode(v), as: UTF8.self) }
        observe("presence-native-encode-absent") { let v = PDirect(file: .absent); return String(decoding: try YYJSONEncoder(mode: .native).encode(v), as: UTF8.self) }
        observe("presence-native-encode-null") { let v = PDirect(file: .null); return String(decoding: try YYJSONEncoder(mode: .native).encode(v), as: UTF8.self) }
        observe("presence-native-decode-absent") { try YYJSONDecoder(mode: .native).decode(PDirect.self, from: data(#"{}"#)).file.description }

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