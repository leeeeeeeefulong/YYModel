// Public optimized-library E2E: referencing encoder lifetime extends through
// keyed/unkeyed/single and derived containers, within one encode(to:) call.
import Foundation
import YYModelSwift

private struct LifetimeKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ text: String) { stringValue = text }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { return nil }
}

private struct LifetimeModel: Encodable {
    let scenario: String
    func encode(to encoder: Encoder) throws {
        var parent = encoder.container(keyedBy: LifetimeKey.self)
        let target = LifetimeKey(scenario == "noarg-keyed" ? "super" : "payload")
        var retained: (any Encoder)? = scenario == "noarg-keyed"
            ? parent.superEncoder() : parent.superEncoder(forKey: target)
        switch scenario {
        case "unkeyed":
            var child = retained!.unkeyedContainer()
            retained = nil
            try parent.encode("later-direct", forKey: target)
            try child.encode("base")
            withExtendedLifetime(child) {}
        case "single":
            var child = retained!.singleValueContainer()
            retained = nil
            try parent.encode("later-direct", forKey: target)
            try child.encode("base")
            withExtendedLifetime(child) {}
        case "nested-keyed":
            var child: KeyedEncodingContainer<LifetimeKey>? = retained!.container(keyedBy: LifetimeKey.self)
            var nested = child!.nestedContainer(keyedBy: LifetimeKey.self, forKey: LifetimeKey("nested"))
            retained = nil
            child = nil
            try parent.encode("later-direct", forKey: target)
            try nested.encode("base", forKey: LifetimeKey("value"))
            withExtendedLifetime(nested) {}
        case "nested-unkeyed":
            var child: KeyedEncodingContainer<LifetimeKey>? = retained!.container(keyedBy: LifetimeKey.self)
            var nested = child!.nestedUnkeyedContainer(forKey: LifetimeKey("nested"))
            retained = nil
            child = nil
            try parent.encode("later-direct", forKey: target)
            try nested.encode("base")
            withExtendedLifetime(nested) {}
        case "descendant-super":
            var child: KeyedEncodingContainer<LifetimeKey>? = retained!.container(keyedBy: LifetimeKey.self)
            var nestedEncoder: (any Encoder)? = child!.superEncoder(forKey: LifetimeKey("nested"))
            var nested = nestedEncoder!.container(keyedBy: LifetimeKey.self)
            retained = nil
            child = nil
            nestedEncoder = nil
            try parent.encode("later-direct", forKey: target)
            try nested.encode("base", forKey: LifetimeKey("value"))
            withExtendedLifetime(nested) {}
        default:
            var child = retained!.container(keyedBy: LifetimeKey.self)
            retained = nil
            try parent.encode("later-direct", forKey: target)
            try child.encode("base", forKey: LifetimeKey("value"))
            withExtendedLifetime(child) {}
        }
    }
}

@main private struct SuperContainerLifetimeE2E {
    static func main() throws {
        func canonical(_ value: Any) throws -> String {
            String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed]), as: UTF8.self)
        }
        func json(_ data: Data) throws -> String {
            try canonical(JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed))
        }
        let native = YYJSONEncoder.native()
        let compatible = YYJSONEncoder.compatible()
        let rules = try YYJSONRules().forType(LifetimeModel.self) { $0.transformTo = { _, _ in true } }
        let hook = YYJSONEncoder.compatible(rules: rules)
        var rows: [[String: Any]] = []
        for scenario in ["keyed", "unkeyed", "single", "nested-keyed", "nested-unkeyed", "noarg-keyed", "descendant-super"] {
            let value = LifetimeModel(scenario: scenario)
            let expected = try json(JSONEncoder().encode(value))
            for route in ["native-data", "native-object", "compatible-data", "compatible-object", "hook-data", "hook-object"] {
                do {
                    let actual: String
                    switch route {
                    case "native-data": actual = try json(native.encode(value))
                    case "native-object": actual = try canonical(native.encodeJSONObject(value))
                    case "compatible-data": actual = try json(compatible.encode(value))
                    case "compatible-object": actual = try canonical(compatible.encodeJSONObject(value))
                    case "hook-data": actual = try json(hook.encode(value))
                    default: actual = try canonical(hook.encodeJSONObject(value))
                    }
                    rows.append(["scenario": "super-container-lifetime-\(scenario)", "route": route, "expected": expected, "actual": actual, "passed": actual == expected])
                } catch {
                    rows.append(["scenario": "super-container-lifetime-\(scenario)", "route": route, "expected": expected, "error": String(describing: error), "passed": false])
                }
            }
        }
        try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        print("rows=\(rows.count) mismatches=\(rows.filter { ($0["passed"] as? Bool) == false }.count)")
    }
}
