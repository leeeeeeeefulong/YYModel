import XCTest
import YYModel
import YYModelSwift

private final class YYBox: NSObject {
    @objc var name: String = ""
}

final class YYJSONDecoderTests: XCTestCase {
    struct Anchor: Codable, Equatable {
        var nick: String
        var age: Int?
    }

    struct Level: Codable, Equatable {
        var floorNumber: Int
        var title: String
        var icon: String?
        var hot: Bool
        var score: Double
        var anchors: [Anchor]

        enum CodingKeys: String, CodingKey {
            case floorNumber = "floor"
            case title
            case icon
            case hot
            case score
            case anchors
        }
    }

    func testCoercionAndMissingKeys() throws {
        let json = """
        {"floor":"3","title":8,"hot":"true","score":"1.5","extra":1,"anchors":[{"nick":"a","age":"18"},{"nick":"b"}]}
        """.data(using: .utf8)!
        let level = try YYJSONDecoder().decode(Level.self, from: json)
        XCTAssertEqual(level.floorNumber, 3)
        XCTAssertEqual(level.title, "8")
        XCTAssertNil(level.icon)
        XCTAssertTrue(level.hot)
        XCTAssertEqual(level.score, 1.5)
        XCTAssertEqual(level.anchors, [Anchor(nick: "a", age: 18), Anchor(nick: "b", age: nil)])
    }

    func testNullAndEmptyObject() throws {
        let json = #"{"floor":null,"title":null,"hot":null,"score":null,"anchors":null}"#.data(using: .utf8)!
        let level = try YYJSONDecoder().decode(Level.self, from: json)
        XCTAssertEqual(level, Level(floorNumber: 0, title: "", icon: nil, hot: false, score: 0, anchors: []))
    }

    func testDictionaryObjectAndNestedArray() throws {
        let object: [String: Any] = [
            "floor": 2,
            "title": "晚场",
            "anchors": [["nick": "主持", "age": 1]]
        ]
        let level = try YYJSONDecoder().decode(Level.self, from: object)
        XCTAssertEqual(level.floorNumber, 2)
        XCTAssertEqual(level.anchors.first?.nick, "主持")
    }

    func testTopLevelArray() throws {
        let json = #"[{"nick":"a"},{"nick":1}]"#.data(using: .utf8)!
        let anchors = try YYJSONDecoder().decode([Anchor].self, from: json)
        XCTAssertEqual(anchors, [Anchor(nick: "a", age: nil), Anchor(nick: "1", age: nil)])
    }

    func testUncoercibleValueThrows() {
        let json = #"{"floor":"nope","title":"x"}"#.data(using: .utf8)!
        XCTAssertThrowsError(try YYJSONDecoder().decode(Level.self, from: json))
    }

    func testObjectiveCModelStillDecodes() throws {
        let box = try XCTUnwrap(YYBox.yy_model(withJSON: #"{"name":"yy"}"#))
        XCTAssertEqual(box.name, "yy")
    }
}
