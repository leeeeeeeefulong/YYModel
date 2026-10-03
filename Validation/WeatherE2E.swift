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

@main struct Runner {
    static func summary(_ model: Envelope) -> [String: Any] {
        let forecasts = model.payload.locations
        return ["locations":forecasts.count,
                "hours":forecasts.reduce(0) { $0 + ($1.hourly?.time.count ?? 0) },
                "days":forecasts.reduce(0) { $0 + $1.daily.time.count },
                "latitudeSum":forecasts.reduce(0.0) { $0 + $1.latitude },
                "currentTemperatureSum":forecasts.reduce(0.0) { $0 + $1.current.temperature_2m },
                "hourlyTemperatureSum":forecasts.reduce(0.0) { $0 + ($1.hourly?.temperature_2m.compactMap { $0 }.reduce(0,+) ?? 0) },
                "hourlyTemperatureCount":forecasts.reduce(0) { $0 + ($1.hourly?.temperature_2m.count ?? 0) },
                "unitKeys":forecasts.reduce(0) { $0 + $1.current_units.count + $1.hourly_units.count + $1.daily_units.count },
                "trace":model.request.trace_id,"ok":model.ok,"warnings":model.warnings.count,
                "nullWarnings":model.warnings.filter { $0 == nil }.count,
                "firstTime":forecasts.first?.hourly?.time.first ?? ""]
    }
    static func main() throws {
        let data = try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))
        let mode = CommandLine.arguments[3]
        let iterations = Int(CommandLine.arguments[4])!
        let yy = YYJSONDecoder()
        let native = JSONDecoder()
        func parse() throws -> Envelope {
            if mode == "native" { return try native.decode(Envelope.self,from:data) }
            return try yy.decode(Envelope.self,from:data)
        }
        var result: [String: Any] = ["bytes":data.count,"iterationsPerSample":iterations,"engine":mode]
        do {
            let model = try parse()
            result["summary"] = summary(model)
            result["modelJSON"] = try JSONSerialization.jsonObject(with:JSONEncoder().encode(model))
            if iterations > 0 {
            for _ in 0..<5 { _ = try autoreleasepool { try parse() } }
            var samples: [Double] = []
            var consumed = 0.0
            for _ in 0..<7 {
                let start = ProcessInfo.processInfo.systemUptime
                for _ in 0..<iterations {
                    consumed += try autoreleasepool { try parse().payload.locations.first?.current.temperature_2m ?? 0 }
                }
                samples.append((ProcessInfo.processInfo.systemUptime-start)*1000)
            }
            result["sampleMilliseconds"] = samples
            result["consumed"] = consumed
            }
        } catch { result["error"] = String(describing:error) }
        let output = try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys])
        try output.write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
    }
}
