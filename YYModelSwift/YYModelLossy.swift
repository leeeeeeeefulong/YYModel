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
//  并且**绝不静默**：被跳过的下标记录在调用方安装的 `YYModelLossReport` 里，
//  随时可查。**推荐用 `decodeWithReport`** —— 它每个调用创建独立报告并随返回值
//  一起返回，不用手动操作 `decoder.userInfo`（后者仍然支持跨调用共享报告）。
//  顶层数组还有专门的 `decodeLossyArray` 入口，完全无需规则配置。
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

    /// 顶层 lossy 数组的专用实现（D3）：不依赖规则配置，逐个元素解码并在失败时跳过。
    /// `report` 从这个方法的 `userInfo` 里读，避免调用方手动把 `YYModelLossReport`
    /// 塞进解码器的 `userInfo`。顶层元素没有属性名，`property` 记为 `"(root)"`。
    static func decodeLossyRoot(
        from container: UnkeyedDecodingContainer,
        date: YYModelDateStrategy,
        userInfo: [CodingUserInfoKey: Any]
    ) throws -> [Element] {
        var container = container
        var result: [Element] = []
        result.reserveCapacity(container.count ?? 0)
        let report = userInfo[YYModelLossReport.key] as? YYModelLossReport
        while !container.isAtEnd {
            let index = container.currentIndex
            let elementDecoder = try container.superDecoder()
            do {
                result.append(try YYModelDecode.value(Element.self, from: elementDecoder, date: date))
            } catch {
                report?.record(property: "(root)", index: index, reason: "\(error)")
            }
        }
        return result
    }
}

/// 顶层 `decodeLossyArray` 的工作盒：让 `YYJSONDecoder` 能对 `[T]` 走 lossy 路径，
/// 而不用为集合注册完整规则（C② 约束：集合仍禁止注册完整 `YYJSONRules`）。
struct YYModelLossyArrayBox<Element: Decodable>: Decodable {
    let elements: [Element]
    init(from decoder: Decoder) throws {
        let date = YYJSONContext.from(decoder).defaults.date
        let container = try decoder.unkeyedContainer()
        elements = try Array<Element>.decodeLossyRoot(from: container, date: date, userInfo: decoder.userInfo)
    }
}

/// `decodeWithReport` 抛错时带回已吸收的 losses（P2-4）。
///
/// `decodeWithReport` 在解析失败时把这个错误作为 `DecodingError` 的
/// `underlyingError` 携带，让调用方仍能按原错误类型匹配，同时取回那次解析
/// 已经吸收的 `YYModelLossReport` 快照。
public struct YYModelLossReportAttachment: Error, @unchecked Sendable {
    /// 失败前已吸收的逐元素跳过记录。
    public let report: YYModelLossReport
    /// 原始错误（如果它是被包装进来的）。
    public let original: Error?
    public init(report: YYModelLossReport, original: Error? = nil) {
        self.report = report
        self.original = original
    }
}

extension YYModelLossReport {
    /// 从 `decodeWithReport` 抛出的错误里解出失败前已吸收的报告，取不到返回 nil。
    ///
    /// ```swift
    /// do { ... } catch {
    ///     if let losses = YYModelLossReport.attached(from: error)?.losses, !losses.isEmpty {
    ///         print("吸收了的坏元素：\(losses)")
    ///     }
    /// }
    /// ```
    public static func attached(from error: Error) -> YYModelLossReport? {
        // 三种路径都能挂着 attachment：直接类型、DecodingError 的某个 case 的
        // context.underlyingError、NSError userInfo 链。逐层剥到 attachment 为止。
        if let attached = error as? YYModelLossReportAttachment { return attached.report }
        var current: Error? = error
        var hops = 0
        while let e = current, hops < 8 {
            if let attached = e as? YYModelLossReportAttachment { return attached.report }
            if let decoding = e as? DecodingError {
                switch decoding {
                case .dataCorrupted(let c): current = c.underlyingError
                case .typeMismatch(_, let c): current = c.underlyingError
                case .valueNotFound(_, let c): current = c.underlyingError
                case .keyNotFound(_, let c): current = c.underlyingError
                @unknown default: current = nil
                }
                hops += 1
                continue
            }
            if let ns = e as NSError? { current = ns.userInfo[NSUnderlyingErrorKey] as? Error; hops += 1; continue }
            break
        }
        return nil
    }
}

extension YYModelLossReportAttachment: LocalizedError, CustomStringConvertible {
    public var errorDescription: String? {
        if let original { return original.localizedDescription }
        return "YYModelLossReportAttachment (no underlying error)"
    }
    public var description: String {
        if let original { return String(describing: original) }
        return "YYModelLossReportAttachment"
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
