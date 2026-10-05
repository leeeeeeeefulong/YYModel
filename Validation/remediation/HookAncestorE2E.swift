import Foundation
import YYModelSwift
private struct Key: CodingKey {
    let stringValue: String; var intValue: Int? { nil }
    init(_ s: String) { stringValue=s }; init?(stringValue: String) { self.init(stringValue) }; init?(intValue: Int) { return nil }
}
private struct C: Codable { var value: Int; var hookValue: Int? }
private struct P: Codable { var child: C }
private struct R: Codable { var parent: P }
private struct ArrayRoot: Codable { var parents: [P] }
private struct DictRoot: Codable { var parents: [String: P] }
private struct SnakeP: Codable { var childId: C }
private struct SnakeRoot: Codable { var parentId: SnakeP }
@main private struct HookAncestorE2E {
    static func main() throws {
        var rows: [[String: Any]] = []
        let rules = try YYJSONRules().forType(C.self) { $0.didTransform = { model, input in model.hookValue = (input["value"] as? NSNumber)?.intValue; return true } }
        var decoder = YYJSONDecoder.compatible(rules: rules); decoder.numberParsingStrategy = .foundation
        decoder.keyDecodingStrategy = .custom { Key($0.last!.stringValue.replacingOccurrences(of: "_raw", with: "")) }
        let native = JSONDecoder(); native.keyDecodingStrategy = decoder.keyDecodingStrategy
        func check<T: Codable>(_ name: String, _ type: T.Type, _ json: String, _ leaf: (T) -> C) {
            do {
                let data = Data(json.utf8)
                let expected = try leaf(native.decode(type, from: data)).value
                let actual = try leaf(decoder.decode(type, from: data))
                rows.append(["scenario": name, "expected": "\(expected),\(expected)", "actual": "\(actual.value),\(actual.hookValue.map(String.init) ?? "nil")", "passed": actual.value == expected && actual.hookValue == expected])
            } catch { rows.append(["scenario": name, "actual": String(describing: error), "passed": false]) }
        }
        check("renamed-parent-hook-collision", R.self, #"{"parent_raw":{"child_raw":{"value":1},"child":{"value":2}}}"#) { $0.parent.child }
        check("array-parent-hook-collision", ArrayRoot.self, #"{"parents":[{"child_raw":{"value":1},"child":{"value":2}}]}"#) { $0.parents[0].child }
        check("dictionary-parent-hook-collision", DictRoot.self, #"{"parents_raw":{"key":{"child_raw":{"value":1},"child":{"value":2}}}}"#) { $0.parents["key"]!.child }
        check("null-losing-child-hook-collision", R.self, #"{"parent_raw":{"child_raw":{"value":1},"child":null}}"#) { $0.parent.child }
        decoder.keyDecodingStrategy = .convertFromSnakeCase; native.keyDecodingStrategy = .convertFromSnakeCase
        check("snake-parent-hook-collision", SnakeRoot.self, #"{"parent_id":{"child_id":{"value":1},"childId":{"value":2}}}"#) { $0.parentId.childId }
        try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
