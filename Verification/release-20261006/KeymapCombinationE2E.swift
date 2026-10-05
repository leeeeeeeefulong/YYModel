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
 let expected:[String:String] = [
 "set-distinct":"count=2;bits=4607182418800017408,4607182418800017409",
 "set-single":"count=1;bits=4607182418800017409",
 "optional-nested-array":"4607182418800017409",
 "renamed-parent":"4607182418800017409",
 "snake-parent":"4607182418800017409",
 "model-array-path":"value.Index 0",
 "model-optional-path":"value",
 "int-dictionary":"4607182418800017409",
 "path-collision":"4607182418800017409"
 ]
 var rows:[[String:Any]]=[]
 for scenario in ["set-distinct","set-single","optional-nested-array","renamed-parent","snake-parent","model-array-path","model-optional-path","int-dictionary","path-collision"] {
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
 case "int-dictionary":v="{\"1\":\(t)}"
 default:v="null"
 }
 let identifier=scenario+(hook ? "/hook-on" : "/hook-off")
 let contract=expected[scenario]!
 do {
 let x=try d.decode(Payload.self,from:Data("{\"value\":\(v)}".utf8))
 let actual=String(decoding:x.value,as:UTF8.self)
 rows.append(["scenario":identifier,"combination":scenario,"hook":hook,"expected":contract,"actual":actual,"passed":actual==contract])
 }
 catch {rows.append(["scenario":identifier,"combination":scenario,"hook":hook,"expected":contract,"actual":"error: "+String(describing:error),"error":String(describing:error),"passed":false])}
 }
 }
 try JSONSerialization.data(withJSONObject:rows,options:[.sortedKeys,.prettyPrinted]).write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
 }
}
