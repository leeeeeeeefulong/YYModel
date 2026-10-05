import XCTest
import YYModelSwift

/// P0-1 / P1-1: a registered rule that never assigns `dateStrategy` inherits the mode's date
/// semantics. `.legacy` keeps Unix seconds; `.compatible` keeps Foundation's reference date.
final class YYModelDateInheritanceTests: XCTestCase {
    struct Stamp: Codable, Equatable { var d: Date }
    struct OwnStamp: YYModelCodable { var d: Date }

    private let unix = Data(#"{"d":1700000000}"#.utf8)
    private let foundationSeconds = 1_700_000_000 + 978_307_200.0

    private func mapped() throws -> YYJSONRules {
        try YYJSONRules().forType(Stamp.self) { $0.mapper = ["d": ["d", "date"]] }
    }

    func testLegacyDecodeIgnoresRuleRegistration() throws {
        XCTAssertEqual(try YYJSONDecoder().decode(Stamp.self, from: unix).d.timeIntervalSince1970, 1_700_000_000)
        XCTAssertEqual(try YYJSONDecoder.legacy(rules: mapped()).decode(Stamp.self, from: unix).d.timeIntervalSince1970, 1_700_000_000)
        let iso = Data(#"{"d":"2026-10-05T00:00:00Z"}"#.utf8)
        XCTAssertEqual(try YYJSONDecoder.legacy(rules: mapped()).decode(Stamp.self, from: iso).d.timeIntervalSince1970, 1_791_158_400)
    }

    func testLegacyEncodeIgnoresRuleRegistration() throws {
        let value = Stamp(d: Date(timeIntervalSince1970: 7))
        XCTAssertEqual(String(decoding: try YYJSONEncoder.legacy(rules: mapped()).encode(value), as: UTF8.self), #"{"d":7}"#)
    }

    func testCompatibleDateIsIndependentOfRulesAndProtocol() throws {
        let plain = try YYJSONDecoder.compatible().decode(Stamp.self, from: unix).d.timeIntervalSince1970
        let ruled = try YYJSONDecoder.compatible(rules: mapped()).decode(Stamp.self, from: unix).d.timeIntervalSince1970
        let owned = try YYJSONDecoder.compatible().decode(OwnStamp.self, from: unix).d.timeIntervalSince1970
        XCTAssertEqual(plain, foundationSeconds)
        XCTAssertEqual(ruled, plain)
        XCTAssertEqual(owned, plain)
    }

    func testExplicitStrategyOverridesMode() throws {
        let automatic = try YYJSONRules().forType(Stamp.self) { $0.dateStrategy = .automatic }
        let native = try YYJSONRules().forType(Stamp.self) { $0.dateStrategy = .native }
        XCTAssertEqual(try YYJSONDecoder.compatible(rules: automatic).decode(Stamp.self, from: unix).d.timeIntervalSince1970, 1_700_000_000)
        XCTAssertEqual(try YYJSONDecoder.legacy(rules: native).decode(Stamp.self, from: unix).d.timeIntervalSince1970, foundationSeconds)
    }

    func testUnassignedStrategyReadsAsPublishedDefault() {
        let configuration = YYModelConfiguration<Stamp>()
        XCTAssertEqual(configuration.dateStrategy, .automatic)
    }
}
