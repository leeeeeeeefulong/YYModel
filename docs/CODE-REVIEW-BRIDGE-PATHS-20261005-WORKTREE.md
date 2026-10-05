# YYModel 最新桥接修复审核与解决方案

2026-10-05。当前 HEAD 为 `7605086c9ad71c1b61740bceb8c3f4fa65d486f1`，审核对象为其上未提交的最新修改。本轮与上次冻结的 17 个 Swift 文件逐一比对，新增生产差异仅在 YYModelJSONValue.swift 和 YYModelNativeBridge.swift；完整阅读这两项差异及相关容器调用链。本轮没有重新宣称完成全仓 OC 与性能审核。

## [P1] 按实际物理键恢复数值，并保留 Foundation 类型检查

位置：`YYModelSwift/YYModelNativeBridge.swift:185–188`，关联查找函数 `:139–142`。

新增逻辑把转换后的 CodingKey 直接用于原始 JSON 字典查找，然后不经过 base.decode 就返回恢复值。配置自定义 keyDecodingStrategy 将 foo→bar、bar→baz 时，回调读取逻辑键 bar 应得到物理键 foo；代码却取到物理键 bar。只要那个节点带有保存的 Double，就静默返回另一个字段。

公开 API 实测输入的 foo 为约 1.0、bar 为约 2.0：无 hook 得到 `1.0000000000000002`，空操作 willTransform 后得到 `2.0000000000000004`。进一步把 foo 改为字符串 `not-a-number`，无 hook 正确抛 typeMismatch；加空操作 hook 后错误返回约 2.0。上轮版本在字符串样本的两个路径均抛错，确认这是新增回归，不只是旧有 1 ULP 问题。

**解决方案：**

1. 先保留 base.decode 的严格验证；成功后才能替换其数值。这能立即阻止非法类型被错误接受，但单独这样修改仍不能解决两个合法数字间的串值。
2. 同时记录物理键到转换后键的对应关系，使原始数值查找使用 Foundation 实际选中的物理节点，而不是用 CodingKey.stringValue 猜测。应在本次解码的 key strategy 执行过程中记录对应关系，避免为了查找再次执行用户回调。
3. 对 .convertFromSnakeCase、自定义策略、嵌套层级及键冲突使用一致的选择规则；不能确认实际节点时不得返回同名但来源不明的 metadata。String-key Dictionary 的物理键语义需要单独保留。

**验收：**复现材料中 key-renamed 两侧应返回同一个 foo 值；key-type 两侧均抛 typeMismatch；补充 snake_case 与 nested/super 路径，检查键回调次数和 codingPath。不能只增加一次 base.decode 就关闭此问题。

## [P2] 让 Optional 和标量集合也经过数值恢复路径

位置：`YYModelSwift/YYModelNativeBridge.swift:246–254`；同类快捷路径也存在于 PrefixKeyedDecoder、PrefixUnkeyedDecoder 和 PrefixDecodingValue。

本次恢复分支只匹配直接的 Double/Float/CGFloat。策略回调通过 singleValueContainer 解码 `[Double]` 或 `Double?` 时，nativeCompatible 快捷路径仍直接交给 Foundation，读取的是 JSONSerialization 后已经舍入的值。普通标量恢复成功不能证明包装类型也恢复成功。

输入 `1.000000000000000111022302462515654042363166809082031251`：无 hook 的 Double bitPattern 为 `4607182418800017409`；空操作 hook 后，[Double] 首元素和 Double? 均为 `4607182418800017408`。标量、手动 unkeyed 和手动嵌套 keyed 三个对照均一致。这是上一轮精度缺陷尚未覆盖的入口，不是本次才出现的全部新问题。

**解决方案：**

- 在存在数值 metadata 的桥接中，Optional、Array、Set 和 Dictionary 应递归经过保留 metadata 的容器；仅对已证明不需要恢复的类型保留 native 快捷路径。
- 集中处理泛型 leaf/collection 的分流，避免在多个 decode 重载中分别补 Double、Optional<Double>、[Double] 等具体类型。
- 保留严格 null、类型和范围语义，以及集合索引和失败不前进的契约；Decimal/UInt64 不得通过 Double 中转。String-key Dictionary 不得二次应用键转换。

**验收：**array、optional 两组 hook/no-hook 的位模式一致，并覆盖嵌套包装、nil、错误字符串、UInt64.max 和 Decimal；同时保持回调执行一次。现有 37/37 契约和 84/84 Double 样本继续通过。

## 上轮两项问题状态

- Swift 5.9 注解问题：新增 `#if compiler(>=5.10)` 分支已修正源码。当前 Swift 6 严格并发编译通过；未运行真实 Swift 5.9，因此旧工具链最终验收仍待完成。
- Date/Data 自定义策略精度：上轮两个直接读取 Double 的样本已恢复一致，但集合包装仍遗漏，并新增上述键转换回归。

## 实际验证与交付

Apple Silicon macOS / Swift 6.3.3 / `-O -swift-version 6 -strict-concurrency=complete -warnings-as-errors`。独立 consumer 运行结果：既有契约 37/37、Double 样本 84/84；新增 7 组对照中 3 组一致、4 组暴露上述两类问题。框架编译成功和脚本退出 0 只表示观察完成，不能解释为发布通过。

[复现步骤](review-bridge-paths-20261005-worktree/README.md) · [最新原始结果](review-bridge-paths-20261005-worktree/BridgePathsConsumer.json) · [前版对照](review-bridge-paths-20261005-worktree/BridgePathsPrevious.json) · [回执](review-bridge-paths-20261005-worktree/receipt.json) · [源码 SHA-256](review-bridge-paths-20261005-worktree/manifest.json)

维护建议：这两项都应收敛到“实际节点定位 + 按目标类型读取数值”的内部桥接，而不是继续为不同业务模型追加特判。公共模型无需新增协议、宏或字段注解。建议先处理 P1 的数据串值与类型检查，再补集合递归。

本轮只生成审核与复现文件，没有修改生产源码、提交或推送；没有访问 PPLive。未运行 iOS 真机、模拟器、真实 Swift 5.9 或 OC 性能测试。
