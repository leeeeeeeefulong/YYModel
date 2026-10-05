# YYModel 键映射与集合修复复审及解决方案

日期：2026-10-05。结论：你提供的 7/7、4/4、37/37、84/84、93/93 回执已独立验证；原始样本确实修复，但组合场景仍存在 5 类问题，其中 2 类是新增回归，3 类是修复未覆盖的残余问题。通过率不能推导为整个原生契约已恢复。

审核范围：永久仓库 `/Users/lee/Desktop/本地项目调试计划/projects/YYModel`，HEAD `7605086c9ad71c1b61740bceb8c3f4fa65d486f1` 上的未提交改动。相对上轮冻结的 17 个 Swift 文件，生产源码增量仅为 YYModelNativeBridge.swift。本轮已完整检查该增量及 Prefix/原生集合调用链，没有把历史报告作为事实依据。

## 1. [P1] 将所有祖先键解析为物理路径，避免子树串值

位置：`YYModelSwift/YYModelNativeBridge.swift:327–330`，集合分支也在 `:341–344`；残余问题。

代码只替换最后一个键，`objectPath` 仍来自 Foundation 的逻辑 codingPath。父级键也被转换时，该路径不能用于遍历原始物理 JSON。实际输入同时有 `physical_parent.foo`（约 1.0）和 `parent.foo`（约 2.0），custom 将 physical_parent→parent、parent→unused。回调读取逻辑 parent.foo，无 hook 得到 bitPattern `4607182418800017409`，空操作 hook 后得到 `4611686018427387905`。严格 base.decode 成功也不能阻止随后从另一个子树替换合法数值。

convertFromSnakeCase 的 parent_node→parentNode 样本也失败：找不到物理祖先，返回已经舍入的值，丢 1 ULP。这说明修复只解决了根级最后一个键。

**解决方案：**每个桥接容器同时携带显示用的逻辑 codingPath 和读取用的物理节点游标。创建 keyed 子容器、unkeyed 子容器或 superDecoder 时，按本层记录的映射进入正确物理节点，再将这个子树交给子容器；不要继续拿逻辑祖先路径遍历原始树。保留严格类型校验及用户回调一次性。

**验收：**renamed-parent 两侧均取 physical_parent.foo；snake-parent 两侧位模式一致；覆盖两层重命名、数组中的重命名对象、super 路径和同名物理祖先并存。修复最后一个键或增加 base.decode 均不足以关闭此问题。

## 2. [P2] 在逐元素纠正后构建 Set，避免不可逆去重

位置：`YYModelSwift/YYModelNativeBridge.swift:276–292`；残余问题。

先 base.decode(Set) 再按圆整值匹配原始数组，去重已经发生，无法恢复被丢掉的元素。输入 `[1.0, 1.000000000000000111022302462515654042363166809082031251]`，原生路径是两个不同 Double，Set.count=2；hook 路径先重序列化，两者都成为 1.0，最终 count=1。单个元素的 Set 已修复，但不能代表含舍入碰撞的 Set 正确。

此外，当前每个集合元素都扫描 rawArr.first，匹配部分具有 O(n²) 增长；这是源码结构结论，本轮没有将其转化为未经测量的耗时倍数。

**解决方案：**按原始数组顺序严格解码每个 Element，先恢复正确数值，再插入 Set。使用数组元素索引或物理节点游标，不依赖去重后的值反查原始元素。对用户模型保持一次 init/一次回调，不能为了补救重跑整个 Set。这样去重发生在正确的类型值上，并消除逐元素全数组扫描。

**验收：**set-distinct count=2 且位模式一致；真实重复值仍按原生 Set 规则去重；单元素控制继续通过。增加反向顺序和错误字符串元素，确保严格拒绝及回调次数不变。

## 3. [P2] 保留集合内用户 Decodable 的完整 codingPath

位置：`YYModelSwift/YYModelNativeBridge.swift:445–449`，同类分支 `:339–345`、`:394–399`；新增回归。

新增分支用类型名称前缀把所有 Optional/Array/Set/Dictionary 都直接交给 base.decode，包括用户自定义模型。用户 init(from:) 因而收到桥接内部的相对路径，绕过 PrefixDecodingValue。自定义模型只记录 decoder.codingPath 即可复现：策略解码 `[PathLeaf]`，无 hook 为 `value.Index 0`，hook 后为 `Index 0`；解码 `PathLeaf?`，无 hook 为 `value`，hook 后为空。前版这两组均一致。

外层 rebasing 只能补抛出错误的路径，无法修复用户初始化过程中已经读取或使用的 codingPath。这会改变依赖解码位置的业务行为。

**解决方案：**用内部能力协议判断可直接走 Foundation 的纯标量集合，保留用户模型经 PrefixDecoder 解码的路径。集合应逐元素经适配器构造，不能以 `String(describing: T.self)` 的名称判断所有泛型类型。不要先原生构造用户模型，再为了纠正路径构造第二遍。

**验收：**model-array-path、model-optional-path 两侧完全一致；补充集合的 keyed/unkeyed 入口、嵌套 Optional 和 superDecoder，并验证用户 init 与策略回调仅执行一次。

## 4. [P2] 用泛型能力实现完整的包装类型递归

位置：`YYModelSwift/YYModelNativeBridge.swift:258–265`、`:296–301`；残余问题。

Mirror 分支虽递归计算 corrected，重包时却只支持列出的几种 Wrapped，其他情况直接丢弃纠正结果。`[[Double]]?` hook/no-hook 仍相差 1 ULP。同时 Int-key Dictionary 明确落回原生舍入值，`[Int:Double]` 读取键 1 也相差 1 ULP。它们都是框架已经接受的 Codable 类型，不应把常见泛型组合视作无需保证的 exotic 类型。

**解决方案：**在框架内部为 Optional、Array、Set、Dictionary 添加带关联类型的能力协议实现，在知道 Wrapped/Element/Key/Value 的泛型上下文中递归解码或纠正；保留 optional.some/.none 层级。Dictionary 按原生 String/Int 物理键语义处理，明确哪些 Key 会走 unkeyed 表示。公共模型无需新增协议或字段注解。避免继续追加 `[Double]?`、`[[Double]]?` 等白名单。

**验收：**optional-nested-array、int-dictionary 位级一致，并验证 nil、嵌套 optional.some(nil)、Decimal、UInt64.max 以及错误类型。String-key Dictionary 不应二次执行 keyDecodingStrategy。

## 5. [P2] 将 keyMap 路径改为结构化 Hashable 键

位置：`YYModelSwift/YYModelNativeBridge.swift:70–71`；新增回归。

将 stringValue、intValue 用 # 和 / 拼接未做无歧义编码。合法键 `a#-1/b` 与两层路径 `a`→`b` 编码相同；首胜记录会混用不同对象的映射。新 consumer 先读取字面键 a#-1/b 内的 first→n，再读取 a.b 内的 second→n。后者错误复用 first 的映射，hook 路径取到约 2.0，无 hook 应为约 1.0。前版此样本只有舍入误差；本版新增整字段串值。

**解决方案：**用 `[PathComponent]` 或等价的结构化 Hashable 键，逐段保留 stringValue 与 Optional<intValue>，不要使用未转义分隔符或把 nil 合并为 -1。该修复可局部完成，维护成本低；并与问题 1 的物理节点游标整合。

**验收：**path-collision 两侧值一致；包含 /、#、空字符串的键和数组索引路径互不混用。可增加纯结构校验，证明路径编码是单射，而非仅靠某几个特殊字符串样本。

## 原始回执复验与范围

| 验证 | 本轮独立结果 |
| --- | --- |
| 上轮 BridgePaths | 7/7；非法类型两侧均抛错 |
| BridgeConsumer Date/Data | 4/4 观察一致 |
| ExternalRules | 37/37 |
| DoubleStress | 84/84 位模式一致 |
| swift test -c release | 93 项，0 failures |
| 新增组合对照 | 9 组，8 组不一致；涵盖上述 5 类问题 |

Apple Silicon macOS / Apple Swift 6.3.3，独立编译使用 `-O -swift-version 6 -strict-concurrency=complete -warnings-as-errors`。同一个新 consumer 也链接前版冻结库运行，以区分新增回归与残余问题。新样本及冻结源码的 SHA-256 均保留。

[复现说明](review-keymap-collections-20261005-worktree/README.md) · [本版结果](review-keymap-collections-20261005-worktree/KeymapCollectionsConsumer.json) · [前版结果](review-keymap-collections-20261005-worktree/KeymapCollectionsPrevious.json) · [回执](review-keymap-collections-20261005-worktree/receipt.json) · [源码身份](review-keymap-collections-20261005-worktree/manifest.json)

## 建议落实顺序与维护成本

先修物理祖先定位及 keyMap 编码，关闭串值；然后统一内部泛型集合适配，逐元素构造，同时关闭 Set 去重、codingPath 和包装类型遗漏。继续堆叠 Mirror 白名单与类型名字符串分支会提高维护成本，也容易只覆盖报告里的单一样本。

这套内部实现应保持普通 Codable 模型零侵入，不要求业务模型采用新协议。所有 custom init、key/date/data callback 都按原生流程执行一次；严格校验在实际读取节点上执行，不在构造完用户模型后重新解码。

本轮没有修改生产源码、提交或推送，没有使用 PPLive。未运行 iOS 真机/模拟器、真实 Swift 5.9 编译器或专门的 ibireme 性能对比；93 项测试中的已有计时输出不作为组件性能交付结论。
