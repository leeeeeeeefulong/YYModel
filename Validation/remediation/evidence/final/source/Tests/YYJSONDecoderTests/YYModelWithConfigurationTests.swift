import XCTest
import YYModelSwift

/// 官方外部配置通道（`DecodableWithConfiguration` / `EncodableWithConfiguration`）的回归测试。
///
/// 命题：本入口是**可选能力**，接入它的模型必须采纳协议并手写
/// `init(from:configuration:)` —— 即放弃零侵入。主入口（普通 Codable + 外部规则）
/// 必须完全不受影响，两者可以并存。
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
final class YYModelWithConfigurationTests: XCTestCase {

    /// 配置经 userInfo 传递，必须是 Sendable（见 YYModelWithConfiguration.swift 的接入说明）。
    struct UnitContext: Equatable, Sendable {
        var unit: String
    }

    struct Reading: DecodableWithConfiguration, EncodableWithConfiguration, Equatable {
        typealias DecodingConfiguration = UnitContext
        typealias EncodingConfiguration = UnitContext

        var value: Double
        var unit: String

        enum CodingKeys: String, CodingKey { case value, unit }

        init(value: Double, unit: String) { self.value = value; self.unit = unit }

        init(from decoder: Decoder, configuration: UnitContext) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            value = try container.decode(Double.self, forKey: .value)
            unit = configuration.unit
        }

        func encode(to encoder: Encoder, configuration: UnitContext) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(value, forKey: .value)
            try container.encode(configuration.unit, forKey: .unit)
        }
    }

    // MARK: - 显式传配置

    func testDecodeWithExplicitConfiguration() throws {
        let reading = try YYJSONDecoder(mode: .native).decode(
            Reading.self, from: Data(#"{"value":30}"#.utf8), configuration: UnitContext(unit: "°C"))
        XCTAssertEqual(reading, Reading(value: 30, unit: "°C"))
    }

    func testEncodeWithExplicitConfiguration() throws {
        let data = try YYJSONEncoder(mode: .native).encode(
            Reading(value: 7, unit: "K"), configuration: UnitContext(unit: "K"))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["value"] as? Double, 7)
        XCTAssertEqual(object?["unit"] as? String, "K")
    }

    /// 配置确实被使用，而不是被忽略。
    func testConfigurationIsActuallyApplied() throws {
        let json = Data(#"{"value":1}"#.utf8)
        let celsius = try YYJSONDecoder(mode: .native).decode(Reading.self, from: json, configuration: UnitContext(unit: "°C"))
        let kelvin = try YYJSONDecoder(mode: .native).decode(Reading.self, from: json, configuration: UnitContext(unit: "K"))
        XCTAssertEqual(celsius.unit, "°C")
        XCTAssertEqual(kelvin.unit, "K")
        XCTAssertNotEqual(celsius.unit, kelvin.unit)
    }

    // MARK: - 往返

    func testRoundTrip() throws {
        let original = Reading(value: 30, unit: "°C")
        let data = try YYJSONEncoder(mode: .native).encode(original, configuration: UnitContext(unit: "°C"))
        let restored = try YYJSONDecoder(mode: .native).decode(Reading.self, from: data, configuration: UnitContext(unit: "°C"))
        XCTAssertEqual(restored, original)
    }

    // MARK: - DecodingConfigurationProviding

    struct SelfConfigured: DecodableWithConfiguration, DecodingConfigurationProviding, Equatable {
        typealias DecodingConfiguration = UnitContext
        static var decodingConfiguration: UnitContext { UnitContext(unit: "F") }
        var value: Int
        var unit: String
        enum CodingKeys: String, CodingKey { case value }
        init(value: Int, unit: String) { self.value = value; self.unit = unit }
        init(from decoder: Decoder, configuration: UnitContext) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            value = try c.decode(Int.self, forKey: .value)
            unit = configuration.unit
        }
    }

    func testDecodingConfigurationProviding() throws {
        let model = try YYJSONDecoder(mode: .native).decode(
            SelfConfigured.self, from: Data(#"{"value":9}"#.utf8))
        XCTAssertEqual(model, SelfConfigured(value: 9, unit: "F"))
    }

    // MARK: - 主入口不受影响

    func testMainEntryIsUnaffected() throws {
        struct Plain: Codable, Equatable { var id: Int; var name: String }
        let model = try YYJSONDecoder(mode: .compatible)
            .decode(Plain.self, from: Data(#"{"id":"1","name":"x"}"#.utf8))
        XCTAssertEqual(model, Plain(id: 1, name: "x"), "普通 Codable + 外部规则的主入口必须照常工作")
    }

    /// 采纳 `DecodableWithConfiguration` 的模型**不再**满足 `Decodable`，
    /// 因此无法通过主入口解码 —— 这是编译期约束，不是运行时错误。
    /// 下面用「只采纳 Decodable 的普通模型」证明主入口照常可用。
    func testPlainEntryStillAvailableForOrdinaryModels() throws {
        struct Plain: Codable, Equatable { var id: Int }
        let model = try YYJSONDecoder(mode: .compatible)
            .decode(Plain.self, from: Data(#"{"id":7}"#.utf8))
        XCTAssertEqual(model, Plain(id: 7))
    }
}
