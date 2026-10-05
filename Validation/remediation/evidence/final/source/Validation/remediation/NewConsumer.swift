import Foundation
import YYModelSwift

enum Kind: String, Codable { case ready }
struct EnumValue: Codable { var value: Kind }
struct OptionalEnum: Codable { var value: Kind? }
struct Child: Codable { var value: Int }
struct OptionalChild: Codable { var value: Child? }
struct DateValue: Codable { var value: Date }
struct OptionalDate: Codable { var value: Date? }
struct Parent: Codable { var child: Child }
struct FallbackDirect: Decodable { var value: Int }
struct FallbackContains: Decodable {
    var value: Int
    enum K: String, CodingKey { case value }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        value = c.contains(.value) ? try c.decode(Int.self, forKey: .value) : -1
    }
}
struct FallbackNil: Decodable {
    var value: Int
    enum K: String, CodingKey { case value }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        value = try c.decodeNil(forKey: .value) ? -1 : c.decode(Int.self, forKey: .value)
    }
}
struct Group: Codable { var child: Child; var items: [Child] }
struct NestedGroup: Codable { var group: Group }
struct NumberKey: Codable, Hashable, CodingKeyRepresentable {
    var id: Int
    struct Key: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue; intValue = Int(stringValue) }
        init?(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
    }
    var codingKey: any CodingKey { Key(intValue: id)! }
    init?<K: CodingKey>(codingKey: K) {
        guard let id = codingKey.intValue else { return nil }
        self.id = id
    }
}
struct DictionaryValue: Codable { var value: [NumberKey: Int] }
struct Config: Sendable { var unit: String }
struct Reading: Codable, DecodableWithConfiguration, EncodableWithConfiguration {
    typealias DecodingConfiguration = Config
    typealias EncodingConfiguration = Config
    var value: Int
    var unit: String
    enum K: String, CodingKey { case value, unit }
    init(value: Int, unit: String) { self.value = value; self.unit = unit }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        value = try c.decode(Int.self, forKey: .value); unit = "plain"
    }
    init(from decoder: Decoder, configuration: Config) throws {
        let c = try decoder.container(keyedBy: K.self)
        value = try c.decode(Int.self, forKey: .value); unit = configuration.unit
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self); try c.encode(value, forKey: .value)
    }
    func encode(to encoder: Encoder, configuration: Config) throws {
        var c = encoder.container(keyedBy: K.self); try c.encode(value, forKey: .value)
        try c.encode(configuration.unit, forKey: .unit)
    }
}

struct SpellingKey: Codable, Hashable, CodingKeyRepresentable {
 var text: String
 var codingKey: any CodingKey { K(stringValue: text)! }
 struct K: CodingKey { var stringValue: String; var intValue: Int?; init?(stringValue: String) {self.stringValue=stringValue;intValue=Int(stringValue)}; init?(intValue: Int) {self.stringValue=String(intValue);self.intValue=intValue} }
 init?<K: CodingKey>(codingKey: K) {text=codingKey.stringValue}
}
struct Keys: Codable { var values: [SpellingKey:Int] }
struct OnlyConfiguration: EncodableWithConfiguration {
 typealias EncodingConfiguration = Int
 func encode(to encoder: Encoder, configuration: Int) throws {var c=encoder.container(keyedBy: K.self);try c.encode(configuration,forKey:.value)}
 enum K: String,CodingKey {case value}
}
struct ConfigDate: EncodableWithConfiguration, DecodableWithConfiguration {
 typealias EncodingConfiguration = Int; typealias DecodingConfiguration = Int
 var value: Date
 init(value: Date) {self.value=value}
 enum K: String,CodingKey {case value}
 init(from decoder: Decoder, configuration: Int) throws {value=try decoder.container(keyedBy:K.self).decode(Date.self,forKey:.value)}
 func encode(to encoder: Encoder, configuration: Int) throws {var c=encoder.container(keyedBy:K.self);try c.encode(value,forKey:.value)}
}
struct NoJSON: Codable {
 var value:Int
 init(value:Int){self.value=value}
 init(from decoder:Decoder)throws {value=try decoder.singleValueContainer().decode(Int.self)}
 func encode(to encoder:Encoder)throws {throw NSError(domain:"no JSON representation",code:1)}
}
struct NoJSONHolder: Codable {var item:NoJSON}
struct OptionalInt:Codable {var value:Int?}
struct Fraction:Codable {var value:Double}
@main struct NewConsumer {
 static func main() throws {
 var rows:[[String:Any]]=[]
 func observe(_ n:String,_ f:()throws->Any){do{rows.append(["name":n,"result":try f()])}catch{rows.append(["name":n,"error":String(describing:error)])}}
 let config=Config(unit:"configured")
 for token in ["{}",#"{"value":"7"}"#] {
 let data=Data(token.utf8)
 observe("foundation-config-"+token){try JSONDecoder().decode(Reading.self,from:data,configuration:config).value}
 observe("yy-native-config-"+token){try YYJSONDecoder(mode:.native).decode(Reading.self,from:data,configuration:config).value}
 }
 let date=ConfigDate(value:Date(timeIntervalSince1970:7))
 observe("foundation-date-encode"){String(decoding:try JSONEncoder().encode(date,configuration:0),as:UTF8.self)}
 observe("yy-native-date-encode"){String(decoding:try YYJSONEncoder(mode:.native).encode(date,configuration:0),as:UTF8.self)}
 observe("foundation-date-decode"){try JSONDecoder().decode(ConfigDate.self,from:Data(#"{"value":0}"#.utf8),configuration:0).value.timeIntervalSince1970}
 observe("yy-native-date-decode"){try YYJSONDecoder(mode:.native).decode(ConfigDate.self,from:Data(#"{"value":0}"#.utf8),configuration:0).value.timeIntervalSince1970}
 for hooked in [false,true] {
 let only=try YYJSONRules().forType(OnlyConfiguration.self){if hooked {$0.transformTo={_,_ in true}}}
 observe("only-config-export-hook=\(hooked)"){String(decoding:try YYJSONEncoder(mode:.compatible,rules:only).encode(OnlyConfiguration(),configuration:7),as:UTF8.self)}
 let dual=try YYJSONRules().forType(Reading.self){$0.mapper=["value":.key("v")];if hooked{$0.transformTo={_,_ in true}}}
 observe("dual-config-export-hook=\(hooked)"){String(decoding:try YYJSONEncoder(mode:.compatible,rules:dual).encode(Reading(value:7,unit:"ignored"),configuration:config),as:UTF8.self)}
 }
 let keys=Data(#"{"values":{"01":1,"1":2}}"#.utf8)
 observe("literal-key-foundation"){try JSONDecoder().decode(Keys.self,from:keys).values.map{[$0.key.text:String($0.value)]}.sorted{String(describing:$0)<String(describing:$1)}}
 observe("literal-key-yy"){try YYJSONDecoder(mode:.compatible).decode(Keys.self,from:keys).values.map{[$0.key.text:String($0.value)]}.sorted{String(describing:$0)<String(describing:$1)}}
 observe("typed-default-without-json"){
 let rules=try YYJSONRules().forType(NoJSONHolder.self){$0.default(\.item,to:NoJSON(value:7))}
 return try YYJSONDecoder(mode:.compatible,rules:rules).decode(NoJSONHolder.self,from:Data("{}".utf8)).item.value
 }
 observe("typed-default-overwrite-nil"){
 let rules=try YYJSONRules().forType(OptionalInt.self){$0.default(\.value,to:7);$0.default(\.value,to:nil)}
 return try YYJSONDecoder(mode:.compatible,rules:rules).decode(OptionalInt.self,from:Data("{}".utf8)).value.map(String.init) ?? "nil"
 }
 let fallback=try YYJSONRules().forType(FallbackDirect.self){$0.fallback(\.value,to:7)}.forType(FallbackNil.self){$0.fallback(\.value,to:7)}
 observe("fallback-null-direct"){try YYJSONDecoder(mode:.compatible,rules:fallback).decode(FallbackDirect.self,from:Data(#"{"value":null}"#.utf8)).value}
 observe("fallback-null-query"){try YYJSONDecoder(mode:.compatible,rules:fallback).decode(FallbackNil.self,from:Data(#"{"value":null}"#.utf8)).value}
 let rules=try YYJSONRules().forType(Fraction.self){$0.willTransform={$0}}
 for t in ["1.00000000000000011102230246251565404236316680908203125","1.000000000000000111022302462515654042363166809082031251"] {
 let d=Data("{\"value\":\(t)}".utf8)
 observe("double-plain-"+t){String(try YYJSONDecoder(mode:.compatible).decode(Fraction.self,from:d).value.bitPattern)}
 observe("double-hook-"+t){String(try YYJSONDecoder(mode:.compatible,rules:rules).decode(Fraction.self,from:d).value.bitPattern)}
 }
 try JSONSerialization.data(withJSONObject:rows,options:[.sortedKeys,.prettyPrinted]).write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
 }
}
