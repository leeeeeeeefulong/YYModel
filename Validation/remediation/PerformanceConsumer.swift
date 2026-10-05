import Foundation
import YYModelSwift

// ============================================================================
//  性能隔离基准
//
//  目的：把「适配层固定开销」与「规则开销」分开测量，避免优化错靶心。
//
//  运行：python3 Validation/remediation/run_performance.py --acceptance-root <冻结验收目录> --output <新目录>
//
//  注意：标签用 ASCII —— String(format:) 对多字节 UTF-8 会截断。
// ============================================================================

struct Geo: Codable { var lat: String; var lng: String }
struct Addr: Codable { var city: String; var zipcode: String; var geo: Geo }
struct Company: Codable { var name: String; var catchPhrase: String; var bs: String }

struct Tiny: Codable { var a: String; var b: Int }

struct Mid: Codable {
    var id: Int; var name: String; var username: String; var email: String
    var phone: String; var website: String
    var address: Addr; var company: Company
}

struct Payload: Codable { var users: [Mid]; var total: Int; var page: Int }

private let tinyJSON = #"{"a":"x","b":1}"#
private let midJSON = #"{"id":1,"name":"n","username":"u","email":"e","phone":"p","website":"w","address":{"city":"c","zipcode":"z","geo":{"lat":"1","lng":"2"}},"company":{"name":"n","catchPhrase":"c","bs":"b"}}"#
private let payloadJSON = #"{"total":10,"page":1,"users":["# + Array(repeating: midJSON, count: 5).joined(separator: ",") + "]}"

private let tinyData = Data(tinyJSON.utf8)
private let midData = Data(midJSON.utf8)
private let payloadData = Data(payloadJSON.utf8)

private func measure(_ iterations: Int, _ body: () throws -> Void) -> Double {
    for _ in 0..<100 { do { try body() } catch { fatalError("Benchmark decode failed: \(error)") } }
    var best = Double.infinity
    for _ in 0..<9 {
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<iterations { do { try body() } catch { fatalError("Benchmark decode failed: \(error)") } }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000 / Double(iterations)
        best = min(best, elapsed)
    }
    return best
}

private let iterations = 3000
private let fieldCounts = ["tiny": 2.0, "mid": 14.0, "payload": 70.0]

private func report(_ label: String, key: String, official: Double, yy: Double) {
    let perField = (yy - official) * 1000 / (fieldCounts[key] ?? 1)
    print(String(format: "  %-34@ official %.5f | yy %.5f | ratio %.2fx | +%.3f us/field",
                 label as NSString, official, yy, yy / official, perField))
}

print("perf-isolation: release -O, best-of-9, 100 warmup, \(iterations) iterations\n")

print("[A] native mode vs official  (historical target <= 1.10x; assess absolute baseline as well)")
report("Tiny    (2 fields)", key: "tiny",
       official: measure(iterations) { _ = try JSONDecoder().decode(Tiny.self, from: tinyData) },
       yy: measure(iterations) { _ = try YYJSONDecoder(mode: .native).decode(Tiny.self, from: tinyData) })
report("Mid     (14 fields)", key: "mid",
       official: measure(iterations) { _ = try JSONDecoder().decode(Mid.self, from: midData) },
       yy: measure(iterations) { _ = try YYJSONDecoder(mode: .native).decode(Mid.self, from: midData) })
report("Payload (70 fields)", key: "payload",
       official: measure(iterations) { _ = try JSONDecoder().decode(Payload.self, from: payloadData) },
       yy: measure(iterations) { _ = try YYJSONDecoder(mode: .native).decode(Payload.self, from: payloadData) })

print("\n[B] compatible mode, EMPTY rules  (R-2: target <= 3.00x)")
report("Tiny    (2 fields)", key: "tiny",
       official: measure(iterations) { _ = try JSONDecoder().decode(Tiny.self, from: tinyData) },
       yy: measure(iterations) { _ = try YYJSONDecoder(mode: .compatible).decode(Tiny.self, from: tinyData) })
report("Mid     (14 fields)", key: "mid",
       official: measure(iterations) { _ = try JSONDecoder().decode(Mid.self, from: midData) },
       yy: measure(iterations) { _ = try YYJSONDecoder(mode: .compatible).decode(Mid.self, from: midData) })
report("Payload (70 fields)", key: "payload",
       official: measure(iterations) { _ = try JSONDecoder().decode(Payload.self, from: payloadData) },
       yy: measure(iterations) { _ = try YYJSONDecoder(mode: .compatible).decode(Payload.self, from: payloadData) })

print("\n[C] compatible mode, WITH rules  (A2.5: rules overhead must be <= 1.10x of empty)")
let rules = try! YYJSONRules().forType(Mid.self) { rule in
    rule.map(\.username, from: "username")
    rule.default(\.website, to: "none")
    rule.require(\.id)
}
let withRules = measure(iterations) { _ = try YYJSONDecoder(mode: .compatible, rules: rules).decode(Payload.self, from: payloadData) }
let emptyRules = measure(iterations) { _ = try YYJSONDecoder(mode: .compatible).decode(Payload.self, from: payloadData) }
print(String(format: "  Payload  empty %.5f | withRules %.5f | rules overhead %.3fx",
             emptyRules, withRules, withRules / emptyRules))

print("\n[D] legacy mode, EMPTY rules  (informational: default entry point)")
report("Payload (70 fields)", key: "payload",
       official: measure(iterations) { _ = try JSONDecoder().decode(Payload.self, from: payloadData) },
       yy: measure(iterations) { _ = try YYJSONDecoder().decode(Payload.self, from: payloadData) })
