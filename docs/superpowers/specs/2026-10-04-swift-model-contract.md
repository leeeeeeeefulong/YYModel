# Swift YYModel 合同与设计

用户已经确认：普通 Swift struct，不继承 NSObject；YYModel 风格快捷 API、声明式 Mapper、多 key、KeyPath、转换钩子和 JSON 导出；尽量不手写 init(from:)。系统验收基准固定 iOS 26.5。先完成，再拆分分发；不得用业务 App 验收。

## 判断与取舍

- 现状不是最近删除了完整 Swift YYModel：Bridge 早期未进入发布产品；现有 YYJSONDecoder 只实现 Codable 容错。需求层面的完整模型接口一直缺失。
- 只加 User.from(json:) 包装不满足映射/钩子要求；反射不能可靠修改任意 Swift struct。使用 Swift 宏生成模型代码可减少手写，但会新增编译插件与 swift-syntax 版本维护，当前不选。
- 采用 Codable 自动合成 + 原生 Decoder/Encoder 容器适配器。普通值直接利用 Foundation 的解析器；字段有类型偏差时复用已有精确转换，按字段回退，避免整个模型初始化两次。元数据缓存存储声明式配置，不缓存用户模型。
- 配置/钩子是显式能力；不能把 JSONDecoder 的自动合成误称为 YYModel 的 Mapper 自动实现。便捷入口有返回 Optional 的 OC 风格版本，也有 throwing 版本提供错误路径。
- struct 没有子类。多态用关联值 enum 的声明式变体注册表；每种载荷仍是普通 struct，不手写 Codable 初始化。不能承诺不存在的 struct 继承或任意 existential 自动合成。

## API 合同

`YYModelCodable: Codable` 默认自动合成，仅有默认空配置。`YYModelConfiguration<Self>` 提供 mapper、blacklist、whitelist、requiredProperties、defaultValues、dateStrategy、willTransform、didTransform、transformTo。

Mapper 的键是 Codable 字段键（自动 CodingKeys 时就是属性名）。字符串值表示点号路径，数组表示有顺序的备选；需要字面量点号键时显式 `.key`。解析选择第一个存在的候选，null 不偷偷跳到后一个；导出使用第一个路径。非法路径或冲突导出不得静默覆盖。

快捷入口：`User.yy_model(withJSON:)` 接受 String/Data/JSON 对象，`User.yy_model(with:)` 接收字典；数组入口 `User.yy_modelArray(withJSON:)`；对应 throwing `yy_decode` / `yy_decodeArray`。导出 JSONObject/Data/String 以及 throwing `yy_encode`。数组导出和已解析对象不做无意义 struct→JSON→OC 重解析。

黑/白名单作用于输入与输出。被忽略/缺失的基础类型用明确零值或配置 defaultValues；Optional 用 nil；复杂值由其 Codable 合成解码，无法形成值时抛错。不能读取并承诺保留所有 Swift 属性声明默认值。空白名单拒绝模型解析/导出，防止误当全开放。

requiredProperties 对缺失/null 报错，包括 Optional；非法数字、溢出、非有限值不默默变成正常数。Date 默认自动识别，导出 Unix 秒；可明确秒/毫秒/ISO8601，避免默认 JSONEncoder 的 2001 时间原点混用。

willTransform 在初始化前执行一次；didTransform 在字段赋值后执行一次，可修改 struct，返回 false 则拒绝；transformTo 在自动字典生成后执行，可修改导出字典，返回 false 则拒绝。嵌套配置/钩子自动进入模型数组、字典、Optional，失败传播。业务钩子由调用方保证并发安全，框架不把任意模型自动声明 Sendable。

`YYModelPolymorphic` 关联值 enum 声明 discriminator 与 `YYModelVariant` 注册表，未知类型、重复匹配或不匹配拒绝；导出写回 discriminator。字段与日期配置在载荷模型声明；enum 根只接受转换钩子，其他配置明确拒绝，防止接受后静默失效。类 Codable 继承仍遵守 Swift 自身规则，不承诺自动合成父类初始化。

## 文件与兼容边界

- `YYModelSwift/YYModelCodable.swift`：协议、配置、路径、快捷 API。
- `YYModelSwift/YYModelJSONValue.swift`：有精度保护的 JSON 树、日期线格式、元数据缓存。
- `YYModelSwift/YYModelDecoder.swift`：原生容器适配与字段转换/钩子。
- `YYModelSwift/YYModelEncoder.swift`：对称映射、容器递归、钩子与导出冲突检查。
- `YYModelSwift/YYModelPolymorphic.swift`：声明式 enum 分派。
- `YYJSONDecoder.swift`：已有 API 不改变；只将内部 `_YYDecoder` 开放给同模块复用，不公开运行时内部类型。
- OC 已知负毫秒/非有限数字日期修复单独验证和提交。原版默认业务合同、ABI 修复、模型缓存保持；不承诺未知缺陷清零。
- SPM 现有两个产品无相互依赖。全部验收后为 CocoaPods 提供 ObjC/Swift 可单独选择的 subspec；默认组合保持兼容。此次开发为 unreleased，不移动 2.1.9 tag。

## 先行失败场景与验收

1. API 没有进入 SPM/Pod、普通 struct 被迫手写解码、旧接口失效。
2. 字符串/Data/已解析对象结果不同，模型数组、字典或 Optional 丢项。
3. Mapper 候选顺序/null、字面点号键、非对象中间节点、嵌套导出错误。
4. 嵌套模型配置/钩子不运行，根/子模型拒绝无效，失败导致初始化/副作用重复。
5. 黑白名单泄漏敏感字段；required 属性被零值掩盖；defaultValues 不一致。
6. Int64/UInt64/Decimal 精度损失、非法数字被吞、非有限 Float/Date 导出。
7. Swift Date 默认 encode/decode 不对称；明确秒/毫秒策略被启发式覆盖。
8. enum discriminator 未知、关联值丢失、混合数组往返不对称。
9. 导出冲突/钩子非法对象静默覆盖或返回成功；自定义容器失败提前消耗元素。
10. 共享缓存/重入串配置；Swift 6 编译失败；模型冒充自动线程安全。
11. 性能只计失败请求、混比 Data 与 object、编译并行污染；省略较慢数据。
12. OC 负毫秒 Number/String 错误，非有限 NSNumber 形成非法 NSDate；正常日期原版回归失败。

先写全部公开 API E2E，记录缺失 API/真实行为失败，再写库代码；不新增后补单元测试。保留源码/输入身份、逐项真实输出、所有采样及完整复跑命令。Swift 普通模型和配置模型分开计时；与同 DTO 的原生 JSONDecoder、既有 YYJSONDecoder 对照。任何性能结论按实测范围表述，不预设全面更快。
