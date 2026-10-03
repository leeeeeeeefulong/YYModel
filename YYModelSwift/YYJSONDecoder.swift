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
        return try YYJSONValueDecoder.decode(type, from: object, codingPath: [])
    }

    public func decode<T: Decodable>(_ type: T.Type, from object: Any) throws -> T {
        if JSONSerialization.isValidJSONObject(object),
           let data = try? JSONSerialization.data(withJSONObject: object, options: []),
           let value = try? Self.fastDecoder().decode(type, from: data) {
            return value
        }
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
    private static func nilValue<T>(_ type: T.Type) -> T? {
        if let optType = type as? ExpressibleByNilLiteral.Type {
            return (optType.init(nilLiteral: ()) as! T)
        }
        return nil
    }

    static func decode<T: Decodable>(_ type: T.Type, from value: Any, codingPath: [CodingKey]) throws -> T {
        if value is NSNull {
            if let nilVal = nilValue(type) { return nilVal }
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
        if let nilVal = nilValue(type) { return nilVal }
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
        if T.self == UInt.self { return integer(value, UInt.self) as? T }
        if T.self == UInt8.self { return integer(value, UInt8.self) as? T }
        if T.self == UInt16.self { return integer(value, UInt16.self) as? T }
        if T.self == UInt32.self { return integer(value, UInt32.self) as? T }
        if T.self == UInt64.self { return integer(value, UInt64.self) as? T }
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

    /// A validated ASCII coefficient and scale: base 10, or base 16 with a binary scale.
    private struct NumericText {
        let negative: Bool
        let radix: Int
        let digits: [UInt8]
        let scale: Int
    }

    private static func numericText(_ text: String) -> NumericText? {
        let bytes = Array(text.utf8)
        guard !bytes.isEmpty else { return nil }
        var index = 0
        let negative = bytes[0] == 45
        if bytes[0] == 43 || negative { index += 1 }
        var radix = 10
        if index + 1 < bytes.count, bytes[index] == 48,
           bytes[index + 1] == 120 || bytes[index + 1] == 88 {
            radix = 16
            index += 2
        }
        var digits: [UInt8] = []
        var hasDot = false
        var fractionalDigits = 0
        coefficient: while index < bytes.count {
            let byte = bytes[index]
            let digit: UInt8
            switch byte {
            case 48...57: digit = byte - 48
            case 65...70 where radix == 16: digit = byte - 55
            case 97...102 where radix == 16: digit = byte - 87
            case 46 where !hasDot:
                hasDot = true
                index += 1
                continue
            default: break coefficient
            }
            digits.append(digit)
            if hasDot { fractionalDigits += 1 }
            index += 1
        }
        guard !digits.isEmpty else { return nil }
        var exponent = 0
        if index < bytes.count {
            let marker = bytes[index]
            guard radix == 16 ? (marker == 112 || marker == 80) : (marker == 101 || marker == 69) else { return nil }
            index += 1
            var negativeExponent = false
            if index < bytes.count, bytes[index] == 43 || bytes[index] == 45 {
                negativeExponent = bytes[index] == 45
                index += 1
            }
            let start = index
            // Beyond this bound, a nonzero coefficient is certainly out of range or truncates to zero.
            // Saturation counts the exponent's value, not its raw length or leading zeros.
            let limit = bytes.count * 4 + 1024
            while index < bytes.count {
                let byte = bytes[index]
                guard byte >= 48 && byte <= 57 else { return nil }
                let digit = Int(byte - 48)
                exponent = exponent > (limit - digit) / 10 ? limit : exponent * 10 + digit
                index += 1
            }
            guard index > start else { return nil }
            if negativeExponent { exponent = -exponent }
        } else if radix == 16 {
            return nil // C99 hexadecimal floating syntax requires a p exponent.
        }
        let unit = radix == 16 ? 4 : 1
        var scale = exponent - fractionalDigits * unit
        let first = digits.firstIndex(where: { $0 != 0 }) ?? digits.endIndex
        digits = Array(digits[first...])
        while digits.last == 0 {
            digits.removeLast()
            scale += unit
        }
        return NumericText(negative: negative, radix: radix, digits: digits, scale: scale)
    }

    private static func integer<I: FixedWidthInteger>(from text: NumericText, _ type: I.Type) -> I? {
        guard !text.digits.isEmpty else { return I(0) }
        var magnitude: UInt64 = 0
        if text.radix == 10 {
            let count = text.digits.count + text.scale
            if count <= 0 { return I(0) }
            guard count <= 20 else { return nil }
            for index in 0..<count {
                let digit = index < text.digits.count ? UInt64(text.digits[index]) : 0
                let product = magnitude.multipliedReportingOverflow(by: 10)
                let sum = product.partialValue.addingReportingOverflow(digit)
                guard !product.overflow && !sum.overflow else { return nil }
                magnitude = sum.partialValue
            }
        } else {
            let leadingBits = 8 - text.digits[0].leadingZeroBitCount
            let coefficientBits = leadingBits + (text.digits.count - 1) * 4
            let count = coefficientBits + text.scale
            if count <= 0 { return I(0) }
            guard count <= 64 else { return nil }
            // Read only the surviving high bits; discarded fractional bits never enter a float.
            for index in 0..<count {
                let bit: UInt64
                if index < coefficientBits {
                    let position = index + 4 - leadingBits
                    bit = UInt64((text.digits[position / 4] >> (3 - position % 4)) & 1)
                } else {
                    bit = 0
                }
                magnitude = (magnitude << 1) | bit
            }
        }
        if magnitude == 0 { return I(0) }
        return I((text.negative ? "-" : "") + String(magnitude))
    }

    private static func decimal(from text: NumericText) -> Decimal? {
        guard !text.digits.isEmpty else { return Decimal(0) }
        if text.radix == 10 {
            let coefficient = String(text.digits.map { Character(UnicodeScalar($0 + 48)) })
            return Decimal(string: (text.negative ? "-" : "") + coefficient + "e" + String(text.scale),
                           locale: Locale(identifier: "en_US_POSIX"))
        }
        // Decimal has finite precision, but binary floating point must not reduce it to 53 bits.
        // Sum hexadecimal places from most to least significant to avoid an oversized coefficient
        // overflowing before a compensating negative exponent can be applied.
        let exponent = (text.digits.count - 1) * 4 + text.scale
        guard abs(exponent) <= 1024 else { return nil }
        var power = Decimal(1)
        var two = Decimal(2)
        for _ in 0..<abs(exponent) {
            var next = Decimal()
            let error = exponent >= 0
                ? NSDecimalMultiply(&next, &power, &two, .plain)
                : NSDecimalDivide(&next, &power, &two, .plain)
            guard error == .noError || error == .lossOfPrecision else { return nil }
            power = next
        }
        var result = Decimal(0)
        var sixteen = Decimal(16)
        for (index, digit) in text.digits.enumerated() {
            if digit != 0 {
                var multiplier = Decimal(Int(digit))
                var term = Decimal()
                let multiplyError = NSDecimalMultiply(&term, &power, &multiplier, .plain)
                guard multiplyError == .noError || multiplyError == .lossOfPrecision else { return nil }
                var sum = Decimal()
                let addError = NSDecimalAdd(&sum, &result, &term, .plain)
                guard addError == .noError || addError == .lossOfPrecision else { return nil }
                result = sum
            }
            if index + 1 < text.digits.count {
                var next = Decimal()
                let error = NSDecimalDivide(&next, &power, &sixteen, .plain)
                if error == .underflow { break } // Remaining places are below Decimal's range.
                guard error == .noError || error == .lossOfPrecision else { return nil }
                power = next
            }
        }
        return text.negative ? -result : result
    }

    private static func decimal(from value: Any) -> Decimal? {
        if let number = value as? NSNumber, !isBoolean(number) {
            return number.decimalValue
        }
        if let text = value as? String,
           let parsed = numericText(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return decimal(from: parsed)
        }
        return nil
    }

    private static func integer<I: FixedWidthInteger>(_ value: Any, _ type: I.Type) -> I? {
        if let number = value as? NSNumber {
            if isBoolean(number) {
                return I(number.boolValue ? 1 : 0)
            }
            if let decimalNum = number as? NSDecimalNumber {
                var truncated = Decimal()
                var copy = decimalNum.decimalValue
                let mode: NSDecimalNumber.RoundingMode = copy.isSignMinus ? .up : .down
                NSDecimalRound(&truncated, &copy, 0, mode)
                let str = "\(truncated)"
                return I(str)
            }
            if CFNumberIsFloatType(number as CFNumber) {
                let d = number.doubleValue
                guard d.isFinite else { return nil }
                return I(exactly: d.rounded(.towardZero))
            }
            let typeChar = number.objCType.pointee
            if typeChar == 67 || typeChar == 83 || typeChar == 73 || typeChar == 76 || typeChar == 81 {
                return I(exactly: number.uint64Value)
            } else {
                return I(exactly: number.int64Value)
            }
        }
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }

            if let exact = I(trimmed) { return exact }

            guard let parsed = numericText(trimmed) else { return nil }
            return integer(from: parsed, type)
        }
        return nil
    }

    #if compiler(>=5.10)
    fileprivate nonisolated(unsafe) static let isoFormatterWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    fileprivate nonisolated(unsafe) static let isoFormatterStandard: ISO8601DateFormatter = {
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
    #else
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
    #endif

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

private struct _SuperKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init(stringValue: String) { self.stringValue = stringValue; self.intValue = nil }
    init?(intValue: Int) { self.stringValue = "\(intValue)"; self.intValue = intValue }
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

    func superDecoder() throws -> Decoder {
        let key = _SuperKey(stringValue: "super")
        let value = dictionary["super"] ?? dictionary
        return _YYDecoder(value: value, codingPath: codingPath + [key])
    }
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
        let key = YYIndexKey(intValue: index)
        let result = try YYJSONValueDecoder.decode(type, from: array[index], codingPath: codingPath + [key])
        currentIndex += 1
        return result
    }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> {
        guard !isAtEnd else { throw end() }
        let index = currentIndex
        let subDecoder = _YYDecoder(value: array[index], codingPath: codingPath + [YYIndexKey(intValue: index)])
        let container = try subDecoder.container(keyedBy: type)
        currentIndex += 1
        return container
    }

    mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        guard !isAtEnd else { throw end() }
        let index = currentIndex
        let subDecoder = _YYDecoder(value: array[index], codingPath: codingPath + [YYIndexKey(intValue: index)])
        let container = try subDecoder.unkeyedContainer()
        currentIndex += 1
        return container
    }

    mutating func superDecoder() throws -> Decoder {
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
