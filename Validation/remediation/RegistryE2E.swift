import Foundation
import YYModelSwift

public struct TestRecord: Codable, Sendable {
    public let id: String
    public let scenario: String
    public let passed: Bool
    public let actual: String
    public let expected: String

    public init(id: String, scenario: String, passed: Bool, actual: String, expected: String) {
        self.id = id
        self.scenario = scenario
        self.passed = passed
        self.actual = actual
        self.expected = expected
    }
}

private struct DynamicKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
    init(_ stringValue: String) { self.stringValue = stringValue }
}

private final class StateBox<T: Sendable>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

// MARK: - Models for E2E Cases

// P-01
private struct P01Model: Codable, Sendable {
    var id: Int64
}

// P-02
private struct P02Model: Codable, Sendable {
    var delta: Int
}

// P-03
private struct P03Model: YYModelCodable, Sendable {
    var score: Decimal
}

// P-04
private struct P04Model: Codable, Sendable {
    var data: Data
}

// P-06
private struct P06Model: Codable, Sendable {
    var f: Float
}

// F-01
private struct F01Model: Codable, Sendable {
    var userName: String
}

// F-02
private struct F02Model: YYModelCodable, Sendable {
    var id: Int
    var name: String
    static var yy_modelConfiguration: YYModelConfiguration<Self> {
        .init(mapper: ["id": "uid"])
    }
}
private struct F02DupModel: YYModelCodable, Sendable {
    var id: Int
    var name: String
}

// F-03
private struct F03DataKeyModel: Codable, Sendable {
    var dict: [String: Int]
}
private struct F03IntDictModel: Codable, Sendable {
    var m: [Int: String]
}

// F-04
private struct F04Model: Codable, Sendable {
    var x: Int
    enum CodingKeys: String, CodingKey { case x }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard c.contains(.x) else {
            throw DecodingError.keyNotFound(CodingKeys.x, .init(codingPath: decoder.codingPath, debugDescription: "contains(x) is false"))
        }
        _ = try c.superDecoder(forKey: .x)
        self.x = 7
    }
}

// F-05
private struct F05Model: YYModelCodable, Sendable {
    var b: Int
    static var yy_modelConfiguration: YYModelConfiguration<Self> {
        .init(mapper: ["b": "a.b"])
    }
}

// F-06
private final class F06HookObserver: @unchecked Sendable {
    static let shared = F06HookObserver()
    var observedVal: Int = -1
}
private struct F06Child: YYModelCodable, Sendable {
    var val: Int
    static var yy_modelConfiguration: YYModelConfiguration<Self> {
        .init(didTransform: { model, dict in
            if let v = dict["val"] as? Int {
                F06HookObserver.shared.observedVal = v
            }
            return true
        })
    }
}
private struct F06Parent: YYModelCodable, Sendable {
    var subItem: F06Child
}

// F-07
private struct F07ArrayModel: Codable, Sendable {
    var items: [YYModelPresence<String>]
}
private struct F07DictModel: Codable, Sendable {
    var map: [String: YYModelPresence<Int>]
}
private struct F07SingleModel: Codable, Sendable {
    var item: YYModelPresence<String>
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        self.item = try c.decode(YYModelPresence<String>.self)
    }
}

// F-08
private struct F08Model: Codable, Sendable {
    var items: [Int]
}
private struct F08ContainerModel: Codable, Sendable {
    var items: [Int]
}

// F-09
private class F09Base: Codable, @unchecked Sendable {
    var title: String
    enum CodingKeys: String, CodingKey { case title }
    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try c.decode(String.self, forKey: .title)
    }
}
private final class F09Sub: F09Base, @unchecked Sendable {
    var `super`: String
    private enum CodingKeys: String, CodingKey { case `super` }
    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.`super` = try c.decode(String.self, forKey: .`super`)
        try super.init(from: c.superDecoder())
    }
}

// F-10
private enum F10Root: Codable, Sendable {
    case sub(F10Sub)
}
private struct F10Sub: Codable, Sendable {
    var name: String
}

// F-11
private struct F11bModel: Codable, Sendable {
    var item: YYModelPresence<String>
    var observedStatus: String
    enum CodingKeys: String, CodingKey { case item }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let isNil = try c.decodeNil(forKey: .item)
        let decoded = try c.decode(YYModelPresence<String>.self, forKey: .item)
        let decodedDesc: String
        switch decoded {
        case .absent: decodedDesc = "absent"
        case .null: decodedDesc = "null"
        case .value(let v): decodedDesc = "value(\(v))"
        }
        self.item = decoded
        self.observedStatus = "decodeNil=\(isNil),decode=\(decodedDesc)"
    }
}
private struct F11fModel: YYModelCodable, Sendable {
    var prop: String
    var observedKeys: [String]
    static var yy_modelConfiguration: YYModelConfiguration<Self> {
        .init(mapper: ["prop": "alias_name"])
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)
        let keys = c.allKeys.map(\.stringValue).sorted()
        self.observedKeys = keys
        self.prop = (try? c.decode(String.self, forKey: DynamicKey("prop"))) ?? ""
    }
}

// MARK: - Probe Executor

@main
struct RegistryE2E {
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count > 1 else {
            fputs("Usage: RegistryE2E <output-json-path>\n", stderr)
            exit(1)
        }
        let outputPath = arguments[1]
        var rows: [TestRecord] = []

        // ====================================================================
        // P-01: 大整数保真与环境范围控制 (>2^53 雪花 ID)
        // ====================================================================
        do {
            let json = "{\"id\": 9007199254740993}"
            let decoder = YYJSONDecoder(mode: .compatible)
            let model = try decoder.decode(P01Model.self, from: Data(json.utf8))
            let actual = String(model.id)
            let expected = "9007199254740993"
            rows.append(TestRecord(id: "P-01", scenario: "p01_large_integer_control",
                                   passed: actual == expected,
                                   actual: actual, expected: expected))
        } catch {
            rows.append(TestRecord(id: "P-01", scenario: "p01_large_integer_control",
                                   passed: false, actual: "error: \(error)", expected: "9007199254740993"))
        }

        // ====================================================================
        // P-02: 正负截断对照 (三态全矩阵: Data, NSNumber Double, NSDecimalNumber)
        // 探针期望统一为向零截断 (-1.9 -> -1, +1.9 -> +1)
        // ====================================================================
        // 1. Data positive
        do {
            let decoder = YYJSONDecoder(mode: .compatible)
            let m = try decoder.decode(P02Model.self, from: Data("{\"delta\": 1.9}".utf8))
            let actual = String(m.delta)
            let expected = "1"
            rows.append(TestRecord(id: "P-02", scenario: "p02_pos_decimal_trunc_data",
                                   passed: actual == expected, actual: actual, expected: expected))
        } catch {
            rows.append(TestRecord(id: "P-02", scenario: "p02_pos_decimal_trunc_data",
                                   passed: false, actual: "error: \(error)", expected: "1"))
        }

        // 2. Data negative
        do {
            let decoder = YYJSONDecoder(mode: .compatible)
            let m = try decoder.decode(P02Model.self, from: Data("{\"delta\": -1.9}".utf8))
            let actual = String(m.delta)
            let expected = "-1"
            rows.append(TestRecord(id: "P-02", scenario: "p02_neg_decimal_trunc_data",
                                   passed: actual == expected, actual: actual, expected: expected))
        } catch {
            rows.append(TestRecord(id: "P-02", scenario: "p02_neg_decimal_trunc_data",
                                   passed: false, actual: "error: \(error)", expected: "-1"))
        }

        // 3. NSNumber positive (Double)
        do {
            let decoder = YYJSONDecoder(mode: .compatible)
            let m = try decoder.decode(P02Model.self, from: ["delta": NSNumber(value: 1.9)])
            let actual = String(m.delta)
            let expected = "1"
            rows.append(TestRecord(id: "P-02", scenario: "p02_pos_decimal_trunc_nsnumber",
                                   passed: actual == expected, actual: actual, expected: expected))
        } catch {
            rows.append(TestRecord(id: "P-02", scenario: "p02_pos_decimal_trunc_nsnumber",
                                   passed: false, actual: "error: \(error)", expected: "1"))
        }

        // 4. NSNumber negative (Double)
        do {
            let decoder = YYJSONDecoder(mode: .compatible)
            let m = try decoder.decode(P02Model.self, from: ["delta": NSNumber(value: -1.9)])
            let actual = String(m.delta)
            let expected = "-1"
            rows.append(TestRecord(id: "P-02", scenario: "p02_neg_decimal_trunc_nsnumber",
                                   passed: actual == expected, actual: actual, expected: expected))
        } catch {
            rows.append(TestRecord(id: "P-02", scenario: "p02_neg_decimal_trunc_nsnumber",
                                   passed: false, actual: "error: \(error)", expected: "-1"))
        }

        // 5. NSDecimalNumber positive
        do {
            let decoder = YYJSONDecoder(mode: .compatible)
            let m = try decoder.decode(P02Model.self, from: ["delta": NSDecimalNumber(string: "1.9")])
            let actual = String(m.delta)
            let expected = "1"
            rows.append(TestRecord(id: "P-02", scenario: "p02_pos_decimal_trunc_decimalnumber",
                                   passed: actual == expected, actual: actual, expected: expected))
        } catch {
            rows.append(TestRecord(id: "P-02", scenario: "p02_pos_decimal_trunc_decimalnumber",
                                   passed: false, actual: "error: \(error)", expected: "1"))
        }

        // 6. NSDecimalNumber negative
        do {
            let decoder = YYJSONDecoder(mode: .compatible)
            let m = try decoder.decode(P02Model.self, from: ["delta": NSDecimalNumber(string: "-1.9")])
            let actual = String(m.delta)
            let expected = "-1"
            rows.append(TestRecord(id: "P-02", scenario: "p02_neg_decimal_trunc_decimalnumber",
                                   passed: actual == expected, actual: actual, expected: expected))
        } catch {
            rows.append(TestRecord(id: "P-02", scenario: "p02_neg_decimal_trunc_decimalnumber",
                                   passed: false, actual: "error: \(error)", expected: "-1"))
        }

        // ====================================================================
        // P-03: 导出 Decimal 保持高精度字面量
        // ====================================================================
        do {
            let decStr = "1.000000000000000031251"
            let decVal = Decimal(string: decStr) ?? Decimal(0)
            let model = P03Model(score: decVal)
            let obj = model.yy_modelToJSONObject()
            let scoreVal = obj?["score"]
            let actual: String
            if let num = scoreVal as? NSDecimalNumber {
                actual = num.stringValue
            } else if let num = scoreVal as? NSNumber {
                actual = num.stringValue
            } else {
                actual = "nil"
            }
            let expected = decStr
            rows.append(TestRecord(id: "P-03", scenario: "p03_decimal_export_literal",
                                   passed: actual == expected, actual: actual, expected: expected))
        }

        // ====================================================================
        // P-04: Custom Data/Date Strategy 回调内 Decimal 精度保持
        // ====================================================================
        do {
            let box = StateBox<String>("")
            var decoder = YYJSONDecoder(mode: .compatible)
            decoder.dataDecodingStrategy = .custom { d in
                let dec = try d.singleValueContainer().decode(Decimal.self)
                box.value = dec.description
                return Data()
            }
            _ = try decoder.decode(P04Model.self, from: Data("{\"data\": 1.000000000000000031251}".utf8))
            let actual = box.value
            let expected = "1.000000000000000031251"
            rows.append(TestRecord(id: "P-04", scenario: "p04_custom_strategy_decimal",
                                   passed: actual == expected, actual: actual, expected: expected))
        } catch {
            rows.append(TestRecord(id: "P-04", scenario: "p04_custom_strategy_decimal",
                                   passed: false, actual: "error: \(error)", expected: "1.000000000000000031251"))
        }

        // ====================================================================
        // P-06: Float 直接文本解析位模式 (1 ULP 偏差)
        // ====================================================================
        do {
            let decoder = YYJSONDecoder(mode: .compatible)
            let rawDict: [String: Any] = ["f": "1.0000000596046448"]
            let m = try decoder.decode(P06Model.self, from: rawDict)
            let actual = String(m.f.bitPattern)
            let expected = String(Float("1.0000000596046448")?.bitPattern ?? 0)
            rows.append(TestRecord(id: "P-06", scenario: "p06_float_text_bitpattern",
                                   passed: actual == expected, actual: actual, expected: expected))
        } catch {
            rows.append(TestRecord(id: "P-06", scenario: "p06_float_text_bitpattern",
                                   passed: false, actual: "error: \(error)", expected: "1065353217"))
        }

        // ====================================================================
        // F-01: Raw 键冲突 - 精确 userName 优先于转换键
        // ====================================================================
        do {
            var decoder = YYJSONDecoder(mode: .compatible)
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            // 寻找使 user_name 先于 userName 遍历的布局
            var selectedDict: [String: Any] = ["user_name": "A", "userName": "B"]
            for padCount in 0..<30 {
                var testD: [String: Any] = [:]
                for j in 0..<padCount { testD["pad_\(j)"] = j }
                testD["user_name"] = "A"
                testD["userName"] = "B"
                for j in padCount..<(padCount + 3) { testD["pad_\(j)"] = j }
                let keys = Array(testD.keys)
                if let iA = keys.firstIndex(of: "user_name"), let iB = keys.firstIndex(of: "userName"), iA < iB {
                    selectedDict = testD
                    break
                }
            }
            let m = try decoder.decode(F01Model.self, from: selectedDict)
            let actual = m.userName
            let expected = "B" // D3-1 Option A: 精确匹配属性名优先
            rows.append(TestRecord(id: "F-01", scenario: "f01_raw_key_conflict_exact_first",
                                   passed: actual == expected, actual: actual, expected: expected))
        } catch {
            rows.append(TestRecord(id: "F-01", scenario: "f01_raw_key_conflict_exact_first",
                                   passed: false, actual: "error: \(error)", expected: "B"))
        }

        // ====================================================================
        // F-02: 模型内生配置 + 外部规则 / 重复注册合成
        // ====================================================================
        // Subcase 1: model mapper + external require 规则合成
        do {
            let rules = try YYJSONRules().forType(F02Model.self) {
                $0.require(\.name)
            }
            let decoder = YYJSONDecoder(mode: .compatible, rules: rules)
            let m = try decoder.decode(F02Model.self, from: Data("{\"uid\": 7, \"name\": \"ok\"}".utf8))
            let actual = "id=\(m.id),name=\(m.name)"
            let expected = "id=7,name=ok"
            rows.append(TestRecord(id: "F-02", scenario: "f02_model_external_rule_merge",
                                   passed: actual == expected, actual: actual, expected: expected))
        } catch {
            rows.append(TestRecord(id: "F-02", scenario: "f02_model_external_rule_merge",
                                   passed: false, actual: "error: \(error)", expected: "id=7,name=ok"))
        }

        // Subcase 2: 两次 forType 注册应累加而非覆盖
        do {
            let rules = try YYJSONRules()
                .forType(F02DupModel.self) { $0.require(\.id) }
                .forType(F02DupModel.self) { $0.require(\.name) }
            let decoder = YYJSONDecoder(mode: .legacy, rules: rules)
            // 缺失 id 但含有 name：若前次 require(\.id) 未被覆盖，必须报错拒绝
            let actual: String
            do {
                let m = try decoder.decode(F02DupModel.self, from: Data("{\"name\": \"ok\"}".utf8))
                actual = "allowed_missing_id(id=\(m.id))"
            } catch {
                actual = "rejected_missing_id"
            }
            let expected = "rejected_missing_id"
            rows.append(TestRecord(id: "F-02", scenario: "f02_duplicate_external_rule_merge",
                                   passed: actual == expected, actual: actual, expected: expected))
        } catch {
            rows.append(TestRecord(id: "F-02", scenario: "f02_duplicate_external_rule_merge",
                                   passed: false, actual: "error: \(error)", expected: "rejected_missing_id"))
        }

        // ====================================================================
        // F-03: 数据键策略及 Int 冲突
        // ====================================================================
        // Subcase 1: 字典中的 String 键是数据，不应被 keyDecodingStrategy 转换
        do {
            var decoder = YYJSONDecoder(mode: .compatible)
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let m = try decoder.decode(F03DataKeyModel.self, from: Data("{\"dict\": {\"snake_case\": 1}}".utf8))
            let actual = m.dict.keys.sorted().joined(separator: ",")
            let expected = "snake_case"
            rows.append(TestRecord(id: "F-03", scenario: "f03_data_keys_snake_case_preserved",
                                   passed: actual == expected, actual: actual, expected: expected))
        } catch {
            rows.append(TestRecord(id: "F-03", scenario: "f03_data_keys_snake_case_preserved",
                                   passed: false, actual: "error: \(error)", expected: "snake_case"))
        }

        // Subcase 2: Int 键冲突 ("01" vs "1") Data 与 Raw 一致性
        do {
            let decoder = YYJSONDecoder(mode: .compatible)
            // 寻找使 "01" 与 "1" 遍历顺序可导致冲突歧义的字典
            var rawD: [String: String] = ["1": "b", "01": "a"]
            for pad in 0..<30 {
                var testD: [String: String] = [:]
                for j in 0..<pad { testD["\(100 + j)"] = "\(j)" }
                testD["1"] = "b"
                testD["01"] = "a"
                for j in pad..<(pad + 3) { testD["\(200 + j)"] = "\(j)" }
                if let testModel = try? decoder.decode(F03IntDictModel.self, from: ["m": testD]) {
                    if testModel.m[1] == "a" {
                        rawD = testD
                        break
                    }
                }
            }
            let rawModel = try decoder.decode(F03IntDictModel.self, from: ["m": rawD])
            let actual = rawModel.m[1] ?? "nil"
            let expected = "b" // 精确整数形式 "1" 必须优先于别名形式 "01"
            rows.append(TestRecord(id: "F-03", scenario: "f03_int_key_dict_conflict_exact_winner",
                                   passed: actual == expected, actual: actual, expected: expected))
        } catch {
            rows.append(TestRecord(id: "F-03", scenario: "f03_int_key_dict_conflict_exact_winner",
                                   passed: false, actual: "error: \(error)", expected: "b"))
        }

        // ====================================================================
        // F-04: Fallback / TypedDefault 容器查询
        // ====================================================================
        do {
            let rules = try YYJSONRules().forType(F04Model.self) {
                $0.fallback(\.x, to: 7)
            }
            let decoder = YYJSONDecoder(mode: .compatible, rules: rules)
            _ = try decoder.decode(F04Model.self, from: Data("{}".utf8))
            let actual = "superDecoder_accessible"
            let expected = "superDecoder_accessible"
            rows.append(TestRecord(id: "F-04", scenario: "f04_fallback_superdecoder_container",
                                   passed: actual == expected, actual: actual, expected: expected))
        } catch {
            rows.append(TestRecord(id: "F-04", scenario: "f04_fallback_superdecoder_container",
                                   passed: false, actual: "error: \(error)", expected: "superDecoder_accessible"))
        }

        // ====================================================================
        // F-05: 错误路径形状 (中间标量节点吞错并静默补零)
        // ====================================================================
        do {
            let decoder = YYJSONDecoder(mode: .legacy)
            let m = try decoder.decode(F05Model.self, from: Data("{\"a\": 5}".utf8))
            let actual = "zeroFilled=\(m.b)"
            let expected = "typeMismatch_thrown"
            rows.append(TestRecord(id: "F-05", scenario: "f05_path_shape_error_swallowed",
                                   passed: false, actual: actual, expected: expected))
        } catch DecodingError.typeMismatch {
            rows.append(TestRecord(id: "F-05", scenario: "f05_path_shape_error_swallowed",
                                   passed: true, actual: "typeMismatch_thrown", expected: "typeMismatch_thrown"))
        } catch {
            rows.append(TestRecord(id: "F-05", scenario: "f05_path_shape_error_swallowed",
                                   passed: false, actual: "error: \(error)", expected: "typeMismatch_thrown"))
        }

        // ====================================================================
        // F-06: 嵌套 Hook 快照与模型解码子树分歧
        // ====================================================================
        do {
            var decoder = YYJSONDecoder(mode: .compatible)
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let json = "{\"sub_item\": {\"val\": 1}, \"subItem\": {\"val\": 2}}"
            F06HookObserver.shared.observedVal = -1
            let m = try decoder.decode(F06Parent.self, from: Data(json.utf8))
            let decodedVal = m.subItem.val
            let hookVal = F06HookObserver.shared.observedVal
            let actual = "decoded=\(decodedVal),hook=\(hookVal)"
            let expected = "decoded=\(decodedVal),hook=\(decodedVal)"
            rows.append(TestRecord(id: "F-06", scenario: "f06_hook_snapshot_subtree_divergence",
                                   passed: decodedVal == hookVal, actual: actual, expected: expected))
        } catch {
            rows.append(TestRecord(id: "F-06", scenario: "f06_hook_snapshot_subtree_divergence",
                                   passed: false, actual: "error: \(error)", expected: "decoded==hook"))
        }

        // ====================================================================
        // F-07: Presence null 在数组、字典与单值容器中
        // ====================================================================
        // 1. Array of presence null
        do {
            let decoder = YYJSONDecoder(mode: .compatible)
            let m = try decoder.decode(F07ArrayModel.self, from: Data("{\"items\": [null]}".utf8))
            let itemDesc: String
            if case .null = m.items.first { itemDesc = ".null" }
            else { itemDesc = "not_null" }
            let actual = itemDesc
            let expected = ".null"
            rows.append(TestRecord(id: "F-07", scenario: "f07_presence_null_array",
                                   passed: actual == expected, actual: actual, expected: expected))
        } catch {
            rows.append(TestRecord(id: "F-07", scenario: "f07_presence_null_array",
                                   passed: false, actual: "error: \(error)", expected: ".null"))
        }

        // 2. Dictionary of presence null
        do {
            let decoder = YYJSONDecoder(mode: .compatible)
            let m = try decoder.decode(F07DictModel.self, from: Data("{\"map\": {\"k\": null}}".utf8))
            let valDesc: String
            if case .null = m.map["k"] { valDesc = ".null" }
            else { valDesc = "not_null" }
            let actual = valDesc
            let expected = ".null"
            rows.append(TestRecord(id: "F-07", scenario: "f07_presence_null_dict",
                                   passed: actual == expected, actual: actual, expected: expected))
        } catch {
            rows.append(TestRecord(id: "F-07", scenario: "f07_presence_null_dict",
                                   passed: false, actual: "error: \(error)", expected: ".null"))
        }

        // 3. Single-value container presence null
        do {
            let decoder = YYJSONDecoder(mode: .compatible)
            let m = try decoder.decode(F07SingleModel.self, from: Data("null".utf8))
            let valDesc: String
            if case .null = m.item { valDesc = ".null" }
            else { valDesc = "not_null" }
            let actual = valDesc
            let expected = ".null"
            rows.append(TestRecord(id: "F-07", scenario: "f07_presence_null_single",
                                   passed: actual == expected, actual: actual, expected: expected))
        } catch {
            rows.append(TestRecord(id: "F-07", scenario: "f07_presence_null_single",
                                   passed: false, actual: "error: \(error)", expected: ".null"))
        }

        // ====================================================================
        // F-08: Lossy + Fallback 优先级倒置及错误容器
        // ====================================================================
        // 1. Lossy 与 Fallback 并存优先级
        do {
            let rules = try YYJSONRules().forType(F08Model.self) {
                $0.lossy(\.items)
                $0.fallback(\.items, to: [999])
            }
            let decoder = YYJSONDecoder(mode: .compatible, rules: rules)
            let m = try decoder.decode(F08Model.self, from: Data("{\"items\": [1, \"bad\", 2]}".utf8))
            let actual = m.items.map(String.init).joined(separator: ",")
            let expected = "1,2"
            rows.append(TestRecord(id: "F-08", scenario: "f08_lossy_fallback_priority_inversion",
                                   passed: actual == expected, actual: actual, expected: expected))
        } catch {
            rows.append(TestRecord(id: "F-08", scenario: "f08_lossy_fallback_priority_inversion",
                                   passed: false, actual: "error: \(error)", expected: "1,2"))
        }

        // 2. 字段值整体类型错误时应记入损失而非直接失败
        do {
            let report = YYModelLossReport()
            let rules = try YYJSONRules().forType(F08ContainerModel.self) {
                $0.lossy(\.items)
            }
            var decoder = YYJSONDecoder(mode: .compatible, rules: rules)
            decoder.userInfo[YYModelLossReport.key] = report
            _ = try decoder.decode(F08ContainerModel.self, from: Data("{\"items\": \"not_an_array\"}".utf8))
            let actual = "losses=\(report.losses.count)"
            let expected = "losses=1"
            rows.append(TestRecord(id: "F-08", scenario: "f08_lossy_wrong_container_type",
                                   passed: report.losses.count > 0, actual: actual, expected: expected))
        } catch {
            rows.append(TestRecord(id: "F-08", scenario: "f08_lossy_wrong_container_type",
                                   passed: false, actual: "error: \(error)", expected: "loss_recorded"))
        }

        // ====================================================================
        // F-09: 业务 "super" 键劫持 superDecoder
        // ====================================================================
        do {
            let decoder = YYJSONDecoder(mode: .compatible)
            let rawDict: [String: Any] = ["super": "VIP", "title": "Manager"]
            let sub = try decoder.decode(F09Sub.self, from: rawDict)
            let actual = "title=\(sub.title),super=\(sub.`super`)"
            let expected = "title=Manager,super=VIP"
            rows.append(TestRecord(id: "F-09", scenario: "f09_business_super_key_hijack",
                                   passed: actual == expected, actual: actual, expected: expected))
        } catch {
            rows.append(TestRecord(id: "F-09", scenario: "f09_business_super_key_hijack",
                                   passed: false, actual: "error: \(error)", expected: "title=Manager,super=VIP"))
        }

        // ====================================================================
        // F-10: 多态判别符数字与 Null 表现
        // ====================================================================
        // 1. 数字判别符
        do {
            let rules = try YYJSONRules().polymorphic(F10Root.self, discriminator: "type", variants: [
                "sub": YYModelVariant(F10Sub.self, create: F10Root.sub, extract: { if case .sub(let s) = $0 { return s } else { return nil } })
            ])
            let decoder = YYJSONDecoder(mode: .compatible, rules: rules)
            var rawOutcome = "unknown"
            do {
                _ = try decoder.decode(F10Root.self, from: ["type": 1, "name": "test"])
                rawOutcome = "coerced"
            } catch DecodingError.typeMismatch {
                rawOutcome = "typeMismatch"
            } catch {
                rawOutcome = "otherError: \(error)"
            }
            let actual = rawOutcome
            let expected = "typeMismatch"
            rows.append(TestRecord(id: "F-10", scenario: "f10_polymorphic_number_discriminator",
                                   passed: actual == expected, actual: actual, expected: expected))
        } catch {
            rows.append(TestRecord(id: "F-10", scenario: "f10_polymorphic_number_discriminator",
                                   passed: false, actual: "error: \(error)", expected: "typeMismatch"))
        }

        // 2. Null 判别符
        do {
            let rules = try YYJSONRules().polymorphic(F10Root.self, discriminator: "type", variants: [
                "sub": YYModelVariant(F10Sub.self, create: F10Root.sub, extract: { if case .sub(let s) = $0 { return s } else { return nil } })
            ])
            let decoder = YYJSONDecoder(mode: .compatible, rules: rules)
            var rawOutcome = "unknown"
            do {
                _ = try decoder.decode(F10Root.self, from: ["type": NSNull(), "name": "test"])
                rawOutcome = "decoded"
            } catch {
                rawOutcome = String(describing: error)
            }
            let actual = rawOutcome
            let isMisleadingEmpty = actual.contains("Unknown model discriminator: ") && actual.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("Unknown model discriminator:")
            let passed = !isMisleadingEmpty && actual.contains("Missing model discriminator")
            let expected = "Missing model discriminator"
            rows.append(TestRecord(id: "F-10", scenario: "f10_polymorphic_null_discriminator",
                                   passed: passed, actual: actual, expected: expected))
        } catch {
            rows.append(TestRecord(id: "F-10", scenario: "f10_polymorphic_null_discriminator",
                                   passed: false, actual: "error: \(error)", expected: "Missing model discriminator"))
        }

        // ====================================================================
        // F-11: 低危集合 (零填充 Presence 矛盾、allKeys 别名泄漏)
        // ====================================================================
        // 1. F-11b: Zero-fill 下 decodeNil 与 decode 结论矛盾
        do {
            let decoder = YYJSONDecoder(mode: .legacy)
            let m = try decoder.decode(F11bModel.self, from: Data("{}".utf8))
            let actual = m.observedStatus
            let passed = !actual.contains("decodeNil=true,decode=absent")
            let expected = "decodeNil=false,decode=absent"
            rows.append(TestRecord(id: "F-11", scenario: "f11b_zerofill_decodenil_presence_conflict",
                                   passed: passed, actual: actual, expected: expected))
        } catch {
            rows.append(TestRecord(id: "F-11", scenario: "f11b_zerofill_decodenil_presence_conflict",
                                   passed: false, actual: "error: \(error)", expected: "decodeNil=false,decode=absent"))
        }

        // 2. F-11f: allKeys 暴露底层物理别名
        do {
            let decoder = YYJSONDecoder(mode: .compatible)
            let m = try decoder.decode(F11fModel.self, from: Data("{\"alias_name\": \"test\"}".utf8))
            let actual = m.observedKeys.joined(separator: ",")
            let passed = !m.observedKeys.contains("alias_name") && m.observedKeys.contains("prop")
            let expected = "prop"
            rows.append(TestRecord(id: "F-11", scenario: "f11f_allkeys_leaking_physical_aliases",
                                   passed: passed, actual: actual, expected: expected))
        } catch {
            rows.append(TestRecord(id: "F-11", scenario: "f11f_allkeys_leaking_physical_aliases",
                                   passed: false, actual: "error: \(error)", expected: "prop"))
        }

        // ====================================================================
        // 结果输出与退出
        // ====================================================================
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(rows)
        try data.write(to: URL(fileURLWithPath: outputPath))

        // 输出可读日志至控制台
        for row in rows {
            let tag = row.passed ? "PASS" : "FAIL"
            print("[\(tag)] \(row.id) - \(row.scenario): actual=\(row.actual), expected=\(row.expected)")
        }
        exit(0)
    }
}
