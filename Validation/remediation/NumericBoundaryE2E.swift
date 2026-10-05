import Foundation
import YYModelSwift

private struct Signed: Codable { var value: Int64 }
private struct Unsigned: Codable { var value: UInt64 }
private struct Narrow: Codable { var value: Float }
private struct Wide: Codable { var value: Double }

@main private struct NumericBoundaryE2E {
    static func main() throws {
        var rows: [[String: Any]] = []
        func check(_ name: String, _ expected: String, _ body: () throws -> String) {
            do {
                let actual = try body()
                rows.append(["scenario": name, "expected": expected, "actual": actual, "passed": actual == expected])
            } catch {
                rows.append(["scenario": name, "expected": expected, "actual": String(describing: error), "passed": false])
            }
        }
        for hook in [false, true] {
            for text in ["9007199254740991", "9007199254740993", "-9007199254740993", "9223372036854775807", "-9223372036854775808"] {
                let rules = try YYJSONRules().forType(Signed.self) { if hook { $0.willTransform = { $0 } } }
                let decoder = YYJSONDecoder.compatible(rules: rules)
                for raw in [false, true] {
                    check("signed-\(text)-hook-\(hook)-raw-\(raw)", text) {
                        let value = raw
                            ? try decoder.decode(Signed.self, from: ["value": NSNumber(value: Int64(text)!)])
                            : try decoder.decode(Signed.self, from: Data("{\"value\":\(text)}".utf8))
                        return String(value.value)
                    }
                }
            }
            for text in ["9007199254740993", "9223372036854775808", "18446744073709551615"] {
                let rules = try YYJSONRules().forType(Unsigned.self) { if hook { $0.willTransform = { $0 } } }
                let decoder = YYJSONDecoder.compatible(rules: rules)
                for raw in [false, true] {
                    check("unsigned-\(text)-hook-\(hook)-raw-\(raw)", text) {
                        let value = raw
                            ? try decoder.decode(Unsigned.self, from: ["value": NSNumber(value: UInt64(text)!)])
                            : try decoder.decode(Unsigned.self, from: Data("{\"value\":\(text)}".utf8))
                        return String(value.value)
                    }
                }
            }
            for text in ["9007199254740993.0", "9.007199254740993e15"] {
                check("floating-integer-\(text)-hook-\(hook)", "9007199254740993") {
                    let rules = try YYJSONRules().forType(Signed.self) { if hook { $0.willTransform = { $0 } } }
                    return String(try YYJSONDecoder.compatible(rules: rules).decode(Signed.self, from: Data("{\"value\":\(text)}".utf8)).value)
                }
            }
            for text in ["1.401298464324817e-45", "-1.401298464324817e-45", "1.1754943508222875e-38", "3.4028234663852886e38", "1.0000000596046448"] {
                check("float-boundary-\(text)-hook-\(hook)", String(Float(text)!.bitPattern)) {
                    let rules = try YYJSONRules().forType(Narrow.self) { if hook { $0.willTransform = { $0 } } }
                    return String(try YYJSONDecoder.compatible(rules: rules).decode(Narrow.self, from: Data("{\"value\":\(text)}".utf8)).value.bitPattern)
                }
            }
            for text in ["4.9406564584124654e-324", "-4.9406564584124654e-324", "2.2250738585072014e-308", "1.7976931348623157e308"] {
                check("double-boundary-\(text)-hook-\(hook)", String(Double(text)!.bitPattern)) {
                    let rules = try YYJSONRules().forType(Wide.self) { if hook { $0.willTransform = { $0 } } }
                    return String(try YYJSONDecoder.compatible(rules: rules).decode(Wide.self, from: Data("{\"value\":\(text)}".utf8)).value.bitPattern)
                }
            }
        }
        try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys, .prettyPrinted])
            .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
