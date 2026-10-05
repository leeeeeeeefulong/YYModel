import XCTest
import YYModelSwift

/// 三态取值（`YYModelPresence`）与增量更新语义的回归测试。
///
/// 核心命题：普通 Codable 把「键缺失」和「键为 null」折叠成同一个 nil，
/// 三态类型必须把它们区分开 —— 这是增量更新（只回传变更字段的接口）的前提。
final class YYModelPresenceTests: XCTestCase {

    struct Song: Codable, Equatable {
        var id: Int
        var name: String
        var file: YYModelPresence<String>
        var likeCount: YYModelPresence<Int>
    }

    private func decode(_ json: String) throws -> Song {
        try YYJSONDecoder(mode: .compatible).decode(Song.self, from: Data(json.utf8))
    }

    // MARK: - 三态判定

    func testPresentWithValue() throws {
        let song = try decode(#"{"id":1,"name":"n","file":"a.mp3","likeCount":7}"#)
        XCTAssertEqual(song.file, .value("a.mp3"))
        XCTAssertEqual(song.likeCount, .value(7))
    }

    func testPresentWithNull() throws {
        let song = try decode(#"{"id":1,"name":"n","file":null,"likeCount":null}"#)
        XCTAssertEqual(song.file, .null)
        XCTAssertEqual(song.likeCount, .null)
    }

    func testKeyAbsent() throws {
        // 只有 id 和 name —— file / likeCount 两个键完全不存在
        let song = try decode(#"{"id":1,"name":"n"}"#)
        XCTAssertEqual(song.file, .absent)
        XCTAssertEqual(song.likeCount, .absent)
    }

    /// 三种状态必须互不相同 —— 这正是普通 `String?` 做不到的。
    func testThreeStatesAreDistinguishable() throws {
        let withValue = try decode(#"{"id":1,"name":"n","file":"a"}"#).file
        let withNull = try decode(#"{"id":1,"name":"n","file":null}"#).file
        let absent = try decode(#"{"id":1,"name":"n"}"#).file

        XCTAssertNotEqual(withValue, withNull)
        XCTAssertNotEqual(withValue, absent)
        XCTAssertNotEqual(withNull, absent)

        XCTAssertTrue(withValue.isPresent)
        XCTAssertTrue(withNull.isPresent)
        XCTAssertFalse(absent.isPresent)
        XCTAssertTrue(withNull.isNull)
        XCTAssertFalse(absent.isNull)
    }

    // MARK: - 增量更新语义

    func testResolveKeepingSemantics() {
        // 已有值 "old"
        XCTAssertEqual(YYModelPresence<String>.value("new").resolve(keeping: "old"), "new")  // 更新
        XCTAssertEqual(YYModelPresence<String>.null.resolve(keeping: "old"), nil)            // 清空
        XCTAssertEqual(YYModelPresence<String>.absent.resolve(keeping: "old"), "old")        // 保留

        // 原本为空
        XCTAssertEqual(YYModelPresence<String>.absent.resolve(keeping: nil), nil)
    }

    /// 端到端：模拟「只回传变更字段」的接口做增量写回。
    func testIncrementalUpdateEndToEnd() throws {
        // 数据库里已有一条记录
        var storedFile: String? = "old.mp3"
        var storedLikeCount: Int? = 3

        // 服务端只回传了 likeCount 的变更，file 键根本没出现
        let patch = try decode(#"{"id":1,"name":"n","likeCount":9}"#)

        storedFile = patch.file.resolve(keeping: storedFile)
        storedLikeCount = patch.likeCount.resolve(keeping: storedLikeCount)

        XCTAssertEqual(storedFile, "old.mp3", "file 键未出现，必须保留原值")
        XCTAssertEqual(storedLikeCount, 9, "likeCount 有值，应更新")

        // 再收一次：这次服务端显式要求清空 file
        let clear = try decode(#"{"id":1,"name":"n","file":null,"likeCount":9}"#)
        storedFile = clear.file.resolve(keeping: storedFile)
        XCTAssertNil(storedFile, "file 为 null，应清空")
    }

    // MARK: - 导出

    func testEncodingSkipsAbsentKey() throws {
        let song = Song(id: 1, name: "n", file: .absent, likeCount: .value(7))
        let object = try YYJSONEncoder(mode: .compatible).encodeJSONObject(song) as? [String: Any]

        XCTAssertNil(object?["file"], ".absent 必须完全省略该键，不能写 null")
        XCTAssertEqual(object?["likeCount"] as? Int, 7)
        XCTAssertEqual(object?["name"] as? String, "n")
    }

    func testEncodingWritesNull() throws {
        let song = Song(id: 1, name: "n", file: .null, likeCount: .absent)
        let object = try YYJSONEncoder(mode: .compatible).encodeJSONObject(song) as? [String: Any]

        XCTAssertTrue(object?["file"] is NSNull, ".null 必须写成显式 null")
        XCTAssertNil(object?["likeCount"])
    }

    /// 往返：三态编码后必须还能解回同样的三态。
    func testRoundTripPreservesAllThreeStates() throws {
        for original in [
            Song(id: 1, name: "n", file: .value("a.mp3"), likeCount: .value(7)),
            Song(id: 1, name: "n", file: .null, likeCount: .null),
            Song(id: 1, name: "n", file: .absent, likeCount: .absent)
        ] {
            let data = try YYJSONEncoder(mode: .compatible).encode(original)
            let restored = try YYJSONDecoder(mode: .compatible).decode(Song.self, from: data)
            XCTAssertEqual(restored, original, "三态往返不一致：\(original)")
        }
    }

    // MARK: - 与既有能力协作

    /// 三态字段也要支持别名映射。
    func testPresenceWorksWithKeyMapping() throws {
        let rules = try YYJSONRules().forType(Song.self) { rule in
            rule.map(\.file, from: "file_url")
        }
        let json = #"{"id":1,"name":"n","file_url":"mapped.mp3"}"#
        let song = try YYJSONDecoder(mode: .compatible, rules: rules).decode(Song.self, from: Data(json.utf8))
        XCTAssertEqual(song.file, .value("mapped.mp3"))
        XCTAssertEqual(song.likeCount, .absent)
    }

    /// 三态字段不应因为「缺失」而失败 —— 即使它没有被标为 Optional。
    func testPresenceNeverThrowsOnMissing() throws {
        XCTAssertNoThrow(try decode(#"{"id":1,"name":"n"}"#))
        // 对照：普通非可选字段缺失会抛错
        XCTAssertThrowsError(
            try YYJSONDecoder(mode: .compatible).decode(Song.self, from: Data(#"{"id":1}"#.utf8))
        )
    }

    /// 三态类型也支持嵌套模型。
    func testPresenceOfNestedModel() throws {
        struct Outer: Codable {
            var id: Int
            var inner: YYModelPresence<Inner>
        }
        struct Inner: Codable, Equatable { var v: Int }

        let withValue = try YYJSONDecoder(mode: .compatible).decode(Outer.self, from: Data(#"{"id":1,"inner":{"v":5}}"#.utf8))
        XCTAssertEqual(withValue.inner, .value(Inner(v: 5)))

        let withNull = try YYJSONDecoder(mode: .compatible).decode(Outer.self, from: Data(#"{"id":1,"inner":null}"#.utf8))
        XCTAssertEqual(withNull.inner, .null)

        let absent = try YYJSONDecoder(mode: .compatible).decode(Outer.self, from: Data(#"{"id":1}"#.utf8))
        XCTAssertEqual(absent.inner, .absent)
    }
}
