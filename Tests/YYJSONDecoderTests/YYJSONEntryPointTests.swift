import XCTest
import YYModelSwift

/// 显式入口的回归测试。
///
/// 命题：无参构造的旧语义**保持不变**（这是已发布的调用契约），
/// 同时提供命名入口让「选哪种模式」在调用处可见。
final class YYJSONEntryPointTests: XCTestCase {

    struct User: Codable, Equatable { var id: Int; var name: String }

    // MARK: - 命名入口与既有模式等价

    func testNamedEntryPointsMatchTheirModes() throws {
        let json = Data(#"{"id":1,"name":"x"}"#.utf8)
        let expected = User(id: 1, name: "x")

        XCTAssertEqual(try YYJSONDecoder.native().decode(User.self, from: json), expected)
        XCTAssertEqual(try YYJSONDecoder.compatible().decode(User.self, from: json), expected)
        XCTAssertEqual(try YYJSONDecoder.legacy().decode(User.self, from: json), expected)
    }

    func testCompatibleEntryCarriesRules() throws {
        let rules = try YYJSONRules().forType(User.self) { rule in
            rule.map(\.id, from: "uid")
        }
        let model = try YYJSONDecoder.compatible(rules: rules)
            .decode(User.self, from: Data(#"{"uid":7,"name":"y"}"#.utf8))
        XCTAssertEqual(model, User(id: 7, name: "y"))
    }

    // MARK: - ★ 旧默认语义必须保持不变

    /// 无参构造仍是 `.legacy`：缺失的非可选字段补零，而不是抛错。
    func testNoArgumentDefaultKeepsLegacySemantics() throws {
        let model = try YYJSONDecoder().decode(User.self, from: Data(#"{"name":"z"}"#.utf8))
        XCTAssertEqual(model.id, 0, "无参构造必须保持旧零值语义")
    }

    /// 命名入口不得悄悄改变旧行为。
    func testLegacyEntryEqualsNoArgumentDefault() throws {
        let json = Data(#"{"name":"z"}"#.utf8)
        let viaDefault = try YYJSONDecoder().decode(User.self, from: json)
        let viaNamed = try YYJSONDecoder.legacy().decode(User.self, from: json)
        XCTAssertEqual(viaDefault, viaNamed)
    }

    /// 对照：`.native` / `.compatible` 在同样输入下**不**补零 —— 差异是真实存在的，
    /// 所以「改默认值」才需要迁移安排，不能悄悄做。
    func testNativeAndCompatibleDoNotZeroFill() {
        XCTAssertThrowsError(try YYJSONDecoder.native().decode(User.self, from: Data(#"{"name":"z"}"#.utf8)))
        XCTAssertThrowsError(try YYJSONDecoder.compatible().decode(User.self, from: Data(#"{"name":"z"}"#.utf8)))
    }

    // MARK: - 编码侧

    func testEncoderEntryPointsAreSymmetric() throws {
        let value = User(id: 1, name: "x")
        for encoder in [YYJSONEncoder.native(), YYJSONEncoder.compatible(), YYJSONEncoder.legacy()] {
            let data = try encoder.encode(value)
            XCTAssertEqual(try JSONDecoder().decode(User.self, from: data), value)
        }
    }

    /// `.native` 遇到非空规则必须明确报错，而不是静默忽略配置。
    func testNativeRejectsRules() throws {
        let rules = try YYJSONRules().forType(User.self) { rule in
            rule.map(\.id, from: "uid")
        }
        let decoder = YYJSONDecoder(mode: .native, rules: rules)
        XCTAssertThrowsError(try decoder.decode(User.self, from: Data(#"{"id":1,"name":"x"}"#.utf8)))
    }
}
