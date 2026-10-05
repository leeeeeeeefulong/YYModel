import Foundation

// ============================================================================
//  Lossy 数组：跳过坏元素而不是让整个解析失败
//
//  问题
//  ----
//  Codable 默认是「全有或全无」：数组里一个元素解不出来，整个模型就失败。
//  一个脏元素毁掉整批数据，在真实接口上很难接受。
//
//      {"results":[ {"id":1}, {"id":"bad"}, {"id":2} ]}
//                                       ↑ 这一个坏元素
//      默认行为：整个 results 解不出来
//      期望行为：得到 [1, 2]，并知道第 1 个被跳过了
//
//  本框架的立场
//  -----------
//  默认**不**丢元素（保持与官方一致的严格语义），lossy 必须显式开启：
//
//      rules.forType(Response.self) { rule in
//          rule.lossy(\.results)
//      }
//
//  并且**绝不静默**：被跳过的下标会记录到 `YYModelLossReport`，调用方随时可查。
//  这解决了「跳过坏元素」与「坏数据不能被伪装成有效结果」之间的矛盾 ——
//  丢是丢，但丢了多少、丢在哪，有据可查。
// ============================================================================

/// 一次 lossy 解析中被跳过的元素。
public struct YYModelLoss: Sendable, CustomStringConvertible, Equatable {
    /// 被跳过元素所在的属性名（CodingKey.stringValue）
    public let property: String
    /// 在数组中的下标
    public let index: Int
    /// 该元素解析失败的原因
    public let reason: String

    public var description: String { "\(property)[\(index)]: \(reason)" }
}

/// 一次解析过程中的跳过记录。
///
/// 用法：放进 `userInfo`，解析结束后读取。
///
/// ```swift
/// let report = YYModelLossReport()
/// var decoder = YYJSONDecoder(mode: .compatible, rules: rules)
/// decoder.userInfo[YYModelLossReport.key] = report
/// let response = try decoder.decode(Response.self, from: data)
///
/// if !report.losses.isEmpty {
///     print("跳过了 \(report.losses.count) 个坏元素：\(report.losses)")
/// }
/// ```
///
/// 线程安全：内部加锁，可跨线程共享。
public final class YYModelLossReport: @unchecked Sendable {

    public static let key = CodingUserInfoKey(rawValue: "YYModelSwift.LossReport")!

    private let lock = NSLock()
    private var storage: [YYModelLoss] = []

    public init() {}

    /// 当前累计的跳过记录。
    public var losses: [YYModelLoss] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    /// 是否有元素被跳过。
    public var hasLosses: Bool {
        lock.lock(); defer { lock.unlock() }
        return !storage.isEmpty
    }

    public func record(property: String, index: Int, reason: String) {
        lock.lock(); defer { lock.unlock() }
        storage.append(YYModelLoss(property: property, index: index, reason: reason))
    }

    public func reset() {
        lock.lock(); defer { lock.unlock() }
        storage.removeAll()
    }
}

// MARK: - 数组的 lossy 解码

/// 让 `decode(_:forKey:)` 在不知道 `Element` 具体类型的情况下，
/// 逐元素解码并跳过失败项。
protocol YYModelLossyArray {
    static var empty: Any { get }
    static func decodeLossy(
        from container: UnkeyedDecodingContainer,
        property: String,
        date: YYModelDateStrategy,
        report: YYModelLossReport?
    ) throws -> Any
}

extension Array: YYModelLossyArray where Element: Decodable {
    static var empty: Any { [Element]() }
    static func decodeLossy(
        from container: UnkeyedDecodingContainer,
        property: String,
        date: YYModelDateStrategy,
        report: YYModelLossReport?
    ) throws -> Any {
        var container = container
        var result: [Element] = []
        result.reserveCapacity(container.count ?? 0)

        while !container.isAtEnd {
            let index = container.currentIndex
            // superDecoder() 无条件推进游标 —— 这正是跳过所需：
            // 失败的元素也必须被消费掉，否则循环无法前进。
            let elementDecoder = try container.superDecoder()
            do {
                result.append(try YYModelDecode.value(Element.self, from: elementDecoder, date: date))
            } catch {
                report?.record(property: property, index: index, reason: "\(error)")
            }
        }
        return result
    }
}

// MARK: - 规则入口

public extension YYModelConfiguration {

    /// 把某个数组属性标记为 **lossy**：单个元素解码失败时跳过它，而不是让整批失败。
    ///
    /// 被跳过的下标会记录到 `YYModelLossReport`（需放进 `decoder.userInfo`），
    /// 不做静默丢弃。
    ///
    /// ```swift
    /// try rule.lossy(\.results)
    /// ```
    mutating func lossy<Element: Decodable>(_ keyPath: KeyPath<Model, [Element]>) {
        lossyProperties.append(Self.propertyName(keyPath))
    }

    /// 同上，但直接接受 `PartialKeyPath`，便于在动态场景使用。
    mutating func lossy(_ keyPath: PartialKeyPath<Model>) {
        lossyProperties.append(Self.propertyName(keyPath))
    }
}
