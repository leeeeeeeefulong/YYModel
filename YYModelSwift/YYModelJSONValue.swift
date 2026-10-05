import Foundation
import CoreFoundation
import ObjectiveC

// Public NSNumber interoperability retains immutable canonical scalar nodes.
// This lets captured hook numbers survive a later decode without creating a
// second representation or a public metadata-mutation API.
enum YYModelNumberBoundary {
    #if compiler(>=5.10)
    private nonisolated(unsafe) static var key: UInt8 = 0
    #else
    private static var key: UInt8 = 0
    #endif
    private final class Preserved {
        let node: YYModelJSONValue
        init(_ node: YYModelJSONValue) { self.node = node }
    }
    static func attach(_ node: YYModelJSONValue, to number: NSDecimalNumber) {
        objc_setAssociatedObject(number, &key, Preserved(node), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    static func node(from number: NSDecimalNumber) -> YYModelJSONValue? {
        (objc_getAssociatedObject(number, &key) as? Preserved)?.node
    }
}

struct YYModelCodingKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int?
    init(_ value: String) { stringValue = value; intValue = nil }
    init(stringValue: String) { self.init(stringValue) }
    init(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
    /// Preserve a literal spelling while exposing the parsed integer.
    /// `Int("01")` yields `1`; rebuilding the key from that integer would
    /// normalize `"01"` to `"1"` and merge distinct dictionary entries.
    /// Keep `stringValue` verbatim so `"01"` and `"1"` stay separate.
    init(preserving stringValue: String, intValue: Int) {
        self.stringValue = stringValue
        self.intValue = intValue
    }
}

struct YYModelPolicy {
    var mapper: [String: YYModelKey] = [:]
    var blacklist: Set<String> = []
    var whitelist: Set<String>?
    var required: Set<String> = []
    var defaults: [String: Any] = [:]
    var date: YYModelDateStrategy = .automatic
    var missing: YYJSONMissingStrategy = .zeroFill
    var fieldDates: [String: YYModelDateStrategy] = [:]
    /// Properties marked lossy: array elements that fail to decode are skipped
    /// (recorded in `YYModelLossReport`) instead of failing the whole array.
    var lossy: Set<String> = []
    /// Properties with a registered fallback: any failure (missing, null, type mismatch,
    /// unknown enum case, invalid URL) yields the registered value instead of throwing.
    /// `default` only covers an absent key; `fallback` also covers an unusable value.
    var fallbacks: [String: Any] = [:]
    /// Typed business defaults from the KeyPath `default(_:to:)` API (R5): returned
    /// verbatim on decode, never reinterpreted through JSON, a date strategy, or a
    /// nested mapper. `defaults` holds their JSON snapshots for Decoder-consuming
    /// access (`superDecoder(forKey:)`) and raw `[String: Any]` defaults.
    var typedDefaults: [String: Any] = [:]
    func allows(_ key: String) -> Bool { !blacklist.contains(key) && (whitelist?.contains(key) ?? true) }
    func paths(_ key: String) -> [[String]] { mapper[key]?.paths ?? [[key]] }
    func validate(for type: Any.Type) throws {
        if whitelist?.isEmpty == true { throw YYJSONRulesError.rule(.emptyWhitelist, type, "Empty whitelist rejects the model") }
        // An empty key means KeyPath name derivation failed (a nested key path expands to
        // "inner.deep" and is deliberately mapped to "" so it lands here).
        //
        // A DOTTED key is NOT rejected here: configuration keys are CodingKey.stringValue,
        // not Swift property names, so `case value = "v.dot"` is a legal CodingKey and the
        // string API must keep working with it. The top-level-only restriction belongs to
        // the KeyPath entry, which enforces it in `propertyName`.
        for key in Set(mapper.keys).union(defaults.keys).union(typedDefaults.keys).union(fallbacks.keys).union(lossy).union(required).union(blacklist).union(whitelist ?? []) {
            guard !key.isEmpty else {
                throw YYJSONRulesError.rule(.emptyKey, type,
                    "Empty configuration key: a nested key path was used where a top-level property is required"
                )
            }
        }
        for (key, value) in mapper {
            guard !key.isEmpty, !value.paths.isEmpty, value.paths.allSatisfy({ !$0.isEmpty && $0.allSatisfy { !$0.isEmpty } }) else {
                throw YYJSONRulesError.rule(.invalidMapperPath, type, "Invalid mapper path for \(key)")
            }
        }
        for key in required where !allows(key) { throw YYJSONRulesError.rule(.requiredExcluded, type, "Required property excluded: \(key)") }
    }
}

/// Lossless supported JSON scalars; whole objects are materialized only for hooks or type coercion.
indirect enum YYModelJSONValue: Codable {
    case null, bool(Bool), string(String), signed(Int64), unsigned(UInt64), decimal(Decimal), number(Double), float(Float)
    /// Exact decimal + literal-parsed Double for tokens binary64 would round away.
    /// Decimal fields use the first, Double fields use the second (bit-identical).
    case decimalDouble(Decimal, Double, Float?)
    case array([Self]), object([String: Self])
    init(from decoder: Decoder) throws {
        if let raw = decoder as? _YYDecoder { self = try yy_decodingJSONValue(at: raw.codingPath) { try Self(raw.value) }; return }
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
            // Classify by the exact decimal text, but only carry the exact value when
            // binary64 would actually round it away (L1): ordinary floats keep the
            // literal-parsed Double, which is bit-identical to a direct parse and
            // preserves -0.0 (Decimal has no negative zero). Integer tokens at or
            // beyond 2^53 keep their exact value (the F1 hook-input precision fix);
            // Decimal-typed fields of other shapes still decode through .decimal.
            let exact = NSDecimalNumber(decimal: v)
            let text = exact.stringValue
            let double = try c.decode(Double.self)
            guard double.isFinite else { throw DecodingError.yy_corrupted(decoder.codingPath, "Non-finite number") }

            let literalFloat = try? c.decode(Float.self)
            if let literalFloat, literalFloat.bitPattern != Float(double).bitPattern {
                // Decimal may already have rounded a tiny fractional tail into an
                // integer. Preserve the independently parsed Float before classifying.
                self = .decimalDouble(v, double, literalFloat)
            } else if let integer = Int64(text), integer >= (1 << 53) || integer <= -(1 << 53) {
                self = .signed(integer)
            } else if let integer = UInt64(text), integer >= (1 << 53) {
                self = .unsigned(integer)
            } else if exact == NSDecimalNumber(value: double) {
                // binary64 represents this value exactly: keep the literal-parsed Double,
                // which is bit-identical to a direct parse and preserves -0.0
                // (Decimal has no negative zero).
                self = .number(double)
            } else {
                // P2-4: keep BOTH — exact Decimal for Decimal fields, literal Double
                // for Double fields. Storing only Decimal loses 1 ULP for long tokens
                // (`...031251` should be 409/1.000...2, not 408/1.0), because Decimal
                // itself rounds beyond 38 digits and Double(stringValue) re-rounds it.
                self = .decimalDouble(v, double, literalFloat)
            }
        }
        else { let v = try c.decode(Double.self); guard v.isFinite else { throw DecodingError.yy_corrupted(decoder.codingPath, "Non-finite number") }; self = .number(v) }
    }
    init(_ value: Any) throws {
        if value is NSNull { self = .null }
        else if let v = value as? String { self = .string(v) }
        else if let v = value as? NSDecimalNumber {
            guard v != .notANumber else { throw YYModelFailure.invalidObject("Invalid decimal") }
            // Restore the dual form when the raw carries a preserved Double.
            if let node = YYModelNumberBoundary.node(from: v) {
                self = node
            } else {
                self = .decimal(v.decimalValue)
            }
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
    var doubleProjection: Double? {
        switch self {
        case .signed(let value): return Double(value)
        case .unsigned(let value): return Double(value)
        case .number(let value): return value
        case .float(let value): return Double(value)
        case .decimal(let value): return Double(NSDecimalNumber(decimal: value).stringValue)
        case .decimalDouble(_, let value, _): return value
        default: return nil
        }
    }
    var floatProjection: Float? {
        switch self {
        case .float(let value): return value
        case .decimalDouble(let decimal, _, let original):
            return original ?? Float(NSDecimalNumber(decimal: decimal).stringValue)
        case .decimal(let value): return Float(NSDecimalNumber(decimal: value).stringValue)
        default: return doubleProjection.map(Float.init)
        }
    }
    var raw: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let v): return NSNumber(value: v)
        case .string(let v): return v
        case .signed(let v): return NSNumber(value: v)
        case .unsigned(let v): return NSNumber(value: v)
        case .decimal(let v): return NSDecimalNumber(decimal: v)
        case .decimalDouble(let dec, _, _):
            let ns = NSDecimalNumber(decimal: dec)
            YYModelNumberBoundary.attach(self, to: ns)
            return ns
        case .float(let value):
            let ns = NSDecimalNumber(string: String(value))
            YYModelNumberBoundary.attach(self, to: ns)
            return ns
        case .number(let v): return NSNumber(value: v)
        case .array(let v): return v.map(\.raw)
        case .object(let v): return v.mapValues(\.raw)
        }
    }
    func encode(to encoder: Encoder) throws {
        switch self {
        // These are physical JSON keys (including completed hook output), not CodingKeys.
        // Foundation's String-key dictionary path preserves them without applying key strategy again.
        case .object(let v): var c = encoder.singleValueContainer(); try c.encode(v)
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
            case .decimalDouble(let dec, _, _): try c.encode(dec)
            case .number(let v): try c.encode(v)
            case .float(let v): try c.encode(v)
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
            let epoch: Double
            if strategy == .microsecondsSince1970 {
                epoch = seconds / 1_000_000
            } else if strategy == .millisecondsSince1970 || (strategy == .automatic && abs(seconds) > 1e11) {
                epoch = seconds / 1000
            } else {
                epoch = seconds
            }
            return Date(timeIntervalSince1970: epoch)
        }
        guard let input = value as? String, strategy == .automatic || strategy == .iso8601 else { return nil }
        lock.lock(); defer { lock.unlock() }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let result = fractional.date(from: text) ?? iso.date(from: text) { return result }
        return strategy == .automatic ? formats.lazy.compactMap { $0.date(from: text) }.first : nil
    }
    func foundationISO8601(_ date: Date) -> String {
        lock.lock(); defer { lock.unlock() }
        return iso.string(from: date)
    }
    func text(_ value: Date) -> String {
        lock.lock(); defer { lock.unlock() }; return fractional.string(from: value)
    }
}

final class YYKeyMapState: @unchecked Sendable {
    private let lock = NSLock()
    var map: [[String]: [String: String]] = [:]
    func record(parent: [String], logical: String, physical: String) {
        lock.lock(); defer { lock.unlock() }
        if map[parent]?[logical] == nil {
            if map[parent] == nil { map[parent] = [:] }
            map[parent]![logical] = physical
        }
    }
    func physical(parent: [String], logical: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return map[parent]?[logical]
    }
}

/// A decode-scoped lazy Foundation snapshot. Models without dictionary hooks never create it.
final class YYModelJSONInput: @unchecked Sendable {
    static let key = CodingUserInfoKey(rawValue: "YYModelSwift.JSONInput")!
    private let data: Data
    /// Syntax options must match the main decoder. Otherwise enabling `allowsJSON5` or
    /// `assumesTopLevelDictionary` would work for a plain model but break as soon as a
    /// dictionary hook (`willTransform` / `didTransform`) forces this snapshot — the same
    /// decoder must not have two different acceptance ranges depending on the business hook.
    private let allowsJSON5: Bool
    private let assumesTopLevelDictionary: Bool
    private let keyMapState: YYKeyMapState?
    private let useFoundationNumbers: Bool
    private let lock = NSLock()
    private var root: Any?
    init(data: Data, allowsJSON5: Bool = false, assumesTopLevelDictionary: Bool = false, keyMapState: YYKeyMapState? = nil,
         useFoundationNumbers: Bool = YYModelCapability.foundationExactDecimal) {
        self.data = data
        self.allowsJSON5 = allowsJSON5
        self.assumesTopLevelDictionary = assumesTopLevelDictionary
        self.keyMapState = keyMapState
        self.useFoundationNumbers = useFoundationNumbers
    }
    private func snapshot() throws -> Any {
        lock.lock(); defer { lock.unlock() }
        if let root { return root }
        // JSONSerialization rounds integer-semantic tokens (9007199254740993.0) to
        // binary64 before hooks can observe them. Decode the exact tree instead;
        // this local decoder uses the default key strategy, so physical keys survive.
        if useFoundationNumbers {
            let exactDecoder = JSONDecoder()
            if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) {
                exactDecoder.allowsJSON5 = allowsJSON5
                exactDecoder.assumesTopLevelDictionary = assumesTopLevelDictionary
            }
            if let exact = try? exactDecoder.decode(YYModelJSONValue.self, from: data) {
                root = exact.raw
            } else {
                root = try Self.nativeObject(from: data, allowsJSON5: allowsJSON5, assumesTopLevelDictionary: assumesTopLevelDictionary)
            }
        } else {
            root = try Self.nativeObject(from: data, allowsJSON5: allowsJSON5, assumesTopLevelDictionary: assumesTopLevelDictionary)
        }
        return root!
    }
    static func nativeObject(from data: Data, allowsJSON5: Bool, assumesTopLevelDictionary: Bool) throws -> Any {
        var options: JSONSerialization.ReadingOptions = [.fragmentsAllowed]
        if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) {
            if allowsJSON5 { options.insert(.json5Allowed) }
            if assumesTopLevelDictionary {
                // Foundation raises an ObjC exception if these options coexist.
                options.remove(.fragmentsAllowed)
                options.insert(.topLevelDictionaryAssumed)
            }
        }
        let object = try JSONSerialization.jsonObject(with: data, options: options)
        guard data.range(of: Data("-0".utf8)) != nil else { return object }
        // JSONSerialization stores integer-spelled -0 as an unsigned/signed zero.
        // Read only signs from Foundation; keep every integer from the exact raw
        // parse. No second scalar tree or custom tokenizer is introduced, and this
        // extra pass only runs on the integer route with a possible negative zero.
        let signDecoder = JSONDecoder()
        if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) {
            signDecoder.allowsJSON5 = allowsJSON5
            signDecoder.assumesTopLevelDictionary = assumesTopLevelDictionary
        }
        signDecoder.userInfo[YYModelNegativeZeroRestoring.key] = YYModelNegativeZeroInput(object)
        return try signDecoder.decode(YYModelNegativeZeroRestoring.self, from: data).value
    }
    func object(at path: [CodingKey]) throws -> Any {
        var value = try snapshot()
        var logicalParent: [String] = []
        for key in path {
            if let array = value as? [Any], let idx = key.intValue, array.indices.contains(idx) {
                value = array[idx]
                logicalParent.append(key.stringValue)
            } else if let dictionary = value as? [String: Any] {
                let physical: String
                if let mapped = keyMapState?.physical(parent: logicalParent, logical: key.stringValue),
                   dictionary[mapped] != nil {
                    physical = mapped
                } else if dictionary[key.stringValue] != nil {
                    physical = key.stringValue
                } else {
                    throw DecodingError.keyNotFound(key, .init(codingPath: path, debugDescription: "Missing hook input path"))
                }
                value = dictionary[physical]!
                logicalParent.append(key.stringValue)
            } else {
                throw DecodingError.keyNotFound(key, .init(codingPath: path, debugDescription: "Missing hook input path"))
            }
        }
        return value
    }
    static func object(from decoder: Decoder) throws -> Any {
        if let raw = decoder as? _YYDecoder { return isolatedJSON(raw.value) }
        if let input = decoder.userInfo[key] as? YYModelJSONInput { return try input.object(at: decoder.codingPath) }
        return try YYModelJSONValue(from: decoder).raw
    }
    // Swift's top-level COW does not isolate Foundation mutable reference subtrees.
    // Rebuild containers while retaining immutable scalar metadata and business values.
    private static func isolatedJSON(_ value: Any) -> Any {
        if let dictionary = value as? [String: Any] { return dictionary.mapValues(isolatedJSON) }
        if let array = value as? [Any] { return array.map(isolatedJSON) }
        if let string = value as? String { return string }
        return value
    }
}

// Visit the existing raw shape synchronously. Never retain a Foundation Decoder:
// Foundation may reuse it while advancing dictionary/array traversal.
// Immutable, decode-local raw JSON containers satisfy the SDK's Sendable userInfo
// requirement. No caller-owned mutable container is stored or shared here.
private final class YYModelNegativeZeroInput: @unchecked Sendable {
    let value: Any
    init(_ value: Any) { self.value = value }
}
private struct YYModelNegativeZeroRestoring: Decodable {
    static let key = CodingUserInfoKey(rawValue: "YYModelSwift.NegativeZeroInput")!
    let value: Any
    init(from decoder: Decoder) throws {
        guard let input = decoder.userInfo[Self.key] as? YYModelNegativeZeroInput else {
            throw DecodingError.yy_corrupted(decoder.codingPath, "Missing signed-zero input")
        }
        value = try Self.restoring(input.value, from: decoder)
    }
    private static func restoring(_ object: Any, from decoder: Decoder) throws -> Any {
        if var dictionary = object as? [String: Any] {
            let container = try decoder.container(keyedBy: YYModelCodingKey.self)
            for (key, value) in dictionary {
                dictionary[key] = try restoring(value, from: container.superDecoder(forKey: YYModelCodingKey(key)))
            }
            return dictionary
        }
        if var array = object as? [Any] {
            var container = try decoder.unkeyedContainer()
            for index in array.indices {
                array[index] = try restoring(array[index], from: container.superDecoder())
            }
            return array
        }
        if let number = object as? NSNumber,
           CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue == 0,
           let value = try? decoder.singleValueContainer().decode(Double.self),
           value == 0, value.sign == .minus {
            return NSNumber(value: value)
        }
        return object
    }
}
