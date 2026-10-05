import Foundation
import YYModelSwift

// Blacklist/whitelist contract (C②):
//  - blacklist/whitelist 同时控制输入和输出（编码排除、解码视为缺失）。
//  - 被排除的非 Optional 字段仍走 missing 策略：strict → keyNotFound，
//    zeroFill → 0。Optional 被排除 → nil。
//  - 显式 default 只作用于「允许」字段；被排除字段注册 default 仍视为缺失
//    （SWIFT-MODEL.md: defaultValues 对缺失的允许字段生效）。
//  - 空白名单在配置时抛 YYJSONRulesError.emptyWhitelist。
struct W: Codable { var a: Int; var b: Int; var c: Int? }
struct OnlyA: Codable { var a: Int; var b: Int; var c: Int? }
struct WO: Codable { var a: Int; var c: Int? }

@main struct WConsumer {
    static func main() throws {
        var rows: [[String: Any]] = []
        func observe(_ name: String, _ body: () throws -> Any) {
            do { rows.append(["name": name, "result": try body()]) }
            catch { rows.append(errorRow(name, error)) }
        }
        func data(_ text: String) -> Data { Data(text.utf8) }
        let wb = try YYJSONRules().forType(W.self) { $0.blacklist = ["b"] }
        let wl = try YYJSONRules().forType(OnlyA.self) { $0.whitelist = ["a"] }
        let wo = try YYJSONRules().forType(WO.self) { $0.blacklist = ["c"] }

        observe("blacklist-encode") { String(decoding: try YYJSONEncoder.compatible(rules: wb).encode(W(a: 1, b: 2, c: 3)), as: UTF8.self) }
        observe("blacklist-decode-compatible") { String(describing: try YYJSONDecoder.compatible(rules: wb).decode(W.self, from: data(#"{"a":1,"b":2}"#))) }
        observe("blacklist-decode-legacy") { let v = try YYJSONDecoder.legacy(rules: wb).decode(W.self, from: data(#"{"a":1,"b":2}"#)); return "\(v.a)|\(v.b)|\(String(describing: v.c))" }
        observe("blacklist-optional-decode-compatible") { let v = try YYJSONDecoder.compatible(rules: wo).decode(WO.self, from: data(#"{"a":1,"c":3}"#)); return "\(v.a)|\(String(describing: v.c))" }
        observe("whitelist-encode") { String(decoding: try YYJSONEncoder.compatible(rules: wl).encode(OnlyA(a: 1, b: 2, c: 3)), as: UTF8.self) }
        observe("whitelist-decode-compatible") { let v = try YYJSONDecoder.compatible(rules: wl).decode(OnlyA.self, from: data(#"{"a":1,"b":2,"c":3}"#)); return "\(v.a)|\(v.b)|\(String(describing: v.c))" }
        observe("empty-whitelist-rejected") { try YYJSONRules().forType(OnlyA.self) { $0.whitelist = [] } }

        let wbDefault = try YYJSONRules().forType(W.self) { $0.blacklist = ["b"]; $0.defaultValues = ["b": 7] }
        observe("blacklist-default-does-not-rescue") { let v = try YYJSONDecoder.compatible(rules: wbDefault).decode(W.self, from: data(#"{"a":1}"#)); return "\(v.a)|\(v.b)" }

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