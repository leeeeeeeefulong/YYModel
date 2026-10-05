import Foundation
import YYModelSwift
struct K: CodingKey { let stringValue: String; let intValue: Int? = nil; init(_ s: String) { stringValue=s }; init?(stringValue: String){self.init(stringValue)}; init?(intValue: Int){return nil} }
struct C: Codable { var value: Int; var hookValue: Int? }
struct P: Codable { var child: C }
struct R: Codable { var parent: P }
@main struct Main {
 static func main() throws {
  let rules = try YYJSONRules().forType(C.self) { $0.didTransform = { m, input in m.hookValue = (input["value"] as? NSNumber)?.intValue; return true } }
  var d = YYJSONDecoder.compatible(rules: rules)
  d.keyDecodingStrategy = .custom { path in K(path.last!.stringValue.replacingOccurrences(of: "_raw", with: "")) }
  let plain = JSONDecoder(); plain.keyDecodingStrategy = d.keyDecodingStrategy
  for json in [#"{"parent_raw":{"child_raw":{"value":1},"child":{"value":2}}}"#, #"{"parent_raw":{"child":{"value":2},"child_raw":{"value":1}}}"#] {
   for route in [YYJSONNumberParsingStrategy.foundation, .integerTokens] {
    d.numberParsingStrategy=route
    let result=try d.decode(R.self, from: Data(json.utf8))
    print("route=\(route) value=\(result.parent.child.value) hook=\(result.parent.child.hookValue!) json=\(json)")
   }
   let result = try plain.decode(R.self, from: Data(json.utf8)); print("Foundation value=\(result.parent.child.value)")
  }
 }
}
