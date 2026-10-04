import Foundation

final class Ledger: @unchecked Sendable {
    let lock = NSLock()
    private var values: [String:Int] = [:]
    func add(_ key: String) { lock.lock(); defer {lock.unlock()}; values[key, default:0] += 1 }
    func count(_ key: String) -> Int { lock.lock(); defer {lock.unlock()}; return values[key, default:0] }
    static let shared = Ledger()
}
struct Profile: YYModelCodable {
    var id: UInt64
    var name: String
    var companyName: String
    var score: Decimal
    var age: Int?
    var created: Date
    var privateNote: String?
    static var yy_modelConfiguration: YYModelConfiguration<Self> {
        .init(mapper: ["id":["id","uid","meta.uid"], "companyName":"company.name", "created":"created_at"],
              blacklist:["privateNote"], requiredProperties:["id"],
              didTransform: { model, _ in model.name = model.name.trimmingCharacters(in:.whitespaces); return model.id > 0 })
    }
}
struct Family: YYModelCodable { var children:[Profile]; var byName:[String:Profile]; var favorite:Profile? }
struct Filtered: YYModelCodable {
    var visible:String; var hidden:String
    static var yy_modelConfiguration: YYModelConfiguration<Self> { .init(whitelist:["visible"]) }
}
struct EmptyWhitelist: YYModelCodable {
    var value:Int
    static var yy_modelConfiguration: YYModelConfiguration<Self> { .init(whitelist:[]) }
}
struct RequiredOptional: YYModelCodable {
    var age:Int?
    static var yy_modelConfiguration: YYModelConfiguration<Self> { .init(requiredProperties:["age"]) }
}
struct Defaulted: YYModelCodable {
    var id:Int; var title:String
    static var yy_modelConfiguration: YYModelConfiguration<Self> { .init(defaultValues:["id":7,"title":"fallback"]) }
}
struct Literal: YYModelCodable {
    var value:String
    static var yy_modelConfiguration: YYModelConfiguration<Self> { .init(mapper:["value":.key("a.b")]) }
}
struct Conflict: YYModelCodable {
    var a:String; var b:String
    static var yy_modelConfiguration: YYModelConfiguration<Self> { .init(mapper:["a":"node","b":"node.name"]) }
}
struct Hooked: YYModelCodable {
    var id:Int
    static var yy_modelConfiguration: YYModelConfiguration<Self> {
        .init(willTransform: { input in Ledger.shared.add("will"); return input["deny"] as? Bool == true ? nil : input },
              didTransform: { model,_ in Ledger.shared.add("from"); model.id += 1; return model.id > 1 },
              transformTo: { model, dict in Ledger.shared.add("to"); guard dict["id"] as? Int == model.id else {return false}; dict["checked"] = true; return true })
    }
}
struct BadExport: YYModelCodable {
    var id:Int
    static var yy_modelConfiguration: YYModelConfiguration<Self> { .init(transformTo: {_, dict in dict["bad"] = NSObject(); return true}) }
}
struct RejectExport: YYModelCodable {
    var id:Int
    static var yy_modelConfiguration: YYModelConfiguration<Self> { .init(transformTo: {_,_ in false}) }
}
struct Stamp: YYModelCodable { var created:Date }
struct MillisecondStamp: YYModelCodable {
    var created:Date
    static var yy_modelConfiguration: YYModelConfiguration<Self> { .init(dateStrategy:.millisecondsSince1970) }
}
struct SecondsStamp: YYModelCodable {
    var created:Date
    static var yy_modelConfiguration: YYModelConfiguration<Self> { .init(dateStrategy:.secondsSince1970) }
}
struct Renamed: YYModelCodable {
    var id:Int
    enum CodingKeys:String,CodingKey { case id = "identifier" }
    static var yy_modelConfiguration: YYModelConfiguration<Self> { .init(mapper:["identifier":"server_id"]) }
}
struct TextEvent: YYModelCodable {
    var body:String
    static var yy_modelConfiguration: YYModelConfiguration<Self> { .init(mapper:["body":"payload.body"]) }
}
struct CountEvent: YYModelCodable { var count:Int }
enum Event: YYModelPolymorphic {
    case text(TextEvent), count(CountEvent)
    static var yy_modelVariants: [String:YYModelVariant<Self>] {
        ["text":.init(TextEvent.self, create:Self.text, extract:{if case .text(let value) = $0 {return value}; return nil}),
         "count":.init(CountEvent.self, create:Self.count, extract:{if case .count(let value) = $0 {return value}; return nil})]
    }
}
enum ProtectedEvent: YYModelPolymorphic {
    case text(TextEvent)
    static var yy_modelVariants:[String:YYModelVariant<Self>] { ["text":.init(TextEvent.self,create:Self.text,extract:{if case .text(let value)=$0{return value};return nil})] }
    static var yy_modelConfiguration:YYModelConfiguration<Self> { .init(blacklist:["payload"]) }
}
enum EnumDatePolicy: YYModelPolymorphic {
    case stamp(Stamp)
    static var yy_modelVariants:[String:YYModelVariant<Self>] { ["stamp":.init(Stamp.self,create:Self.stamp,extract:{if case .stamp(let value)=$0{return value};return nil})] }
    static var yy_modelConfiguration:YYModelConfiguration<Self> { .init(dateStrategy:.millisecondsSince1970) }
}
struct Events: YYModelCodable { var events:[Event] }
struct InputChecked: YYModelCodable {
    var id:Int
    static var yy_modelConfiguration:YYModelConfiguration<Self> {
        .init(didTransform:{model,input in input["id"].map {String(describing:$0) == String(model.id)} ?? false})
    }
}
struct InputFamily: YYModelCodable {
    var values:[InputChecked]; var byName:[String:InputChecked]
    static var yy_modelConfiguration:YYModelConfiguration<Self> { .init(mapper:["values":"payload.values"]) }
}
struct HookFoundationDate: YYModelCodable {
    var created:Date
    static var yy_modelConfiguration:YYModelConfiguration<Self> { .init(didTransform:{model,input in (input["created"] as? Date) == model.created}) }
}
struct HookPrecision: YYModelCodable {
    var value:Decimal
    static var yy_modelConfiguration:YYModelConfiguration<Self> { .init(transformTo:{_,dictionary in dictionary["checked"]=true;return true}) }
}
struct Siblings: YYModelCodable {
    var name:String; var id:Int
    static var yy_modelConfiguration:YYModelConfiguration<Self> { .init(mapper:["name":"company.name","id":"company.id"]) }
}
struct FoundationModel: YYModelCodable { var blob:Data; var url:URL; var amount:Decimal }
struct DateArray: YYModelCodable {
    var dates:[Date?]
    static var yy_modelConfiguration:YYModelConfiguration<Self> { .init(dateStrategy:.millisecondsSince1970) }
}
struct AttemptArray: Codable {
    var values:[String]
    init(from decoder:Decoder) throws {
        var c = try decoder.unkeyedContainer(); var values:[String] = []
        while !c.isAtEnd {
            if let nested = try? c.nestedContainer(keyedBy:Key.self) {values.append(try nested.decode(String.self,forKey:.value))}
            else if var nested = try? c.nestedUnkeyedContainer() {values.append(try nested.decode(String.self))}
            else {values.append(try c.decode(String.self))}
        }
        self.values = values
    }
    func encode(to encoder:Encoder) throws {var c = encoder.unkeyedContainer();for value in values {try c.encode(value)}}
    enum Key:String,CodingKey {case value}
}
struct SingleInitialization: YYModelCodable {
    var id:Int; var name:String
    init(from decoder:Decoder) throws {
        Ledger.shared.add("init")
        let c = try decoder.container(keyedBy:Key.self)
        id = try c.decode(Int.self,forKey:.id); name = try c.decode(String.self,forKey:.name)
    }
    func encode(to encoder:Encoder) throws {var c=encoder.container(keyedBy:Key.self);try c.encode(id,forKey:.id);try c.encode(name,forKey:.name)}
    enum Key:String,CodingKey {case id,name}
}
struct NumberModel<T: Codable>: YYModelCodable { var value:T }

@main struct ModelContractRunner {
    static func main() throws {
        var checks:[String:Bool] = [:]
        let json = #"{"meta":{"uid":"18446744073709551615"},"name":"  Ada  ","company":{"name":"YY"},"score":"9007199254740993.125","age":"18","created_at":1700000000000,"privateNote":"secret"}"#
        let input = try JSONSerialization.jsonObject(with:Data(json.utf8)) as! [String:Any]
        let a = try Profile.yy_decode(withJSON:json)
        let b = try Profile.yy_decode(withJSON:Data(json.utf8))
        let c = Profile.yy_model(with:input)
        checks["StringDataObject"] = a.id == UInt64.max && b.id == a.id && c?.id == a.id
        checks["MapperKeyPath"] = a.companyName == "YY" && a.name == "Ada"
        checks["PrecisionAndCoercion"] = a.score == Decimal(string:"9007199254740993.125") && a.age == 18
        checks["BlacklistDecode"] = a.privateNote == nil
        let exported = try a.yy_encode()
        checks["NestedExport"] = (exported["company"] as? [String:Any])?["name"] as? String == "YY" && exported["company.name"] == nil
        checks["BlacklistEncode"] = exported["privateNote"] == nil
        checks["JSONObjectModelPrecision"] = Profile.yy_model(with:exported)?.score == a.score
        checks["JSONDataStringRoundtrip"] = a.yy_modelToJSONData().flatMap {Profile.yy_model(withJSON:$0)}?.id == a.id && a.yy_modelToJSONString().flatMap {Profile.yy_model(withJSON:$0)}?.created == a.created
        checks["AliasOrder"] = Profile.yy_model(with:input.merging(["id":"9","uid":"8"]) {_,v in v})?.id == 9
        checks["AliasNullStops"] = Profile.yy_model(with:input.merging(["id":NSNull(),"uid":"8"]) {_,v in v}) == nil
        checks["RequiredMissing"] = Profile.yy_model(with:input.filter {$0.key != "meta"}) == nil
        checks["RequiredOptional"] = RequiredOptional.yy_model(with:[:]) == nil && RequiredOptional.yy_model(with:["age":NSNull()]) == nil && RequiredOptional.yy_model(with:["age":"18"])?.age == 18
        checks["MalformedInteger"] = Profile.yy_model(with:input.merging(["id":"123abc"]) {_,v in v}) == nil
        checks["OutOfRangeInteger"] = Profile.yy_model(with:input.merging(["id":"18446744073709551616.0"]) {_,v in v}) == nil
        checks["NonObjectKeyPath"] = Profile.yy_model(with:input.merging(["company":7]) {_,v in v})?.companyName == ""
        let family = Family.yy_model(with:["children":[input,input],"byName":["a":input],"favorite":input])
        checks["NestedModels"] = family?.children.count == 2 && family?.byName["a"]?.id == UInt64.max && family?.favorite?.companyName == "YY"
        checks["NestedRejection"] = Family.yy_model(with:["children":[input, input.merging(["id":"0"]) {_,v in v}],"byName":[:]]) == nil
        checks["RootModelArray"] = Profile.yy_modelArray(withJSON:[input,input])?.count == 2
        let filtered = Filtered.yy_model(with:["visible":"yes","hidden":"secret"])
        checks["Whitelist"] = filtered?.hidden == "" && filtered?.yy_modelToJSONObject()?.count == 1
        checks["EmptyWhitelist"] = EmptyWhitelist.yy_model(with:["value":1]) == nil && EmptyWhitelist(value:1).yy_modelToJSONObject() == nil
        checks["Defaults"] = Defaulted.yy_model(with:[:])?.id == 7 && Defaulted.yy_model(with:[:])?.title == "fallback"
        checks["LiteralDottedKey"] = Literal.yy_model(with:["a.b":"literal"])?.value == "literal"
        checks["CodingKeysInteroperation"] = Renamed.yy_model(with:["server_id":11])?.id == 11 && Renamed(id:11).yy_modelToJSONObject()?["server_id"] as? Int == 11
        checks["ExportConflict"] = Conflict(a:"x",b:"y").yy_modelToJSONObject() == nil
        let beforeWill = Ledger.shared.count("will"), beforeFrom = Ledger.shared.count("from")
        let hooked = Hooked.yy_model(withJSON:#"{"id":"1"}"#)
        checks["HooksExactlyOnce"] = hooked?.id == 2 && Ledger.shared.count("will") == beforeWill+1 && Ledger.shared.count("from") == beforeFrom+1
        checks["WillRejection"] = Hooked.yy_model(with:["id":1,"deny":true]) == nil
        checks["FromRejection"] = Hooked.yy_model(with:["id":0]) == nil
        checks["ToAfterAutomaticFields"] = hooked?.yy_modelToJSONObject()?["checked"] as? Bool == true
        checks["InvalidToObject"] = BadExport(id:1).yy_modelToJSONObject() == nil
        checks["ToRejection"] = RejectExport(id:1).yy_modelToJSONObject() == nil
        checks["DateRoundtrip"] = a.created.timeIntervalSince1970 == 1700000000 && Stamp(created:a.created).yy_modelToJSONData().flatMap {Stamp.yy_model(withJSON:$0)}?.created == a.created
        checks["NegativeMillisDate"] = Stamp.yy_model(with:["created":"-1700000000000"])?.created.timeIntervalSince1970 == -1700000000
        checks["ExplicitMillisAmbiguous"] = MillisecondStamp.yy_model(with:["created":1000])?.created.timeIntervalSince1970 == 1
        checks["ExplicitSecondsHuge"] = SecondsStamp.yy_model(with:["created":1700000000000])?.created.timeIntervalSince1970 == 1700000000000
        let originalDates = ["2026-10-03T08:00:00", "2026-10-03T08:00:00.000", "2026-10-03T08:00:00Z", "2026-10-03T08:00:00+0000", "2026-10-03T08:00:00+00:00", "2026-10-03T08:00:00.000Z", "2026-10-03T08:00:00.000+0000", "2026-10-03T08:00:00.000+00:00", "Sat Oct 03 08:00:00 +0000 2026", "Sat Oct 03 08:00:00.000 +0000 2026"]
        checks["OriginalDateFormatParity"] = originalDates.allSatisfy {Stamp.yy_model(with:["created":$0])?.created.timeIntervalSince1970 == 1791014400}
        checks["ExtendedDate"] = Stamp.yy_model(with:["created":"Sat, 03 Oct 2026 08:00:00 +0000"])?.created.timeIntervalSince1970 == 1791014400
        checks["NonFiniteDate"] = Stamp.yy_model(with:["created":Double.infinity]) == nil && Stamp(created:Date(timeIntervalSince1970:.infinity)).yy_modelToJSONData() == nil
        let events = Events.yy_model(withJSON:#"{"events":[{"type":"text","payload":{"body":"hello"}},{"type":"count","count":"7"}]}"#)
        if let events, events.events.count == 2, case .text(let t) = events.events[0], case .count(let n) = events.events[1] { checks["PolymorphicNested"] = t.body == "hello" && n.count == 7 }
        else {checks["PolymorphicNested"] = false}
        checks["PolymorphicDatePolicyNotIgnored"] = EnumDatePolicy.yy_model(withJSON:#"{"type":"stamp","created":1000}"#) == nil
        checks["PolymorphicUnsupportedPolicyRejects"] = ProtectedEvent.text(TextEvent(body:"secret")).yy_modelToJSONObject() == nil
        checks["UnknownDiscriminator"] = Event.yy_model(withJSON:#"{"type":"missing"}"#) == nil
        checks["PolymorphicRoundtrip"] = events?.yy_modelToJSONData().flatMap {Events.yy_model(withJSON:$0)}?.events.count == 2
        checks["NullOptionalArrayOrder"] = NumberModel<[Int?]>.yy_model(with:["value":["1",NSNull(),"2"]])?.value == [1,nil,2]
        checks["NonFiniteFloat"] = NumberModel<Float>.yy_model(with:["value":Double.infinity]) == nil && NumberModel<Float>.yy_model(with:["value":1e39]) == nil
        checks["LegacyDecoderStillWorks"] = try YYJSONDecoder().decode([Int].self,from:Data(#"["1",2]"#.utf8)) == [1,2]
        let precise = Decimal(string:"0.12345678901234567890123456789012345678")!
        let preciseModel = HookPrecision(value:precise)
        let familyInput = InputFamily.yy_model(withJSON:#"{"payload":{"values":[{"id":"7"},{"id":8}]},"byName":{"one":{"id":9}}}"#)
        checks["NestedHookSourcePath"] = familyInput?.values.map(\.id) == [7,8] && familyInput?.byName["one"]?.id == 9
        let rawDate = Date(timeIntervalSince1970:1700000000)
        checks["FoundationDictionaryHookInput"] = HookFoundationDate.yy_model(with:["created":rawDate])?.created == rawDate
        checks["HookExportPrecision"] = preciseModel.yy_modelToJSONData().flatMap {HookPrecision.yy_model(withJSON:$0)}?.value == precise
        checks["JSONObjectPrecision"] = (preciseModel.yy_modelToJSONObject()?["value"] as? NSNumber)?.decimalValue == precise
        let siblings = Siblings(name:"YY",id:7)
        checks["SiblingPathsPreserved"] = siblings.yy_modelToJSONData().flatMap {Siblings.yy_model(withJSON:$0)}?.id == 7 && (siblings.yy_modelToJSONObject()?["company"] as? [String:Any])?.count == 2
        let foundation = FoundationModel(blob:Data([0,1,255]),url:URL(string:"https://example.org/a")!,amount:Decimal(string:"9007199254740993.125")!)
        let foundationRoundtrip = foundation.yy_modelToJSONData().flatMap {FoundationModel.yy_model(withJSON:$0)}
        checks["FoundationWireFormats"] = foundationRoundtrip?.blob == foundation.blob && foundationRoundtrip?.url == foundation.url && foundationRoundtrip?.amount == foundation.amount
        let dates = DateArray.yy_model(with:["dates":[1000,NSNull(),-1000]])
        checks["DateArrayPolicyInherited"] = dates?.dates[0]?.timeIntervalSince1970 == 1 && dates?.dates[2]?.timeIntervalSince1970 == -1 && dates?.yy_modelToJSONData().flatMap {DateArray.yy_model(withJSON:$0)}?.dates[0] == dates?.dates[0]
        let attempts = NumberModel<AttemptArray>.yy_model(withJSON:#"{"value":["first",{"value":"second"},["third"]]}"#)
        checks["FailedNestedContainerDoesNotConsume"] = attempts?.value.values == ["first","second","third"]
        let initBefore = Ledger.shared.count("init")
        checks["DirtyModelInitializedOnce"] = SingleInitialization.yy_model(withJSON:#"{"id":"1","name":2}"#)?.id == 1 && Ledger.shared.count("init") == initBefore+1
        do { _ = try NumberModel<[UInt8]>.yy_decode(withJSON:#"{"value":[1,"999"]}"#); checks["ThrowingErrorPath"] = false }
        catch DecodingError.typeMismatch(_,let context) {checks["ThrowingErrorPath"] = context.codingPath.map(\.stringValue) == ["value","Index 1"] || context.codingPath.map(\.stringValue) == ["value","1"]}
        catch {checks["ThrowingErrorPath"] = false}
        let failuresBefore = Ledger.shared.count("concurrentFailure")
        DispatchQueue.concurrentPerform(iterations:32) { _ in
            if Literal.yy_model(with:["a.b":"ok"])?.value != "ok" || Defaulted.yy_model(with:[:])?.id != 7 {Ledger.shared.add("concurrentFailure")}
        }
        checks["ConcurrentSchemasIndependent"] = Ledger.shared.count("concurrentFailure") == failuresBefore
        let result:[String:Any] = ["checks":checks,"profileJSON":exported,"profileJSONData":a.yy_modelToJSONString() as Any? ?? NSNull(),"preciseScore":(exported["score"] as? NSNumber)?.stringValue as Any? ?? NSNull(),"passed":checks.values.filter {$0}.count,"total":checks.count]
        try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
        print("Swift model contracts: \(checks.values.filter {$0}.count)/\(checks.count)")
    }
}
