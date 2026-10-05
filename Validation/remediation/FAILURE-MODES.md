# 修复工程公开 API E2E 失效场景（实现前）

- KEYMAP-1：父键重命名后，逻辑祖先被当作物理路径，读到另一合法子树。
- KEYMAP-2：Set 在恢复 token 浮点位模式前去重，两个不同元素不可逆合并。
- KEYMAP-3：Array / Optional 中用户 Decodable 看到相对 codingPath；或为补路径重复初始化。
- KEYMAP-4：Optional / Array / Int-key Dictionary 泛型递归遗漏位模式修复。
- KEYMAP-5：特殊字符串键与多层路径编码碰撞，映射串值。
- 控制：单元素 Set 保持正确；hook=false/true 不允许同错而被当作通过。

执行器编译当前 YYModelSwift 全部源码，生成动态库，另行编译仅使用公开 API 的 consumer。
逐场景断言固定期望、hook 两态相等、无 error；保存源码 SHA-256、工具链、命令、完整日志、观察值与判定。
旧冻结复现仅作为历史证据，不用于当前验收。

数值扩展：P-03 字典导出Decimal塌缩；P-04策略桥Decimal塌缩；P-06Float中点以上长token经Double二次舍入（含超过Decimal容量的长token、负数）。固定期望分别为原Decimal文本和直接Float(text)位模式。

历史消费者回归：桥接严格类型拒绝/Date/Data策略位模式、84个Double token位模式、37项外部规则、配置入口/typed default/enum/default/date/字典可表示键。历史探针迁入Validation后直接编译当前源码，回执保留所有原观察值；以历史已通过行为作为回归期望，不把进程退出0当成功。

第二轮组合扩展（修复前）：
- 逻辑前缀与相对子键同名时，错误路径误判为已重定位，value.value变为value。
- no-argument superDecoder读取super子树，但物理游标仍指向当前父节点，长Double低位丢失。
- no-argument superDecoder 的数值修复不得遗漏 `value.super` 的错误路径前缀。
- 嵌套 custom Date/Data 策略已经生成完整路径，外层不能重复加前缀；普通字典形状错误须保留完整路径。
- 用户模型自行消费 null 并抛出业务错误时，不得被 try? 吞成通用 valueNotFound。
- Int 字典规范键仲裁作用于已成功解码的值；保持既有严格容器契约，任一输入项无效仍拒绝。不得保存 Foundation 的临时 Decoder 再延后读取（它可在遍历中复用）。
- raw hook入参含NSMutableArray子树时，hook可能反向修改调用方输入。
- 键策略/用户init回调应hook前后次数一致且模型只构造一次。
- Int字典canonical键冲突应在Data/raw/hook与逆输入顺序下保持确定。
- Date字典字段覆盖策略逐次/并发调用不可串扰。
- 嵌套编码器映射冲突必须被顶层捕获；作为F-11c真实性控制，若已拒绝不得宣称修复前失败。
# 数值边界补充（生产改动前登记）

- Data/raw 的 Int64/UInt64 在 2^53±1 与 signed/unsigned 边界可能被 Double 中转损坏；hook 两态均须字面值相等。
- 大整数的浮点拼写可能与整数拼写走不同路径；现代 Foundation 必须精确，旧系统须另行真实运行验证。
- Float 正负正常值/次正规值/最大有限值及 Double 最小次正规值，hook 可能二次舍入或下溢；Data 入口与直接字面量解析位值比较。
- 数值诊断和旧 OS 探测仍须验证每次调用隔离；不能将现代 Foundation 的结果冒充旧 OS 运行验收。

字段解析收敛补充（下一轮实现前）：Optional mapped 字段不可因 contains 不可抛错而将无效中间形状当成 nil；typed default 的 nestedContainer 必须读取已注册 JSON 快照；keyed null 自定义模型应能消费 null；重复注册不得重新引用原始可变 default；decodeWithReport 必须创建独立报告，不复用 userInfo 中的累计报告。

R-2 整数附近的 Float 中点：超过 Decimal 容量的小数尾巴可被 Decimal 分类吞掉，token 被误归为“精确 Double / 整数”后失去原始 Float 位值；例如 16777217 + 极小正尾巴应向上舍入，不能将 Float(Double(token)) 当期望。

R-2 编码边界：export hook 或多态输出中的已转换物理键不可再次调用 keyEncodingStrategy；同一模型及 Date/Data callbacks 每次编码各执行一次。hook移动现有数字节点仍保留字面量位值，hook新建NSNumber按其新值消费。原先模型/Date重复执行不能凭源码往返推断，必须用公开callback计数控制。

R-3 路由缺口：仅 hook snapshot 使用能力探测不足以修复无 hook 的 Data 整数快路径；须 Data 顶层同源路由。显式每实例整数 token 路由对照必须支持 fragments / JSON5 / brace-less（系统提供选项时），native 模式仍完全遵循 Foundation。该对照证明路由逻辑，不代替旧 OS runtime。

# P-05 与 P-08 扩展失效模式（实现前登记）

- P-05 微秒日期策略（microsecondsSince1970）：
  - 显式 microsecondsSince1970 在标量解码、字典键值解码、字典 fieldDates 覆盖、对象编码往返中若未完整适配，将导致时间戳按秒或毫秒误读产生几十年偏差。
  - 负微秒日期（1970 年以前时间戳，如 -1_000_000 µs）在除以/乘以 1,000,000 时若符号处理不当或整除截断将导致正负反转或负零丢失。
  - 严禁通过篡改既有 automatic 日期启发式逻辑来迁就微秒样本。
- P-08 可选类型强制转换（Coercion）诊断机制：
  - 默认关闭机制未生效时会在正常解析热路径中造成额外分配与性能退化。
  - 1 -> Bool、浮点向零截断为整数（如 3.7 -> 3）、数字字符串转整数（如 "42" -> 42）等宽松恢复未被精准捕捉并记录规范字段（logical codingPath / sourceCategory / targetType / reason）。
  - 正常整数读取与原生快速路径可能误报 coercion。
  - Report 若直接持久化用户原值或直接控制台 print，将破坏用户数据隔离与日志干净度。
  - 多次 decode 或并发环境下若共享隐式报告槽位，将引起跨调用/跨线程状态污染。

## R-2 TreeEncoder Foundation parity (before follow-up fixes)

The new strategy substrate can bypass root Date/Data strategy when calling value.encode
instead of a generic scalar container; dictionary values can do the same. Unsupported
object-key dictionaries must retain Foundation's alternating key/value array encoding,
not become invalid JSON. Native ISO8601 must retain Foundation's non-fractional format.
Float transport through Decimal(Double(Float)) can change its short JSON spelling or
negative-zero sign. An Encodable that writes nothing must be rejected at the root like Foundation; an explicitly requested empty keyed container may produce {}. Initial empty-object assumption was disproven by the Foundation control.
These are public parity E2E scenarios; record both expected Foundation output and current
results before repairs. Internal number metadata must not become a new public API or a
second scalar math representation.

## Tree substrate completion boundary controls (before main takeover fixes)

- Array callback keys must match Foundation stringValue "Index 0" and intValue 0.
- Nested Encodable that writes nothing encodes {}, whereas no-write root is rejected.
- Explicit empty keyed root must encode {} and custom Date/Data callbacks that write
  nothing follow Foundation's empty-object fallback.
- Initial hypothesis: Date seconds with infinity might obey Foundation's non-conforming Float strategy. The independent Foundation control disproved this: Date infinity is rejected even with convertToString; retain rejection (TreeFoundationParityE2E).
These controls extend TreeFoundationParityE2E before main repairs the partial substrate.

## Independent review: logical hook parent address and integer-route signed zero

- Renamed/snake parents, array Index 0 and dictionary values with transformed
  duplicate child keys must give didTransform exactly the Foundation-selected model
  subtree; a null losing child must not break an otherwise valid Foundation decode.
  YYKeyMapState is addressed by logical Foundation codingPath, not the raw physical path.
- .integerTokens JSON '-0' Double must preserve negative-zero bitPattern, also nested
  and in arrays. JSONSerialization's integer NSNumber drops the sign. The repair must
  preserve its exact large integer tokens, not replace them with legacy Decimal/Double.

## Independent TreeEncoder protocol review (before protocol completion repairs)

Repeated keyed/unkeyed requests for the same nested key must share its prior child;
no-arg superEncoder must transform the super key. Snake conversion must match actual
Foundation CharacterSet Lu/Lt boundaries, including initial URL and Unicode cases.
CodingKeyRepresentable dictionary callbacks retain the original codingKey intValue.
Mapper reservations must track logical owner: reuse of payload->envelope is valid,
whereas first/second->envelope remains rejected. Agent probes with Foundation controls
are migrated unchanged into TreeProtocolE2E and RepeatedEncodingE2E before repairs.
