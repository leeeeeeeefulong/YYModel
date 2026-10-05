> ⚠️ **本报告已过时（2026-10-05 标注）**
> 审核对象是 **2.2.0 (`3fe64ec`)**。其中 **F1（`isSwiftDynamic`）与 F5（`Bridge/` 草稿）
> 已在 2.3.0 修复**，其余结论也可能已被后续版本取代。
> **当前有效的审核报告是 [CODE-REVIEW-IDIOMATIC-20261005-WORKTREE](CODE-REVIEW-IDIOMATIC-20261005-WORKTREE.md)**；
> 当前状态见 [docs/README.md](README.md)。本文件仅作历史记录保留。

# YYModel 双版本独立复核报告

复核日期：2026-10-05
复核对象：`master` @ `3fe64ec`（= tag `2.2.0`，工作区干净）
原版对照：ibireme `c7df27538c043e5f54f5b6605958544bb529892f`
本机工具链：Xcode 26.6 / Swift 6.3.3 / iOS 26.5 SDK（**无 iOS 27 SDK 与模拟器**）
复核方式：源码独立复算 + 上游逐行对照 + 本地实跑门禁（不采信文档自述）

---

## 0. 结论摘要

| 复核项 | 结论 |
|---|---|
| ObjC 与 Swift 是否彻底分离 | **基本达成**，残留 1 个 Swift 相关公开符号（F1） |
| ObjC 业务/API 是否缺失 | **无缺失**；公开 API 零删除，上游测试断言零修改 |
| ObjC 是否存在废弃 API | 库自身**无**；构建配置有 1 处平台枚举弃用（F4） |
| ObjC 与原始 fork 一致性 | **达成**（上游测试 27/27 原样通过；契约 43/43） |
| Swift 是否可行 | **可行**，实跑 62/62 + 16/16 全绿 |
| Swift 是否足够便利 | **够用但有摩擦**，见 §4 |

**总判定：本轮实现未偏移业务，无功能缺失。** 发现 7 项问题，其中 2 项为中等（F1 需求张力、F2 文档与实现漂移），5 项为低/提示级。**无 P0 阻断项。**

---

## 1. 复核方法与证据链

所有结论均由本地实跑复现，不依赖文档自述：

| 门禁 | 命令 | 实测结果 |
|---|---|---|
| SPM 构建 | `swift build --disable-sandbox` | **成功**（2.55s），仅 2 条 `.v11` 平台弃用警告 |
| Swift 单测 | `swift test` | **16 passed / 0 failed** |
| Swift 外部规则 E2E | `python3 Validation/run_external_rules.py` | **62 / 62 passed** |
| ObjC 公开契约 E2E | `python3 Validation/run_objc_contract.py` | **43 / 43 passed** |
| 上游 XCTest 套件 | `xcodebuild test -scheme YYModel` | **27 / 27 passed，TEST SUCCEEDED** |
| ObjC 严格编译 | `clang -Wall -Wextra -Werror` | 仅 1 处继承自上游的 `-Wsign-compare` |
| Swift 严格编译 | `-warnings-as-errors -strict-concurrency=complete`（Swift 5 / 6 两种语言模式） | **两种模式均 0 警告** |

> 说明：`swift build` 在沙箱内会因 SwiftPM 自身的 `sandbox-exec` 被拦截而报 "Invalid manifest"，属环境限制而非代码缺陷；加 `--disable-sandbox` 后正常。XCTest 需要 `CODE_SIGNING_ALLOWED=NO` 绕过开发者签名。

---

## 2. 两条产品线的目标、边界与一致性约束（要求 6）

### 2.1 ObjC（`YYModel` 产品 / `YYModel2/ObjC` subspec）

**目标**：在 ibireme 原版之上，仅做"被废弃 API 的适配与更新"，不重写、不改变既有调用方式。

**边界**
- 不引入任何 Swift 符号、协议、宏或属性包装器（`F1` 为唯一例外）。
- 保持全部原有入口：`yy_modelWithJSON:` / `yy_modelWithDictionary:` / `yy_modelToJSONObject` / `yy_modelCopy` / `yy_modelHash` / `yy_modelIsEqual:` / `yy_modelEncodeWithCoder:` 等。
- 分发下限保持 iOS 11.0 / macOS 10.13（分发政策，非技术下限）。

**一致性约束（对原版）**
1. 公开方法签名不得删除或改语义 —— **已满足**。
2. 默认配置契约（mapper / generic 只取最具体有效 hook）必须与原版一致 —— **已满足**。
3. 上游测试断言不得修改 —— **已满足**（`YYModelTests/`、`Benchmark/` 与上游逐字节相同）。
4. 新增能力必须是显式 opt-in —— **已满足**（`modelMergesSuperclassConfiguration`、`modelRequiresSuccessfulNestedTransforms` 默认 NO）。

### 2.2 Swift（`YYModelSwift` 产品 / `YYModel2/Swift` subspec）

**目标**：不做 ObjC 直译；基于 Swift 原生 `Codable`，把 YYModel 的"映射 + 容错 + 导出"能力外置到解码器，模型保持普通 struct。

**边界**
- 不要求模型采纳任何 YY 协议 / 属性包装器 / 宏（`YYModelCodable` 为可选便利层）。
- 不通过 Swift 私有内存布局写属性（明确拒绝 HandyJSON 路线）。
- 不维护 Foundation 私有 JSON 解析器分支，Data 扫描交给 Foundation。
- 不自动探测属性初始化表达式（`var age = 18` ≠ 缺失默认值）。
- 不伪装 OC 对象身份 / 任意 KVC / 安全归档语义。

**一致性约束（对 ObjC 能力面）**
1. 同一模型可配不同规则集，无进程级业务 schema 缓存 —— **已满足**（`YYJSONRules` 为不可变值类型快照）。
2. 别名按声明顺序取首个存在键、显式 null 阻断后续别名 —— **已满足**。
3. 大整数不经 Double 中转 —— **已满足**（走 `Decimal` / 精确 `NumericText` 词法）。
4. 坏数组元素不静默丢弃、required 不因"容错"被当作有效业务数据 —— **已满足**。
5. 编解码对称（同 mode + 同 rules）—— **已满足**。

---

## 3. 逐条对照原始要求

### 要求 1：ObjC 完全移除 Swift 内容，与 Swift 彻底分离

**结论：基本达成，1 处残留。**

- `YYModel/` 目录内**无任何 `.swift` 文件**，构建清单（`Package.swift` target `YYModel` path=`YYModel`；podspec `YYModel/*.{h,m}`）也不含 Swift。
- `Package.swift` 定义两个**独立 library product**（`YYModel` / `YYModelSwift`），podspec 定义两个**独立 subspec**（`ObjC` / `Swift`）。ObjC subspec 的 `source_files` 只含 `YYModel/*.{h,m}`，**对 Swift 无依赖**。分离在构建层是真实的。
- 残留：`YYClassInfo.h` 仍暴露 `isSwiftDynamic` —— 见 **F1**。

### 要求 2：ObjC 实现业务/性能/API 无废弃项，低侵入、便利

- **API 零删除**：把上游与本版的公开声明集合做机器比对，差异仅为**参数名改写**（`dic`→`dictionary`、`aDecoder`→`aCoder`）与**新增 2 个 opt-in hook**。无方法移除、无返回值变更。
- **无废弃 API 调用**：库源码未使用 `archivedDataWithRootObject:` / `unarchiveObjectWithData:` / `NSInvocation` / `OSAtomic` 等。安全归档走 `NSSecureCoding` 允许类路径。
- **低侵入**：调用方式与原版完全一致（`[User yy_modelWithJSON:json]` 等），无需改造既有模型；新增能力全部默认关闭。
- **性能**：本次未重跑 OC 配对基准（交付回执记录 current/original 轮比率中位 0.98–1.02，无稳定退化）。本次仅确认严格编译干净。

### 要求 3：与原始 fork 代码一致，不破坏既有行为

**结论：达成。**

- `YYModelTests/`、`Benchmark/` 相对上游 **diff 为空**（零修改）。
- 全仓 diff 相对上游为 **1702 insertions / 0 deletions**（新增文件，无既有内容删除）。
- 上游 XCTest **27/27 原样通过**。
- 需注意的**唯一行为契约变更**：fork 早期版本曾让子类 mapper/generic **自动合并父类**；本版恢复为原版"子类覆盖"语义。这对**依赖 fork 合并行为的既有用户是破坏性变更**，但：① 它才是与原版一致的行为；② 提供 `modelMergesSuperclassConfiguration` 显式回退；③ 已在 `OBJC-MIGRATION.md` 记录迁移方式。**判定为合理且已充分披露。**

### 要求 4：纯 Swift 版本（非直译、原生 Codable、灵活配置、低侵入）

**结论：方向正确，可行性已实证，便利性有摩擦点。**

- **非直译**：实现基于 `Decoder` / `KeyedDecodingContainerProtocol` 协议族，规则键用 `CodingKey.stringValue`，不存在"用反射模拟 OC Runtime"的痕迹。
- **原生 Codable**：`YYModelDecodingBox<T>` 包裹普通 `Decodable`；`.native` 模式直接转发 Foundation。模型侧零改造。
- **灵活配置**：mapper（别名/点路径/字面点号键）、required、defaultValues、黑白名单、逐字段日期、typed transform/validate、will/didTransform、transformTo、多态注册 —— 覆盖 ObjC 对应能力。
- **低侵入**：规则注册在 decoder 侧，模型不实现任何 YY 协议。

---

## 4. Swift 便利性评估（用户重点关切）

**可行的部分（实测确认）**
- 模型零改动即可解析标准 JSON；复杂接口只需在**网络层集中注册一次规则**，同模型可在不同 API 用不同规则。
- 编码对称：同一 rules 直接用于 `YYJSONEncoder`，别名反向生成嵌套 JSON。
- 精确大整数（雪花 ID `9007199254740993`）、`UInt64.max`、非有限值拒绝均已验证。

**摩擦点（建议关注）**

| 摩擦点 | 说明 | 影响 |
|---|---|---|
| 规则键为字符串 | `$0.mapper = ["id": ...]` 拼错无编译期报错，仅运行时字段错位 | 中；文档已承认并建议对关键字段显式 `required` |
| **默认入口是慢路径** | `YYJSONDecoder()` 默认 `.legacy`，实测约为原生 **4.8 倍**耗时；文档虽有说明，但"零参数即最便利入口 = 最慢"反直觉 | 中；建议默认值或文档显著位置调整 |
| 双入口并存 | `YYJSONDecoder`（推荐）与 `YYModelCodable` 便利层并存，后者易被误当主入口 | 低；已在文档标注"可选便利" |
| 日期单位需声明 | 秒/毫秒自动启发式（`abs > 1e11`）在歧义区间不可靠 | 低；文档已要求业务显式声明 |

---

## 5. 发现清单

### F1 — `isSwiftDynamic`：ObjC 公开 API 中残留的 Swift 相关符号（中等）

- **事实**：`YYClassInfo.h:124` 暴露 `YYClassPropertyInfo.isSwiftDynamic`（deprecated，恒返回 NO）。经 `git grep` 全量核对，**该符号不存在于上游 ibireme 任何文件中**，由本 fork 提交 `7d4fb0a`（"modern iOS compatibility - v1.0.5"）引入。
- **现状**：库内部**从不消费**该属性，仅由验证脚本与文档引用，属死 API。
- **冲突**：要求 1 明确"完全移除所有 Swift 相关内容"，而这是 ObjC 公开头文件中唯一与 Swift 直接相关的符号。
- **建议**：二选一并显式留痕 ——（a）直接删除（对本 fork 早期消费者是源码级破坏，需 minor 版本说明）；（b）保留但在 README/迁移文档中明确标注"这是相对上游的**额外**符号，属已接受的兼容例外"，避免读者误以为它来自原版。
- **备注**：替代能力 `YYEncodingTypePropertyDynamic` **确为上游原有**（`@dynamic` 标记），可安全承接原用途。

### F2 — README 对当前实现的行为与性能描述已过期（中等）

- **事实 1**：`README.md:132` 称 *"YYJSONDecoder still tries native JSONDecoder first, then its tolerant decoder after failure."* 经核，**该策略已不存在**。tag `2.1.9` 的 decoder 含 `try? Self.fastDecoder().decode(type, from: data)` 原生优先快路径；当前 master 的 `.legacy` 直接走字段适配路径（`YYModelDecodingBox`），无原生优先尝试。
- **事实 2**：README 主性能表（Native `0.882ms` vs `YYJSONDecoder 0.917ms`，≈1.04×）是 **2.1.9 架构**的数据。本次 release 模式实测 `users.json`：原生 `0.123ms` vs `YYJSONDecoder()` `0.586ms`，**≈4.8×**。
- **旁证**：较新的 `DELIVERY-EXTERNAL-RULES-20261004.md` 已如实写明"增强模式约慢五倍，不能宣传为原生性能"——即**交付文档诚实，但 README 未同步**。
- **影响**：仅读 README 的使用者会误判默认解码器的性能量级。
- **建议**：更新 README 第 132 行；在 2.1.9 性能表上方加注"该数据对应已被移除的 native-first 架构，当前默认入口性能见 2.2.0 交付报告"。

### F3 — `-Wsign-compare` 编译错误（低，继承自上游，非回归）

- `NSObject+YYModel.m:1299`：`modelMeta->_keyMappedCount >= CFDictionaryGetCount(...)`，`NSUInteger` vs `CFIndex` 符号比较。
- **与上游 `:1496` 完全一致**，属原版既有问题，**不是本次引入的回归**。
- 默认 Xcode 构建设置不会因此失败，但开启 `-Werror` 的工程会被阻断。
- **建议**：加显式 `(NSUInteger)` 转换即可，零行为影响。

### F4 — 构建配置的平台枚举已弃用（低）

- `Package.swift:15,17` 使用 `.iOS(.v11)` / `.tvOS(.v11)`，当前 SwiftPM 明确警告：*"'v11' is deprecated: iOS 12.0 is the oldest supported version"*。
- 不影响功能（仍可解析），但每次构建产生警告，与"无废弃项"的目标不符。
- **注意**：`podspec` 的 `deployment_target = '11.0'` 不受影响，两者可不同步处理。
- **建议**：确认是否仍需 iOS 11 分发下限；若保留，可在 Package.swift 注释说明这是**有意低于工具链建议下限**的分发政策。

### F5 — `Bridge/YYModelBridge.swift` 为无引用草稿（低，卫生问题）

- 该文件位于仓库根，**未被 `Package.swift` / 两个 podspec / Demo Makefile 中任何构建清单引用**。
- 在"ObjC/Swift 彻底分离"的要求下，一个游离的 Swift 桥接草稿放在发货树中容易造成误解。
- **建议**：删除或移入 `Validation/` / `research/`。

### F6 — Swift 默认入口是性能慢路径（提示）

- 文档已明示，此处仅作设计提示：把"最省事的零参数构造"与"最慢的执行路径"绑定，容易让使用者在不自知的情况下承担 5× 成本。
- **建议**：考虑让 `mode` 无默认值，强制调用方显式选择；或在构造器文档首行标注性能量级。

### F7 — 文档版本状态不一致（低）

- `DELIVERY-EXTERNAL-RULES-20261004.md:5` 与 `SWIFT-EXTERNAL-RULES.md:3` 仍称"master 的 **Unreleased** 源码"。
- 但 `HEAD == tag 2.2.0`，README 已声明 "Current release: 2.2.0"。
- **建议**：统一为 2.2.0，或明确标注"文档写于发布前"。

---

## 6. 关于"iOS 27"适配环境的边界（重要）

用户目标环境为 **iOS 27**，本机为 **iOS 26.5**。经核：

- 本机 iPhoneOS SDK 仅有 `iPhoneOS26.5.sdk`，**不存在 iOS 27 SDK**。
- 模拟器 runtime 最高为 **iOS 26.5**（另有 18.2 / 18.5）。

**因此：iOS 27 上的适配结论在当前机器上无法验证**，所有"已通过"的门禁都只覆盖 macOS 26.5 + iOS 26.5 模拟器。这不是实现缺陷，而是**验收覆盖缺口**，建议：
1. 明确定义 iOS 27 的验收方式（待 SDK 发布后补跑同一套 `Validation/` 门禁）；
2. 鉴于本库**不依赖任何 iOS 26/27 新增 API**（仅用 `os_unfair_lock`、`NSSecureCoding`、runtime 基础 API），升级风险主要来自**工具链与 SDK 行为变化**而非 API 废弃，风险可控。

---

## 7. 建议的处理优先级

| 优先级 | 项 | 动作 |
|---|---|---|
| 高 | F2 | 修正 README 的 native-first 描述与性能表适用范围（误导性最强） |
| 高 | F1 | 就 `isSwiftDynamic` 去留做一次明确决策并留痕 |
| 中 | F4 | 处理 `.v11` 弃用警告，或注明为有意策略 |
| 中 | F7 | 统一"Unreleased / 2.2.0"表述 |
| 低 | F3 | 补显式类型转换（顺带清理上游遗留） |
| 低 | F5 | 清理 `Bridge/` 草稿 |
| 低 | F6 | 评估是否强制显式选择 `mode` |

---

## 8. 复核边界声明

- 本次未重跑 OC 配对性能基准与物理设备测量；性能结论仅限本次实测的 `users.json` + release 模式。
- 未验证 iOS 27（无 SDK/模拟器）、未做持续并发吞吐与内存峰值测试。
- 文档中的历史回执（`Validation/receipts/`）未逐条复算，仅复核了当前源码可复现的门禁。
- 本报告不修改任何生产实现，仅记录复核结论。
