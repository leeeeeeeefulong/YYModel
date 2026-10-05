import Foundation
import YYModelSwift
struct Payload: Codable { var value: Data }
struct Key: CodingKey {
 let stringValue: String
 var intValue: Int? { nil }
 init(_ s:String) {stringValue=s}
 init?(stringValue:String){self.init(stringValue)}
 init?(intValue:Int){return nil}
}
@main struct Probe {
 static func main() throws {
 let t="1.000000000000000111022302462515654042363166809082031251"
 let u="2.000000000000000222044604925031308084726333618164062502"
 var rows:[[String:Any]]=[]
 for scenario in ["scalar","array","optional","key-renamed","key-type","nested","unkeyed"] {
 for hook in [false,true] {
 let rules=try YYJSONRules().forType(Payload.self){if hook{$0.willTransform={$0}}}
 var d=YYJSONDecoder(mode:.compatible,rules:rules)
 if (scenario == "key-renamed" || scenario == "key-type") {
 d.keyDecodingStrategy = .custom { path in
 let k=path.last!.stringValue
 return Key(k == "foo" ? "bar" : k == "bar" ? "baz" : k)
 }
 }
 d.dataDecodingStrategy = .custom { decoder in
 let n:Double
 switch scenario {
 case "array": n=try decoder.singleValueContainer().decode([Double].self)[0]
 case "optional": n=try decoder.singleValueContainer().decode(Double?.self)!
 case "key-renamed","key-type": n=try decoder.container(keyedBy:Key.self).decode(Double.self,forKey:Key("bar"))
 case "nested": n=try decoder.container(keyedBy:Key.self).nestedContainer(keyedBy:Key.self,forKey:Key("inner")).decode(Double.self,forKey:Key("n"))
 case "unkeyed": var c=try decoder.unkeyedContainer(); n=try c.decode(Double.self)
 default: n=try decoder.singleValueContainer().decode(Double.self)
 }
 return Data("\(n)|\(n.bitPattern)".utf8)
 }
 let v:String
 switch scenario {
 case "array","unkeyed":v="[\(t)]"
 case "key-renamed":v="{\"foo\":\(t),\"bar\":\(u)}"
 case "key-type":v="{\"foo\":\"not-a-number\",\"bar\":\(u)}"
 case "nested":v="{\"inner\":{\"n\":\(t)}}"
 default:v=t
 }
 do {let x=try d.decode(Payload.self,from:Data("{\"value\":\(v)}".utf8));rows.append(["scenario":scenario,"hook":hook,"result":String(decoding:x.value,as:UTF8.self)])}
 catch {rows.append(["scenario":scenario,"hook":hook,"error":String(describing:error)])}
 }
 }
 try JSONSerialization.data(withJSONObject:rows,options:[.sortedKeys,.prettyPrinted]).write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
 }
}
