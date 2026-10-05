import Foundation
import CoreFoundation
import YYModelSwift

// Public consumer: synthesized Codable only; no library internals or test target.
private struct CurrentWeather: Codable, Equatable {
    var time: String
    var interval: Int
    var temperature_2m: Double
    var relative_humidity_2m: Int
    var is_day: Int
    var precipitation: Double
    var wind_speed_10m: Double
}

private struct HourlyWeather: Codable, Equatable {
    var time: [String]
    var temperature_2m: [Double]
    var relative_humidity_2m: [Int]
    var precipitation: [Double]
    var wind_speed_10m: [Double]
}

private struct DailyWeather: Codable, Equatable {
    var time: [String]
    var temperature_2m_max: [Double]
    var temperature_2m_min: [Double]
    var precipitation_sum: [Double]
}

private struct CityForecast: Codable, Equatable {
    var location_id: Int?
    var latitude: Double
    var longitude: Double
    var generationtime_ms: Double
    var utc_offset_seconds: Int
    var timezone: String
    var timezone_abbreviation: String
    var elevation: Double
    var current_units: [String: String]
    var current: CurrentWeather
    var hourly_units: [String: String]
    var hourly: HourlyWeather
    var daily_units: [String: String]
    var daily: DailyWeather
}

private struct ForecastEnvelope: Codable, Equatable {
    var fetchedAt: Date
    var forecasts: [CityForecast]
}

private struct WeatherServiceError: Codable, Equatable {
    var error: Bool
    var reason: String
}

private struct ForecastSummary: Codable, Equatable {
    var timezone: String
    var currentTemperature: Double
    var hourlyRows: Int
    var dailyRows: Int
    var lowestTemperature: Double
    var highestTemperature: Double
    var forecastRainfall: Double
}

private struct CheckRow: Codable {
    var scenario: String
    var expected: String
    var actual: String
    var passed: Bool
}

private struct E2EArtifact: Codable {
    var suite: String
    var generatedAtUTC: String
    var operatingSystem: String
    var inputPath: String
    var inputBytes: Int
    var sourceMetadata: [String: String]
    var cityCount: Int
    var oracleLeafCount: Int
    var summaries: [ForecastSummary]
    var passed: Int
    var failed: Int
    var rows: [CheckRow]
}

private struct ContractViolation: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}

private final class Recorder {
    var rows: [CheckRow] = []

    func check(_ scenario: String, expected: String, _ body: () throws -> String) {
        do {
            let actual = try body()
            rows.append(CheckRow(scenario: scenario, expected: expected, actual: actual, passed: true))
        } catch {
            rows.append(CheckRow(scenario: scenario, expected: expected, actual: describe(error), passed: false))
        }
    }

    func rejection(_ scenario: String, _ body: () throws -> Void) {
        check(scenario, expected: "DecodingError rejection; no usable weather model") {
            do { try body() }
            catch let error as DecodingError { return "rejected: \(describe(error))" }
            throw ContractViolation("Decoder accepted input whose contract requires rejection")
        }
    }
}

private final class HookCounts {
    var will = 0
    var did = 0
    var export = 0
    func reset() { will = 0; did = 0; export = 0 }
}

private struct DecoderPath {
    var name: String
    var mode: YYJSONMode
    var raw: Bool

    func decode(_ data: Data, object: Any, rules: YYJSONRules = .init()) throws -> [CityForecast] {
        let decoder = YYJSONDecoder(mode: mode, rules: rules)
        return raw
            ? try decoder.decode([CityForecast].self, from: object)
            : try decoder.decode([CityForecast].self, from: data)
    }
}

private func describe(_ error: Error) -> String {
    func path(_ keys: [CodingKey]) -> String {
        keys.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
    }
    switch error {
    case DecodingError.keyNotFound(let key, let context):
        return "keyNotFound at \(path(context.codingPath)).\(key.stringValue): \(context.debugDescription)"
    case DecodingError.valueNotFound(let type, let context):
        return "valueNotFound \(type) at \(path(context.codingPath)): \(context.debugDescription)"
    case DecodingError.typeMismatch(let type, let context):
        return "typeMismatch \(type) at \(path(context.codingPath)): \(context.debugDescription)"
    case DecodingError.dataCorrupted(let context):
        return "dataCorrupted at \(path(context.codingPath)): \(context.debugDescription)"
    default: return String(describing: error)
    }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw ContractViolation(message) }
}

// Foundation owns the oracle: compare every key, every array slot and every leaf.
// Numeric JSON representations may differ (3 versus 3.0), but booleans may not.
@discardableResult
private func compareJSON(_ expected: Any, _ actual: Any, path: String = "$", leaves: inout Int) throws -> Int {
    if let expected = expected as? [String: Any] {
        guard let actual = actual as? [String: Any] else { throw ContractViolation("\(path): expected object") }
        try require(Set(expected.keys) == Set(actual.keys), "\(path): key set differs; expected \(expected.keys.sorted()), actual \(actual.keys.sorted())")
        for key in expected.keys.sorted() {
            try compareJSON(expected[key]!, actual[key]!, path: "\(path).\(key)", leaves: &leaves)
        }
    } else if let expected = expected as? [Any] {
        guard let actual = actual as? [Any] else { throw ContractViolation("\(path): expected array") }
        try require(expected.count == actual.count, "\(path): expected \(expected.count) elements, actual \(actual.count)")
        for index in expected.indices {
            try compareJSON(expected[index], actual[index], path: "\(path)[\(index)]", leaves: &leaves)
        }
    } else if let expected = expected as? NSNumber {
        guard let actual = actual as? NSNumber else { throw ContractViolation("\(path): expected number") }
        let expectedBool = CFGetTypeID(expected) == CFBooleanGetTypeID()
        let actualBool = CFGetTypeID(actual) == CFBooleanGetTypeID()
        try require(expectedBool == actualBool && expected.compare(actual) == .orderedSame, "\(path): expected \(expected), actual \(actual)")
        leaves += 1
    } else if let expected = expected as? String {
        guard let actual = actual as? String else { throw ContractViolation("\(path): expected string") }
        try require(expected == actual, "\(path): expected \(expected), actual \(actual)")
        leaves += 1
    } else if expected is NSNull {
        try require(actual is NSNull, "\(path): expected null")
        leaves += 1
    } else { throw ContractViolation("\(path): unsupported oracle category \(type(of: expected))") }
    return leaves
}

private func equalJSON(_ expected: Any, _ actual: Any) throws -> Int {
    var leaves = 0
    return try compareJSON(expected, actual, leaves: &leaves)
}

private func parseJSON(_ data: Data) throws -> Any {
    try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
}

private func jsonData(_ object: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed])
}

private func foundationProjection<T: Encodable>(_ value: T) throws -> Any {
    try parseJSON(JSONEncoder().encode(value))
}

private func rawObject(_ value: Any, _ name: String) throws -> [String: Any] {
    guard let object = value as? [String: Any] else { throw ContractViolation("\(name): expected object") }
    return object
}

private func rawDoubles(_ object: [String: Any], _ key: String) throws -> [Double] {
    guard let values = object[key] as? [NSNumber] else { throw ContractViolation("oracle: \(key) must contain numbers") }
    return values.map(\.doubleValue)
}

// This summary reads the raw JSON directly; it never uses a decoded DTO.
private func oracleSummaries(_ raw: Any) throws -> [ForecastSummary] {
    guard let cities = raw as? [[String: Any]] else { throw ContractViolation("oracle: top level must be city array") }
    return try cities.map { city in
        let current = try rawObject(city["current"] as Any, "current")
        let hourly = try rawObject(city["hourly"] as Any, "hourly")
        let daily = try rawObject(city["daily"] as Any, "daily")
        let lows = try rawDoubles(daily, "temperature_2m_min")
        let highs = try rawDoubles(daily, "temperature_2m_max")
        let rain = try rawDoubles(daily, "precipitation_sum")
        guard let timezone = city["timezone"] as? String,
              let temperature = current["temperature_2m"] as? NSNumber,
              let hours = hourly["time"] as? [String], let days = daily["time"] as? [String],
              let minimum = lows.min(), let maximum = highs.max() else {
            throw ContractViolation("oracle: incomplete summary fields")
        }
        return ForecastSummary(timezone: timezone, currentTemperature: temperature.doubleValue,
                               hourlyRows: hours.count, dailyRows: days.count,
                               lowestTemperature: minimum, highestTemperature: maximum,
                               forecastRainfall: rain.reduce(0, +))
    }
}

private func businessSummaries(_ cities: [CityForecast]) throws -> [ForecastSummary] {
    try require(cities.count == 3, "business: expected requested three cities")
    try require(Set(cities.map(\.timezone)).count == cities.count, "business: city timezones must remain distinct")
    return try cities.map { city in
        let h = city.hourly
        let d = city.daily
        try require(h.time.count == 72 && d.time.count == 3, "business: requested three-day window requires 72 hours and 3 days")
        try require([h.temperature_2m.count, h.relative_humidity_2m.count, h.precipitation.count, h.wind_speed_10m.count].allSatisfy { $0 == h.time.count }, "business: hourly time/value arrays must align")
        try require([d.temperature_2m_max.count, d.temperature_2m_min.count, d.precipitation_sum.count].allSatisfy { $0 == d.time.count }, "business: daily time/value arrays must align")
        try require(zip(h.time, h.time.dropFirst()).allSatisfy { $0.0 < $0.1 }, "business: hourly timestamps must increase")
        try require(zip(d.time, d.time.dropFirst()).allSatisfy { $0.0 < $0.1 }, "business: daily timestamps must increase")
        try require((-90...90).contains(city.latitude) && (-180...180).contains(city.longitude), "business: coordinate domain")
        try require(TimeZone(identifier: city.timezone) != nil && !city.timezone_abbreviation.isEmpty, "business: timezone metadata")
        try require(city.current.interval > 0 && (0...1).contains(city.current.is_day), "business: current interval/day domain")
        try require((0...100).contains(city.current.relative_humidity_2m) && h.relative_humidity_2m.allSatisfy { (0...100).contains($0) }, "business: humidity domain")
        try require(city.current.precipitation >= 0 && city.current.wind_speed_10m >= 0 && h.precipitation.allSatisfy { $0 >= 0 } && h.wind_speed_10m.allSatisfy { $0 >= 0 } && d.precipitation_sum.allSatisfy { $0 >= 0 }, "business: rain/wind domain")
        let temperatures = [city.current.temperature_2m] + h.temperature_2m + d.temperature_2m_max + d.temperature_2m_min
        try require(temperatures.allSatisfy { $0.isFinite }, "business: finite temperatures")
        try require(zip(d.temperature_2m_max, d.temperature_2m_min).allSatisfy { $0.0 >= $0.1 }, "business: daily high must not be below low")
        try require(city.current_units["temperature_2m"] == "°C" && city.hourly_units["temperature_2m"] == "°C" && city.daily_units["precipitation_sum"] == "mm", "business: requested units")
        guard let low = d.temperature_2m_min.min(), let high = d.temperature_2m_max.max() else { throw ContractViolation("business: empty forecast") }
        return ForecastSummary(timezone: city.timezone, currentTemperature: city.current.temperature_2m,
                               hourlyRows: h.time.count, dailyRows: d.time.count,
                               lowestTemperature: low, highestTemperature: high,
                               forecastRainfall: d.precipitation_sum.reduce(0, +))
    }
}

private func verifyModel(_ cities: [CityForecast], against raw: Any, checkBusiness: Bool = true) throws -> String {
    let leaves = try equalJSON(raw, foundationProjection(cities))
    if checkBusiness {
        let summary = try businessSummaries(cities)
        let rawSummary = try oracleSummaries(raw)
        try require(summary == rawSummary, "business: typed and raw summaries differ")
    }
    return "accepted; \(cities.count) cities, \(leaves) JSON leaves match; \(checkBusiness ? "business summary matches" : "explicit compatibility oracle matches")"
}

private func mutate(_ raw: Any, section: String, field: String, value: Any?) throws -> Any {
    guard var cities = raw as? [[String: Any]] else { throw ContractViolation("mutation: no city array") }
    var city = cities[0]
    if section.isEmpty { city[field] = value }
    else {
        var object = try rawObject(city[section] as Any, section)
        object[field] = value
        city[section] = object
    }
    cities[0] = city
    return cities
}

private struct EnvelopeKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ stringValue: String) { self.stringValue = stringValue }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

@main
private struct WeatherBusinessE2E {
    static func main() {
        let recorder = Recorder()
        guard CommandLine.arguments.count == 3 else {
            FileHandle.standardError.write(Data("Usage: WeatherBusinessE2E input-weather.json output-results.json\n".utf8))
            exit(2)
        }
        let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
        var bytes = 0
        var leaves = 0
        var cityCount = 0
        var summaries: [ForecastSummary] = []
        var metadata: [String: String] = [:]
        do {
            let data = try Data(contentsOf: inputURL)
            bytes = data.count
            let raw = try parseJSON(data)
            let control = try JSONDecoder().decode([CityForecast].self, from: data)
            cityCount = control.count
            leaves = try equalJSON(raw, foundationProjection(control))
            summaries = try oracleSummaries(raw)
            let sourceURL = inputURL.deletingLastPathComponent().appendingPathComponent("weather-source.json")
            let source = try rawObject(parseJSON(Data(contentsOf: sourceURL)), "source metadata")
            for key in ["provider", "url", "fetchedAtUTC", "sha256", "attribution"] {
                if let value = source[key] as? String { metadata[key] = value }
            }
            try run(data: data, raw: raw, control: control, source: source, recorder: recorder)
            let errorURL = inputURL.deletingLastPathComponent().appendingPathComponent("weather-error.json")
            let errorSourceURL = inputURL.deletingLastPathComponent().appendingPathComponent("weather-error-source.json")
            let errorSource = try rawObject(parseJSON(Data(contentsOf: errorSourceURL)), "error source metadata")
            for key in ["url", "fetchedAtUTC", "sha256"] {
                if let value = errorSource[key] as? String { metadata["error.\(key)"] = value }
            }
            metadata["error.httpStatus"] = String(describing: errorSource["httpStatus"] ?? "missing")
            try runServiceError(data: Data(contentsOf: errorURL), source: errorSource, recorder: recorder)
        } catch {
            recorder.rows.append(CheckRow(scenario: "setup.foundationOracle", expected: "Recorded source and complete fresh three-city response", actual: describe(error), passed: false))
        }
        recorder.check("artifact.uniqueScenarios", expected: "Each assertion has a unique scenario identifier") {
            try require(Set(recorder.rows.map(\.scenario)).count == recorder.rows.count, "duplicate scenario identifiers")
            return "\(recorder.rows.count) unique scenario identifiers"
        }
        let failed = recorder.rows.filter { !$0.passed }.count
        let artifact = E2EArtifact(suite: "Fresh Open-Meteo public API weather business E2E",
                                   generatedAtUTC: ISO8601DateFormatter().string(from: Date()),
                                   operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
                                   inputPath: inputURL.path, inputBytes: bytes, sourceMetadata: metadata,
                                   cityCount: cityCount, oracleLeafCount: leaves, summaries: summaries,
                                   passed: recorder.rows.count - failed, failed: failed, rows: recorder.rows)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(artifact).write(to: outputURL, options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("Unable to preserve results: \(error)\n".utf8))
            exit(2)
        }
        print("WeatherBusinessE2E: \(recorder.rows.count - failed) passed, \(failed) failed; \(leaves) oracle leaves; \(outputURL.path)")
        for row in recorder.rows where !row.passed { print("FAIL \(row.scenario): \(row.actual)") }
        exit(failed == 0 ? 0 : 1)
    }

    private static func run(data: Data, raw: Any, control: [CityForecast], source: [String: Any], recorder: Recorder) throws {
        let modes: [(String, YYJSONMode)] = [("native", .native), ("compatible", .compatible), ("legacy", .legacy)]
        let paths = modes.flatMap { name, mode in
            [DecoderPath(name: "\(name).data", mode: mode, raw: false), DecoderPath(name: "\(name).raw", mode: mode, raw: true)]
        }
        recorder.check("liveAPI.foundation.decode", expected: "Entire snapshot and business summary match independent raw oracle") {
            try verifyModel(control, against: raw)
        }
        for path in paths {
            recorder.check("liveAPI.decode.\(path.name)", expected: "Every typed field and array entry equals snapshot; usable forecast") {
                try verifyModel(path.decode(data, object: raw), against: raw)
            }
        }
        recorder.check("liveAPI.foundation.encode", expected: "Foundation Data export preserves complete snapshot and business output") {
            let exported = try JSONEncoder().encode(control)
            let count = try equalJSON(raw, parseJSON(exported))
            _ = try verifyModel(JSONDecoder().decode([CityForecast].self, from: exported), against: raw)
            return "Data round-trip accepted; \(count) leaves match"
        }
        for (name, mode) in modes {
            for objectOutput in [false, true] {
                let suffix = objectOutput ? "object" : "data"
                recorder.check("liveAPI.encode.\(name).\(suffix)", expected: "Complete JSON export equals snapshot; Foundation can consume business forecast") {
                    let encoder = YYJSONEncoder(mode: mode)
                    let object = objectOutput ? try encoder.encodeJSONObject(control) : try parseJSON(encoder.encode(control))
                    let count = try equalJSON(raw, object)
                    _ = try verifyModel(JSONDecoder().decode([CityForecast].self, from: jsonData(object)), against: raw)
                    return "\(suffix) round-trip accepted; \(count) leaves match"
                }
            }
        }
        try runHooks(data: data, raw: raw, control: control, paths: paths, modes: modes, recorder: recorder)
        try runPolicies(raw: raw, control: control, source: source, recorder: recorder)
        try runMutations(data: data, raw: raw, paths: paths, recorder: recorder)
    }

    private static func runHooks(data: Data, raw: Any, control: [CityForecast], paths: [DecoderPath], modes: [(String, YYJSONMode)], recorder: Recorder) throws {
        let counts = HookCounts()
        let rules = try YYJSONRules().forType(CityForecast.self) { configuration in
            configuration.willTransform = { object in counts.will += 1; return object }
            configuration.didTransform = { _, _ in counts.did += 1; return true }
            configuration.transformTo = { _, _ in counts.export += 1; return true }
        }
        for path in paths where path.mode != .native {
            recorder.check("liveAPI.noopHooks.decode.\(path.name)", expected: "No-op hooks preserve complete forecast; will/did once per city") {
                counts.reset()
                let description = try verifyModel(path.decode(data, object: raw, rules: rules), against: raw)
                try require(counts.will == 3 && counts.did == 3 && counts.export == 0, "hook counts: will=\(counts.will) did=\(counts.did) export=\(counts.export)")
                return "\(description); will=3 did=3 export=0"
            }
        }
        for (name, mode) in modes where mode != .native {
            for objectOutput in [false, true] {
                let suffix = objectOutput ? "object" : "data"
                recorder.check("liveAPI.noopHooks.encode.\(name).\(suffix)", expected: "No-op export preserves complete forecast; export once per city") {
                    counts.reset()
                    let encoder = YYJSONEncoder(mode: mode, rules: rules)
                    let object = objectOutput ? try encoder.encodeJSONObject(control) : try parseJSON(encoder.encode(control))
                    let count = try equalJSON(raw, object)
                    try require(counts.will == 0 && counts.did == 0 && counts.export == 3, "hook counts: will=\(counts.will) did=\(counts.did) export=\(counts.export)")
                    _ = try verifyModel(JSONDecoder().decode([CityForecast].self, from: jsonData(object)), against: raw)
                    return "\(count) leaves match; will=0 did=0 export=3"
                }
            }
        }
        recorder.check("policy.native.rejectsNonemptyRules", expected: "Native mode explicitly rejects enhanced hook configuration") {
            do { _ = try YYJSONDecoder(mode: .native, rules: rules).decode([CityForecast].self, from: data) }
            catch let error as YYJSONRulesError { return "rejected nonempty rules: \(error)" }
            throw ContractViolation("Native mode silently accepted enhanced rules")
        }
    }

    private static func runPolicies(raw: Any, control: [CityForecast], source: [String: Any], recorder: Recorder) throws {
        guard let timestamp = source["fetchedAtUTC"] as? String else { throw ContractViolation("metadata: missing retrieval timestamp") }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let fetchedAt = formatter.date(from: timestamp) else { throw ContractViolation("metadata: invalid retrieval timestamp") }
        let envelope = ForecastEnvelope(fetchedAt: fetchedAt, forecasts: control)
        let seconds = fetchedAt.timeIntervalSince1970
        let mapped: [String: Any] = ["transport": ["retrieved_at": seconds], "payload": ["weather": raw]]
        let mappedData = try jsonData(mapped)
        let rules = try YYJSONRules().forType(ForecastEnvelope.self) { configuration in
            configuration.mapper = ["fetchedAt": "transport.retrieved_at", "forecasts": "payload.weather"]
            configuration.fieldDateStrategies = ["fetchedAt": .secondsSince1970]
        }
        for (name, mode) in [("compatible", YYJSONMode.compatible), ("legacy", YYJSONMode.legacy)] {
            for rawInput in [false, true] {
                let suffix = rawInput ? "raw" : "data"
                recorder.check("policy.mappedDate.decode.\(name).\(suffix)", expected: "Mapped application envelope retains retrieval epoch and full weather forecast") {
                    let decoder = YYJSONDecoder(mode: mode, rules: rules)
                    let value = rawInput ? try decoder.decode(ForecastEnvelope.self, from: mapped) : try decoder.decode(ForecastEnvelope.self, from: mappedData)
                    try require(value == envelope, "mapped envelope changed retrieval date or weather values")
                    return try verifyModel(value.forecasts, against: raw) + "; retrieval epoch matches"
                }
            }
            for objectOutput in [false, true] {
                let suffix = objectOutput ? "object" : "data"
                recorder.check("policy.mappedDate.encode.\(name).\(suffix)", expected: "Mapped JSON paths and explicit date seconds round-trip exactly") {
                    let encoder = YYJSONEncoder(mode: mode, rules: rules)
                    let object = objectOutput ? try encoder.encodeJSONObject(envelope) : try parseJSON(encoder.encode(envelope))
                    let count = try equalJSON(mapped, object)
                    let value = try YYJSONDecoder(mode: mode, rules: rules).decode(ForecastEnvelope.self, from: object)
                    try require(value == envelope, "mapped round-trip differs")
                    return "\(count) leaves match; mapped envelope date and business model round-trip"
                }
            }
        }
        let keyed: [String: Any] = ["retrieved_at": seconds, "city_forecasts": raw]
        let keyedData = try jsonData(keyed)
        let decodeKey: @Sendable ([CodingKey]) -> CodingKey = { path in
            let value = path.last!.stringValue
            guard path.count == 1 else { return EnvelopeKey(value) }
            return EnvelopeKey(value == "retrieved_at" ? "fetchedAt" : value == "city_forecasts" ? "forecasts" : value)
        }
        let encodeKey: @Sendable ([CodingKey]) -> CodingKey = { path in
            let value = path.last!.stringValue
            guard path.count == 1 else { return EnvelopeKey(value) }
            return EnvelopeKey(value == "fetchedAt" ? "retrieved_at" : value == "forecasts" ? "city_forecasts" : value)
        }
        recorder.check("policy.foundation.dateAndKeysControl", expected: "Foundation custom root keys and seconds date preserve full business envelope") {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            decoder.keyDecodingStrategy = .custom(decodeKey)
            let value = try decoder.decode(ForecastEnvelope.self, from: keyedData)
            try require(value == envelope, "Foundation policy model differs")
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            encoder.keyEncodingStrategy = .custom(encodeKey)
            let count = try equalJSON(keyed, parseJSON(encoder.encode(value)))
            return "\(count) leaves match; Foundation date/key control accepted"
        }
        for (name, mode) in [("native", YYJSONMode.native), ("compatible", YYJSONMode.compatible)] {
            recorder.check("policy.foundationStrategies.\(name)", expected: "Public Foundation date/key strategies preserve full envelope on Data and raw paths") {
                var decoder = YYJSONDecoder(mode: mode)
                decoder.dateDecodingStrategy = .secondsSince1970
                decoder.keyDecodingStrategy = .custom(decodeKey)
                let dataValue = try decoder.decode(ForecastEnvelope.self, from: keyedData)
                let rawValue = try decoder.decode(ForecastEnvelope.self, from: keyed)
                try require(dataValue == envelope && rawValue == envelope, "YY date/key strategy model differs")
                var encoder = YYJSONEncoder(mode: mode)
                encoder.dateEncodingStrategy = .secondsSince1970
                encoder.keyEncodingStrategy = .custom(encodeKey)
                let count = try equalJSON(keyed, parseJSON(encoder.encode(dataValue)))
                _ = try equalJSON(keyed, encoder.encodeJSONObject(rawValue))
                return "Data/raw decode and Data/object encode accepted; \(count) leaves match"
            }
        }
    }

    private static func runMutations(data: Data, raw: Any, paths: [DecoderPath], recorder: Recorder) throws {
        guard let cities = raw as? [[String: Any]],
              let current = cities[0]["current"] as? [String: Any],
              let originalTemperature = current["temperature_2m"] as? NSNumber,
              let hourly = cities[0]["hourly"] as? [String: Any],
              let temperatures = hourly["temperature_2m"] as? [Any] else { throw ContractViolation("mutation setup: missing weather fields") }
        let stringTemperature = try mutate(raw, section: "current", field: "temperature_2m", value: originalTemperature.stringValue)
        var stringHours = temperatures
        stringHours[17] = (temperatures[17] as! NSNumber).stringValue
        let stringArray = try mutate(raw, section: "hourly", field: "temperature_2m", value: stringHours)
        for (name, object) in [("numberString", stringTemperature), ("numberStringArray", stringArray)] {
            let mutationData = try jsonData(object)
            recorder.rejection("mutation.\(name).foundation") { _ = try JSONDecoder().decode([CityForecast].self, from: mutationData) }
            for path in paths {
                if path.mode == .native {
                    recorder.rejection("mutation.\(name).\(path.name)") { _ = try path.decode(mutationData, object: object) }
                } else {
                    recorder.check("mutation.\(name).\(path.name)", expected: "Numeric strings coerce losslessly; original forecast and array entries preserved") {
                        try verifyModel(path.decode(mutationData, object: object), against: raw)
                    }
                }
            }
        }
        for (name, replacement) in [("missingTemperature", Optional<Any>.none), ("nullTemperature", Optional<Any>.some(NSNull()))] {
            let object = try mutate(raw, section: "current", field: "temperature_2m", value: replacement)
            let mutationData = try jsonData(object)
            let zeroOracle = try mutate(raw, section: "current", field: "temperature_2m", value: 0)
            recorder.rejection("mutation.\(name).foundation") { _ = try JSONDecoder().decode([CityForecast].self, from: mutationData) }
            for path in paths {
                if path.mode == .legacy {
                    recorder.check("mutation.\(name).\(path.name)", expected: "Published legacy compatibility zero-fills only the unavailable scalar") {
                        try verifyModel(path.decode(mutationData, object: object), against: zeroOracle, checkBusiness: false)
                    }
                } else {
                    recorder.rejection("mutation.\(name).\(path.name)") { _ = try path.decode(mutationData, object: object) }
                }
            }
        }
        var mixedHours = temperatures
        mixedHours[17] = ["unexpected": "object"]
        let mixedArray = try mutate(raw, section: "hourly", field: "temperature_2m", value: mixedHours)
        let missingCurrent = try mutate(raw, section: "", field: "current", value: nil)
        let nullCurrent = try mutate(raw, section: "", field: "current", value: NSNull())
        let currentPlaceholder: [String: Any] = ["time": "", "interval": 0, "temperature_2m": 0,
                                                  "relative_humidity_2m": 0, "is_day": 0,
                                                  "precipitation": 0, "wind_speed_10m": 0]
        let placeholderOracle = try mutate(raw, section: "", field: "current", value: currentPlaceholder)
        for (name, object) in [("mixedObjectArray", mixedArray), ("missingCurrentObject", missingCurrent), ("nullCurrentObject", nullCurrent)] {
            let mutationData = try jsonData(object)
            recorder.rejection("mutation.\(name).foundation") { _ = try JSONDecoder().decode([CityForecast].self, from: mutationData) }
            for path in paths {
                if path.mode == .legacy && name != "mixedObjectArray" {
                    recorder.check("mutation.\(name).\(path.name)", expected: "Legacy explicit current placeholder matches; business rejects unusable current weather") {
                        let value = try path.decode(mutationData, object: object)
                        _ = try verifyModel(value, against: placeholderOracle, checkBusiness: false)
                        do { _ = try businessSummaries(value) }
                        catch let failure as ContractViolation { return "exact zero current placeholder preserved; business rejected: \(failure)" }
                        throw ContractViolation("Business workflow accepted zero current placeholder")
                    }
                } else {
                    recorder.rejection("mutation.\(name).\(path.name)") { _ = try path.decode(mutationData, object: object) }
                }
            }
        }
        let malformed = Data(data.dropLast())
        recorder.rejection("mutation.malformedJSON.foundation") { _ = try JSONDecoder().decode([CityForecast].self, from: malformed) }
        for path in paths where !path.raw {
            recorder.rejection("mutation.malformedJSON.\(path.name)") { _ = try path.decode(malformed, object: raw) }
        }
        let shortArray = try mutate(raw, section: "hourly", field: "temperature_2m", value: Array(temperatures.dropLast()))
        let badHumidity = try mutate(raw, section: "current", field: "relative_humidity_2m", value: 101)
        let badDay = try mutate(raw, section: "current", field: "is_day", value: 2)
        let badRain = try mutate(raw, section: "current", field: "precipitation", value: -1)
        for (name, object) in [("shortHourlyArray", shortArray), ("invalidHumidity", badHumidity), ("invalidDay", badDay), ("negativeRain", badRain)] {
            let mutationData = try jsonData(object)
            func rejectedBusiness(_ cities: [CityForecast]) throws -> String {
                _ = try verifyModel(cities, against: object, checkBusiness: false)
                do { _ = try businessSummaries(cities) }
                catch let failure as ContractViolation { return "decode preserved every mutated value; rejected: \(failure)" }
                throw ContractViolation("Business workflow accepted an invalid forecast")
            }
            recorder.check("mutation.\(name).foundation", expected: "Decode retains malformed data; business workflow rejects unusable forecast") {
                try rejectedBusiness(JSONDecoder().decode([CityForecast].self, from: mutationData))
            }
            for path in paths {
                recorder.check("mutation.\(name).\(path.name)", expected: "Decode retains malformed data; business workflow rejects unusable forecast") {
                    try rejectedBusiness(path.decode(mutationData, object: object))
                }
            }
        }
    }

    private static func runServiceError(data: Data, source: [String: Any], recorder: Recorder) throws {
        let raw = try parseJSON(data)
        let control = try JSONDecoder().decode(WeatherServiceError.self, from: data)
        func verify(_ value: WeatherServiceError) throws -> String {
            let count = try equalJSON(raw, foundationProjection(value))
            try require(value.error && !value.reason.isEmpty, "business: service error must retain true error flag and useful reason")
            return "HTTP 400 service error recognized; \(count) leaves match; reason preserved"
        }
        recorder.check("realAPI.http400.foundation", expected: "Recorded HTTP 400 response is a complete service error") {
            try require((source["httpStatus"] as? NSNumber)?.intValue == 400, "provenance: expected actual HTTP 400")
            return try verify(control)
        }
        recorder.rejection("realAPI.http400.notForecast.foundation") { _ = try JSONDecoder().decode([CityForecast].self, from: data) }
        for (name, mode) in [("native", YYJSONMode.native), ("compatible", YYJSONMode.compatible), ("legacy", YYJSONMode.legacy)] {
            for rawInput in [false, true] {
                let suffix = rawInput ? "raw" : "data"
                recorder.check("realAPI.http400.decode.\(name).\(suffix)", expected: "Parse complete service error and surface reason to application") {
                    let decoder = YYJSONDecoder(mode: mode)
                    let value = rawInput ? try decoder.decode(WeatherServiceError.self, from: raw) : try decoder.decode(WeatherServiceError.self, from: data)
                    return try verify(value)
                }
                recorder.rejection("realAPI.http400.notForecast.\(name).\(suffix)") {
                    let decoder = YYJSONDecoder(mode: mode)
                    if rawInput { _ = try decoder.decode([CityForecast].self, from: raw) }
                    else { _ = try decoder.decode([CityForecast].self, from: data) }
                }
            }
            for objectOutput in [false, true] {
                let suffix = objectOutput ? "object" : "data"
                recorder.check("realAPI.http400.encode.\(name).\(suffix)", expected: "Service error JSON export preserves flag and reason") {
                    let encoder = YYJSONEncoder(mode: mode)
                    let object = objectOutput ? try encoder.encodeJSONObject(control) : try parseJSON(encoder.encode(control))
                    let count = try equalJSON(raw, object)
                    _ = try verify(JSONDecoder().decode(WeatherServiceError.self, from: jsonData(object)))
                    return "\(count) error leaves match; Foundation error round-trip accepted"
                }
            }
        }
    }
}
