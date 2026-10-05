import Foundation
import YYModelSwift
struct Payload: Codable { let value: Int64 }
func compileOnly(_ data: Data) throws {
    var decoder = YYJSONDecoder.compatible()
    decoder.numberParsingStrategy = .integerTokens
    decoder.userInfo[YYModelCoercionReport.key] = YYModelCoercionReport()
    let value = try decoder.decode(Payload.self, from: data)
    var encoder = YYJSONEncoder.compatible()
    let rules = try YYJSONRules().forType(Date.self) { $0.dateStrategy = .microsecondsSince1970 }
    encoder = YYJSONEncoder.compatible(rules: rules)
    _ = try encoder.encodeJSONObject(value)
    _ = YYModelCapability.foundationExactDecimal
}
