import Foundation
import CoreFoundation

struct YYModelCodingKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int?
    init(_ value: String) { stringValue = value; intValue = nil }
    init(stringValue: String) { self.init(stringValue) }
    init(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
}

// Configuration snapshots are immutable. The lock protects publication, not execution of user hooks.
final class YYModelSchemaCache: @unchecked Sendable {
    static let shared = YYModelSchemaCache()
    private let lock = NSLock()
    private var values: [ObjectIdentifier: Any] = [:]
    private var variantTables: [ObjectIdentifier: Any] = [:]
    func schema<M: YYModelCodable>(_ type: M.Type) -> YYModelSchema<M> {
        let key = ObjectIdentifier(type)
        lock.lock(); let cached = values[key] as? YYModelSchema<M>; lock.unlock()
        if let cached { return cached }
        let fresh = YYModelSchema(configuration: M.yy_modelConfiguration)
        lock.lock(); defer { lock.unlock() }
        if let cached = values[key] as? YYModelSchema<M> { return cached }
        values[key] = fresh
        return fresh
    }
    func variants<M: YYModelPolymorphic>(_ type: M.Type) -> [String: YYModelVariant<M>] {
        let key = ObjectIdentifier(type)
        lock.lock(); let cached = variantTables[key] as? [String: YYModelVariant<M>]; lock.unlock()
        if let cached { return cached }
        let fresh = M.yy_modelVariants
        lock.lock(); defer { lock.unlock() }
        if let cached = variantTables[key] as? [String: YYModelVariant<M>] { return cached }
        variantTables[key] = fresh; return fresh
    }

}
struct YYModelSchema<M> {
    let configuration: YYModelConfiguration<M>
    private let resolved: Result<YYModelPolicy, Error>
    init(configuration c: YYModelConfiguration<M>) {
        configuration = c
        let policy = YYModelPolicy(mapper: c.mapper, blacklist: Set(c.blacklist), whitelist: c.whitelist.map(Set.init),
                                   required: Set(c.requiredProperties), defaults: c.defaultValues, date: c.dateStrategy)
        resolved = Result {
            try policy.validate()
            if M.self is any YYModelPolymorphic.Type {
                guard c.mapper.isEmpty, c.blacklist.isEmpty, c.whitelist == nil, c.requiredProperties.isEmpty, c.defaultValues.isEmpty, c.dateStrategy == .automatic else {
                    throw YYModelFailure.invalidObject("Declare polymorphic field and date policies on the payload model, not the enum")
                }
            }
            return policy
        }
    }
    func policy() throws -> YYModelPolicy { try resolved.get() }
}

struct YYModelPolicy {
    var mapper: [String: YYModelKey] = [:]
    var blacklist: Set<String> = []
    var whitelist: Set<String>?
    var required: Set<String> = []
    var defaults: [String: Any] = [:]
    var date: YYModelDateStrategy = .automatic
    func allows(_ key: String) -> Bool { !blacklist.contains(key) && (whitelist?.contains(key) ?? true) }
    func paths(_ key: String) -> [[String]] { mapper[key]?.paths ?? [[key]] }
    func validate() throws {
        if whitelist?.isEmpty == true { throw YYModelFailure.invalidObject("Empty whitelist rejects the model") }
        for (key, value) in mapper {
            guard !key.isEmpty, !value.paths.isEmpty, value.paths.allSatisfy({ !$0.isEmpty && $0.allSatisfy { !$0.isEmpty } }) else {
                throw YYModelFailure.invalidObject("Invalid mapper path for \(key)")
            }
        }
        for key in required where !allows(key) { throw YYModelFailure.invalidObject("Required property excluded: \(key)") }
    }
}

/// Lossless supported JSON scalars; whole objects are materialized only for hooks or type coercion.
indirect enum YYModelJSONValue: Codable {
    case null, bool(Bool), string(String), signed(Int64), unsigned(UInt64), decimal(Decimal), number(Double)
    case array([Self]), object([String: Self])
    init(from decoder: Decoder) throws {
        if let raw = decoder as? _YYDecoder { try self.init(raw.value); return }
        if let container = try? decoder.container(keyedBy: YYModelCodingKey.self) {
            self = .object(try Dictionary(uniqueKeysWithValues: container.allKeys.map { key in (key.stringValue, try container.decode(Self.self, forKey: key)) })); return
        }
        if var container = try? decoder.unkeyedContainer() {
            var values: [Self] = []; while !container.isAtEnd { values.append(try container.decode(Self.self)) }
            self = .array(values); return
        }
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Decimal.self), !v.isNaN {
            // Native integer decoding can accept a large fractional token after rounding.
            // Classify the exact decimal before deciding that a JSON number is an integer.
            let text = NSDecimalNumber(decimal: v).stringValue
            if let integer = Int64(text) { self = .signed(integer) }
            else if let integer = UInt64(text) { self = .unsigned(integer) }
            else { self = .decimal(v) }
        }
        else { let v = try c.decode(Double.self); guard v.isFinite else { throw YYModelFailure.invalidObject("Non-finite number") }; self = .number(v) }
    }
    init(_ value: Any) throws {
        if value is NSNull { self = .null }
        else if let v = value as? String { self = .string(v) }
        else if let v = value as? NSDecimalNumber {
            guard v != .notANumber else { throw YYModelFailure.invalidObject("Invalid decimal") }; self = .decimal(v.decimalValue)
        } else if let v = value as? NSNumber {
            if CFGetTypeID(v) == CFBooleanGetTypeID() { self = .bool(v.boolValue) }
            else {
                guard v.doubleValue.isFinite else { throw YYModelFailure.invalidObject("Non-finite number") }
                let kind = String(cString: v.objCType)
                if ["Q", "L", "I", "S", "C"].contains(kind) { self = .unsigned(v.uint64Value) }
                else if ["q", "l", "i", "s", "c"].contains(kind) { self = .signed(v.int64Value) }
                else { self = .number(v.doubleValue) }
            }
        } else if let v = value as? [String: Any] { self = .object(try v.mapValues(Self.init)) }
        else if let v = value as? [Any] { self = .array(try v.map(Self.init)) }
        else { throw YYModelFailure.invalidObject("Unsupported JSON value: \(Swift.type(of: value))") }
    }
    var raw: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let v): return NSNumber(value: v)
        case .string(let v): return v
        case .signed(let v): return NSNumber(value: v)
        case .unsigned(let v): return NSNumber(value: v)
        case .decimal(let v): return NSDecimalNumber(decimal: v)
        case .number(let v): return NSNumber(value: v)
        case .array(let v): return v.map(\.raw)
        case .object(let v): return v.mapValues(\.raw)
        }
    }
    func encode(to encoder: Encoder) throws {
        switch self {
        case .object(let v): var c = encoder.container(keyedBy: YYModelCodingKey.self); for (key, value) in v { try c.encode(value, forKey: YYModelCodingKey(key)) }
        case .array(let v): var c = encoder.unkeyedContainer(); for value in v { try c.encode(value) }
        default:
            var c = encoder.singleValueContainer()
            switch self {
            case .null: try c.encodeNil()
            case .bool(let v): try c.encode(v)
            case .string(let v): try c.encode(v)
            case .signed(let v): try c.encode(v)
            case .unsigned(let v): try c.encode(v)
            case .decimal(let v): try c.encode(v)
            case .number(let v): try c.encode(v)
            default: break
            }
        }
    }
}

// Formatter instances are protected together because ISO8601DateFormatter is not Sendable.
final class YYModelDates: @unchecked Sendable {
    static let shared = YYModelDates()
    private let lock = NSLock()
    private let iso = ISO8601DateFormatter()
    private let fractional = ISO8601DateFormatter()
    private let formats: [DateFormatter]
    private init() {
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formats = ["yyyy-MM-dd", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm:ss.SSS",
                   "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss.SSS",
                   "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
                   "EEE MMM dd HH:mm:ss Z yyyy", "EEE MMM dd HH:mm:ss.SSS Z yyyy",
                   "EEE, dd MMM yyyy HH:mm:ss Z", "EEE MMM dd HH:mm:ss yyyy", "yyyy/MM/dd HH:mm:ss"].map {
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = $0; f.isLenient = false; return f
        }
    }
    func date(_ value: Any, strategy: YYModelDateStrategy) -> Date? {
        if let date = value as? Date { return date.timeIntervalSince1970.isFinite ? date : nil }
        var seconds: Double?
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { seconds = number.doubleValue }
        if let text = value as? String { seconds = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
        if strategy != .iso8601, let seconds, seconds.isFinite {
            let epoch = strategy == .millisecondsSince1970 || (strategy == .automatic && abs(seconds) > 1e11) ? seconds / 1000 : seconds
            return Date(timeIntervalSince1970: epoch)
        }
        guard let input = value as? String, strategy == .automatic || strategy == .iso8601 else { return nil }
        lock.lock(); defer { lock.unlock() }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let result = fractional.date(from: text) ?? iso.date(from: text) { return result }
        return strategy == .automatic ? formats.lazy.compactMap { $0.date(from: text) }.first : nil
    }
    func text(_ value: Date) -> String {
        lock.lock(); defer { lock.unlock() }; return fractional.string(from: value)
    }
}

/// A decode-scoped lazy Foundation snapshot. Models without dictionary hooks never create it.
final class YYModelJSONInput: @unchecked Sendable {
    static let key = CodingUserInfoKey(rawValue: "YYModelSwift.JSONInput")!
    private let data: Data
    private let lock = NSLock()
    private var root: Any?
    init(data: Data) { self.data = data }
    private func snapshot() throws -> Any {
        lock.lock(); defer { lock.unlock() }
        if let root { return root }
        let value = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        root = value
        return value
    }
    func object(at path: [CodingKey]) throws -> Any {
        var value = try snapshot()
        for key in path {
            if let array = value as? [Any], let index = key.intValue, array.indices.contains(index) { value = array[index] }
            else if let dictionary = value as? [String: Any], let next = dictionary[key.stringValue] { value = next }
            else { throw DecodingError.keyNotFound(key, .init(codingPath: path, debugDescription: "Missing hook input path")) }
        }
        return value
    }
    static func object(from decoder: Decoder) throws -> Any {
        if let raw = decoder as? _YYDecoder { return raw.value }
        if let input = decoder.userInfo[key] as? YYModelJSONInput { return try input.object(at: decoder.codingPath) }
        return try YYModelJSONValue(from: decoder).raw
    }
}
