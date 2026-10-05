import Foundation
import YYModelSwift

struct DecimalModel: YYModelCodable { var value: Decimal }
struct BridgePayload: Codable { var value: Data }
struct FloatModel: Codable { var value: Float }
@main struct NumericE2E {
 static func main() throws {
  var rows: [[String: Any]] = []
  func check(_ id: String, _ name: String, expected: String, _ body: () throws -> String) {
   do { let actual = try body(); rows.append(["id":id,"scenario":name,"expected":expected,"actual":actual,"passed":actual == expected]) }
   catch { rows.append(["id":id,"scenario":name,"expected":expected,"actual":String(describing:error),"passed":false]) }
  }
  let literal = "1.000000000000000031251"
  check("P-03", "decimal-object-export", expected:literal) {
   let m = DecimalModel(value:Decimal(string:literal)!)
   return (try m.yy_encode()["value"] as! NSNumber).stringValue
  }
  check("P-03", "decimal-encoder-object", expected:literal) {
   let o = try YYJSONEncoder.compatible().encodeJSONObject(DecimalModel(value:Decimal(string:literal)!)) as! [String:Any]
   return (o["value"] as! NSNumber).stringValue
  }
  for hook in [false,true] {
   check("P-04", "bridge-decimal-hook-\(hook)", expected:literal) {
    let rules = try YYJSONRules().forType(BridgePayload.self) { if hook { $0.willTransform = { $0 } } }
    var d = YYJSONDecoder.compatible(rules:rules)
    d.dataDecodingStrategy = .custom { decoder in
     let value = try decoder.singleValueContainer().decode(Decimal.self)
     return Data(NSDecimalNumber(decimal:value).stringValue.utf8)
    }
    return String(decoding:try d.decode(BridgePayload.self,from:Data("{\"value\":\(literal)}".utf8)).value,as:UTF8.self)
   }
  }
  for text in ["1.0000000596046448", "1.000000059604644775390625000000000000000000000000000001", "-1.0000000596046448"] {
   let expected = String(Float(text)!.bitPattern)
   for hook in [false,true] {
    check("P-06", "float-\(text)-hook-\(hook)", expected:expected) {
     let r = try YYJSONRules().forType(FloatModel.self) { if hook { $0.willTransform = { $0 } } }
     let x = try YYJSONDecoder.compatible(rules:r).decode(FloatModel.self,from:Data("{\"value\":\(text)}".utf8))
     return String(x.value.bitPattern)
    }
   }
  }
  try JSONSerialization.data(withJSONObject:rows,options:[.sortedKeys,.prettyPrinted]).write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
 }
}
