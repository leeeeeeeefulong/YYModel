# YYModel 升级与兼容指南

2026-10-05 核验补充。本文替换未执行的迁移草稿，按实际源码和机器回执区分修复、扩展和限制；不修改库生产实现。

## 版本与接入

- ibireme 对照：`c7df27538c043e5f54f5b6605958544bb529892f`。
- 已发布2.1.9：`00329f245752ed0e264e8c90bc14a6bd4e4e46e5`，tag保持不变。
- 新生产实现：OC契约修复`e50e794`，Swift外部规则`ad01ae0`，属于Unreleased。依赖应固定交付提交，不能仍固定2.1.9却期待新接口。
- SPM产品`YYModel`/`YYModelSwift`可独立选择；CocoaPods为`YYModel2/ObjC`、`YYModel2/Swift`。Swift纯Codable不需要链接OC产品。

## OC：迁移需要关注什么

| 场景 | 当前行为 | 使用建议 |
|---|---|---|
| 子类重写Mapper/容器泛型 | 默认只取当前类最具体有效hook，与原版覆盖契约相同 | 依赖fork父子合并的类显式返回`modelMergesSuperclassConfiguration=YES` |
| 黑/白名单 | 保留有效hook覆盖，不因合并开关改变 | 不自动合并名单 |
| Pointer/CString-only equality/hash | 没有可比较字段时按实例身份判断 | 同一实例相等，两个不同实例不相等 |
| NSObject协议识别 | category不再使全部NSObject conform YYModel | Swift NSObject hook模型显式conform或导出@objc hook；旧OC hook仍按respondsToSelector识别 |
| Swift来源判断 | isSwiftDynamic弃用且保守NO | Dynamic flag只说明runtime标记，不能证明语言来源 |
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
