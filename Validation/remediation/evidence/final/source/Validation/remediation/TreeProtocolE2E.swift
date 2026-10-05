import Foundation
import YYModelSwift
struct K: CodingKey { let stringValue:String; let intValue:Int?; init(_ s:String,_ i:Int?=nil){stringValue=s;intValue=i};init?(stringValue:String){self.init(stringValue)};init?(intValue:Int){self.init(String(intValue),intValue)} }
struct RepeatedObject: Encodable {func encode(to e:Encoder)throws { var root=e.container(keyedBy:K.self);var a=root.nestedContainer(keyedBy:K.self,forKey:K("payload"));try a.encode(1,forKey:K("first"));var b=root.nestedContainer(keyedBy:K.self,forKey:K("payload"));try b.encode(2,forKey:K("second"))}}
struct RepeatedArray: Encodable {func encode(to e:Encoder)throws { var root=e.container(keyedBy:K.self);var a=root.nestedUnkeyedContainer(forKey:K("payload"));try a.encode(1);var b=root.nestedUnkeyedContainer(forKey:K("payload"));try b.encode(2)}}
struct SuperValue: Encodable {func encode(to e:Encoder)throws {var root=e.container(keyedBy:K.self);var c=root.superEncoder().container(keyedBy:K.self);try c.encode(3,forKey:K("baseValue"))}}
struct Named: Encodable {let name:String;func encode(to e:Encoder)throws{var c=e.container(keyedBy:K.self);try c.encode(1,forKey:K(name))}}
struct DK: Hashable,Codable,CodingKeyRepresentable { let id:Int;var codingKey:any CodingKey{K("key"+String(id),id)};init(_ id:Int){self.id=id};init?<T:CodingKey>(codingKey:T){guard let id=codingKey.intValue else{return nil};self.id=id}}
@main struct TreeProtocolE2E {static func main() throws {
 var rows:[[String:Any]]=[]
 func json(_ d:Data)throws->String{try json(JSONSerialization.jsonObject(with:d,options:.fragmentsAllowed))}
 func json(_ o:Any)throws->String{String(decoding:try JSONSerialization.data(withJSONObject:o,options:[.sortedKeys,.fragmentsAllowed]),as:UTF8.self)}
 func run<T:Encodable>(_ name:String,_ value:T,key:JSONEncoder.KeyEncodingStrategy = .useDefaultKeys,date:JSONEncoder.DateEncodingStrategy = .deferredToDate)throws{
 let f=JSONEncoder();f.keyEncodingStrategy=key;f.dateEncodingStrategy=date;let expected=try json(f.encode(value));var y=YYJSONEncoder.native();y.keyEncodingStrategy=key;y.dateEncodingStrategy=date;let actual=try json(y.encodeJSONObject(value));rows.append(["scenario":name,"expected":expected,"actual":actual,"passed":expected==actual]); if !(value is [DK:Date]) { let r=try YYJSONRules().forType(T.self){$0.transformTo={_,_ in true}}; var hooked=YYJSONEncoder.compatible(rules:r);hooked.keyEncodingStrategy=key;hooked.dateEncodingStrategy=date;let h=try json(hooked.encode(value));rows.append(["scenario":name+"-hook","expected":expected,"actual":h,"passed":expected==h]) }
 }
 try run("repeated-keyed",RepeatedObject());try run("repeated-unkeyed",RepeatedArray());try run("super-custom",SuperValue(),key:.custom{K("X"+$0.last!.stringValue)})
 try run("representable-int-metadata",[DK(7):Date(timeIntervalSince1970:7)],date:.custom{_,e in var c=e.singleValueContainer();try c.encode(e.codingPath.map{"\($0.stringValue)|\($0.intValue.map(String.init) ?? "nil")"}.joined(separator:"/"))})
 for s in ["helloWorld","URLValue","myURLValue","a1B","a12BC","fooǅBar","fooⅢBar","fooİBar","fooÄBär","aⒶB","👩‍💻ABCValue","a\u{301}BCValue","A_BCValue","ab12CD34Ef"] {try run("snake-"+s,Named(name:s),key:.convertToSnakeCase)}
 try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[1]));print(rows.filter{($0["passed"] as? Bool)==false})
}}
