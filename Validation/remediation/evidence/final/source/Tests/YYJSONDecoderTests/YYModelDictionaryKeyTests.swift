import XCTest
import YYModelSwift

/// 字典键类型的回归测试。
///
/// 命题：JSON 对象的键要能映射到 `String` / `Int`，以及官方给出的
/// `CodingKeyRepresentable` 自定义键类型 —— 而不是只有前两种硬编码。
final class YYModelDictionaryKeyTests: XCTestCase {

    // MARK: - String / Int（既有行为，防止回归）

    func testStringKeys() throws {
        struct Holder: Codable { var table: [String: Int] }
        let model = try YYJSONDecoder(mode: .compatible)
            .decode(Holder.self, from: Data(#"{"table":{"a":1,"b":2}}"#.utf8))
        XCTAssertEqual(model.table, ["a": 1, "b": 2])
    }

    func testIntKeys() throws {
        struct Holder: Codable { var table: [Int: String] }
        let model = try YYJSONDecoder(mode: .compatible)
            .decode(Holder.self, from: Data(#"{"table":{"1":"x","2":"y"}}"#.utf8))
        XCTAssertEqual(model.table, [1: "x", 2: "y"])
    }

    func testNonNumericIntKeyFails() {
        struct Holder: Codable { var table: [Int: String] }
        XCTAssertThrowsError(
            try YYJSONDecoder(mode: .compatible)
                .decode(Holder.self, from: Data(#"{"table":{"abc":"x"}}"#.utf8))
        )
    }

    // MARK: - CodingKeyRepresentable 自定义键

    /// 一个用 `CodingKeyRepresentable` 描述的自定义字典键。
    struct Slug: Hashable, Codable, CodingKeyRepresentable {
        var raw: String

        init(_ raw: String) { self.raw = raw }

        init?<T: CodingKey>(codingKey: T) { self.init(codingKey.stringValue) }

        var codingKey: any CodingKey { SlugKey(raw) }

        struct SlugKey: CodingKey {
            var stringValue: String
            var intValue: Int?
            init(_ value: String) { stringValue = value; intValue = nil }
            init?(stringValue: String) { self.init(stringValue) }
            init?(intValue: Int) { self.init("\(intValue)") }
        }

        init(from decoder: Decoder) throws {
            raw = try decoder.singleValueContainer().decode(String.self)
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer(); try c.encode(raw)
        }
    }

    func testCodingKeyRepresentableKeysDecode() throws {
        struct Holder: Codable { var table: [Slug: Int] }
        let model = try YYJSONDecoder(mode: .compatible)
            .decode(Holder.self, from: Data(#"{"table":{"alpha":1,"beta":2}}"#.utf8))
        XCTAssertEqual(model.table, [Slug("alpha"): 1, Slug("beta"): 2])
    }

    func testCodingKeyRepresentableKeysRoundTrip() throws {
        struct Holder: Codable { var table: [Slug: Int] }
        let original = Holder(table: [Slug("alpha"): 1, Slug("beta"): 2])
        let data = try YYJSONEncoder(mode: .compatible).encode(original)
        let restored = try YYJSONDecoder(mode: .compatible).decode(Holder.self, from: data)
        XCTAssertEqual(restored.table, original.table)
    }

    /// 导出必须是真正的 JSON 对象，而不是 key-value 交替数组。
    func testCodingKeyRepresentableKeysEncodeAsObject() throws {
        struct Holder: Codable { var table: [Slug: Int] }
        let object = try YYJSONEncoder(mode: .compatible)
            .encodeJSONObject(Holder(table: [Slug("alpha"): 1])) as? [String: Any]
        XCTAssertEqual(object?["table"] as? [String: Int], ["alpha": 1])
    }

    // MARK: - 不支持的键类型仍交回调用方

    func testUnsupportedKeyTypeFallsBackToDefaultHandling() throws {
        // Bool 不是 CodingKeyRepresentable，也不支持映射 → 应走普通模型路径并失败，
        // 而不是被静默当成空字典。
        struct Holder: Codable { var table: [Bool: Int] }
        XCTAssertThrowsError(
            try YYJSONDecoder(mode: .compatible)
                .decode(Holder.self, from: Data(#"{"table":{"true":1}}"#.utf8))
        )
    }
}
