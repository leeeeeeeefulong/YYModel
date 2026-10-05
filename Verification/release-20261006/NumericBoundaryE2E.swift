import Foundation
import YYModelSwift

private struct BoundaryNumbers: Codable, Equatable {
    var signedMinimum: Int64
    var signedMaximum: Int64
    var unsignedMaximum: UInt64
    var adjacentDouble: Double
}
private struct SignedNumber: Codable { var value: Int64 }
private struct UnsignedNumber: Codable { var value: UInt64 }
private struct FloatingNumber: Codable { var value: Double }
private struct DateNumber: Codable, Equatable { var value: Date }

private struct NumericRow: Codable {
    var scenario: String
    var expected: String
    var actual: String
    var passed: Bool
}
private struct NumericArtifact: Codable {
    var suite: String
    var inputOrigin: String
    var operatingSystem: String
    var passed: Int
    var failed: Int
    var unverified: [String]
    var rows: [NumericRow]
}
private struct NumericFailure: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}
private final class NumericRecorder {
    var rows: [NumericRow] = []
    func check(_ scenario: String, expected: String, _ body: () throws -> String) {
        do { rows.append(.init(scenario: scenario, expected: expected, actual: try body(), passed: true)) }
        catch { rows.append(.init(scenario: scenario, expected: expected, actual: String(describing: error), passed: false)) }
    }
    func rejects(_ scenario: String, _ body: () throws -> Void) {
        check(scenario, expected: "Public API rejects; no JSON/model result") {
            do { try body() }
            catch { return "rejected: \(String(describing: error))" }
            throw NumericFailure("accepted invalid numeric/date boundary")
        }
    }
}

private enum NativeOutcome<Value: Equatable>: Equatable {
    case value(Value)
    case error(String)
}
private func nativeOutcome<T: Equatable>(_ body: () throws -> T) -> NativeOutcome<T> {
    do { return .value(try body()) }
    catch { return .error(String(describing: error)) }
}
private func insist(_ condition: @autoclosure () throws -> Bool, _ detail: String) throws {
    guard try condition() else { throw NumericFailure(detail) }
}
private func serialize(_ object: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed])
}
private func parse(_ data: Data) throws -> Any {
    try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
}
private func decode<T: Decodable>(_ type: T.Type, data: Data, object: Any, mode: YYJSONMode, raw: Bool) throws -> T {
    let decoder = YYJSONDecoder(mode: mode)
    return raw ? try decoder.decode(type, from: object) : try decoder.decode(type, from: data)
}
private func numericDescription(_ value: BoundaryNumbers) -> String {
    "Int64=[\(value.signedMinimum),\(value.signedMaximum)]; UInt64=\(value.unsignedMaximum); Double.bits=0x\(String(value.adjacentDouble.bitPattern, radix: 16))"
}
private func exactBoundaries(_ value: BoundaryNumbers) throws -> String {
    try insist(value.signedMinimum == Int64.min, "Int64.min lost precision")
    try insist(value.signedMaximum == Int64.max, "Int64.max lost precision")
    try insist(value.unsignedMaximum == UInt64.max, "UInt64.max lost precision")
    try insist(value.adjacentDouble.bitPattern == 0x3ff0000000000001, "adjacent Double rounded to a different bit pattern")
    return numericDescription(value)
}
private func exactObject(_ object: Any) throws {
    guard let object = object as? [String: Any],
          let minimum = object["signedMinimum"] as? NSNumber,
          let maximum = object["signedMaximum"] as? NSNumber,
          let unsigned = object["unsignedMaximum"] as? NSNumber,
          let adjacent = object["adjacentDouble"] as? NSNumber else { throw NumericFailure("numeric object schema changed") }
    try insist(Set(object.keys) == Set(["signedMinimum", "signedMaximum", "unsignedMaximum", "adjacentDouble"]), "numeric object keys changed")
    try insist(minimum.int64Value == Int64.min && maximum.int64Value == Int64.max, "signed NSNumber values changed")
    try insist(unsigned.uint64Value == UInt64.max, "unsigned NSNumber value changed")
    try insist(adjacent.doubleValue.bitPattern == 0x3ff0000000000001, "NSNumber Double bit pattern changed")
}

private struct DateScale {
    var name: String
    var policy: YYModelDateStrategy
    var factor: Double
    var foundationDecode: JSONDecoder.DateDecodingStrategy?
    var foundationEncode: JSONEncoder.DateEncodingStrategy?
}

@main
private struct NumericBoundaryE2E {
    private static let modes: [(String, YYJSONMode)] = [("native", .native), ("compatible", .compatible), ("legacy", .legacy)]
    static func main() {
        guard CommandLine.arguments.count == 2 else {
            FileHandle.standardError.write(Data("Usage: NumericBoundaryE2E output.json\n".utf8))
            exit(2)
        }
        let recorder = NumericRecorder()
        do { try runNumbers(recorder); try runDates(recorder) }
        catch { recorder.rows.append(.init(scenario: "setup.literalInputs", expected: "Synthetic literals can be prepared", actual: String(describing: error), passed: false)) }
        recorder.check("artifact.uniqueScenarios", expected: "Unique assertion identifiers") {
            try insist(Set(recorder.rows.map(\.scenario)).count == recorder.rows.count, "duplicate numeric scenario identifiers")
            return "\(recorder.rows.count) unique identifiers"
        }
        let failed = recorder.rows.filter { !$0.passed }.count
        let artifact = NumericArtifact(suite: "Public numeric/date boundary E2E", inputOrigin: "Synthetic literal contracts; not live API data",
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            passed: recorder.rows.count - failed, failed: failed,
            unverified: ["Decimal precision", "smaller integer widths", "Float rounding", "JSON5", "timezone/calendar date range", "non-default nonconforming-float conversions", "unexecuted operating systems"], rows: recorder.rows)
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(artifact).write(to: url, options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("Cannot preserve numeric artifact: \(error)\n".utf8)); exit(2)
        }
        print("NumericBoundaryE2E: \(recorder.rows.count - failed) passed, \(failed) failed; \(url.path)")
        for row in recorder.rows where !row.passed { print("FAIL \(row.scenario): \(row.actual)") }
        exit(failed == 0 ? 0 : 1)
    }

    private static func runNumbers(_ recorder: NumericRecorder) throws {
        let literals = Data(#"{"signedMinimum":-9223372036854775808,"signedMaximum":9223372036854775807,"unsignedMaximum":18446744073709551615,"adjacentDouble":1.0000000000000002}"#.utf8)
        let strings = Data(#"{"signedMinimum":"-9223372036854775808","signedMaximum":"9223372036854775807","unsignedMaximum":"18446744073709551615","adjacentDouble":"1.0000000000000002"}"#.utf8)
        let value = BoundaryNumbers(signedMinimum: .min, signedMaximum: .max, unsignedMaximum: .max, adjacentDouble: Double(bitPattern: 0x3ff0000000000001))
        for (scenario, data) in [("literal", literals), ("numericStrings", strings)] {
            let object = try parse(data)
            for raw in [false, true] {
                let route = raw ? "raw" : "data"
                let foundation = nativeOutcome { try JSONDecoder().decode(BoundaryNumbers.self, from: raw ? serialize(object) : data) }
                recorder.check("control.foundation.\(scenario).\(route)", expected: "Record same-route Foundation semantics; literal Data retains exact boundaries") {
                    if scenario == "literal" && !raw {
                        guard case .value(let result) = foundation else { throw NumericFailure("Foundation literal Data rejected") }
                        _ = try exactBoundaries(result)
                    } else if scenario == "numericStrings" {
                        guard case .error = foundation else { throw NumericFailure("Foundation accepted numeric strings for required numeric fields") }
                    }
                    return String(describing: foundation)
                }
                for (name, mode) in modes {
                    recorder.check("decode.\(scenario).\(name).\(route)", expected: mode == .native ? "Same outcome as matching Foundation route; no cross-route precision claim" : "Exact Int64/UInt64 literals and adjacent Double bit pattern") {
                        if mode == .native {
                            let actual = nativeOutcome { try decode(BoundaryNumbers.self, data: data, object: object, mode: mode, raw: raw) }
                            try insist(actual == foundation, "native outcome differs from matching Foundation control: \(actual)")
                            return "Foundation-equivalent: \(actual)"
                        }
                        return try exactBoundaries(decode(BoundaryNumbers.self, data: data, object: object, mode: mode, raw: raw))
                    }
                }
            }
        }
        recorder.check("encode.literal.foundationData", expected: "Independent Foundation encoder preserves exact typed literals") {
            try exactBoundaries(JSONDecoder().decode(BoundaryNumbers.self, from: JSONEncoder().encode(value)))
        }
        for (name, mode) in modes {
            for objectOutput in [false, true] {
                let route = objectOutput ? "object" : "data"
                recorder.check("encode.literal.\(name).\(route)", expected: "Foundation consumes exact boundary integers and adjacent Double from exported JSON") {
                    let encoder = YYJSONEncoder(mode: mode)
                    let exported: Data
                    if objectOutput {
                        let object = try encoder.encodeJSONObject(value)
                        try exactObject(object)
                        exported = try serialize(object)
                    } else { exported = try encoder.encode(value) }
                    return try exactBoundaries(JSONDecoder().decode(BoundaryNumbers.self, from: exported))
                }
            }
        }
        for (scenario, literal) in [("int64Overflow", "9223372036854775808"), ("uint64Overflow", "18446744073709551616")] {
            let data = Data("{\"value\":\(literal)}".utf8)
            let object = try parse(data)
            for raw in [false, true] {
                let route = raw ? "raw" : "data"
                recorder.rejects("reject.\(scenario).foundation.\(route)") {
                    let input = raw ? try serialize(object) : data
                    if scenario == "int64Overflow" { _ = try JSONDecoder().decode(SignedNumber.self, from: input) }
                    else { _ = try JSONDecoder().decode(UnsignedNumber.self, from: input) }
                }
                for (name, mode) in modes {
                    recorder.rejects("reject.\(scenario).\(name).\(route)") {
                        if scenario == "int64Overflow" { _ = try decode(SignedNumber.self, data: data, object: object, mode: mode, raw: raw) }
                        else { _ = try decode(UnsignedNumber.self, data: data, object: object, mode: mode, raw: raw) }
                    }
                }
            }
        }
        let overflowingFloat = Data(#"{"value":1e309}"#.utf8)
        recorder.rejects("reject.floatExponentOverflow.foundation.data") { _ = try JSONDecoder().decode(FloatingNumber.self, from: overflowingFloat) }
        for (name, mode) in modes {
            recorder.rejects("reject.floatExponentOverflow.\(name).data") { _ = try YYJSONDecoder(mode: mode).decode(FloatingNumber.self, from: overflowingFloat) }
        }
        for (scenario, number) in [("infinity", Double.infinity), ("nan", Double.nan)] {
            let object: [String: Any] = ["value": NSNumber(value: number)]
            recorder.check("reject.\(scenario).foundation.raw", expected: "Foundation JSON validation rejects nonfinite raw object before unsafe writer invocation") {
                try insist(!JSONSerialization.isValidJSONObject(object), "Foundation accepted invalid nonfinite raw JSON")
                return "isValidJSONObject=false; invalid object has no usable JSON result"
            }
            recorder.rejects("reject.\(scenario).foundation.encode") { _ = try JSONEncoder().encode(FloatingNumber(value: number)) }
            for (name, mode) in modes {
                recorder.rejects("reject.\(scenario).\(name).raw") { _ = try YYJSONDecoder(mode: mode).decode(FloatingNumber.self, from: object) }
                for objectOutput in [false, true] {
                    recorder.rejects("reject.\(scenario).\(name).encode.\(objectOutput ? "object" : "data")") {
                        let encoder = YYJSONEncoder(mode: mode)
                        if objectOutput { _ = try encoder.encodeJSONObject(FloatingNumber(value: number)) }
                        else { _ = try encoder.encode(FloatingNumber(value: number)) }
                    }
                }
            }
        }
        for (scenario, invalid) in [("dateObject", Date(timeIntervalSince1970: 7) as Any), ("opaqueObject", NSObject() as Any)] {
            let object: [String: Any] = ["value": invalid]
            recorder.check("reject.nonJSON.\(scenario).foundation", expected: "Foundation validity control rejects unsupported raw value without invoking unsafe writer") {
                try insist(!JSONSerialization.isValidJSONObject(object), "Foundation accepted non-JSON value")
                return "isValidJSONObject=false; no usable JSON result"
            }
            for (name, mode) in modes {
                recorder.rejects("reject.nonJSON.\(scenario).\(name).raw") { _ = try YYJSONDecoder(mode: mode).decode(FloatingNumber.self, from: object) }
            }
        }
        recorder.check("control.native.finiteUInt64Fragment", expected: "Native validation preserves Foundation-supported unsigned scalar fragment") {
            let object = NSNumber(value: UInt64.max)
            let control = try JSONDecoder().decode(UInt64.self, from: serialize(object))
            let decoded = try YYJSONDecoder.native().decode(UInt64.self, from: object)
            try insist(decoded == control, "native unsigned scalar fragment differs from Foundation")
            return "Foundation-equivalent UInt64=\(decoded)"
        }
        recorder.check("control.native.finiteDoubleFragment", expected: "Native validation preserves adjacent Double scalar fragment") {
            let object = NSNumber(value: Double(bitPattern: 0x3ff0000000000001))
            let control = try JSONDecoder().decode(Double.self, from: serialize(object))
            let decoded = try YYJSONDecoder.native().decode(Double.self, from: object)
            try insist(decoded.bitPattern == control.bitPattern && decoded.bitPattern == 0x3ff0000000000001, "native Double scalar fragment changed")
            return "Double.bits=0x3ff0000000000001"
        }
        recorder.check("control.native.boolFragment", expected: "Native validation preserves Foundation boolean scalar fragment") {
            let decoded = try YYJSONDecoder.native().decode(Bool.self, from: NSNumber(value: true))
            try insist(decoded, "native boolean scalar fragment changed")
            return "Bool=true"
        }
        recorder.check("control.native.nullFragment", expected: "Native validation preserves Foundation null scalar fragment") {
            let decoded = try YYJSONDecoder.native().decode(Double?.self, from: NSNull())
            try insist(decoded == nil, "native null scalar fragment changed")
            return "Optional<Double>=nil"
        }
    }

    private static func runDates(_ recorder: NumericRecorder) throws {
        let scales = [DateScale(name: "seconds", policy: .secondsSince1970, factor: 1, foundationDecode: .secondsSince1970, foundationEncode: .secondsSince1970),
                      DateScale(name: "milliseconds", policy: .millisecondsSince1970, factor: 1000, foundationDecode: .millisecondsSince1970, foundationEncode: .millisecondsSince1970),
                      DateScale(name: "microseconds", policy: .microsecondsSince1970, factor: 1_000_000, foundationDecode: nil, foundationEncode: nil)]
        let value = DateNumber(value: Date(timeIntervalSince1970: 1700000000.125))
        let overflow = DateNumber(value: Date(timeIntervalSince1970: Double.greatestFiniteMagnitude))
        for scale in scales {
            let object: [String: Any] = ["value": 1700000000.125 * scale.factor]
            let data = try serialize(object)
            let rules = try YYJSONRules().forType(DateNumber.self) { $0.fieldDateStrategies = ["value": scale.policy] }
            if let decoding = scale.foundationDecode, let encoding = scale.foundationEncode {
                recorder.check("date.finite.\(scale.name).foundation", expected: "Foundation explicit date scale retains exact fractional epoch") {
                    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = decoding
                    let decoded = try decoder.decode(DateNumber.self, from: data)
                    try insist(decoded == value, "Foundation scaled date changed epoch")
                    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = encoding
                    let exported = try encoder.encode(decoded)
                    try insist(try decoder.decode(DateNumber.self, from: exported) == value, "Foundation date round-trip changed epoch")
                    return "epoch=1700000000.125; scale=\(scale.factor)"
                }
                recorder.check("date.finite.\(scale.name).native", expected: "Native Data/raw and Data/object date routes match exact same-route Foundation control") {
                    var decoder = YYJSONDecoder.native(); decoder.dateDecodingStrategy = decoding
                    let decoded = try decoder.decode(DateNumber.self, from: data)
                    let rawDecoded = try decoder.decode(DateNumber.self, from: object)
                    try insist(decoded == value && rawDecoded == value, "native finite date changed epoch")
                    var encoder = YYJSONEncoder.native(); encoder.dateEncodingStrategy = encoding
                    let fd = JSONDecoder(); fd.dateDecodingStrategy = decoding
                    let exportedData = try encoder.encode(value)
                    let exportedObject = try serialize(encoder.encodeJSONObject(value))
                    try insist(try fd.decode(DateNumber.self, from: exportedData) == value, "native date Data export changed epoch")
                    try insist(try fd.decode(DateNumber.self, from: exportedObject) == value, "native date object export changed epoch")
                    return "Data/raw + Data/object: epoch=1700000000.125"
                }
            }
            for (name, mode) in modes where mode != .native {
                for rawInput in [false, true] {
                    let route = rawInput ? "raw" : "data"
                    recorder.check("date.finite.\(scale.name).\(name).\(route)", expected: "Explicit date policy retains literal fractional epoch on both JSON exports") {
                        let decoder = YYJSONDecoder(mode: mode, rules: rules)
                        let decoded = rawInput ? try decoder.decode(DateNumber.self, from: object) : try decoder.decode(DateNumber.self, from: data)
                        try insist(decoded == value, "enhanced scaled date changed epoch")
                        let encoder = YYJSONEncoder(mode: mode, rules: rules)
                        let exportedData = try encoder.encode(decoded)
                        let exportedObject = try encoder.encodeJSONObject(decoded)
                        for exported in [try parse(exportedData), exportedObject] {
                            guard let object = exported as? [String: Any], let number = object["value"] as? NSNumber else { throw NumericFailure("date export is not a numeric object") }
                            try insist(number.doubleValue == 1700000000.125 * scale.factor, "date export scale changed")
                            let roundTrip = try decoder.decode(DateNumber.self, from: object)
                            try insist(roundTrip == value, "enhanced date round-trip changed epoch")
                        }
                        return "epoch=1700000000.125; scale=\(scale.factor); Data/object round-trip"
                    }
                }
            }
            if scale.factor > 1 {
                if let encoding = scale.foundationEncode {
                    recorder.rejects("date.scaleOverflow.\(scale.name).foundation") {
                        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = encoding; _ = try encoder.encode(overflow)
                    }
                    for objectOutput in [false, true] {
                        recorder.rejects("date.scaleOverflow.\(scale.name).native.\(objectOutput ? "object" : "data")") {
                            var encoder = YYJSONEncoder.native(); encoder.dateEncodingStrategy = encoding
                            if objectOutput { _ = try encoder.encodeJSONObject(overflow) } else { _ = try encoder.encode(overflow) }
                        }
                    }
                }
                for (name, mode) in modes where mode != .native {
                    for objectOutput in [false, true] {
                        recorder.rejects("date.scaleOverflow.\(scale.name).\(name).\(objectOutput ? "object" : "data")") {
                            let encoder = YYJSONEncoder(mode: mode, rules: rules)
                            if objectOutput { _ = try encoder.encodeJSONObject(overflow) } else { _ = try encoder.encode(overflow) }
                        }
                    }
                }
            }
        }
        let infinite = DateNumber(value: Date(timeIntervalSince1970: .infinity))
        recorder.rejects("date.infinite.foundation") { _ = try JSONEncoder().encode(infinite) }
        for (name, mode) in modes {
            for objectOutput in [false, true] {
                recorder.rejects("date.infinite.\(name).\(objectOutput ? "object" : "data")") {
                    let encoder = YYJSONEncoder(mode: mode)
                    if objectOutput { _ = try encoder.encodeJSONObject(infinite) } else { _ = try encoder.encode(infinite) }
                }
            }
        }
    }
}
