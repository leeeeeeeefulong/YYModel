// Public optimized-library E2E scenarios. Foundation is the oracle for ordinary
// direct writes and retained super encoders. In single-recovery the four tree
// paths must return the successful fallback. Native/compatible Data are runtime
// Foundation controls, including known OS-specific partial-write retention.
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
@main struct RecoveryScenarioRows { static func main() throws {
 var rows:[[String:Any]]=[]
 func canonical(_ o:Any)throws->String {String(decoding:try JSONSerialization.data(withJSONObject:o,options:[.fragmentsAllowed,.sortedKeys]),as:UTF8.self)}
 func json(_ d:Data)throws->String {try canonical(JSONSerialization.jsonObject(with:d,options:.fragmentsAllowed))}
 func run<T:Encodable>(_ name:String,_ v:T)throws {let foundationExpected=try json(JSONEncoder().encode(v));let native=YYJSONEncoder.native();let compatible=YYJSONEncoder.compatible();let rules=try YYJSONRules().forType(T.self){$0.transformTo={_,_ in true}};let hooked=YYJSONEncoder.compatible(rules:rules)
 for route in ["native-data","native-object","compatible-data","compatible-object","hook-data","hook-object"] {
 let singleControl = name == "single-recovery" && (route == "native-data" || route == "compatible-data")
 let expected = name == "single-recovery" && !singleControl ? "{\"payload\":\"fallback\"}" : foundationExpected
 let category = singleControl ? "foundation-single-container-control" : "business-regression"
 do {let actual:String;switch route {case "native-data":actual=try json(native.encode(v));case "native-object":actual=try canonical(native.encodeJSONObject(v));case "compatible-data":actual=try json(compatible.encode(v));case "compatible-object":actual=try canonical(compatible.encodeJSONObject(v));case "hook-data":actual=try json(hooked.encode(v));default:actual=try canonical(hooked.encodeJSONObject(v))}; rows.append(["scenario":name,"route":route,"category":category,"foundationObserved":foundationExpected,"expected":expected,"actual":actual,"passed":actual==expected])}catch{rows.append(["scenario":name,"route":route,"category":category,"foundationObserved":foundationExpected,"expected":expected,"error":String(describing:error),"passed":false])}}

 }
 for partial in [false,true] {for previous in [false,true]{try run("key-partial-\(partial)-previous-\(previous)",KeyRecovery(partial:partial,previous:previous))};try run("array-partial-\(partial)",Wrapped(payload:ArrayRecovery(partial:partial)))}
 try run("single-recovery",Wrapped(payload:SingleRecovery()))
 try run("retained-super",LateSuper())
 try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
 print("rows=\(rows.count) mismatches=\(rows.filter{($0["passed"] as? Bool)==false}.count)")
 }
}
