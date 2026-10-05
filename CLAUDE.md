# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> 每条事实后的 `〔…〕` 是来源文件。版本号以 `YYModel.podspec` 为准，README 安装片段里的 `2.3.0` 已过时。

## 1. 概览

- **YYModel 2.3.1**：iOS/macOS 上的高性能 JSON ↔ Model 框架，MIT 协议。作者 ibireme（原作者）和 leeeeeeeefulong（本 fork 维护者）。仓库：https://github.com/leeeeeeeefulong/YYModel 〔YYModel.podspec〕
- **两条实现线并行**：〔README.md, Package.swift〕
  - `YYModel/`：维护中的 Objective-C 版（ARC、runtime 反射、`NSObject (YYModel)` 分类）。
  - `YYModelSwift/`：Swift 版，基于原生 `Codable`。模型就是普通 struct，不用协议、属性包装器、宏，也不用继承 NSObject（`YYModelCodable` 只是可选便利层）。
- **语言**：Swift 部分要求 Swift 5.9+ 工具链（`swift-tools-version:5.9`）。`swift_versions = ['5.0','6.0']` 指的是 CocoaPods 的**语言模式**，与 Xcode 版本无关；写成 `"5.9"` 会破坏客户端的版本选择。〔YYModel.podspec 注释, Package.swift〕
- **依赖**：没有第三方依赖。podspec 和 SPM 只链接 `Foundation` 与 `CoreFoundation`。另外，Swift 源码会 `import ObjectiveC`（`YYModelJSONValue.swift`），并在 `#if canImport` 条件下导入 `Combine` 和 `Network`（`YYModelPlatformConformances.swift`），给 `TopLevelDecoder/Encoder`（iOS 13+）和 `NetworkDecoder/Encoder`（iOS 26+）提供一致性实现。〔YYModel.podspec, Package.swift, YYModelSwift/*.swift〕
- **部署下限**：iOS 11.0 / macOS 10.13，SPM 另外声明 tvOS 11 / watchOS 4。这些是有意设定的分发政策，不是疏漏。〔Package.swift 注释, YYModel.podspec〕

## 2. 架构

### ObjC 与 Swift 的边界

```
               ┌─────────────── 分发 ───────────────┐
 CocoaPods  YYModel2 (或 YYModel) ── default: ObjC + Swift
              ├─ subspec ObjC  : YYModel/*.{h,m} + PrivacyInfo.xcprivacy bundle
              └─ subspec Swift : YYModelSwift/*.swift      (单 pod 时 import YYModel2 同时可见两者)
 SPM        product YYModel      → target YYModel      (path YYModel/, publicHeadersPath ".")
            product YYModelSwift → target YYModelSwift (path YYModelSwift/)
            testTarget YYJSONDecoderTests → 依赖上面两个 target（仅测试层混用）

  YYModel/ (ObjC)                    ║    YYModelSwift/ (Swift)
  ── 互不 import，不共享映射表 ──    ║    ── 不依赖 ObjC target ──
  modelCustomPropertyMapper 等 hook  ║    CodingKeys + 外部 YYJSONRules
```
〔YYModel.podspec, Package.swift, README.md「Mixed」节〕

- SPM target 不能混放 `.swift` 和 `.m`，所以两者必须是两个 target。〔README.md〕
- **ObjC 产品不能含任何 Swift 相关 API**。2.3.0 起已删除 `YYClassPropertyInfo.isSwiftDynamic`。要判断 runtime Dynamic 标记，改用 `(info.type & YYEncodingTypePropertyDynamic) != 0`。目前 `YYModel/` 下没有任何 "swift" 字样，新增代码要保持这一点。〔docs/OBJC-MIGRATION.md, README.md〕
- 两个 podspec 只差三处：`s.name`、`s.summary`，以及 ObjC 的 resource bundle 名（`YYModel` 对 `YYModel2`）。改其中一份时要同步另一份。CocoaPods trunk 上实际发布的是 `YYModel2`，因为原 `YYModel` pod 归 ibireme 所有。trunk 在 2026-12-02 之后只读。〔diff YYModel.podspec YYModel2.podspec, README.md〕

### Objective-C 引擎（`YYModel/`）

- `YYClassInfo.{h,m}`：runtime 反射层（ivar / method / property / class info），带全局缓存。`YYEncodingType` 是类型编码位掩码。缓存锁用 `os_unfair_lock`，替换了原来的 `dispatch_semaphore`（后者有优先级反转风险）。〔YYClassInfo.m:326-358〕
- `NSObject+YYModel.m`：`_YYModelPropertyMeta` / `_YYModelMeta` 是每个类的映射元数据缓存（同样用 `os_unfair_lock`，见 :747）。属性赋值通过类型化的 `objc_msgSend` typedef 完成。ISO 日期输出是串行化的（:208）。
- 配置 hook 通过 `respondsToSelector:` 识别，**不要求**模型声明 `<YYModel>`，`NSObject` 也不再自动遵循该协议。〔docs/OBJC-MIGRATION.md〕
- 默认只用最具体子类的 mapper / 容器泛型 hook，与原版一致。父子合并必须显式开启：`+modelMergesSuperclassConfiguration` 返回 YES。黑名单和白名单始终不合并。〔docs/OBJC-MIGRATION.md〕

### Swift 引擎（`YYModelSwift/`）

- 入口是 `YYJSONDecoder` / `YYJSONEncoder`，二者都是 `(mode, rules)` 值类型，按 `YYJSONMode` 分派：〔YYJSONDecoder.swift:89-135, YYJSONEncoder.swift:24-60, YYJSONRules.swift:9-17〕
  - `.native`：直接交给 Foundation 的 `JSONDecoder`/`JSONEncoder`。如果传入了**非空 rules，会抛错**，不会静默忽略。
  - `.compatible`：字段级容错和外部规则（别名 / KeyPath、默认值、required、hook、日期、多态）。
  - `.legacy`：无参构造时的默认模式，保留 2.x 的补零和自动日期语义。2.2.0 起不再做"先 native 失败再整模型重试"。
- 非 native 的解码路径：`YYJSONContext`（放在 `userInfo` 里）→ `YYModelDecodingBox<T>` → `YYModelDecode` / `YYModelDecoder`，字段解析由 `YYFieldResolver` 完成〔YYModelDecoder.swift〕。传入的若是已解析的 Foundation 对象或整数 token，则走 `YYModelJSONInput` 和 `_YYDecoder`〔YYJSONDecoder.swift:679〕。`YYJSONNumberParsingStrategy` 和 `YYModelCapability.foundationExactDecimal` 决定是否改用整数 token 来保住精度。
- 规则保存在 `YYJSONRules`：不可变，以 `ObjectIdentifier` 作键。只能注册在**模型类型**上，注册到标量或集合会抛错。`.forType(_:configure:)` 配置的是 `YYModelConfiguration<Model>`。〔YYJSONRules.swift:20-60, YYModelCodable.swift:42-79〕
- 编码分两条路：`YYModelEncoder` 走 Foundation 编码；`YYModelTreeEncoder` 直接导出 `YYModelJSONValue` 树（remediation 中的 R-2，`encodeJSONObject` 用的就是它）。〔YYJSONEncoder.swift, YYModelTreeEncoder.swift, Validation/remediation/STATUS.md〕
- 调用方自定义的 Foundation 标量策略由 `YYModelNativeBridge` 处理：只在该标量上走 Foundation，不重试它所属的整个模型。〔YYModelNativeBridge.swift:1-5〕

## 3. 公开 API 索引

**ObjC**（〔YYModel/*.h〕）
- `YYModel.h`：伞头文件，导出 `YYModelVersionNumber` 和 `YYModelVersionString`。
- `YYClassInfo.h`：`YYEncodingType`（NS_OPTIONS）。`YYClassIvarInfo` / `YYClassMethodInfo` / `YYClassPropertyInfo`（各自有 `-initWithIvar:` / `-initWithMethod:` / `-initWithProperty:`）。`YYClassInfo` 提供 `+classInfoWithClass:`、`+classInfoWithClassName:`、`-setNeedUpdate`、`-needUpdate`。
- `NSObject+YYModel.h`：
  - `@protocol YYModel`（hook 全部可选）：`+modelMergesSuperclassConfiguration`、`+modelCustomPropertyMapper`、`+modelContainerPropertyGenericClass`、`+modelCustomClassForDictionary:`、`+modelPropertyBlacklist`、`+modelPropertyWhitelist`、`-modelCustomWillTransformFromDictionary:`、`-modelCustomTransformFromDictionary:`、`+modelRequiresSuccessfulNestedTransforms`、`-modelCustomTransformToDictionary:`
  - `NSObject (YYModel)`：`+yy_modelWithJSON:`、`+yy_modelWithDictionary:`、`-yy_modelSetWithJSON:`、`-yy_modelSetWithDictionary:`、`-yy_modelToJSONObject`、`-yy_modelToJSONData`、`-yy_modelToJSONString`、`-yy_modelCopy`、`-yy_modelEncodeWithCoder:`、`-yy_modelInitWithCoder:`、`-yy_modelHash`、`-yy_modelIsEqual:`、`-yy_modelDescription`
  - `NSArray (YYModel)` `+yy_modelArrayWithClass:json:`；`NSDictionary (YYModel)` `+yy_modelDictionaryWithClass:json:`

**Swift**（〔YYModelSwift/*.swift〕中的 `public` 声明）
- `YYJSONRules.swift`：`YYJSONMode`、`YYJSONRules`（`forType`、`polymorphic(_:discriminator:variants:)`、`isEmpty`）、`YYJSONUserInfoValue`
- `YYJSONDecoder.swift`：`YYJSONDecoder`。属性与 `JSONDecoder` 对齐：日期 / 数据 / 键 / 非一致浮点策略、`userInfo`、`allowsJSON5`、`assumesTopLevelDictionary`，外加 `numberParsingStrategy`。方法有 `decode(_:from:)`（Data / String / Any）和 `decodeWithReport`（返回 `YYModelLossReport`）。另有 `YYJSONNumberParsingStrategy`。
- `YYJSONEncoder.swift`：`YYJSONEncoder`，方法 `encode` / `encodeJSONObject` / `encodeString`
- `YYJSONEntryPoints.swift`：工厂方法 `.native()`、`.compatible(rules:)`、`.legacy(rules:)`，解码器和编码器都有
- `YYModelWithConfiguration.swift`：`DecodableWithConfiguration` / `EncodableWithConfiguration` 重载（iOS 15+）
- `YYModelCodable.swift`：`YYModelCodable`、`YYModelKey`（`.key` / `.path` / `.alternatives` / `.aliases`）、`YYModelDateStrategy`、`YYJSONMissingStrategy`、`YYModelConfiguration<Model>`、`YYModelJSON`
- `YYModelKeyPath.swift`：`YYModelConfiguration` 上基于 KeyPath 的扩展，例如 `$0.map(\.id, from:)`
- `YYModelLossy.swift`：`YYModelLoss`、`YYModelLossReport`，以及 lossy 配置扩展
- `YYModelCoercionReport.swift`：`YYModelCoercionReport`（通过 `userInfo` 键注入）
- `YYModelPresence.swift`：`YYModelPresence<Value>`，用来区分字段缺失、null 和有值
- `YYModelPolymorphic.swift`：`YYModelPolymorphic`、`YYModelVariant<Root>`
- `YYModelNativeBridge.swift`：`YYModelCapability.foundationExactDecimal`
- `YYModelPlatformConformances.swift`：`TopLevelDecoder/Encoder`、`NetworkDecoder/Encoder` 一致性实现

完整契约与限制见 `docs/SWIFT-EXTERNAL-RULES.md`、`docs/SWIFT-MODEL.md`、`docs/UPGRADE-COMPAT-GUIDE-20261004.md`。

## 4. 构建与测试命令

```sh
# SPM：构建，以及 Swift + 混合回归测试（Tests/YYJSONDecoderTests，93 个测试）
swift build
swift test                       # CI 用的是 swift test -c release
swift test --filter YYJSONDecoderTests.YYModelLossyTests            # 跑单个测试类
swift test --filter YYJSONDecoderTests.YYModelLossyTests/<testName> # 跑单个测试方法

# ObjC XCTest（YYModelTests/，Framework/YYModel.xcodeproj，scheme YYModel，iOS framework）
xcodebuild test -project Framework/YYModel.xcodeproj -scheme YYModel \
  -destination 'platform=iOS Simulator,name=<设备名>' \
  [-only-testing:YYModelTests/YYTestModelPropertyMapper]

# 纯 ObjC 演示（直接用 clang 编译 YYModel/*.m，T1–T18；T16 需要联网访问 jsonplaceholder）
cd Demo && make        # 也可以 make build / make run / make clean

# 公开 API 端到端验收。--output 目录必须事先不存在；任一断言失败即非零退出
python3 Validation/remediation/run.py --output /tmp/yymodel-acceptance-<new>
python3 Validation/remediation/verify_platforms.py --acceptance-root /tmp/yymodel-acceptance-<new> --output /tmp/yymodel-platforms-<new>
python3 Validation/run_swift_model_data.py --source-root /tmp/yymodel-acceptance-<new>/source --output /tmp/yymodel-business-<new> --samples 1 --iterations 1
python3 Validation/remediation/run_performance.py --acceptance-root /tmp/yymodel-acceptance-<new> --output /tmp/yymodel-perf-<new>
python3 Validation/run_objc_contract.py --output /tmp/yy-objc-contract-mac   # 加 --simulator <booted-UUID> 跑 iOS
```
〔Package.swift, .github/workflows/remediation-e2e.yml, Demo/Makefile, Framework/…/YYModel.xcscheme, Validation/remediation/README.md, docs/OBJC-MIGRATION.md〕

- 有效的 CI 只有 `.github/workflows/remediation-e2e.yml`（macos-latest，依次运行上面前三条 Python 命令和 `swift test -c release`）。`.travis.yml` 是遗留配置（xcode8 / iPhone 7），已经失效。〔两文件〕
- `verify_platforms.py` 会对 Swift 5 和 Swift 6 语言模式做 `-strict-concurrency=complete -warnings-as-errors` 的 typecheck，并按 iOS11 / watchOS4 / tvOS11 / macOS10.13 的 target 编译。改 Swift 代码后，至少要通过这两种模式的严格编译。〔Validation/remediation/evidence/platforms-final/receipt.json commands〕
- `Validation/remediation/` 的 E2E 不新增单元测试，验收结果以冻结源码加 `receipt.json` 为准，不能从"编译通过"推断行为已验收。〔docs/OBJC-MIGRATION.md, Validation/remediation/README.md〕

## 5. 目录树（≤3 层）

```
YYModel/               ObjC 引擎（5 个文件）——不得出现 Swift 内容
YYModelSwift/          Swift Codable 引擎（19 个 .swift，扁平目录，podspec 用 *.swift 收录）
Tests/YYJSONDecoderTests/        SPM 测试（Swift 与混合用法）
  Fixtures/            s1–s10 场景 JSON 和 users.json，以 .copy 方式作为资源
YYModelTests/          ObjC XCTest：AutoTypeConvert、BlacklistWhitelist、ClassInfo、CopyingAndCoding、
                       CustomClass、CustomTransform、Description、ModelMapper、ModelToJSON、NestModel，另有 YYTestHelper
Framework/             YYModel.xcodeproj（iOS framework 与测试 target）、Info.plist
Demo/                  main.m 和 Makefile（纯 ObjC 演示；生成的 yymodel_test 已被 gitignore）
Benchmark/             ModelBenchmark Xcode 工程（CocoaPods，对比其他 JSON 库）
docs/                  迁移说明、交付报告、remediation 设计/计划/验收、缺陷登记（见第 6 节的 gitignore 说明）
Validation/            Python 驱动的公开 API E2E、契约、数值与性能脚本，回执、证据与研究结论（只建索引，不要通读）
Package.swift  YYModel.podspec  YYModel2.podspec  PrivacyInfo.xcprivacy  CHANGELOG.md  publish_releases.sh
```

Validation 关键入口（只记位置与用途）：`remediation/run.py`（主验收）、`remediation/STATUS.md`（最终结论）、`remediation/evidence/*/receipt.json` 与 `performance-final/gate.json`（冻结回执，每个目录下的 `command-*.log` 不需要阅读）、`research/20261004/`（ObjC 独立审查探针）、`receipts/*.json` / `*.csv`（历史版本交付回执）、`*FAILURE-MODES.md`（先行固定的失败判定）。`Validation/perf-isolation/` 和 `.build/` 是构建产物，已被 gitignore。

## 6. 约束与注意事项

**ObjC 与 Swift 的行为差异**（〔docs/OBJC-MIGRATION.md, Validation/research/20261004/OBJC-FAILURE-MODES.md, README.md〕）

| 方面 | ObjC (`YYModel/`) | Swift (`YYModelSwift/`) |
|---|---|---|
| 字段映射 | `modelCustomPropertyMapper`（支持 key path 和多键回退） | `CodingKeys` 加 `YYJSONRules` 的 mapper / KeyPath。两边不共享映射表 |
| 继承配置 | 默认只用子类的 hook；合并需 `modelMergesSuperclassConfiguration` | 规则按具体类型注册 |
| 数字字符串 | 宽松转换，与 Swift 严格数值 lexer 的契约**不同** | 严格；NaN、∞ 和 Float 溢出会被拒绝 |
| 缺失 / null | null 变 nil，缺失的标量变 0 | `.legacy` 补零值；`.compatible` 要求显式默认值；`.native` 等同 Foundation |
| 日期 | 自动秒/毫秒判断是启发式的；不支持或会误读负数毫秒 | 时间戳绝对值大于 1e11 视为毫秒（含负数）；做 YY 往返要设 `.secondsSince1970` |
| 嵌套转换失败 | 默认子模型失败不影响父模型；`modelRequiresSuccessfulNestedTransforms` 改为严格，但没有事务回滚 | 抛错；`compatible` 模式不再重试整个模型 |
| hash / equality | 只含 Pointer、CString 等不参与比较字段的模型按对象身份比较 | 不适用（值类型） |
| 安全归档 | 容器使用 allowlist；任意 id 或异构自定义容器不能视为安全归档 | 不适用 |

**弃用 API 与替代方案**（〔docs/OBJC-MIGRATION.md, 源码 grep〕）

| 弃用 / 移除 | 替代 | 位置 |
|---|---|---|
| `YYClassPropertyInfo.isSwiftDynamic`（2.2.0 弃用，2.3.0 删除） | `type & YYEncodingTypePropertyDynamic` | YYClassInfo.h |
| `dispatch_semaphore` 缓存锁（原版） | `os_unfair_lock`（iOS 10 / macOS 10.12） | YYClassInfo.m, NSObject+YYModel.m |
| `+[NSKeyedArchiver archivedDataWithRootObject:]`、`+[NSKeyedUnarchiver unarchiveObjectWithData:]`、`-initForWritingWithMutableData:` | `archivedDataWithRootObject:requiringSecureCoding:error:` / `unarchivedObjectOfClass:fromData:error:`（`Demo/main.m:248-254` 已改用） | 仍出现在 YYModelTests/YYTestCopyingAndCoding.m:158-179（测试代码，不在 Core 中） |
| PrivacyInfo 中虚构的 ObjCRuntime required-reason 类别 | 已清空 `NSPrivacyAccessedAPITypes`；新增 covered API 时要按 TN3183 重新核查 | PrivacyInfo.xcprivacy |

- Core 不依赖完整的归档便利 API，所以不能拿这一点论证可以降低 iOS 11 的部署下限〔docs/OBJC-MIGRATION.md〕。`Demo/Makefile` 用 `-Wno-deprecated-declarations` 压掉了弃用警告。仓库里**没有**针对 iOS 27 的适配证据，现有证据只覆盖到 iOS 26.5 SDK 下的编译。

**性能基线**（最终门禁数字，〔Validation/remediation/evidence/performance-final/gate.json〕，`passed: true`）
- YY 耗时与官方 JSONDecoder 的比值：native 模式 Tiny 0.98× / Mid 1.04× / Payload 1.01×；compatible 模式 Tiny 5.08× / Mid 3.80× / Payload 4.06×。rulesOverhead 1.09×（上限 1.10×）。
- 门禁规则是相对同工具链基线回退不超过 +10%。`longTermCompatible3xGoalMet: false`，即 compatible ≤3× 的长期目标**尚未达成**，不要对外宣称已达成。
- 验收汇总：公开 API E2E 555/555（`evidence/final/receipt.json`）；业务与数值 oracle 1,837/1,837；SPM release 108/108；ObjC 契约 49/49；平台下限检查只做了编译，`runtimeTested: false`。〔Validation/remediation/STATUS.md, platforms-final/receipt.json〕
- 测量环境（只在这里记一次）：Apple Silicon arm64，macOS 26.7，iOS/watchOS/tvOS/macOS 26.5 SDK。〔evidence receipts〕

**其他**
- 真实旧版 OS 上的运行验证（G5）和外部人员签署（G7）尚未完成，远端 CI 也还没实际跑过。不要据此宣称"所有平台没有问题"。〔Validation/remediation/STATUS.md〕
- `docs/` 下很多文件被 gitignore，属于本地评审产物，不会进入版本库：`docs/README.md`、`docs/review-*/`，以及 `CODE-REVIEW-{FOLLOWUP,IDIOMATIC,INDEPENDENT,LATEST,REREVIEW}-*`、`CODABLE-*`、`APPLE-OFFICIAL-MECHANISMS-*`、`OFFICIAL-PARITY-*`、`SWIFT-IDIOMATIC-DESIGN-REVIEW-*`。引用文档前先确认它已被跟踪，`git ls-files docs` 可查。〔.gitignore〕
- `publish_releases.sh` 会对远端仓库执行 `gh release create`，属于对外操作，未经用户明确要求不要运行。
- 研究和验收都不读取 PPLive 业务工程。〔Validation/research/20261004/OBJC-FAILURE-MODES.md〕
- 证据 JSON 里含有本机临时路径和环境指纹。引用时只取结论数字，不要转抄路径。
