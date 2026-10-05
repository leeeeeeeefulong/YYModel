import XCTest
import YYModelSwift

/// Lossy 数组的回归测试。
///
/// 命题：默认保持官方的严格语义（一个坏元素让整批失败）；
/// 显式开启 `rule.lossy(...)` 后才跳过坏元素，且**跳过项必须可查**，不能静默丢弃。
final class YYModelLossyTests: XCTestCase {

    struct Item: Codable, Equatable {
        var id: Int
        var name: String
    }

    struct Response: Codable {
        var results: [Item]
    }

    /// 第 1 个元素是坏的（"bad" 转不成 Int）
    private let mixedJSON = #"{"results":[{"id":1,"name":"a"},{"id":"bad","name":"b"},{"id":3,"name":"c"}]}"#
    private let cleanJSON = #"{"results":[{"id":1,"name":"a"},{"id":2,"name":"b"}]}"#

    private func lossyRules() throws -> YYJSONRules {
        try YYJSONRules().forType(Response.self) { rule in
            rule.lossy(\.results)
        }
    }

    // MARK: - 默认严格

    func testDefaultIsStrict() {
        XCTAssertThrowsError(
            try YYJSONDecoder(mode: .compatible).decode(Response.self, from: Data(mixedJSON.utf8)),
            "未开启 lossy 时，坏元素必须让整批失败（与官方一致）"
        )
    }

    // MARK: - 开启后跳过

    func testLossySkipsBadElement() throws {
        let response = try YYJSONDecoder(mode: .compatible, rules: try lossyRules())
            .decode(Response.self, from: Data(mixedJSON.utf8))

        XCTAssertEqual(response.results, [Item(id: 1, name: "a"), Item(id: 3, name: "c")],
                       "坏元素被跳过，好元素保持原顺序")
    }

    func testCleanArrayIsUnaffected() throws {
        let response = try YYJSONDecoder(mode: .compatible, rules: try lossyRules())
            .decode(Response.self, from: Data(cleanJSON.utf8))
        XCTAssertEqual(response.results.count, 2)
    }

    func testEmptyArray() throws {
        let response = try YYJSONDecoder(mode: .compatible, rules: try lossyRules())
            .decode(Response.self, from: Data(#"{"results":[]}"#.utf8))
        XCTAssertTrue(response.results.isEmpty)
    }

    func testAllElementsBadYieldsEmptyArray() throws {
        let json = #"{"results":[{"id":"x","name":"a"},{"id":"y","name":"b"}]}"#
        let response = try YYJSONDecoder(mode: .compatible, rules: try lossyRules())
            .decode(Response.self, from: Data(json.utf8))
        XCTAssertTrue(response.results.isEmpty)
    }

    // MARK: - 跳过必须可查（不静默）

    func testLossReportRecordsSkippedIndex() throws {
        let report = YYModelLossReport()
        var decoder = YYJSONDecoder(mode: .compatible, rules: try lossyRules())
        decoder.userInfo[YYModelLossReport.key] = report

        _ = try decoder.decode(Response.self, from: Data(mixedJSON.utf8))

        XCTAssertTrue(report.hasLosses)
        XCTAssertEqual(report.losses.count, 1)
        XCTAssertEqual(report.losses[0].property, "results")
        XCTAssertEqual(report.losses[0].index, 1, "必须记录被跳过元素的下标")
        XCTAssertFalse(report.losses[0].reason.isEmpty, "必须记录失败原因")
    }

    func testLossReportEmptyWhenNoLoss() throws {
        let report = YYModelLossReport()
        var decoder = YYJSONDecoder(mode: .compatible, rules: try lossyRules())
        decoder.userInfo[YYModelLossReport.key] = report

        _ = try decoder.decode(Response.self, from: Data(cleanJSON.utf8))
        XCTAssertFalse(report.hasLosses)
        XCTAssertTrue(report.losses.isEmpty)
    }

    /// 不传 report 时也必须能正常跳过，只是没人记录。
    func testLossyWorksWithoutReport() throws {
        let response = try YYJSONDecoder(mode: .compatible, rules: try lossyRules())
            .decode(Response.self, from: Data(mixedJSON.utf8))
        XCTAssertEqual(response.results.count, 2)
    }

    // MARK: - 与规则协作

    /// lossy 字段同时有别名映射时，两者都要生效。
    func testLossyWorksWithKeyMapping() throws {
        let rules = try YYJSONRules().forType(Response.self) { rule in
            rule.map(\.results, from: "items")
            rule.lossy(\.results)
        }
        let json = #"{"items":[{"id":1,"name":"a"},{"id":"bad","name":"b"}]}"#
        let response = try YYJSONDecoder(mode: .compatible, rules: rules)
            .decode(Response.self, from: Data(json.utf8))
        XCTAssertEqual(response.results, [Item(id: 1, name: "a")])
    }

    /// 只对标记过的字段生效。未标记字段的严格性由 `testUnmarkedArrayStillStrict` 单独验证。
    func testOnlyMarkedPropertiesAreLossy() throws {
        struct Two: Codable { var a: [Item]; var b: [Item] }
        let rules = try YYJSONRules().forType(Two.self) { rule in
            rule.lossy(\.a)
        }
        let json = #"{"a":[{"id":"bad","name":"x"},{"id":1,"name":"y"}],"b":[{"id":2,"name":"z"}]}"#
        let value = try YYJSONDecoder(mode: .compatible, rules: rules).decode(Two.self, from: Data(json.utf8))

        XCTAssertEqual(value.a, [Item(id: 1, name: "y")], "标记过的字段跳过坏元素")
        XCTAssertEqual(value.b, [Item(id: 2, name: "z")], "未标记的字段正常解析")
    }

    /// 未标记的字段仍应严格失败 —— 上面那个测试无法同时断言，单独再验一次。
    func testUnmarkedArrayStillStrict() {
        struct Two: Codable { var a: [Item]; var b: [Item] }
        let rules = (try? YYJSONRules().forType(Two.self) { rule in
            rule.lossy(\.a)
        }) ?? YYJSONRules()
        let json = #"{"a":[{"id":1,"name":"y"}],"b":[{"id":"bad","name":"z"}]}"#
        XCTAssertThrowsError(
            try YYJSONDecoder(mode: .compatible, rules: rules).decode(Two.self, from: Data(json.utf8)),
            "未标记 lossy 的数组必须保持严格"
        )
    }

    // MARK: - 嵌套模型元素

    func testLossyWithNestedModelElements() throws {
        struct Inner: Codable, Equatable { var v: Int }
        struct Outer: Codable { var inners: [Inner] }
        let rules = try YYJSONRules().forType(Outer.self) { rule in
            rule.lossy(\.inners)
        }
        let json = #"{"inners":[{"v":1},{"v":"bad"},{"v":3}]}"#
        let report = YYModelLossReport()
        var decoder = YYJSONDecoder(mode: .compatible, rules: rules)
        decoder.userInfo[YYModelLossReport.key] = report

        let value = try decoder.decode(Outer.self, from: Data(json.utf8))
        XCTAssertEqual(value.inners, [Inner(v: 1), Inner(v: 3)])
        XCTAssertEqual(report.losses.map(\.index), [1])
    }

    /// lossy 字段为 null / 缺失时，落回常规语义（这里用默认值）。
    ///
    /// 注意默认值必须是**可 JSON 表示**的值。KeyPath 版 `default` 的 `Value`
    /// 由属性推导为 `[Item]`，因此模型默认值只能用字符串版 `defaultValues`
    /// 以字典形态提供。
    func testLossyFallsBackToDefaultsWhenKeyMissing() throws {
        let rules = try YYJSONRules().forType(Response.self) { rule in
            rule.lossy(\.results)
            rule.defaultValues = ["results": [["id": 99, "name": "fallback"]]]
        }
        let response = try YYJSONDecoder(mode: .compatible, rules: rules)
            .decode(Response.self, from: Data(#"{}"#.utf8))
        XCTAssertEqual(response.results, [Item(id: 99, name: "fallback")])
    }

    /// 记录一个已知限制：KeyPath 版 `default` 无法给「模型类型」的默认值
    /// （`Value` 由属性推导，必须是 `[Item]`，而字面量只能是字典形态）。
    func testModelTypedDefaultCannotBeExpressedViaKeyPath() throws {
        let rules = try YYJSONRules().forType(Response.self) { rule in
            rule.lossy(\.results)
            rule.defaultValues = ["results": [["id": 99, "name": "fallback"]]]
        }
        // 字符串版可以表达；KeyPath 版在编译期就无法写出模型字面量 —— 这是类型安全的代价。
        let response = try YYJSONDecoder(mode: .compatible, rules: rules)
            .decode(Response.self, from: Data(#"{}"#.utf8))
        XCTAssertEqual(response.results.count, 1)
    }

    // MARK: - D3：顶层 decodeLossyArray 显式入口

    func testTopLevelLossyArraySkipsBadElements() throws {
        let (value, report) = try YYJSONDecoder.compatible()
            .decodeLossyArray([Int].self, from: Data(#"[1,"bad",3]"#.utf8))
        XCTAssertEqual(value, [1, 3])
        XCTAssertEqual(report.losses.count, 1)
        XCTAssertEqual(report.losses.first?.property, "(root)")
        XCTAssertEqual(report.losses.first?.index, 1)
    }

    func testTopLevelLossyArrayFromStringAndRaw() throws {
        let (fromString, rs) = try YYJSONDecoder.compatible().decodeLossyArray([Int].self, from: #"[1,"bad",3]"#)
        XCTAssertEqual(fromString, [1, 3]); XCTAssertEqual(rs.losses.count, 1)
        let (fromRaw, rr) = try YYJSONDecoder.compatible().decodeLossyArray([Int].self, from: [1, "bad", 3] as [Any])
        XCTAssertEqual(fromRaw, [1, 3]); XCTAssertEqual(rr.losses.count, 1)
    }

    func testTopLevelLossyAllBadYieldsEmpty() throws {
        let (value, report) = try YYJSONDecoder.compatible()
            .decodeLossyArray([Int].self, from: Data(#"["a","b"]"#.utf8))
        XCTAssertTrue(value.isEmpty)
        XCTAssertEqual(report.losses.count, 2)
    }

    func testTopLevelLossyModelElements() throws {
        struct Inner: Codable, Equatable { var v: Int }
        let (value, report) = try YYJSONDecoder.compatible()
            .decodeLossyArray([Inner].self, from: Data(#"[{"v":1},{"v":"bad"},{"v":3}]"#.utf8))
        XCTAssertEqual(value, [Inner(v: 1), Inner(v: 3)])
        XCTAssertEqual(report.losses.map(\.index), [1])
        XCTAssertEqual(report.losses.first?.property, "(root)")
    }

    func testTopLevelStrictDecodeUnchanged() throws {
        XCTAssertThrowsError(try YYJSONDecoder.compatible().decode([Int].self, from: Data(#"[1,"bad",3]"#.utf8)))
    }
}
