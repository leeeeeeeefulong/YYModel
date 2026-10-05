import Foundation
#if PUBLIC_API
import YYModelSwift
#endif

struct User: Codable, Equatable {
    let id: UInt64
    let name: String
    let age: Int?
    let created: Date
}
struct Envelope: Codable, Equatable { let users: [User]; let index: [String: User]; let favorite: User? }
struct Required: Codable { let value: Int }
struct Defaults: Codable { let value: Int; let optional: Int? }
struct TextPayload: Codable, Equatable { let body: String }
struct CountPayload: Codable, Equatable { let count: Int }
enum Event: Codable, Equatable { case text(TextPayload), count(CountPayload) }
struct Events: Codable, Equatable { let values: [Event] }
enum BusinessError: Error { case rejected }
final class Counter: @unchecked Sendable {
    static let shared = Counter()
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.lock(); defer { lock.unlock() }; value += 1 }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}
struct Reject: Decodable {
    init(from decoder: Decoder) throws { Counter.shared.increment(); throw BusinessError.rejected }
}
struct Collision: Codable { let first: String; let second: String }
struct NativeValues: Codable, Equatable { let date: Date; let bytes: Data; let snakeName: String }
struct ExplicitOptional: Decodable {
    let value: Int?
    enum CodingKeys: String, CodingKey { case value }
    init(from decoder: Decoder) throws { value = try decoder.container(keyedBy: CodingKeys.self).decode(Optional<Int>.self, forKey: .value) }
}
struct StrategyPaths: Codable, Equatable { let when: Date; let bytes: Data }
struct HookChild: Codable { let value: Int }
struct HookEnvelope: Codable { let nestedChild: HookChild }
struct Exported: Codable { let value: Int }
struct ExportDate: Codable { let when: Date }
struct ExportDateEnvelope: Codable { let child: ExportDate }
struct EncodingPathHelper: Encodable {
    func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(encoder.codingPath.map(\.stringValue).joined(separator: ".")) }
}
enum Choice: Codable { case item(Exported) }
struct StrategyKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init(_ value: String) { stringValue = value }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

@main enum ExternalRulesE2E {
    static func main() throws {
        var checks: [String: Bool] = [:]
        func check(_ name: String, _ run: () throws -> Bool) { do { checks[name] = try run() } catch { checks[name] = false; print("\(name): \(error)") } }
        func rejects(_ run: () throws -> Void) -> Bool { do { try run(); return false } catch { return true } }
        let rules = try YYJSONRules().forType(User.self) {
            $0.mapper = ["id": ["id", "uid"], "name": "profile.name"]
            $0.requiredProperties = ["id"]
            $0.fieldDateStrategies = ["created": .millisecondsSince1970]
            $0.validate = { user in if user.id == 0 { throw BusinessError.rejected } }
        }
        let decoder = YYJSONDecoder(mode: .compatible, rules: rules)
        let object: [String: Any] = ["uid": "9007199254740993", "profile": ["name": "Lee"], "age": NSNull(), "created": 1000]
        let input: [String: Any] = ["users": [object], "index": ["one": object], "favorite": object]
        let bytes = try JSONSerialization.data(withJSONObject: input)
        check("OrdinaryCodableNestedRules") {
            let envelope = try decoder.decode(Envelope.self, from: bytes)
            return envelope.users.first?.id == 9007199254740993 && envelope.index["one"] == envelope.favorite && envelope.favorite?.created.timeIntervalSince1970 == 1 && envelope.favorite?.age == nil
        }
        check("FoundationObjectMatchesData") { try decoder.decode(Envelope.self, from: input) == decoder.decode(Envelope.self, from: bytes) }
        check("EncoderSymmetry") { let model = try decoder.decode(Envelope.self, from: bytes); return try decoder.decode(Envelope.self, from: YYJSONEncoder(mode: .compatible, rules: rules).encode(model)) == model }
        check("KeyPathExport") { let model = try decoder.decode(User.self, from: object); let output = try YYJSONEncoder(mode: .compatible, rules: rules).encodeJSONObject(model) as! [String: Any]; return (output["profile"] as? [String: Any])?["name"] as? String == "Lee" && output["profile.name"] == nil }
        check("IndependentRules") {
            let alternate = try YYJSONRules().forType(User.self) { $0.mapper = ["id": "uid", "name": "other"]; $0.fieldDateStrategies = ["created": .secondsSince1970] }
            var other = object; other["other"] = "Other"
            let value = try YYJSONDecoder(mode: .compatible, rules: alternate).decode(User.self, from: other)
            return try value.name == "Other" && value.created.timeIntervalSince1970 == 1000 && (try decoder.decode(User.self, from: object).name) == "Lee"
        }
        check("StrictMissing") { rejects { _ = try YYJSONDecoder(mode: .compatible).decode(Required.self, from: [:]) } }
        check("StrictNull") { rejects { _ = try YYJSONDecoder(mode: .compatible).decode(Required.self, from: ["value": NSNull()]) } }
        check("ExplicitDefaults") { let defaults = try YYJSONRules().forType(Defaults.self) { $0.defaultValues = ["value": 7, "optional": 8] }; let d = YYJSONDecoder(mode: .compatible, rules: defaults); return try d.decode(Defaults.self, from: [:]).value == 7 && d.decode(Defaults.self, from: ["optional": NSNull()]).optional == nil }
        check("NullAliasStops") { var value = object; value["id"] = NSNull(); return rejects { _ = try decoder.decode(User.self, from: value) } }
        check("MalformedPathSafe") { var value = object; value["profile"] = 3; return rejects { _ = try decoder.decode(User.self, from: value) } }
        check("NativeRulesRejected") { rejects { _ = try YYJSONDecoder(mode: .native, rules: rules).decode(User.self, from: object) } }
        check("NativeStrategies") {
            let native = JSONDecoder(); native.dateDecodingStrategy = .millisecondsSince1970; native.keyDecodingStrategy = .convertFromSnakeCase
            var yy = YYJSONDecoder(mode: .native); yy.dateDecodingStrategy = .millisecondsSince1970; yy.keyDecodingStrategy = .convertFromSnakeCase
            let data = Data(#"{"date":1000,"bytes":"YQ==","snake_name":"ok"}"#.utf8)
            return try yy.decode(NativeValues.self, from: data) == native.decode(NativeValues.self, from: data)
        }
        for mode in [YYJSONMode.native, .compatible, .legacy] {
            check("SingleBusinessInit-\(mode)") { let before = Counter.shared.count; do { _ = try YYJSONDecoder(mode: mode).decode(Reject.self, from: Data("{}".utf8)); return false } catch BusinessError.rejected { return Counter.shared.count == before + 1 } catch { return false } }
        }
        check("LegacyZeroFill") { try YYJSONDecoder().decode(Required.self, from: [:]).value == 0 }
        check("ExactUInt64") { struct ID: Decodable { let value: UInt64 }; return try YYJSONDecoder(mode: .compatible).decode(ID.self, from: Data(#"{"value":"18446744073709551615"}"#.utf8)).value == UInt64.max }
        check("MalformedNumberRejected") { rejects { _ = try YYJSONDecoder(mode: .compatible).decode(Required.self, from: ["value": "123abc"]) } }
        check("RangeRejected") { struct ID: Decodable { let value: Int64 }; return rejects { _ = try YYJSONDecoder(mode: .compatible).decode(ID.self, from: ["value": "-9223372036854775809.0"]) } }
        check("CollisionRejected") { let c = try YYJSONRules().forType(Collision.self) { $0.mapper = ["first": "node", "second": "node.name"] }; return rejects { _ = try YYJSONEncoder(mode: .compatible, rules: c).encode(Collision(first: "a", second: "b")) } }
        let poly = try rules.forType(TextPayload.self) { $0.mapper = ["body": "payload.body"] }.polymorphic(Event.self, discriminator: "type", variants: [
            "text": YYModelVariant(TextPayload.self, create: Event.text, extract: { if case .text(let value) = $0 { return value }; return nil }),
            "count": YYModelVariant(CountPayload.self, create: Event.count, extract: { if case .count(let value) = $0 { return value }; return nil })
        ])
        check("OrdinaryPolymorphicRoundTrip") { let d = YYJSONDecoder(mode: .compatible, rules: poly); let value = try d.decode(Events.self, from: Data(#"{"values":[{"type":"text","payload":{"body":"hi"}},{"type":"count","count":"7"}]}"#.utf8)); return try value.values == [.text(TextPayload(body: "hi")), .count(CountPayload(count: 7))] && (try d.decode(Events.self, from: YYJSONEncoder(mode: .compatible, rules: poly).encode(value))) == value }
        check("ExplicitOptionalNull") { try YYJSONDecoder(mode: .compatible).decode(ExplicitOptional.self, from: Data(#"{"value":null}"#.utf8)).value == nil }
        check("StrictRootNull") { rejects { _ = try YYJSONDecoder(mode: .compatible).decode(Int.self, from: Data("null".utf8)) } }
        check("NativeStrategyObjectContext") {
            var d = YYJSONDecoder(mode: .compatible)
            d.dateDecodingStrategy = .custom { Date(timeIntervalSince1970: Double($0.codingPath.count)) }
            d.dataDecodingStrategy = .custom { Data($0.codingPath.map(\.stringValue).joined(separator: ".").utf8) }
            return try d.decode(StrategyPaths.self, from: ["when": 0, "bytes": "abc"]) == d.decode(StrategyPaths.self, from: Data(#"{"when":0,"bytes":"abc"}"#.utf8))
        }
        check("SnakeCaseObjectMatchesData") {
            struct Snake: Codable, Equatable { let snakeName: String }
            var d = YYJSONDecoder(mode: .compatible); d.keyDecodingStrategy = .convertFromSnakeCase
            return try d.decode(Snake.self, from: ["snake_name": "ok"]) == d.decode(Snake.self, from: Data(#"{"snake_name":"ok"}"#.utf8))
        }
        check("DictionaryKeysRemainData") {
            var d = YYJSONDecoder(mode: .compatible, rules: rules); d.keyDecodingStrategy = .convertFromSnakeCase
            let o: [String: Any] = ["snake_key": object]
            return try d.decode([String: User].self, from: o)["snake_key"]?.name == "Lee" && d.decode([String: User].self, from: JSONSerialization.data(withJSONObject: o))["snake_key"]?.name == "Lee"
        }
        check("NestedHookWithKeyStrategy") {
            let r = try YYJSONRules().forType(HookChild.self) { $0.didTransform = { _, input in input["value"] as? Int == 7 } }
            var d = YYJSONDecoder(mode: .compatible, rules: r); d.keyDecodingStrategy = .convertFromSnakeCase
            return try d.decode(HookEnvelope.self, from: Data(#"{"nested_child":{"value":7}}"#.utf8)).nestedChild.value == 7
        }
        check("ExportHookKeyStrategyOnce") {
            let r = try YYJSONRules().forType(Exported.self) { $0.transformTo = { _, _ in true } }
            var e = YYJSONEncoder(mode: .compatible, rules: r); e.keyEncodingStrategy = .custom { StrategyKey("x" + $0.last!.stringValue) }
            let o = try e.encodeJSONObject(Exported(value: 7)) as! [String: Any]
            return o["xvalue"] as? Int == 7 && o["xxvalue"] == nil
        }
        check("PolymorphicKeyStrategyOnce") {
            let r = try YYJSONRules().polymorphic(Choice.self, variants: ["item": YYModelVariant(Exported.self, create: Choice.item, extract: { if case .item(let v) = $0 { return v }; return nil })])
            var e = YYJSONEncoder(mode: .compatible, rules: r); e.keyEncodingStrategy = .custom { StrategyKey("x" + $0.last!.stringValue) }
            let o = try e.encodeJSONObject(Choice.item(Exported(value: 7))) as! [String: Any]
            return o["xvalue"] as? Int == 7 && o["xtype"] as? String == "item" && o["xxvalue"] == nil
        }
        check("RawCustomStrategyRemainsStrict") {
            var d = YYJSONDecoder(mode: .compatible)
            d.dateDecodingStrategy = .custom { Date(timeIntervalSince1970: try $0.singleValueContainer().decode(Double.self)) }
            return rejects { _ = try d.decode(StrategyPaths.self, from: ["when": "7", "bytes": "YQ=="]) } && rejects { _ = try d.decode(StrategyPaths.self, from: Data(#"{"when":"7","bytes":"YQ=="}"#.utf8)) }
        }
        check("HookCustomStrategyGenericPath") {
            let r = try YYJSONRules().forType(ExportDate.self) { $0.transformTo = { _, _ in true } }
            var e = YYJSONEncoder(mode: .compatible, rules: r)
            e.dateEncodingStrategy = .custom { _, encoder in var c = encoder.singleValueContainer(); try c.encode(EncodingPathHelper()) }
            let value = ExportDateEnvelope(child: ExportDate(when: Date(timeIntervalSince1970: 0)))
            let o = try e.encodeJSONObject(value) as! [String: Any]
            return (o["child"] as? [String: Any])?["when"] as? String == "child.when"
        }
        check("FractionalTokensDoNotRoundIntoSmallIntegers") {
            struct Numbers: Decodable { let values: [Int64] }
            let data = Data(#"{"values":[0.9999999999999999999,-0.9999999999999999999,4503599627370495.9]}"#.utf8)
            return try YYJSONDecoder(mode: .compatible).decode(Numbers.self, from: data).values == [0, 0, 4503599627370495]
        }
        check("ScalarCollectionsPreserveExactAndNullableValues") {
            struct Numbers: Codable, Equatable { let values: [[UInt64?]]; let index: [String: Int64] }
            let data = Data(#"{"values":[[null,9007199254740993.0,18446744073709551615]],"index":{"small_key":-0.9999999999999999999}}"#.utf8)
            var d = YYJSONDecoder(mode: .compatible); d.keyDecodingStrategy = .convertFromSnakeCase
            let value = try d.decode(Numbers.self, from: data)
            let roundTrip = try d.decode(Numbers.self, from: YYJSONEncoder().encode(value))
            return value.values == [[nil, 9007199254740993, UInt64.max]] && value.index["small_key"] == 0 && roundTrip == value
        }
        check("ScalarCollectionOverflowRejected") {
            let d = YYJSONDecoder(mode: .compatible)
            return rejects { _ = try d.decode([Int64?].self, from: Data("[-9223372036854775809.0]".utf8)) }
                && rejects { _ = try d.decode([UInt64].self, from: Data("[18446744073709551616.0]".utf8)) }
        }
        check("NativeScalarCollectionsRejectNonfinite") {
            var d = YYJSONDecoder(mode: .compatible)
            d.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
            return rejects { _ = try d.decode([[Double?]].self, from: Data(#"[["inf"]]"#.utf8)) }
                && rejects { _ = try d.decode([String: Float].self, from: Data(#"{"key":"nan"}"#.utf8)) }
        }
        check("RawScalarCollectionsMatchStrictDataNullPolicy") {
            struct Scalars: Decodable { let values: [Double] }
            let d = YYJSONDecoder(mode: .compatible)
            return rejects { _ = try d.decode([Double].self, from: [NSNull()]) }
                && rejects { _ = try d.decode([Double].self, from: Data("[null]".utf8)) }
                && rejects { _ = try d.decode(Scalars.self, from: ["values": [NSNull()]]) }
                && rejects { _ = try d.decode(Scalars.self, from: Data(#"{"values":[null]}"#.utf8)) }
        }
        check("DefaultEncoderDecoderDateRoundTrip") {
            struct Dated: Codable, Equatable { let when: Date }
            let d = YYJSONDecoder()
            let value = try d.decode(Dated.self, from: Data(#"{"when":1700000000}"#.utf8))
            let roundTrip = try d.decode(Dated.self, from: YYJSONEncoder().encode(value))
            return value.when.timeIntervalSince1970 == 1700000000 && roundTrip == value
        }
        let result: [String: Any] = ["checks": checks, "total": checks.count, "passed": checks.values.filter { $0 }.count, "allPassed": checks.values.allSatisfy { $0 }]
        let output = CommandLine.arguments[1]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: output))
        if !checks.values.allSatisfy({ $0 }) { exit(1) }
    }
}
