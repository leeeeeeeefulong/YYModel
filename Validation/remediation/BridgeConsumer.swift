import Foundation
import YYModelSwift
struct Bytes: Codable {var value:Data}
struct Moment: Codable {var value:Date}
@main struct Probe {
 static func main()throws {
 var rows:[[String:Any]]=[]
 let token="1.000000000000000111022302462515654042363166809082031251"
 let data=Data("{\"value\":\(token)}".utf8)
 for hooked in [false,true] {
 let rb=try YYJSONRules().forType(Bytes.self){if hooked {$0.willTransform={$0}}}
 var d=YYJSONDecoder(mode:.compatible,rules:rb)
 d.dataDecodingStrategy = .custom { decoder in
 let n=try decoder.singleValueContainer().decode(Double.self)
 return Data(String(n.bitPattern).utf8)
 }
 let result=try d.decode(Bytes.self,from:data)
 rows.append(["name":"custom-data-hook=\(hooked)","bits":String(decoding:result.value,as:UTF8.self)])
 let rm=try YYJSONRules().forType(Moment.self){if hooked {$0.willTransform={$0}}}
 var md=YYJSONDecoder(mode:.compatible,rules:rm)
 md.dateDecodingStrategy = .custom {Date(timeIntervalSinceReferenceDate:try $0.singleValueContainer().decode(Double.self))}
 rows.append(["name":"custom-date-hook=\(hooked)","bits":String(try md.decode(Moment.self,from:data).value.timeIntervalSinceReferenceDate.bitPattern)])
 }
 try JSONSerialization.data(withJSONObject:rows,options:[.sortedKeys,.prettyPrinted]).write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
 }
}
