# OC 默认契约修复：实现前失败场景

本轮只使用组件公开 API E2E；不读写业务工程、不新增单元测试。先固定以下期望，再改生产源码。按照用户要求，全部实现完成后再集中执行验收与性能；本代理阶段只编译检查。

1. Pointer/CString-only 模型：两个不同实例，即使指针值相同或覆盖 hash 为常数，也不能因为未比较字段被判相等；同一个实例仍相等。NSSet 应保留两个不同实例。
2. 混合属性：指针继续按原有规则忽略，普通可比较字段仍决定 hash/equality；不擅自扩大参与比较类型。
3. 子类重写 Mapper：默认只使用最具体有效 hook；父独有映射不自动恢复，读取与 JSON 导出都回到原版键。
4. 子类重写泛型：默认保留未声明泛型的原始数组项，包括 dictionary/null/number；不能自动父合并并过滤。
5. 新 hook `+modelMergesSuperclassConfiguration`：缺省 NO；明确 YES 才合并 Mapper/泛型；子类同名项覆盖；继承 YES 可由子类 NO 关闭。
6. 黑/白名单：无论合并开关如何，仍只使用当前类有效 hook；不自动父子合并。
7. NSObject：导入 YYModel 后不能自动 conform YYModel；显式 conform 的模型仍可识别；未显式 conform 的模型 hook 继续通过 respondsToSelector 工作。
8. 纯 Objective-C @dynamic 与形似 Swift 的 ivar 命名不能证明 Swift 来源；2.3.0 起旧 isSwiftDynamic getter 已完全移除（ObjC 产品无任何 Swift 相关 API）；Dynamic 编码标记仍保持。
9. 现有增强不能丢：UInt64 高精度、负毫秒/零/非有限日期边界、正确 generic 的 NSSecureCoding 容器往返。
10. 已知限制不被扩大承诺：未声明允许类的 secure 自定义容器、泛型 NSDictionary 的已实例化成员、自动日期单位歧义另行记录，不通过更改断言掩盖。

产物：`ObjCContractE2E.m` 输出逐项 passed/actual/expected JSON，并以失败断言返回非零。`run_objc_contract.py` 保存源码 SHA、编译命令、环境和验收回执。两者均先编写，本阶段不执行程序。

## 2026-10-05 新增归档探针的验收标准

- 不重复声明测试类，先确认可真实编译运行。
- 旧非 secure 归档的异构数组保留成员数量、NSNull、NSNumber 和自定义成员值。
- 分别检查声明 generic 与未声明 generic，不能把声明了 generic 的模型标成未声明。
- 非 secure 往返成功不等于任意异构成员可自动 secure 解码，不扩大允许类。
- 源码未修改时不重跑无关性能；保留原33项历史回执，新增结果单独记录。
