# 新天气数据与发布条件核验（2026-10-06）

本报告评估当前工作区修复候选。基线生产源码来自 824faad；随后 f97a4cb 仅修改发布脚本及忽略目录，不改变这 20 个 Swift 文件。2026-10-06 严肃复核后新增 YYModelDecoder R-05 显式拒绝修复，候选为 6 个生产文件变更；该候选已作为 **2.3.3** 提交（`4a016ef`）、重新冻结证据并打 tag 推送，时间线与最终判定见文末「最终核验与发布判定」。

范围按用户确认：仅评估实际执行验证的现代系统。旧系统、未运行平台、真机、远程 CI 和生产天气服务稳定性不推定通过。历史 93/475/555 项结果均不作为本轮通过证据。

## 新数据与复现方法

使用 [Open-Meteo 官方免费非商业 API](https://open-meteo.com/en/docs)，无需 API key；数据按 CC BY 4.0 保留归属信息。上海、纽约、东京的新响应含 216 小时及 9 日预报；另独立请求非法变量，保存真实 HTTP 400 服务错误。实时响应与人工变异分开标记。

- 原始响应：`Verification/release-20261006/fixtures/weather-api.json`，10,878 字节。
- SHA256：`30fa38881a0f8c566f63e00f11f2d767108018c19c7b101cfd6c213b189a0920`。
- URL、UTC 采集时间、状态码、哈希和单位长度在相邻 source JSON；重新抓取脚本同时获取正常与错误响应，拒绝覆盖既有快照。
- 完整普通 Codable DTO 逐键、逐数组元素与独立 Foundation raw JSON 对照，检查 1,208 个叶值。业务检查包括时间与值对齐、湿度范围、昼夜值、降水/风速非负、每日最高温不小于最低温；由 raw 及 DTO 分别计算城市摘要。
- 覆盖 native/compatible/legacy 的 Data/raw 输入、Data/object 输出、空 hook 次数、mapper、显式日期、缺失/null/数字字符串/坏数组/异常 JSON/越界业务值/HTTP 400。

离线复跑，无需再次联网：

```sh
python3 Verification/release-20261006/run.py --output /tmp/yymodel-new-run
python3 Verification/release-20261006/run.py --output /tmp/yymodel-new-ios-run --simulator BOOTED_UDID
```

联网采集独立的新快照：

```sh
python3 Verification/release-20261006/fetch_weather.py --output /tmp/yymodel-new-weather
python3 Verification/release-20261006/run.py --fixtures /tmp/yymodel-new-weather --output /tmp/yymodel-new-weather-run
```

每次执行冻结源码及消费者，严格 Swift 6、优化、完整并发检查、warnings-as-errors 编译；保存命令、退出码、结果 JSON、系统和 SHA256。编译成功不计运行通过，环境控制结果不计业务正确。`Verification/release-20261006/Evidence/` 为本地冻结目录，仍被忽略；消费者、快照、runner 已纳入版本控制并接入 CI `release-e2e`（macOS 复跑）。提交 `4a016ef` 的远程 CI `test` 与 `release-e2e` 两 job 均已跑绿（run 37375083972）。

## 原五类组合问题与旧文档

当前 824faad 源码独立重跑原九场景 × hook 开关，18/18 通过，两次输出完全相同。包含父键重命名、snake case、结构路径碰撞、Set 纠正后去重、用户模型 codingPath、Optional 嵌套数组及 Int→Double 字典；数值按字面量 bitPattern 断言。

原四份登记/设计/实施/验收文件已在 824faad 清理中移除，当前无法把它们作为现行验收清单。现存升级文档的 K-01–05 描述上述五类契约；已有 Tests 没有直接覆盖这些自定义 Data 策略组合，故补充独立 `KeymapCombinationE2E.swift`。本轮不宣称仅凭 18 行就覆盖原全部 22 个 P/F/A 缺陷或五种数值类型。

## 本轮问题记录

严重度：S1 表示崩溃或成功返回错误业务数据；S2 表示特定规则/手写容器边界的功能错误。以下均有修改前运行证据；安全修复限定相关入口，不调整版本号。

| ID / 严重度 | 现象、复现条件 | 影响范围 | 解决方案与状态 |
| --- | --- | --- | --- |
| R-01 / S1 | 子 Encodable 写入草稿后 throw，父容器 catch 并继续；失败节点覆盖已成功 key 或消耗数组位置 | object 导出、export hook 的树编码；涉及手写异常恢复 | 子节点先独立编码，成功后提交；keyed/unkeyed/dictionary 已修复，最终三平台通过 |
| R-02 / S1 | 上述失败后直接写 String/Int/Bool/Double，被适配器转进 Foundation 泛型重载，下一字段读到草稿 | compatible Data 手写编码器 | keyed/unkeyed/single 补 14 种既有标量的具体转发；保留 mapper/filter；已修复，最终三平台通过 |
| R-03 / S2 | 持有 superEncoder 或仅持其返回的 keyed/unkeyed/single/后代容器，同 key 后续写入导致错误胜者 | 四条树出口，全部在 encode 调用期间发生 | 引用 token 由编码器与全部容器共享，后代引用持有父 token，最后持有者释放才提交；42 行修复前对照发现 25 个错误，已修复，最终三平台通过 |
| R-04 / S2 | 多态根注册 fallback/lossy/typedDefaults/missing 策略被接受后忽略，两种注册顺序均复现 | 配置多态根的调用方，payload 策略不受影响 | 根规则构造时明确拒绝不支持的字段策略；保留 payload 策略正向用例；已修复，最终三平台通过 |
| R-05 / S1 | 默认值 7 被无法 JSON 编码的新业务值 99 替换，直接 decode 得到 99，superDecoder 却仍读旧快照 7 | KeyPath typed default 被覆盖且通过容器读取 | 替换时先清除旧 JSON 快照；业务值通道保持 99；容器入口仅使用 JSON 快照，无快照时显式抛 `typeMismatch`，不再回退到业务实例或旧快照；已修复，重冻证据三平台复跑通过 |
| R-06 / S1 | iOS 18.2 Single 容器 catch 子编码失败后继续 String 编码触发 SIGTRAP；单补具体标量重载仍崩溃 | compatible Data 的手写单值异常恢复 | 泛型单值入口经 base container 的 EncodingBox 执行，恢复 Foundation 子事务/回滚；树单值同样隔离失败子节点；已修复，最终三平台通过 |
| R-07 / S1 | native raw 输入包含 Infinity/NaN/Date/NSObject 时触发 NSInvalidArgumentException，Swift catch 无法捕获；四输入独立进程均 SIGABRT | native 已解析对象入口遇到非法 JSON 业务值 | 序列化前验证可表示的 JSON 树，非法值返回可捕获 DecodingError；仍序列化原对象以保留 Foundation 行为；已修复，最终三平台通过 |

问题清单还记录下列实测限制，不能用控制行通过来掩盖：

| 事项 / 状态 | 已确认行为、业务影响 | 本次处理与后续建议 |
| --- | --- | --- |
| Foundation catch 后继续编码 / 条件限制 | macOS 26.7/iOS 26.5 的部分泛型或 single 容器失败恢复保留草稿；iOS 18.2 的 Foundation 行为不同 | 原生 Data 委托 Foundation，保留独立环境观察；业务 Encodable 应让错误向上传播，在新容器中编码替代 DTO，避免相同容器 catch 后继续。树出口单独要求正确 fallback，不复制上游错误 |
| legacy 缺失数据 / 已文档化契约 | legacy 可以把缺失/null 的数值填零，复杂天气 current 也可生成空/零占位 | 天气业务校验会拒绝无效 interval/time；需要严谨数据校验的接入使用 compatible 或 native，并保留业务校验，不把零占位当有效预报 |
| 天气 schema / 已补全测试 DTO | API 第二、第三城市含可选 location_id，第一城市不含；完整键 oracle 首次执行拒绝漏建模 DTO | DTO 增加 Optional 字段，不修改库；未来字段变化必须调整 DTO/oracle，而不是静默删除完整键断言 |
| 性能 / 延后 | 本轮已有微基准显示增强 decode 比 Foundation 慢；未发现新天气流程不可完成、超时或资源耗尽 | 不作为发布阻塞，不进行无关性能改造；该微基准不代表大负载/并发 SLA 已验证 |

## 最终核验与发布判定

**结论：发布条件已闭环，2.3.3 已发布。** 本节前文记录的中间状态（原 `Evidence/final` 为修复前冻结、修复未提交、无新 tag、远程 CI 未跑绿）已在同日收尾中逐项解除：候选以 `4a016ef` 提交并打 `2.3.3` tag 推送，远程 CI `test` 与 `release-e2e` 两 job 跑绿；`Evidence/` 按 20 文件候选重新冻结，`verify_evidence.py` 全量通过（610 个文件哈希、三平台 454 行、消费者哈希一致）。前文的"拒绝发布（条件未闭环）"判定针对收尾前状态，保留作为时间线记录；失败从未重命名为通过，环境控制行与业务断言的区分继续有效。

| 执行环境/入口 | 最终结果 | 证据 |
| --- | --- | --- |
| macOS 26.7 / Swift 6.3.3 优化公开消费者 | 454/454（重冻） | `Evidence/final/macos/receipt.json` |
| iOS 18.2 ARM64 模拟器 | 454/454（重冻） | `Evidence/final/ios18/receipt.json` |
| iOS 26.5 ARM64 模拟器 | 454/454（重冻） | `Evidence/final/ios26/receipt.json` |
| 混合 ObjC/Swift 互转 | 9/9（随新候选重跑） | `Evidence/final/mixed-ios18`、`mixed-ios26` |
| 独立 SwiftPM 应用，release 构建 | 136 天气 + 9 混合（随新候选重跑） | `Evidence/final/delivery/spm-weather.log`、`spm-mixed-weather.log` |
| Swift 回归 | 108/108（随新候选重跑） | `Evidence/final/delivery/swift-regression.log` |
| ObjC Demo | 84/84（随新候选重跑） | `Evidence/final/delivery/objc-business.log` |
| CocoaPods 本地源码校验 | YYModel2 passed validation（随新候选重跑） | `Evidence/final/delivery/pod-lint.log` |
| 远程 CI（macOS） | `test` + `release-e2e` success | run [37375083972](https://github.com/leeeeeeeefulong/YYModel/actions/runs/37375083972)（commit `4a016ef`） |

收尾补充说明：

- `Evidence/final/{macos,ios18,ios26}` 已替换为 20 文件候选的完整冻结（源码、消费者、快照、命令日志、receipt），并从当次运行复制；旧冻结中的空 `YYModelSwift.abi.json`（NO_MODULE 空转储）不再随新候选重生成，历史基线目录中的副本按原字节保留。修改前的 95 条失败断言、生命周期失败、两次 iOS 18 崩溃（`Evidence/baseline/`）与四种 native raw 崩溃的可重放资料（`Evidence/native-raw-baseline/`）均未改动。
- `summary.json` 与 `artifact-manifest.json` 按新候选重写，`summary.json` SHA256 为 `b542e24c5ee44f0ea1e775d3ec38e48d3917d3d7b7ee3bb0b2c86e4a1fc8052f`；`verify_evidence.py` 输出 `Verified 610 evidence files; identical 20-source candidate; 454 rows per platform`。冻结的 `Evidence/` 按设计保持本地（`.gitignore`）作为可复核字节；可重复门禁（版本控制的消费者/快照/runner + CI `release-e2e`）已在 `4a016ef` 跑绿。把冻结证据晋升到外部受控存储（例如 GitHub Release 资产）属发布管理动作，待执行。
- 每平台 454 行组成：恢复 48、标量恢复 72、Foundation 控制 4、多态/默认值 22、引用容器生命周期 42、原五类组合 18、天气 136、数值/日期边界 112。恢复矩阵的 188 行明确分成 170 条业务断言与 18 条环境控制；控制不能证明 catch 后继续编码安全。数值矩阵另含原生 Foundation 对照，不能据总计宣传所有入口的数值精度相同。

### 发布条件收尾状态

1. ✅ 发布候选包含六个生产文件修复，哈希重冻并更新 `summary.json`/`artifact-manifest.json`；已提交（`4a016ef`）并以 `2.3.3` tag 发布，旧 2.3.2 tag 与修复前源码不再作为通过候选。
2. ✅ 版本承诺按实际验证范围书写：README/CHANGELOG 仅承诺天气 schema、64 位整数/Double、已测日期/规则入口与混合消费；ObjC/Swift 手写编码器 catch 后继续编码的 Foundation 限制、legacy 占位值校验要求在 CHANGELOG Known Limitations 中延续。
3. ✅ 消费者、快照、失败模式与 runner 已入库，CI `release-e2e`（macOS）跑绿（run 37375083972）；重冻证据本地校验通过。冻结证据的外部受控存储晋升待发布管理者执行。
4. ✅（以不承诺方式闭环）发行声明未扩展到未验证范围：真机与旧 OS、tvOS/watchOS、新 E2E 的 Float 二次舍入/Decimal/Int128/UInt128/较小整数宽度/JSON5/非默认非有限浮点转换策略、日期日历极值、大负载/并发 SLA 均保持"未验证即不宣称"，后续扩大承诺前必须先补运行证据。

本轮未发现核心天气流程无法使用的性能问题。既有微基准记录 native decode ~0.08ms、增强 decode ~0.36–0.40ms/次（约 4.4–4.8 倍，随运行波动）；不是生产 SLA 或优化结论，留待性能专项。GitHub Release 对象可按 `publish_releases.sh` 中 2.3.3 条目创建；`pod trunk push` 由发布管理者另行执行。

