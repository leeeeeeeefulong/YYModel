# 独立 OC 审查：先行失败判定

在编写独立公开 API 探针前固定以下失败场景，不修改生产源码。

1. 子类覆盖 mapper 时，父类映射被重新合并，导致原版默认字段输入/输出变化。
2. 非 secure 旧归档中的异构 NSArray/NSDictionary/NSSet 自定义 NSCoding 成员因新增 allowlist 丢失，或 decoder 进入 error 后 fallback 无法恢复。
3. secure archive 中未声明 generic 的自定义 NSSecureCoding 成员被不充分的 allowlist 丢失，应明确能力边界，不能由 NSObject 的声明自动证明安全。
4. nested strict 模式绕过子类 yy_modelSetWithDictionary: override，可能忽略业务校验；公开文档当前限定 strict 使用 protocol hooks，故单列扩展行为而非默认回归。
5. NSDate 的 Number/字符串 timestamp、扩展斜线日期改变原版接受范围或歧义。
6. 同值 SEL/long double 的 equality/hash 与原版不同。默认对象仍需自定义 -hash/-isEqual:，只比较正确委托的模型。
7. generic NSDictionary 的已实例化模型被过滤，数组/集合与字典行为不一致。若原版同样如此，则标为既有缺陷。
8. 原版 tag/master 源码与回执不同，或有限天气模型 oracle 对字段做归一化而掩盖真实容器值类型差异。

复测不依据失败结果改断言，不读取 PPLive 业务工程。产物保存在本目录。

9. 静态发现 yy_modelHash 当前对所有 getter 递增 count，却不处理 Pointer/CString/CArray 等类型；仅含这些属性的两个不同对象可能拥有相同 hash，yy_modelIsEqual 又忽略这些类型，导致不同内容被判为相等。先固定判定再扩展探针：两个 PointerOnly 模型指针分别为 0x1 和 0x2，应观察原版与 fork 的差异，不能把未处理字段当作有值的 hash 属性。
