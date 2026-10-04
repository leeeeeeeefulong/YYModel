# Swift：普通 Codable 与外部规则

本接口在 master 的 Unreleased 源码中，已发布 2.1.9 tag 不含这些新接口。安装 Swift 独立 SPM 产品 `YYModelSwift`，或 CocoaPods 的 `YYModel2/Swift`；无需链接 OC 产品。

## 选择执行方式

| 入口 | 执行器 | 缺失 / null 非 Optional | 日期默认 | 适用场景 |
|---|---|---|---|---|
| `YYJSONDecoder(mode: .native)` | 直接 Foundation JSONDecoder | 原生规则 | deferredToDate，数值从2001年起 | 标准 Codable 数据及完整原生策略 |
| `YYJSONDecoder(mode: .compatible, rules: rules)` | Foundation 扫描 + 字段容器适配 | 必须存在或提供默认；不会默默变0 | 原生策略；可按类型/字段扩展 | 接口别名、嵌套路径、类型混发和业务校验 |
| `YYJSONDecoder()` / `.legacy` | 相同字段引擎的旧语义 | 旧零值/空容器兼容 | YY 自动秒/毫秒/文本，导出秒 | 已发布2.x调用迁移 |

所有模式支持普通 Decodable/Encodable。无参数 encoder 与 decoder 都默认 legacy，以保证日期往返；新接口请显式配对相同 mode 和 rules。`.native` 不读取 YYModelCodable 配置，且遇到非空 YYJSONRules 会报配置错误。原生模式不会先扫描另一份 JSON，也不会试初始化模型。增强模式同样不捕获任意错误再重试整个模型；模型主动抛出的业务错误原样上抛。

日期采用 `.native` 策略时，可配置原生 `dateDecodingStrategy`、`dataDecodingStrategy`、`keyDecodingStrategy`、`nonConformingFloatDecodingStrategy`、`userInfo`；Encoder 有对应策略及 `outputFormatting`。原生模式的非有限浮点策略保持 Foundation 行为；增强模式仍拒绝非有限数值。Swift6 工具链的公开 decoder userInfo 值遵循 Sendable 要求。

## 模型本身不改

```swift
import YYModelSwift

enum MyError: Error { case invalidUser }
struct User: Codable {
    let id: UInt64
    let name: String
    let age: Int?
    let created: Date
}
struct Response: Codable {
    let users: [User]
    let byID: [String: User]
}

let rules = try YYJSONRules().forType(User.self) {
    $0.mapper = ["id": ["id", "uid"], "name": "profile.name"]
    $0.requiredProperties = ["id"]
    $0.fieldDateStrategies = ["created": .millisecondsSince1970]
    $0.validate = { user in
        guard user.id > 0 else { throw MyError.invalidUser }
    }
}
let decoder = YYJSONDecoder(mode: .compatible, rules: rules)
let response = try decoder.decode(Response.self, from: data)
let output = try YYJSONEncoder(mode: .compatible, rules: rules).encode(response)
```

规则键是 **CodingKey.stringValue**。例如 CodingKeys 的 `case id = "identifier"`，规则就配置 identifier。不存在通用公开反射能证明规则拼写与所有模型属性一致，因此关键字段必须显式校验。

规则集合按 metatype 标识、不可变追加；`forType` 对同类型替换配置，并保留已注册的多态分派。普通父模型无需为了让子模型规则生效而注册或实现协议。数组、Optional、String/Int 键字典传递同一次调用的上下文；字典数据键保持原值，不当成模型 CodingKeys。相同 User 可以在两个 decoder 中使用不同规则，没有进程级业务配置缓存。纯 Swift 类继承仍遵循 Codable 自己的 super.init/encode；forType 匹配具体类型，不反射合并 Swift 父类配置。

## 映射、默认、过滤

```swift
let rules = try YYJSONRules().forType(User.self) {
    $0.mapper = [
        "id": ["id", "uid", "meta.uid"],
        "name": .path("profile", "name"),
        "created": .key("created.at") // 字面点号键，不是路径
    ]
    $0.defaultValues = ["name": "Guest"]
    $0.requiredProperties = ["id"]
    $0.blacklist = ["age"]
}
```

别名按声明顺序取第一个存在的键；显式 null 会阻止后续别名，不会自动绕过。非法中间节点安全视为该路径未命中。导出选择第一个别名路径，形成真正嵌套 JSON；重复/前缀冲突报错，禁止覆盖。

Optional 缺失/null 保留 nil；缺失且声明了默认时使用默认，显式 null 不被默认覆盖。默认值必须是支持的 JSON 值，注册时复制，防止 NSMutableDictionary/Array 后续修改污染规则。声明 `var age = 18` 不等于 Codable 的缺失默认；框架不会猜初始化表达式。`.missingStrategy = .zeroFill` 是主动选择的类型策略，不能把自动补值当作业务校验通过。

黑/白名单过滤后，非 Optional 字段仍需显式默认或零值策略；required 与过滤冲突在配置时失败。空白名单拒绝该模型。数组保持顺序/数量，坏元素使解析失败；当前没有静默丢元素开关。

## 精度与日期

增强路径保留 UInt64 全范围、雪花ID和 Decimal 转换；整数转换向零截断，非法后缀/溢出拒绝，不把所有数值先转 Double。Foundation 对数值 token 的范围/精度仍是底层边界，不承诺任意长度十进制精度。

外部 `forType` 默认 `.native` 日期；`.dateStrategy = .automatic` 主动选择 YY 自动识别；或选择 secondsSince1970 / millisecondsSince1970 / iso8601。`fieldDateStrategies` 优先处理该字段及其 Date 容器值；编码使用相同单位。秒/毫秒启发式不能替代服务端单位契约。

Data 输入继续由 Foundation 扫描。已经解析的 Foundation 对象在增强模式直接读容器；使用原生 Date/Data 策略时，相关字段可能重新编码为标量 Data 以保持 Foundation 语义，自定义策略获得原字段路径及严格容器。原生模式的对象入口必须整份序列化为 Data；这项成本不能算成 JSONDecoder 原生解析加速。

## 外部钩子与多态

```swift
let rules = try YYJSONRules().forType(User.self) {
    $0.transform = { $0 = User(id: $0.id, name: $0.name.trimmingCharacters(in: .whitespaces), age: $0.age, created: $0.created) }
    $0.validate = { if $0.id == 0 { throw MyError.invalidUser } }
}
```

typed transform/validate 不物化原始字典。只有 willTransform/didTransform 请求原始字典时才懒构造 JSON 快照；导出 transformTo 在字段编码完成后拿到物理 JSON 字典，新增键按原样写入，不再次应用 keyEncodingStrategy。业务错误保留，初始化和每次钩子不以整模型重试重复执行。

```swift
struct Text: Codable { let body: String }
struct Count: Codable { let count: Int }
enum Event: Codable { case text(Text), count(Count) }

let rules = try YYJSONRules()
    .forType(Text.self) { $0.mapper = ["body": "payload.body"] }
    .polymorphic(Event.self, discriminator: "type", variants: [
        "text": YYModelVariant(Text.self, create: Event.text, extract: {
            if case .text(let value) = $0 { return value }; return nil
        }),
        "count": YYModelVariant(Count.self, create: Event.count, extract: {
            if case .count(let value) = $0 { return value }; return nil
        })
    ])
```

不需要手写分派 init/encode 或 YY 模型协议。payload 字段规则放在 payload 类型；根多态类型的字段/日期规则不可静默忽略。未知/歧义 variant、discriminator 与 payload 冲突报错。导出选中 payload 的字典会物化，这是该可选功能的实际成本。

## 兼容与限制

- YYModelCodable/YYModelJSON 的既有便利方法调用同一引擎；模型协议是可选的配置所有权选择，不是主入口条件。
- 旧 no-argument 入口保留零值与日期语义，但标准数据也走字段适配，不能承诺旧 native-first 快路径的全部性能。需要原生速度/契约，显式选择 `.native`。
- 输入 convenience 支持 Data、JSON 文本 String、Foundation JSON 对象；String 参数表示 JSON 文本。输出支持 Data、String 和 JSON 对象。
- 规则快照不包含隐式线程安全业务状态。decoder/encoder 配置完成后再共享；同步闭包捕获的可变状态，避免在初始化结束后保存/跨线程使用 Decoder/Encoder。
- Swift copy/equality/hash/archive/更新仍使用语言标准能力；不伪装成 OC KVC 任意写属性或对象身份。
- 当前验证为 Apple Silicon/macOS/iOS26.5模拟器，没有物理 iPhone 数据；工具链实际为Swift6.3.3，另检查Swift5语言模式，不等于安装了所有旧Swift5.9编译器。

公开消费者 E2E 与复跑命令见 `Validation/run_external_rules.py`；性能条件和当前数据见 `DELIVERY-EXTERNAL-RULES-20261004.md`。
