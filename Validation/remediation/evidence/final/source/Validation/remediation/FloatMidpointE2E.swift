import Foundation
import YYModelSwift
private struct Value: Codable { var value: Float }
@main private struct FloatMidpointE2E {
    static func main() throws {
        var rows: [[String: Any]] = []
        for token in ["16777217.000000000000000000000000000000000000000001",
                      "-16777217.000000000000000000000000000000000000000001",
                      "9007199791611904.000000000000000000000000000001"] {
            for hook in [false, true] {
                let expected = String(Float(token)!.bitPattern)
                let name = "float-integer-midpoint-\(token)-hook-\(hook)"
                do {
                    let rules = try YYJSONRules().forType(Value.self) { if hook { $0.willTransform = { $0 } } }
                    let result = try YYJSONDecoder.compatible(rules: rules).decode(Value.self, from: Data("{\"value\":\(token)}".utf8))
                    let actual = String(result.value.bitPattern)
                    rows.append(["scenario": name, "expected": expected, "actual": actual, "passed": expected == actual])
                } catch {
                    rows.append(["scenario": name, "expected": expected, "actual": String(describing: error), "passed": false])
                }
            }
        }
        try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys, .prettyPrinted])
            .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
