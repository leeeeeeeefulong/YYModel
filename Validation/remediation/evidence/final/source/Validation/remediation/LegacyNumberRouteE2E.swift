import Foundation
import YYModelSwift
private struct Value: Codable { var id: Int64; var maximum: UInt64 }
@main private struct LegacyNumberRouteE2E {
    static func main() throws {
        var rows: [[String: Any]] = []
        func check(_ name: String, _ expected: String, _ body: () throws -> String) {
            do { let actual = try body(); rows.append(["scenario": name, "expected": expected, "actual": actual, "passed": actual == expected]) }
            catch { rows.append(["scenario": name, "expected": expected, "actual": String(describing: error), "passed": false]) }
        }
        for strategy in [YYJSONNumberParsingStrategy.automatic, .foundation, .integerTokens] {
            for hook in [false, true] {
                check("integer-route-\(strategy)-hook-\(hook)", "9007199254740993,18446744073709551615") {
                    let rules = try YYJSONRules().forType(Value.self) { if hook { $0.willTransform = { $0 } } }
                    var d = YYJSONDecoder.compatible(rules: rules); d.numberParsingStrategy = strategy
                    let value = try d.decode(Value.self, from: Data("{\"id\":9007199254740993,\"maximum\":18446744073709551615}".utf8))
                    return "\(value.id),\(value.maximum)"
                }
            }
        }
        check("integer-route-fragment", "9007199254740993") {
            var d = YYJSONDecoder.compatible(); d.numberParsingStrategy = .integerTokens
            return String(try d.decode(Int64.self, from: Data("9007199254740993".utf8)))
        }
        check("integer-route-string-fragment", "hello") {
            var d = YYJSONDecoder.compatible(); d.numberParsingStrategy = .integerTokens
            return try d.decode(String.self, from: Data("\"hello\"".utf8))
        }
        check("integer-route-json5-braceless", "9007199254740993,18446744073709551615") {
            var d = YYJSONDecoder.compatible(); d.numberParsingStrategy = .integerTokens
            d.allowsJSON5 = true; d.assumesTopLevelDictionary = true
            let value = try d.decode(Value.self, from: Data("'id':9007199254740993,'maximum':18446744073709551615".utf8))
            return "\(value.id),\(value.maximum)"
        }
        check("native-ignores-enhanced-number-route", "9007199254740993") {
            var d = YYJSONDecoder.native(); d.numberParsingStrategy = .integerTokens
            return String(try d.decode(Int64.self, from: Data("9007199254740993".utf8)))
        }
        try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys, .prettyPrinted])
            .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
