import Foundation
import YYModelSwift
struct K: CodingKey { let stringValue:String; let intValue:Int?; init(_ s:String,_ i:Int?=nil){stringValue=s;intValue=i};init?(stringValue:String){self.init(stringValue)};init?(intValue:Int){self.init(String(intValue),intValue)} }
struct RepeatedObject: Encodable {func encode(to e:Encoder)throws { var root=e.container(keyedBy:K.self);var a=root.nestedContainer(keyedBy:K.self,forKey:K("payload"));try a.encode(1,forKey:K("first"));var b=root.nestedContainer(keyedBy:K.self,forKey:K("payload"));try b.encode(2,forKey:K("second"))}}
struct RepeatedArray: Encodable {func encode(to e:Encoder)throws { var root=e.container(keyedBy:K.self);var a=root.nestedUnkeyedContainer(forKey:K("payload"));try a.encode(1);var b=root.nestedUnkeyedContainer(forKey:K("payload"));try b.encode(2)}}
struct SuperValue: Encodable {func encode(to e:Encoder)throws {var root=e.container(keyedBy:K.self);var c=root.superEncoder().container(keyedBy:K.self);try c.encode(3,forKey:K("baseValue"))}}
struct Named: Encodable {let name:String;func encode(to e:Encoder)throws{var c=e.container(keyedBy:K.self);try c.encode(1,forKey:K(name))}}
struct DK: Hashable,Codable,CodingKeyRepresentable { let id:Int;var codingKey:any CodingKey{K("key"+String(id),id)};init(_ id:Int){self.id=id};init?<T:CodingKey>(codingKey:T){guard let id=codingKey.intValue else{return nil};self.id=id}}
struct TrueCollision: Encodable {func encode(to e:Encoder)throws {var c=e.container(keyedBy:K.self);try c.encode(1,forKey:K("first"));try c.encode(2,forKey:K("second"))}}
@main struct RepeatedEncodingE2E {static func main() throws {
var rows:[[String:Any]]=[]
func json(_ d:Data)throws->String{try json(JSONSerialization.jsonObject(with:d,options:.fragmentsAllowed))}
func json(_ o:Any)throws->String{String(decoding:try JSONSerialization.data(withJSONObject:o,options:[.sortedKeys,.fragmentsAllowed]),as:UTF8.self)}
func check<T:Encodable>(_ name:String,_ value:T,rules:YYJSONRules,expected:String,expectReject:Bool=false){
let y=YYJSONEncoder.compatible(rules:rules)
for object in [false,true] {let route=object ? "JSONObject":"Data";do{let result=try object ? json(y.encodeJSONObject(value)):json(y.encode(value));rows.append(["scenario":name+"-"+route,"expected":expectReject ? "rejected":expected,"actual":result,"passed":!expectReject && result==expected])}catch{rows.append(["scenario":name+"-"+route,"expected":expectReject ? "rejected":expected,"actual":"rejected","error":String(describing:error),"passed":expectReject])}}
}
let native=JSONEncoder()
try check("same-key-no-mapper",RepeatedObject(),rules:.init(),expected:json(native.encode(RepeatedObject())))
try check("same-array-no-mapper",RepeatedArray(),rules:.init(),expected:json(native.encode(RepeatedArray())))
let mappedObject=try YYJSONRules().forType(RepeatedObject.self){$0.mapper=["payload":"envelope"]}
let mappedArray=try YYJSONRules().forType(RepeatedArray.self){$0.mapper=["payload":"envelope"]}
let expectedObject=try json(native.encode(RepeatedObject())).replacingOccurrences(of:"payload",with:"envelope")
let expectedArray=try json(native.encode(RepeatedArray())).replacingOccurrences(of:"payload",with:"envelope")
check("same-key-mapped",RepeatedObject(),rules:mappedObject,expected:expectedObject)
check("same-array-mapped",RepeatedArray(),rules:mappedArray,expected:expectedArray)
let collisions=try YYJSONRules().forType(TrueCollision.self){$0.mapper=["first":"envelope","second":"envelope"]}
check("distinct-fields-collide",TrueCollision(),rules:collisions,expected:"",expectReject:true)
try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[1]));print(rows)
}}
