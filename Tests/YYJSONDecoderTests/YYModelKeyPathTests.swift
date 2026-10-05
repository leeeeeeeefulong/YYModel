import XCTest
import YYModelSwift

/// KeyPath 版配置 API 的回归测试。
///
/// 其中 `testDerivesTopLevelPropertyNames` 是**格式兜底断言**：
/// 属性名推导依赖 `String(describing: keyPath)` 形如 `\Type.property` 的输出。
/// 该格式多年稳定但 Apple 未正式承诺 —— 一旦未来工具链改变，
/// 这个测试会立刻红灯，而不是让映射静默失效。
final class YYModelKeyPathTests: XCTestCase {

    struct Inner: Codable, Equatable {
        var deep: String
    }

    struct Probe: Codable, Equatable {
        var text: String
        var number: Int
        var optional: String?
        var list: [Int]
        var table: [String: Int]
        var nested: Inner
    }

    private typealias Config = YYModelConfiguration<Probe>

    // MARK: - 属性名推导（格式兜底）

    func testDerivesTopLevelPropertyNames() {
        XCTAssertEqual(Config.propertyName(\Probe.text), "text")
        XCTAssertEqual(Config.propertyName(\Probe.number), "number")
        XCTAssertEqual(Config.propertyName(\Probe.optional), "optional")
        XCTAssertEqual(Config.propertyName(\Probe.list), "list")
        XCTAssertEqual(Config.propertyName(\Probe.table), "table")
        XCTAssertEqual(Config.propertyName(\Probe.nested), "nested")
    }

    // MARK: - 嵌套 KeyPath 必须被拒绝

    func testNestedKeyPathIsRejected() {
        XCTAssertThrowsError(
            try YYJSONRules().forType(Probe.self) { rule in
                rule.map(\.nested.deep, from: "deep")
            }
        ) { error in
            XCTAssertTrue("\(error)".contains("top-level property"), "实际错误：\(error)")
        }
    }

    // MARK: - 回归：字符串 API 的 CodingKey 契约不能被 KeyPath 限制污染
    //
    // 配置键是 CodingKey.stringValue，**不是** Swift 属性名，因此完全可能含点号
    //（`case value = "v.dot"`）。早期实现把「Swift 属性名不含点号」推广给了所有
    // 旧配置，导致合法的字符串规则被拒 —— 这里锁住该契约。

    func testDottedCodingKeyWorksWithStringMapper() throws {
        struct Dotted: Codable {
            var value: Int
            enum CodingKeys: String, CodingKey { case value = "v.dot" }
        }
        // 注意：mapper 的**值**是路径（"a.b" 会拆成 a→b）。
        // 要映射到字面含点号的 JSON 键，必须用 .key(...)。
        let rules = try YYJSONRules().forType(Dotted.self) { rule in
            rule.mapper = ["v.dot": .key("v.dot")]
        }
        let model = try YYJSONDecoder(mode: .compatible, rules: rules)
            .decode(Dotted.self, from: Data(#"{"v.dot":7}"#.utf8))
        XCTAssertEqual(model.value, 7)
    }

    /// 同上，但走嵌套路径形态，确认点号出现在**配置键**（CodingKey）一侧时不被误拒。
    func testDottedCodingKeyWithNestedPathValue() throws {
        struct Dotted: Codable {
            var value: Int
            enum CodingKeys: String, CodingKey { case value = "v.dot" }
        }
        let rules = try YYJSONRules().forType(Dotted.self) { rule in
            rule.mapper = ["v.dot": .path("outer", "v.dot")]
        }
        let model = try YYJSONDecoder(mode: .compatible, rules: rules)
            .decode(Dotted.self, from: Data(#"{"outer":{"v.dot":7}}"#.utf8))
        XCTAssertEqual(model.value, 7)
    }

    func testDottedCodingKeyWorksWithRequiredAndDefault() throws {
        struct Dotted: Codable {
            var value: Int
            var other: Int
            enum CodingKeys: String, CodingKey { case value = "v.dot", other }
        }
        let rules = try YYJSONRules().forType(Dotted.self) { rule in
            rule.requiredProperties = ["v.dot"]
            rule.defaultValues = ["other": 9]
        }
        let model = try YYJSONDecoder(mode: .compatible, rules: rules)
            .decode(Dotted.self, from: Data(#"{"v.dot":7}"#.utf8))
        XCTAssertEqual(model.value, 7)
        XCTAssertEqual(model.other, 9)
    }

    // MARK: - typed default 必须支持它接受的 Codable 值

    func testTypedDefaultAcceptsCodableValues() throws {
        struct Child: Codable, Equatable { var n: Int }
        struct Holder: Codable { var child: Child }

        let rules = try YYJSONRules().forType(Holder.self) { rule in
            rule.default(\.child, to: Child(n: 7))
        }
        let model = try YYJSONDecoder(mode: .compatible, rules: rules)
            .decode(Holder.self, from: Data(#"{}"#.utf8))
        XCTAssertEqual(model.child, Child(n: 7))
    }

    func testTypedDefaultAcceptsArrayOfCodableValues() throws {
        struct Child: Codable, Equatable { var n: Int }
        struct Holder: Codable { var children: [Child] }

        let rules = try YYJSONRules().forType(Holder.self) { rule in
            rule.default(\.children, to: [Child(n: 1), Child(n: 2)])
        }
        let model = try YYJSONDecoder(mode: .compatible, rules: rules)
            .decode(Holder.self, from: Data(#"{}"#.utf8))
        XCTAssertEqual(model.children, [Child(n: 1), Child(n: 2)])
    }

    func testTypedDefaultAcceptsRawRepresentableEnum() throws {
        struct Holder: Codable {
            var kind: Kind
            enum Kind: String, Codable { case a, b }
        }
        let rules = try YYJSONRules().forType(Holder.self) { rule in
            rule.default(\.kind, to: .b)
        }
        let model = try YYJSONDecoder(mode: .compatible, rules: rules)
            .decode(Holder.self, from: Data(#"{}"#.utf8))
        XCTAssertEqual(model.kind, .b)
    }

    func testNestedKeyPathIsRejectedInDefaultsAndFilters() {
        XCTAssertThrowsError(
            try YYJSONRules().forType(Probe.self) { rule in
                rule.default(\.nested.deep, to: "x")
            }
        )
        XCTAssertThrowsError(
            try YYJSONRules().forType(Probe.self) { rule in
                rule.require(\.nested.deep)
            }
        )
    }

    // MARK: - KeyPath 版与字符串版行为等价

    func testKeyPathConfigMatchesStringConfig() throws {
        let viaKeyPath = try YYJSONRules().forType(Probe.self) { rule in
            rule.map(\.text, from: "t")
            rule.require(\.number)
            rule.default(\.optional, to: "fallback")
        }
        let viaStrings = try YYJSONRules().forType(Probe.self) { rule in
            rule.mapper = ["text": "t"]
            rule.requiredProperties = ["number"]
            rule.defaultValues = ["optional": "fallback"]
        }

        let data = Data(#"{"t":"hello","number":7,"list":[1,2],"nested":{"deep":"d"},"table":{"k":1}}"#.utf8)
        let a = try YYJSONDecoder(mode: .compatible, rules: viaKeyPath).decode(Probe.self, from: data)
        let b = try YYJSONDecoder(mode: .compatible, rules: viaStrings).decode(Probe.self, from: data)

        XCTAssertEqual(a, b)
        XCTAssertEqual(a.text, "hello")
        XCTAssertEqual(a.number, 7)
        XCTAssertEqual(a.optional, "fallback")
    }

    // MARK: - 多别名 / 嵌套路径 / 字面点号键

    func testAliasesFallBackInDeclarationOrder() throws {
        let rules = try YYJSONRules().forType(Probe.self) { rule in
            rule.map(\.text, from: "missing", "alsoMissing", "t")
        }
        let data = Data(#"{"t":"third","number":1,"list":[],"nested":{"deep":""},"table":{}}"#.utf8)
        let model = try YYJSONDecoder(mode: .compatible, rules: rules).decode(Probe.self, from: data)
        XCTAssertEqual(model.text, "third")
    }

    func testNestedPathMapping() throws {
        let rules = try YYJSONRules().forType(Probe.self) { rule in
            rule.map(\.text, at: "outer", "inner")
        }
        let data = Data(#"{"outer":{"inner":"deep"},"number":1,"list":[],"nested":{"deep":""},"table":{}}"#.utf8)
        let model = try YYJSONDecoder(mode: .compatible, rules: rules).decode(Probe.self, from: data)
        XCTAssertEqual(model.text, "deep")
    }

    func testLiteralDottedKeyIsNotSplit() throws {
        let rules = try YYJSONRules().forType(Probe.self) { rule in
            rule.map(\.text, literalKey: "a.b")
        }
        let data = Data(#"{"a.b":"literal","number":1,"list":[],"nested":{"deep":""},"table":{}}"#.utf8)
        let model = try YYJSONDecoder(mode: .compatible, rules: rules).decode(Probe.self, from: data)
        XCTAssertEqual(model.text, "literal")
    }

    // MARK: - 类型安全默认值

    func testTypedDefaultValues() throws {
        let rules = try YYJSONRules().forType(Probe.self) { rule in
            rule.default(\.text, to: "unset")
            rule.default(\.list, to: [9])
            rule.default(\.table, to: ["k": 1])
        }
        let data = Data(#"{"number":1,"nested":{"deep":""}}"#.utf8)
        let model = try YYJSONDecoder(mode: .compatible, rules: rules).decode(Probe.self, from: data)
        XCTAssertEqual(model.text, "unset")
        XCTAssertEqual(model.list, [9])
        XCTAssertEqual(model.table, ["k": 1])
    }

    /// `default(_:to: nil)` 曾经把 Swift 的 Optional.none 直接塞进 [String: Any]，
    /// 触发 "Unsupported JSON value: Optional<String>"。现在应解包成 NSNull。
    func testNilDefaultForOptionalProperty() throws {
        let rules = try YYJSONRules().forType(Probe.self) { rule in
            rule.default(\.optional, to: nil)
        }
        let data = Data(#"{"text":"x","number":1,"list":[],"nested":{"deep":""},"table":{}}"#.utf8)
        let model = try YYJSONDecoder(mode: .compatible, rules: rules).decode(Probe.self, from: data)
        XCTAssertNil(model.optional)
    }

    /// 默认值只在「键不存在」时生效；显式 null 不被默认值覆盖。
    func testExplicitNullIsNotReplacedByDefault() throws {
        let rules = try YYJSONRules().forType(Probe.self) { rule in
            rule.default(\.text, to: "unset")
        }
        let data = Data(#"{"text":null,"number":1,"list":[],"nested":{"deep":""},"table":{}}"#.utf8)
        XCTAssertThrowsError(try YYJSONDecoder(mode: .compatible, rules: rules).decode(Probe.self, from: data))
    }

    // MARK: - required

    func testRequiredPropertyFailsWhenMissing() {
        let rules = (try? YYJSONRules().forType(Probe.self) { rule in
            rule.require(\.number)
        }) ?? YYJSONRules()
        let data = Data(#"{"text":"x","list":[],"nested":{"deep":""},"table":{}}"#.utf8)
        XCTAssertThrowsError(try YYJSONDecoder(mode: .compatible, rules: rules).decode(Probe.self, from: data))
    }

    // MARK: - 过滤

    func testOnlyKeepsListedProperties() throws {
        let rules = try YYJSONRules().forType(Probe.self) { rule in
            rule.only(\.text, \.number, \.optional, \.list, \.table, \.nested)
        }
        let data = Data(#"{"text":"x","number":1,"list":[],"nested":{"deep":""},"table":{}}"#.utf8)
        let model = try YYJSONDecoder(mode: .compatible, rules: rules).decode(Probe.self, from: data)
        XCTAssertEqual(model.text, "x")
    }
}
