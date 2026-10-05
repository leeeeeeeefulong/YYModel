# OC 默认契约修复与迁移

本文件说明当前源码的 OC 修复；**不属于已发布的 2.1.9 tag**。原版对照固定为 ibireme `c7df27538c043e5f54f5b6605958544bb529892f`，2.1.9 固定为 `00329f245752ed0e264e8c90bc14a6bd4e4e46e5`。当前修复保留现有数值、日期和受控安全归档能力，并恢复原版的配置覆盖默认值；不承诺所有历史异常输入逐字节等同原版。

## Mapper 和容器泛型的默认值

现在默认只调用当前模型类的最具体有效 `modelCustomPropertyMapper` / `modelContainerPropertyGenericClass` hook，与原版一致。没有重写时仍正常继承父类方法；子类重写时使用子类返回的完整配置，不自动补回父配置。

例如，父类返回 `name→legacy`，子类只返回 `tail→other`：

| 输入同时含 name / legacy / other | 原版与本次默认 | 2.1.9 默认 |
|---|---|---|
| name="normal", legacy="ancestor", other="tail" | name="normal"，导出 name / other | name="ancestor"，导出 legacy / other |

同理，子类泛型 hook 没有声明的数组字段不再自动套用父泛型并筛掉 null/number。这个默认修复会影响依赖 fork 父子自动合并的模型，升级前需选择下面一种迁移方式。

### 保留 fork 的父子合并

在需要合并的模型类上显式实现新 hook：

```objc
@interface Book : ParentBook <YYModel>
@end

@implementation Book
+ (BOOL)modelMergesSuperclassConfiguration {
    return YES;
}
+ (NSDictionary *)modelCustomPropertyMapper {
    return @{ @"title": @"book_title" };
}
@end
```

YES 只对 Mapper 和容器泛型执行父→子合并，子类同名项优先。这个类策略可继承；需要恢复原版覆盖的子类返回 NO 即可。它只影响实现/继承该 hook 的模型类元数据，不自动传播到任意嵌套模型类。

另一种方式是在子类 hook 中显式合并 `[super modelCustomPropertyMapper]` 或 `[super modelContainerPropertyGenericClass]`。这适合只合并其中一种配置，或需要控制父条目删除的模型。默认 hook 返回 nil/空字典时不会自动恢复父配置；启用自动合并后，nil/空字典表示没有新增项，并不能删除祖先已有项。

`modelPropertyBlacklist` / `modelPropertyWhitelist` **始终使用当前类的有效 hook，不自动合并**。新增开关不改变名单语义。名单也不会因为父 Mapper 合并而变成父子交集或并集。

## Hash 与 equality 的身份回退

2.1.9 的 hash 对所有 getter 属性计数，但 Pointer/CString 等字段并不参与 hash/equality 的值比较。这使仅含这些字段的不同对象拥有同一 hash，并错误地判为相等。

本次修复让 hash 和 equality 共享参与比较的类型规则。仅有未参与比较字段的模型按对象身份处理：不同实例不相等，同一实例相等；即使调用方把 hash 重写为常数，也保留身份判断。包含普通可比较字段时，原先忽略 Pointer/CString 的行为保持，不新增指针内容比较。

继续按原版方式委托模型方法：

```objc
- (NSUInteger)hash { return [self yy_modelHash]; }
- (BOOL)isEqual:(id)object { return [self yy_modelIsEqual:object]; }
```

SEL、long double 等在 fork 中已参与的比较规则保留。这里修复已确认的身份回退问题，不宣传成所有 hash 数值与原版完全相同。

## YYModel 协议不再自动附着于所有 NSObject

`NSObject (YYModel)` 仍提供原有解析、导出、copy/coding/hash/equality 入口，但不再替所有 NSObject 声明 YYModel 协议 conformance。

模型 hook 仍通过 `respondsToSelector:` 识别，不要求旧 OC 模型为了继续解析而新增 `<YYModel>`。只有需要协议类型/运行时协议识别的模型才显式声明 `<YYModel>`；不要用 `conformsToProtocol:YYModel` 代替判断某个 NSObject 是否有可解析属性。

## isSwiftDynamic 的移除

2.3.0 起公开 getter `YYClassPropertyInfo.isSwiftDynamic` 已从 Objective-C 产品中完全移除：ObjC 产品不再包含任何 Swift 相关 API，也没有废弃声明残留。此前（2.2.0）该 getter 已被标记 deprecated 且保守返回 NO，因此移除不改变任何可观察的解析行为。

Objective-C 的 Dynamic 属性标记或形似 Swift 的 ivar 名称不能可靠证明属性来自 Swift。需要判断 Objective-C runtime 的动态属性标记时，使用：

```objc
BOOL dynamic = (propertyInfo.type & YYEncodingTypePropertyDynamic) != 0;
```

这只表示 runtime Dynamic 标记，不是 Swift 来源检测。框架不会通过猜测 ivar 前缀提供"自动 Swift 检测"。

## 保留的能力与限制

- **从 OC 迁移到 Swift 版不是 drop-in**：Swift 版对 Foundation `JSONDecoder` 的相对差异
  （数字字符串、Bool、Data/Base64、自动日期与 `1e11` 毫秒边界、缺失/null 语义、
  D1 超合理量级时间戳记录）逐项列在
  [Swift 与 Foundation 行为差异表](SWIFT-EXTERNAL-RULES.md#与-foundation-jsoncoder-行为的差异非-drop-in)。
  OC 宽松数字字符串转换仍不是 Swift 严格数值 lexer 的同一契约。
- UInt64 / NSDecimalNumber 已修正边界保留；OC 宽松数字字符串转换仍不是 Swift 严格数值 lexer 的同一契约。
- 当前 master 的负数毫秒、零字符串、非有限日期修复保留；已发布 2.1.9 没有这些后续日期修复。自动秒/毫秒和月/日识别仍有歧义，业务应明确数据单位与格式。
- NSSecureCoding 容器 allowlist 和 generic 类型支持保留。模型及成员需要支持 NSSecureCoding，并提供正确允许类；任意 id/异构自定义容器不能视为自动安全归档。
- `modelRequiresSuccessfulNestedTransforms` 继续默认 NO，启用后校验协议转换 hook，不提供事务回滚。需要父子泛型合并的严格模型，也应显式启用 `modelMergesSuperclassConfiguration` 或主动合并 super 配置。
- generic NSDictionary 的已实例化模型过滤行为仍沿用既有实现；本次不扩大这项默认转换行为。
- 最低平台声明保持 iOS11 / macOS10.13；它是当前分发支持政策，不能以核心未使用的完整归档便利 API 论证不可降低。

Runtime `l/L` 编码在 Apple 64位平台仍表示32位值，`@encode(long)` 使用 `q`；尺寸查询保留，但不再称原版 Int32 处理必然错误。原版 msgSend 已有类型化非可变参数 cast；本次 typedef 整理不单独证明 PAC 修复或性能加速。

## 集中验收与回执

公开 API E2E 使用真实模型与 Foundation 归档，保存逐项 actual/expected/passed JSON，断言失败返回非零；不新增单元测试，也不依赖业务 App。

生产源码完成后已集中执行契约与性能验收，不能从代码编译成功推导行为已通过。

## 隐私清单修正

旧 PrivacyInfo.xcprivacy 使用 ObjCRuntime 类别，属于错误声明。Apple [TN3183](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest) 列出的 required-reason 类别为键盘、磁盘空间、文件时间戳、系统启动时间、UserDefaults，没有 Objective-C runtime 类别。生产 OC/Swift 源码没有此次核查的这些 covered API 调用，现有清单保留组件无收集/跟踪声明并清空虚构的 accessed API 项；新增相关调用时必须重新核查。已通过 plist 语法检查；这不是 App Store 审核结果，也不能替代 App 自身的完整隐私声明。
