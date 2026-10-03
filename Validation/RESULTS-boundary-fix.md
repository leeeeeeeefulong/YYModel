# G1–G4 修复验收（2026-10-04）

基于 master `854f7bd9b6d4db964f783a82a8b64ca3f2eb512f`，修复源码身份以 [JSON 回执](receipts/boundary-fix-20261004.json) 中的 SHA-256 为准。本次提交包含源码、公开 API E2E、失败场景、文档和回执；没有操作正式业务 App。2.1.8 标签仍固定在 `518c405a51ab46cb6e6a39e22a36ab9d9788f78c`，不包含本次修复。

## 修复行为与兼容性

- **G1 / OC UInt64**：NSDecimalNumber 先精确向零截断，再按无符号范围转换。`18446744073709551615` 和 JSON 数字 `18446744073709551615.0` 均保持完整值，避免有符号 longLongValue 饱和。NaN、正数越界不写入已有属性；负数转换保持原版语义（`-1` → UInt64.max），不宣称全部 OC 数值类型已改为严格范围检查。
- **G2 / Swift 非有限值**：拒绝 NaN、infinity 和 Float 窄化产生的溢出，覆盖 Data 的快/慢路径及 Any 输入；Decimal、Date 同样防止接收非有限值。有限值控制用例继续通过。
- **G3 / 负毫秒**：快/慢路径共用日期转换；使用绝对值判断原有 `1e11` 秒/毫秒阈值。`-1700000000000` → `-1700000000` 秒，数字与字符串一致。阈值仍是自动推断，不提供任意历史日期的精确单位识别。
- **G4 / 嵌套失败传播**：原版也会忽略子模型 transform 返回 NO，因此默认保留兼容行为；根模型可实现 `+modelRequiresSuccessfulNestedTransforms` 返回 YES，开启本次解析的严格策略。覆盖对象、数组、字典、集合、深层模型及 will-transform 取消；失败根返回 nil，已有对象 setter 返回 NO。状态沿调用栈显式传递，不使用线程局部变量或全局失败标记。

严格模式使用 YYModel 协议转换钩子，信任输入中已实例化的模型；更新已有对象可能部分赋值，**不提供事务回滚**。调用方若需要失败后保留旧对象，应先解析一个新对象，成功后替换。

## 新鲜验收

先列出失败场景并写好 E2E，再修改库。相同 62 项验收在修复前为 21 通过、41 失败；没有在实现后补写单元测试，也没有修改期望来使结果通过。

| 检查 | macOS arm64 | iOS 26.5 arm64 模拟器 |
|---|---:|---:|
| G1–G4 边界（含固定原版对照） | 62 / 62 | 62 / 62 |
| 既有数值组合 | 1,792 / 1,792 | 1,792 / 1,792 |
| Open-Meteo 天气验收判定 | 20 / 20 | 20 / 20 |

边界包含有效值、UInt64 小数/越界、并发 32 次混合策略以及校验回调中独立解析的重入。默认嵌套行为与 ibireme `c7df27538c043e5f54f5b6605958544bb529892f` 对照一致。

天气检查包含三城市固定快照与 96 城市合成扩容，逐字段、逐数组元素比较共同业务模型，并检查 OC keyPath 导出及 JSON 往返。20 项判定中有两项是原生 JSONDecoder 对 dirty/sparse 的预期拒绝，不能理解为所有引擎均支持脏数据。

补充回归：既有独立契约复现 38/38、Swift release 16/16、Demo 84/84（构建无警告）、Framework XCTest 27/27、Swift 6 模块编译通过。Package.swift 最低平台声明及旧 XCTest 仍有弃用/原型警告，相关文件本次未改动。

## 性能样本

先完成全部正确性检查，再顺序运行性能任务。天气输入在计时前固定为 Data；预热 5 次，7 轮采样，每次消费结果及释放临时对象。完整天气验收的两平台样本、大载荷规模和环境信息随 JSON 回执保存。

macOS 额外按「修复前 / 修复后 / 原版 / 原版 / 修复后 / 修复前」交替测量相同天气载荷；每个引擎/载荷合并 14 个样本，每个样本 100 次：

| ms/次，中位数 | 修复前 854f7bd | 本次修复后 | ibireme 原版 |
|---|---:|---:|---:|
| OC 干净天气 | 0.2545 | 0.2473 | 0.2627 |
| OC 脏天气 | 0.2702 | 0.2557 | 0.2609 |
| Swift YY 干净天气 | 0.7527 | 0.7583 | — |
| Swift YY 脏天气 | 4.1612 | 4.2368 | — |

Swift 样本分别增加约 0.7% 和 1.8%。初始小模型微基准每轮仅 1,000 次，曾观察到约 5.6% 的差异；扩大到每轮 100 万次并消费字段结果，按 before/after/after/before 重测后，合并 14 样本的中位数为 0.4908 → 0.4876 ms/千次。OC 日期样本为 34.1490 → 33.5229 ms/千次。初始与复测全部样本均保留，不能仅挑选较快的一轮作为结论。

这些样本没有复现稳定的明显回退，也不足以证明普遍提速。未锁定 CPU 频率、温度或后台负载；没有实体 iPhone、iOS 27、峰值内存、长期泄漏或 sanitizer 证据。OC/Swift 模型表示不同，不把跨语言耗时比值解释为纯引擎效率。

## 复跑

按 [README](README.md) 提取固定原版提交，再依次执行（性能命令不要并行）：

```sh
python3 Validation/run_boundary.py --original-source /tmp/YYModel-original/YYModel --output /tmp/yymodel-boundary-mac
python3 Validation/run_boundary.py --original-source /tmp/YYModel-original/YYModel --simulator SIMULATOR_UUID --output /tmp/yymodel-boundary-ios
python3 Validation/run.py --original-source /tmp/YYModel-original/YYModel --output /tmp/yymodel-business-mac
python3 Validation/run.py --original-source /tmp/YYModel-original/YYModel --simulator SIMULATOR_UUID --output /tmp/yymodel-business-ios
swift test -c release
make -C Demo build && ./Demo/yymodel_test
xcodebuild test -project Framework/YYModel.xcodeproj -scheme YYModel -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' IPHONEOS_DEPLOYMENT_TARGET=13.0 CODE_SIGNING_ALLOWED=NO
```

四个 Validation 命令应退出 0。与本次修复前比较时，将 854f7bd 提取到独立目录，并使用 `--source-root` 指定，复用同一验证包与固定输入。严格模式、默认模式及原版边界实际值均随 JSON 回执保存。
