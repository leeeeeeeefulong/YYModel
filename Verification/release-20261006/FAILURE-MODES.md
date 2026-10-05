# 发布核验先验失效模式 — 2026-10-06

基线为824faad（当前2.3.2代码），原Validation与历史数据已按用户要求删除。本轮使用新网络快照与新公开API端到端消费者，不恢复整个旧测试目录。
评估范围：实际运行核验的现代系统；未验证旧系统不推定通过。仅评估，不发布、不改版本号。

- 天气核心流程：真实多城市API响应→完整DTO→规则/业务字段→JSON导出→再解码。逐字段与原始JSON比较，包含所有数组元素、null、数字、单位和城市顺序。
- 合成边界：根据新快照明确生成缺失、null、数字字符串、坏数字、数组坏元素、空载荷等样本。与在线原始响应分开标记；不能把合成样本称为API实测。
- 手写编码异常恢复：子编码写入草稿后throw，调用方catch后继续，可能保留草稿、覆盖已成功字段或污染下一标量，产生成功但错误的输出。
- superEncoder生命周期：延迟引用写入与同一key的直接编码发生交叉时，树与Foundation可能选错最终值。
- 多态根规则：不支持的typedDefaults/fallback/lossy/missing政策可能被接受后忽略，根策略必须在构造时明确拒绝，payload策略正向控制应继续可用。
- 重复typed default：新默认值无法序列化时可能留下旧JSON快照，使直接decode与superDecoder读出不同业务值。
- 平台/交付：真实SPM消费端、混合ObjC/Swift及可用iOS模拟器核验；历史计数不作为当前通过结果，编译不代替实际运行。
- 新天气混合消费：独立SPM应用同时导入两个公开产品，ObjC反射读取完整current子对象并导出，Swift再消费；反向Swift导出再由ObjC读取。所有配置的字段逐一与新API原值比较，不把简化DTO称为完整响应验证。
- 性能仅记录：没有证明业务无法使用的微基准差距不阻塞；崩溃/资源耗尽/超时导致核心流程无法完成才列阻塞。

生产修改前先运行当前源码失败基线；按现象、复现、影响、严重度、方案、处理状态与证据记录；保留失败期望，不通过修改断言隐藏缺陷。

- iOS18.2已实测：SingleValueEncodingContainer在子模型throw后继续String编码崩溃；YY单值泛型直接调用业务encode绕过Foundation child transaction。具体scalar转发单独不足以修复，泛型入口也必须经base container的YYModelEncodingBox保留回滚。修复前两个crashlog分别记录generic和String Foundation witness。
