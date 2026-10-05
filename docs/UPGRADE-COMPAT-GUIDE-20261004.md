# YYModel 升级与兼容指南

2026-10-05 核验补充。本文替换未执行的迁移草稿，按实际源码和机器回执区分修复、扩展和限制；不修改库生产实现。

## 版本与接入

- ibireme 对照：`c7df27538c043e5f54f5b6605958544bb529892f`。
- 已发布2.1.9：`00329f245752ed0e264e8c90bc14a6bd4e4e46e5`，tag保持不变。
- 新生产实现：OC契约修复`e50e794`，Swift外部规则`ad01ae0`，已随 2.2.0 发布并由 2.3.0 延续（写作时为发布前的 master 快照）。依赖应固定 2.2.0 及以上的 tag，不能仍固定2.1.9却期待新接口。
- SPM产品`YYModel`/`YYModelSwift`可独立选择；CocoaPods为`YYModel2/ObjC`、`YYModel2/Swift`。Swift纯Codable不需要链接OC产品。

## OC：迁移需要关注什么

| 场景 | 当前行为 | 使用建议 |
|---|---|---|
| 子类重写Mapper/容器泛型 | 默认只取当前类最具体有效hook，与原版覆盖契约相同 | 依赖fork父子合并的类显式返回`modelMergesSuperclassConfiguration=YES` |
| 黑/白名单 | 保留有效hook覆盖，不因合并开关改变 | 不自动合并名单 |
| Pointer/CString-only equality/hash | 没有可比较字段时按实例身份判断 | 同一实例相等，两个不同实例不相等 |
| NSObject协议识别 | category不再使全部NSObject conform YYModel | Swift NSObject hook模型显式conform或导出@objc hook；旧OC hook仍按respondsToSelector识别 |
| Swift来源判断 | 2.3.0起 isSwiftDynamic 已移除，ObjC产品无任何Swift相关API | Dynamic flag只说明runtime标记，不能证明语言来源；用 `type & YYEncodingTypePropertyDynamic` 查询 |
| secure归档 | 容器允许基础类和声明的generic成员；成员需支持NSSecureCoding | 正确声明允许成员类；不自动允许任意id/异构自定义类 |

保留的UInt64/Decimal、日期和受控安全容器能力是相对原版的增强。SEL/long double比较也保留fork扩展，**不能描述为与原版所有比较规则相同**。已实例化模型在generic NSDictionary中的过滤沿用原版既有边界。详见[OC迁移说明](OBJC-MIGRATION.md)。

## 新增归档假设的实测结论

收到的探针有重复类声明，原样编译失败；其注释称“未声明generic”，模型实际上声明了generic，且没有加入注释所称的NSNumber。因此草稿的“已验证”不能作为事实。

校正后分别构造有/无generic的模型，旧非secure归档往返`[model("one"), null, 7, model("two")]`。macOS与iOS26.5模拟器各43/43项通过，其中新增10项验证数量、null、数字、成员类型和字段值。

**本场景没有复现成员丢失，生产源码无需修复。** 这不意味着未声明允许类的secure归档也能自动成功，更不能为了验收而降低secure解码约束。[本次回执](../Validation/receipts/archive-followup-20261005.json)保留源码/探针SHA和实际结果；原33项回执仍是先前运行的快照。

## 性能复测已经完成

当前OC生产源码已经与固定ibireme版本完成配对复测，不是等待VM外执行的待办。dirty Data六轮、clean Data/dirty对象各三轮；每轮ABBA、每块7样本、每样本1000次，完整模型门禁通过。

| OC路径 | 当前/原版轮比率中位 |
|---|---:|
| dirty Data | 0.9844 |
| clean Data | 0.9811 |
| dirty已解析字典 | 1.0215 |

当前源码与计时OC文件SHA相同；该负载没有稳定的大幅退化。物理iPhone、所有模型/输入或峰值内存仍未测，不能从这一表推导普遍更快。原始样本和混合调用数据见[交付报告](DELIVERY-EXTERNAL-RULES-20261004.md)。无需因修正文档/归档探针再次跑无关性能。

## Swift：模型不增加YY协议

### 2026-10-05 修复工程（工作区，尚未发布）

以下变化属于当前未提交工作区；最终核验以 [公开 E2E 状态表](../Validation/remediation/STATUS.md) 为准。

| 场景 | 原行为或问题 | 当前行为 |
|---|---|---|
| raw 模型键经策略变为同名（F-01/F-06） | 无序字典可能选择不同源键 | 精确逻辑键优先，再按 UTF-8 字节序；Data 入口保留 Foundation 的冲突结果，hook 读取同一结果 |
| 外部规则注册（F-02） | 替换模型配置、重复注册替换之前规则 | 模型规则作为基底，后续注册叠加；同一项后写覆盖，其他项及 hook 保留 |
| Int 字典键 `01` / `1`（F-03B） | 遍历顺序决定胜者 | 规范拼写 `1` 优先，再 UTF-8；所有值仍严格解码，坏的冲突条目不会静默跳过 |
| Optional 指向无效 mapper 路径（F-05） | 可能误判 absent | 抛出路径形状错误；业务 init 与策略错误保留 |
| null、default、fallback 与容器查询（F-04/F-07/F-11b/f） | 查询与直接 decode 不一致 | 共用字段解析；typed default 返回业务值，容器读取对应 JSON 快照；Presence null 贯穿数组/字典 |
| lossy（F-08） | 无默认报告或被 fallback 抢先 | 默认返回报告，每次 decodeWithReport 隔离；逐元素 lossy 先于字段 fallback |
| raw `superDecoder()`（F-09） | 劫持业务键 `super` | 扁平继承，不读取该业务键；与 Foundation 的差异明确保留 |
| 多态 discriminator（F-10） | 对象入口可宽松转成 String | 两入口均要求严格 String，missing/null 错误包含判别键 |
| hook 可变子树（F-11d） | 修改 NSArray 可能污染调用方 | hook 输入递归隔离；原业务值不被修改 |
| NativeBridge（K-01–05） | 递归数值、Set 去重、游标或错误路径不一致 | 元素恢复后建 Set；物理祖先与结构路径映射、完整 codingPath 贯穿泛型容器 |
| 数值树（P-03/04/06、P-01 现代 hook 补充） | Float 二次舍入、UInt64 边界分类损失 | 保存原生 Float/Double 位表示、大整数分类；跨调用保存的 hook NSNumber 仍保真 |

对象导出和export hook改为直接值树，不再经JSONSerialization重解析；保留Date/Data/key策略与Foundation容器协议。相同逻辑mapper字段重复获取容器允许，不同字段映射到相同或重叠目标仍拒绝。对象普通键顺序不属于API契约。

新增 `.microsecondsSince1970` 日期策略；解码、编码及字段/字典策略配对使用。`.automatic` 仍以 `abs > 1e11` 判毫秒，不能自动判断微秒；ISO8601 默认导出仍只保证毫秒。若客户端对 `YYModelDateStrategy` 作穷尽 switch，应增加新 case。

可选互转诊断默认关闭，不打印原始值：

```swift
let report = YYModelCoercionReport()
var decoder = YYJSONDecoder(mode: .legacy)
decoder.userInfo[YYModelCoercionReport.key] = report
// decoder.decode(...) 后读取 report.records；共享该 report 时累计，clear() 可清空。
```

新增逐 decoder 的 `.numberParsingStrategy`：`.automatic` 使用缓存能力探测，现代 Foundation 沿用原路线；`.foundation` 强制 Foundation；`.integerTokens` 经 JSONSerialization 顶层解析走 raw，支持对象/数组/片段并保留 JSON5 配置。`.native` 始终委托 Foundation。旧 OS 上超 2^53 的浮点形式整数（如 `9007199254740993.0`）不保证精确，服务端应输出整数字面量或字符串；本机无旧 runtime，真实旧 OS 验收仍未完成。

未新增 R-1/R-2 双管线运行开关；恢复已验收源码/发行版本后复跑验收是回滚办法。本轮没有修改发布版本号、推送或发布。

普通`struct: Codable`即可。推荐标准数据使用`.native`；别名、KeyPath、混发类型、required、默认值、字段日期、多态等放在外部`YYJSONRules`，使用`.compatible`。YYModelCodable只是可选便利。

无参数decoder/encoder都为legacy，保留旧零值/自动日期语义；compatible默认日期委托Foundation，其默认纪元为2001年。Unix数据应明确设置秒/毫秒策略或外部字段日期，编码与解码配对相同mode/rules。增强路径不会捕获任意业务错误并重试整模型。

这份天气负载native接近原生JSONDecoder；compatible约为原生5倍，脏数据与已发布2.1.9接近，不能宣传增强模式为原生速度。[Swift规则与示例](SWIFT-EXTERNAL-RULES.md)说明能力、成本和未自动反射的边界。

## 复跑新增契约

在组件仓库根目录、已启动的模拟器上执行，使用新的输出目录：

```sh
python3 Validation/run_objc_contract.py --output /tmp/yy-archive-mac
python3 Validation/run_objc_contract.py --simulator <UUID> --output /tmp/yy-archive-ios
```

`acceptance.json`需`allPassed=true`，程序遇断言失败退出非零。性能、完整天气/数值、原版XCTest与Swift回归的复跑命令见交付报告；不依赖PPLive或其他业务App。
