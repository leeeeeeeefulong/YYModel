import Foundation

struct YYModelDecodingBox<T: Decodable>: Decodable {
    let value: T
    init(from decoder: Decoder) throws { value = try YYModelDecode.value(T.self, from: decoder, date: YYJSONContext.from(decoder).defaults.date) }
}

// R2: the DecodableWithConfiguration entry runs T's OWN rule flow — policy
// (mapper/required), will/finish hooks — exactly like the ordinary entry, and only
// the final construction goes through init(from:configuration:). Without this, the
// context would resolve rules for the BOX (none) and silently drop T's rules.
//
// Native configuration entries carry no YY rules or model hooks: the decoder
// holds no YYJSONContext, so bypass the legacy adapter and decode directly.
// Otherwise a missing native context would fabricate `.legacy` defaults
// (zero-fill, string coercion, automatic dates) and corrupt the result.
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
enum YYModelConfigurationDecode {
    @discardableResult
    static func value<T: DecodableWithConfiguration>(_ type: T.Type, from input: Decoder,
                                                     date: YYModelDateStrategy,
                                                     configuration: T.DecodingConfiguration) throws -> T {
        guard input.userInfo[YYJSONContext.key] != nil else {
            return try T(from: input, configuration: configuration)
        }
        let decoder = (input as? YYModelDecoder)?.base ?? input
        let context = YYJSONContext.from(input)
        var defaults = context.defaults; defaults.date = date
        let rule = try context.rule(type)
        let policy = rule?.resolved(defaults: defaults) ?? defaults
        var source = decoder
        var object: [String: Any]?
        if let rule, rule.needsInput {
            guard let dictionary = try YYModelJSONInput.object(from: decoder) as? [String: Any] else {
                throw DecodingError.typeMismatch([String: Any].self, .init(codingPath: decoder.codingPath, debugDescription: "Expected an object for a model with dictionary hooks"))
            }
            object = dictionary
            if let hook = rule.will {
                guard let transformed = try hook(dictionary) else { throw DecodingError.yy_corrupted(decoder.codingPath, "willTransform rejected model") }
                object = transformed
                source = context.rawDecoder(transformed, path: decoder.codingPath, userInfo: decoder.userInfo)
            }
        }
        let adapter = YYModelDecoder(base: source, policy: policy)
        if !policy.required.isEmpty { try adapter.validateRequired() }
        let result = try T(from: adapter, configuration: configuration)
        if let finish = rule?.finish {
            guard let value = try finish(result, object, decoder.codingPath) as? T else { throw DecodingError.yy_corrupted(decoder.codingPath, "Unexpected transformed type") }
            return value
        }
        return result
    }
}

// Native scalar collections have no user model hooks; a failed attempt is safe to retry by field.
protocol YYModelNativeCollection {
    static var nativeCompatible: Bool { get }
    func validateScalars(at path: [CodingKey]) throws
}
extension Optional: YYModelNativeCollection {
    static var nativeCompatible: Bool { YYModelDecode.isNativeValue(Wrapped.self) }
    func validateScalars(at path: [CodingKey]) throws { if let value = self { _ = try YYModelDecode.validateScalar(value, path: path) } }
}
extension Array: YYModelNativeCollection {
    static var nativeCompatible: Bool { YYModelDecode.isNativeValue(Element.self) }
    func validateScalars(at path: [CodingKey]) throws {
        for (index, value) in enumerated() { _ = try YYModelDecode.validateScalar(value, path: path + [YYModelCodingKey(intValue: index)]) }
    }
}
extension Set: YYModelNativeCollection {
    static var nativeCompatible: Bool { YYModelDecode.isNativeValue(Element.self) }
    func validateScalars(at path: [CodingKey]) throws {
        for value in self { _ = try YYModelDecode.validateScalar(value, path: path) }
    }
}
extension Dictionary: YYModelNativeCollection {
    static var nativeCompatible: Bool { Key.self == String.self && YYModelDecode.isNativeValue(Value.self) }
    func validateScalars(at path: [CodingKey]) throws {
        for (key, value) in self { _ = try YYModelDecode.validateScalar(value, path: path + [YYModelCodingKey(String(describing: key))]) }
    }
}
enum YYModelDecode {
    static func isInteger<T>(_ type: T.Type) -> Bool {
        type == Int.self || type == Int8.self || type == Int16.self || type == Int32.self || type == Int64.self ||
        type == UInt.self || type == UInt8.self || type == UInt16.self || type == UInt32.self || type == UInt64.self
    }
    static func isNativeValue<T>(_ type: T.Type) -> Bool {
        if type == Date.self || type == Data.self || isInteger(type) { return false }
        return YYJSONValueDecoder.isLeaf(type) || (type as? YYModelNativeCollection.Type)?.nativeCompatible == true
    }
    /// `path` 是 `@autoclosure`：它只在**真正需要**时求值 ——
    /// 即值为非有限数（抛错）或值为集合（递归校验）时。
    ///
    /// 这一点很关键。调用方写的是 `validateScalar(result, path: codingPath + [key])`，
    /// 若参数是普通 `[CodingKey]`，那么**每个标量字段**都会急切构造一次数组 ——
    /// 而 String / Bool / Int 这些最常见的情况根本用不到它。
    /// 改成 autoclosure 后，热路径上的数组分配被完全消除。
    static func validateScalar<T>(_ result: T, path: @autoclosure () -> [CodingKey]) throws -> T {
        if T.self == Double.self, !(result as! Double).isFinite { throw DecodingError.dataCorrupted(.init(codingPath: path(), debugDescription: "Non-finite Double")) }
        if T.self == Float.self, !(result as! Float).isFinite { throw DecodingError.dataCorrupted(.init(codingPath: path(), debugDescription: "Non-finite Float")) }
        if T.self == CGFloat.self, !(result as! CGFloat).isFinite { throw DecodingError.dataCorrupted(.init(codingPath: path(), debugDescription: "Non-finite CGFloat")) }
        if T.self == Decimal.self, (result as! Decimal).isNaN { throw DecodingError.dataCorrupted(.init(codingPath: path(), debugDescription: "Non-finite Decimal")) }
        if let collection = result as? YYModelNativeCollection { try collection.validateScalars(at: path()) }
        return result
    }
    // This path has no model policy/hooks. Integer tokens still pass through Decimal;
    // accepting a small native integer can silently round a long fractional token up.
    static func scalar<T: Decodable>(_ type: T.Type, from decoder: Decoder) throws -> T {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            if let optional = type as? ExpressibleByNilLiteral.Type { return optional.init(nilLiteral: ()) as! T }
            if YYJSONContext.from(decoder).defaults.missing == .zeroFill, let zero = YYJSONValueDecoder.zero(type) { return zero }
            throw DecodingError.valueNotFound(type, .init(codingPath: decoder.codingPath, debugDescription: "Null scalar"))
        }
        if !(decoder is _YYDecoder), let collection = type as? YYModelScalarCollection.Type, collection.scalarCompatible {
            guard let value = try collection.decodeScalars(from: decoder) as? T else { throw DecodingError.yy_corrupted(decoder.codingPath, "Unexpected scalar collection") }
            return value
        }
        if let raw = decoder as? _YYDecoder { return try YYJSONValueDecoder.decode(type, from: raw.value, codingPath: decoder.codingPath, userInfo: decoder.userInfo) }
        if isInteger(type), let decimal = try? container.decode(Decimal.self) {
            return try YYJSONValueDecoder.decode(type, from: NSDecimalNumber(decimal: decimal), codingPath: decoder.codingPath, userInfo: decoder.userInfo)
        }
        if !isInteger(type), let result = try? container.decode(type) { return try validateScalar(result, path: decoder.codingPath) }
        if let text = try? container.decode(String.self) { return try YYJSONValueDecoder.decode(type, from: text, codingPath: decoder.codingPath, userInfo: decoder.userInfo) }
        if let boolean = try? container.decode(Bool.self) { return try YYJSONValueDecoder.decode(type, from: NSNumber(value: boolean), codingPath: decoder.codingPath, userInfo: decoder.userInfo) }
        return try YYJSONValueDecoder.decode(type, from: YYModelJSONValue(from: decoder).raw, codingPath: decoder.codingPath, userInfo: decoder.userInfo)
    }
    static func value<T: Decodable>(_ type: T.Type, from input: Decoder, date: YYModelDateStrategy) throws -> T {
        let decoder = (input as? YYModelDecoder)?.base ?? input
        let context = YYJSONContext.from(input)
        var defaults = context.defaults; defaults.date = date
        let rule = try context.rule(type)
        let policy = rule?.resolved(defaults: defaults) ?? defaults
        var source = decoder
        var object: [String: Any]?
        if let rule, rule.needsInput {
            guard let dictionary = try YYModelJSONInput.object(from: decoder) as? [String: Any] else {
                throw DecodingError.typeMismatch([String: Any].self, .init(codingPath: decoder.codingPath, debugDescription: "Expected an object for a model with dictionary hooks"))
            }
            object = dictionary
            if let hook = rule.will {
                guard let transformed = try hook(dictionary) else { throw DecodingError.yy_corrupted(decoder.codingPath, "willTransform rejected model") }
                object = transformed
                source = context.rawDecoder(transformed, path: decoder.codingPath, userInfo: decoder.userInfo)
            }
        }
        let result: T
        if let dispatch = rule?.polymorphicDecode {
            guard let value = try dispatch(source) as? T else { throw DecodingError.yy_corrupted(source.codingPath, "Unexpected polymorphic type") }
            result = value
        } else if (try? source.singleValueContainer().decodeNil()) == true {
            if let presenceType = type as? any YYModelPresenceType.Type { result = presenceType.yy_null as! T }
            else if let optional = type as? ExpressibleByNilLiteral.Type { result = optional.init(nilLiteral: ()) as! T }
            else if policy.missing == .zeroFill, let zero = YYJSONValueDecoder.zero(type) { result = zero }
            else {
                if !YYJSONValueDecoder.isLeaf(type) {
                    result = try T(from: YYModelDecoder(base: source, policy: policy))
                } else {
                    throw DecodingError.valueNotFound(type, .init(codingPath: source.codingPath, debugDescription: "Null value"))
                }
            }
        } else if type == Date.self {
            if policy.date == .native {
                if let raw = source as? _YYDecoder {
                    if case .custom(let transform) = context.nativeDecoder.dateDecodingStrategy {
                        result = try YYModelNativeBridge.custom(type, raw: raw, options: context.nativeDecoder) { try transform($0) }
                    } else {
                        let data = try JSONSerialization.data(withJSONObject: raw.value, options: [.fragmentsAllowed])
                        result = try context.decodeNative(type, data: data, path: source.codingPath)
                    }
                } else { result = try source.singleValueContainer().decode(type) }
            } else {
                let raw = try (source as? _YYDecoder)?.value ?? YYModelJSONValue(from: source).raw
                guard let value = YYModelDates.shared.date(raw, strategy: policy.date) as? T else { throw DecodingError.dataCorrupted(.init(codingPath: source.codingPath, debugDescription: "Invalid date")) }
                result = value
            }
        } else if type == Data.self {
            // Foundation custom Data strategies are caller code: execute once, do not swallow its error.
            if let raw = source as? _YYDecoder {
                if case .custom(let transform) = context.nativeDecoder.dataDecodingStrategy {
                    result = try YYModelNativeBridge.custom(type, raw: raw, options: context.nativeDecoder) { try transform($0) }
                } else {
                    result = try context.decodeNative(type, data: JSONSerialization.data(withJSONObject: raw.value, options: [.fragmentsAllowed]), path: source.codingPath)
                }
            } else { result = try source.singleValueContainer().decode(type) }
        } else if YYJSONValueDecoder.isLeaf(type) {
            result = try scalar(type, from: source)
        } else if rule == nil, !(source is _YYDecoder), (type as? YYModelNativeCollection.Type)?.nativeCompatible == true,
                  let value = try? source.singleValueContainer().decode(type) {
            result = try validateScalar(value, path: source.codingPath)
        } else if rule == nil, !(source is _YYDecoder), let collection = type as? YYModelScalarCollection.Type,
                  collection.scalarCompatible {
            guard let value = try collection.decodeScalars(from: source) as? T else { throw DecodingError.yy_corrupted(source.codingPath, "Unexpected scalar collection") }
            result = value
        } else if let dictionary = type as? YYModelDictionaryDecoding.Type,
                  let value = try dictionary.decodeDictionary(from: source, date: policy.date) as? T { result = value }
        else {
            let adapter = YYModelDecoder(base: source, policy: policy)
            if !policy.required.isEmpty { try adapter.validateRequired() }
            result = try T(from: adapter)
        }
        if let finish = rule?.finish {
            guard let value = try finish(result, object, decoder.codingPath) as? T else { throw DecodingError.yy_corrupted(decoder.codingPath, "Unexpected transformed type") }
            return value
        }
        return result
    }
}

struct YYModelDecoder: Decoder {
    let base: Decoder
    let policy: YYModelPolicy
    var codingPath: [CodingKey] { base.codingPath }
    var userInfo: [CodingUserInfoKey: Any] { base.userInfo }
    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        KeyedDecodingContainer(YYModelKeyedDecoder<Key>(base: try base.container(keyedBy: YYModelCodingKey.self), policy: policy, context: YYJSONContext.from(base), userInfo: userInfo))
    }
    func unkeyedContainer() throws -> UnkeyedDecodingContainer { YYModelUnkeyedDecoder(base: try base.unkeyedContainer(), date: policy.date, context: YYJSONContext.from(base), userInfo: userInfo) }
    func singleValueContainer() throws -> SingleValueDecodingContainer { YYModelSingleDecoder(base: base, date: policy.date) }
    func validateRequired() throws {
        let container = YYModelKeyedDecoder<YYModelCodingKey>(base: try base.container(keyedBy: YYModelCodingKey.self), policy: policy, context: YYJSONContext.from(base), userInfo: userInfo)
        for key in policy.required {
            guard let field = try container.field(key), try !field.0.decodeNil(forKey: field.1) else {
                throw DecodingError.keyNotFound(YYModelCodingKey(key), .init(codingPath: codingPath, debugDescription: "Required property missing or null"))
            }
        }
    }
}

enum YYFieldResolution {
    case present(KeyedDecodingContainer<YYModelCodingKey>, YYModelCodingKey)
    case null(KeyedDecodingContainer<YYModelCodingKey>, YYModelCodingKey)
    case defaultVal(typed: Any?, json: Any?)
    case fallbackVal(Any)
    case absent
    case invalidPath(Error)
}

struct YYFieldResolver {
    let base: KeyedDecodingContainer<YYModelCodingKey>
    let policy: YYModelPolicy

    func resolve(_ name: String) -> YYFieldResolution {
        guard policy.allows(name) else { return .absent }

        if policy.mapper[name] == nil {
            let key = YYModelCodingKey(name)
            if base.contains(key) {
                do {
                    if try base.decodeNil(forKey: key) {
                        return .null(base, key)
                    } else {
                        return .present(base, key)
                    }
                } catch {
                    return .invalidPath(error)
                }
            }
        } else {
            var firstInvalidError: Error?
            for path in policy.paths(name) {
                guard let last = path.last else { continue }
                var current = base
                var pathBroken = false
                for component in path.dropLast() {
                    let compKey = YYModelCodingKey(component)
                    guard current.contains(compKey) else { pathBroken = true; break }
                    do {
                        current = try current.nestedContainer(keyedBy: YYModelCodingKey.self, forKey: compKey)
                    } catch {
                        if firstInvalidError == nil { firstInvalidError = error }
                        pathBroken = true
                        break
                    }
                }
                if pathBroken { continue }
                let key = YYModelCodingKey(last)
                if current.contains(key) {
                    do {
                        if try current.decodeNil(forKey: key) {
                            return .null(current, key)
                        } else {
                            return .present(current, key)
                        }
                    } catch {
                        return .invalidPath(error)
                    }
                }
            }
            if let firstInvalidError {
                return .invalidPath(firstInvalidError)
            }
        }

        if policy.typedDefaults[name] != nil || policy.defaults[name] != nil {
            return .defaultVal(typed: policy.typedDefaults[name], json: policy.defaults[name])
        }
        if let fallback = policy.fallbacks[name] {
            return .fallbackVal(fallback)
        }
        return .absent
    }
}

struct YYModelKeyedDecoder<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let base: KeyedDecodingContainer<YYModelCodingKey>
    let policy: YYModelPolicy
    let context: YYJSONContext
    let userInfo: [CodingUserInfoKey: Any]
    var codingPath: [CodingKey] { base.codingPath }
    var resolver: YYFieldResolver { YYFieldResolver(base: base, policy: policy) }

    var allKeys: [Key] {
        let physicalAliases = Set(policy.mapper.values.flatMap { $0.paths.compactMap { $0.first } })
        let names = Set(base.allKeys.map(\.stringValue)).subtracting(physicalAliases).union(policy.mapper.keys).union(policy.defaults.keys)
            .union(policy.typedDefaults.keys).union(policy.fallbacks.keys)
        return names.filter { name in
            guard policy.allows(name) else { return false }
            switch resolver.resolve(name) {
            case .present, .null, .defaultVal, .fallbackVal:
                return true
            case .absent, .invalidPath:
                return false
            }
        }.compactMap { Key(stringValue: $0) }
    }

    func field(_ name: String) throws -> (KeyedDecodingContainer<YYModelCodingKey>, YYModelCodingKey)? {
        switch resolver.resolve(name) {
        case .present(let c, let k), .null(let c, let k):
            return (c, k)
        case .invalidPath(let error):
            throw error
        case .defaultVal, .fallbackVal, .absent:
            return nil
        }
    }

    func contains(_ key: Key) -> Bool {
        guard policy.allows(key.stringValue) else { return false }
        switch resolver.resolve(key.stringValue) {
        case .present, .null, .defaultVal, .fallbackVal, .invalidPath:
            return true
        case .absent:
            return false
        }
    }

    func decodeNil(forKey key: Key) throws -> Bool {
        guard policy.allows(key.stringValue) else {
            throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "Key not allowed"))
        }
        switch resolver.resolve(key.stringValue) {
        case .invalidPath(let error):
            throw error
        case .present:
            return false
        case .null:
            if let fallback = policy.fallbacks[key.stringValue] {
                return fallback is NSNull
            }
            return true
        case .fallbackVal(let fallback):
            return fallback is NSNull
        case .defaultVal(let typed, let json):
            if typed != nil { return false }
            if let json { return json is NSNull }
            return false
        case .absent:
            guard policy.missing == .zeroFill else {
                throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "Missing key; supply an explicit default or decode an Optional"))
            }
            return false
        }
    }

    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        let name = key.stringValue
        if policy.mapper[name] == nil, policy.fallbacks[name] == nil,
           (policy.lossy.isEmpty || !policy.lossy.contains(name)),
           policy.allows(name) {
            let physical = YYModelCodingKey(name)
            if YYJSONValueDecoder.isLeaf(type), YYModelDecode.isNativeValue(type),
               base.contains(physical), (try? base.decodeNil(forKey: physical)) == false,
               let result = try? base.decode(type, forKey: physical) {
                return try YYModelDecode.validateScalar(result, path: codingPath + [key])
            }
            if YYModelDecode.isInteger(type),
               base.contains(physical), (try? base.decodeNil(forKey: physical)) == false,
               let decimal = try? base.decode(Decimal.self, forKey: physical),
               let result = try? YYJSONValueDecoder.decode(type, from: NSDecimalNumber(decimal: decimal), codingPath: codingPath + [key], userInfo: userInfo) {
                return try YYModelDecode.validateScalar(result, path: codingPath + [key])
            }
        }

        let resolution = resolver.resolve(name)
        if case .invalidPath(let error) = resolution {
            if policy.fallbacks[name] == nil {
                throw error
            }
        }
        if !policy.lossy.isEmpty, policy.lossy.contains(name), let lossyType = type as? any YYModelLossyArray.Type {
            let date = policy.fieldDates[name] ?? policy.date
            if case .present(let container, let fieldKey) = resolution {
                let report = userInfo[YYModelLossReport.key] as? YYModelLossReport
                do {
                    let unkeyed = try container.nestedUnkeyedContainer(forKey: fieldKey)
                    return try lossyType.decodeLossy(from: unkeyed, property: name, date: date, report: report) as! T
                } catch {
                    report?.record(property: name, index: 0, reason: "\(error)")
                    return lossyType.empty as! T
                }
            }
        }
        if !policy.fallbacks.isEmpty, let fallback = policy.fallbacks[name] {
            let date = policy.fieldDates[name] ?? policy.date
            if case .present(let container, let fieldKey) = resolution,
               let decoded = try? YYModelDecode.value(type, from: container.superDecoder(forKey: fieldKey), date: date) {
                return decoded
            }
            if fallback is NSNull, let optional = T.self as? ExpressibleByNilLiteral.Type {
                return optional.init(nilLiteral: ()) as! T
            }
            guard let value = fallback as? T else {
                throw DecodingError.typeMismatch(
                    T.self,
                    .init(codingPath: codingPath + [key],
                          debugDescription: "Registered fallback for \"\(key.stringValue)\" is not of the requested type")
                )
            }
            return value
        }
        if case .present(let container, let fieldKey) = resolution {
            if YYJSONValueDecoder.isLeaf(type), YYModelDecode.isNativeValue(type), let result = try? container.decode(type, forKey: fieldKey) {
                return try YYModelDecode.validateScalar(result, path: codingPath + [key])
            }
            return try YYModelDecode.value(type, from: container.superDecoder(forKey: fieldKey), date: policy.fieldDates[name] ?? policy.date)
        }
        if case .null(let container, let fieldKey) = resolution {
            if let presenceType = type as? any YYModelPresenceType.Type { return presenceType.yy_null as! T }
            if let optional = type as? ExpressibleByNilLiteral.Type { return optional.init(nilLiteral: ()) as! T }
            if policy.missing == .zeroFill { return try zeroFilled(type, forKey: key) }
            if !YYJSONValueDecoder.isLeaf(type) {
                return try YYModelDecode.value(type, from: container.superDecoder(forKey: fieldKey), date: policy.fieldDates[name] ?? policy.date)
            }
            throw DecodingError.valueNotFound(type, .init(codingPath: codingPath + [key], debugDescription: "Null property"))
        }
        if case .defaultVal(let typed, let json) = resolution {
            if let presenceType = type as? any YYModelPresenceType.Type { return presenceType.yy_absent as! T }
            if let typed = typed as? T { return typed }
            if let json {
                return try YYModelDecode.value(type, from: context.rawDecoder(json, path: codingPath + [key], userInfo: userInfo), date: policy.fieldDates[name] ?? policy.date)
            }
        }
        if case .absent = resolution {
            if let presenceType = type as? any YYModelPresenceType.Type { return presenceType.yy_absent as! T }
            guard policy.missing == .zeroFill else {
                throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "Missing property; supply an explicit default"))
            }
            return try zeroFilled(type, forKey: key)
        }
        if case .invalidPath(let error) = resolution {
            throw error
        }
        guard policy.missing == .zeroFill else { throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "Missing property; supply an explicit default")) }
        return try zeroFilled(type, forKey: key)
    }

    private func zeroFilled<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        if let zero = YYJSONValueDecoder.zero(type) { return zero }
        let empty: Any = String(describing: type).hasPrefix("Array<") || String(describing: type).hasPrefix("Set<") ? [Any]() : [String: Any]()
        return try YYModelDecode.value(type, from: context.rawDecoder(empty, path: codingPath + [key], userInfo: userInfo), date: policy.fieldDates[key.stringValue] ?? policy.date)
    }

    func decodeIfPresent<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T? {
        let name = key.stringValue
        let resolution = resolver.resolve(name)
        if case .invalidPath(let error) = resolution {
            if policy.fallbacks[name] == nil {
                throw error
            }
        }
        if type is any YYModelPresenceType.Type { return try decode(type, forKey: key) }
        if !policy.lossy.isEmpty, policy.lossy.contains(name), let lossyType = type as? any YYModelLossyArray.Type {
            let date = policy.fieldDates[name] ?? policy.date
            if case .present(let container, let fieldKey) = resolution {
                let report = userInfo[YYModelLossReport.key] as? YYModelLossReport
                do {
                    let unkeyed = try container.nestedUnkeyedContainer(forKey: fieldKey)
                    return try lossyType.decodeLossy(from: unkeyed, property: name, date: date, report: report) as? T
                } catch {
                    report?.record(property: name, index: 0, reason: "\(error)")
                    return lossyType.empty as? T
                }
            }
        }
        if !policy.fallbacks.isEmpty, let fallback = policy.fallbacks[name] {
            let date = policy.fieldDates[name] ?? policy.date
            if case .present(let container, let fieldKey) = resolution,
               let decoded = try? YYModelDecode.value(type, from: container.superDecoder(forKey: fieldKey), date: date) {
                return decoded
            }
            if fallback is NSNull { return nil }
            guard let value = fallback as? T else {
                throw DecodingError.typeMismatch(
                    T.self,
                    .init(codingPath: codingPath + [key],
                          debugDescription: "Registered fallback for \"\(key.stringValue)\" is not of the requested type")
                )
            }
            return value
        }
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        return try decode(type, forKey: key)
    }

    func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> {
        try superDecoder(forKey: key).container(keyedBy: type)
    }
    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer { try superDecoder(forKey: key).unkeyedContainer() }
    func superDecoder() throws -> Decoder { YYModelDecoder(base: try base.superDecoder(), policy: YYModelPolicy(date: policy.date, missing: context.defaults.missing)) }
    func superDecoder(forKey key: Key) throws -> Decoder {
        let date = policy.fieldDates[key.stringValue] ?? policy.date
        switch resolver.resolve(key.stringValue) {
        case .present(let container, let fieldKey), .null(let container, let fieldKey):
            return YYModelDecoder(base: try container.superDecoder(forKey: fieldKey), policy: YYModelPolicy(date: date, missing: context.defaults.missing))
        case .defaultVal(let typed, let json):
            let value = json ?? typed
            if let value {
                return YYModelDecoder(base: context.rawDecoder(value, path: codingPath + [key], userInfo: userInfo), policy: YYModelPolicy(date: date, missing: context.defaults.missing))
            }
        case .fallbackVal(let fallback):
            return YYModelDecoder(base: context.rawDecoder(fallback, path: codingPath + [key], userInfo: userInfo), policy: YYModelPolicy(date: date, missing: context.defaults.missing))
        case .invalidPath(let error):
            throw error
        case .absent:
            break
        }
        throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "Missing container"))
    }
}

struct YYModelUnkeyedDecoder: UnkeyedDecodingContainer {
    var base: UnkeyedDecodingContainer
    let date: YYModelDateStrategy
    let context: YYJSONContext
    let userInfo: [CodingUserInfoKey: Any]
    var codingPath: [CodingKey] { base.codingPath }
    var count: Int? { base.count }
    var isAtEnd: Bool { base.isAtEnd }
    var currentIndex: Int { base.currentIndex }
    mutating func decodeNil() throws -> Bool { try base.decodeNil() }
    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
        // Commit the index only after success, allowing a custom Codable to try another type.
        var attempt = base
        if YYJSONValueDecoder.isLeaf(type), YYModelDecode.isNativeValue(type),
           (try? attempt.decodeNil()) == false, let result = try? attempt.decode(type) {
            let value = try YYModelDecode.validateScalar(result, path: codingPath + [YYModelCodingKey(intValue: currentIndex)])
            base = attempt
            return value
        }
        attempt = base
        let value = try YYModelDecode.value(type, from: attempt.superDecoder(), date: date)
        base = attempt
        return value
    }
    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> {
        var attempt = base
        let result = KeyedDecodingContainer(YYModelKeyedDecoder<NestedKey>(base: try attempt.nestedContainer(keyedBy: YYModelCodingKey.self), policy: YYModelPolicy(date: date, missing: context.defaults.missing), context: context, userInfo: userInfo))
        base = attempt; return result
    }
    mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        var attempt = base
        let result = YYModelUnkeyedDecoder(base: try attempt.nestedUnkeyedContainer(), date: date, context: context, userInfo: userInfo)
        base = attempt; return result
    }
    mutating func superDecoder() throws -> Decoder { YYModelDecoder(base: try base.superDecoder(), policy: YYModelPolicy(date: date, missing: context.defaults.missing)) }
}
struct YYModelSingleDecoder: SingleValueDecodingContainer {
    let base: Decoder
    let date: YYModelDateStrategy
    var codingPath: [CodingKey] { base.codingPath }
    func decodeNil() -> Bool { (try? base.singleValueContainer().decodeNil()) ?? false }
    func decode<T: Decodable>(_ type: T.Type) throws -> T { try YYModelDecode.value(type, from: base, date: date) }
}
