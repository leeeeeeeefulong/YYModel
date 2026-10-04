import Foundation

@main struct InteropRunner {
    static func main() throws {
        let args = CommandLine.arguments
        let data = try Data(contentsOf: URL(fileURLWithPath: args[1]))
        let foundationObject = try JSONSerialization.jsonObject(with: data) as! NSDictionary
        let swiftObject = foundationObject as! [String: Any]
        let engine = args[3], channel = args[4], iterations = Int(args[5])!
        var result: [String: Any]
        #if INTEROP
        precondition(ValidationTouchObjC())
        if engine == "oc" {
            result = ValidationOCResult(data, foundationObject, channel, UInt(iterations)) as! [String: Any]
        } else if engine == "swift-oc" {
            result = runObjC(data, swiftObject, channel, iterations)
        } else {
            result = runSwift(data, foundationObject, engine, channel, iterations)
        }
        #else
        result = runSwift(data, foundationObject, engine, channel, iterations)
        #endif
        result["bytes"] = data.count
        result["engine"] = engine
        result["channel"] = channel
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: args[2]))
    }

    static func runSwift(_ data: Data, _ object: NSDictionary, _ engine: String,
                         _ channel: String, _ iterations: Int) -> [String: Any] {
        let native = JSONDecoder(), yy = YYJSONDecoder(), encoder = JSONEncoder()
        func parse() throws -> Envelope {
            if engine == "yy" {
                return channel == "object" ? try yy.decode(Envelope.self, from: object)
                                           : try yy.decode(Envelope.self, from: data)
            }
            let decoder = engine == "native-new" ? JSONDecoder() : native
            let bytes = channel == "object" ? try JSONSerialization.data(withJSONObject: object) : data
            return try decoder.decode(Envelope.self, from: bytes)
        }
        do {
            let start = ProcessInfo.processInfo.systemUptime
            let model = try parse()
            var result: [String: Any] = ["firstDecodeMilliseconds": (ProcessInfo.processInfo.systemUptime - start) * 1000,
                "modelJSON": try JSONSerialization.jsonObject(with: encoder.encode(model))]
            if channel == "encode" { result["encodedBytes"] = try encoder.encode(model).count }
            if iterations == 0 { return result }
            for _ in 0..<5 {
                _ = try autoreleasepool { channel == "encode" ? Double(try encoder.encode(model).count)
                    : try parse().payload.locations.first?.current.temperature_2m ?? 0 }
            }
            var samples: [Double] = [], consumed = 0.0
            for _ in 0..<7 {
                let start = ProcessInfo.processInfo.systemUptime
                for _ in 0..<iterations {
                    consumed += try autoreleasepool { channel == "encode" ? Double(try encoder.encode(model).count)
                        : try parse().payload.locations.first?.current.temperature_2m ?? 0 }
                }
                samples.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
            }
            result["sampleMilliseconds"] = samples
            result["consumed"] = consumed
            result["iterationsPerSample"] = iterations
            return result
        } catch { return ["error": String(describing: error)] }
    }

    #if INTEROP
    static func runObjC(_ data: Data, _ object: [String: Any], _ channel: String,
                        _ iterations: Int) -> [String: Any] {
        func parse() throws -> WeatherEnvelope {
            let model = channel == "object" ? WeatherEnvelope.yy_model(with: object)
                                             : WeatherEnvelope.yy_model(withJSON: data)
            guard let model else { throw CocoaError(.coderReadCorrupt) }
            return model
        }
        do {
            let start = ProcessInfo.processInfo.systemUptime
            let model = try parse()
            let firstMS = (ProcessInfo.processInfo.systemUptime - start) * 1000
            var result = ValidationModelResult(model) as! [String: Any]
            result["firstDecodeMilliseconds"] = firstMS
            if channel == "encode" {
                guard let encoded = model.yy_modelToJSONData() else { throw CocoaError(.coderInvalidValue) }
                result["encodedModelJSON"] = try JSONSerialization.jsonObject(with: encoded)
                result["encodedBytes"] = encoded.count
            }
            if iterations == 0 { return result }
            for _ in 0..<5 {
                _ = try autoreleasepool { channel == "encode" ? Double(model.yy_modelToJSONData()?.count ?? 0)
                    : try parse().forecasts?.first?.current?.temperature_2m ?? 0 }
            }
            var samples: [Double] = [], consumed = 0.0
            for _ in 0..<7 {
                let start = ProcessInfo.processInfo.systemUptime
                for _ in 0..<iterations {
                    consumed += try autoreleasepool { channel == "encode" ? Double(model.yy_modelToJSONData()?.count ?? 0)
                        : try parse().forecasts?.first?.current?.temperature_2m ?? 0 }
                }
                samples.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
            }
            result["sampleMilliseconds"] = samples
            result["consumed"] = consumed
            result["iterationsPerSample"] = iterations
            return result
        } catch { return ["error": String(describing: error)] }
    }
    #endif
}
