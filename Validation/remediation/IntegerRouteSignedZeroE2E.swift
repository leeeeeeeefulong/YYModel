import Foundation
import YYModelSwift
private struct Values: Codable { let big: UInt64; let zero: Double; let array: [Double]; let object: [String: Double] }
@main private struct IntegerRouteSignedZeroE2E {
    static func main() throws {
        var rows: [[String: Any]] = []
        func check(_ name: String, _ expected: String, _ body: () throws -> String) {
            do { let actual = try body(); rows.append(["scenario":name,"expected":expected,"actual":actual,"passed":actual==expected]) }
            catch { rows.append(["scenario":name,"actual":String(describing:error),"passed":false]) }
        }
        var decoder = YYJSONDecoder.compatible(); decoder.numberParsingStrategy = .integerTokens
        for token in ["-0", "-0.0", "-0e0", "0"] {
            let expected = try JSONDecoder().decode(Double.self, from: Data(token.utf8)).bitPattern
            check("integer-route-zero-\(token)", String(expected)) { String(try decoder.decode(Double.self, from: Data(token.utf8)).bitPattern) }
        }
        check("integer-route-nested-zero-and-exact-big", "18446744073709551615|9223372036854775808|9223372036854775808|9223372036854775808") {
            let value = try decoder.decode(Values.self, from: Data(#"{"big":18446744073709551615,"zero":-0,"array":[-0],"object":{"key":-0}}"#.utf8))
            return "\(value.big)|\(value.zero.bitPattern)|\(value.array[0].bitPattern)|\(value.object["key"]!.bitPattern)"
        }
        try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted,.sortedKeys]).write(to: URL(fileURLWithPath:CommandLine.arguments[1]))
    }
}
