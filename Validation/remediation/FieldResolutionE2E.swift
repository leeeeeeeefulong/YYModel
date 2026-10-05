import Foundation
import YYModelSwift

private struct OptionalMapped: Codable { var value: Int? }
private struct Child: Codable { var x: Int }
private struct NestedDefault: Decodable {
    var value: Child
    enum K: String, CodingKey { case value, x }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        value = Child(x: try c.nestedContainer(keyedBy: K.self, forKey: .value).decode(Int.self, forKey: .x))
    }
}
private struct NullAccept: Codable {
    var accepted: Bool
    init(from decoder: Decoder) throws { accepted = try decoder.singleValueContainer().decodeNil() }
    func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encodeNil() }
}
private struct NullParent: Codable { var value: NullAccept }
private struct List: Codable { var value: [Int] }

@main private struct FieldResolutionE2E {
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
        for raw in [false, true] {
            check("optional-mapper-invalid-shape-\(raw)", "shape-error") {
                let rules = try YYJSONRules().forType(OptionalMapped.self) { $0.mapper = ["value": "physical.value"] }
                let d = YYJSONDecoder.compatible(rules: rules)
                do {
                    _ = raw ? try d.decode(OptionalMapped.self, from: ["physical": 3])
                            : try d.decode(OptionalMapped.self, from: Data("{\"physical\":3}".utf8))
                    return "accepted"
                } catch DecodingError.typeMismatch { return "shape-error" }
            }
            check("typed-default-nested-container-\(raw)", "7") {
                let rules = try YYJSONRules().forType(NestedDefault.self) { $0.default(\.value, to: Child(x: 7)) }
                let d = YYJSONDecoder.compatible(rules: rules)
                let result = raw ? try d.decode(NestedDefault.self, from: [:] as [String: Any])
                                 : try d.decode(NestedDefault.self, from: Data("{}".utf8))
                return String(result.value.x)
            }
            check("keyed-user-model-consumes-null-\(raw)", "true") {
                let d = YYJSONDecoder.compatible()
                let result = raw ? try d.decode(NullParent.self, from: ["value": NSNull()])
                                 : try d.decode(NullParent.self, from: Data("{\"value\":null}".utf8))
                return String(result.value.accepted)
            }
        }
        check("repeated-registration-default-snapshot", "1") {
            let original = NSMutableArray(array: [1])
            let first = try YYJSONRules().forType(List.self) { $0.defaultValues = ["value": original] }
            original.add(2)
            let second = try first.forType(List.self) { $0.requiredProperties = [] }
            return String(try YYJSONDecoder.compatible(rules: second).decode(List.self, from: Data("{}".utf8)).value.count)
        }
        check("loss-report-invocation-isolation", "1,0,0") {
            let rules = try YYJSONRules().forType(List.self) { $0.lossy(\.value) }
            var d = YYJSONDecoder.compatible(rules: rules)
            let shared = YYModelLossReport(); d.userInfo[YYModelLossReport.key] = shared
            let first = try d.decodeWithReport(List.self, from: Data("{\"value\":[1,\"bad\"]}".utf8))
            let second = try d.decodeWithReport(List.self, from: Data("{\"value\":[1]}".utf8))
            return "\(first.report.losses.count),\(second.report.losses.count),\(shared.losses.count)"
        }
        try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys, .prettyPrinted])
            .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
