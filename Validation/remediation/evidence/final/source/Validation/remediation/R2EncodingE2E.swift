import Foundation
import YYModelSwift
private struct Key: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ value: String) { stringValue = value }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { return nil }
}
private final class Counts: @unchecked Sendable {
    private var values: [String: Int] = [:]
    private let lock = NSLock()
    func add(_ name: String) { lock.lock(); values[name, default: 0] += 1; lock.unlock() }
    var text: String {
        lock.lock(); defer { lock.unlock() }
        return ["model", "date", "data", "key"].map { "\($0)=\(values[$0, default: 0])" }.joined(separator: ",")
    }
}
private let countKey = CodingUserInfoKey(rawValue: "R2.Counts")!
private struct Callbacks: Encodable {
    func encode(to encoder: Encoder) throws {
        (encoder.userInfo[countKey] as? Counts)?.add("model")
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(Date(timeIntervalSince1970: 7), forKey: Key("stamp"))
        try c.encode(Data([1]), forKey: Key("blob"))
    }
}
private struct Amount: Codable { var value: Double; var fresh: Double? }
private struct Member: Codable { var value: Int }
private enum Root: Codable { case member(Member) }

@main private struct R2EncodingE2E {
    static func main() throws {
        var rows: [[String: Any]] = []
        func check(_ name: String, _ expected: String, _ body: () throws -> String) {
            do { let actual = try body(); rows.append(["scenario": name, "expected": expected, "actual": actual, "passed": actual == expected]) }
            catch { rows.append(["scenario": name, "expected": expected, "actual": String(describing: error), "passed": false]) }
        }
        func json(_ object: Any) throws -> String {
            String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
        }
        for hook in [false, true] {
            for object in [false, true] {
                check("encoding-callbacks-and-physical-keys-\(hook)-object-\(object)",
                      "{\"prefix_blob\":\"data\",\"prefix_stamp\":\"date\"}|model=1,date=1,data=1,key=2") {
                    let counts = Counts()
                    let rules = try YYJSONRules().forType(Callbacks.self) { if hook { $0.transformTo = { _, _ in true } } }
                    var encoder = YYJSONEncoder.compatible(rules: rules)
                    encoder.userInfo[countKey] = counts
                    encoder.keyEncodingStrategy = .custom { path in counts.add("key"); return Key("prefix_" + path.last!.stringValue) }
                    encoder.dateEncodingStrategy = .custom { _, target in
                        counts.add("date"); var c = target.singleValueContainer(); try c.encode("date")
                    }
                    encoder.dataEncodingStrategy = .custom { _, target in
                        counts.add("data"); var c = target.singleValueContainer(); try c.encode("data")
                    }
                    let result = object ? try encoder.encodeJSONObject(Callbacks())
                                        : try JSONSerialization.jsonObject(with: encoder.encode(Callbacks()))
                    return try json(result) + "|" + counts.text
                }
            }
        }
        check("polymorphic-physical-keys-once", "{\"prefix_type\":\"member\",\"prefix_value\":7}") {
            let rules = try YYJSONRules().polymorphic(Root.self, variants: ["member": .init(Member.self, create: Root.member, extract: {
                if case .member(let value) = $0 { return value }; return nil
            })])
            var encoder = YYJSONEncoder.compatible(rules: rules)
            encoder.keyEncodingStrategy = .custom { Key("prefix_" + $0.last!.stringValue) }
            return try json(JSONSerialization.jsonObject(with: encoder.encode(Root.member(Member(value: 7)))))
        }
        check("hook-moves-number-preserving-literal", "4607182418800017409,123.45") {
            let rules = try YYJSONRules().forType(Amount.self) { rule in
                rule.willTransform = { input in
                    var output = input; output["value"] = output.removeValue(forKey: "source")
                    output["fresh"] = NSNumber(value: 123.45); return output
                }
            }
            let value = try YYJSONDecoder.compatible(rules: rules).decode(Amount.self,
                from: Data("{\"source\":1.000000000000000111022302462515654042363166809082031251}".utf8))
            return "\(value.value.bitPattern),\(value.fresh ?? 0)"
        }
        try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys, .prettyPrinted])
            .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
