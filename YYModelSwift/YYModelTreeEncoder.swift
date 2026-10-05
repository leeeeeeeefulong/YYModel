import Foundation

final class YYModelTreeBox: @unchecked Sendable {
    var value: YYModelJSONValue?
    var object: [String: YYModelTreeBox]?
    var array: [YYModelTreeBox]?

    var hasValue: Bool {
        value != nil || object != nil || array != nil
    }

    init(_ value: YYModelJSONValue? = nil) {
        self.value = value
    }

    func set(_ val: YYModelJSONValue) {
        self.value = val
    }

    func startObject() {
        if object == nil { object = [:] }
    }

    func startArray() {
        if array == nil { array = [] }
    }

    func materialize(emptyAsObject: Bool = true) -> YYModelJSONValue {
        if let object {
            return .object(object.mapValues { $0.materialize() })
        }
        if let array {
            return .array(array.map { $0.materialize() })
        }
        return value ?? (emptyAsObject ? .object([:]) : .null)
    }
}

final class YYModelTreeOptions: @unchecked Sendable {
    let dateEncodingStrategy: JSONEncoder.DateEncodingStrategy
    let dataEncodingStrategy: JSONEncoder.DataEncodingStrategy
    let keyEncodingStrategy: JSONEncoder.KeyEncodingStrategy
    let nonConformingFloatEncodingStrategy: JSONEncoder.NonConformingFloatEncodingStrategy

    init(dateEncodingStrategy: JSONEncoder.DateEncodingStrategy = .deferredToDate,
         dataEncodingStrategy: JSONEncoder.DataEncodingStrategy = .base64,
         keyEncodingStrategy: JSONEncoder.KeyEncodingStrategy = .useDefaultKeys,
         nonConformingFloatEncodingStrategy: JSONEncoder.NonConformingFloatEncodingStrategy = .throw) {
        self.dateEncodingStrategy = dateEncodingStrategy
        self.dataEncodingStrategy = dataEncodingStrategy
        self.keyEncodingStrategy = keyEncodingStrategy
        self.nonConformingFloatEncodingStrategy = nonConformingFloatEncodingStrategy
    }
}

// Match Foundation's Unicode Lu/Lt word-boundary behavior, including its
// initial-acronym convention. Verified with the installed Foundation oracle.
// Reference: swiftlang/swift-foundation JSONEncoder.KeyEncodingStrategy.
func yy_convertToSnakeCase(_ key: String) -> String {
    guard !key.isEmpty else { return key }
    var pieces: [String] = []
    var start = key.startIndex
    var cursor = key.index(after: start)
    while cursor < key.endIndex,
          let capital = key.rangeOfCharacter(from: .uppercaseLetters, range: cursor..<key.endIndex) {
        pieces.append(String(key[start..<capital.lowerBound]))
        guard let lower = key.rangeOfCharacter(from: .lowercaseLetters, range: capital.lowerBound..<key.endIndex) else {
            start = capital.lowerBound
            break
        }
        if lower.lowerBound == key.index(after: capital.lowerBound) {
            start = capital.lowerBound
        } else {
            let boundary = key.index(before: lower.lowerBound)
            pieces.append(String(key[capital.lowerBound..<boundary]))
            start = boundary
        }
        cursor = lower.upperBound
    }
    pieces.append(String(key[start..<key.endIndex]))
    return pieces.map { $0.lowercased() }.joined(separator: "_")
}

enum YYModelTreeBoxer {
    static func encode<T: Encodable>(_ value: T,
                                     into box: YYModelTreeBox,
                                     at codingPath: [CodingKey],
                                     options: YYModelTreeOptions,
                                     userInfo: [CodingUserInfoKey: Any]) throws {
        if let date = value as? Date {
            try encodeDate(date, into: box, at: codingPath, options: options, userInfo: userInfo)
            return
        }
        if let data = value as? Data {
            try encodeData(data, into: box, at: codingPath, options: options, userInfo: userInfo)
            return
        }
        if let float = value as? Float {
            box.set(try encodeFloat(float, at: codingPath, options: options))
            return
        }
        if let double = value as? Double {
            box.set(try encodeDouble(double, at: codingPath, options: options))
            return
        }
        if let decimal = value as? Decimal {
            guard !decimal.isNaN else {
                throw EncodingError.invalidValue(decimal, .init(codingPath: codingPath, debugDescription: "Non-finite Decimal"))
            }
            box.set(.decimal(decimal))
            return
        }
        if let string = value as? String { box.set(.string(string)); return }
        if let bool = value as? Bool { box.set(.bool(bool)); return }
        if let int = value as? Int { box.set(.signed(Int64(int))); return }
        if let int8 = value as? Int8 { box.set(.signed(Int64(int8))); return }
        if let int16 = value as? Int16 { box.set(.signed(Int64(int16))); return }
        if let int32 = value as? Int32 { box.set(.signed(Int64(int32))); return }
        if let int64 = value as? Int64 { box.set(.signed(int64)); return }
        if let uint = value as? UInt { box.set(.unsigned(UInt64(uint))); return }
        if let uint8 = value as? UInt8 { box.set(.unsigned(UInt64(uint8))); return }
        if let uint16 = value as? UInt16 { box.set(.unsigned(UInt64(uint16))); return }
        if let uint32 = value as? UInt32 { box.set(.unsigned(UInt64(uint32))); return }
        if let uint64 = value as? UInt64 { box.set(.unsigned(uint64)); return }
        if let json = value as? YYModelJSONValue {
            box.set(json)
            return
        }
        if let dict = value as? any YYModelTreeDictionary, dict.canEncodeAsObject() {
            try dict.encodeObjectToTree(into: box, at: codingPath, options: options, userInfo: userInfo)
            return
        }
        let encoder = YYModelTreeEncoder(box: box, codingPath: codingPath, options: options, userInfo: userInfo)
        try value.encode(to: encoder)

    }

    static func encodeDate(_ date: Date,
                           into box: YYModelTreeBox,
                           at codingPath: [CodingKey],
                           options: YYModelTreeOptions,
                           userInfo: [CodingUserInfoKey: Any]) throws {
        let encoder = YYModelTreeEncoder(box: box, codingPath: codingPath, options: options, userInfo: userInfo)
        switch options.dateEncodingStrategy {
        case .deferredToDate:
            try date.encode(to: encoder)
        case .secondsSince1970:
            let s = date.timeIntervalSince1970
            guard s.isFinite else { throw EncodingError.invalidValue(date, .init(codingPath: codingPath, debugDescription: "Non-finite date")) }
            box.set(.number(s))
        case .millisecondsSince1970:
            let s = date.timeIntervalSince1970 * 1000.0
            guard s.isFinite else { throw EncodingError.invalidValue(date, .init(codingPath: codingPath, debugDescription: "Non-finite date")) }
            box.set(.number(s))
        case .iso8601:
            box.set(.string(YYModelDates.shared.foundationISO8601(date)))
        case .formatted(let formatter):
            box.set(.string(formatter.string(from: date)))
        case .custom(let callback):
            try callback(date, encoder)
            if !box.hasValue { box.startObject() }
        @unknown default:
            try date.encode(to: encoder)
        }
    }

    static func encodeData(_ data: Data,
                           into box: YYModelTreeBox,
                           at codingPath: [CodingKey],
                           options: YYModelTreeOptions,
                           userInfo: [CodingUserInfoKey: Any]) throws {
        let encoder = YYModelTreeEncoder(box: box, codingPath: codingPath, options: options, userInfo: userInfo)
        switch options.dataEncodingStrategy {
        case .deferredToData:
            try data.encode(to: encoder)
        case .base64:
            box.set(.string(data.base64EncodedString()))
        case .custom(let callback):
            try callback(data, encoder)
            if !box.hasValue { box.startObject() }
        @unknown default:
            box.set(.string(data.base64EncodedString()))
        }
    }

    static func encodeDouble(_ value: Double, at path: [CodingKey], options: YYModelTreeOptions) throws -> YYModelJSONValue {
        if !value.isFinite {
            switch options.nonConformingFloatEncodingStrategy {
            case .throw:
                throw EncodingError.invalidValue(value, .init(codingPath: path, debugDescription: "Non-finite Double"))
            case .convertToString(let pos, let neg, let nan):
                if value == .infinity { return .string(pos) }
                if value == -.infinity { return .string(neg) }
                return .string(nan)
            @unknown default:
                throw EncodingError.invalidValue(value, .init(codingPath: path, debugDescription: "Non-finite Double"))
            }
        }
        return .number(value)
    }

    static func encodeFloat(_ value: Float, at path: [CodingKey], options: YYModelTreeOptions) throws -> YYModelJSONValue {
        if !value.isFinite {
            switch options.nonConformingFloatEncodingStrategy {
            case .throw:
                throw EncodingError.invalidValue(value, .init(codingPath: path, debugDescription: "Non-finite Float"))
            case .convertToString(let pos, let neg, let nan):
                if value == .infinity { return .string(pos) }
                if value == -.infinity { return .string(neg) }
                return .string(nan)
            @unknown default:
                throw EncodingError.invalidValue(value, .init(codingPath: path, debugDescription: "Non-finite Float"))
            }
        }
        return .float(value)
    }
}

final class YYModelTreeEncoder: Encoder {
    let box: YYModelTreeBox
    var codingPath: [CodingKey]
    let options: YYModelTreeOptions
    var userInfo: [CodingUserInfoKey: Any]

    init(box: YYModelTreeBox = YYModelTreeBox(),
         codingPath: [CodingKey] = [],
         options: YYModelTreeOptions = YYModelTreeOptions(),
         userInfo: [CodingUserInfoKey: Any] = [:]) {
        self.box = box
        self.codingPath = codingPath
        self.options = options
        self.userInfo = userInfo
    }

    var value: YYModelJSONValue { box.materialize(emptyAsObject: false) }

    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        box.startObject()
        return KeyedEncodingContainer(YYModelTreeKeyedEncoder<Key>(box: box, codingPath: codingPath, options: options, userInfo: userInfo))
    }

    func unkeyedContainer() -> UnkeyedEncodingContainer {
        box.startArray()
        return YYModelTreeUnkeyedEncoder(box: box, codingPath: codingPath, options: options, userInfo: userInfo)
    }

    func singleValueContainer() -> SingleValueEncodingContainer {
        YYModelTreeSingleEncoder(box: box, codingPath: codingPath, options: options, userInfo: userInfo)
    }
}

struct YYModelTreeKeyedEncoder<Key: CodingKey>: KeyedEncodingContainerProtocol {
    let box: YYModelTreeBox
    var codingPath: [CodingKey]
    let options: YYModelTreeOptions
    var userInfo: [CodingUserInfoKey: Any]

    private func resolveKey(_ key: any CodingKey) -> String {
        switch options.keyEncodingStrategy {
        case .useDefaultKeys:
            return key.stringValue
        case .convertToSnakeCase:
            return yy_convertToSnakeCase(key.stringValue)
        case .custom(let callback):
            return callback(codingPath + [key]).stringValue
        @unknown default:
            return key.stringValue
        }
    }

    mutating func encodeNil(forKey key: Key) throws {
        let physical = resolveKey(key)
        box.object?[physical] = YYModelTreeBox(.null)
    }

    mutating func encode(_ value: Bool, forKey key: Key) throws { box.object?[resolveKey(key)] = YYModelTreeBox(.bool(value)) }
    mutating func encode(_ value: String, forKey key: Key) throws { box.object?[resolveKey(key)] = YYModelTreeBox(.string(value)) }
    mutating func encode(_ value: Double, forKey key: Key) throws {
        let node = try YYModelTreeBoxer.encodeDouble(value, at: codingPath + [key], options: options)
        box.object?[resolveKey(key)] = YYModelTreeBox(node)
    }
    mutating func encode(_ value: Float, forKey key: Key) throws {
        let node = try YYModelTreeBoxer.encodeFloat(value, at: codingPath + [key], options: options)
        box.object?[resolveKey(key)] = YYModelTreeBox(node)
    }
    mutating func encode(_ value: Int, forKey key: Key) throws { box.object?[resolveKey(key)] = YYModelTreeBox(.signed(Int64(value))) }
    mutating func encode(_ value: Int8, forKey key: Key) throws { box.object?[resolveKey(key)] = YYModelTreeBox(.signed(Int64(value))) }
    mutating func encode(_ value: Int16, forKey key: Key) throws { box.object?[resolveKey(key)] = YYModelTreeBox(.signed(Int64(value))) }
    mutating func encode(_ value: Int32, forKey key: Key) throws { box.object?[resolveKey(key)] = YYModelTreeBox(.signed(Int64(value))) }
    mutating func encode(_ value: Int64, forKey key: Key) throws { box.object?[resolveKey(key)] = YYModelTreeBox(.signed(value)) }
    mutating func encode(_ value: UInt, forKey key: Key) throws { box.object?[resolveKey(key)] = YYModelTreeBox(.unsigned(UInt64(value))) }
    mutating func encode(_ value: UInt8, forKey key: Key) throws { box.object?[resolveKey(key)] = YYModelTreeBox(.unsigned(UInt64(value))) }
    mutating func encode(_ value: UInt16, forKey key: Key) throws { box.object?[resolveKey(key)] = YYModelTreeBox(.unsigned(UInt64(value))) }
    mutating func encode(_ value: UInt32, forKey key: Key) throws { box.object?[resolveKey(key)] = YYModelTreeBox(.unsigned(UInt64(value))) }
    mutating func encode(_ value: UInt64, forKey key: Key) throws { box.object?[resolveKey(key)] = YYModelTreeBox(.unsigned(value)) }

    mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
        let physical = resolveKey(key)
        let childBox = YYModelTreeBox()
        box.object?[physical] = childBox
        try YYModelTreeBoxer.encode(value, into: childBox, at: codingPath + [key], options: options, userInfo: userInfo)
    }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> {
        let physical = resolveKey(key)
        let childBox = box.object?[physical] ?? YYModelTreeBox()
        childBox.startObject()
        box.object?[physical] = childBox
        return KeyedEncodingContainer(YYModelTreeKeyedEncoder<NestedKey>(box: childBox, codingPath: codingPath + [key], options: options, userInfo: userInfo))
    }

    mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        let physical = resolveKey(key)
        let childBox = box.object?[physical] ?? YYModelTreeBox()
        childBox.startArray()
        box.object?[physical] = childBox
        return YYModelTreeUnkeyedEncoder(box: childBox, codingPath: codingPath + [key], options: options, userInfo: userInfo)
    }

    mutating func superEncoder() -> Encoder {
        let childBox = YYModelTreeBox()
        box.object?[resolveKey(YYModelCodingKey("super"))] = childBox
        return YYModelTreeEncoder(box: childBox, codingPath: codingPath + [YYModelCodingKey("super")], options: options, userInfo: userInfo)
    }

    mutating func superEncoder(forKey key: Key) -> Encoder {
        let physical = resolveKey(key)
        let childBox = YYModelTreeBox()
        box.object?[physical] = childBox
        return YYModelTreeEncoder(box: childBox, codingPath: codingPath + [key], options: options, userInfo: userInfo)
    }
}

private struct YYModelTreeIndexKey: CodingKey {
    let intValue: Int?
    var stringValue: String { "Index \(intValue!)" }
    init(_ index: Int) { intValue = index }
    init?(intValue: Int) { self.init(intValue) }
    init?(stringValue: String) { return nil }
}

struct YYModelTreeUnkeyedEncoder: UnkeyedEncodingContainer {
    let box: YYModelTreeBox
    var codingPath: [CodingKey]
    let options: YYModelTreeOptions
    var userInfo: [CodingUserInfoKey: Any]

    var count: Int { box.array?.count ?? 0 }

    mutating func encodeNil() throws { box.array?.append(YYModelTreeBox(.null)) }
    mutating func encode(_ value: Bool) throws { box.array?.append(YYModelTreeBox(.bool(value))) }
    mutating func encode(_ value: String) throws { box.array?.append(YYModelTreeBox(.string(value))) }
    mutating func encode(_ value: Double) throws {
        let index = count
        let node = try YYModelTreeBoxer.encodeDouble(value, at: codingPath + [YYModelTreeIndexKey(index)], options: options)
        box.array?.append(YYModelTreeBox(node))
    }
    mutating func encode(_ value: Float) throws {
        let index = count
        let node = try YYModelTreeBoxer.encodeFloat(value, at: codingPath + [YYModelTreeIndexKey(index)], options: options)
        box.array?.append(YYModelTreeBox(node))
    }
    mutating func encode(_ value: Int) throws { box.array?.append(YYModelTreeBox(.signed(Int64(value)))) }
    mutating func encode(_ value: Int8) throws { box.array?.append(YYModelTreeBox(.signed(Int64(value)))) }
    mutating func encode(_ value: Int16) throws { box.array?.append(YYModelTreeBox(.signed(Int64(value)))) }
    mutating func encode(_ value: Int32) throws { box.array?.append(YYModelTreeBox(.signed(Int64(value)))) }
    mutating func encode(_ value: Int64) throws { box.array?.append(YYModelTreeBox(.signed(value))) }
    mutating func encode(_ value: UInt) throws { box.array?.append(YYModelTreeBox(.unsigned(UInt64(value)))) }
    mutating func encode(_ value: UInt8) throws { box.array?.append(YYModelTreeBox(.unsigned(UInt64(value)))) }
    mutating func encode(_ value: UInt16) throws { box.array?.append(YYModelTreeBox(.unsigned(UInt64(value)))) }
    mutating func encode(_ value: UInt32) throws { box.array?.append(YYModelTreeBox(.unsigned(UInt64(value)))) }
    mutating func encode(_ value: UInt64) throws { box.array?.append(YYModelTreeBox(.unsigned(value))) }

    mutating func encode<T: Encodable>(_ value: T) throws {
        let index = count
        let childBox = YYModelTreeBox()
        box.array?.append(childBox)
        try YYModelTreeBoxer.encode(value, into: childBox, at: codingPath + [YYModelTreeIndexKey(index)], options: options, userInfo: userInfo)
    }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> {
        let index = count
        let childBox = YYModelTreeBox()
        childBox.startObject()
        box.array?.append(childBox)
        return KeyedEncodingContainer(YYModelTreeKeyedEncoder<NestedKey>(box: childBox, codingPath: codingPath + [YYModelTreeIndexKey(index)], options: options, userInfo: userInfo))
    }

    mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        let index = count
        let childBox = YYModelTreeBox()
        childBox.startArray()
        box.array?.append(childBox)
        return YYModelTreeUnkeyedEncoder(box: childBox, codingPath: codingPath + [YYModelTreeIndexKey(index)], options: options, userInfo: userInfo)
    }

    mutating func superEncoder() -> Encoder {
        let index = count
        let childBox = YYModelTreeBox()
        box.array?.append(childBox)
        return YYModelTreeEncoder(box: childBox, codingPath: codingPath + [YYModelTreeIndexKey(index)], options: options, userInfo: userInfo)
    }
}

struct YYModelTreeSingleEncoder: SingleValueEncodingContainer {
    let box: YYModelTreeBox
    var codingPath: [CodingKey]
    let options: YYModelTreeOptions
    var userInfo: [CodingUserInfoKey: Any]

    mutating func encodeNil() throws { box.set(.null) }
    mutating func encode(_ value: Bool) throws { box.set(.bool(value)) }
    mutating func encode(_ value: String) throws { box.set(.string(value)) }
    mutating func encode(_ value: Double) throws {
        box.set(try YYModelTreeBoxer.encodeDouble(value, at: codingPath, options: options))
    }
    mutating func encode(_ value: Float) throws {
        box.set(try YYModelTreeBoxer.encodeFloat(value, at: codingPath, options: options))
    }
    mutating func encode(_ value: Int) throws { box.set(.signed(Int64(value))) }
    mutating func encode(_ value: Int8) throws { box.set(.signed(Int64(value))) }
    mutating func encode(_ value: Int16) throws { box.set(.signed(Int64(value))) }
    mutating func encode(_ value: Int32) throws { box.set(.signed(Int64(value))) }
    mutating func encode(_ value: Int64) throws { box.set(.signed(value)) }
    mutating func encode(_ value: UInt) throws { box.set(.unsigned(UInt64(value))) }
    mutating func encode(_ value: UInt8) throws { box.set(.unsigned(UInt64(value))) }
    mutating func encode(_ value: UInt16) throws { box.set(.unsigned(UInt64(value))) }
    mutating func encode(_ value: UInt32) throws { box.set(.unsigned(UInt64(value))) }
    mutating func encode(_ value: UInt64) throws { box.set(.unsigned(value)) }

    mutating func encode<T: Encodable>(_ value: T) throws {
        try YYModelTreeBoxer.encode(value, into: box, at: codingPath, options: options, userInfo: userInfo)
    }
}

protocol YYModelTreeDictionary {
    func canEncodeAsObject() -> Bool
    func encodeObjectToTree(into box: YYModelTreeBox,
                            at codingPath: [CodingKey],
                            options: YYModelTreeOptions,
                            userInfo: [CodingUserInfoKey: Any]) throws
}

extension Dictionary: YYModelTreeDictionary where Value: Encodable {
    func canEncodeAsObject() -> Bool {
        YYModelDictionaryKey.isSupported(Key.self)
    }

    func encodeObjectToTree(into box: YYModelTreeBox,
                            at codingPath: [CodingKey],
                            options: YYModelTreeOptions,
                            userInfo: [CodingUserInfoKey: Any]) throws {
        box.startObject()
        for (k, v) in self {
            guard let name = YYModelDictionaryKey.name(k) else {
                throw EncodingError.invalidValue(
                    k,
                    .init(codingPath: codingPath, debugDescription: "Dictionary key \(k) is not representable as JSON string")
                )
            }
            let childKey: CodingKey
            if let intKey = k as? Int {
                childKey = YYModelCodingKey(preserving: name, intValue: intKey)
            } else if #available(iOS 15.4, macOS 12.3, tvOS 15.4, watchOS 8.5, *),
                      let representable = k as? any CodingKeyRepresentable {
                childKey = representable.codingKey
            } else {
                childKey = YYModelCodingKey(name)
            }
            let childBox = YYModelTreeBox()
            box.object?[name] = childBox
            try YYModelTreeBoxer.encode(v, into: childBox, at: codingPath + [childKey], options: options, userInfo: userInfo)
        }
    }
}
