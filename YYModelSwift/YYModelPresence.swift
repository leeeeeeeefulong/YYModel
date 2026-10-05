import Foundation

// ============================================================================
//  三态取值：区分「键不存在」与「键存在但为 null」
//
//  问题
//  ----
//  普通 Codable 把两种情况折叠成同一个结果：
//
//      A: { "id": 1, "file": null }              → 意图：把 file 清空
//      B: { "id": 1, "like": true }              → 意图：只更新 like，file 别动
//
//  解码后 A 和 B 的 file 都是 nil，**无法区分**。这对增量更新（只回传变更字段
//  的接口 / Core Data 局部写回）是致命的：你会把「没提到的字段」误当成「要求清空」。
//
//  解法
//  ----
//  用三态枚举承载，由解码容器负责判定「键是否存在」：
//
//      struct Song: Codable {
//          var id: Int
//          var file: YYModelPresence<String>      // 三态，不需要 Optional
//      }
//
//      switch song.file {
//      case .value(let v): managedObject.file = v     // 更新
//      case .null:         managedObject.file = nil   // 清空
//      case .absent:       break                      // 跳过，保留原值
//      }
//
//  与参考实现的关键差异
//  --------------------
//  常见的 `OptionalValue<T>?` 写法用「Optional 是否为 nil」表达「键缺失」，
//  语义上叠了两层 Optional，容易误用。这里用**三态枚举**，不需要 Optional 包裹：
//  属性类型直接是 `YYModelPresence<T>`，三种状态各占一个 case。
//
//  注意
//  ----
//  · 属性必须是**非可选**的 `YYModelPresence<T>`。写成 `YYModelPresence<T>?`
//    会让合成 Codable 走 `decodeIfPresent`，把 `.null` 也折叠成 nil。
//  · 不要把三态字段加入 `requiredProperties` —— 容忍缺失正是它的目的，两者矛盾。
//  · 参考实现指出「属性包装器 + Codable」会强制键必须存在（即使是 Optional 也会抛
//    keyNotFound），因此这里刻意用**普通枚举类型**而非 @propertyWrapper。
// ============================================================================

/// 一个字段在 JSON 中的三种状态。
public enum YYModelPresence<Value: Codable>: Codable {
    /// 键不存在 —— 调用方应**保留**已有值，不做修改。
    case absent
    /// 键存在且值为 null —— 调用方应**清空**已有值。
    case null
    /// 键存在且有值 —— 调用方应**写入**该值。
    case value(Value)
}

// MARK: - 容器标记协议（模块内部使用）

/// 让解码容器能在不知道具体 `Value` 的情况下，为「键缺失 / 值为 null」构造结果。
/// 容器判定完三态中的前两种后，第三种（有值）交回 `YYModelPresence.init(from:)`。
protocol YYModelPresenceType: Decodable {
    static var yy_absent: Self { get }
    static var yy_null: Self { get }
}

extension YYModelPresence: YYModelPresenceType {
    static var yy_absent: Self { .absent }
    static var yy_null: Self { .null }
}

/// 让编码容器能跳过 `.absent` 字段（键完全不出现）。
protocol YYModelPresenceEncodable {
    var yy_isAbsent: Bool { get }
}

extension YYModelPresence: YYModelPresenceEncodable {
    var yy_isAbsent: Bool { if case .absent = self { return true }; return false }
}

// MARK: - 取值便利

public extension YYModelPresence {

    /// 增量更新用的折叠：把三态落到「目标字段的最终值」上。
    ///
    /// ```swift
    /// // 只更新 JSON 中出现的字段，其余保留数据库里的原值
    /// record.file = song.file.resolve(keeping: record.file)
    /// ```
    ///
    /// - `.absent` → 返回 `existing`（保留原值）
    /// - `.null`   → 返回 `nil`（清空）
    /// - `.value`  → 返回新值
    func resolve(keeping existing: Value?) -> Value? {
        switch self {
        case .absent: return existing
        case .null: return nil
        case .value(let value): return value
        }
    }

    /// 键是否存在（`.absent` 之外都为 true）。
    var isPresent: Bool { if case .absent = self { return false }; return true }

    /// 是否为显式 null。
    var isNull: Bool { if case .null = self { return true }; return false }

    /// 有值时返回它，否则返回 nil。注意 `.null` 与 `.absent` 都返回 nil ——
    /// 需要区分时请用 `resolve(keeping:)` 或直接模式匹配。
    var valueOrNil: Value? { if case .value(let value) = self { return value }; return nil }
}

// MARK: - Codable

public extension YYModelPresence {

    /// 只处理「键存在且有值」这一种情况。
    /// 「键缺失」与「值为 null」由 `YYModelKeyedDecoder` 在进入本方法前判定 ——
    /// 因为值类型自身无法感知键是否存在。
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        self = .value(try container.decode(Value.self))
    }

    /// `.absent` 正常情况下不会走到这里（编码容器会直接跳过该键）。
    /// 若被单独编码，退化为 null，避免产出无意义的空对象。
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .absent, .null:
            try container.encodeNil()
        case .value(let value):
            try container.encode(value)
        }
    }
}

// MARK: - 等值/调试

extension YYModelPresence: Equatable where Value: Equatable {}
extension YYModelPresence: Hashable where Value: Hashable {}
extension YYModelPresence: Sendable where Value: Sendable {}

extension YYModelPresence: CustomStringConvertible {
    public var description: String {
        switch self {
        case .absent: return "absent"
        case .null: return "null"
        case .value(let value): return "value(\(value))"
        }
    }
}
