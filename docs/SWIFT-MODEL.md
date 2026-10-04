# Swift YYModel 使用与合同

此文档对应 `master` 的未发布实现。2.1.9 tag 不含 `YYModelCodable`；不要把新接口写成已发布的 2.1.9 能力。

目标是普通 Swift struct 使用 YYModel 风格的快捷接口，利用 Codable 自动合成，减少逐个模型手写解码。底层用 Foundation Decoder/Encoder 容器；字段映射、默认值、精确转换与模型钩子由 YYModel 适配层实现。Swift 5.9+ 工具链，iOS 验证环境为 26.5。

## 最小调用

```swift
import YYModelSwift // SPM。CocoaPods 的模块名是 YYModel2。

struct User: YYModelCodable {
    var id: UInt64
    var name: String
    var companyName: String
    var age: Int?

    static var yy_modelConfiguration: YYModelConfiguration<Self> {
        .init(mapper: ["id": ["id", "uid", "meta.uid"],
                       "companyName": "company.name"],
              requiredProperties: ["id"])
    }
}

let user = User.yy_model(withJSON: data) // String / Data / 已解析 JSON 对象
let diagnostic = try User.yy_decode(withJSON: data) // 字段错误提供 CodingPath
let fromDictionary = User.yy_model(with: dictionary)
let users = User.yy_modelArray(withJSON: arrayData)
let exported = user?.yy_modelToJSONObject()
let bytes = user?.yy_modelToJSONData()
let text = user?.yy_modelToJSONString()
```

不需要 NSObject，不需要常规模型的 `init(from:)` 或 `encode(to:)`。嵌套 struct 也声明 `YYModelCodable`，其配置在数组、字典、Optional 中自动生效；普通 Codable 载荷可以混用，但没有自己的 YYModel 配置。

数组提供 JSON 对象/Data/String 导出。`YYModelJSON.decode(_:from:)` 和 `YYModelJSON.encode(_:)` 支持通用数组、字典以及 Codable 根值。Optional 快捷入口失败返回 nil；需要诊断时使用 throwing 入口，不要依靠 nil 猜测原因。

## 映射与过滤

Mapper 的左侧是 Codable 字段键。自动合成 CodingKeys 时就是属性名；如果已有 `case id = "identifier"`，Mapper 左侧应写 `identifier`。右侧字符串表示点号 KeyPath，数组表示有顺序的备选路径。

- 第一个**存在**的候选生效；显式 null 不会偷偷跳到下一别名。
- 中间节点不是对象时，该路径视为缺失，不触发 KVC。
- 导出使用第一个候选，递归生成嵌套对象。相同输出位置及父子输出路径冲突报错。
- JSON 的字面量 `"a.b"` 键使用 `.key("a.b")`；显式组件使用 `.path("company", "name")`。
- `blacklist` / `whitelist` 同时控制输入和输出，空白名单拒绝整个模型。
- `requiredProperties` 对缺失/null 报错，包括 Optional；不能配置为被黑白名单排除。
- `defaultValues` 对缺失的允许字段生效。未配置时，基础值用 0/空字符串/false，Optional 用 nil，集合用空集合。无法构成复杂值时抛错。

Swift 自动合成 Codable 不保留任意属性声明的初始值。例如 `var count = 7` 不是 JSON 缺失时的统一默认机制；需显式 `defaultValues:["count":7]`。只读属性、被 CodingKeys 排除的属性也遵守 Swift 编译器自己的规则，框架不使用反射强行写入。

Swift Foundation 类型遵守 Codable 的线格式，例如 Data 使用 Base64；不把它和 OC 的 NSData UTF-8 字符串转换混为同一合同。

数值转换保留整数范围及 Decimal 精度。JSON 对象中的数字使用 NSNumber / NSDecimalNumber；涉及精确 Decimal 时优先直接导出 JSONData/String，外部序列化器可能经 Double 舍入。非法后缀、溢出和非有限数字报错；不能把精确 ID 声明为 Double 后再要求 UInt64 保真。

## 转换钩子

```swift
static var yy_modelConfiguration: YYModelConfiguration<Self> {
    .init(
        willTransform: { dictionary in
            guard dictionary["deny"] as? Bool != true else { return nil }
            return dictionary
        },
        didTransform: { model, _ in
            model.name = model.name.trimmingCharacters(in: .whitespaces)
            return model.id > 0
        },
        transformTo: { model, dictionary in
            // 自动字段已导出，可以读取或修改。
            dictionary["validated"] = model.id > 0
            return true
        }
    )
}
```

will 返回 nil，或 did/to 返回 false，均拒绝对应操作。嵌套拒绝传播到根；不默默丢弃数组里的坏模型。新接口不会在原生解码失败后再初始化整个模型，避免初始化/钩子的业务副作用重复。导出钩子产生非 JSON 对象时失败。

配置按类型缓存，按不可变声明使用。钩子捕获的业务对象、计数器等由调用方保证并发安全；框架没有把任意 struct 自动声明为 Sendable。

## 日期线格式

默认 `.automatic` 识别 Unix 秒、绝对值大于 1e11 的毫秒、ISO8601、常见日期文本及 RFC/asctime；默认导出 Unix 秒，与常规 Unix 秒输入保持同一时间原点。

业务存在小数/很早的毫秒日期或极大秒值时，明确声明 `.secondsSince1970` / `.millisecondsSince1970`；需要字符串时声明 `.iso8601`。直接的 Date 数组、字典、Optional 使用所在模型的策略。嵌套 YYModelCodable 模型使用自己的策略（默认 automatic）；普通 Codable 子载荷沿用父策略。非有限日期拒绝。

自动识别是启发式，不是时间单位的证明。不要混用默认 JSONEncoder 的 2001 年原点；使用 YYModel 导出，或给原生 JSONEncoder 明确设置 `.secondsSince1970`。

## struct 载荷多态

Swift struct 没有继承。用关联值 enum 注册载荷类型，不手写 Codable 分派：

```swift
struct TextMessage: YYModelCodable { var body: String }
struct CountMessage: YYModelCodable { var count: Int }

enum Message: YYModelPolymorphic {
    case text(TextMessage), count(CountMessage)
    static var yy_modelVariants: [String: YYModelVariant<Self>] {
        ["text": .init(TextMessage.self, create: Self.text, extract: {
            if case .text(let value) = $0 { return value }; return nil
        }),
         "count": .init(CountMessage.self, create: Self.count, extract: {
            if case .count(let value) = $0 { return value }; return nil
        })]
    }
}
let messages = Message.yy_modelArray(withJSON: #"[{"type":"text","body":"hello"},{"type":"count","count":"7"}]"#)
```

默认判别键为 `type`，可用 `yy_modelDiscriminator` 指定路径/别名。未知判别值、无匹配或多个匹配拒绝；导出写回判别值，和载荷的冲突报错。

字段 Mapper、过滤、required/default 配置声明在具体载荷 struct 上；enum 自身配置只使用转换钩子；日期策略也声明在载荷模型上，不支持直接配置其不存在的统一字段表，框架会拒绝这类配置。Swift Codable 类继承仍需遵守 Swift 的父类解码规则，不能把 struct enum 分派描述成 OC 子类工厂。

## 旧接口和原生路径

`YYJSONDecoder` 保留，用于已有普通 Codable 模型：原生 JSONDecoder 先尝试，失败再走已有容错解码器。这个完整模型重试机制仍然存在，兼容旧调用。

YYModel 配置应通过 `yy_model` / `yy_decode` / `YYModelJSON` 执行。普通 struct 直接交给原生 JSONDecoder 或旧 YYJSONDecoder 时按普通 Codable 处理，不会自动应用这些配置。

新 `YYModelCodable` 路径则由一次模型初始化中的原生容器处理 JSON；正常标量及纯标量集合直接解码，偏差字段局部转换，Mapper/钩子始终参与。不能为了走根对象的原生快路径而跳过嵌套配置。需要字典的解码钩子按需获取本次输入的 Foundation 快照，并按真实 CodingPath 定位子模型；同一次 Data 解码共享快照，普通模型不创建。willTransform 修改后的字典仍需逐字段转换，成本会高于无钩子路径。标准 JSON 的原生 Codable 仍可能更快；新增能力和脏数据效率用实测说明，不能承诺全面快于原生。

早期 `Bridge/YYModelBridge.swift` 没有进入发布产品，其少量包装不构成完整 Swift YYModel。不要把这个历史文件作为新入口。

## 独立使用

SPM 产品本来就是独立的：只添加 `YYModelSwift` 不依赖 OC target；只添加 `YYModel` 不编译 Swift。CocoaPods 在此次未发布改动中提供：

```ruby
pod 'YYModel2/Swift', :git => 'https://github.com/leeeeeeeefulong/YYModel.git', :commit => '<已交付提交>'
pod 'YYModel2/ObjC',  :git => 'https://github.com/leeeeeeeefulong/YYModel.git', :commit => '<已交付提交>'
# 默认 YYModel2 仍同时安装两者。
```

组件代码、天气快照与复跑脚本均在本仓库；不使用正式业务 App 验收。回执见 `Validation/RESULTS-swift-model.md`。
