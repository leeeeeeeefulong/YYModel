import Foundation

/// Associated-value enums register variants rather than handwriting Codable dispatch.
public protocol YYModelPolymorphic: YYModelCodable {
    static var yy_modelDiscriminator: YYModelKey { get }
    static var yy_modelVariants: [String: YYModelVariant<Self>] { get }
}
public struct YYModelVariant<Root> {
    let decode: (Decoder) throws -> Root
    let export: (Root) throws -> [String: Any]?
    public init<Member: YYModelCodable>(_ type: Member.Type, create: @escaping (Member) -> Root, extract: @escaping (Root) -> Member?) {
        decode = { try create(YYModelDecode.value(type, from: $0, date: .automatic)) }
        export = { root in guard let member = extract(root) else { return nil }; return try member.yy_encode() }
    }
}
public extension YYModelPolymorphic {
    static var yy_modelDiscriminator: YYModelKey { "type" }
    init(from decoder: Decoder) throws {
        let base = try decoder.container(keyedBy: YYModelCodingKey.self)
        let policy = YYModelPolicy(mapper: ["discriminator": Self.yy_modelDiscriminator])
        try policy.validate()
        let container = YYModelKeyedDecoder<YYModelCodingKey>(base: base, policy: policy)
        guard let field = container.field("discriminator") else { throw YYModelFailure.invalidObject("Missing model discriminator") }
        let name = try field.0.decode(String.self, forKey: field.1)
        guard let variant = YYModelSchemaCache.shared.variants(Self.self)[name] else { throw YYModelFailure.invalidObject("Unknown model discriminator: \(name)") }
        self = try variant.decode((decoder as? YYModelDecoder)?.base ?? decoder)
    }
    func encode(to encoder: Encoder) throws {
        try YYModelPolicy(mapper: ["discriminator": Self.yy_modelDiscriminator]).validate()
        var selection: (String, [String: Any])?
        let variants = YYModelSchemaCache.shared.variants(Self.self)
        for name in variants.keys.sorted() {
            if let object = try variants[name]?.export(self) {
                guard selection == nil else { throw YYModelFailure.invalidObject("Ambiguous model variant") }
                selection = (name, object)
            }
        }
        guard let (name, object) = selection, let path = Self.yy_modelDiscriminator.paths.first, !path.isEmpty, path.allSatisfy({ !$0.isEmpty }) else { throw YYModelFailure.invalidObject("No model variant or invalid discriminator") }
        func inserting(_ dictionary: [String: Any], _ path: ArraySlice<String>) throws -> [String: Any] {
            var result = dictionary; let key = path.first!
            if path.count == 1 {
                if let old = result[key], (old as? String) != name { throw YYModelFailure.invalidObject("Discriminator conflicts with payload") }
                result[key] = name
            } else {
                if let existing = result[key], !(existing is [String: Any]) { throw YYModelFailure.invalidObject("Discriminator path conflicts with payload") }
                result[key] = try inserting(result[key] as? [String: Any] ?? [:], path.dropFirst())
            }
            return result
        }
        try YYModelJSONValue(inserting(object, path[...] )).encode(to: (encoder as? YYModelEncoder)?.base ?? encoder)
    }
}
