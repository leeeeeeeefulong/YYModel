> 本文是修复前的审查/调研快照。后续实现、已关闭问题、当前接口和新鲜测量见 [交付说明](DELIVERY-EXTERNAL-RULES-20261004.md)；本文旧数据不代表当前源码。

# Swift YYModel 方向复核与技术选型

日期：2026-10-04。审查源码：`f42d50a7e4f5bb622acb08efa3ac055b6bcd17e4`。已发布 `2.1.9`：`00329f245752ed0e264e8c90bc14a6bd4e4e46e5`。

本轮交付是源码复核、GitHub/官方资料调研、隔离 E2E 观察和技术选型；以下新接口是设计示意，尚未替换生产实现。没有使用或修改 PPLive 业务工程。`YYModelCodable` 是 master 的 Unreleased 新增方案，不属于已发布 2.1.9。

## 1. 目标和本次决策

目标是两项各自成立的交付：OC 保留 ibireme/YYModel 的成熟调用方式、业务契约和解析效率，并处理当前 SDK 的兼容问题；Swift 保留标准 Codable 模型和原生解析优势，将 YYModel 擅长的接口数据适配能力放在工具侧，减少模型迁移和手写解码代码。

选择 **普通 Codable + 解码器外部规则 + 原生直通/增强适配两种明确执行模式**。第三方模型协议、属性包装器和宏都不作为必要条件；也不通过 Swift 私有内存布局写属性。

上一轮将 mapper、钩子和便捷方法集中在 `YYModelCodable`，确实实现了部分 OC 风格功能，也减少了手写 `init(from:)`。但它把配置所有权放到了模型上，并增加了另一套主要入口，偏离了低侵入优先级。Swift 的 Decoder 协议并不要求这种额外模型协议。

“零侵入”在这里指 **无需 YY 专用模型声明**，模型仍须具备标准 `Decodable` / `Encodable` 能力。它不意味着能在没有配置的情况下猜出别名、日期单位或业务默认值，也不意味着所有增强可以零成本执行。

## 2. 已确认的现状

通过 `Validation/research/20261004/ArchitectureProbe.swift` 调用当前源码；使用 Swift 6、`-O`、`-warnings-as-errors` 编译，在 macOS arm64 执行。失败模式先写入同目录 `FAILURE-MODES.md`，回执包含模型源码、组件源码 SHA-256 和工具链。

| 观察 | 原生 / 旧接口 / 新接口的实际结果 | 含义 |
|---|---|---|
| 普通 Codable 嵌套数组 | `YYJSONDecoder` 解出两个普通 User，Optional null 保留 nil | 普通模型并不需要 YY 协议，嵌套本身也不是原生缺陷 |
| `uid → id` mapper | 同一个 YYModelCodable，旧 `YYJSONDecoder` 得到 0，新 `YYModelJSON` 得到 42 | 入口规则分裂，会产生“成功但字段错误” |
| 模型主动抛出业务错误 | 原生初始化 1 次；旧 `YYJSONDecoder` 2 次；新适配入口 1 次；最终均拒绝 | 旧整模型回退可能重复副作用，不能把所有 Error 都当类型容错信号 |
| `var name = "Guest"; var age = 18`，输入 `{}` | 原生报 keyNotFound；旧接口得到 `""` 和 0 | 声明初值、缺失字段默认值、零值是三个概念 |
| Date 的 JSON 数值 0 | 原生默认对应 Unix 秒 978307200；旧 YY 对应 0 | YY 日期策略不是原生默认策略的完全直通 |
| 字符串 UInt64 | `"9007199254740993"` 保真；`"123abc"` 拒绝 | 现有精确数字转换有复用价值 |
| 普通 Codable + 外部 policy 的内部能力探针 | 不增加 YY 协议，解出上述大整数和 `company.name` | 外部配置在技术上可行；这不是新公开 API 已完成的证明 |

现存旧 `YYJSONDecoder` 仍是“先原生，失败后整份 JSONSerialization + 容错 walker”。`2.1.9 → master` 对这个文件仅修改了 `_YYDecoder` 的访问级别，未移除原生兜底路线。问题是它的边界和新功能入口没有统一，而不是原生兜底已经不存在。

历史提交 `d02c88f` 引入普通 Codable 的 YYJSONDecoder；`139dc31` 加入原生优先路径；`f42d50a` 添加协议配置路线。`Bridge/YYModelBridge.swift` 当前不在 SPM / Pod 源文件集合中，不应把这份草稿当成已交付的完整 Swift 能力。

## 3. 原生 Codable 值得保留什么

编译器合成模型初始化/编码，标准 `Array`、`Dictionary`、`Optional` 和嵌套 Codable 组合，CodingKeys 重命名，原生日期/Data/key 策略和 `codingPath` 错误，都属于基础能力。结构差异可以通过标准容器自定义，但会增加手写代码。[Apple 官方说明](https://developer.apple.com/documentation/foundation/encoding-and-decoding-custom-types)

当前 Swift Foundation 开源实现直接扫描 UTF-8 JSON，并对字符串、数字等按请求解码，不是早年必然先构造完整 NSDictionary 的路线。普通格式正确的数据没有必要先整体变成 `[String: Any]` 再编码回 Data。[固定源码 a211bea 的 JSONDecoder](https://github.com/swiftlang/swift-foundation/blob/a211bea22b6fa5b041c37592aaf50c7b3db5c354/Sources/FoundationEssentials/JSON/JSONDecoder.swift)

上述 main 源码用于确认现代实现方向，不能据此断言 iOS 26.5 的每个内部细节完全相同。SDK 上的实际表现以本地 E2E 和性能回执为证据。标准协议的设计本来就允许自定义 Decoder 为同一 Codable 模型提供不同数据格式/策略，不需要给模型再绑定一种 JSON 框架协议。[SE-0166](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0166-swift-archival-serialization.md)

原生策略的能力也有边界：key 策略重命名单个键，不能直接代替有优先级的别名、跨层路径、缺失默认值和外部模型校验。Decoder 能看到请求的字段类型和 CodingKey，但没有公开通用 API 读取任意属性初始化表达式。

## 4. GitHub 方案比较

以下是文档和定点源码审查，不是这些库在本机的同场性能排名。

| 路线 / 项目 | 核心手段 | 对模型的影响 | 对本项目的取舍 |
|---|---|---|---|
| 原生 JSONDecoder | 标准 Codable、编译器合成、策略 | 只需 Codable | 保留为无增强路径的实际执行器 |
| BetterCodable | Default、Lossy、LosslessValue 属性包装器 | 特殊字段增加包装器；合成存储类型也改变 | 借鉴字段局部处理，不作为必要依赖 |
| CodableWrappers | 日期/默认/容错包装器及 key 宏 | 标注特殊字段或类型 | 减少手写，但不是模型零改动；3.x README 明示不支持 CocoaPods |
| MetaCodable / ReerCodable | 宏生成 mapper、路径、别名、默认、编码代码 | 类型/字段增加宏标注 | 编译期生成优雅，仍有模型和工具链耦合；不是本次核心路线 |
| SmartCodable | 自有 Decoder、默认实例、类型转换、映射钩子 | 核心方案要求 SmartDecodable / SmartCodable 类协议及 `init()` | 功能接近 OC，但再次要求专用协议不能解决当前诉求 |
| ZippyJSON | 替换 Decoder 底层、simdjson | 模型仍可标准 Codable | README 自述 iOS 17+ 原生更快，不能照搬旧性能宣传 |
| ReerJSON | yyjson + Codable Decoder/Encoder | 模型仍可标准 Codable | 是解析引擎候选，不是 mapper/default 方案；所查 main 要 Swift 6.4，本机 6.3.3 无法直接构建这一版 |
| HandyJSON | Swift 元数据和内存直接写入 | 自有协议和初始化约束 | 不采用依赖私有布局来模拟 OC Runtime 的路线 |

来源：[BetterCodable](https://github.com/marksands/BetterCodable)，[CodableWrappers](https://github.com/GottaGetSwifty/CodableWrappers)，[MetaCodable](https://github.com/SwiftyLab/MetaCodable)，[ReerCodable](https://github.com/reers/ReerCodable)，[SmartCodable](https://github.com/iAmMccc/SmartCodable)，[ZippyJSON](https://github.com/michaeleisel/ZippyJSON)，[ReerJSON](https://github.com/reers/ReerJSON)，[HandyJSON](https://github.com/alibaba/HandyJSON)。

定点源码证据：BetterCodable `2b4a27f` 的 `DefaultCodable.swift` 用包装器和 keyed-container 重载提供默认；SmartCodable `bc1522f` 的 `SmartDecodable.swift:22–33` 要求额外协议及 `init()`；ReerJSON `db97217` 的 `Package.swift:1` 为 tools 6.4，并引入 yyjson / JJLISO8601DateFormatter。这些取舍有明确依据，但不代表已审计其所有错误和精度边界。[包装器源码](https://github.com/marksands/BetterCodable/blob/2b4a27f03c8fe80f195ac2b6ac1764213406ee89/Sources/BetterCodable/DefaultCodable.swift)、[SmartDecodable 源码](https://github.com/iAmMccc/SmartCodable/blob/bc1522f6b635128ea992331867fe65f231492dc0/Sources/SmartCodable/Core/SmartCodable/SmartDecodable.swift)、[ReerJSON manifest](https://github.com/reers/ReerJSON/blob/db972175173aeb3b83c256534499c63ad8cfe720/Package.swift)

Swift 团队还在 experimental/new-codable 分支探索新协议和宏。这是调研信号，不能当作当前系统标准 API，或要求用户为它迁移模型。[官方原型公告](https://forums.swift.org/t/new-codable-prototype-available-for-feedback/85186)

## 5. 选择的结构和行为边界

### 5.1 一个配置入口，两个清楚的执行模式

推荐主入口继续叫 `YYJSONDecoder`，配套 `YYJSONEncoder`；它们接受普通 Decodable / Encodable。业务规则由调用侧定义，可在网络层统一复用。同一个模型在不同 API 下可以使用不同规则，不使用按模型类型永久缓存业务配置的全局状态。

- **原生模式**：直接交给配置好的 Foundation JSONDecoder / JSONEncoder，保留所有原生语义及错误。没有额外扫描、模型协议查询或整模型重试。它的目标是原生加薄入口成本，具体比例仍要实测。
- **增强模式**：在调用模型初始化前就选择容器适配路线；Data 的扫描仍由 Foundation 执行。仅在字段请求处做规则映射和已声明的转换，不先失败整份模型再重建。
- 严格模式遇到不能由原生表达的规则，应明确拒绝配置或要求选择增强模式，不能悄悄忽略 mapper。
- 如果顶层没有配置、但嵌套类型有配置，增强模式仍需把上下文传入嵌套解码；不能因为顶层普通 Codable 就直接绕过子类型规则。标准协议没有安全、免费的模型图发现机制，不通过试初始化探测它。

接口示意，不是当前可编译 API：

```swift
struct User: Codable {
    let id: UInt64
    let name: String
    let age: Int?
}

// 放在网络/适配层，User 本身完全不改。
let rules = YYJSONRules()
    .forType(User.self) {
        $0.map("id", from: ["id", "uid"])
        $0.map("name", fromPath: ["profile", "name"])
        $0.require("id")
    }
let decoder = YYJSONDecoder(mode: .compatible, rules: rules)
let user = try decoder.decode(User.self, from: data)
```

规则以模型 metatype 标识，键使用 **CodingKey.stringValue**，不是猜测内存属性名。规则集合是实例范围的不可变快照，嵌套模型、数组、字典共享一次调用的上下文。配置拼写错误不能靠反射保证消除，关键字段校验和诊断必须暴露出来。

### 5.2 增强功能的取舍

| 能力 | Swift 设计 |
|---|---|
| 数字/字符串/布尔混发 | 复用经过精度和范围验证的字段转换，不经 Double 中转所有整数 |
| 别名和 KeyPath | 外部规则、确定的匹配优先级；路径节点非法安全失败；null 是否阻止后续别名单独定义 |
| 缺失和 null | Optional 保留 nil；非 Optional 不自动等同有效业务值；显式默认/零值策略才能补值 |
| 声明默认值 | 可以显式提供字段默认或默认实例工厂；不承诺自动发现任意 `var x = expression` |
| 数组容错 | 默认保留顺序和完整性；跳过坏元素需显式选择并记录索引，不静默丢数据 |
| 日期 | 原生策略保留；增强可配置每类型/字段单位和格式；秒/毫秒启发式不是精确单位判断 |
| 校验/转换钩子 | 外部类型安全闭包；普通 typed 校验不要求物化整份 JSON；需要原始字典的钩子才承担该成本 |
| 多态 | 外部注册 discriminator + 实际 Decodable 类型/enum 构造闭包；不猜类名，不扩大任意运行时创建 |
| 导出 | 相同规则的 Encoder，多个输入别名必须指定唯一输出键；路径冲突报错，不覆盖数据 |
| 已解析 JSON 对象 | 增强模式直接处理对象；原生公开 API 需要 Data 时明确记录重新编码成本 |
| 更新/归档/hash/equality | 先保留 Swift 的值语义和标准协议，不将 OC 对象身份、任意 KVC 和安全归档伪装成 struct 同等能力 |

“尽量不手写”可以实现为通用策略一次选择、例外规则集中配置，而不是每个模型写 init/encode。不同业务接口的别名、必填项和默认值仍然需要真实规则，这是数据契约的必要信息。

### 5.3 不采用的替代方案

不选择“整份 JSON 先规范化，再重新编码给原生”的主路线：虽然模型无需变化，但会增加完整物化/复制/编码，并可能在规范化中损失大数信息。局部业务预处理可以保留。

不复制维护一份完整 Foundation 私有 JSONDecoder：性能路线的长期成本包括解析器语法、数字、错误、日期、字典特殊处理和未来工具链变化。当前目标是减少业务适配代码，不是维护一个系统 Foundation 分支。

不把“所有 Error 都兜底”作为增强语义。只处理正在请求的已知标量/容器差异；模型自行抛出的 Error 继续原样上抛。避免根模型第二次初始化，但需要每个自定义值类型的原生初始化语义仍保持一次调用。

## 6. 性能证据及未验证事项

上一轮的 iOS 26.5 模拟器配对数据：原生 clean 0.846ms，新协议适配路径 1.090ms，比值 1.288；dirty 旧整模型回退 4.683ms，新字段适配 1.215ms。它说明字段适配对容错有价值，也有标准数据开销。不能推断“协议声明本身造成全部 29%”，也不能把失败的原生解码作为成功吞吐基准。完整条件见 `Validation/RESULTS-swift-model.md`。

**已确认**：无额外 YY 模型协议也能通过现有内部容器实现根级映射和精确数字转换；普通 Codable 的现有嵌套基础能力可用。

**合理推测**：把规则外置后，可复用已有字段适配、精确数字和导出能力；无增强直通可以避免标准模型上的适配循环成本。

**尚未验证**：新的外部规则在完整嵌套图上的执行成本、首次解码时延、内存峰值、规则并发隔离、完整 Encoder 对称性以及物理设备性能。内部根级探针没有证明这些已经完成。

验收必须使用同一 DTO、同一输入和全部字段检查，区分 Data 输入、已解析对象输入和导出。冷启动与重复解析分开；Release 下相邻 ABBA、多轮记录完整样本。固定公开天气 API 快照、生成脏/缺失/异构数据，先正确性后计时；网络和磁盘读取不混入纯解析时延。禁止以正式业务项目的测试状态代替组件验收。

## 7. OC 独立复审结果

独立代理比较原版 `c7df275`、已发布 2.1.9 和当前 master；详细结论及复测方法见 `OBJC-INDEPENDENT-REVIEW-20261004.md`。

- 已发布版本确实不只做废弃 API 更新；包括配置继承合并、数值/日期扩展、安全解档、hash/equality 和 opt-in 嵌套拒绝策略。
- 父子 mapper/generic 自动合并改变原版“子类覆盖”默认契约。黑/白名单仍与原版采用顶层 hook，不能泛称四者都合并。
- 仅含 void* 属性、hash/isEqual 正确委托 YY 方法的不同模型，在 fork 被错误判为相等；原版的身份兜底没有这个结果。这是独立探针确认的实际回归，尚未修复。
- 本次 iOS 26.5 模拟器独占 ABBA：dirty/Data 六轮 current/original 中位比 **1.011895**，范围 **0.975475–1.035324**；clean/Data 三轮中位 **1.011733**；dirty/object 三轮中位 **0.998664**。此前 18.35% 没有稳定复现。不能据此宣称所有路径、所有输入或物理设备完全等效。

优先恢复原版无法比较属性的身份 fallback；继承配置合并应作为明确的可选扩展，并为当前 fork 用户保留迁移说明。旧的某些“fixed/restored”记录是在恢复中间 fork 的退化，而非相对 ibireme 的新增，文档也需区分。

## 8. 实施顺序和发布边界

1. 先把原版 OC 契约、Swift 低侵入边界以及当前差异写成可重复的失败 E2E；包含初始化次数、错误类型/路径、默认值、嵌套规则和整数精度。
2. 在现有 YYJSONDecoder 上增加显式原生模式及完整原生策略传递；无增强路径先达到原生正确性，单独测入口成本。
3. 把模型配置抽取成实例范围规则，并复用现有容器适配。先支持普通 Codable 的根/嵌套/数组/字典，再接外部钩子与多态注册；不要为通过测试增加必需模型协议。
4. 配套 Encoder 使用同一规则，先完成别名/路径/日期/过滤的确定性往返，再增加便捷 JSON 对象入口。
5. 核对旧 2.x 调用语义。已发布 `YYJSONDecoder()` 的旧默认不能在小版本里静默改成严格原生；通过显式模式迁移。Unreleased 的 YYModelCodable 可降为兼容便利层，规则归一后不再形成独立主引擎。
6. 按组件独立 E2E、原版 OC 对照、同 DTO 原生 Swift 对照、模拟器和具备条件时的物理设备交付回执。公开测试夹具与报告，满足后再决定独立包版本和发布；不移动旧标签。

最终验收标准是：普通 Codable 模型不改；普通数据可以选择原生语义和执行器；增强数据无需重复写解码器；失败不会被伪装成有效零值；优势、代价和兼容范围有可重复数据支持。
