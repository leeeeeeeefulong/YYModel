import Foundation

enum Rejection: Error { case business }
final class Counter: @unchecked Sendable {
    static let shared = Counter()
    var count = 0
}
struct Validated: Decodable {
    let amount: Int
    enum CodingKeys: String, CodingKey { case amount }
    init(from decoder: Decoder) throws {
        Counter.shared.count += 1
        amount = try decoder.container(keyedBy: CodingKeys.self).decode(Int.self, forKey: .amount)
        if amount < 0 { throw Rejection.business }
    }
}
struct Defaults: Codable { var name = "Guest"; var age = 18 }
struct Mapped: YYModelCodable {
    let id: Int
    static var yy_modelConfiguration: YYModelConfiguration<Self> { .init(mapper: ["id": "uid"]) }
}
struct Dated: Codable { let date: Date }
struct Envelope: Codable { let users: [User] }
struct User: Codable { let name: String; let age: Int? }
struct Number: Codable { let id: UInt64 }
struct Ordinary: Codable { let id: UInt64; let title: String }
// Research-only: not a published API. Reuse the existing internal adapter to
// prove the model protocol is not required by Swift's decoding mechanism.
struct ExternalPolicyProbe: Decodable {
    let value: Ordinary
    init(from decoder: Decoder) throws {
        let policy = YYModelPolicy(mapper: ["id": "uid", "title": "company.name"])
        value = try Ordinary(from: YYModelDecoder(base: decoder, policy: policy))
    }
}

@main enum Run {
    static func main() throws {
        var rows: [[String: Any]] = []
        let reject = Data(#"{"amount":-1}"#.utf8)
        for mode in ["native", "legacy", "model"] {
            Counter.shared.count = 0
            var errorName = "none"
            do {
                switch mode {
                case "native": _ = try JSONDecoder().decode(Validated.self, from: reject)
                case "legacy": _ = try YYJSONDecoder().decode(Validated.self, from: reject)
                default: _ = try YYModelJSON.decode(Validated.self, from: reject)
                }
            } catch { errorName = String(reflecting: error) }
            rows.append(["case": "businessRejection", "mode": mode, "initializations": Counter.shared.count, "error": errorName])
        }
        let empty = Data("{}".utf8)
        var nativeMissing = "none"
        do { _ = try JSONDecoder().decode(Defaults.self, from: empty) } catch { nativeMissing = String(reflecting: error) }
        let defaults = try YYJSONDecoder().decode(Defaults.self, from: empty)
        rows.append(["case": "declarationDefaults", "nativeError": nativeMissing, "legacyName": defaults.name, "legacyAge": defaults.age])
        let mapping = Data(#"{"uid":42}"#.utf8)
        let ignored = try YYJSONDecoder().decode(Mapped.self, from: mapping)
        let applied = try YYModelJSON.decode(Mapped.self, from: mapping)
        rows.append(["case": "entrySpecificMapper", "legacyID": ignored.id, "modelID": applied.id])
        let epoch = Data(#"{"date":0}"#.utf8)
        let nativeDate = try JSONDecoder().decode(Dated.self, from: epoch)
        let legacyDate = try YYJSONDecoder().decode(Dated.self, from: epoch)
        rows.append(["case": "dateDefaults", "nativeUnixEpoch": nativeDate.date.timeIntervalSince1970, "legacyUnixEpoch": legacyDate.date.timeIntervalSince1970])
        let nested = Data(#"{"users":[{"name":"A","age":null},{"name":"B","age":3}]}"#.utf8)
        let plain = try YYJSONDecoder().decode(Envelope.self, from: nested)
        rows.append(["case": "plainCodableNestedArray", "count": plain.users.count, "firstAgeIsNil": plain.users[0].age == nil, "secondAge": plain.users[1].age!])
        let exact = try YYJSONDecoder().decode(Number.self, from: Data(#"{"id":"9007199254740993"}"#.utf8))
        var suffixRejected = false
        do { _ = try YYJSONDecoder().decode(Number.self, from: Data(#"{"id":"123abc"}"#.utf8)) } catch { suffixRejected = true }
        rows.append(["case": "numericCoercion", "exactID": String(exact.id), "malformedSuffixRejected": suffixRejected])
        let external = try JSONDecoder().decode(ExternalPolicyProbe.self, from: Data(#"{"uid":"9007199254740993","company":{"name":"Weather"}}"#.utf8))
        rows.append(["case": "internalExternalPolicyFeasibility", "modelConformance": "Codable only", "exactID": String(external.value.id), "title": external.value.title])
        let wrongNode = try JSONDecoder().decode(ExternalPolicyProbe.self, from: Data(#"{"uid":42,"company":7}"#.utf8))
        rows.append(["case": "internalExternalPolicyInvalidIntermediate", "id": String(wrongNode.value.id), "title": wrongNode.value.title, "noCrash": true])
        let json = try JSONSerialization.data(withJSONObject: ["observations": rows], options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(json)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
