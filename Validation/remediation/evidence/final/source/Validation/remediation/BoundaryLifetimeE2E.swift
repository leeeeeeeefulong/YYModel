import Foundation
import YYModelSwift
private struct Value: Codable { var value: Double }
private final class Capture: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String: Any] = [:]
    func save(_ input: [String: Any]) { lock.lock(); stored = input; lock.unlock() }
    var object: [String: Any] { lock.lock(); defer { lock.unlock() }; return stored }
}
@main private struct BoundaryLifetimeE2E {
    static func main() throws {
        var rows: [[String: Any]] = []
        for will in [false, true] {
            let capture = Capture()
            let rules = try YYJSONRules().forType(Value.self) { rule in
                if will { rule.willTransform = { capture.save($0); return $0 } }
                else { rule.didTransform = { _, input in capture.save(input); return true } }
            }
            let first = try YYJSONDecoder.compatible(rules: rules).decode(Value.self,
                from: Data("{\"value\":1.000000000000000111022302462515654042363166809082031251}".utf8))
            let second = try YYJSONDecoder.compatible().decode(Value.self, from: capture.object)
            let expected = "4607182418800017409,4607182418800017409"
            let actual = "\(first.value.bitPattern),\(second.value.bitPattern)"
            rows.append(["scenario": "cached-hook-number-cross-invocation-\(will)",
                         "expected": expected, "actual": actual, "passed": expected == actual])
        }
        try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys, .prettyPrinted])
            .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
