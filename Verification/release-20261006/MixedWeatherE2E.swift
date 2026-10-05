import Foundation
import YYModel
import YYModelSwift

@objcMembers final class CurrentObjC: NSObject {
    var time = ""
    var interval = 0
    var temperature_2m = 0.0
    var relative_humidity_2m = 0
    var is_day = 0
    var precipitation = 0.0
    var wind_speed_10m = 0.0
}
@objcMembers final class CityObjC: NSObject {
    var latitude = 0.0
    var longitude = 0.0
    var elevation = 0.0
    var timezone = ""
    var current: CurrentObjC?
}
private struct CurrentSwift: Codable {
    var time: String
    var interval: Int
    var temperature_2m: Double
    var relative_humidity_2m: Int
    var is_day: Int
    var precipitation: Double
    var wind_speed_10m: Double
}
private struct CitySwift: Codable {
    var latitude: Double
    var longitude: Double
    var elevation: Double
    var timezone: String
    var current: CurrentSwift
}
private struct Row: Encodable {
    var scenario: String
    var expected: String
    var actual: String
    var passed: Bool
}
@main private struct MixedWeatherE2E {
    static func main() throws {
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [[String: Any]]
        var rows: [Row] = []
        func canonical(_ value: Any) throws -> String {
            String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self)
        }
        func check(_ name: String, expected: String, _ body: () throws -> String) {
            let actual: String
            do { actual = try body() } catch { actual = "error: \(error)" }
            rows.append(Row(scenario: name, expected: expected, actual: actual, passed: actual == expected))
        }
        for (index, city) in raw.enumerated() {
            let projection = city.filter { ["latitude", "longitude", "elevation", "timezone", "current"].contains($0.key) }
            let expected = try canonical(projection)
            let old = CityObjC.yy_model(withJSON: city)
            check("city.\(index).objc-reflection-export", expected: expected) {
                guard let old, let json = old.yy_modelToJSONObject() else { throw NSError(domain: "ObjCDecode", code: 1) }
                return try canonical(json)
            }
            check("city.\(index).objc-to-swift", expected: expected) {
                guard let data = old?.yy_modelToJSONData() else { throw NSError(domain: "ObjCExport", code: 1) }
                let swift = try YYJSONDecoder.compatible().decode(CitySwift.self, from: data)
                return try canonical(JSONSerialization.jsonObject(with: JSONEncoder().encode(swift)))
            }
            check("city.\(index).swift-to-objc", expected: expected) {
                let swift = try YYJSONDecoder.compatible().decode(CitySwift.self, from: city)
                let data = try YYJSONEncoder.compatible().encode(swift)
                guard let result = CityObjC.yy_model(withJSON: data)?.yy_modelToJSONObject() else { throw NSError(domain: "MixedDecode", code: 1) }
                return try canonical(result)
            }
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(rows).write(to: output)
        print("MixedWeatherE2E: \(rows.filter(\.passed).count)/\(rows.count)")
        if rows.contains(where: { !$0.passed }) { exit(1) }
    }
}
