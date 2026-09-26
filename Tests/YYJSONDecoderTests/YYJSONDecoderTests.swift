import XCTest
import YYModel
import YYModelSwift

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

    struct Stamp: Codable {
        var created: Date
    }

    enum Kind: String, Codable {
        case live
    }

    struct Link: Codable {
        var site: URL?
        var kind: Kind?
    }

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        )
        return try Data(contentsOf: url)
    }

    func testS1Coercion() throws {
        let level = try YYJSONDecoder().decode(Level.self, from: try fixture("s1-coercion"))
        XCTAssertEqual(level.floorNumber, 3)
        XCTAssertEqual(level.title, "8")
        XCTAssertNil(level.icon)
        XCTAssertTrue(level.hot)
        XCTAssertEqual(level.score, 1.5)
        XCTAssertEqual(level.anchors, [Anchor(nick: "a", age: 18), Anchor(nick: "b", age: nil)])
    }

    func testS2NullBecomesZero() throws {
        let level = try YYJSONDecoder().decode(Level.self, from: try fixture("s2-null"))
        XCTAssertEqual(level, Level(floorNumber: 0, title: "", icon: nil, hot: false, score: 0, anchors: []))
    }

    func testS3MissingObjectBecomesZero() throws {
        let level = try YYJSONDecoder().decode(Level.self, from: try fixture("s3-missing"))
        XCTAssertEqual(level, Level(floorNumber: 0, title: "", icon: nil, hot: false, score: 0, anchors: []))
    }

    func testS4TopLevelArrayCoercion() throws {
        let anchors = try YYJSONDecoder().decode([Anchor].self, from: try fixture("s4-anchors"))
        XCTAssertEqual(anchors, [Anchor(nick: "a", age: nil), Anchor(nick: "1", age: nil)])
    }

    func testS5BoolFromZeroAndOne() throws {
        let level = try YYJSONDecoder().decode(Level.self, from: try fixture("s5-bool-number"))
        XCTAssertEqual(level.floorNumber, 1)
        XCTAssertEqual(level.title, "晚场")
        XCTAssertFalse(level.hot)
        XCTAssertEqual(level.score, 2)
        XCTAssertTrue(level.anchors.isEmpty)
    }

    func testS6ISODate() throws {
        let stamp = try YYJSONDecoder().decode(Stamp.self, from: try fixture("s6-date-iso"))
        let expected = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-05T12:00:00Z"))
        XCTAssertEqual(stamp.created, expected)
    }

    func testS7UnixDate() throws {
        let stamp = try YYJSONDecoder().decode(Stamp.self, from: try fixture("s7-date-unix"))
        XCTAssertEqual(stamp.created, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testS8OptionalURLAndEnum() throws {
        let link = try YYJSONDecoder().decode(Link.self, from: try fixture("s8-link"))
        XCTAssertEqual(link.site, URL(string: "https://example.com"))
        XCTAssertEqual(link.kind, .live)
    }

    func testS9MissingOptionalURLAndEnum() throws {
        let link = try YYJSONDecoder().decode(Link.self, from: try fixture("s9-link-missing"))
        XCTAssertNil(link.site)
        XCTAssertNil(link.kind)
    }

    func testS10UncoercibleValueThrows() throws {
        XCTAssertThrowsError(try YYJSONDecoder().decode(Level.self, from: try fixture("s10-bad-floor")))
    }

    func testParsedObjectMatchesFixtureFile() throws {
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: try fixture("s5-bool-number")) as? [String: Any])
        let level = try YYJSONDecoder().decode(Level.self, from: object)
        XCTAssertEqual(level.title, "晚场")
        XCTAssertFalse(level.hot)
    }

    func testObjectiveCModelStillDecodes() throws {
        let box = try XCTUnwrap(YYBox.yy_model(withJSON: #"{"name":"yy"}"#))
        XCTAssertEqual(box.name, "yy")
    }

    func testUsersFixturePerformance() throws {
        let data = try fixture("users")
        let iterations = 1000

        _ = try YYJSONDecoder().decode([SwiftUser].self, from: data)
        let swiftDecode = try elapsed(iterations) {
            _ = try YYJSONDecoder().decode([SwiftUser].self, from: data)
        }
        let users = try YYJSONDecoder().decode([SwiftUser].self, from: data)
        XCTAssertEqual(users.count, 10)
        XCTAssertEqual(users[0].name, "Leanne Graham")
        XCTAssertEqual(users[0].address.city, "Gwenborough")
        let swiftEncode = elapsed(iterations) {
            _ = try? JSONEncoder().encode(users)
        }

        _ = NSArray.yy_modelArray(with: OCUser.self, json: data)
        let mixedDecode = elapsed(iterations) {
            _ = NSArray.yy_modelArray(with: OCUser.self, json: data)
        }
        let mixedUsers = try XCTUnwrap(NSArray.yy_modelArray(with: OCUser.self, json: data) as? [OCUser])
        XCTAssertEqual(mixedUsers.count, 10)
        XCTAssertEqual(mixedUsers[0].companyName, "Romaguera-Crona")
        let mixedEncode = elapsed(iterations) {
            _ = (mixedUsers as NSArray).yy_modelToJSONObject()
        }

        print(String(format: "SWIFT_DECODE %.2fms %.3fms", swiftDecode.total, swiftDecode.each))
        print(String(format: "SWIFT_ENCODE %.2fms %.3fms", swiftEncode.total, swiftEncode.each))
        print(String(format: "MIXED_DECODE %.2fms %.3fms", mixedDecode.total, mixedDecode.each))
        print(String(format: "MIXED_ENCODE %.2fms %.3fms", mixedEncode.total, mixedEncode.each))
    }
}

private struct SwiftGeo: Codable {
    var lat: String
    var lng: String
}

private struct SwiftAddress: Codable {
    var street: String
    var suite: String
    var city: String
    var zipcode: String
    var geo: SwiftGeo
}

private struct SwiftCompany: Codable {
    var name: String
    var catchPhrase: String
    var bs: String
}

private struct SwiftUser: Codable {
    var userId: Int
    var name: String
    var username: String
    var email: String
    var phone: String
    var website: String
    var address: SwiftAddress
    var company: SwiftCompany

    enum CodingKeys: String, CodingKey {
        case userId = "id"
        case name, username, email, phone, website, address, company
    }
}

private final class OCGeo: NSObject {
    @objc var lat: String = ""
    @objc var lng: String = ""
}

private final class OCAddress: NSObject {
    @objc var street: String = ""
    @objc var suite: String = ""
    @objc var city: String = ""
    @objc var zipcode: String = ""
    @objc var geo: OCGeo?
}

private final class OCCompany: NSObject {
    @objc var name: String = ""
    @objc var catchPhrase: String = ""
    @objc var bs: String = ""
}

private final class OCUser: NSObject {
    @objc var userId: Int = 0
    @objc var name: String = ""
    @objc var username: String = ""
    @objc var email: String = ""
    @objc var phone: String = ""
    @objc var website: String = ""
    @objc var address: OCAddress?
    @objc var company: OCCompany?
    @objc var companyName: String = ""
    @objc var homepage: String = ""

    override class func modelCustomPropertyMapper() -> [String: Any]? {
        [
            "userId": "id",
            "companyName": "company.name",
            "homepage": ["website", "homepage", "url"]
        ]
    }
}

private struct Timing {
    var total: Double
    var each: Double
}

private func elapsed(_ iterations: Int, _ body: () throws -> Void) rethrows -> Timing {
    let start = CFAbsoluteTimeGetCurrent()
    for _ in 0..<iterations {
        try body()
    }
    let total = (CFAbsoluteTimeGetCurrent() - start) * 1000
    return Timing(total: total, each: total / Double(iterations))
}

private final class YYBox: NSObject {
    @objc var name: String = ""
}
