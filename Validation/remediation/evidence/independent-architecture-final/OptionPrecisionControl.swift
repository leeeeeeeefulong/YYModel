import Foundation
import YYModelSwift
private struct Model: Decodable { let zero: Double; let max: UInt64; let min: Int64; let flag: Bool; let text: String }
@main private struct Main {
 static func main() throws {
  var rows: [[String: Any]]=[]
  func check(_ name: String, json: String, json5: Bool=false, assumed: Bool=false, reject: Bool=false) {
   var d=YYJSONDecoder.compatible(); d.numberParsingStrategy = .integerTokens; d.allowsJSON5=json5; d.assumesTopLevelDictionary=assumed
   do {
    let v=try d.decode(Model.self,from:Data(json.utf8))
    let passed = !reject && v.zero.bitPattern == 9223372036854775808 && v.max == UInt64.max && v.min == Int64.min && v.flag && v.text == "ref-0"
    rows.append(["scenario":name,"passed":passed,"zeroBits":String(v.zero.bitPattern),"max":String(v.max),"min":String(v.min),"flag":v.flag,"text":v.text])
   } catch { rows.append(["scenario":name,"passed":reject,"error":String(describing:error)]) }
  }
  let json5=#"{zero:-0,max:18446744073709551615,min:-9223372036854775808,flag:true,text:'ref-0',/*option control*/}"#
  check("strict-zero-precision-control",json:#"{"zero":-0,"max":18446744073709551615,"min":-9223372036854775808,"flag":true,"text":"ref-0"}"#)
  check("json5-zero-precision-control",json:json5,json5:true)
  check("json5-option-still-required",json:json5,reject:true)
  check("assumed-dictionary-zero-precision-control",json:#"zero:-0,max:18446744073709551615,min:-9223372036854775808,flag:true,text:'ref-0'"#,json5:true,assumed:true)
  try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
 }
}
