import Foundation

/// Thread-safe diagnostic report for runtime type coercions (P-08).
/// Dispatches only when explicitly enabled via `userInfo[YYModelCoercionReport.key]`.
/// Never logs or retains user values; only records metadata categories and coding paths.
public final class YYModelCoercionReport: @unchecked Sendable {
    public static let key = CodingUserInfoKey(rawValue: "YYModelSwift.CoercionReport")!

    public struct Record: Sendable, Equatable {
        public let codingPath: String
        public let sourceCategory: String
        public let targetType: String
        public let reason: String

        public init(codingPath: String, sourceCategory: String, targetType: String, reason: String) {
            self.codingPath = codingPath
            self.sourceCategory = sourceCategory
            self.targetType = targetType
            self.reason = reason
        }
    }

    private let lock = NSLock()
    private var _records: [Record] = []

    public var records: [Record] {
        lock.lock(); defer { lock.unlock() }
        return _records
    }

    public init() {}

    public func record(codingPath: [CodingKey], sourceCategory: String, targetType: String, reason: String) {
        let path = codingPath.map(\.stringValue).joined(separator: ".")
        record(codingPath: path, sourceCategory: sourceCategory, targetType: targetType, reason: reason)
    }

    public func record(codingPath: String, sourceCategory: String, targetType: String, reason: String) {
        lock.lock(); defer { lock.unlock() }
        _records.append(Record(codingPath: codingPath, sourceCategory: sourceCategory, targetType: targetType, reason: reason))
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        _records.removeAll()
    }
}
