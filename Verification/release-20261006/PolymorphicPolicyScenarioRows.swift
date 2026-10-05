// Public optimized-library E2E registration and decoding scenarios. Unsupported
// polymorphic root field policies reject in both orders, while Payload policies
// work through Data/object entries. Replaced typed defaults never expose stale JSON.
import Foundation
import YYModelSwift

private struct Payload: Codable { var value: Int; var items: [Int] }
private enum Root: Codable { case payload(Payload) }
private struct BusinessDefault: Codable {
    var value: Int
    var cannotEncode: Bool = false
    enum Keys: String, CodingKey { case value }
    init(_ value: Int, cannotEncode: Bool = false) { self.value = value; self.cannotEncode = cannotEncode }
    init(from decoder: Decoder) throws { value = try decoder.container(keyedBy: Keys.self).decode(Int.self, forKey: .value) }
    func encode(to encoder: Encoder) throws {
        if cannotEncode { throw NSError(domain: "ExpectedUnencodableDefault", code: 1) }
        var c = encoder.container(keyedBy: Keys.self); try c.encode(value, forKey: .value)
    }
}
private struct DirectDefaultHost: Codable { var child: BusinessDefault }
private struct DecoderDefaultHost: Codable {
    var child: BusinessDefault
    enum CodingKeys: String, CodingKey { case child }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        child = try BusinessDefault(from: c.superDecoder(forKey: .child))
    }
}

@main private struct PolymorphicPolicyScenarioRows {
    static func main() throws {
        var rows: [[String: Any]] = []
        func check(_ name: String, _ expected: String, _ body: () throws -> String) {
            let actual: String
            do { actual = try body() } catch { actual = "unexpected error: \(error)" }
            rows.append(["scenario": name, "expected": expected, "actual": actual, "passed": actual == expected])
        }
        func polymorphic(_ rules: YYJSONRules) throws -> YYJSONRules {
            try rules.polymorphic(Root.self, variants: ["p": .init(Payload.self, create: Root.payload, extract: {
                if case .payload(let payload) = $0 { return payload }; return nil
            })])
        }
        func decode<T: Decodable>(_ type: T.Type, rules: YYJSONRules, object: [String: Any], raw: Bool) throws -> T {
            let decoder = YYJSONDecoder.compatible(rules: rules)
            return try raw ? decoder.decode(type, from: object) : decoder.decode(type, from: JSONSerialization.data(withJSONObject: object))
        }
        let policies = ["fallback", "lossy", "typed-default", "zero-fill"]
        for policy in policies {
            for order in ["before", "after"] {
                check("release-root-policy-\(policy)-\(order)", "rejected") {
                    let configure: (inout YYModelConfiguration<Root>) -> Void = {
                        switch policy {
                        case "fallback": $0.fallbackValues = ["value": 88]
                        case "lossy": $0.lossyProperties = ["items"]
                        case "typed-default": $0.typedDefaultValues = ["value": 88]
                        default: $0.missingStrategy = .zeroFill
                        }
                    }
                    do {
                        _ = try order == "before"
                            ? polymorphic(YYJSONRules().forType(Root.self, configure: configure))
                            : polymorphic(YYJSONRules()).forType(Root.self, configure: configure)
                        return "accepted"
                    } catch {
                        guard String(describing: error).contains("Declare polymorphic field/date policies on payload types") else { throw error }
                        return "rejected"
                    }
                }
            }
            for raw in [false, true] {
                let expected = "value=\(policy == "lossy" ? 7 : policy == "zero-fill" ? 0 : 88);items=1,2"
                check("release-payload-policy-\(policy)-raw-\(raw)", expected) {
                    let rules = try polymorphic(YYJSONRules().forType(Payload.self) {
                        switch policy {
                        case "fallback": $0.fallback(\.value, to: 88)
                        case "lossy": $0.lossy(\.items)
                        case "typed-default": $0.default(\.value, to: 88)
                        default: $0.missingStrategy = .zeroFill
                        }
                    })
                    let object: [String: Any] = policy == "lossy"
                        ? ["type": "p", "value": 7, "items": [1, "bad", 2]]
                        : ["type": "p", "items": [1, 2]]
                    let root = try decode(Root.self, rules: rules, object: object, raw: raw)
                    guard case .payload(let payload) = root else { return "wrong variant" }
                    return "value=\(payload.value);items=\(payload.items.map(String.init).joined(separator: ","))"
                }
            }
        }
        for raw in [false, true] {
            check("release-typed-default-direct-new-value-raw-\(raw)", "99") {
                let first = try YYJSONRules().forType(DirectDefaultHost.self) { $0.default(\.child, to: BusinessDefault(7)) }
                let second = try first.forType(DirectDefaultHost.self) { $0.default(\.child, to: BusinessDefault(99, cannotEncode: true)) }
                return String(try decode(DirectDefaultHost.self, rules: second, object: [:], raw: raw).child.value)
            }
            for hasPrevious in [false, true] {
                check("release-typed-default-decoder-no-stale-value-previous-\(hasPrevious)-raw-\(raw)", "typeMismatch") {
                    let first = try hasPrevious
                        ? YYJSONRules().forType(DecoderDefaultHost.self) { $0.default(\.child, to: BusinessDefault(7)) }
                        : YYJSONRules()
                    let second = try first.forType(DecoderDefaultHost.self) { $0.default(\.child, to: BusinessDefault(99, cannotEncode: true)) }
                    do { return String(try decode(DecoderDefaultHost.self, rules: second, object: [:], raw: raw).child.value) }
                    catch DecodingError.typeMismatch { return "typeMismatch" }
                }
            }
        }
        try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys, .prettyPrinted])
            .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
