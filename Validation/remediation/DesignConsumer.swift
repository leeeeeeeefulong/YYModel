import Foundation
import YYModelSwift
struct Money: Codable { let value: Decimal }
struct ID: Codable { let value: Int64 }
struct Dotted: Codable {
 let value: Int
 enum CodingKeys: String, CodingKey { case value = "v.dot" }
}
final class Reference: Codable { let value: Int }
struct WithComputed: Codable {
 let backing: Int
 var value: Int { backing }
 enum CodingKeys: String, CodingKey { case value }
 init(from decoder: Decoder) throws { backing = try decoder.container(keyedBy: CodingKeys.self).decode(Int.self,forKey:.value) }
 func encode(to encoder: Encoder) throws { var c = encoder.container(keyedBy:CodingKeys.self); try c.encode(backing,forKey:.value) }
}
struct DateDefault: Codable { let value: Date }
enum Kind: String, Codable { case yes }
struct EnumDefault: Codable { let value: Kind }
struct Child: Codable { let n: Int }
struct ObjectDefault: Codable { let value: Child }
@main struct Probe {
 static func main() throws {
  var rows:[[String:Any]]=[]
  func observe(_ name:String,_ body:() throws->Any) {
   do { rows.append(["name":name,"result":try body()]) }
   catch { rows.append(errorRow(name,error)) }
  }
  let plain=YYJSONDecoder(mode:.compatible)
  let hook=try YYJSONRules().forType(Money.self) { $0.willTransform = { $0 } }
  for token in ["12345678901234567890.123456789012345678","9007199254740993.125","0.123456789012345678","0.9999999999999999"] {
   let data=Data("{\"value\":\(token)}".utf8)
   observe("decimal-plain-"+token) { NSDecimalNumber(decimal:try plain.decode(Money.self,from:data).value).stringValue }
   observe("decimal-will-"+token) { NSDecimalNumber(decimal:try YYJSONDecoder(mode:.compatible,rules:hook).decode(Money.self,from:data).value).stringValue }
  }
  let idHook=try YYJSONRules().forType(ID.self) { $0.willTransform = { $0 } }
  for token in ["-9223372036854775809.0","-9.223372036854775809e18"] {
   let data=Data("{\"value\":\(token)}".utf8)
   observe("overflow-plain-"+token) { String(try plain.decode(ID.self,from:data).value) }
   observe("overflow-will-"+token) { String(try YYJSONDecoder(mode:.compatible,rules:idHook).decode(ID.self,from:data).value) }
  }
  observe("dotted-mapper") {
   let rules=try YYJSONRules().forType(Dotted.self) { $0.mapper=["v.dot":.key("input")] }
   return try YYJSONDecoder(mode:.compatible,rules:rules).decode(Dotted.self,from:Data("{\"input\":7}".utf8)).value
  }
  observe("dotted-default") {
   let rules=try YYJSONRules().forType(Dotted.self) { $0.defaultValues=["v.dot":7] }
   return try YYJSONDecoder(mode:.compatible,rules:rules).decode(Dotted.self,from:Data("{}".utf8)).value
  }
  observe("dotted-required") {
   let rules=try YYJSONRules().forType(Dotted.self) { $0.requiredProperties=["v.dot"] }
   return try YYJSONDecoder(mode:.compatible,rules:rules).decode(Dotted.self,from:Data("{\"v.dot\":7}".utf8)).value
  }
#if KEY_PATH
  observe("keypath-class-name") { YYModelConfiguration<Reference>.propertyName(\Reference.value) }
  observe("keypath-class-map") {
   let rules=try YYJSONRules().forType(Reference.self) { $0.map(\.value,from:"input") }
   return try YYJSONDecoder(mode:.compatible,rules:rules).decode(Reference.self,from:Data("{\"input\":7}".utf8)).value
  }
  observe("keypath-class-map-legacy") {
   let rules=try YYJSONRules().forType(Reference.self) { $0.map(\.value,from:"input") }
   return try YYJSONDecoder(mode:.legacy,rules:rules).decode(Reference.self,from:Data("{\"input\":7}".utf8)).value
  }
  observe("keypath-class-string-control") {
   let rules=try YYJSONRules().forType(Reference.self) { $0.mapper=["value":.key("input")] }
   return try YYJSONDecoder(mode:.compatible,rules:rules).decode(Reference.self,from:Data("{\"input\":7}".utf8)).value
  }
  observe("keypath-computed-name") { YYModelConfiguration<WithComputed>.propertyName(\WithComputed.value) }
  observe("keypath-computed-map") {
   let rules=try YYJSONRules().forType(WithComputed.self) { $0.map(\.value,from:"input") }
   return try YYJSONDecoder(mode:.compatible,rules:rules).decode(WithComputed.self,from:Data("{\"input\":7}".utf8)).value
  }
  observe("keypath-date-default") {
   let rules=try YYJSONRules().forType(DateDefault.self) { $0.default(\.value,to:Date(timeIntervalSince1970:7)) }
   return try YYJSONDecoder(mode:.compatible,rules:rules).decode(DateDefault.self,from:Data("{}".utf8)).value.timeIntervalSince1970
  }
  observe("keypath-enum-default") {
   let rules=try YYJSONRules().forType(EnumDefault.self) { $0.default(\.value,to:.yes) }
   return try YYJSONDecoder(mode:.compatible,rules:rules).decode(EnumDefault.self,from:Data("{}".utf8)).value.rawValue
  }
  observe("keypath-object-default") {
   let rules=try YYJSONRules().forType(ObjectDefault.self) { $0.default(\.value,to:Child(n:7)) }
   return try YYJSONDecoder(mode:.compatible,rules:rules).decode(ObjectDefault.self,from:Data("{}".utf8)).value.n
  }
#endif
  let data=try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys])
  try data.write(to:URL(fileURLWithPath:CommandLine.arguments[1])); print(String(decoding:data,as:UTF8.self))
 }
}

/// Structured error fields (C12): consumers emit errorType / errorPath (Foundation codingPath
/// semantics) and errorKey for keyNotFound, so run.py can assert them in the expectations.
func errorRow(_ name: String, _ error: Error) -> [String: Any] {
    var row: [String: Any] = ["name": name, "error": String(describing: error)]
    func put(_ type: String, _ context: DecodingError.Context) {
        row["errorType"] = type; row["errorPath"] = context.codingPath.map(\.stringValue)
    }
    switch error {
    case DecodingError.keyNotFound(let key, let context): put("keyNotFound", context); row["errorKey"] = key.stringValue
    case DecodingError.valueNotFound(_, let context): put("valueNotFound", context)
    case DecodingError.typeMismatch(_, let context): put("typeMismatch", context)
    case DecodingError.dataCorrupted(let context): put("dataCorrupted", context)
    case let rules as YYJSONRulesError:
        row["errorType"] = "YYJSONRulesError." + rules.code.rawValue
        if case .encodingRejected(_, let path, _) = rules { row["errorPath"] = path }
    default: row["errorType"] = String(describing: type(of: error))
    }
    return row
}