import YYModelSwift
import PublishedYY
import Foundation

struct Current: Codable {
    let time: String
    let interval: Int
    let temperature_2m: Double
    let relative_humidity_2m: Int
    let is_day: Int
    let precipitation: Double
    let weather_code: Int
    let wind_speed_10m: Double
}
struct Hourly: Codable {
    let time: [String]
    let temperature_2m: [Double?]
    let relative_humidity_2m: [Int?]
    let precipitation_probability: [Int?]
    let precipitation: [Double?]
    let weather_code: [Int?]
    let wind_speed_10m: [Double?]
}
struct Daily: Codable {
    let time: [String]
    let temperature_2m_max: [Double?]
    let temperature_2m_min: [Double?]
    let precipitation_sum: [Double?]
    let sunrise: [String]
    let sunset: [String]
}
struct Forecast: Codable {
    let latitude: Double
    let longitude: Double
    let generationtime_ms: Double
    let utc_offset_seconds: Int
    let timezone: String
    let timezone_abbreviation: String
    let elevation: Double
    let current_units: [String: String]
    let hourly_units: [String: String]
    let daily_units: [String: String]
    let current: Current
    let hourly: Hourly?
    let daily: Daily
}
struct Request: Codable { let trace_id: String }
struct Payload: Codable { let locations: [Forecast] }
struct Envelope: Codable { let request: Request; let payload: Payload; let ok: Bool; let warnings: [String?] }

@main enum WeatherRunner {
    static func main() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        let engine = CommandLine.arguments[3]
        let iterations = Int(CommandLine.arguments[4])!
        let foundation = JSONDecoder()
        let native = YYModelSwift.YYJSONDecoder(mode: .native)
        let rules = try YYJSONRules().forType(Forecast.self) { $0.defaultValues = ["latitude": 0] }
        let compatible = YYModelSwift.YYJSONDecoder(mode: .compatible, rules: rules)
        let published = PublishedYY.YYJSONDecoder()
        let object = try JSONSerialization.jsonObject(with: data)
        func parse() throws -> Envelope {
            switch engine {
            case "foundation": return try foundation.decode(Envelope.self, from: data)
            case "native": return try native.decode(Envelope.self, from: data)
            case "published": return try published.decode(Envelope.self, from: data)
            case "object": return try compatible.decode(Envelope.self, from: object)
            default: return try compatible.decode(Envelope.self, from: data)
            }
        }
        var result: [String: Any] = ["engine": engine, "iterations": iterations, "bytes": data.count]
        do {
            let model = try parse()
            let encoded = try YYJSONEncoder(mode: .compatible, rules: rules).encode(model)
            result["modelJSON"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(model))
            result["roundTripJSON"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(compatible.decode(Envelope.self, from: encoded)))
            if iterations > 0 {
                for _ in 0..<5 { _ = try autoreleasepool { try parse() } }
                var samples: [Double] = []; var consumed = 0.0
                for _ in 0..<7 {
                    let start = ProcessInfo.processInfo.systemUptime
                    for _ in 0..<iterations { consumed += try autoreleasepool { try parse().payload.locations[0].current.temperature_2m } }
                    samples.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
                }
                result["sampleMilliseconds"] = samples; result["consumed"] = consumed
            }
        } catch { result["error"] = String(describing: error) }
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: output)
    }
}
