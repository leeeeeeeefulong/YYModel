import Foundation

/// Errors from building `YYJSONRules`, from using rules with an incompatible mode, and from
/// rule-driven encoding. Problems in the decoded JSON itself are reported as `DecodingError`
/// with the `codingPath` of the offending value, never as this type.
public enum YYJSONRulesError: Error, Equatable, Sendable, CustomStringConvertible {
    /// A rule declaration or decoder/encoder configuration was rejected.
    /// `typeName` is the model type the rule was declared for.
    case invalidRule(Code, typeName: String, detail: String)
    /// Rule-driven encoding was rejected. `codingPath` holds `CodingKey.stringValue`s of the
    /// value being encoded (or, for an export-path conflict, of the conflicting JSON path).
    case encodingRejected(Code, codingPath: [String], detail: String)

    /// Stable, machine-readable reason. Raw values are part of the public contract.
    public enum Code: String, Sendable, Equatable {
        /// `.native` received non-empty rules.
        case rulesRequireCompatibleMode
        /// `forType` was called on a scalar or collection instead of a model type.
        case ruleTargetNotModel
        /// A whitelist with no entries would exclude every property.
        case emptyWhitelist
        /// An empty configuration key (typically a nested KeyPath was used).
        case emptyKey
        /// A mapper path is empty or contains an empty component.
        case invalidMapperPath
        /// A required property is also excluded by the blacklist or whitelist.
        case requiredExcluded
        /// A default value has no JSON representation.
        case invalidDefaultValue
        /// `polymorphic` was given no variants.
        case emptyPolymorphicVariants
        /// Field or date policies were declared on a polymorphic root instead of its payloads.
        case polymorphicRootPolicy
        /// `transformTo` returned `false`.
        case transformToRejected
        /// A model, hook or variant did not export a JSON object.
        case exportNotObject
        /// Two properties export to the same or overlapping JSON paths.
        case exportPathConflict
        /// A polymorphic value matched more than one registered variant.
        case ambiguousVariant
        /// A polymorphic value matched no registered variant.
        case noMatchingVariant
        /// The discriminator path collides with a payload field.
        case discriminatorConflict
        /// An exported value is not representable as JSON.
        case invalidJSONValue
        /// A rule closure received a value of an unexpected type.
        case unexpectedValue
    }

    public var code: Code {
        switch self {
        case .invalidRule(let code, _, _), .encodingRejected(let code, _, _): return code
        }
    }

    public var description: String {
        switch self {
        case .invalidRule(let code, let typeName, let detail):
            return "YYJSONRulesError.\(code.rawValue) (type \(typeName)): \(detail)"
        case .encodingRejected(let code, let codingPath, let detail):
            return "YYJSONRulesError.\(code.rawValue) (path \(codingPath.joined(separator: "."))): \(detail)"
        }
    }

    static func rule(_ code: Code, _ type: Any.Type, _ detail: String) -> Self {
        .invalidRule(code, typeName: String(describing: type), detail: detail)
    }
    static func encoding(_ code: Code, _ path: [CodingKey], _ detail: String) -> Self {
        .encodingRejected(code, codingPath: path.map(\.stringValue), detail: detail)
    }
}

extension DecodingError {
    /// A decoded value that YYModelSwift rejected at `path` (hook rejection, unknown
    /// discriminator, internal type contract). Foundation reports invalid values the same way.
    static func yy_corrupted(_ path: [CodingKey], _ detail: String) -> DecodingError {
        .dataCorrupted(.init(codingPath: path, debugDescription: detail))
    }
}

/// Runs a body that builds `YYModelJSONValue` from a Foundation object and reports an
/// unrepresentable value as `dataCorrupted` at `path` instead of leaking an internal error.
func yy_decodingJSONValue<T>(at path: @autoclosure () -> [CodingKey], _ body: () throws -> T) throws -> T {
    do { return try body() }
    catch let failure as YYModelFailure { throw DecodingError.yy_corrupted(path(), failure.description) }
}

/// Encoding counterpart of `yy_decodingJSONValue`.
func yy_encodingJSONValue<T>(at path: @autoclosure () -> [CodingKey], _ body: () throws -> T) throws -> T {
    do { return try body() }
    catch let failure as YYModelFailure { throw YYJSONRulesError.encoding(.invalidJSONValue, path(), failure.description) }
}
