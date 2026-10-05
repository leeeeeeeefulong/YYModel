//
//  YYJSONDecoder.swift
//  YYModel
//
//  Decodes plain Swift Codable values. Models do not conform to a YYModel protocol.
//  Native mode delegates directly to Foundation. Enhanced modes select their
//  container adapter before initializing the model; they never retry a model.
//
//  URL and raw-value enums have no zero value: keep those properties optional
//  when the key may be absent. A value that cannot be coerced throws.
//

import Foundation

/// Enhanced Data parsing policy. Native mode always uses Foundation directly.
public enum YYJSONNumberParsingStrategy: Sendable {
    /// Detect exact Decimal support once; use integer-token parsing on older Foundation.
    case automatic
    /// Use Foundation JSONDecoder, including its platform-specific number behavior.
    case foundation
    /// Preserve integer literals through JSONSerialization's signed/unsigned NSNumber.
    /// Fractional/exponent tokens retain that parser's precision, including on old OSes.
    case integerTokens
}

/// Ordinary Decodable values. Choose `.native` for Foundation semantics or
/// `.compatible` for field-local YY conversions and external rules. The no-argument
/// initializer preserves published 2.x zero-fill/date behavior through `.legacy`.
/// Configure before sharing; userInfo and captured hook state require caller synchronization.
public struct YYJSONDecoder: @unchecked Sendable {
    public let mode: YYJSONMode
    public let rules: YYJSONRules
    public var dateDecodingStrategy: JSONDecoder.DateDecodingStrategy = .deferredToDate
    public var dataDecodingStrategy: JSONDecoder.DataDecodingStrategy = .base64
    public var keyDecodingStrategy: JSONDecoder.KeyDecodingStrategy = .useDefaultKeys
    public var nonConformingFloatDecodingStrategy: JSONDecoder.NonConformingFloatDecodingStrategy = .throw
    public var userInfo: [CodingUserInfoKey: YYJSONUserInfoValue] = [:]
    public var numberParsingStrategy: YYJSONNumberParsingStrategy = .automatic
    /// Foundation's JSON5 support, forwarded verbatim (iOS 15 / macOS 12+).
    /// Enables single-quoted and multi-line strings, `//` and `/* */` comments,
    /// hexadecimal numbers, leading/trailing decimal points and an explicit plus sign.
    /// YYModelSwift's own tolerant lexer covers none of the comment/quote forms,
    /// so this is the only way to accept them. Defaults to `false`, as in Foundation.
    public var allowsJSON5: Bool = false
    /// Foundation's brace-less top-level object support, forwarded verbatim
    /// (iOS 15 / macOS 12+). Compatible with both JSON5 and plain JSON modes.
    /// Defaults to `false`, as in Foundation.
    public var assumesTopLevelDictionary: Bool = false
    public init(mode: YYJSONMode = .legacy, rules: YYJSONRules = .init()) { self.mode = mode; self.rules = rules }

    private func foundationDecoder(keyMapState: YYKeyMapState? = nil) -> JSONDecoder {
        let decoder = JSONDecoder()
        if case .deferredToDate = dateDecodingStrategy {} else { decoder.dateDecodingStrategy = dateDecodingStrategy }
        if case .base64 = dataDecodingStrategy {} else { decoder.dataDecodingStrategy = dataDecodingStrategy }
        if let keyMapState {
            switch keyDecodingStrategy {
            case .useDefaultKeys:
                break
            case .convertFromSnakeCase:
                decoder.keyDecodingStrategy = .custom { path in
                    let physical = path.last!.stringValue
                    let logical = yy_bridgeSnakeCase(physical)
                    let parent = path.dropLast().map(\.stringValue)
                    keyMapState.record(parent: parent, logical: logical, physical: physical)
                    return YYModelCodingKey(logical)
                }
            case .custom(let callback):
                decoder.keyDecodingStrategy = .custom { path in
                    let physical = path.last!.stringValue
                    let key = callback(path)
                    let parent = path.dropLast().map(\.stringValue)
                    keyMapState.record(parent: parent, logical: key.stringValue, physical: physical)
                    return key
                }
            @unknown default:
                decoder.keyDecodingStrategy = keyDecodingStrategy
            }
        } else {
            if case .useDefaultKeys = keyDecodingStrategy {} else { decoder.keyDecodingStrategy = keyDecodingStrategy }
        }
        if case .throw = nonConformingFloatDecodingStrategy {} else { decoder.nonConformingFloatDecodingStrategy = nonConformingFloatDecodingStrategy }
        if !userInfo.isEmpty { decoder.userInfo = userInfo }
        if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) {
            if allowsJSON5 { decoder.allowsJSON5 = true }
            if assumesTopLevelDictionary { decoder.assumesTopLevelDictionary = true }
        }
        return decoder
    }
    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        if mode == .native {
            guard rules.isEmpty else { throw YYJSONRulesError.rule(.rulesRequireCompatibleMode, T.self, "YY rules require compatible mode") }
            return try foundationDecoder().decode(type, from: data)
        }
        let useIntegerTokens: Bool
        switch numberParsingStrategy {
        case .automatic: useIntegerTokens = !YYModelCapability.foundationExactDecimal
        case .foundation: useIntegerTokens = false
        case .integerTokens: useIntegerTokens = true
        }
        if useIntegerTokens {
            let object = try YYModelJSONInput.nativeObject(from: data, allowsJSON5: allowsJSON5,
                                                          assumesTopLevelDictionary: assumesTopLevelDictionary)
            return try decodeRaw(type, from: object)
        }
        let keyMapState = YYKeyMapState()
        let decoder = foundationDecoder(keyMapState: keyMapState)
        let context = YYJSONContext(mode: mode, rules: rules, decoder: foundationDecoder())
        decoder.userInfo[YYJSONContext.key] = context
        decoder.userInfo[YYModelJSONInput.key] = YYModelJSONInput(
            data: data,
            allowsJSON5: allowsJSON5,
            assumesTopLevelDictionary: assumesTopLevelDictionary,
            keyMapState: keyMapState,
            useFoundationNumbers: true
        )
        return try decoder.decode(YYModelDecodingBox<T>.self, from: data).value
    }
    public func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        try decode(type, from: Data(json.utf8))
    }
    /// Compatible mode consumes an already parsed Foundation object directly.
    /// Native mode must serialize it to Data because Foundation exposes no object entry point.
    public func decode<T: Decodable>(_ type: T.Type, from object: Any) throws -> T {
        if let data = object as? Data { return try decode(type, from: data) }
        if let text = object as? String { return try decode(type, from: text) }
        if mode == .native {
            guard rules.isEmpty else { throw YYJSONRulesError.rule(.rulesRequireCompatibleMode, T.self, "YY rules require compatible mode") }
            return try decode(type, from: JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed]))
        }
        return try decodeRaw(type, from: object)
    }
    private func decodeRaw<T: Decodable>(_ type: T.Type, from object: Any) throws -> T {
        let context = YYJSONContext(mode: mode, rules: rules, decoder: foundationDecoder())
        let raw = context.rawDecoder(object, path: [], userInfo: userInfo)
        return try YYModelDecode.value(type, from: raw, date: context.defaults.date)
    }

    public func decodeWithReport<T: Decodable>(_ type: T.Type, from data: Data) throws -> (value: T, report: YYModelLossReport) {
        let report = YYModelLossReport()
        var copy = self
        copy.userInfo[YYModelLossReport.key] = report
        let value = try copy.decode(type, from: data)
        return (value, report)
    }
    public func decodeWithReport<T: Decodable>(_ type: T.Type, from json: String) throws -> (value: T, report: YYModelLossReport) {
        try decodeWithReport(type, from: Data(json.utf8))
    }
    public func decodeWithReport<T: Decodable>(_ type: T.Type, from object: Any) throws -> (value: T, report: YYModelLossReport) {
        let report = YYModelLossReport()
        var copy = self
        copy.userInfo[YYModelLossReport.key] = report
        let value = try copy.decode(type, from: object)
        return (value, report)
    }
}

enum YYJSONValueDecoder {
    private static func nilValue<T>(_ type: T.Type) -> T? {
        if let optType = type as? ExpressibleByNilLiteral.Type {
            return (optType.init(nilLiteral: ()) as! T)
        }
        return nil
    }

    static func decode<T: Decodable>(_ type: T.Type, from value: Any, codingPath: [CodingKey], userInfo: [CodingUserInfoKey: Any]? = nil) throws -> T {
        if value is NSNull {
            if let nilVal = nilValue(type) { return nilVal }
            if let zero = zero(type) { return zero }
            throw DecodingError.valueNotFound(type, context(codingPath, "null for \(type)"))
        }
        if let coerced = coerce(value, to: type, codingPath: codingPath, userInfo: userInfo) {
            return coerced
        }
        if isLeaf(type) {
            throw DecodingError.typeMismatch(type, context(codingPath, "cannot coerce \(Swift.type(of: value)) to \(type)"))
        }
        let decoder = _YYDecoder(value: value, codingPath: codingPath)
        if let userInfo { decoder.userInfo = userInfo }
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

    static func coerce<T: Decodable>(_ value: Any, to type: T.Type, codingPath: [CodingKey] = [], userInfo: [CodingUserInfoKey: Any]? = nil) -> T? {
        let report = userInfo?[YYModelCoercionReport.key] as? YYModelCoercionReport
        if T.self == String.self {
            if let text = string(from: value) {
                if value is NSNumber {
                    report?.record(codingPath: codingPath, sourceCategory: "number", targetType: "String", reason: "number-to-string")
                }
                return text as? T
            }
            return nil
        }
        if T.self == Bool.self {
            if let number = value as? NSNumber {
                if isBoolean(number) { return number.boolValue as? T }
                if number.doubleValue == 0 {
                    report?.record(codingPath: codingPath, sourceCategory: "number", targetType: "Bool", reason: "number-to-bool")
                    return false as? T
                }
                if number.doubleValue == 1 {
                    report?.record(codingPath: codingPath, sourceCategory: "number", targetType: "Bool", reason: "number-to-bool")
                    return true as? T
                }
                return nil
            }
            if let text = value as? String {
                switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                case "true", "yes", "1":
                    report?.record(codingPath: codingPath, sourceCategory: "string", targetType: "Bool", reason: "string-to-bool")
                    return true as? T
                case "false", "no", "0":
                    report?.record(codingPath: codingPath, sourceCategory: "string", targetType: "Bool", reason: "string-to-bool")
                    return false as? T
                default: return nil
                }
            }
            return nil
        }
        if T.self == Double.self {
            if let res = double(from: value) {
                if value is String {
                    report?.record(codingPath: codingPath, sourceCategory: "string", targetType: "Double", reason: "string-to-float")
                }
                return res as? T
            }
            return nil
        }
        if T.self == Float.self {
            if let res = floating(from: value, Float.self) {
                if value is String {
                    report?.record(codingPath: codingPath, sourceCategory: "string", targetType: "Float", reason: "string-to-float")
                }
                return res as? T
            }
            return nil
        }
        if T.self == CGFloat.self {
            if let res = floating(from: value, CGFloat.self) {
                if value is String {
                    report?.record(codingPath: codingPath, sourceCategory: "string", targetType: "CGFloat", reason: "string-to-float")
                }
                return res as? T
            }
            return nil
        }
        if T.self == Decimal.self { return decimal(from: value) as? T }
        if T.self == Int.self { return integer(value, Int.self, codingPath: codingPath, report: report) as? T }
        if T.self == Int8.self { return integer(value, Int8.self, codingPath: codingPath, report: report) as? T }
        if T.self == Int16.self { return integer(value, Int16.self, codingPath: codingPath, report: report) as? T }
        if T.self == Int32.self { return integer(value, Int32.self, codingPath: codingPath, report: report) as? T }
        if T.self == Int64.self { return integer(value, Int64.self, codingPath: codingPath, report: report) as? T }
        if T.self == UInt.self { return integer(value, UInt.self, codingPath: codingPath, report: report) as? T }
        if T.self == UInt8.self { return integer(value, UInt8.self, codingPath: codingPath, report: report) as? T }
        if T.self == UInt16.self { return integer(value, UInt16.self, codingPath: codingPath, report: report) as? T }
        if T.self == UInt32.self { return integer(value, UInt32.self, codingPath: codingPath, report: report) as? T }
        if T.self == UInt64.self { return integer(value, UInt64.self, codingPath: codingPath, report: report) as? T }
        if T.self == URL.self {
            guard let text = value as? String, let url = URL(string: text), !text.isEmpty else { return nil }
            return url as? T
        }
        if T.self == Date.self {
            if let date = YYModelDates.shared.date(value, strategy: .automatic, report: report, codingPath: codingPath) { return date as? T }
            return nil
        }
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
        let result: Double?
        if let number = value as? NSNumber {
            if isBoolean(number) {
                result = number.boolValue ? 1 : 0
            } else if let decimalNum = number as? NSDecimalNumber {
                // P2-4: dual snapshot carries the literal-parsed Double invisibly.
                // Return it directly for bit-identical results; otherwise parse the
                // exact decimal text (L1), which rounds correctly vs lossy doubleValue.
                if let node = YYModelNumberBoundary.node(from: decimalNum) {
                    result = node.doubleProjection
                } else {
                    result = Double(number.stringValue) ?? number.doubleValue
                }
            } else {
                result = number.doubleValue
            }
        } else if let text = value as? String {
            result = Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            result = nil
        }
        guard let result, result.isFinite else { return nil }
        return result
    }

    private static func floating<F: BinaryFloatingPoint>(from value: Any, _ type: F.Type) -> F? {
        if F.self == Float.self {
            let direct: Float?
            if let decimal = value as? NSDecimalNumber {
                direct = YYModelNumberBoundary.node(from: decimal)?.floatProjection ?? Float(decimal.stringValue)
            } else if let text = value as? String {
                direct = Float(text.trimmingCharacters(in: .whitespacesAndNewlines))
            } else { direct = nil }
            if let direct { return direct.isFinite ? direct as? F : nil }
        }
        guard let number = double(from: value) else { return nil }
        let result = F(number)
        return result.isFinite ? result : nil
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
            let decimal = number.decimalValue
            return decimal.isNaN ? nil : decimal
        }
        if let text = value as? String,
           let parsed = numericText(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return decimal(from: parsed)
        }
        return nil
    }

    private static func integer<I: FixedWidthInteger>(_ value: Any, _ type: I.Type, codingPath: [CodingKey] = [], report: YYModelCoercionReport? = nil) -> I? {
        if let number = value as? NSNumber {
            if isBoolean(number) {
                report?.record(codingPath: codingPath, sourceCategory: "boolean", targetType: "\(type)", reason: "boolean-to-integer")
                return I(number.boolValue ? 1 : 0)
            }
            if let decimalNum = number as? NSDecimalNumber {
                var truncated = Decimal()
                var copy = decimalNum.decimalValue
                let mode: NSDecimalNumber.RoundingMode = copy.isSignMinus ? .up : .down
                NSDecimalRound(&truncated, &copy, 0, mode)
                if truncated != copy {
                    report?.record(codingPath: codingPath, sourceCategory: "number", targetType: "\(type)", reason: "float-truncated-to-integer")
                }
                let str = "\(truncated)"
                return I(str)
            }
            if CFNumberIsFloatType(number as CFNumber) {
                let d = number.doubleValue
                guard d.isFinite else { return nil }
                let rounded = d.rounded(.towardZero)
                if rounded != d {
                    report?.record(codingPath: codingPath, sourceCategory: "number", targetType: "\(type)", reason: "float-truncated-to-integer")
                }
                return I(exactly: rounded)
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

            if let exact = I(trimmed) {
                report?.record(codingPath: codingPath, sourceCategory: "string", targetType: "\(type)", reason: "string-to-integer")
                return exact
            }

            guard let parsed = numericText(trimmed) else { return nil }
            if let res = integer(from: parsed, type) {
                report?.record(codingPath: codingPath, sourceCategory: "string", targetType: "\(type)", reason: "string-to-integer")
                return res
            }
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

final class _YYDecoder: Decoder {
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
        var candidates: [String: (physicalKey: String, value: Any)] = [:]
        let context = userInfo[YYJSONContext.key] as? YYJSONContext
        for (key, value) in dictionary {
            let transformed = context?.decodingKey(key, at: codingPath) ?? key
            if let existing = candidates[transformed] {
                let replace: Bool
                if key == transformed && existing.physicalKey != transformed {
                    replace = true
                } else if existing.physicalKey == transformed {
                    replace = false
                } else {
                    replace = key.utf8.lexicographicallyPrecedes(existing.physicalKey.utf8)
                }
                if replace {
                    candidates[transformed] = (key, value)
                }
            } else {
                candidates[transformed] = (key, value)
            }
        }
        var keys: [String: Any] = [:]
        for (k, v) in candidates {
            keys[k] = v.value
        }
        return KeyedDecodingContainer(YYKeyedContainer(decoder: self, dictionary: keys))
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
        return try YYJSONValueDecoder.decode(type, from: value, codingPath: path, userInfo: decoder.userInfo)
    }

    func decodeIfPresent<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T? {
        guard let value = dictionary[key.stringValue], !(value is NSNull) else { return nil }
        return try YYJSONValueDecoder.decode(type, from: value, codingPath: codingPath + [key], userInfo: decoder.userInfo)
    }

    func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> {
        try nestedDecoder(forKey: key).container(keyedBy: type)
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        try nestedDecoder(forKey: key).unkeyedContainer()
    }

    func superDecoder() throws -> Decoder {
        let key = _SuperKey(stringValue: "super")
        let value = dictionary
        let child = _YYDecoder(value: value, codingPath: codingPath + [key]); child.userInfo = decoder.userInfo; return child
    }
    func superDecoder(forKey key: Key) throws -> Decoder { try nestedDecoder(forKey: key) }

    private func nestedDecoder(forKey key: Key) throws -> _YYDecoder {
        guard let value = dictionary[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath, debugDescription: key.stringValue))
        }
        let child = _YYDecoder(value: value, codingPath: codingPath + [key]); child.userInfo = decoder.userInfo; return child
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
        let result = try YYJSONValueDecoder.decode(type, from: array[index], codingPath: codingPath + [key], userInfo: decoder.userInfo)
        currentIndex += 1
        return result
    }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> {
        guard !isAtEnd else { throw end() }
        let index = currentIndex
        let subDecoder = _YYDecoder(value: array[index], codingPath: codingPath + [YYIndexKey(intValue: index)])
        subDecoder.userInfo = decoder.userInfo
        let container = try subDecoder.container(keyedBy: type)
        currentIndex += 1
        return container
    }

    mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        guard !isAtEnd else { throw end() }
        let index = currentIndex
        let subDecoder = _YYDecoder(value: array[index], codingPath: codingPath + [YYIndexKey(intValue: index)])
        subDecoder.userInfo = decoder.userInfo
        let container = try subDecoder.unkeyedContainer()
        currentIndex += 1
        return container
    }

    mutating func superDecoder() throws -> Decoder {
        guard !isAtEnd else { throw end() }
        let index = currentIndex
        currentIndex += 1
        let child = _YYDecoder(value: array[index], codingPath: codingPath + [YYIndexKey(intValue: index)]); child.userInfo = decoder.userInfo; return child
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
        try YYJSONValueDecoder.decode(type, from: decoder.value, codingPath: codingPath, userInfo: decoder.userInfo)
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
