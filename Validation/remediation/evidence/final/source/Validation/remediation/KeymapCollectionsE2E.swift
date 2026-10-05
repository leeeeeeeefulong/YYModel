import Foundation
import YYModelSwift
struct Payload: Codable {var value:Data}
struct Key: CodingKey {
 let stringValue:String
 var intValue:Int? {nil}
 init(_ s:String){stringValue=s}
 init?(stringValue:String){self.init(stringValue)}
 init?(intValue:Int){return nil}
}
struct PathLeaf: Decodable {
 let path:String
 init(from decoder:Decoder)throws {path=decoder.codingPath.map(\.stringValue).joined(separator:".")}
}
@main struct Probe {
 static func main()throws {
 let t="1.000000000000000111022302462515654042363166809082031251"
 let u="2.000000000000000222044604925031308084726333618164062502"
 var rows:[[String:Any]]=[]
 for scenario in ["set-distinct","set-single","optional-nested-array","renamed-parent","snake-parent","model-array-path","model-optional-path","int-dictionary","path-collision","unkeyed-nested-cursor","set-float-distinct","dictionary-model-path"] {
 for hook in [false,true] {
 let rules=try YYJSONRules().forType(Payload.self){if hook{$0.willTransform={$0}}}
 var d=YYJSONDecoder(mode:.compatible,rules:rules)
 if scenario == "renamed-parent" {
 d.keyDecodingStrategy = .custom {path in
 let s=path.last!.stringValue
 return Key(s == "physical_parent" ? "parent" : s == "parent" ? "unused" : s)
 }
 } else if scenario == "path-collision" {
 d.keyDecodingStrategy = .custom {path in
 let k=path.last!.stringValue
 if k == "first" {return Key(path.count == 3 ? "n" : "other")}
 if k == "second" {return Key("n")}
 return Key(k)
 }
 } else if scenario == "snake-parent" {d.keyDecodingStrategy = .convertFromSnakeCase}
 d.dataDecodingStrategy = .custom {decoder in
 let s:String
 switch scenario {
 case "set-distinct","set-single":
 let a=try decoder.singleValueContainer().decode(Set<Double>.self)
 s="count=\(a.count);bits="+a.map{String($0.bitPattern)}.sorted().joined(separator:",")
 case "optional-nested-array":
 let a=try decoder.singleValueContainer().decode([[Double]]?.self)!
 s=String(a[0][0].bitPattern)
 case "renamed-parent","snake-parent":
 let c=try decoder.container(keyedBy:Key.self)
 let n=try c.nestedContainer(keyedBy:Key.self,forKey:Key(scenario == "snake-parent" ? "parentNode" : "parent"))
 s=String(try n.decode(Double.self,forKey:Key("foo")).bitPattern)
 case "model-array-path":
 s=try decoder.singleValueContainer().decode([PathLeaf].self)[0].path
 case "model-optional-path":
 s=try decoder.singleValueContainer().decode(PathLeaf?.self)!.path
 case "path-collision":
 let c=try decoder.container(keyedBy:Key.self)
 let first=try c.nestedContainer(keyedBy:Key.self,forKey:Key("a#-1/b"))
 _ = try first.decode(Double.self,forKey:Key("n"))
 let a=try c.nestedContainer(keyedBy:Key.self,forKey:Key("a"))
 let second=try a.nestedContainer(keyedBy:Key.self,forKey:Key("b"))
 s=String(try second.decode(Double.self,forKey:Key("n")).bitPattern)
 case "unkeyed-nested-cursor":
 var outer=try decoder.unkeyedContainer()
 var first=try outer.nestedUnkeyedContainer()
 let x=try first.decode(Double.self)
 let second=try outer.nestedContainer(keyedBy:Key.self)
 let y=try second.decode(Double.self,forKey:Key("foo"))
 s=String(x.bitPattern)+","+String(y.bitPattern)
 case "set-float-distinct":
 let a=try decoder.singleValueContainer().decode(Set<Float>.self)
 s="count=\(a.count);bits="+a.map{String($0.bitPattern)}.sorted().joined(separator:",")
 case "dictionary-model-path":
 s=try decoder.singleValueContainer().decode([String:PathLeaf].self)["key"]!.path
 case "int-dictionary":
 s=String(try decoder.singleValueContainer().decode([Int:Double].self)[1]!.bitPattern)
 default: s="unknown"
 }
 return Data(s.utf8)
 }
 let v:String
 switch scenario {
 case "set-distinct":v="[1.0,\(t)]"
 case "set-single":v="[\(t)]"
 case "optional-nested-array":v="[[\(t)]]"
 case "renamed-parent":v="{\"physical_parent\":{\"foo\":\(t)},\"parent\":{\"foo\":\(u)}}"
 case "snake-parent":v="{\"parent_node\":{\"foo\":\(t)}}"
 case "model-array-path":v="[{}]"
 case "model-optional-path":v="{}"
 case "path-collision":v="{\"a#-1/b\":{\"first\":\(t)},\"a\":{\"b\":{\"second\":\(t),\"first\":\(u)}}}"
 case "unkeyed-nested-cursor":v="[[\(t)],{\"foo\":\(u)}]"
 case "set-float-distinct":v="[1.0,1.0000000596046448]"
 case "dictionary-model-path":v="{\"key\":{}}"
 case "int-dictionary":v="{\"1\":\(t)}"
 default:v="null"
 }
 do {let x=try d.decode(Payload.self,from:Data("{\"value\":\(v)}".utf8)); rows.append(["scenario":scenario,"hook":hook,"result":String(decoding:x.value,as:UTF8.self)])}
 catch {rows.append(["scenario":scenario,"hook":hook,"error":String(describing:error)])}
 }
 }
 try JSONSerialization.data(withJSONObject:rows,options:[.sortedKeys,.prettyPrinted]).write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
 }
}
