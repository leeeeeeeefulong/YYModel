import Foundation
import YYModelSwift

// P1-2 / C12: no internal error type crosses the public API. Data problems are DecodingError with
// a codingPath; rule construction, mode misuse and rule-driven encoding are YYJSONRulesError codes.
enum Shape: Codable { case circle(Circle) }
struct Circle: Codable { var r: Int }
struct Holder: Codable { var shape: Shape }
struct Num: Codable { var n: Int }
struct Wrapper: Codable { var item: Num }

@main struct ErrorContractConsumer {
    static func main() throws {
        var rows: [[String: Any]] = []
        func observe(_ name: String, _ body: () throws -> Any) {
            do { rows.append(["name": name, "result": try body()]) }
            catch { rows.append(errorRow(name, error)) }
        }
        func data(_ text: String) -> Data { Data(text.utf8) }
        let poly = try YYJSONRules().polymorphic(Shape.self, discriminator: "type", variants: [
            "circle": YYModelVariant(Circle.self, create: { .circle($0) }, extract: { if case .circle(let c) = $0 { return c }; return nil })])
        let decoder = YYJSONDecoder.compatible(rules: poly)
        observe("poly-unknown") { try decoder.decode(Holder.self, from: data(#"{"shape":{"type":"square","r":1}}"#)) }
        observe("poly-unknown-raw") { try decoder.decode(Holder.self, from: ["shape": ["type": "square", "r": 1]] as [String: Any]) }
        observe("poly-missing") { try decoder.decode(Holder.self, from: data(#"{"shape":{"r":1}}"#)) }
        observe("poly-null") { try decoder.decode(Holder.self, from: data(#"{"shape":{"type":null,"r":1}}"#)) }

        let didFalse = try YYJSONRules().forType(Num.self) { $0.didTransform = { _, _ in false } }
        observe("didTransform-false") { try YYJSONDecoder.compatible(rules: didFalse).decode(Wrapper.self, from: data(#"{"item":{"n":1}}"#)) }
        let willNil = try YYJSONRules().forType(Num.self) { $0.willTransform = { _ in nil } }
        observe("willTransform-nil") { try YYJSONDecoder.compatible(rules: willNil).decode(Wrapper.self, from: data(#"{"item":{"n":1}}"#)) }
        observe("hook-input-not-object") { try YYJSONDecoder.compatible(rules: willNil).decode(Wrapper.self, from: data(#"{"item":5}"#)) }

        observe("native-with-rules") { try YYJSONDecoder(mode: .native, rules: willNil).decode(Num.self, from: data(#"{"n":1}"#)) }
        observe("native-encoder-with-rules") { try YYJSONEncoder(mode: .native, rules: willNil).encode(Num(n: 1)) }
        let toFalse = try YYJSONRules().forType(Num.self) { $0.transformTo = { _, _ in false } }
        observe("transformTo-false") { try YYJSONEncoder.compatible(rules: toFalse).encode(Wrapper(item: Num(n: 1))) }
        observe("forType-collection") { try YYJSONRules().forType([Num].self) { _ in } }
        observe("forType-empty-whitelist") { try YYJSONRules().forType(Num.self) { $0.whitelist = [] } }
        observe("forType-required-excluded") { try YYJSONRules().forType(Num.self) { $0.requiredProperties = ["n"]; $0.blacklist = ["n"] } }
        observe("polymorphic-empty") { try YYJSONRules().polymorphic(Shape.self, variants: [:]) }

        try JSONSerialization.data(withJSONObject: rows.map(sanitized), options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
    /// Successful configuration calls return opaque values; record that they succeeded.
    static func sanitized(_ row: [String: Any]) -> [String: Any] {
        guard let result = row["result"], !(result is String || result is NSNumber) else { return row }
        var copy = row; copy["result"] = "accepted"; return copy
    }
}

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
    case let rules as YYJSONRulesError:
        row["errorType"] = "YYJSONRulesError." + rules.code.rawValue
        if case .encodingRejected(_, let path, _) = rules { row["errorPath"] = path }
    default: row["errorType"] = String(describing: type(of: error))
    }
    return row
}
