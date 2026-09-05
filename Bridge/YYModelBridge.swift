//
//  YYModelBridge.swift
//  YYModel iOS 27 Bridge
//
//  Bridges YYModel (ObjC) with Codable (Swift).
//  New code uses Codable; old ObjC models continue using YYModel.
//
//  Usage:
//    // In new Swift code — use Codable directly:
//    struct User: Codable { ... }
//    let user = try JSONDecoder().decode(User.self, from: data)
//
//    // Bridge existing ObjC models:
//    let oldUser = YYModelBridge.decode(OldUser.self, from: jsonString)
//
//    // Mixed container (ObjC model inside Codable):
//    struct Response: Codable {
//        let users: [OldUser]  // ObjC model auto-bridged
//    }
//

import Foundation

// MARK: - YYModelBridge

/// Namespace for YYModel ↔ Codable bridge utilities.
public enum YYModelBridge {

    // MARK: Decode (JSON → ObjC Model)

    /// Decode a JSON string into an ObjC model using YYModel.
    public static func decode<T: NSObject>(_ type: T.Type, from json: String) -> T?
        where T: YYModel
    {
        return T.yy_model(withJSON: json)
    }

    /// Decode a JSON dictionary into an ObjC model using YYModel.
    public static func decode<T: NSObject>(_ type: T.Type, from dict: [String: Any]) -> T?
        where T: YYModel
    {
        return T.yy_model(withDictionary: dict)
    }

    /// Decode JSON data into an ObjC model using YYModel.
    public static func decode<T: NSObject>(_ type: T.Type, from data: Data) -> T?
        where T: YYModel
    {
        return T.yy_model(withJSON: data)
    }

    // MARK: Decode Array

    /// Decode a JSON array into an array of ObjC models.
    public static func decodeArray<T: NSObject>(_ type: T.Type, from json: Any) -> [T]?
        where T: YYModel
    {
        return NSArray.yy_modelArray(with: T.self, json: json) as? [T]
    }

    // MARK: Encode (ObjC Model → JSON)

    /// Encode an ObjC model to a JSON dictionary.
    public static func encodeToJSON(_ model: NSObject) -> [String: Any]? {
        return model.yy_modelToJSONObject() as? [String: Any]
    }

    /// Encode an ObjC model to JSON data.
    public static func encodeToData(_ model: NSObject) -> Data? {
        return model.yy_modelToJSONData()
    }

    /// Encode an ObjC model to a JSON string.
    public static func encodeToString(_ model: NSObject) -> String? {
        return model.yy_modelToJSONString()
    }
}

// MARK: - Codable → YYModel Fallback

/// When a Codable type also conforms to ObjCModelBridge, you can decode
/// from either Codable or YYModel transparently.
public protocol ObjCModelBridge {
    /// Try to decode from a dictionary using YYModel as fallback.
    static func from(dictionary: [String: Any]) -> Self?
}

extension ObjCModelBridge where Self: NSObject & YYModel {
    public static func from(dictionary: [String: Any]) -> Self? {
        return Self.yy_model(withDictionary: dictionary)
    }
}

// MARK: - Codable Wrapper for ObjC Models

/// Wraps an ObjC YYModel object in a Codable-compatible envelope.
/// Use this when you need to pass ObjC models through Codable pipelines.
///
/// Example:
///   struct Response: Codable {
///       let data: YYModelWrapper<OldUser>
///   }
///
public struct YYModelWrapper<T: NSObject & YYModel>: Codable {
    public let value: T?

    public init(_ value: T?) {
        self.value = value
    }

    // Decode from a JSON dictionary
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKeys.self)
        var dict: [String: Any] = [:]
        for key in container.allKeys {
            if let val = try? container.decodeIfPresent(String.self, forKey: key) {
                dict[key.stringValue] = val
            } else if let val = try? container.decodeIfPresent(Int.self, forKey: key) {
                dict[key.stringValue] = val
            } else if let val = try? container.decodeIfPresent(Double.self, forKey: key) {
                dict[key.stringValue] = val
            } else if let val = try? container.decodeIfPresent(Bool.self, forKey: key) {
                dict[key.stringValue] = val
            }
        }
        self.value = T.yy_model(withDictionary: dict)
    }

    // Encode to a JSON dictionary
    public func encode(to encoder: Encoder) throws {
        guard let model = value,
              let json = model.yy_modelToJSONObject() as? [String: Any] else { return }
        var container = encoder.container(keyedBy: DynamicCodingKeys.self)
        for (key, val) in json {
            if let codingKey = DynamicCodingKeys(stringValue: key) {
                if let s = val as? String {
                    try container.encode(s, forKey: codingKey)
                } else if let i = val as? Int {
                    try container.encode(i, forKey: codingKey)
                } else if let d = val as? Double {
                    try container.encode(d, forKey: codingKey)
                } else if let b = val as? Bool {
                    try container.encode(b, forKey: codingKey)
                }
            }
        }
    }
}

/// Dynamic coding keys for arbitrary string keys.
private struct DynamicCodingKeys: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

// MARK: - Convenience: Decode Any Codable from YYModel JSON

extension Decodable {
    /// Try to decode this Codable type from a YYModel-compatible JSON source.
    ///
    ///     let user: User? = User.from(json: jsonString)
    ///     let user: User? = User.from(dictionary: dict)
    ///
    public static func from(json string: String) -> Self? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    public static func from(dictionary dict: [String: Any]) -> Self? {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}

// MARK: - NSCoding → Codable Bridge

/// For types that need both NSCoding and Codable conformance.
/// Use this when migrating archived data from YYModel to Codable.
public protocol LegacyArchivable: NSObject & NSCoding & Codable {
    /// Migrate from legacy NSCoding archive to Codable-compatible instance.
    static func migrateLegacyArchive(from data: Data) -> Self?
}

extension LegacyArchivable {
    public static func migrateLegacyArchive(from data: Data) -> Self? {
        // Use YYModel's NSSecureCoding-aware unarchiver
        let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver?.requiresSecureCoding = false // Allow legacy data
        return unarchiver?.decodeObject(of: Self.self, forKey: NSKeyedArchiveRootObjectKey)
    }
}
