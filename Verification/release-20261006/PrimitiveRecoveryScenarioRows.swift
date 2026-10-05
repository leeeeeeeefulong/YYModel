// Public optimized-library E2E scenarios. Direct Int/Bool/Double writes must
// recover to the successful value. Caller-written generic helpers in native Data
// and compatible Data are Foundation controls: their observed upstream draft leak
// is not a required tree behavior. Tree/hook routes must contain only the successful
// primitive after a caught failing child, even when the caller uses a generic helper.
import Foundation
import YYModelSwift
struct K: CodingKey { let stringValue: String; var intValue: Int? { nil }; init(_ v: String) { stringValue=v }; init?(stringValue: String) { self.init(stringValue) }; init?(intValue: Int) { return nil } }
enum Failure: Error { case failed }
struct Bad: Encodable { let partial: Bool; func encode(to e: Encoder) throws { if partial { var c=e.container(keyedBy:K.self);try c.encode("sensitive-draft",forKey:K("draft")) }; throw Failure.failed } }
struct KeyRecovery: Encodable { let partial:Bool;let previous:Bool;func encode(to e:Encoder)throws {var c=e.container(keyedBy:K.self);if previous { try c.encode("last-valid",forKey:K("optional")) };do {try c.encode(Bad(partial:partial),forKey:K("optional"))}catch{};try c.encode("ok",forKey:K("status"))} }
struct ArrayRecovery: Encodable {let partial:Bool;func encode(to e:Encoder)throws{var c=e.unkeyedContainer();try c.encode("first");do {try c.encode(Bad(partial:partial))}catch{};try c.encode(c.count);try c.encode("last")} }
struct SingleRecovery: Encodable {func encode(to e:Encoder)throws{var c=e.singleValueContainer();do {try c.encode(Bad(partial:true))}catch{};try c.encode("fallback")} }
struct Wrapped<T:Encodable>:Encodable {let payload:T}
struct LateSuper:Encodable {func encode(to e:Encoder)throws{var c=e.container(keyedBy:K.self);let s=c.superEncoder(forKey:K("payload"));try c.encode("later-direct",forKey:K("payload"));var sc=s.singleValueContainer();try sc.encode("base");withExtendedLifetime(s){}}}
func keyedGeneric<T:Encodable>(_ v:T,_ c:inout KeyedEncodingContainer<K>)throws{try c.encode(v,forKey:K("status"))}
func arrayGeneric<T:Encodable>(_ v:T,_ c:inout any UnkeyedEncodingContainer)throws{try c.encode(v)}
struct PrimitiveRecovery:Encodable {let kind:Int;let array:Bool;let generic:Bool;func encode(to e:Encoder)throws{
 if array {var c=e.unkeyedContainer();do{try c.encode(Bad(partial:true))}catch{};switch kind{case 0:if generic{try arrayGeneric(7,&c)}else{try c.encode(7)};case 1:if generic{try arrayGeneric(true,&c)}else{try c.encode(true)};default:if generic{try arrayGeneric(1.25,&c)}else{try c.encode(1.25)}}}
 else{var c=e.container(keyedBy:K.self);do{try c.encode(Bad(partial:true),forKey:K("optional"))}catch{};switch kind{case 0:if generic{try keyedGeneric(7,&c)}else{try c.encode(7,forKey:K("status"))};case 1:if generic{try keyedGeneric(true,&c)}else{try c.encode(true,forKey:K("status"))};default:if generic{try keyedGeneric(1.25,&c)}else{try c.encode(1.25,forKey:K("status"))}}}
}}
@main struct PrimitiveRecoveryScenarioRows { static func main() throws {
 var rows:[[String:Any]]=[]
 func canonical(_ o:Any)throws->String {String(decoding:try JSONSerialization.data(withJSONObject:o,options:[.fragmentsAllowed,.sortedKeys]),as:UTF8.self)}
 func json(_ d:Data)throws->String {try canonical(JSONSerialization.jsonObject(with:d,options:.fragmentsAllowed))}
 func run<T:Encodable>(_ name:String,_ v:T,_ success:Any,_ generic:Bool)throws {let foundationExpected=try json(JSONEncoder().encode(v));let successExpected=try canonical(success);let native=YYJSONEncoder.native();let compatible=YYJSONEncoder.compatible();let rules=try YYJSONRules().forType(T.self){$0.transformTo={_,_ in true}};let hooked=YYJSONEncoder.compatible(rules:rules)
 for route in ["native-data","native-object","compatible-data","compatible-object","hook-data","hook-object"] {
 let upstreamControl = generic && (route == "native-data" || route == "compatible-data")
 let expected = upstreamControl ? foundationExpected : successExpected
 let category = upstreamControl ? "foundation-generic-helper-control" : "successful-primitive-recovery"
 do {let actual:String;switch route {case "native-data":actual=try json(native.encode(v));case "native-object":actual=try canonical(native.encodeJSONObject(v));case "compatible-data":actual=try json(compatible.encode(v));case "compatible-object":actual=try canonical(compatible.encodeJSONObject(v));case "hook-data":actual=try json(hooked.encode(v));default:actual=try canonical(hooked.encodeJSONObject(v))}; rows.append(["scenario":name,"route":route,"category":category,"foundationObserved":foundationExpected,"expected":expected,"actual":actual,"passed":actual==expected])}catch{rows.append(["scenario":name,"route":route,"category":category,"foundationObserved":foundationExpected,"expected":expected,"error":String(describing:error),"passed":false])}}

 }
 for kind in 0..<3{for array in [false,true]{for generic in [false,true]{let values:[Any] = [7,true,1.25];let value = values[kind];let success:Any = array ? ["payload":[value]] : ["payload":["status":value]];try run("type-\(kind)-array-\(array)-generic-\(generic)",Wrapped(payload:PrimitiveRecovery(kind:kind,array:array,generic:generic)),success,generic)}}}
 try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
 print("rows=\(rows.count) mismatches=\(rows.filter{($0["passed"] as? Bool)==false}.count)")
 }
}
