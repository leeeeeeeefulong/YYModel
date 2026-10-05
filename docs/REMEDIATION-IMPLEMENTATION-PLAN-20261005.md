# 修复落地实施计划（Remediation Implementation Plan）— 2026-10-05

> **文档定位**：把 [REMEDIATION-DESIGN-20261005](REMEDIATION-DESIGN-20261005.md) 的设计排入可执行的阶段与任务。
> 每阶段的通过/失败判定一律以 [REMEDIATION-ACCEPTANCE-PLAN-20261005](REMEDIATION-ACCEPTANCE-PLAN-20261005.md) 的门禁为准；本文不重复判定标准。
> 缺陷编号出处：[DEFECT-REGISTRY-20261005](DEFECT-REGISTRY-20261005.md)。

---

> **执行证据更新**：当前修复进度以 [公开 E2E 状态表](../Validation/remediation/STATUS.md) 和冻结源码回执为准。
> 下文“位置/复现”保留审计基线；源码疑点不等同于已复现运行缺陷。正式外部签署及旧 OS 运行验收未完成。


## 本轮执行记录与原计划调整（优先于下方历史任务处方）

用户已授权继续全部修复。本轮使用公开 API consumer E2E：先登记失败模式、运行基线，再修复；未在生产实现后补写单元测试。旧计划的三个 XCTest 文件、`XCTExpectFailure` 包装、R-1/R-2 双管线运行开关均不作为本轮交付物。新增已知失败必须阻断，不通过 expected failure 隐藏。

| 工作项 | 对应 ID | 当前可核验结果 |
|---|---|---|
| 探针迁入、冻结回执与可重放脚本 | A-03、全部 P/F/K | 已迁入 `Validation/remediation/`，CI 配置已写；远端尚未执行 |
| 误报排除与行为锁定 | P-02/P-07/F-03A | 已实测排除，不执行错误处方 |
| 契约确定化与字段收敛 | F-01–11、A-01 | 公开基线失败已修；R-1新增及独立祖先对照通过 |
| 组合路径与递归 | K-01、K-02、K-03、K-04、K-05、F-06 | 12 组公开两态对照通过，原始旧快照不作为当前基线 |
| 数值边界与 Float 双舍入 | P-06、P-01 现代 hook 补充 | 整数 54 项与 Float 超长尾巴等已通过 |
| 日期与可选互转诊断 | P-05/P-08 | µs 显式策略与诊断公开 E2E 已通过，automatic 行为保持 |
| 导出树与数值主干收敛 | P-03/P-04/A-02 | 已完成直接树导出与集中数值边界，保留跨调用不可变节点；编码回归及独立协议用例全部通过 |
| 能力探测与 Data 整数路由 | P-01/R-3 | `.automatic` / `.foundation` / `.integerTokens` 已实施并公开验证；真实旧 OS 仍待证 |
| 性能、下限、API、最终业务 oracle | G0/G4/G6 | 最终冻结475项公开E2E通过；性能/下限/API与业务oracle证据见公开状态表 |
| 外部签署与发布 | G5/G7 | 旧 runtime 与独立签署缺失；未发布、未代签 |

**维护成本决策**：R-1/R-2 保留两套实现会重建本次要消除的多管线问题，因此以冻结源码/先前发行版本回滚替代长期运行时双轨。R-3 的 `.numberParsingStrategy` 是明确的逐 decoder 选择，可独立回退到 Foundation。任何回滚需要重新运行该快照的公开验收，不声称存在未实现的内部开关。

**R-2 兼容修订**：不执行全部移除 associated object 的旧处方。`BoundaryLifetimeE2E` 证明 hook 捕获 NSNumber 在后续调用中仍须保真；采用单一规范数值节点，以及集中封装的不可变 NSNumber 边界元数据。内部运算不能直接读另一套 Double/Float 旁路。

下方为原审计提出的阶段划分和工作量估计，勾选框不是当前实现完成度；当前状态以本节及公开状态表为准，禁止把未实现的开关、旧 OS 验收或正式签署自动视为完成。

## 1. 原阶段划分

| 阶段 | 名称 | 目标缺陷 | 前置 | 工作量估算* | 合入形态 |
|---|---|---|---|---|---|
| Phase 0 | 安全网：探针入库 | A-03（+为全部缺陷备探针） | 无 | 1–2 人日 | 独立 PR（仅加测试） |
| Phase 1 | 止血：快速修复与回归锁 | F-11（P-02维持现状加锁，P-07关闭） | Phase 0 | 1–2 人日 | 独立 PR |
| Phase 2 | 契约确定化与组合映射 | F-01/02/03B/08/09/10、P-05、P-08、K-01~05 | Phase 0；**D3 评审推进** | 3–4 人日 | 每个缺陷独立 commit |
| Phase 3 | R-1 统一字段解析 | F-04/05/06/07、A-01、K-01~05收敛 | Phase 2 | 4–6 人日 | 特性开关合入，验收后开闸 |
| Phase 4 | R-2/R-3 数值收敛与旧 OS 路由 | P-01/03/04/06、A-02 | Phase 3 | 5–7 人日 | 特性开关合入，验收后开闸 |
| Phase 5 | 发布与文档收口 | 全部 | Phase 1–4 | 1 人日 | 版本发布 |

\* 估算为一名熟悉本库的 Swift 工程师净投入，含公开 E2E 编写，不含外部评审等待。

**关键依赖链**：Phase 0 → Phase 1 →（D3 契约评估推进）→ Phase 2 → Phase 3 → Phase 4 → Phase 5。
Phase 2 各缺陷相互独立，可并行；Phase 3 与 Phase 4 严格串行（R-3 依赖 raw 管线已确定化）。

**授权与签署状态声明**：用户已授权按本文档全部推进修复；推荐契约已通过独立技术评估，但正式签署仍未完成（待外部专业评审人与项目负责人正式签字）。

---

## 2. Phase 0 — 安全网：探针入库（治 A-03）

**目标**：在任何修复开始前，把历史审查探针与本次审计新探针全部迁入 `Tests/YYJSONDecoderTests/`，使「93/93 通过但 8/9 探针失败」的错位消失。

### 任务

- [ ] T0.1 新建三个探针文件（按验收计划 §3 的矩阵逐条落用例）：
  - `PrecisionProbesTests.swift` — P-01/02/03/04/05/06/07/08 全部探针（含 P-02 向零截断正负锁定）
  - `FieldResolutionProbesTests.swift` — F-01/02/03/04/05/07/08/09/10/11 全部探针
  - `EntryParityTests.swift` — 五入口一致性对照（G2 矩阵）及 K-01~05 组合用例
- [ ] T0.2 从 `docs/review-*-worktree/` 提取历轮探针（idiomatic/latest/followup/rereview/solutions/bridge/keymap），凡仍相关的迁入上述文件；来源轮次写进用例注释。
- [ ] T0.3 对当前已知会失败的探针：`XCTExpectFailure`（或编译开关 `REMEDIATION_PENDING`）包裹并标注对应缺陷 ID——**失败可见但不阻断 CI**，Phase 1/2 修复后逐条摘除包裹。
- [ ] T0.4 每条探针注释格式统一：`// DEFECT: <ID> | 设计: <D2-x/R-x> | 来源: <审计|某轮审查>`。
- [ ] T0.5 CI 快照：记录基线（93 既有测试 + 新增探针通过/预期失败计数），写入本文件附录。

### 交付物

三个探针文件 + 基线快照记录。**本阶段不改动任何框架源码。**

### 门禁与回滚

门禁：G0（既有 93/93 不破坏）+ G1 中"预期失败清单与缺陷登记册一一对应"。
回滚：纯测试新增，revert PR 即可。

---

## 3. Phase 1 — 止血：快速修复与回归锁（D2 组）

**目标**：修复无契约争议、单点、可立即验证的缺陷，锁定已正确行为，关闭误报。

### 任务

- [ ] T1.1 P-02 取整锁定：复核确认原源码 `copy.isSignMinus ? .up : .down` 在 Foundation API 下已是向零截断，生产代码不作改动；补充正负数浮点转整数锁定测试（`{"delta":-1.9} -> -1`，`{"delta":1.9} -> 1`）。
- [ ] T1.2 P-07 误报关闭：确认代码库不存在该幽灵代码，无需修改，直接关闭对应跟踪。
- [ ] T1.3 D2-3 六项（F-11a–f）：
  - a: 快路径 `codingPath: []` 改为 `codingPath + [key]`（完善快路径抛错上下文）；
  - b: `logicalNull` 单点统一，Presence 在零填充下统一返回 `.absent`；
  - c: `YYModelEncoder` 的 `state` 引用贯穿子容器，避免错误吞噬；
  - d: willTransform 浅拷贝保护（防范引用子树篡改）；
  - e: dictionaryDate 参数化传递，消除多线程共享状态竞争；
  - f: allKeys 过滤源键伪属性。
- [ ] T1.4 CHANGELOG 记录（P-02 保持向零截断正确语义，纠正历史审查文档反转认知）。

### 交付物

框架文件改动（`YYModelDecoder.swift`、`YYModelEncoder.swift`、`YYModelDictionary.swift` 等）+ 探针全绿。

### 门禁与回滚

门禁：G0 + G1（本组探针转绿）+ G4（性能快照对比无回退）。
回滚：独立 PR，revert 即回旧行为；每项缺陷独立 commit 便于单点回退。

---

## 4. Phase 2 — 契约确定化与组合映射（D3 组与 K 系列）

**目标**：在架构收敛前，把行为不确定/互相矛盾的语义**定死并公告**，对齐主代理五类 Keymap 组合映射。此阶段是 Phase 4（R-3 旧 OS 路由走 raw 管线）的前提——raw 管线必须先确定化。

### 推进状态说明

用户已授权按文档推荐方案推进全部修复；推荐方案已完成独立技术评估，待评审人最终签署。

### 任务

- [ ] T2.1 D3-1（F-01）：`_YYDecoder.container` 确定性键序（精确匹配优先 → UTF-8 字节序），Foundation 序列化序差异写入 `SWIFT-MODEL.md` 与 README。
- [ ] T2.2 D3-2（F-02）：`forType` 以模型规则为基底合成；重复注册叠加；`SWIFT-EXTERNAL-RULES.md` 更新优先级表。
- [ ] T2.3 D3-3（F-03B）：裸 Int 键字面量冲突确定性（三处同病同修：`YYModelDictionary`/`YYModelScalarDecoding`/`YYModelNativeBridge` 保留字面量冲突判定）；排除 F-03A 误报，不增加无谓的 Data 字典键重读。
- [ ] T2.4 D3-4（F-08）：默认 loss report + lossy 先于 fallback + 取容器入 catch。
- [ ] T2.5 D3-5（F-09）：移除 `"super"` 键读取，扁平继承语义文档化。
- [ ] T2.6 D3-6（F-10）：判别符严格 String + 可行动错误。
- [ ] T2.7 D3-7/D3-8（P-05/P-08）：`.microsecondsSince1970` 新策略 + 文档 + coercion 诊断开关。
- [ ] T2.8 D3-9（K-01 ~ K-05 NativeBridge 组合映射）：对齐主代理 E2E，确保物理祖先路径、Set 值去重纠偏、模型 codingPath 完整贯穿、泛型递归游标及结构路径映射稳定，支持原样本已修与扩展场景后续验收。
- [ ] T2.9 `UPGRADE-COMPAT-GUIDE-20261004.md` 增补「旧→新行为对照表」（本阶段全部行为变化）；CHANGELOG 条目。

### 交付物

框架文件改动 + 行为对照表 + 文档更新。

### 门禁与回滚

门禁：G0 + G1（D3 组探针转绿）+ G2（五入口一致性矩阵达到本阶段预期行）+ G6（公开 API 变化清单评审）。
回滚：每缺陷独立 commit；行为变化类（F-01/F-02/F-09）如现场反馈问题，单 revert 对应 commit。

---

## 5. Phase 3 — R-1 统一字段解析器

**目标**：按设计 §4 落地 `YYFieldResolver`，A/B/C/D 四管线复用，特性开关 `YYModelInternals.unifiedFieldResolution` 默认关闭合入。

### 任务

- [ ] T3.1 实现 `YYFieldResolver`（定位/存在性/null 语义/默认物化四接口），带单元测试。
- [ ] T3.2 `YYModelDecoder` 七个消费方法切换到 resolver（开关内新路径）。
- [ ] T3.3 错误传播改造（F-05）：形状无效 vs 策略抛错分离；诊断记录。
- [ ] T3.4 hook 快照 keyMap 反查（F-06）：`YYModelJSONInput.snapshot` 改造。
- [ ] T3.5 Presence/null 下沉 `YYModelDecode.value`（F-07）；lossy 对 null 不再记损失。
- [ ] T3.6 蛇形副本合并：删除 `yy_bridgeSnakeCase`。
- [ ] T3.7 开关开启的性能/A-B 对照测试（两个开关位各跑一次全量测试与 Benchmark）。
- [ ] T3.8 验收通过后默认置 true，CHANGELOG 公告；旧路径保留一个版本周期后单独 PR 删除。

### 交付物

`YYModelDecoder.swift`（主要）、`YYJSONDecoder.swift`、`YYModelJSONValue.swift`、`YYModelNativeBridge.swift` 改动 + 开关。

### 门禁与回滚

门禁：G0 + G1 + G2（五入口矩阵全绿）+ G4（开关两态性能均达标）。
回滚：开关置 false 即回到旧路径（运行时回滚，无需 revert）；代码级 revert 为独立 PR。

---

## 6. Phase 4 — R-2 数值收敛 + R-3 旧 OS 路由

**目标**：`YYModelJSONValue` 树成为唯一数值中转；旧系统恢复整数精确。开关 `YYModelInternals.unifiedNumericTree`。

### 任务

- [ ] T4.1 R-2.1 导出直出树：`YYModelEncoder` 值树输出模式；删除 5 处 JSONSerialization 往返（P-03 架构清理；主代理 consumer `NumericE2E.json` 实测当前环境已通过）。
- [ ] T4.2 R-2.2 桥消费树：`YYModelNativeBridge.swift:46` 改 `raw.encode()`（P-04 架构清理；主代理 consumer `NumericE2E.json` 实测当前环境已通过）。
- [ ] T4.3 R-2.3 Float 直解析（P-06）：树中保留字面量，优先 `Float(literalText)`，重点修复 `NumericE2E.json` 已确证的 Hook 路径 3 项 Float 探针失败（1 ULP 偏差）。
- [ ] T4.4 R-2.4 preserved-Double 旁路退役：与主代理 bridge-green 递归数值恢复工作树协同，全部读取点改树后删除挂载机制。
- [ ] T4.5 R-3.1 能力探测（进程缓存）+ DEBUG 首测打印。
- [ ] T4.6 R-3.2 降级路由：旧 Foundation 下 Data 入口预解析走 raw 管线（P-01 平台条件缺陷；当前 macOS 26.7 无法直接复现，需在旧 OS 模拟器或专用 CI 验证，禁止冒充旧系统验收）。
- [ ] T4.7 R-3.3 残留决策执行：按评审选定（默认 A：文档化浮点形式整数在旧 OS 的限制）。
- [ ] T4.8 开关开启全量验证（含真实旧 OS 模拟器矩阵）；验收后默认 true。

### 交付物

`YYModelEncoder/YYModelNativeBridge/YYModelJSONValue/YYModelDecoder/YYJSONDecoder` 改动 + 开关 + 文档。

### 门禁与回滚

门禁：G0 + G1 + G3（数值保真专项全绿）+ G4（两态性能）+ G5（旧 OS 模拟器清单，严禁无环境假验收）。
回滚：同 Phase 3，开关运行时回滚；R-3 降级路由单独开关 `legacyExactRouting` 可独立关闭。

---

## 7. Phase 5 — 发布与文档收口

- [ ] T5.1 版本号与 CHANGELOG 汇总（按缺陷 ID 列：问题→修复→行为变化）。
- [ ] T5.2 `UPGRADE-COMPAT-GUIDE` 终稿；`docs/README.md`「当前状态」表更新。
- [ ] T5.3 缺陷登记册状态列更新（全部 → 已修复/已验证关闭），附验证人。
- [ ] T5.4 发布（`publish_releases.sh` 流程，按仓库既有规范）。

门禁：G7（文档与签署齐全）。

---

## 8. 变更管理与协作

- **分支策略**：每阶段一个 `codex/remediation-phase<N>` 分支，基于 `master`；阶段内每缺陷独立 commit（信息格式 `fix(P-02): truncate decimals toward zero for negative values`）。
- **评审要求**：Phase 2 前置的 D3 选项签字由项目负责人+外部评审人双人确认；Phase 3/4 的开关默认值变更需二次评审。
- **角色建议**：实施工程师 1 名（Swift）、探针/验收工程师 1 名（可由实施者兼任但验收签署人必须独立）、外部专业评审（用户安排）。
- **风险登记**：
  | 风险 | 概率 | 缓解 |
  |---|---|---|
  | Phase 3 重构引入新回归 | 中 | 开关双态全量测试 + G2 矩阵 + 观察 PR 期 |
  | 性能回退超阈值 | 中 | G4 每阶段快照；resolver/树路径均为查表重构，无新序列化 |
  | D3 选项评审久拖 | 中高 | 默认推荐项先行准备探针，签字后即可动工 |
  | 旧 OS 模拟器环境缺失 | 低 | G5 提供两种替代（CI 多版本 Xcode / 真机抽检） |

- **进度跟踪**：以本节执行表及公开状态表为当前进度源；历史勾选框保留原处方，不作为当前完成状态。正式阶段签署只能由对应外部人员填写。
