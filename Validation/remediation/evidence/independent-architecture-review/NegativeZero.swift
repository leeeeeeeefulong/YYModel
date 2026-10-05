import Foundation
import YYModelSwift
@main struct Main {
static func main() throws {
 var d=YYJSONDecoder.compatible()
 for token in ["-0", "-0.0", "-0e0"] {
  let data=Data(token.utf8)
  let f=try JSONDecoder().decode(Double.self,from:data)
  for route in [YYJSONNumberParsingStrategy.foundation,.integerTokens] {
   d.numberParsingStrategy=route
   let v=try d.decode(Double.self,from:data)
   print("token=\(token) route=\(route) Foundation=\(f.bitPattern) actual=\(v.bitPattern)")
  }
 }
}}
