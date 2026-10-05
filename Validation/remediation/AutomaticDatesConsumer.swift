import Foundation
import YYModelSwift

// Automatic-date and date-inheritance contract (P0-1, P1-1, D1/P2-5, C5).
// A rule that never assigns `dateStrategy` must not change date semantics:
// `.legacy` keeps Unix seconds/automatic recognition, `.compatible` keeps Foundation's.
struct Stamp: Codable { var d: Date }
struct OwnStamp: YYModelCodable { var d: Date }
struct NestedStamp: Codable { var child: Stamp }

@main struct AutomaticDatesConsumer {
    static func main() throws {
        var rows: [[String: Any]] = []
        func observe(_ name: String, _ body: () throws -> Any) {
            do { rows.append(["name": name, "result": try body()]) }
            catch { rows.append(errorRow(name, error)) }
        }
        func data(_ text: String) -> Data { Data(text.utf8) }
        func seconds<T: Decodable>(_ type: T.Type, _ decoder: YYJSONDecoder, _ json: String, _ pick: (T) -> Date) throws -> Double {
            pick(try decoder.decode(type, from: data(json))).timeIntervalSince1970
        }
        func text(_ value: Data) -> String { String(decoding: value, as: UTF8.self) }
        let mapped = try YYJSONRules().forType(Stamp.self) { $0.mapper = ["d": ["d", "date"]] }
        let unix = #"{"d":1700000000}"#

        // P0-1: legacy + a rule that never mentions dates.
        observe("legacy-norules-seconds") { try seconds(Stamp.self, YYJSONDecoder(), unix) { $0.d } }
        observe("legacy-rules-seconds") { try seconds(Stamp.self, .legacy(rules: mapped), unix) { $0.d } }
        observe("legacy-rules-alias-seconds") { try seconds(Stamp.self, .legacy(rules: mapped), #"{"date":1700000000}"#) { $0.d } }
        observe("legacy-rules-iso") { try seconds(Stamp.self, .legacy(rules: mapped), #"{"d":"2026-10-05T00:00:00Z"}"#) { $0.d } }
        observe("legacy-norules-encode") { text(try YYJSONEncoder().encode(Stamp(d: Date(timeIntervalSince1970: 7)))) }
        observe("legacy-rules-encode") { text(try YYJSONEncoder.legacy(rules: mapped).encode(Stamp(d: Date(timeIntervalSince1970: 7)))) }
        observe("legacy-yymodelcodable-seconds") { try seconds(OwnStamp.self, YYJSONDecoder(), unix) { $0.d } }

        // P1-1: compatible keeps the same date semantics with or without rules / YYModelCodable.
        observe("compatible-norules-seconds") { try seconds(Stamp.self, .compatible(), unix) { $0.d } }
        observe("compatible-rules-seconds") { try seconds(Stamp.self, .compatible(rules: mapped), unix) { $0.d } }
        observe("compatible-yymodelcodable-seconds") { try seconds(OwnStamp.self, .compatible(), unix) { $0.d } }
        observe("compatible-rules-encode") { text(try YYJSONEncoder.compatible(rules: mapped).encode(Stamp(d: Date(timeIntervalSince1970: 7)))) }

        // An explicit assignment still wins over the inherited mode date.
        let explicitAutomatic = try YYJSONRules().forType(Stamp.self) { $0.dateStrategy = .automatic }
        let explicitNative = try YYJSONRules().forType(Stamp.self) { $0.dateStrategy = .native }
        observe("compatible-explicit-automatic") { try seconds(Stamp.self, .compatible(rules: explicitAutomatic), unix) { $0.d } }
        observe("legacy-explicit-native") { try seconds(Stamp.self, .legacy(rules: explicitNative), unix) { $0.d } }

        // A nested model with an inheriting rule follows its containing field's strategy.
        let nested = try YYJSONRules()
            .forType(NestedStamp.self) { $0.fieldDateStrategies = ["child": .millisecondsSince1970] }
            .forType(Stamp.self) { $0.mapper = ["d": "d"] }
        observe("compatible-nested-field-millis") {
            try seconds(NestedStamp.self, .compatible(rules: nested), #"{"child":{"d":1700000000000}}"#) { $0.child.d }
        }

        try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}

/// Structured error fields: `errorType` and `errorPath` (Foundation codingPath semantics);
/// `errorKey` names the missing key of keyNotFound. `run.py` asserts them when an expectation has them.
func errorRow(_ name: String, _ error: Error) -> [String: Any] {
    var row: [String: Any] = ["name": name, "error": String(describing: error)]
    func put(_ type: String, _ context: DecodingError.Context) {
        row["errorType"] = type; row["errorPath"] = context.codingPath.map(\.stringValue)
    }
    switch error {
    case DecodingError.keyNotFound(let key, let context): put("keyNotFound", context); row["errorKey"] = key.stringValue
    case DecodingError.valueNotFound(_, let context): put("valueNotFound", context)
    case DecodingError.typeMismatch(_, let context): put("typeMismatch", context)
    case DecodingError.dataCorrupted(let context): put("dataCorrupted", context)
    default: row["errorType"] = String(describing: type(of: error))
    }
    return row
}
