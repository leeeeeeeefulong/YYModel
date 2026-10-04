import Foundation

// Two independent responses, never a struct -> JSON -> OC conversion pipeline.
@main struct CoexistE2E {
    static func main() throws {
        let args = CommandLine.arguments
        let ocData = try Data(contentsOf: URL(fileURLWithPath: args[1]))
        let swiftData = try Data(contentsOf: URL(fileURLWithPath: args[2]))
        let object = try JSONSerialization.jsonObject(with: ocData) as! NSDictionary
        let mode = args[4], iterations = Int(args[5])!, swiftFirst = args[6] == "swift-first"
        let yy = YYJSONDecoder()
        func parseOC() throws -> WeatherEnvelope {
            let result = mode == "foundation-object" ? WeatherEnvelope.yy_model(withJSON: object)
                                                      : WeatherEnvelope.yy_model(withJSON: ocData)
            guard let result else { throw CocoaError(.coderReadCorrupt) }
            return result
        }
        func parseSwift() throws -> Envelope { try yy.decode(Envelope.self, from: swiftData) }
        let oc = try parseOC(), swift = try parseSwift()
        var result = ValidationModelResult(oc) as! [String: Any]
        result["swiftModelJSON"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(swift))
        result["operationsPerIteration"] = mode == "foundation-object" ? 1 : 2
        result["mode"] = mode
        func ocScore() throws -> Double {
            try autoreleasepool { try parseOC().forecasts?.first?.current?.temperature_2m ?? 0 }
        }
        func swiftScore() throws -> Double {
            try autoreleasepool { try parseSwift().payload.locations.first?.current.temperature_2m ?? 0 }
        }
        func operation() throws -> Double {
            if mode == "foundation-object" { return try ocScore() }
            if swiftFirst { return try swiftScore() + ocScore() }
            return try ocScore() + swiftScore()
        }
        if iterations > 0 {
            for _ in 0..<5 { _ = try operation() }
            var samples: [Double] = [], consumed = 0.0
            for _ in 0..<7 {
                let start = ProcessInfo.processInfo.systemUptime
                for _ in 0..<iterations { consumed += try operation() }
                samples.append((ProcessInfo.processInfo.systemUptime-start)*1000)
            }
            result["sampleMilliseconds"] = samples
            result["consumed"] = consumed
        }
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: args[3]))
    }
}
