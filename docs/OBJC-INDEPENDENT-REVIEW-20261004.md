# YYModel Objective-C 独立审查（2026-10-04）

结论：这版 OC 已经包含行为扩展和内部重写，不能概括成“只是把原版废弃 API 换成现代 API”。大部分通常用法得到保留，但“100% 原版契约一致”不成立。本轮复现了 2.1.9 与 master 均有的一项 equality 回归，以及 Mapper/泛型默认继承策略的实际数据变化。此前模拟器 dirty Data 慢 18.35% 的单组观察，未在六轮独占 ABBA 中稳定复现。本轮只读组件生产源码，没有修改、提交、推送，也未读取或修改 PPLive 正式业务工程。

## 1. 已确认的版本身份

- 组件仓库：`/Users/lee/Desktop/本地项目调试计划/projects/YYModel`。
- 原版固定基线：`c7df27538c043e5f54f5b6605958544bb529892f`。
- 已发布 tag 2.1.9：`00329f245752ed0e264e8c90bc14a6bd4e4e46e5`。
- 当前 master：`f42d50a7e4f5bb622acb08efa3ac055b6bcd17e4`。
- 归档 `/tmp/YYModel-delivery-2.1.9-20261004/original/YYModel` 的五个 .h/.m 文件逐字节与 `git show c7df275:<path>` 相同；不是凭目录名认定原版。
- `git diff 2.1.9 HEAD -- YYModel` 的生产 OC 差异只有日期分支，来自 `a83cb351b800dbc58d0e81ce8fd3968d52039516`；`f42d50a` 的主要新增是独立 Swift 模型产品，不是新增 OC 修复。不能把 master 的日期修复归入已发布 2.1.9。
- 入口/出口时组件工作树均干净。机器回执：[identities.json](/Users/lee/Desktop/本地项目调试计划/projects/YYModel/Validation/research/20261004/objc-identities.json)。

## 2. 可复现的 OC 回归与契约差异

### 2.1 必须修复：仅含未参与比较属性的模型被判为相等

两个 `PointerOnly` 对象均按原版示例委托 `-hash`→`yy_modelHash`、`-isEqual:`→`yy_modelIsEqual:`，唯一属性为 `void *value`，分别赋 `0x1`、`0x2`。

| 版本 | 对象是否不同 | hash 是否相同 | isEqual |
|---|---:|---:|---:|
| 原版 c7df275 | 是 | 否 | NO |
| 已发布 2.1.9 | 是 | 是 | YES |
| master f42d50a | 是 | 是 | YES |

根因：[NSObject+YYModel.m:1919](/Users/lee/Desktop/本地项目调试计划/projects/YYModel/YYModel/NSObject+YYModel.m:1919) 对所有有 getter 的属性都 XOR 属性名并递增 count，但 Pointer 等类型落入 default，没有将属性值加入 hash；[同文件:1961](/Users/lee/Desktop/本地项目调试计划/projects/YYModel/YYModel/NSObject+YYModel.m:1961) 的 equality 又忽略这些类型。原版仅计入 KVC 可比较属性，count 为零时按对象身份散列；fork 的 count 使这个回退失效。

必要修复方向：让 hash/count 和 equality 使用同一份“参与比较的类型”规则；没有任何可比较属性时保留对象身份语义。不要把所有 Pointer 默默计作有值字段，也不要为了让现有回执通过而删掉这个探针。探针键 `differentPointers`，属于新增行为回归；普通 JSON 天气模型不会覆盖此类型。

### 2.2 默认 Mapper 合并改变原版子类覆盖契约

父类 `name→legacy`；子类只返回 `tail→other`。同一字典同时含 `name="normal"`、`legacy="ancestor"`、`other="tail"`。

| 版本 | 最终 name | 导出键 |
|---|---|---|
| 原版 | normal | name / other |
| 2.1.9 与 master | ancestor | legacy / other |

原版只调用最具体类的有效 Mapper hook；子类重写后，没有列出的 name 使用默认同名映射。fork [NSObject+YYModel.m:632](/Users/lee/Desktop/本地项目调试计划/projects/YYModel/YYModel/NSObject+YYModel.m:632) 在父→子循环中合并祖先独有条目。

历史材料曾把“父配置丢失”作为 fork 问题并要求合并，但原版自身就是子类覆盖。合并可以是一项有用的明确扩展；它不等于原版默认契约。若当前目标是可直接替换原版，推荐保留原版默认，并将父配置合并做成明确可选策略；子类也可主动调用/合并 super 的配置。已经依赖合并的 fork 使用者需要迁移说明，不能再次默默改变他们的行为。

### 2.3 泛型合并可造成默认数据过滤变化

父类声明 `members→ArchiveMember`；子类泛型 hook 只声明另一个属性，未声明 members。同一输入 `members=[{"name":"one"},null,42]`：

- 原版：members 保留三项，第一项是 NSDictionary。
- 2.1.9 与 master：父泛型自动合并，members 变为一个 ArchiveMember；null、42 被按泛型筛选规则丢弃。

根因 [NSObject+YYModel.m:615](/Users/lee/Desktop/本地项目调试计划/projects/YYModel/YYModel/NSObject+YYModel.m:615)。这是比“输出看起来差不多”更实质的默认差异。解决策略应与 Mapper 一致，不能只给字段 Mapper 增加兼容开关而留下容器默认变化。

### 2.4 黑/白名单保留原版覆盖行为

实测父 blacklist=[name]、子 blacklist=[tail] 时，三版都只过滤 tail，name 保留；父 whitelist=[name]、子 whitelist=[tail] 时，三版都只保留 tail。源码 [NSObject+YYModel.m:596](/Users/lee/Desktop/本地项目调试计划/projects/YYModel/YYModel/NSObject+YYModel.m:596) 只调用当前类有效 hook，没有自动父子合并。

因此不能泛称“所有配置均按父子合并”，也不应为了配置规则统一而自动合并黑/白名单。新增验收需要同时覆盖 Mapper/泛型合并，以及名单不合并。

### 2.5 equality 的其他可观察变化

加入双方相同的 NSString anchor 后，两个模型仅 SEL 值不同，或仅 long double 值不同：原版 isEqual=YES，2.1.9/master=NO。原版忽略这两类非 KVC 兼容属性；fork 用类型化 getter 参与比较。这可以是有意义的正确性增强，但仍属于语义变化，需要明确记录，不能称为单纯 typedef 更新。

原版已经使用 `isMemberOfClass:self.class`，父/子对象双向都不相等。本轮探针三版结果相同；CHANGELOG 的“恢复 equality 对称性”是相对中间 fork 错误，不是相对固定 ibireme 原版的新修复。

## 3. Secure coding：有实际增强，也存在允许类边界

公开 API 探针模型均显式实现 NSSecureCoding 与 supportsSecureCoding，并委托 YYModel 编解码：

| 场景 | 原版 | 2.1.9 / master |
|---|---|---|
| 普通非 secure 旧归档，array/dictionary/set 含自定义 NSCoding 对象 | 三种容器和对象字段均完整恢复 | 同样完整恢复 |
| secure 容器含自定义成员，但未声明 generic | 解码失败 | 同样失败 |
| secure 容器含自定义成员，声明正确 generic | 解码失败 | array/dictionary/set 都成功 |
| secure 自定义对象存入声明为 NSObject 的字段 | 解码失败 | 本次对象成功 |
| secure 自定义对象存入 id 字段，没有允许类配置 | 解码失败 | 同样失败 |

fork [NSObject+YYModel.m:1837](/Users/lee/Desktop/本地项目调试计划/projects/YYModel/YYModel/NSObject+YYModel.m:1837) 添加集合基础类和 `_genericCls` allowlist，提供了真实能力。未声明允许成员类的失败与原版一致，不能混同为“旧普通 NSCoding 归档被破坏”。这也不证明任意异构容器自动可安全归档，README 的“Full support”应限定允许类与模型协议配合。

[NSObject+YYModel.m:1851](/Users/lee/Desktop/本地项目调试计划/projects/YYModel/YYModel/NSObject+YYModel.m:1851) 的 id 属性仍使用 decodeObjectForKey，缺乏具体允许类。是否新增允许类 hook 取决于真实使用需求；不建议仅为扩大宣传自动允许任意类。

## 4. API 现代化、修复与扩展的边界

| 改动 | 判断 | 原版契约影响 |
|---|---|---|
| 明确 typedef 的 objc_msgSend 调用 | 代码组织/类型维护改进；原版已经显式非可变参数函数指针 cast | 通常签名一致；没有独立证据证明原版有 PAC 问题或必然加速 |
| dispatch_semaphore→os_unfair_lock | 同步原语替换，非“原版不支持缓存” | 通常模型行为保留；有最低平台要求，性能须测量 |
| ISO 输出 formatter 加锁 | 同步实现变化 | 线格式保留；日期解析 blocks 并非都由这把锁包住 |
| nullable 与轻量泛型注解 | 互操作声明完善 | ObjC 入口保留；Swift 导入类型可变，需要单独验证 |
| NSSecureCoding allowlist | 实际能力扩展，不只是方法重命名 | 普通归档本次保留，secure 需要允许类 |
| UInt64 字符串/NSDecimalNumber 边界处理 | 数值正确性增强 | 合法大数得到修正，溢出等边界规则有变化；不能说严格复刻所有原版异常值 |
| NSDate Number/10或13位数字字符串/RFC/asctime/斜线等 fallback | 默认接受范围扩展 | 原版 Number 时间戳与这些 fallback 不属于固定原版契约；歧义日期仍有风险 |
| `modelRequiresSuccessfulNestedTransforms` | 明确可选扩展，默认 NO | 默认嵌套 hook 失败忽略策略保留；启用后使用协议 hook，非任意 public setter override；无事务回滚 |
| Mapper/泛型父配置合并 | 默认语义扩展 | 已复现默认读取/导出/过滤变化，应可选化 |
| NSObject category 声明 `<YYModel>` | 新的协议可见性行为 | 原版 NSObject 不 conform，fork conform；探针确认所有 NSObject 的协议识别结果变化 |
| isSwiftDynamic | 新元数据 API，但当前识别不可靠 | 纯 ObjC @dynamic 也被标为 YES；本次确认不参与核心解析，主要是 API/宣传问题 |
| SEL/long double hash/equality | 比较语义增强与重写 | 新增参与比较范围，并引出仅有未处理类型的 equality 回归 |

### 必须纠正的事实性宣传

1. [YYClassInfo.m:58](/Users/lee/Desktop/本地项目调试计划/projects/YYModel/YYModel/YYClassInfo.m:58) 与 README F3 称 `l/L` arm64 是 8 字节、原版 Int32 错误。本机 arm64 公开 Foundation 调用 `NSGetSizeAndAlignment("l")=4`，`@encode(long)="q"`；三版 `YYEncodingGetType("l")` 都返回 Int32。因此这里没有证明修复原版 64 位 long 缺陷。新的尺寸查询可保留，但注释和宣传必须跟实际编码区分。
2. README/CHANGELOG 称 `archivedDataWithRootObject:requiringSecureCoding:error:` 与 `unarchivedObjectOfClass:fromData:error:` 用在 Core、由此“必须”最低 iOS11。实际生产 YYModel 五个 .h/.m 没有调用这两项便利 API；核心只调用 coder 的 decodeObjectOfClass(es)。最低平台可以是维护政策，但不能用并不存在的 Core 调用论证。
3. [YYClassInfo.m:247](/Users/lee/Desktop/本地项目调试计划/projects/YYModel/YYModel/YYClassInfo.m:247) 仅因 Dynamic 标志就置 isSwiftDynamic=YES。纯 ObjC @dynamic 反例已复现；不能把它写成可靠 Swift 检测。
4. 原版缓存、显式 msgSend cast、日期格式 blocks、isMemberOfClass 对称比较都已经存在。应区分“相对原版新增”与“修复 fork 重写引入的退化”。[NSObject+YYModel.m:15](/Users/lee/Desktop/本地项目调试计划/projects/YYModel/YYModel/NSObject+YYModel.m:15) 的 `100% Behavioral & contract fidelity` 仍与上面的公开探针冲突。

## 5. 已发布日期问题与 master 修复不能混用

`a83cb351b800dbc58d0e81ce8fd3968d52039516` 在保留原版格式长度分派后，新增有符号/空白的 10/13 位 timestamp 字符串；接受零字符串；Number 分支以 fabs(ts)>1e11 识别负毫秒并拒绝 NaN/Infinity。

这是修复 fork 默认日期扩展的边界，仍不是原版 NSDate 新契约。2.1.9 对负数毫秒、零字符串、非有限日期的已知问题仍然存在；master 才修复。已有 `Validation/RESULTS-objc-date.md` 与 `receipts/objc-date-20261004.json` 明确区分了版本。本轮独立探针确认 2.1.9 的 `"0000000000"→nil`、master→epoch0，并保留原版 ISO 对照。

日期自动单位识别仍是启发式；扩展斜线日期 `01/02/2023` 在 fork 优先按 MM/dd/yyyy 得到 1月2日，原版拒绝，不能视为自动理解日/月业务语义。未验证所有日期范围、时区变化与并发场景。

## 6. 测试覆盖核查

已确认：

- 原版 `YYModelTests` 相对固定 c7df275 没有改断言；旧用例覆盖基本转换、日期格式、Mapper/keyPath、基础容器、名单、嵌套、多态、copy/coding/hash、class info、description。既有 `official.log` 报告 27/27；本轮未重新运行 XCTest，不把历史日志声称为本轮新鲜通过。
- 现有新增 E2E 的方向合理：天气完整业务字段/往返、Data/object/export 分开、跨语言同模型/链接身份、整数边界、strict nested 的失败传播、日期正负/非有限输入。
- [run_delivery.py:77](/Users/lee/Desktop/本地项目调试计划/projects/YYModel/Validation/run_delivery.py:77) 的正确性门禁在计时前运行；复测还逐块检验完整模型/往返和 consumed 值，避免失败解码更快的错误结论。
- [run.py:55](/Users/lee/Desktop/本地项目调试计划/projects/YYModel/Validation/run.py:55) 的天气 oracle 显式规范化 OC 原始 NSArray 数值，适合比较这些固定业务字段，不是任意 Foundation 元素实际类型完全相同的证明。
- [DateContractE2E.m:34](/Users/lee/Desktop/本地项目调试计划/projects/YYModel/Validation/DateContractE2E.m:34) 只以回执写入成功返回0；要使用 `run_swift_model.py --only date` 或检查 JSON passed。直接二进制 exit0 不能单独证明日期断言通过。外层脚本确实读取 passed 并失败退出。

本轮暴露的缺口：父/子 Mapper 与泛型覆盖、黑/白名单不合并、仅 Pointer 等未比较类型的 hash/equality、纯 ObjC dynamic 的 Swift 标志反例、secure typed/untyped/id 三种能力边界，均需要独立 E2E。

既有问题而非新增回归：generic NSDictionary 输入已经实例化的模型时，三版均过滤该项，得到 count0；同一个模型放数组/集合均得到 count1。当前“实例化值被信任”说明应限定具体路径，或安排明确的兼容性修复，不能把它归为 fork 新增回归。

通过 27/62/183/1792 等有限用例不等于无缺陷；1792 数值验收主要属于 Swift，并不能自动覆盖所有 OC 数值/元数据类型。

## 7. 六轮独占 ABBA 性能复核

已确认的测量条件：iOS Simulator（非物理 iPhone）、Apple M1 Max、已有 Xcode26.6 / iOS26.5 SDK 的 standalone `clang -O2` 程序；不是本轮执行 Xcode Release configuration 的 XCTest。它使用与既有 Release 优化口径一致的已编译程序。逐一核对 current/source/harness/original/fixture SHA，二进制 SHA 写入回执；复用同一 Weather OC 模型和同一输入，禁止与编译并行。

正式测量 UTC 12:32:03–12:33:40（上海20:32:03–20:33:40）。预热5次，每块7个样本，每样本1000次，顺序 Original/Current/Current/Original。dirty Data 六轮，两个控制各三轮；所有 result/roundTrip/consumed 门禁通过。曾在父代理编译未结束前启动的试跑被中断作废，未纳入正式结果。

| 路径 | ABBA轮数 | 每轮 current/original 比率中位 | 最小–最大轮比率 | 合并样本原版 ms/次 | 当前 ms/次 | 合并中位比 |
|---|---:|---:|---:|---:|---:|---:|
| dirty Data | 6 | 1.011895 | 0.975475–1.035324 | 0.302763 | 0.307783 | 1.016581 |
| clean Data 控制 | 3 | 1.011733 | 1.000496–1.061195 | 0.303705 | 0.309191 | 1.018064 |
| dirty object 控制 | 3 | 0.998664 | 0.960521–1.036930 | 0.010878 | 0.010897 | 1.001777 |

此前 interop-ios 的单组 dirty Data ABBA 比率为1.183511，原版样本0.329–0.660ms，当前0.344–0.991ms，区间波动明显。六轮正式 dirty Data 比率分别 1.035324、0.975475、1.016267、1.007524、1.028231、0.999880。

合理推测：之前18%很可能包含宿主/调度状态的时变影响；本次数据不支持“稳定慢18%”。未验证：该波动的具体操作系统因果、物理iPhone性能、全部模型/载荷/内存/持续并发吞吐。不能进一步称绝对等效、全部更快、性能零成本，也不能凭单次差值要求为性能修改语义。

## 8. 实际建议与维护成本

1. 优先修复 Pointer-only equality 回归，用公开 API E2E 保留原版身份回退；这不是宣传清理。
2. 以“保留原版默认契约”为目标时，把 Mapper/泛型继承合并明确可选化并提供迁移说明。历史 fork 合并需求与现在原版替换目标不同；两个目标不能用同一句完全兼容遮盖。
3. 保留已证明有价值的 unsigned 边界/secure typed 容器/date boundary 修复，但逐项写清扩展范围、版本归属与允许类要求。别为完全还原某些原版缺陷机械撤销修复。
4. 修正 l/L、Core 最低系统依据、isSwiftDynamic 和百分百原版一致等事实性声明。没有维护实际使用场景时，未使用的 Swift检测标志可降级为 dynamic 元数据提示，减少长期错误承诺。
5. 不因这次18%未复现而删除历史结果；保留原始样本和多轮复测，性能结论限定当前同输入、同模型、同模拟器工作负载。
6. 新增能力优先集中在独立 Swift产品/可选配置；OC原版兼容核心每增加一个默认分支都扩大行为矩阵和跨版本维护成本。

## 9. 可重复产物

- 先行失败场景：[FAILURE-MODES.md](/Users/lee/Desktop/本地项目调试计划/projects/YYModel/Validation/research/20261004/OBJC-FAILURE-MODES.md)。
- 独立公开API探针：[Probe.m](/Users/lee/Desktop/本地项目调试计划/projects/YYModel/Validation/research/20261004/ObjCProbe.m)。
- 构建/运行驱动：[run_research.py](/Users/lee/Desktop/本地项目调试计划/projects/YYModel/Validation/research/20261004/run_research.py)。在仓库根目录执行 `python3 Validation/research/20261004/run_research.py --only objc --output /tmp/yy-objc-review-repeat` 会从固定Git提交重新导出原版/tag，保留当前master源码只读；输出独立JSON与构建/运行日志。它是观察探针，退出0仅表示探针构建运行/写回执成功，并不表示被审查库无回归。
- 三版回执：[probe-receipts.json](/Users/lee/Desktop/本地项目调试计划/projects/YYModel/Validation/research/20261004/objc-probe-receipts.json)。
- 多轮ABBA驱动：[remeasure.py](/Users/lee/Desktop/本地项目调试计划/projects/YYModel/Validation/research/20261004/remeasure_objc.py)。复跑时指定新的 `--output` 目录，依赖现有已通过门禁的 `/tmp/YYModel-swift-contract-20261004/interop-ios` 构建目录和同一已启动模拟器；源码/框架/输入哈希改变则停止。
- 正式性能原始值、二进制hash、每轮比率：[perf-ios-exclusive/receipt.json](/Users/lee/Desktop/本地项目调试计划/projects/YYModel/Validation/research/20261004/objc-performance-receipt.json)。每块 `.json` 与 `.log` 也在该目录。
- 首次 equality 探针只有 SEL/long double 时会触发原版 identity hash；已记录混杂因素并加入双方相同 anchor 再比较，见 `probe-notes.md`，没有修改既有断言或库实现。

本轮 xcodebuildmcp 相关工具未暴露，未伪称使用 MCP 跑过 XCTest；模拟器执行复用组件原有 `run_delivery.py` 的公共 runner。报告严格区分本轮新鲜探针/性能证据与既有测试回执。

## 持久化补充

以上具体结果是该次运行快照。复跑命令、原始运行器与便携运行器的区别见 `Validation/research/20261004/README.md`。组件源码本轮未修改；指针 equality 回归仍存在。
