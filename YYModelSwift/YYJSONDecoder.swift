//
//  YYJSONDecoder.swift
//  YYModel
//
//  Decodes plain Swift Codable values. Models do not conform to a YYModel protocol.
//  Data that already matches Codable uses JSONDecoder (Unix seconds for dates).
//  If that fails, a tolerant walker zero-fills missing keys and nulls, and coerces
//  string, number, and bool values. Key renames stay on Swift CodingKeys.
//
//  URL and raw-value enums have no zero value: keep those properties optional
//  when the key may be absent. A value that cannot be coerced throws.
//

import Foundation

public struct YYJSONDecoder: Sendable {
    public init() {}

    /// `Data` that already matches `Codable` is decoded with `JSONDecoder`.
    /// Dates in that pass are Unix seconds. If that decode throws, the tolerant
    /// walker runs: it zero-fills missing keys and nulls, and coerces string,
    /// number, and bool values.
    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        if let value = try? Self.fastDecoder().decode(type, from: data) {
            return value
        }
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return try decode(type, from: object)
    }

    public func decode<T: Decodable>(_ type: T.Type, from object: Any) throws -> T {
        return try YYJSONValueDecoder.decode(type, from: object, codingPath: [])
    }

    private static func fastDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let seconds = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: seconds > 1e11 ? seconds / 1000.0 : seconds)
            }
            if let text = try? container.decode(String.self) {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if let seconds = TimeInterval(trimmed) {
                    return Date(timeIntervalSince1970: seconds > 1e11 ? seconds / 1000.0 : seconds)
                }
                if let d = YYJSONValueDecoder.isoFormatterWithFractionalSeconds.date(from: trimmed) { return d }
                if let d = YYJSONValueDecoder.isoFormatterStandard.date(from: trimmed) { return d }
                if let d = YYJSONValueDecoder.commonDateFormatter.date(from: trimmed) { return d }
            }
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Invalid date format"))
        }
        return decoder
    }
}

enum YYJSONValueDecoder {
    static func decode<T: Decodable>(_ type: T.Type, from value: Any, codingPath: [CodingKey]) throws -> T {
        if value is NSNull {
            if let zero = zero(type) { return zero }
            throw DecodingError.valueNotFound(type, context(codingPath, "null for \(type)"))
        }
        if let coerced = coerce(value, to: type) {
            return coerced
        }
        if isLeaf(type) {
            throw DecodingError.typeMismatch(type, context(codingPath, "cannot coerce \(Swift.type(of: value)) to \(type)"))
        }
        let decoder = _YYDecoder(value: value, codingPath: codingPath)
        return try T(from: decoder)
    }

    static func zero<T: Decodable>(_ type: T.Type) -> T? {
        switch type {
        case is String.Type: return "" as? T
        case is Bool.Type: return false as? T
        case is Int.Type: return 0 as? T
        case is Int8.Type: return Int8(0) as? T
        case is Int16.Type: return Int16(0) as? T
        case is Int32.Type: return Int32(0) as? T
        case is Int64.Type: return Int64(0) as? T
        case is UInt.Type: return UInt(0) as? T
        case is UInt8.Type: return UInt8(0) as? T
        case is UInt16.Type: return UInt16(0) as? T
        case is UInt32.Type: return UInt32(0) as? T
        case is UInt64.Type: return UInt64(0) as? T
        case is Float.Type: return Float(0) as? T
        case is Double.Type: return Double(0) as? T
        case is Decimal.Type: return Decimal(0) as? T
        case is CGFloat.Type: return CGFloat(0) as? T
        case is Date.Type: return Date(timeIntervalSince1970: 0) as? T
        case is Data.Type: return Data() as? T
        default: return nil
        }
    }

    static func missing<T: Decodable>(_ type: T.Type, codingPath: [CodingKey]) throws -> T {
        if let zero = zero(type) { return zero }
        let name = String(describing: type)
        if name.hasPrefix("Array<") || name.hasPrefix("Set<") {
            return try decode(type, from: [Any](), codingPath: codingPath)
        }
        if name.hasPrefix("Dictionary<") {
            return try decode(type, from: [String: Any](), codingPath: codingPath)
        }
        return try decode(type, from: [String: Any](), codingPath: codingPath)
    }

    static func isLeaf<T>(_ type: T.Type) -> Bool {
        T.self == String.self || T.self == Bool.self
            || T.self == Int.self || T.self == Int8.self || T.self == Int16.self || T.self == Int32.self || T.self == Int64.self
            || T.self == UInt.self || T.self == UInt8.self || T.self == UInt16.self || T.self == UInt32.self || T.self == UInt64.self
            || T.self == Float.self || T.self == Double.self || T.self == Decimal.self || T.self == CGFloat.self
            || T.self == Date.self || T.self == Data.self || T.self == URL.self
    }

    static func coerce<T: Decodable>(_ value: Any, to type: T.Type) -> T? {
        if T.self == String.self { return string(from: value) as? T }
        if T.self == Bool.self { return bool(from: value) as? T }
        if T.self == Double.self { return double(from: value) as? T }
        if T.self == Float.self { return double(from: value).map { Float($0) } as? T }
        if T.self == CGFloat.self { return double(from: value).map { CGFloat($0) } as? T }
        if T.self == Decimal.self { return decimal(from: value) as? T }
        if T.self == Int.self { return integer(value, Int.self) as? T }
        if T.self == Int8.self { return integer(value, Int8.self) as? T }
        if T.self == Int16.self { return integer(value, Int16.self) as? T }
        if T.self == Int32.self { return integer(value, Int32.self) as? T }
        if T.self == Int64.self { return integer(value, Int64.self) as? T }
        if T.self == UInt.self { return unsigned(value, UInt.self) as? T }
        if T.self == UInt8.self { return unsigned(value, UInt8.self) as? T }
        if T.self == UInt16.self { return unsigned(value, UInt16.self) as? T }
        if T.self == UInt32.self { return unsigned(value, UInt32.self) as? T }
        if T.self == UInt64.self { return unsigned(value, UInt64.self) as? T }
        if T.self == URL.self {
            guard let text = value as? String, let url = URL(string: text), !text.isEmpty else { return nil }
            return url as? T
        }
        if T.self == Date.self { return date(from: value) as? T }
        if T.self == Data.self {
            if let data = value as? Data { return data as? T }
            if let text = value as? String, let data = Data(base64Encoded: text) { return data as? T }
            return nil
        }
        return nil
    }

    private static func string(from value: Any) -> String? {
        if let text = value as? String { return text }
        if let number = value as? NSNumber {
            if isBoolean(number) { return number.boolValue ? "true" : "false" }
            return number.stringValue
        }
        return nil
    }

    private static func bool(from value: Any) -> Bool? {
        if let number = value as? NSNumber {
            if isBoolean(number) { return number.boolValue }
            if number.doubleValue == 0 { return false }
            if number.doubleValue == 1 { return true }
            return nil
        }
        if let text = value as? String {
            switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: return nil
            }
        }
        return nil
    }

    private static func double(from value: Any) -> Double? {
        if let number = value as? NSNumber {
            if isBoolean(number) { return number.boolValue ? 1 : 0 }
            return number.doubleValue
        }
        if let text = value as? String {
            return Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private static func decimal(from value: Any) -> Decimal? {
        if let text = value as? String { return Decimal(string: text) }
        if let number = value as? NSNumber, !isBoolean(number) {
            return number.decimalValue
        }
        return nil
    }

    private static func integer<I: FixedWidthInteger & SignedInteger>(_ value: Any, _ type: I.Type) -> I? {
        guard let number = wholeNumber(from: value) else { return nil }
        return I(exactly: number)
    }

    private static func unsigned<I: FixedWidthInteger & UnsignedInteger>(_ value: Any, _ type: I.Type) -> I? {
        guard let number = wholeNumber(from: value), number >= 0 else { return nil }
        return I(exactly: number)
    }

    private static func wholeNumber(from value: Any) -> Int64? {
        if let number = value as? NSNumber {
            if isBoolean(number) { return number.boolValue ? 1 : 0 }
            let double = number.doubleValue
            guard double.isFinite else { return nil }
            return Int64(double.rounded(.towardZero))
        }
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let exact = Int64(trimmed) { return exact }
            if let double = Double(trimmed), double.isFinite {
                return Int64(double.rounded(.towardZero))
            }
        }
        return nil
    }

    fileprivate static let isoFormatterWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    fileprivate static let isoFormatterStandard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    fileprivate static let commonDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static func date(from value: Any) -> Date? {
        if let date = value as? Date { return date }
        if let number = value as? NSNumber, !isBoolean(number) {
            let seconds = number.doubleValue
            return Date(timeIntervalSince1970: seconds > 1e11 ? seconds / 1000.0 : seconds)
        }
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let seconds = TimeInterval(trimmed) {
                return Date(timeIntervalSince1970: seconds > 1e11 ? seconds / 1000.0 : seconds)
            }
            if let d = isoFormatterWithFractionalSeconds.date(from: trimmed) { return d }
            if let d = isoFormatterStandard.date(from: trimmed) { return d }
            return commonDateFormatter.date(from: trimmed)
        }
        return nil
    }

    private static func isBoolean(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private static func context(_ path: [CodingKey], _ debug: String) -> DecodingError.Context {
        DecodingError.Context(codingPath: path, debugDescription: debug)
    }
}

private final class _YYDecoder: Decoder {
    var codingPath: [CodingKey]
    var userInfo: [CodingUserInfoKey: Any] = [:]
    let value: Any

    init(value: Any, codingPath: [CodingKey]) {
        self.value = value
        self.codingPath = codingPath
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        guard let dictionary = value as? [String: Any] else {
            throw DecodingError.typeMismatch([String: Any].self, DecodingError.Context(codingPath: codingPath, debugDescription: "expected object"))
        }
        return KeyedDecodingContainer(YYKeyedContainer(decoder: self, dictionary: dictionary))
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        guard let array = value as? [Any] else {
            throw DecodingError.typeMismatch([Any].self, DecodingError.Context(codingPath: codingPath, debugDescription: "expected array"))
        }
        return YYUnkeyedContainer(decoder: self, array: array)
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
        YYSingleContainer(decoder: self)
    }
}

private struct YYKeyedContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let decoder: _YYDecoder
    let dictionary: [String: Any]
    var codingPath: [CodingKey] { decoder.codingPath }
    var allKeys: [Key] { dictionary.keys.compactMap(Key.init(stringValue:)) }

    func contains(_ key: Key) -> Bool { dictionary[key.stringValue] != nil }

    func decodeNil(forKey key: Key) throws -> Bool {
        guard let value = dictionary[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath, debugDescription: key.stringValue))
        }
        return value is NSNull
    }

    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        let path = codingPath + [key]
        guard let value = dictionary[key.stringValue], !(value is NSNull) else {
            return try YYJSONValueDecoder.missing(type, codingPath: path)
        }
        return try YYJSONValueDecoder.decode(type, from: value, codingPath: path)
    }

    func decodeIfPresent<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T? {
        guard let value = dictionary[key.stringValue], !(value is NSNull) else { return nil }
        return try YYJSONValueDecoder.decode(type, from: value, codingPath: codingPath + [key])
    }

    func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> {
        try nestedDecoder(forKey: key).container(keyedBy: type)
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        try nestedDecoder(forKey: key).unkeyedContainer()
    }

    func superDecoder() throws -> Decoder { _YYDecoder(value: NSNull(), codingPath: codingPath) }
    func superDecoder(forKey key: Key) throws -> Decoder { try nestedDecoder(forKey: key) }

    private func nestedDecoder(forKey key: Key) throws -> _YYDecoder {
        guard let value = dictionary[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath, debugDescription: key.stringValue))
        }
        return _YYDecoder(value: value, codingPath: codingPath + [key])
    }
}

private struct YYUnkeyedContainer: UnkeyedDecodingContainer {
    let decoder: _YYDecoder
    let array: [Any]
    var codingPath: [CodingKey] { decoder.codingPath }
    var count: Int? { array.count }
    var isAtEnd: Bool { currentIndex >= array.count }
    private(set) var currentIndex: Int = 0

    mutating func decodeNil() throws -> Bool {
        guard !isAtEnd else { throw end() }
        if array[currentIndex] is NSNull {
            currentIndex += 1
            return true
        }
        return false
    }

    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
        guard !isAtEnd else { throw end() }
        let index = currentIndex
        currentIndex += 1
        let key = YYIndexKey(intValue: index)
        return try YYJSONValueDecoder.decode(type, from: array[index], codingPath: codingPath + [key])
    }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> {
        try nextDecoder().container(keyedBy: type)
    }

    mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        try nextDecoder().unkeyedContainer()
    }

    mutating func superDecoder() throws -> Decoder { try nextDecoder() }

    private mutating func nextDecoder() throws -> _YYDecoder {
        guard !isAtEnd else { throw end() }
        let index = currentIndex
        currentIndex += 1
        return _YYDecoder(value: array[index], codingPath: codingPath + [YYIndexKey(intValue: index)])
    }

    private func end() -> DecodingError {
        DecodingError.valueNotFound(Any.self, DecodingError.Context(codingPath: codingPath, debugDescription: "array ended"))
    }
}

private struct YYSingleContainer: SingleValueDecodingContainer {
    let decoder: _YYDecoder
    var codingPath: [CodingKey] { decoder.codingPath }

    func decodeNil() -> Bool { decoder.value is NSNull }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try YYJSONValueDecoder.decode(type, from: decoder.value, codingPath: codingPath)
    }
}

private struct YYIndexKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = Int(stringValue)
    }
    init(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}
