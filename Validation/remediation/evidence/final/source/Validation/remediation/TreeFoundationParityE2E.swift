import Foundation
import YYModelSwift
private struct Box<T: Encodable>: Encodable { let value: T }
private struct Empty: Encodable { func encode(to encoder: Encoder) throws {} }
private struct EmptyObject: Encodable { func encode(to encoder: Encoder) throws { _ = encoder.container(keyedBy: TreeKey.self) } }
private struct Dates: Encodable { let stamp: Date }
private struct TreeKey: CodingKey { let stringValue: String; var intValue: Int? { nil }; init(_ s: String) { stringValue=s }; init?(stringValue: String) { self.init(stringValue) }; init?(intValue: Int) { return nil } }
private struct Floats: Encodable { let value: Float; let negativeZero: Float; let tiny: Float }
@main private struct TreeFoundationParityE2E {
    static func main() throws {
        var rows: [[String: Any]] = []
        func check(_ name: String, _ body: () throws -> (String, String)) {
            do { let (expected, actual) = try body(); rows.append(["scenario": name, "expected": expected, "actual": actual, "passed": expected == actual]) }
            catch { rows.append(["scenario": name, "actual": String(describing: error), "passed": false]) }
        }
        func text(_ value: Any) throws -> String {
            String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys]), as: UTF8.self)
        }
        func parity<T: Encodable>(_ value: T, date: JSONEncoder.DateEncodingStrategy = .secondsSince1970,
                                  data: JSONEncoder.DataEncodingStrategy = .base64, mode: YYJSONMode = .native) throws -> (String, String) {
            let native = JSONEncoder(); native.dateEncodingStrategy = date; native.dataEncodingStrategy = data
            var yy = YYJSONEncoder(mode: mode); yy.dateEncodingStrategy = date; yy.dataEncodingStrategy = data
            let expected = try JSONSerialization.jsonObject(with: native.encode(value), options: [.fragmentsAllowed])
            return try (text(expected), text(yy.encodeJSONObject(value)))
        }
        let date = Date(timeIntervalSince1970: 7.125)
        let data = Data([1, 2, 3])
        check("tree-root-date-seconds-native") { try parity(date) }
        check("tree-root-data-base64-native") { try parity(data) }
        check("tree-root-date-seconds-compatible") { try parity(date, mode: .compatible) }
        check("tree-root-data-base64-compatible") { try parity(data, mode: .compatible) }
        check("tree-string-dictionary-date") { try parity(Box(value: ["stamp": date])) }
        check("tree-int-dictionary-date") { try parity(Box(value: [7: date])) }
        check("tree-dictionary-data-base64") { try parity(Box(value: ["blob": data])) }
        check("tree-root-alternating-key-value-array") { try parity([UUID(uuidString: "00000000-0000-0000-0000-000000000007")!: 9]) }
        check("tree-nested-alternating-key-value-array") { try parity(Box(value: [UUID(uuidString: "00000000-0000-0000-0000-000000000007")!: 9])) }
        check("tree-native-iso8601-format") { try parity(Box(value: date), date: .iso8601) }
        check("tree-root-empty-encodable-rejected-control") {
            let nativeRejected: Bool
            do { _ = try JSONEncoder().encode(Empty()); nativeRejected = false } catch { nativeRejected = true }
            let yyRejected: Bool
            do { _ = try YYJSONEncoder.native().encodeJSONObject(Empty()); yyRejected = false } catch { yyRejected = true }
            return (String(nativeRejected), String(yyRejected))
        }
        check("tree-hook-empty-encodable") {
            let rules = try YYJSONRules().forType(Empty.self) { $0.transformTo = { _, _ in true } }
            do { _ = try YYJSONEncoder.compatible(rules: rules).encode(Empty()); return ("rejected", "accepted") }
            catch { return ("rejected", "rejected") }
        }
        check("tree-hook-float-spelling-and-negative-zero") {
            let value = Floats(value: Float(bitPattern: 1065353217), negativeZero: -Float.zero, tiny: .leastNonzeroMagnitude)
            let native = JSONEncoder(); native.outputFormatting = .sortedKeys
            let rules = try YYJSONRules().forType(Floats.self) { $0.transformTo = { _, _ in true } }
            var yy = YYJSONEncoder.compatible(rules: rules); yy.outputFormatting = .sortedKeys
            return (String(decoding: try native.encode(value), as: UTF8.self), String(decoding: try yy.encode(value), as: UTF8.self))
        }
        check("tree-root-dictionary-custom-key-bypass") {
            let native = JSONEncoder(); native.keyEncodingStrategy = .custom { TreeKey("prefix_" + $0.last!.stringValue) }
            var yy = YYJSONEncoder.native(); yy.keyEncodingStrategy = native.keyEncodingStrategy
            let value = ["dataKey": 7]
            return try (text(JSONSerialization.jsonObject(with: native.encode(value))), text(yy.encodeJSONObject(value)))
        }
        check("tree-int-dictionary-date-callback-key-intValue") {
            let strategy = JSONEncoder.DateEncodingStrategy.custom { _, target in
                var c = target.singleValueContainer(); try c.encode("int=\(target.codingPath.last?.intValue.map(String.init) ?? "nil")")
            }
            return try parity(Box(value: [7: date]), date: strategy)
        }
        check("tree-nested-export-hook-callback-prefix") {
            let value = Box(value: Box(value: Dates(stamp: date)))
            let strategy = JSONEncoder.DateEncodingStrategy.custom { _, target in
                var c = target.singleValueContainer(); try c.encode(target.codingPath.map(\.stringValue).joined(separator: "."))
            }
            let native = JSONEncoder(); native.dateEncodingStrategy = strategy
            let rules = try YYJSONRules().forType(Box<Box<Dates>>.self) { $0.transformTo = { _, _ in true } }
                .forType(Box<Dates>.self) { $0.transformTo = { _, _ in true } }
                .forType(Dates.self) { $0.transformTo = { _, _ in true } }
            var yy = YYJSONEncoder.compatible(rules: rules); yy.dateEncodingStrategy = strategy
            return try (text(JSONSerialization.jsonObject(with: native.encode(value))), text(JSONSerialization.jsonObject(with: yy.encode(value))))
        }
        check("tree-array-date-callback-index-key") {
            let strategy = JSONEncoder.DateEncodingStrategy.custom { _, target in
                var c = target.singleValueContainer()
                try c.encode("\(target.codingPath.last!.stringValue)|\(target.codingPath.last!.intValue!)")
            }
            return try parity([date], date: strategy)
        }
        check("tree-nested-empty-encodable-object-control") { try parity(Box(value: Empty())) }
        check("tree-explicit-empty-keyed-object-control") { try parity(EmptyObject()) }
        check("tree-date-custom-empty-object-control") { try parity(date, date: .custom { _, _ in }) }
        check("tree-data-custom-empty-object-control") { try parity(data, data: .custom { _, _ in }) }
        check("tree-date-infinity-rejection-control") {
            let native = JSONEncoder(); native.dateEncodingStrategy = .secondsSince1970
            native.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "INF", negativeInfinity: "-INF", nan: "NaN")
            var yy = YYJSONEncoder.native(); yy.dateEncodingStrategy = native.dateEncodingStrategy
            yy.nonConformingFloatEncodingStrategy = native.nonConformingFloatEncodingStrategy
            let value = Date(timeIntervalSince1970: .infinity)
            let expected: Bool; do { _ = try native.encode(value); expected = false } catch { expected = true }
            let actual: Bool; do { _ = try yy.encodeJSONObject(value); actual = false } catch { actual = true }
            return (String(expected), String(actual))
        }
        try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
