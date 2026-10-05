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
            catch { rows.append(["name": name, "error": String(describing: error)]) }
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
