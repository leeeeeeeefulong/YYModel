import Foundation
import YYModelSwift
struct Key: CodingKey { let stringValue: String; let intValue: Int? = nil; init(_ s: String) { stringValue=s }; init?(stringValue: String){self.init(stringValue)}; init?(intValue: Int){return nil} }
struct C: Codable { var value: Int; var hookValue: Int? }
struct P: Codable { var child: C }
struct ArrayRoot: Codable { var parents: [P] }
struct DictRoot: Codable { var parents: [String: P] }
struct SnakeP: Codable { var childId: C }
struct SnakeRoot: Codable { var parentId: SnakeP }
@main struct Main {
 static func main() throws {
  var rows: [[String: Any]]=[]
  let rules = try YYJSONRules().forType(C.self) { $0.didTransform = { m, input in m.hookValue = (input["value"] as? NSNumber)?.intValue; return true } }
  var d = YYJSONDecoder.compatible(rules: rules); d.numberParsingStrategy = .foundation
  d.keyDecodingStrategy = .custom { Key($0.last!.stringValue.replacingOccurrences(of: "_raw", with: "")) }
  let f=JSONDecoder(); f.keyDecodingStrategy=d.keyDecodingStrategy
  let array=Data(#"{"parents":[{"child_raw":{"value":1},"child":{"value":2}}]}"#.utf8)
  let a=try d.decode(ArrayRoot.self,from:array).parents[0].child
  rows.append(["scenario":"array-index-parent-collision","value":a.value,"hookValue":a.hookValue!,"Foundation":try f.decode(ArrayRoot.self,from:array).parents[0].child.value,"passed":a.value == a.hookValue])
  let dictionary=Data(#"{"parents_raw":{"key":{"child_raw":{"value":1},"child":{"value":2}}}}"#.utf8)
  let b=try d.decode(DictRoot.self,from:dictionary).parents["key"]!.child
  rows.append(["scenario":"renamed-dictionary-parent-collision","value":b.value,"hookValue":b.hookValue!,"Foundation":try f.decode(DictRoot.self,from:dictionary).parents["key"]!.child.value,"passed":b.value == b.hookValue])
  d.keyDecodingStrategy = .convertFromSnakeCase; f.keyDecodingStrategy = .convertFromSnakeCase
  let snake=Data(#"{"parent_id":{"child_id":{"value":1},"childId":{"value":2}}}"#.utf8)
  let c=try d.decode(SnakeRoot.self,from:snake).parentId.childId
  rows.append(["scenario":"snake-parent-collision","value":c.value,"hookValue":c.hookValue!,"Foundation":try f.decode(SnakeRoot.self,from:snake).parentId.childId.value,"passed":c.value == c.hookValue])
  try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
 }
}
