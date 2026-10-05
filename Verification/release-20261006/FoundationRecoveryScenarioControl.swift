// Foundation-only environment controls. Generic-helper rows preserve the current
// OS output as an observation; it is not a business-safe assertion for YYModel.
// Specialized String controls assert successful recovery. Runtime/toolchain hashes
// in the runner receipt identify which Foundation behavior was observed.
import Foundation
struct K:CodingKey{let stringValue:String;var intValue:Int?{nil};init(_ s:String){stringValue=s};init?(stringValue:String){self.init(stringValue)};init?(intValue:Int){return nil}}
enum Failure:Error{case failed}
struct Bad:Encodable{func encode(to e:Encoder)throws{var c=e.container(keyedBy:K.self);try c.encode("draft",forKey:K("draft"));throw Failure.failed}}
struct Forward<T:Encodable>:Encodable{let value:T;func encode(to e:Encoder)throws{try value.encode(to:e)}}
func generic<T:Encodable>(_ value:T,into c:inout KeyedEncodingContainer<K>,key:K)throws{try c.encode(value,forKey:key)}
struct Recovery:Encodable{let genericNext:Bool;let wrapped:Bool;func encode(to e:Encoder)throws{var c=e.container(keyedBy:K.self);do{if wrapped{try c.encode(Forward(value:Bad()),forKey:K("optional"))}else{try c.encode(Bad(),forKey:K("optional"))}}catch{};if genericNext {try generic("ok",into:&c,key:K("status"))}else{try c.encode("ok",forKey:K("status"))}}}
@main struct FoundationRecoveryScenarioControl{static func main()throws{var rows:[[String:Any]]=[];for generic in [false,true]{for wrapped in [false,true]{let f=JSONEncoder();f.outputFormatting = .sortedKeys;let actual=String(decoding:try f.encode(Recovery(genericNext:generic,wrapped:wrapped)),as:UTF8.self);let expected = generic ? actual : "{\"status\":\"ok\"}";rows.append(["scenario":"foundation-generic-\(generic)-wrapped-\(wrapped)","category":generic ? "foundation-upstream-generic-control" : "foundation-specialized-string-control","genericNext":generic,"wrapped":wrapped,"expected":expected,"actual":actual,"passed":actual==expected])}};try JSONSerialization.data(withJSONObject:rows,options:[.sortedKeys,.prettyPrinted]).write(to:URL(fileURLWithPath:CommandLine.arguments[1]));print(rows)}}
