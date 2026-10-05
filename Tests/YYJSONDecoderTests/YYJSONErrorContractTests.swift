import XCTest
import YYModelSwift

/// P1-2: public decode paths throw `DecodingError` with a codingPath; rule construction and
/// rule-driven encoding throw `YYJSONRulesError` with a stable code.
final class YYJSONErrorContractTests: XCTestCase {
    enum Shape: Codable { case circle(Circle) }
    struct Circle: Codable { var r: Int }
    struct Holder: Codable { var shape: Shape }
    struct Num: Codable { var n: Int }

    private func rules() throws -> YYJSONRules {
        try YYJSONRules().polymorphic(Shape.self, discriminator: "type", variants: [
            "circle": YYModelVariant(Circle.self, create: { .circle($0) }, extract: { if case .circle(let c) = $0 { return c }; return nil })])
    }

    func testUnknownDiscriminatorIsDataCorruptedAtDiscriminatorPath() throws {
        let decoder = YYJSONDecoder.compatible(rules: try rules())
        XCTAssertThrowsError(try decoder.decode(Holder.self, from: Data(#"{"shape":{"type":"square"}}"#.utf8))) { error in
            guard case DecodingError.dataCorrupted(let context) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(context.codingPath.map(\.stringValue), ["shape", "type"])
        }
    }

    func testDidTransformRejectionIsDataCorruptedAtModelPath() throws {
        let rules = try YYJSONRules().forType(Num.self) { $0.didTransform = { _, _ in false } }
        XCTAssertThrowsError(try YYJSONDecoder.compatible(rules: rules).decode([Num].self, from: Data(#"[{"n":1}]"#.utf8))) { error in
            guard case DecodingError.dataCorrupted(let context) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(context.codingPath.map(\.stringValue), ["Index 0"])
        }
    }

    func testRuleConstructionAndEncodingUseRulesErrorCodes() throws {
        XCTAssertThrowsError(try YYJSONRules().forType(Num.self) { $0.whitelist = [] }) { error in
            XCTAssertEqual((error as? YYJSONRulesError)?.code, .emptyWhitelist)
        }
        let reject = try YYJSONRules().forType(Num.self) { $0.transformTo = { _, _ in false } }
        XCTAssertThrowsError(try YYJSONEncoder.compatible(rules: reject).encode(Num(n: 1))) { error in
            XCTAssertEqual((error as? YYJSONRulesError)?.code, .transformToRejected)
        }
        XCTAssertThrowsError(try YYJSONDecoder(mode: .native, rules: reject).decode(Num.self, from: Data(#"{"n":1}"#.utf8))) { error in
            XCTAssertEqual((error as? YYJSONRulesError)?.code, .rulesRequireCompatibleMode)
        }
    }
}
