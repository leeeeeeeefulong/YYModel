import Foundation

/// Optional convenience. External YYJSONRules also dispatch ordinary Codable enums/classes.
public protocol YYModelPolymorphic: YYModelCodable {
    static var yy_modelDiscriminator: YYModelKey { get }
    static var yy_modelVariants: [String: YYModelVariant<Self>] { get }
}
public struct YYModelVariant<Root> {
    let decode: (Decoder) throws -> Root
    let export: (Root, Encoder) throws -> [String: Any]?
    public init<Member: Codable>(_ type: Member.Type, create: @escaping (Member) -> Root, extract: @escaping (Root) -> Member?) {
        decode = { decoder in try create(YYModelDecode.value(type, from: decoder, date: YYJSONContext.from(decoder).defaults.date)) }
        export = { root, encoder in
            let context = YYJSONContext.from(encoder)
            guard let member = extract(root) else { return nil }
            let treeEncoder = context.exportTreeEncoder(at: encoder)
            try YYModelEncodingBox(value: member, date: context.defaults.date, skipHook: false).encode(to: treeEncoder)
            guard let object = treeEncoder.value.raw as? [String: Any] else { throw YYJSONRulesError.encoding(.exportNotObject, encoder.codingPath, "Variant payload must export an object") }
            return object
        }
    }
}

enum YYModelPolymorphism {
    static func decode<Root>(from input: Decoder, discriminator: YYModelKey, variants: [String: YYModelVariant<Root>]) throws -> Root {
        let decoder = (input as? YYModelDecoder)?.base ?? input
        let context = YYJSONContext.from(input)
        let policy = YYModelPolicy(mapper: ["discriminator": discriminator])
        let container = YYModelKeyedDecoder<YYModelCodingKey>(base: try decoder.container(keyedBy: YYModelCodingKey.self), policy: policy, context: context, userInfo: decoder.userInfo)
        // Foundation semantics: an absent discriminator is keyNotFound, a null one valueNotFound.
        guard let field = try container.field("discriminator") else {
            let path: [String] = discriminator.paths.first ?? ["type"]
            let parents: [CodingKey] = path.dropLast().map { YYModelCodingKey($0) }
            throw DecodingError.keyNotFound(YYModelCodingKey(path.last ?? "type"),
                                            .init(codingPath: decoder.codingPath + parents, debugDescription: "Missing model discriminator"))
        }
        guard try !field.0.decodeNil(forKey: field.1) else {
            throw DecodingError.valueNotFound(String.self, .init(codingPath: field.0.codingPath + [field.1], debugDescription: "Missing model discriminator (null)"))
        }
        if let raw = (try? field.0.superDecoder(forKey: field.1)) as? _YYDecoder {
            guard raw.value is String else {
                throw DecodingError.typeMismatch(String.self, .init(codingPath: decoder.codingPath + [field.1], debugDescription: "Expected String for model discriminator"))
            }
        }
        let name = try field.0.decode(String.self, forKey: field.1)
        guard let variant = variants[name] else { throw DecodingError.yy_corrupted(field.0.codingPath + [field.1], "Unknown model discriminator: \(name)") }
        return try variant.decode(decoder)
    }
    static func encode<Root>(_ value: Root, to input: Encoder, discriminator: YYModelKey, variants: [String: YYModelVariant<Root>]) throws {
        let encoder = (input as? YYModelEncoder)?.base ?? input
        let context = YYJSONContext.from(input)
        var selection: (String, [String: Any])?
        for name in variants.keys.sorted() {
            if let object = try variants[name]?.export(value, encoder) {
                guard selection == nil else { throw YYJSONRulesError.encoding(.ambiguousVariant, encoder.codingPath, "Ambiguous model variant") }
                selection = (name, object)
            }
        }
        guard let (name, object) = selection, let path = discriminator.paths.first, !path.isEmpty, path.allSatisfy({ !$0.isEmpty }) else { throw YYJSONRulesError.encoding(.noMatchingVariant, encoder.codingPath, "No model variant or invalid discriminator") }
        let metadata = YYModelDiscriminatorOutput(path: path, name: name)
        let treeEncoder = context.exportTreeEncoder(at: encoder)
        try metadata.encode(to: treeEncoder)
        guard let discriminatorObject = treeEncoder.value.raw as? [String: Any] else { throw YYJSONRulesError.encoding(.discriminatorConflict, encoder.codingPath, "Invalid discriminator object") }
        func merging(_ payload: [String: Any], _ metadata: [String: Any]) throws -> [String: Any] {
            var result = payload
            for (key, value) in metadata {
                if let nested = value as? [String: Any] {
                    if let old = result[key], !(old is [String: Any]) { throw YYJSONRulesError.encoding(.discriminatorConflict, encoder.codingPath, "Discriminator path conflicts with payload") }
                    result[key] = try merging(result[key] as? [String: Any] ?? [:], nested)
                } else {
                    if let old = result[key], (old as? String) != (value as? String) { throw YYJSONRulesError.encoding(.discriminatorConflict, encoder.codingPath, "Discriminator conflicts with payload") }
                    result[key] = value
                }
            }
            return result
        }
        try yy_encodingJSONValue(at: encoder.codingPath) { try YYModelJSONValue(merging(object, discriminatorObject)) }.encode(to: encoder)
    }
}
public extension YYModelPolymorphic {
    static var yy_modelDiscriminator: YYModelKey { "type" }
    init(from decoder: Decoder) throws {
        try YYModelPolicy(mapper: ["discriminator": Self.yy_modelDiscriminator]).validate(for: Self.self)
        self = try YYModelPolymorphism.decode(from: decoder, discriminator: Self.yy_modelDiscriminator, variants: Self.yy_modelVariants)
    }
    func encode(to encoder: Encoder) throws {
        try YYModelPolicy(mapper: ["discriminator": Self.yy_modelDiscriminator]).validate(for: Self.self)
        try YYModelPolymorphism.encode(self, to: encoder, discriminator: Self.yy_modelDiscriminator, variants: Self.yy_modelVariants)
    }
}

private struct YYModelDiscriminatorOutput: Encodable {
    let path: [String]
    let name: String
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: YYModelCodingKey.self)
        for component in path.dropLast() { container = container.nestedContainer(keyedBy: YYModelCodingKey.self, forKey: YYModelCodingKey(component)) }
        try container.encode(name, forKey: YYModelCodingKey(path.last!))
    }
}
