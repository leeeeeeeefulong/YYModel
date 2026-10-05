# 验收计划（Acceptance Plan）— 2026-10-05

> **文档定位**：[REMEDIATION-IMPLEMENTATION-PLAN-20261005](REMEDIATION-IMPLEMENTATION-PLAN-20261005.md) 各阶段的验收标准与操作规程；
> 缺陷编号出处 [DEFECT-REGISTRY-20261005](DEFECT-REGISTRY-20261005.md)。
> **供外部专业评审人使用**：本文件自含全部判定标准，评审人无需回读审计报告即可执行验收。

---

> **执行证据更新**：当前修复进度以 [公开 E2E 状态表](../Validation/remediation/STATUS.md) 和冻结源码回执为准。
> 下文“位置/复现”保留审计基线；源码疑点不等同于已复现运行缺陷。正式外部签署及旧 OS 运行验收未完成。


## 本轮验收记录（自动证据，不代替人员签署）

A-01统一字段、A-02单一数值主干、A-03探针入库均已实施。冻结源码公开E2E **475/475**，包含原五类组合的12组两态、全部登记册用例、
数值边界与Float长尾、R-1字段、R-3路由/负零及R-2 Foundation编码协议对照。
失败基线、不可变源码、SHA-256、命令日志、观察值和独立复核均已留存于
[`Validation/remediation/evidence/`](../Validation/remediation/STATUS.md)。

G4最终Payload耗时0.12815ms、4.06×官方，比本轮初始耗时+4.04%，规则开销1.090×；本轮+10%回退门禁通过，≤3×目标未达。最终G0/G4/G6及业务oracle的同源码结果以[公开状态表](../Validation/remediation/STATUS.md)为准。
G5真实旧 OS runtime缺失、G7负责人及独立验收人尚未签署，不能将这些门禁标记通过。
新增CI尚未远端执行。原矩阵保留最初复现与待证说明，当前处置见登记册最终索引。

## 1. 验收总则

1. **独立性原则**：验收签署人不得是修复代码的作者（治 A-03「修复者=验证者」）。每阶段签署栏必须由独立人员填写。
2. **先失败后通过**：每个缺陷的探针必须能证明「修复前失败、修复后通过」。Phase 0 基线快照中预期失败清单即失败证据；本轮以公开 API E2E 的失败观察、源码哈希和修复后冻结回执呈现。控制用例或未复现疑点如实标注，不人为制造红灯。
3. **环境基线**：所有命令沿用 `docs/README.md`「复现命令（当前有效）」一节（本机 `swift` 需 `--disable-sandbox`；`xcodebuild` 需 `CODE_SIGNING_ALLOWED=NO`）。
4. **门禁通过定义**：门禁清单全部条目通过才视为阶段通过；任一条目失败即阶段失败，不得带病进入下一阶段（硬门禁：G0/G1/G4；G5 允许有条件放行但须签署风险声明）。

---

## 2. 门禁定义（G0–G7）

### G0 既有回归（所有阶段）
```sh
swift test -c release --disable-sandbox     # 既有回归
python3 Validation/remediation/run.py --output /tmp/yy-remediation-new # 公开 E2E 与冻结回执
for m in 5 6; do swiftc -typecheck -swift-version $m \
  -strict-concurrency=complete -warnings-as-errors YYModelSwift/*.swift; done
python3 Validation/run_objc_contract.py --output /tmp/yy-objc   # 49/49
# 声明下限编译四件套（docs/README.md「下限验证」命令原样执行）
```
**通过标准**：swift test 0 失败；两版严格编译 exit=0；ObjC 契约 49/49；iOS 11 / macOS 10.13 / tvOS 11 / watchOS 4 四下限 typecheck exit=0。

### G1 探针套件（Phase 0 起所有阶段）
- 所有 P/F/K/A 条目须关联公开 E2E、架构核验或明确的平台待证项。
- 失败场景修复后必须匹配期望；不使用预期失败包装把已知缺陷视为通过。
- `Validation/remediation/run.py` 独立编译冻结生产库与 consumer；必须检查 receipt 的 `passed` 及各项结果，程序 exit=0 不等于验收通过。

### G2 五入口一致性对照（Phase 2/3）
见 §4 矩阵。**通过标准**：矩阵中标记「必须一致」的行，管线 A/B/C/D 四入口结果完全相等；标记「允许差异（已文档化）」的行，差异与文档一致且方向固定。

### G3 数值保真专项（Phase 1/4）
见 §5 token 清单。**通过标准**：每行期望值精确匹配（`XCTAssertEqual` / 位级断言 `bitPattern`）。

### G4 性能不回退（Phase 1 起所有阶段）
```sh
python3 Validation/remediation/run_performance.py \
  --acceptance-root /tmp/yy-remediation-new --output /tmp/yy-remediation-perf-new
```
**通过标准**：同工具链修复前 `.compatible` Payload 实测 **3.81×、0.12317 ms**，允许 +10%（比值 ≤4.191×、绝对耗时 ≤0.135487 ms）；Tiny/Mid 同样对照原记录。官方 decoder 的绝对耗时也要记录，防止分母波动冒充回归或改善。`.native` 对照自身基线；小载荷原有固定开销不伪报为本轮回归。规则开销 ≤1.10×空规则。目标 ≤3.00×仍是长期目标。原文 3.50×/3.85×为旧工具链记录，不作为本轮实测门禁。R-1 中间版本已观察到 Payload 0.15099 ms 回退，必须修复后重测；见公开状态表。本轮未引入 R-1/R-2 双管线开关，不声称完成开关两态验收。

### G5 旧 OS 运行时验证（Phase 4）
见 §6 清单。环境：iOS 14 与 iOS 15 模拟器（覆盖 legacy JSONDecoder 两侧）；无环境时可采用 CI 多版本 Xcode 或真机抽检，须在签署栏注明方式。

### G6 公开 API 兼容审查（Phase 2/4）
- `swift-api-digester` 或人工 diff 公开接口；**通过标准**：无未在 `UPGRADE-COMPAT-GUIDE` 公告的公开 API 变更；新增 API 符合 `docs/README.md` 版本门槛矩阵（门控方式正确）。

### G7 文档与签署（Phase 5）
- CHANGELOG 按缺陷 ID 全覆盖（问题→修复→行为变化三要素齐全）；UPGRADE 指南含旧→新行为对照表；`docs/README.md`「当前状态」已更新；缺陷登记册全部条目标记关闭并附验证人。

---

## 3. 缺陷 → 探针 → 验收矩阵（G1/G3 的用例定义）

> 每行一个探针用例。`入口`：A=Data、B=对象、C=hook、D=custom 策略桥、E=native（E 仅标注处需要）。

### 3.1 数值精度组

| ID | 探针（输入 → 模型字段 → 期望） | 入口 | 门禁 | 状态与核验说明 |
|---|---|---|---|---|
| P-01 | `{"id": 9007199254740993}` → Int64 → 9007199254740993 | A（新 OS） | G3 | 现代 swift-foundation 本身精确（当前 macOS 26.7 无法复现旧缺陷） |
| P-01 | 同上（iOS 14/15 模拟器）→ 9007199254740993 | A | G5 | 必须使用真实旧 OS 模拟器执行，**严禁无旧环境冒充验收** |
| P-01 | `{"id": "9007199254740993"}`（字符串）→ Int64 → 精确 | A/B | G3 | 既有行为锁定 |
| P-01 | `{"id": 18446744073709551615}` → UInt64 → 精确 | A/B | G3 | 既有行为锁定 |
| P-02 | `{"delta": -1.9}` → Int → **-1** | A/B/C | G3 | **误报纠偏·锁定正确行为**：原源码已是向零截断，实测 `-1.9 -> -1` |
| P-02 | `{"delta": "-1.9"}` → Int → -1（既有行为锁定） | A/B | G3 | 既有行为锁定 |
| P-02 | `{"delta": -1.9}` → Int64/Int32 → -1；`-0.9` → 0；`1.9` → 1 | A | G3 | 向零截断正负数全集锁定 |
| P-03 | Decimal 字段 `1.000000000000000031251` → `yy_modelToJSONObject()` → 字面量保持 | — | G3 | 当前环境实测已过（NumericE2E），保留作为架构演进防腐 |
| P-04 | custom dateDecodingStrategy + Decimal 字段长 token → 精确 | D | G3 | 当前环境实测已过（NumericE2E），保留作为架构演进防腐 |
| P-05 | `.microsecondsSince1970` + `1699999999999999` → 正确日期；`.automatic` 行为快照锁定 | A | G3 | 已实施，DateAndCoercionE2E通过 |
| P-06 | `{"f": 1.0000000596046448}` → Float → 与 `Float("...")` 位级相等 | A/C | G3 | **已复现**：NumericE2E 证实 Hook 路径 3 项探针明确失败（1 ULP 偏差） |
| P-07 | Set 匹配：原始值 "abc" 不与 0 匹配 | D | G3 | **误报关闭**：当前代码库无此幽灵代码，条目关闭 |
| P-08 | 诊断开启：`{"flag":1}`→true 产生 coercion 记录；默认关闭无记录 | A | G1 | 已实施元数据报告，DateAndCoercionE2E通过（不打印日志） |
| 锁定 | `0.9999999999999999`/`-0.0`/`0.1` 的 Double 位级往返（历史 L1 回归锁） | A/C | G3 | 回归锁 |
| 锁定 | `9007199254740993.0`（浮点拼写）新 OS 精确（历史 F1/S1 锁） | A | G3 | 回归锁 |
| 锁定 | `-9223372036854775809` → Int64 抛 dataCorrupted（历史 S1 锁） | A/B | G3 | 回归锁 |

### 3.2 字段读取组

| ID | 探针 | 入口 | 门禁 | 状态与核验说明 |
|---|---|---|---|---|
| F-01 | `["user_name":"A","userName":"B"]` + snake 策略，重复 100 次 → raw 入口恒定胜者；Data 入口保持序列化序 | A/B | G1/G2 | 源码确认哈希序不确定 |
| F-02 | 模型 `id←uid` + 外部 `require(\.name)` → 两者同时生效；`{"uid":7}` → id=7 | A/B | G1 | **已复现**（`/tmp/f02_probe` 证实外部规则吞模型配置） |
| F-02 | 二次 forType 叠加：第一条不被第二条吞 | — | G1 | 源码确认覆盖逻辑 |
| F-03A| `{"data":{"snake_case":1}}` → `[String:Int]` → 键为 `"snake_case"` | A/B | G2 | **误报排除**：Foundation 原生不改写字典键，两入口一致保持原键名 |
| F-03B| `{"m":{"01":"a","1":"b"}}` → `[Int:String]` → 确定性结果 + strict 冲突策略生效 | A/B | G1 | 源码确认无序字典遍历覆盖 |
| F-04 | `fallback(\.x, to: 7)` + `{}` → `contains==true` 且 `nestedContainer(forKey:)`/`superDecoder(forKey:)` 可用 | A | G1 | 源码确认容器物化缺少分支 |
| F-05 | mapper 指向 `a.b`，JSON `{"a": 5}`（a 为标量）→ 报路径形状错误；custom 策略抛错时错误上抛 | A/B | G1 | 源码确认 `try?` 吞噬错误 |
| F-06 | `{"user_name":1,"userName":2}` → 模型值与 willTransform/didTransform 看到的值一致 | A/C | G2 | 源码确认查找策略分歧 |
| F-07 | `[YYModelPresence<String>]` 含 null 元素 → 得 `.null` 元素，整组成功；lossy 不记损失 | A/B | G1 | **已复现**（`/tmp/f07_probe` 证实遇到 null 抛 valueNotFound 崩溃） |
| F-07 | `[String: YYModelPresence<Int>]` 值 null → `.null`；单值容器 decode null → `.null` | A | G1 | 源码确认单值容器缺少 Presence 分支 |
| F-08 | `[Int]` 含 "x" → lossy 得其余元素 + 默认报告可读；lossy+fallback 同字段 → 逐元素跳过胜出；值类型整体错误 → 走损失记录 | A | G1 | 源码确认优先级及容器获取外置缺陷 |
| F-09 | 模型含业务字段 `super` → raw 入口正常读到；类层级扁平继承用例不回归 | A/B | G1/G2 | 源码确认 `"super"` 键特判劫持 |
| F-10 | `{"type":1}` → 两入口同错同文案；`{"type":null}` → 可行动错误 | A/B | G2 | 源码确认歧义报错 |
| F-11a| 整数快路径越界错误（UInt64 字段值 -1）→ codingPath 指向字段 | A | G1 | 待证/防御修补（因 `try?` 失败后会回退完整路径） |
| F-11b| 零填充下 `decodeNil` 与 `decode` 对 presence 结论一致（absent） | A | G1 | 源码确认两端返回矛盾 |
| F-11c| 嵌套容器内触发键冲突 → 导出抛错（不再静默丢字段） | — | G1 | 修复前公开 E2E 已拒绝冲突；原推断未复现 |
| F-11d| hook 内修改入参字典 → 调用方原字典不变（DEBUG 断言） | B/C | G1 | 已复现可变 NSArray 子树污染；顶层 Swift COW 控制安全 |
| F-11e| 并发解码两个不同 date 字典 → 无串扰（诊断线程 sanitizer 或 100 次压测） | A/B | G1 | 修复前公开并发控制已过；按维护性收敛验收 |
| F-11f| `allKeys` 只含属性名；物理别名不出现 | A | G1 | 源码确认混入物理键 |

### 3.3 NativeBridge 组合映射组（K-01 ~ K-05，对齐主代理 E2E）

> **证据出处**：对齐 `/tmp/yymodel-remediation-*-baseline-20261005/receipt.json`。
> 主代理在 bridge-green 回执已全部转绿（12/12 通过）。此处明确各用例属于「已修复原样本」还是「扩展已通过当前冻结验收」。

| 编号 | 场景名称 | 测试目标与期望 | 门禁 | 基线状态 | 验收状态说明 |
|---|---|---|---|---|---|
| **K-01** | `renamed-parent` | 重命名父键透传：预期保真 bits=...7409 | G1/G2 | 通过 | **已修复原样本**（锁定回归） |
| **K-01** | `snake-parent` | 蛇形父键透传：预期保真 bits=...7409 | G1/G2 | 通过 | **已修复原样本**（锁定回归） |
| **K-02** | `set-distinct` | Set 标量不同元素去重：预期 count=2 | G1/G3 | 通过 | **已修复原样本**（锁定回归） |
| **K-02** | `set-single` | Set 标量单一元素保真：预期 count=1 | G1/G3 | 通过 | **已修复原样本**（锁定回归） |
| **K-02** | `set-float-distinct` | Set 浮点数去重：预期 count=2 | G1/G3 | **失败**（hook下得1） | **已通过（bridge-green 及后续冻结回执）** |
| **K-03** | `model-array-path` | 数组内模型 codingPath 保留物理下标前缀 | G1/G2 | 通过 | **已修复原样本**（锁定回归） |
| **K-03** | `model-optional-path` | 可选嵌套模型 codingPath 保留物理前缀 | G1/G2 | 通过 | **已修复原样本**（锁定回归） |
| **K-03** | `dictionary-model-path` | 字典模型 codingPath 保留物理前缀 | G1/G2 | 通过 | **已修复原样本**（锁定回归） |
| **K-04** | `optional-nested-array` | 嵌套可选数组长数值保真（...7409） | G1/G3 | **失败**（hook下得...7408） | **已通过（bridge-green 及后续冻结回执）** |
| **K-04** | `unkeyed-nested-cursor` | unkeyed 容器嵌套游标推进长数值保真 | G1/G3 | **失败**（hook下得...7408） | **已通过（bridge-green 及后续冻结回执）** |
| **K-05** | `path-collision` | 结构化路径 `/`、`#` 分隔符碰撞消解（...7409） | G1/G2 | 通过 | **已修复原样本**（锁定回归） |
| **K-04** | `int-dictionary` | 裸 Int 字典长数值保真（...7409） | G1/G2 | **失败**（hook下得...7408） | **已通过（bridge-green 及后续冻结回执）** |

---

---

## 4. G2 五入口一致性矩阵

**载荷集**（每行同一样本经 A/B/C/D 四入口解码同一模型，结果必须相等，标注除外）：

| # | 载荷 | 一致性要求 |
|---|---|---|
| 1 | `{"user_name":"A","userName":"B"}`（snake 策略） | 必须确定（允许 A↔B 差异，但方向固定且已文档化：Data=序列化序，raw=按 D3-1 选定规则） |
| 2 | `{"value": -1.9}` → Int | 必须一致（-1） |
| 3 | `{"data":{"snake_case":1}}` → `[String:Int]` | 必须一致（键不转换，Phase 2 后） |
| 4 | `{"value":null}` vs `{}`（三态字段） | 必须一致（null ≠ absent） |
| 5 | Decimal 字段长 token | 必须一致（树收敛后） |
| 6 | `{"type":"a", ...}` 多态判别 | 必须一致（错误也须同型同文案） |
| 7 | 类层级 + superDecoder | 允许差异（已文档化：raw=扁平继承，A/D=Foundation） |
| 8 | 纯 native（E）与 A | 允许差异（E 无规则引擎，单列对照防混淆） |

---

## 5. G3 数值保真 token 清单（位级断言库）

| token | 目标类型 | 期望 |
|---|---|---|
| `9007199254740993` | Int64 | 9007199254740993 |
| `18446744073709551615` | UInt64 | UInt64.max |
| `-9223372036854775808` | Int64 | Int64.min |
| `-9223372036854775809` | Int64 | 抛 dataCorrupted |
| `9007199254740993.0` | Int64 | 9007199254740993（新 OS；旧 OS 按 R-3 残留决策） |
| `0.123456789012345678` | Decimal / Double | Decimal 精确；Double 位级 = 直接解析 |
| `1.000000000000000111022302462515654042363166809082031251` | Double | 位级 = 直接解析（历史 REREVIEW 用例） |
| `0.9999999999999999`、`-0.0`、`0.1`、`1e18`、`1e-129` | Double | 位级 = 直接解析（含符号位） |
| `1.000000000000000031251` | Decimal（hook/导出往返） | 字面量保持 |
| `1699999999999999` | Date（µs 策略 / `.automatic` 快照） | µs 策略正确；automatic 行为锁定 |

---

## 6. G5 旧 OS 手工验收清单（Phase 4）

环境：iOS 14.x 与 iOS 15.x 模拟器各一台（新旧 Foundation 分界两侧）；Xcode 对应旧版或 CI。

1. [ ] 能力探测日志：记录 `YYModelCapability.foundationExactDecimal` 的实际结果，不预设平台结果；默认生产库不打印日志。
2. [ ] G3 表前 6 行在新 OS 命令 `xcodebuild test`（`CODE_SIGNING_ALLOWED=NO`）全绿（Int64/UInt64/Int64.min/越界/浮点拼写按决策）。
3. [ ] hook 路径 `willTransform` 收到的 `9007199254740993` 精确（历史 F1 场景）。
4. [ ] `swift test` 主套件在旧 OS 目标编译运行通过（或声明不可行并附理由，签署风险声明）。
5. [ ] 逐 decoder 设置 `.numberParsingStrategy = .foundation` 时行为 = Foundation 现状；`.integerTokens` 强制降级分支以作对照（旧 OS 精度损失可接受地存在且已文档化）。
6. [ ] 结果记录：每项附模拟器系统版本、Xcode 版本、截图/日志。

---

## 7. 性能验收规程（G4）

1. 保留修复前同工具链基线及完整 benchmark 输入；本轮见 `Validation/remediation/evidence/perf-baseline.log`。
2. 每阶段结束对接受的冻结源码跑 `run_performance.py`；CPU 并行任务结束后复核，禁止择优隐藏失败。
3. 记录四组数：`.native`、`.compatible` 空规则、带规则、`.legacy`。
4. 判定：相对基线回退 >10% → 阶段失败，定位回归 commit（git bisect + 单用例 Profile）。
5. Phase 4 后额外记录（非门禁）：数值链短路后的 `.compatible` 变化，写入 README「当前状态」。

---

## 8. 签署与发布标准

### 阶段签署模板（每阶段一张，追加于本文件附录）

```
阶段：Phase <N>
验收人（独立于修复作者）：________  日期：________
门禁核验：G0 ☐  G1 ☐  G2 ☐  G3 ☐  G4 ☐  G5 ☐  G6 ☐
预期失败清单变化：新增 ___ 条 / 转绿 ___ 条 / 残留 ___ 条（对应缺陷 ID：___）
行为变化确认：已公告 ☐  已写入 UPGRADE 指南 ☐
结论：通过 ☐   有条件通过（风险声明见下）☐   驳回 ☐
备注：________
```

### 发布标准（Phase 5 → 版本发布）

1. Phase 1–4 全部签署「通过」（G5 可有条件通过但须双签）。
2. 缺陷登记册各项（P-01~08、F-01~11、K-01~05、A-01~03）按规程全部处理完毕：`已修复+探针转绿`、`已确认误报/幽灵代码关闭` 或 `已文档化决策`（仅 P-05/P-08 与 R-3 残留允许）。
3. CHANGELOG 三要素覆盖全部已修复 ID；版本号按仓库语义化规范递增。
4. `docs/README.md`「当前状态」「已知未完成项」同步更新；探针计数与 CI 一致。
5. 最终验收人（用户指定的外部专业人员）在 Phase 5 签署栏签字。

---

## 附录 A：D3 契约选项评审签字表（Phase 2 前置）

> [!NOTE]
> **授权与签署状态声明**：用户已明确授权按本文档推荐的技术路线与设计决策推进全部修复工作；推荐契约方案已完成技术可行性评估。但产品级最终正式签署仍未完成（待外部专业评审人与项目负责人正式签字），故本表保持待签署状态，不替用户或外部评审人代签。

| 设计项 | 推荐选项 | 选定 | 评审人 | 日期 |
|---|---|---|---|---|
| D3-1 冲突规则 | A 确定性（精确匹配→字节序） | ☐A ☐B | （待签） | （待签） |
| D3-2 规则合成 | A 基底合成 | ☐A ☐B | （待签） | （待签） |
| D3-3a 数据键策略 | A1 永不转换 | ☐A1 ☐A2 | （待签） | （待签） |
| D3-3b Int 键冲突 | 确定性+strict 可选抛错 | ☐接受 ☐修改 | （待签） | （待签） |
| D3-4 lossy 优先级 | lossy 先于 fallback | ☐接受 ☐修改 | （待签） | （待签） |
| D3-5 super 语义 | A 移除劫持保留扁平 | ☐A ☐B | （待签） | （待签） |
| D3-6 判别符 | 严格 String | ☐接受 ☐修改 | （待签） | （待签） |
| D3-7 时间戳 | 行为不变+µs 策略 | ☐接受 ☐修改 | （待签） | （待签） |
| D3-8 coercion 诊断 | 开关默认关 | ☐接受 ☐修改 | （待签） | （待签） |
| D3-9 组合映射 | 统一按物理祖先、Set 规范、codingPath 规范对齐 | ☐接受 ☐修改 | （待签） | （待签） |
| R-3.3 旧 OS 浮点整数 | A 文档化限制 | ☐A ☐B ☐C | （待签） | （待签） |

## 附录 B：Phase 0 基线快照（合入时填写）

| 项 | 值 |
|---|---|
| swift test 初始结果 | 93 通过 / 0 失败 |
| 初始公开 E2E | 九组 7 通过 / 2 失败；扩展 12 组 8 通过 / 4 失败，见状态表 |
| 性能基线 Payload | native 1.03× / compatible 3.81× |
