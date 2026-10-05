import Foundation
import YYModelSwift

private struct DateModel: Codable, Equatable {
    var date: Date
}

private struct DateDictModel: Codable {
    var dates: [String: Date]
}

private struct CoercionModel: Codable {
    var flag: Bool
    var count: Int
    var normalInt: Int
}

@main private struct DateAndCoercionE2E {
    static func main() throws {
        var rows: [[String: Any]] = []
        func check(_ name: String, _ expected: String, _ body: () throws -> String) {
            do {
                let actual = try body()
                rows.append(["scenario": name, "expected": expected, "actual": actual, "passed": actual == expected])
            } catch {
                rows.append(["scenario": name, "expected": expected, "actual": String(describing: error), "passed": false])
            }
        }

        // P-05: Explicit microsecondsSince1970
        check("date-explicit-microseconds-decode", "1000.5") {
            let rules = try YYJSONRules().forType(DateModel.self) { $0.dateStrategy = .microsecondsSince1970 }
            let d = YYJSONDecoder.compatible(rules: rules)
            // 1000.5 seconds = 1_000_500_000 microseconds
            let m = try d.decode(DateModel.self, from: Data("{\"date\": 1000500000}".utf8))
            return String(m.date.timeIntervalSince1970)
        }

        check("date-microseconds-dictionary", "1000.25") {
            let rules = try YYJSONRules().forType(DateDictModel.self) {
                $0.dateStrategy = .microsecondsSince1970
            }
            let d = YYJSONDecoder.compatible(rules: rules)
            let m = try d.decode(DateDictModel.self, from: Data("{\"dates\": {\"t1\": 1000250000}}".utf8))
            return String(m.dates["t1"]!.timeIntervalSince1970)
        }

        check("date-microseconds-field-dates", "1000.125") {
            let rules = try YYJSONRules().forType(DateDictModel.self) {
                $0.fieldDateStrategies = ["dates": .microsecondsSince1970]
            }
            let d = YYJSONDecoder.compatible(rules: rules)
            let m = try d.decode(DateDictModel.self, from: Data("{\"dates\": {\"t1\": 1000125000}}".utf8))
            return String(m.dates["t1"]!.timeIntervalSince1970)
        }

        check("date-microseconds-negative", "-2.5") {
            let rules = try YYJSONRules().forType(DateModel.self) { $0.dateStrategy = .microsecondsSince1970 }
            let d = YYJSONDecoder.compatible(rules: rules)
            // -2.5 seconds = -2_500_000 microseconds
            let m = try d.decode(DateModel.self, from: Data("{\"date\": -2500000}".utf8))
            return String(m.date.timeIntervalSince1970)
        }

        check("date-microseconds-encode-roundtrip", "true") {
            let rules = try YYJSONRules().forType(DateModel.self) { $0.dateStrategy = .microsecondsSince1970 }
            let encoder = YYJSONEncoder.compatible(rules: rules)
            let decoder = YYJSONDecoder.compatible(rules: rules)
            let original = DateModel(date: Date(timeIntervalSince1970: 1700000000.123456))
            let data = try encoder.encode(original)
            let decoded = try decoder.decode(DateModel.self, from: data)
            let diff = abs(decoded.date.timeIntervalSince1970 - original.date.timeIntervalSince1970)
            return String(diff < 0.00001)
        }

        check("date-automatic-heuristic-unchanged", "1700000000") {
            // automatic: 1700000000 is <= 1e11, so treated as seconds, NOT milliseconds or microseconds
            let d = YYJSONDecoder.legacy()
            let m = try d.decode(DateModel.self, from: Data("{\"date\": 1700000000}".utf8))
            return String(Int(m.date.timeIntervalSince1970))
        }

        // P-08: Optional coercion report diagnostics
        check("coercion-default-off", "0") {
            let d = YYJSONDecoder.compatible()
            let m = try d.decode(CoercionModel.self, from: Data("{\"flag\": 1, \"count\": \"42\", \"normalInt\": 100}".utf8))
            return String(m.count - (m.flag ? 42 : 0)) // 0, works without report
        }

        check("coercion-report-records", "number:Bool,string:Int") {
            var d = YYJSONDecoder.compatible()
            let report = YYModelCoercionReport()
            d.userInfo[YYModelCoercionReport.key] = report
            _ = try d.decode(CoercionModel.self, from: Data("{\"flag\": 1, \"count\": \"42\", \"normalInt\": 100}".utf8))
            let records = report.records
            // Expect records for flag (1 -> Bool) and count ("42" -> Int), but NOT for normalInt (100 -> Int)
            let summary = records.map { "\($0.sourceCategory):\($0.targetType)" }.joined(separator: ",")
            return summary
        }

        check("coercion-truncation-record", "float-truncated-to-integer:3") {
            var d = YYJSONDecoder.compatible()
            let report = YYModelCoercionReport()
            d.userInfo[YYModelCoercionReport.key] = report
            let m = try d.decode(CoercionModel.self, from: Data("{\"flag\": true, \"count\": 3.9, \"normalInt\": 100}".utf8))
            let truncRecords = report.records.filter { $0.reason == "float-truncated-to-integer" }
            return "\(truncRecords.first?.reason ?? "none"):\(m.count)"
        }

        check("coercion-report-isolation-and-concurrency", "true") {
            final class SafeState: @unchecked Sendable {
                var passed = true
                let lock = NSLock()
                func fail() { lock.lock(); passed = false; lock.unlock() }
                func get() -> Bool { lock.lock(); defer { lock.unlock() }; return passed }
            }
            let state = SafeState()
            let group = DispatchGroup()
            for _ in 0..<10 {
                group.enter()
                DispatchQueue.global().async {
                    do {
                        var d = YYJSONDecoder.compatible()
                        let report = YYModelCoercionReport()
                        d.userInfo[YYModelCoercionReport.key] = report
                        _ = try d.decode(CoercionModel.self, from: Data("{\"flag\": 0, \"count\": \"10\", \"normalInt\": 5}".utf8))
                        if report.records.count != 2 {
                            state.fail()
                        }
                    } catch {
                        state.fail()
                    }
                    group.leave()
                }
            }
            group.wait()
            return String(state.get())
        }

        try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys, .prettyPrinted])
            .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
