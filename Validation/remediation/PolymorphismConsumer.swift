import Foundation
import YYModelSwift

// Polymorphism contract (C②):
//  - unknown discriminator → dataCorrupted at discriminator path.
//  - missing discriminator → keyNotFound at the container.
//  - null discriminator → valueNotFound.
//  - round-trip keeps the discriminator key in the encoded output.
enum Shape: Codable { case circle(Circle) }
struct Circle: Codable { var r: Int }
struct ShapeHolder: Codable { var shape: Shape }

@main struct PolymorphismConsumer {
    static func main() throws {
        var rows: [[String: Any]] = []
        func observe(_ name: String, _ body: () throws -> Any) {
            do { rows.append(["name": name, "result": try body()]) }
            catch { rows.append(errorRow(name, error)) }
        }
        func data(_ text: String) -> Data { Data(text.utf8) }
        let poly = try YYJSONRules().polymorphic(Shape.self, discriminator: "type", variants: [
            "circle": YYModelVariant(Circle.self, create: { .circle($0) },
                                     extract: { if case .circle(let c) = $0 { return c }; return nil })])
        let decoder = YYJSONDecoder.compatible(rules: poly)
        let encoder = YYJSONEncoder.compatible(rules: poly)

        observe("poly-unknown") { try decoder.decode(ShapeHolder.self, from: data(#"{"shape":{"type":"square","r":1}}"#)) }
        observe("poly-unknown-raw") { try decoder.decode(ShapeHolder.self, from: ["shape": ["type": "square", "r": 1]] as [String: Any]) }
        observe("poly-missing") { try decoder.decode(ShapeHolder.self, from: data(#"{"shape":{"r":1}}"#)) }
        observe("poly-null") { try decoder.decode(ShapeHolder.self, from: data(#"{"shape":{"type":null,"r":1}}"#)) }
        observe("poly-roundtrip") {
            let v = try decoder.decode(ShapeHolder.self, from: data(#"{"shape":{"type":"circle","r":7}}"#))
            return String(decoding: try encoder.encode(v), as: UTF8.self)
        }

        try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}

/// Structured error fields (C12): consumers emit errorType / errorPath (Foundation codingPath
/// semantics) and errorKey for keyNotFound, so run.py can assert them in the expectations.
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