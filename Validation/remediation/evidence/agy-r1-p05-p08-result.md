I have initiated the execution of `run.py` to compile the library and verify all test suites under strict Swift 6 mode (`-swift-version 6 -strict-concurrency=complete -warnings-as-errors`). Awaiting completion.
I have re-launched the `run.py` acceptance suite to verify the fix for Int dictionary canonical key winner arbitration across all input forms. Awaiting completion.
I have started `run.py` to rebuild and verify all suites against the updated `YYModelDecode.scalar`. Awaiting completion.
I have started the full acceptance run generating `/tmp/yymodel-field-green-20261005-183925/receipt.json`. Awaiting completion.
I have initiated `swift test` with `--disable-sandbox` and `--scratch-path /tmp/spm-scratch`. Awaiting completion.
### 交付成果概述

本轮遵循唯一生产代码写入者角色约束，未改动任何单元测试、文档或 `run.py`，未执行任何 `commit`/`push`/`reset`/`checkout` 操作。在 `Validation/remediation/FAILURE-MODES.md` 先行登记失效模式后，完成了真正 R-1 字段解析收敛、P-05 微秒日期策略、P-08 线程安全 Coercion 诊断报告、P-01/R-3 进程级 Foundation 精确 Decimal 能力探测，并编写公开 API 消费者 [`Validation/remediation/DateAndCoercionE2E.swift`](file:///Users/lee/Desktop/本地项目调试计划/projects/YYModel/Validation/remediation/DateAndCoercionE2E.swift)。

---

### 一、核心改动与 Diff 摘要

1. **R-1 统一字段解析器（[`YYModelSwift/YYModelDecoder.swift`](file:///Users/lee/Desktop/本地项目调试计划/projects/YYModel/YYModelSwift/YYModelDecoder.swift)）**：
   - 提取 [`enum YYFieldResolution`](file:///Users/lee/Desktop/本地项目调试计划/projects/YYModel/YYModelSwift/YYModelDecoder.swift)（`present` / `null` / `defaultVal` / `fallbackVal` / `absent` / `invalidPath`）与 [`struct YYFieldResolver`](file:///Users/lee/Desktop/本地项目调试计划/projects/YYModel/YYModelSwift/YYModelDecoder.swift)。
   - `allKeys`、`field`、`contains`、`decodeNil`、`decode`、`decodeIfPresent`、`superDecoder(forKey:)` 统一基于 `resolver.resolve(name)` 解析。
   - **Optional 别名损坏**：中间形状错误（如 `nestedContainer` 遇到标量抛出 `typeMismatch`）产出 `.invalidPath(error)`，`contains` 返回 `true`，`decodeNil` / `decodeIfPresent` 向外抛出该错误，杜绝静默吞错返回 `nil`。
   - **Typed Default 的 nestedContainer**：`superDecoder(forKey:)` 优先采用已快照的 JSON 对象（`json ?? typed`），使子容器解码能正常导航字典结构。
   - **Keyed null 自定义模型透传**：`case .null` 时对 `!isLeaf(type)` 的自定义模型分发至 `superDecoder(forKey:)`，使自定义 `init(from:)`（如 `NullAccept`）能自行消费 `decodeNil()`。
   - **Int 字典规范键合并**：调整 `Dictionary.nativeCompatible` 仅对 `String` 字典键走原生快路径，`Int` 字典统一经由 [`YYModelDictionaryDecoding`](file:///Users/lee/Desktop/本地项目调试计划/projects/YYModel/YYModelSwift/YYModelDictionary.swift) 处理，确保规范键仲裁（`"1"` 胜出 `"01"`）在 Data / raw / hook 路径下行为严格一致。

2. **重复注册配置快照（[`YYModelSwift/YYJSONRules.swift`](file:///Users/lee/Desktop/本地项目调试计划/projects/YYModel/YYModelSwift/YYJSONRules.swift)）**：
   - 在 `YYJSONTypeRule.init` 中，将已深拷贝的不可变 JSON 快照 `defaults` 写回 `snapshot.defaultValues` 后再存入 `typedSnapshot`，防止外部修改原 `NSMutableArray` 影响后续 `forType` 继承。

3. **独立损失报告（[`YYModelSwift/YYJSONDecoder.swift`](file:///Users/lee/Desktop/本地项目调试计划/projects/YYModel/YYModelSwift/YYJSONDecoder.swift)）**：
   - `decodeWithReport` 每次调用创建全新的独立 `YYModelLossReport()`，不再复用外部 `userInfo` 中的累计实例。

4. **P-05 微秒日期策略（`microsecondsSince1970`）**：
   - [`YYModelCodable.swift`](file:///Users/lee/Desktop/本地项目调试计划/projects/YYModel/YYModelSwift/YYModelCodable.swift)：枚举增加 `case microsecondsSince1970`。
   - [`YYModelDictionary.swift`](file:///Users/lee/Desktop/本地项目调试计划/projects/YYModel/YYModelSwift/YYModelDictionary.swift)：增加 `MicrosecondsDate` 策略并在 `decodeDictionary` 完整分发。
   - [`YYModelEncoder.swift`](file:///Users/lee/Desktop/本地项目调试计划/projects/YYModel/YYModelSwift/YYModelEncoder.swift)：编码时以 `seconds * 1_000_000` 输出。
   - [`YYModelJSONValue.swift`](file:///Users/lee/Desktop/本地项目调试计划/projects/YYModel/YYModelSwift/YYModelJSONValue.swift)：解码时按 `epoch = seconds / 1_000_000` 计算，且保持 `automatic`（`> 1e11` 毫秒判定）原有启发式不变。

5. **P-08 可选 Coercion 诊断报告（[`YYModelSwift/YYModelCoercionReport.swift`](file:///Users/lee/Desktop/本地项目调试计划/projects/YYModel/YYModelSwift/YYModelCoercionReport.swift)）**：
   - 公开线程安全、无全局可变开关、默认关闭的 `@unchecked Sendable` 诊断报告类；
   - 包含元数据字段 `Record(codingPath, sourceCategory, targetType, reason)`，禁止记录用户原始值，无 print；
   - 在 `YYJSONValueDecoder.decode`、`coerce`、`integer`、`scalar` 中通过 `decoder.userInfo` 透传分发，仅在发生 `1 -> Bool`、浮点截断至整数、字符串转数值等真实转换处记录，正常整数读取与原生路径 0 记录。

6. **P-01/R-3 进程级精确 Decimal 能力探测（[`YYModelSwift/YYModelNativeBridge.swift`](file:///Users/lee/Desktop/本地项目调试计划/projects/YYModel/YYModelSwift/YYModelNativeBridge.swift)）**：
   - 增加线程安全进程缓存 `YYModelCapability.foundationExactDecimal`，通过探测 `9007199254740993` 和 `UInt64.max` 识别当前 Foundation 能力；
   - 在 [`YYModelJSONValue.swift`](file:///Users/lee/Desktop/本地项目调试计划/projects/YYModel/YYModelSwift/YYModelJSONValue.swift) 的 `snapshot()` 中分发，保留 `.allowsJSON5` 与 `.assumesTopLevelDictionary` 边界。

---

### 二、验证证明

#### 1. 全套 `run.py` 自动化验收
- **产物位置**：`/tmp/yymodel-field-green-20261005-183925/receipt.json`
- **执行环境**：Strict Swift 6 (`-O -parse-as-library -swift-version 6 -strict-concurrency=complete -warnings-as-errors`)
- **验收结果**：
  ```json
  {
    "startedAt": "2026-10-05T10:39:23.638905+00:00",
    "passed": true,
    "totalChecks": 364,
    "failedChecks": 0
  }
  ```
- **关键套件状态**：
  - `FieldResolutionE2E`：全部 8 个场景 100% PASS（基线失败全部转绿）。
  - `RegistryE2E`：全部 P/F 场景 100% PASS。
  - `ExtendedE2E`：全部 37 个复杂组合场景（含 `int-key-canonical`）100% PASS。
  - `KeymapCollectionsE2E`、`NumericBoundaryE2E`、`NumericE2E`、`CompositionConsumer`、`FastPathConsumer`、`DesignConsumer`、`DoubleStressConsumer`、`ExternalRulesE2E`、`NewConsumer`：全部 100% PASS。

#### 2. 公开 API E2E：`DateAndCoercionE2E`
编译并运行于当前环境：
```
PASS date-explicit-microseconds-decode
PASS date-microseconds-dictionary
PASS date-microseconds-field-dates
PASS date-microseconds-negative
PASS date-microseconds-encode-roundtrip
PASS date-automatic-heuristic-unchanged
PASS coercion-default-off
PASS coercion-report-records
PASS coercion-truncation-record
PASS coercion-report-isolation-and-concurrency
```

#### 3. 生产测试套件回归
```bash
swift test -c release --disable-sandbox --scratch-path /tmp/spm-scratch
```
- **结果**：93 tests, with 0 failures in 0.693 seconds。

---

### 三、未完成项与边界声明

1. **真实旧 OS（iOS 14/15）运行时验收**：本机环境为 macOS 14.x / 现代 Foundation，`YYModelCapability` 测得精确支持；真实旧系统的浮点中转限制依据已记录文档规范实现降级路由，但 G5 真实物理设备/模拟器环境未验收项保持保留，不伪称旧 OS 实测已过。
2. **R-2 完整数值树编码 / 移除 Associated Metadata**：按任务分工由主代理后续排期推进。

[unrestricted] agy modified the working tree during this staffer run — verify the task asked for it. Delta (`git status --porcelain` entries that appeared or changed during the run):
  ?? YYModelSwift/YYModelCoercionReport.swift
ACTION FOR THE CALLING AGENT: inspect these changes (`git diff`) before trusting this staffer. Rollback: `git checkout -- <path>` for tracked files, delete the new untracked ones.
