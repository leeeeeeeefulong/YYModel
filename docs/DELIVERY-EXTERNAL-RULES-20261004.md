# YYModel：OC 契约修复与 Swift 外部规则交付

本次交付的目标是：OC 保留 ibireme 原版默认契约并修复 fork 回归；Swift 用普通 Codable 模型获得 YYModel 的映射、容错和导出能力，同时保留直接调用 Foundation 的执行方式。所有工作位于组件仓库，没有读取、修改或使用 PPLive 工程作为验收标准。

这是 **2.2.0 引入、2.3.0 起正式发布的源码交付**（写作时为发布前的 master 快照），不是重新定义已发布 2.1.9。原版固定为 `c7df27538c043e5f54f5b6605958544bb529892f`；2.1.9 固定为 `00329f245752ed0e264e8c90bc14a6bd4e4e46e5`。已发布 tag 保持不动；使用这些接口应固定 2.2.0 及以上的 tag。

## 1. OC 修复结论

| 已确认的问题 | 本次行为 | 升级注意 |
|---|---|---|
| Pointer/CString 等不参与值比较，却计入 hash/count，导致不同对象误判相等 | hash/equality 共享参与类型规则；没有可比较字段时按实例身份处理 | 包括相同指针值、不同实例、NSSet、常数 hash 覆盖场景 |
| 父子 Mapper 自动合并改变原版默认覆盖 | 默认使用最具体有效 hook，与原版相同 | 依赖 fork 合并的类显式返回 `modelMergesSuperclassConfiguration=YES` |
| 泛型自动合并让原版未声明的数组隐式转模型并丢元素 | 同样恢复有效 hook 默认，合并与 Mapper 共用 opt-in | 黑/白名单仍按原版覆盖，开关不会合并名单 |
| 所有 NSObject 自动 conform YYModel | 移除 category-wide conformance，解析入口和 respondsToSelector 识别仍保留 | Swift NSObject hook 模型显式 conform YYModel 或导出 @objc hook；普通 Swift Codable 不需要它 |
| isSwiftDynamic 误把纯 OC Dynamic 标记识别为 Swift | getter 保留、deprecated、保守 NO | runtime Dynamic 标记使用 type 中的 PropertyDynamic；不猜来源语言 |
| l/L、PAC、缓存、最低系统与隐私声明存在错误宣传 | 注释与文档对齐已验证事实；移除无效 ObjCRuntime privacy 类别 | typed msgSend/caches 原版已有；iOS11 是分发支持政策 |

相对原版保留的实际增强包括 UInt64/NSDecimalNumber 边界处理、声明了允许成员类的安全容器归档、日期扩展与负毫秒/零字符串/非有限日期修正，以及可选的嵌套转换失败传播。它们扩大了能力范围，但不是全部异常输入与原版完全相同。SEL/long double 的比较扩展也有明确语义差异。

这轮已复现的 OC 问题均关闭；有限验收不能证明框架不存在任何未知缺陷。默认改变、迁移例子、安全归档允许类及日期歧义见 [OC 迁移说明](OBJC-MIGRATION.md)。

## 2. Swift 主入口与侵入性

```swift
struct User: Codable {
    let id: UInt64
    let name: String
    let age: Int?
}
let rules = try YYJSONRules().forType(User.self) {
    $0.mapper = ["id": ["id", "uid"], "name": "profile.name"]
    $0.requiredProperties = ["id"]
}
let decoder = YYJSONDecoder(mode: .compatible, rules: rules)
let user = try decoder.decode(User.self, from: data)
let output = try YYJSONEncoder(mode: .compatible, rules: rules).encode(user)
```

模型无需增加 YYModelCodable、NSObject、属性包装器、宏或手写 init/encode。只有特殊接口规则由 decoder 外部注册。既有 CodingKeys 自定义仍有效，规则名称使用其 stringValue。YYModelCodable 便利方法仍可用，但属于可选配置方式，和普通 Codable 使用同一增强引擎。

| 能力 | 原生 Codable + JSONDecoder | 本次 Swift 增强 |
|---|---|---|
| 标准 JSON、数组、嵌套 struct、Optional | 已支持 | `.native` 直接委托 Foundation |
| 同一属性多个接口别名、深层路径扁平映射 | 通常手写解码或另建 DTO | 外部 Mapper；导出形成对应嵌套 JSON |
| 数字/字符串混发、精确大整数、向零截断 | 类型不符通常报错 | 字段适配；非法后缀、溢出和非有限数值拒绝 |
| 缺失默认、required、黑/白名单 | 合成 Codable 不会自动使用属性初始化默认 | 显式外部规则；Optional null 保留 nil |
| 逐字段日期单位、业务转换与校验 | 需要容器代码或模型逻辑 | 外部字段策略与 typed hook |
| JSON discriminator 与普通枚举 payload | 通常手写分派 | 外部 variant 注册；payload 仍是普通 Codable |
| 已解析 JSON 对象、便捷文本输入与对称导出 | JSONDecoder 只有 Data 入口 | Data/String/Foundation 对象输入，Data/String/对象输出 |

规则是不可变类型快照，同一个模型可配不同 decoder；没有全局业务 schema/variant 缓存。业务初始化或 hook 抛出的错误原样上抛，不捕获任意错误后再初始化整个模型。坏数组元素不会静默删除，必需字段也不会因为“容错”被当作有效业务数据。

## 3. 原生执行方式与旧兜底的变化

原生能力保留：`YYJSONDecoder(mode: .native)` 与对应 encoder 直接调用 Foundation，并转交 date/Data/key/nonconforming-float/userInfo/outputFormatting 配置。它不扫描另一份 JSON，不试探初始化模型；有 YY 规则时明确拒绝，避免忽略配置。

增强模式先选定字段容器适配，Foundation 仍负责 Data 扫描。标准标量集合使用原生路径，整数集合采用轻量精确标量路径；不对每个元素重复做模型规则查询。所有整数数字 token 仍先取 Decimal，避免 `0.9999999999999999999` 被浮点舍入成1。只有内置标量/集合可以局部尝试，用户模型和自定义业务 hook 不会因兜底重复执行。

`YYJSONDecoder()` 保留已发布入口的 legacy 零值、空容器、自动日期语义，但不再采用“整个原生模型失败后重试整个宽松模型”的架构。保留的是转换能力与明确兼容模式，旧任意错误重试不是安全契约。标准数据需要原生速度时选择 `.native`；需要映射与容错时选择 `.compatible`。不承诺增强模式零开销。

新 encoder 的无参数默认也为 legacy，保证和既有 decoder 的 Unix 日期语义配对。显式 native/compatible 时两侧应使用相同 mode/rules；日期配置为 `.native` 的字段才委托 Foundation 日期策略。

## 4. 性能：同数据、同模型、相邻配对

以下是本次实际运行数据。宿主 Apple M1 Max/arm64、macOS26.7、Xcode26.6、Swift6.3.3、iOS26.5 SDK；执行于 **iOS26.5模拟器，非物理 iPhone**。OC 为 clang -O2，Swift 为 -O。每块预热5次、7个批次样本，按 A/B/B/A 顺序测量，计时与编译互斥。

业务数据来自仓库已保存的 Open-Meteo JSON，构造同一完整天气 DTO 的 clean/dirty/nullable/sparse/large 五种场景：包含位置、当前天气、小时/日数组、单位字典和 envelope。标准 JSON 15,785 bytes，类型混发 JSON 15,792 bytes，大数据501,555 bytes。测试不访问网络；公开消费者仅 import 已编译模块，比较完整模型与往返结果后才计时。时间排除文件读取、网络、最初对象构造/桥接、校验导出和编译。

OC NSArray 可以保留 Foundation 原始元素，Swift `[Int?]`/`[Double?]` 则对元素逐一转换/验证。完整业务字段 oracle 对 OC 数组作规范化比较，并不证明所有元素实际类型一致。因此原版/current 的同一 OC 模型比较、Foundation/YY 的同一 Swift DTO 比较最可比；不能把跨语言绝对时间差等同为同一种底层工作。

### OC 与 ibireme 原版

| 输入/API | 原版 ms/次 | 当前 ms/次 | 当前/原版：每轮比率中位 | 轮比率范围 |
|---|---:|---:|---:|---:|
| dirty Data，OC 调 OC | 0.300550 | 0.296956 | 0.9844 | 0.9754–1.0155 |
| clean Data，OC 调 OC | 0.297740 | 0.296985 | 0.9811 | 0.9801–1.0293 |
| 已解析 dirty 字典，OC 调 OC | 0.010847 | 0.010996 | 1.0215 | 1.0154–1.0272 |

dirty Data 六轮，其余三轮，每批1000次。毫秒值为合并样本中位，轮比率中位单独计算，两者不能混用。当前生产 OC 源码 SHA 与该计时构建一致；回执同时记录了构建时未用于独立 OC 计时的 Swift 辅助源码版本。

这组负载没有稳定的显著 OC 解析退化，已解析字典略慢约2%，Data略快约2%；不能据此宣布所有场景更快或绝对等效。已解析字典入口的时间排除了 JSON 扫描，因此比 Data 入口小很多；这是两种不同输入契约，不是可直接互换的吞吐数字。

### Swift 及混合调用

每组三轮ABBA，每批100次；下列毫秒值来自各组独立配对，不能把不同组的 baseline 混用。

| Swift Data 路径 | 对照 ms/次 | 当前 ms/次 | 每轮比率中位 | 轮比率范围 |
|---|---:|---:|---:|---:|
| clean，Foundation vs YY native | 0.737629 | 0.741807 | 0.9990 | 0.9872–1.0171 |
| clean，Foundation vs YY compatible | 0.747841 | 3.899161 | 5.1033 | 4.6982–5.2662 |
| dirty，已发布2.1.9 vs YY compatible | 4.072590 | 4.138599 | 1.0091 | 0.8689–1.0618 |

**已确认：原生模式保持 JSONDecoder 同等量级；增强模式约慢五倍，不能宣传为原生性能。** 增强路径提供精确整数、外部模型规则与单次业务初始化，这些有实际成本。本负载脏数据与2.1.9接近，没有证明稳定加速。Foundation/native 在dirty数据上正确拒绝，失败解码不参与计时。

初次开发测量增强clean约7.674ms、dirty约7.813ms，暴露了整数数组逐元素完整适配的开销；随后使用精确标量boxes并补齐集合有限值与raw null门禁。最终clean3.899ms、dirty4.139ms。这是跨轮开发观察，约减半用于定位与修正，不能当作相邻版本ABBA的稳定加速承诺。初次回执保留，避免只展示有利结果。

混合调用单独三轮ABBA，每批250次，均使用dirty天气数据。Swift的 `yy` 引擎为无参数 **legacy 模式**；不将这些数字冒充带外部规则的 compatible 计时。

| 混合调用比较 | 对照 ms/次 | 目标 ms/次 | 目标/对照轮比率中位 | 轮比率范围 |
|---|---:|---:|---:|---:|
| 混合二进制内：OC调OC vs Swift调OC，Data | 0.303054 | 0.305400 | 1.0226 | 0.9458–1.0331 |
| 混合二进制内：OC字典入口 vs Swift字典调OC | 0.011117 | 0.014350 | 1.2735 | 1.2641–1.3364 |
| OC独立产品 vs 混合链接中的OC调用，Data | 0.318272 | 0.321109 | 1.0065 | 0.9908–1.0750 |
| Swift独立 vs 混合链接中的Swift legacy，Data | 4.100540 | 4.042560 | 0.9951 | 0.9457–1.0085 |

Swift调OC值得保留测量：Data入口差异较小，已解析字典路径额外约3.23微秒，相对比例约27%，反映调用/字典桥接及结果访问成本。最初Foundation→Swift对象构造在计时外，反复传入Swift字典时的API桥接在计时内。它适合继续使用NSObject模型的混合工程；没有理由把纯struct先转换为OC模型以追求这些数字。

单纯混合链接在本负载没有显示稳定的大幅损耗。它不证明任意业务工程的启动、二进制大小或内存零成本，也不替代物理设备测量。上述时间只测解析；完整字段和导出往返是计时前门禁，导出耗时未作为本轮新性能结论。

## 5. 集中验收与复跑

先写失败场景与公开 E2E，生产实现完成后集中执行；性能暴露问题后，仅补充对应失败门禁、修改标量路径、复审和复验，没有新增单元测试套件。现有单元测试只复跑；恢复 OC 协议声明后，Swift 测试模型显式 conformance，断言不变。

最终公开Swift消费者/天气每环境62项、OC契约每环境33项、数值边界1792项及混合调用183项门禁均通过。原版XCTest27项与既有Swift测试16项也通过。原版断言未修改。当前 Xcode 的旧 iOS11 deployment/XCTest 链接提示、原版测试无 prototype block 警告仍存在，不称整个工程零警告；生产 Swift 两种语言模式编译均以 warnings-as-errors 检查。

最终仅移除了标量源码末尾一个多余LF；原始测量SHA保留，机器回执提供可精确重建的1字节对账，不修改已测结果。

机器可读入口：[本次交付回执](../Validation/receipts/external-rules-20261004.json)。它关联来源/驱动/fixture/二进制 SHA、逐项结果、原始配对样本、工具链、命令和本地 xcresult 路径。历史2.1.9及早期测量保留，不能用旧回执冒充本次接口数据。

仓库根目录复跑（模拟器需要先启动，UUID替换为本机实际值；每次使用新的输出目录）：

```sh
swift test -c release
python3 Validation/run_external_rules.py --output /tmp/yy-swift-mac
python3 Validation/run_external_rules.py --simulator <UUID> --benchmark --rounds 3 --iterations 100 --output /tmp/yy-swift-ios
python3 Validation/run_objc_contract.py --output /tmp/yy-objc-mac
python3 Validation/run_objc_contract.py --simulator <UUID> --output /tmp/yy-objc-ios
python3 Validation/run.py --only numeric --no-benchmark --output /tmp/yy-numeric
python3 Validation/run_delivery.py --no-benchmark --original-root <original-checkout> --simulator <UUID> --output /tmp/yy-interop
python3 Validation/research/20261004/remeasure_objc.py --existing /tmp/yy-interop --original-root <original-checkout> --iterations 1000 --output /tmp/yy-objc-pairs
python3 Validation/run_interop_pairs.py --existing /tmp/yy-interop --output /tmp/yy-mixed-pairs
```

`original-checkout` 固定在上述 ibireme commit。公开 Swift runner从仓库已保存的2.1.9 Git对象构建独立 PublishedYY 模块；浅克隆需要先获取该 tag。完整 OC 项目测试使用 `Framework/YYModel.xcodeproj` 的 YYModel scheme/Release 和本机模拟器。

## 6. 使用与维护边界

- 已有纯 Codable 标准接口先选 `.native`；复杂/不稳定接口在 decoder 外配置 `.compatible` 规则，旧调用需要兼容时保留 `.legacy`。
- 不反射/修改 Swift 私有内存布局，不猜属性初始化默认值。copy/equality/hash/更新/归档按 Swift 自身能力实现，不仿造 OC KVC 任意赋值。
- 日期秒/毫秒自动猜测仍有歧义，业务应声明单位；受控归档仍需要正确允许类和 NSSecureCoding 模型。
- 未测物理 iPhone、持续并发吞吐、峰值内存或所有旧Swift编译器。Swift5语言模式检查使用当前6.3.3工具链，不等于安装了Swift5.9工具链。
- SPM `YYModel`/`YYModelSwift` 产品与 CocoaPods `YYModel2/ObjC`、`YYModel2/Swift` 已独立选择，Swift产品无需链接OC。它们仍在同一仓库；拆成两个仓库是后续分发决策，不影响当前使用。

更完整的 API、错误策略与例子见 [Swift 外部规则](SWIFT-EXTERNAL-RULES.md)。

## 7. 2026-10-05 归档验证补充

生产源码与上列交付 SHA 完全一致。新增的未提交归档探针曾有重复类声明，原样不能编译；校正探针后检查有、无 generic 声明的旧非 secure 异构数组往返。macOS 与 iOS26.5 模拟器各 **43/43** 通过，其中原33项实际/预期结果逐项保持一致，新增10项验证成员数量、null、数字、模型类型和值。本场景没有复现库源码缺陷，不修改生产代码或扩大 secure 允许类。

原33项及性能回执保留为2026-10-04快照，无关性能未重跑。[新增机器回执](../Validation/receipts/archive-followup-20261005.json)保存当前来源与探针SHA及独立结果；[升级兼容指南](UPGRADE-COMPAT-GUIDE-20261004.md)给出准确的迁移边界和复跑方式。
