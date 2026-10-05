import Foundation
import YYModelSwift

private struct Key: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ value: String) { stringValue = value }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { return nil }
}
private struct Payload: Codable { var value: Data }
private struct Table: Codable { var value: [Int: Double] }
private struct Mutated: Codable { var nested: [Int] }
private struct Dates: Codable { var sec: [String: Date]; var ms: [String: Date] }
private struct NullReject: Decodable {
    init(from decoder: Decoder) throws {
        if try decoder.singleValueContainer().decodeNil() { throw NSError(domain: "null-model-user-error", code: 1) }
    }
}
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
private let counterKey = CodingUserInfoKey(rawValue: "E2E.Counter")!
private struct Leaf: Codable {
    var n: Double
    init(from decoder: Decoder) throws {
        (decoder.userInfo[counterKey] as? Counter)?.increment()
        n = try decoder.container(keyedBy: Key.self).decode(Double.self, forKey: Key("n"))
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self); try c.encode(n, forKey: Key("n"))
    }
}
private struct Leaves: Codable { var value: [Leaf] }
private struct Collision: Encodable {
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        var first = c.nestedContainer(keyedBy: Key.self, forKey: Key("a"))
        try first.encode(1, forKey: Key("x"))
        var second = c.nestedContainer(keyedBy: Key.self, forKey: Key("b"))
        try second.encode(2, forKey: Key("x"))
    }
}

@main private struct ExtendedE2E {
    static func main() throws {
        var rows: [[String: Any]] = []
        func observe(_ id: String, _ name: String, _ expected: String, _ body: () throws -> String) {
            do {
                let actual = try body()
                rows.append(["id": id, "scenario": name, "actual": actual,
                             "expected": expected, "passed": actual == expected])
            } catch {
                rows.append(["id": id, "scenario": name, "actual": String(describing: error),
                             "expected": expected, "passed": false])
            }
        }
        let token = "1.000000000000000111022302462515654042363166809082031251"
        for hook in [false, true] {
            observe("K-03", "nested-strategy-error-path-\(hook)", "value.child") {
                let rules = try YYJSONRules().forType(Payload.self) { if hook { $0.willTransform = { $0 } } }
                var d = YYJSONDecoder.compatible(rules: rules)
                d.dataDecodingStrategy = .custom { decoder in
                    _ = try decoder.container(keyedBy: Key.self).decode(Date.self, forKey: Key("child"))
                    return Data()
                }
                d.dateDecodingStrategy = .custom { decoder in
                    _ = try decoder.singleValueContainer().decode(Double.self)
                    return Date()
                }
                do {
                    _ = try d.decode(Payload.self, from: Data("{\"value\":{\"child\":\"invalid\"}}".utf8))
                    return "accepted-invalid-value"
                } catch DecodingError.typeMismatch(_, let context) {
                    return context.codingPath.map(\.stringValue).joined(separator: ".")
                }
            }
            observe("K-03", "dictionary-shape-error-path-\(hook)", "value") {
                let rules = try YYJSONRules().forType(Payload.self) { if hook { $0.willTransform = { $0 } } }
                var d = YYJSONDecoder.compatible(rules: rules)
                d.dataDecodingStrategy = .custom { decoder in
                    _ = try decoder.singleValueContainer().decode([String: Leaf].self)
                    return Data()
                }
                do {
                    _ = try d.decode(Payload.self, from: Data("{\"value\":[]}".utf8))
                    return "accepted-invalid-value"
                } catch DecodingError.typeMismatch(_, let context) {
                    return context.codingPath.map(\.stringValue).joined(separator: ".")
                }
            }
            observe("K-04", "int-dictionary-renamed-model-\(hook)", "4607182418800017409") {
                let rules = try YYJSONRules().forType(Payload.self) { if hook { $0.willTransform = { $0 } } }
                var d = YYJSONDecoder.compatible(rules: rules)
                d.keyDecodingStrategy = .custom { path in Key(path.last?.stringValue == "physical_n" ? "n" : path.last?.stringValue ?? "") }
                d.dataDecodingStrategy = .custom { decoder in
                    let values = try decoder.singleValueContainer().decode([Int: Leaf].self)
                    guard let n = values[1]?.n else { return Data("missing".utf8) }
                    return Data(String(n.bitPattern).utf8)
                }
                return String(decoding: try d.decode(Payload.self,
                    from: Data("{\"value\":{\"1\":{\"physical_n\":\(token)}}}".utf8)).value, as: UTF8.self)
            }
            observe("K-03", "same-name-error-path-\(hook)", "value.value") {
                let rules = try YYJSONRules().forType(Payload.self) { if hook { $0.willTransform = { $0 } } }
                var d = YYJSONDecoder.compatible(rules: rules)
                d.dataDecodingStrategy = .custom { decoder in
                    _ = try decoder.container(keyedBy: Key.self).decode(Double.self, forKey: Key("value"))
                    return Data()
                }
                do {
                    _ = try d.decode(Payload.self, from: Data("{\"value\":{\"value\":\"invalid\"}}".utf8))
                    return "accepted-invalid-value"
                } catch DecodingError.typeMismatch(_, let context) {
                    return context.codingPath.map(\.stringValue).joined(separator: ".")
                }
            }
            observe("K-01", "super-physical-node-\(hook)", "4607182418800017409") {
                let rules = try YYJSONRules().forType(Payload.self) { if hook { $0.willTransform = { $0 } } }
                var d = YYJSONDecoder.compatible(rules: rules)
                d.dataDecodingStrategy = .custom { decoder in
                    let c = try decoder.container(keyedBy: Key.self)
                    let value = try c.superDecoder().singleValueContainer().decode(Double.self)
                    return Data(String(value.bitPattern).utf8)
                }
                return String(decoding: try d.decode(Payload.self,
                    from: Data("{\"value\":{\"super\":\(token)}}".utf8)).value, as: UTF8.self)
            }
            observe("K-03", "super-error-path-\(hook)", "value.super") {
                let rules = try YYJSONRules().forType(Payload.self) { if hook { $0.willTransform = { $0 } } }
                var d = YYJSONDecoder.compatible(rules: rules)
                d.dataDecodingStrategy = .custom { decoder in
                    let c = try decoder.container(keyedBy: Key.self)
                    _ = try c.superDecoder().singleValueContainer().decode(Double.self)
                    return Data()
                }
                do {
                    _ = try d.decode(Payload.self, from: Data("{\"value\":{\"super\":\"invalid\"}}".utf8))
                    return "accepted-invalid-value"
                } catch DecodingError.typeMismatch(_, let context) {
                    return context.codingPath.map(\.stringValue).joined(separator: ".")
                }
            }
            observe("K-03", "model-init-once-\(hook)", "2") {
                let count = Counter()
                let rules = try YYJSONRules().forType(Leaves.self) { if hook { $0.willTransform = { $0 } } }
                var d = YYJSONDecoder.compatible(rules: rules); d.userInfo[counterKey] = count
                let result = try d.decode(Leaves.self, from: Data("{\"value\":[{\"n\":1},{\"n\":2}]}".utf8))
                guard result.value.map(\.n) == [1, 2] else { return "wrong-values" }
                return String(count.value)
            }
            for raw in [false, true] {
                observe("F-03", "int-key-canonical-\(hook)-\(raw)", "4607182418800017409") {
                    let rules = try YYJSONRules().forType(Table.self) { if hook { $0.willTransform = { $0 } } }
                    let d = YYJSONDecoder.compatible(rules: rules)
                    let result: Table
                    if raw {
                        result = try d.decode(Table.self, from: ["value": ["01": 2,
                            "1": NSDecimalNumber(string: "1.0000000000000002")]])
                    } else {
                        result = try d.decode(Table.self, from: Data("{\"value\":{\"01\":2,\"1\":\(token)}}".utf8))
                    }
                    guard let value = result.value[1] else { return "missing-key" }
                    return String(value.bitPattern)
                }
            }
        }
        observe("F-07", "null-user-error-preserved", "null-model-user-error") {
            do {
                _ = try YYJSONDecoder.compatible().decode([NullReject].self, from: Data("[null]".utf8))
                return "accepted-null"
            } catch { return (error as NSError).domain }
        }
        for raw in [false, true] {
            observe("F-03", "int-dictionary-losing-invalid-alias-\(raw)", "rejected") {
                let d = YYJSONDecoder.compatible()
                do {
                    _ = raw
                        ? try d.decode(Table.self, from: ["value": ["01": "invalid", "1": 1]])
                        : try d.decode(Table.self, from: Data("{\"value\":{\"01\":\"invalid\",\"1\":1}}".utf8))
                    return "accepted-invalid-entry"
                } catch DecodingError.typeMismatch { return "rejected" }
            }
        }
        observe("F-11d", "mutable-hook-input-isolated", "source=1,model=2") {
            let original = NSMutableArray(array: [1])
            let rules = try YYJSONRules().forType(Mutated.self) { rule in
                rule.willTransform = { dictionary in
                    var result = dictionary
                    if let mutable = dictionary["nested"] as? NSMutableArray {
                        mutable.add(2)
                    } else {
                        result["nested"] = (dictionary["nested"] as? [Int] ?? []) + [2]
                    }
                    return result
                }
            }
            let result = try YYJSONDecoder.compatible(rules: rules).decode(Mutated.self, from: ["nested": original])
            return "source=\(original.count),model=\(result.nested.count)"
        }
        observe("F-11c", "nested-export-collision-rejected", "rejected") {
            let rules = try YYJSONRules().forType(Collision.self) { $0.mapper = ["a": "same", "b": "same"] }
            do { _ = try YYJSONEncoder.compatible(rules: rules).encode(Collision()); return "accepted" }
            catch { return String(describing: error).contains("Conflicting export path") ? "rejected" : "wrong-error" }
        }
        observe("F-11e", "dictionary-date-context-parallel", "0") {
            let failures = Counter()
            let rules = try YYJSONRules().forType(Dates.self) {
                $0.fieldDateStrategies = ["sec": .secondsSince1970, "ms": .millisecondsSince1970]
            }
            let d = YYJSONDecoder.compatible(rules: rules)
            DispatchQueue.concurrentPerform(iterations: 100) { _ in
                do {
                    let value = try d.decode(Dates.self, from: Data("{\"sec\":{\"a\":1000},\"ms\":{\"a\":1000}}".utf8))
                    if value.sec["a"]?.timeIntervalSince1970 != 1000 || value.ms["a"]?.timeIntervalSince1970 != 1 {
                        failures.increment()
                    }
                } catch { failures.increment() }
            }
            return String(failures.value)
        }
        try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys, .prettyPrinted])
            .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
