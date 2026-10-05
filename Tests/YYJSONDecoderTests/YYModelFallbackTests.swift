import XCTest
import YYModelSwift

/// 兜底值（`rule.fallback(...)`）的回归测试。
///
/// 命题：`default` 只管「键不存在」，而真实痛点往往在「值存在但解不出」——
/// 枚举未知值、无效 URL、类型不匹配。这些情况下 Optional 救不了，
/// 必须有显式的兜底入口。
final class YYModelFallbackTests: XCTestCase {

    enum Kind: String, Codable, Equatable {
        case live, replay, unknown
    }

    struct Link: Codable {
        var site: URL?
        var kind: Kind
    }

    // MARK: - 枚举未知值

    /// 服务端新增了 case，老版本 App 解析会抛 dataCorrupted。
    func testUnknownEnumCaseFallsBack() throws {
        let rules = try YYJSONRules().forType(Link.self) { rule in
            rule.fallback(\.kind, to: .unknown)
        }
        let json = #"{"kind":"brand_new_case"}"#
        let model = try YYJSONDecoder(mode: .compatible, rules: rules)
            .decode(Link.self, from: Data(json.utf8))
        XCTAssertEqual(model.kind, .unknown)
    }

    /// 未注册兜底时，未知枚举值必须仍然失败（保持严格语义）。
    func testUnknownEnumCaseWithoutFallbackStillFails() {
        XCTAssertThrowsError(
            try YYJSONDecoder(mode: .compatible)
                .decode(Link.self, from: Data(#"{"kind":"brand_new_case"}"#.utf8))
        )
    }

    /// 已知值不受兜底影响。
    func testKnownEnumCaseIsNotReplacedByFallback() throws {
        let rules = try YYJSONRules().forType(Link.self) { rule in
            rule.fallback(\.kind, to: .unknown)
        }
        let model = try YYJSONDecoder(mode: .compatible, rules: rules)
            .decode(Link.self, from: Data(#"{"kind":"replay"}"#.utf8))
        XCTAssertEqual(model.kind, .replay)
    }

    // MARK: - 无效 URL

    /// 空字符串 URL 会抛 dataCorrupted（"Invalid URL string."）。
    func testInvalidURLFallsBackToNil() throws {
        let rules = try YYJSONRules().forType(Link.self) { rule in
            rule.fallback(\.site, to: nil)
            rule.fallback(\.kind, to: .unknown)
        }
        let model = try YYJSONDecoder(mode: .compatible, rules: rules)
            .decode(Link.self, from: Data(#"{"site":"","kind":"live"}"#.utf8))
        XCTAssertNil(model.site)
        XCTAssertEqual(model.kind, .live)
    }

    func testInvalidURLWithoutFallbackStillFails() {
        XCTAssertThrowsError(
            try YYJSONDecoder(mode: .compatible)
                .decode(Link.self, from: Data(#"{"site":"","kind":"live"}"#.utf8))
        )
    }

    func testValidURLIsNotReplacedByFallback() throws {
        let rules = try YYJSONRules().forType(Link.self) { rule in
            rule.fallback(\.site, to: nil)
        }
        let model = try YYJSONDecoder(mode: .compatible, rules: rules)
            .decode(Link.self, from: Data(#"{"site":"https://example.com","kind":"live"}"#.utf8))
        XCTAssertEqual(model.site?.absoluteString, "https://example.com")
    }

    // MARK: - 缺失 / null

    func testMissingKeyUsesFallback() throws {
        let rules = try YYJSONRules().forType(Link.self) { rule in
            rule.fallback(\.kind, to: .unknown)
        }
        let model = try YYJSONDecoder(mode: .compatible, rules: rules)
            .decode(Link.self, from: Data(#"{}"#.utf8))
        XCTAssertEqual(model.kind, .unknown)
    }

    func testExplicitNullUsesFallback() throws {
        let rules = try YYJSONRules().forType(Link.self) { rule in
            rule.fallback(\.kind, to: .unknown)
        }
        let model = try YYJSONDecoder(mode: .compatible, rules: rules)
            .decode(Link.self, from: Data(#"{"kind":null}"#.utf8))
        XCTAssertEqual(model.kind, .unknown)
    }

    // MARK: - 类型不匹配

    func testTypeMismatchUsesFallback() throws {
        struct Holder: Codable { var count: Int }
        let rules = try YYJSONRules().forType(Holder.self) { rule in
            rule.fallback(\.count, to: 0)
        }
        let model = try YYJSONDecoder(mode: .compatible, rules: rules)
            .decode(Holder.self, from: Data(#"{"count":"not-a-number"}"#.utf8))
        XCTAssertEqual(model.count, 0)
    }

    // MARK: - 与 default 的语义差异

    /// `default` 不管「值存在但解不出」—— 那正是 fallback 存在的理由。
    func testDefaultDoesNotCoverInvalidValue() {
        let rules = (try? YYJSONRules().forType(Link.self) { rule in
            rule.default(\.kind, to: .unknown)
        }) ?? YYJSONRules()
        XCTAssertThrowsError(
            try YYJSONDecoder(mode: .compatible, rules: rules)
                .decode(Link.self, from: Data(#"{"kind":"brand_new_case"}"#.utf8)),
            "default 只在键缺失时生效，解不出的值仍应失败"
        )
    }

    /// fallback 覆盖 default 的全部场景。
    func testFallbackAlsoCoversMissingKeyLikeDefault() throws {
        let rules = try YYJSONRules().forType(Link.self) { rule in
            rule.fallback(\.kind, to: .replay)
        }
        let model = try YYJSONDecoder(mode: .compatible, rules: rules)
            .decode(Link.self, from: Data(#"{}"#.utf8))
        XCTAssertEqual(model.kind, .replay)
    }

    // MARK: - 不重试（无副作用风险）

    /// 兜底字段至多尝试解码一次 —— 失败即返回兜底，不会让模型 init 跑第二次。
    func testFallbackDoesNotRetryModelInitialization() throws {
        FallbackRetryProbe.reset()
        let rules = try YYJSONRules().forType(FallbackRetryOuter.self) { rule in
            rule.fallback(\.inner, to: FallbackRetryInner(n: -1))
        }
        let model = try YYJSONDecoder(mode: .compatible, rules: rules)
            .decode(FallbackRetryOuter.self, from: Data(#"{"inner":{"n":"bad"}}"#.utf8))

        XCTAssertEqual(model.inner.n, -1, "应返回兜底值")
        XCTAssertEqual(FallbackRetryProbe.initCount, 1, "失败的 init 只应执行一次，不得重试")
    }
}

// MARK: - 文件级辅助类型（嵌套 struct 无法捕获外层变量，故放在文件作用域）

private enum FallbackRetryProbe {
    nonisolated(unsafe) static var initCount = 0
    static func reset() { initCount = 0 }
}

private struct FallbackRetryInner: Codable {
    var n: Int
    init(n: Int) { self.n = n }
    init(from decoder: Decoder) throws {
        FallbackRetryProbe.initCount += 1
        let container = try decoder.container(keyedBy: CodingKeys.self)
        n = try container.decode(Int.self, forKey: .n)
    }
    enum CodingKeys: String, CodingKey { case n }
}

private struct FallbackRetryOuter: Codable {
    var inner: FallbackRetryInner
}
