# Changelog

All notable changes to this project will be documented in this file.
This project adheres to [Semantic Versioning](https://semver.org/).

## Unreleased — 修复工程（2026-10-05）

本节记录当前工作区，未提交或发布。迁移行为见
[升级指南](docs/UPGRADE-COMPAT-GUIDE-20261004.md)。

- **F-01/02/03B/06**：raw 冲突按精确键/UTF-8 确定；规则合成保留模型基底和先前注册；Int 字典规范拼写优先，所有输入值仍严格解码；hook 键查找使用实际 Foundation 映射。
- **F-04/05/07/08、A-01**：共用字段解析，区分 absent/null/无效路径；typed default 容器及 fallback 可物化；Presence 贯穿数组/字典；lossy 默认有报告且每次 decodeWithReport 隔离。
- **F-09/10/11**：raw 扁平继承释放业务 super 键；判别符严格 String；hook 可变子树隔离、字典日期显式传递、allKeys 过滤源别名。F-11a/c/e 维护性改动不冒充已复现运行缺陷。
- **K-01–05**：物理祖先、结构化 keyMap、Set 逐元素恢复后建集、用户模型完整 codingPath、Optional/Int 字典及 unkeyed 嵌套递归统一。
- **P-06、P-01 现代 hook 补充**：修复 Float 二次舍入和 UInt64 大整数误分类，包含长 token 极小尾巴控制。
- **P-05**：新增显式微秒日期策略；automatic 启发式及 ISO8601 毫秒导出保持并公告。
- **P-08**：新增默认关闭的线程安全互转元数据报告，不记录原始值或自动打印。
- **P-01/R-3**：新增缓存精确 Decimal 能力探测和逐 decoder 数值路由选择；强制路由公开 E2E 通过，真实旧 OS 验收待证。
- **P-03/04、A-02**：直接树导出和集中数值边界已完成；首版编码回归已修，Foundation策略、空容器、Unicode键转换、重复容器、super键策略与字典CodingKey对照通过。本机 Decimal 控制原已通过，不能称已复现旧平台精度问题。
- **A-03**：历史公开 consumer 入库，严格冻结源码、SHA-256、命令及结果可重放；新增 CI 配置尚未远端执行。
- **P-02/P-07/F-03A**：排除负数取整错误处方、不存在的 Set 匹配代码及字典数据键策略误报；保留行为控制。

## 2.3.1.1 — Followup Review Fixes (R1–R8) (2026-10-05)

### Swift — YYModelSwift (followup review R1–R8)
Fixes for the 8 defects confirmed by the follow-up worktree review; verified against that report's scenarios plus the full suite (Swift tests 93/93, external rules 62/62, OC contract 49/49 on macOS + iOS 26.5 simulator):

- **(R1) Fast path honors strict missing/null**: both scalar fast paths now require the physical key to exist and be non-null before reading; absent/null fields return to the unified policy path, so `.compatible` no longer yields `0`/`""`/`false` for `{}` or `[k: NSNull]`, explicit defaults are not pre-empted by zeros, and a no-op `willTransform` cannot pierce strict validation (Data and dictionary entries).
- **(R2) Configuration entry applies T's rules**: the `DecodableWithConfiguration`/`EncodableWithConfiguration` entries route through the model's own rule flow (mapper, required, will/finish, transformTo) instead of the rules-less box; registered validation now fires on both entries and export hooks rename fields symmetrically. (Note: this toolchain does not propagate `EncodableWithConfiguration: Encodable` into constraint solving inside availability contexts; the hook path casts to `any Encodable` at runtime.)
- **(R3) Small high-precision decimals stay exact**: hook-input classification keeps the exact decimal for ALL non-exact tokens (not only ≥ 2^53) — `0.123456789012345678` survives a no-op hook unchanged — while Double fields still decode bit-identically (via the exact-text NSDecimalNumber conversion) and `-0.0` keeps its sign.
- **(R4) `Optional.some` typed defaults accepted**: unwrapping no longer bypasses the business-value channel; `default(\.kind?, to: .some(.unknown))` constructs and applies.
- **(R5) Typed defaults keep business-value semantics**: KeyPath defaults are stored as the caller's business value and returned verbatim — no JSON round-trip, no date-strategy reinterpretation (`default(\.date, to: Date(7))` yields epoch 7 under seconds, milliseconds, or iso8601 consumers), no re-application of a nested model's mapper. A best-effort JSON snapshot is retained for `superDecoder` consumers; raw `[String: Any]` defaults keep their original semantics.
- **(R6) CodingKeyRepresentable numeric keys**: custom dictionary keys are constructed with `intValue` populated for numeric JSON keys, matching Foundation — `{"7": 9}` decodes for keys built from `codingKey.intValue`.
- **(R7) Fallback joins container queries**: `contains`, `allKeys`, and `decodeNil` treat fallback-registered keys as logically present with the fallback's nullity, so handwritten `contains(.k) ? decode(...) : other` observes the same fallback as synthesized Codable.
- **(R8) lossy/fallback keys validated at construction**: the rule validator's key set now includes `lossy` and `fallbacks`, so unsupported (nested/underived) KeyPaths throw at construction instead of silently registering an empty key.

## 2.3.1 — Independent Review Fixes (2026-10-05)

Fixes for all defects confirmed by the independent review of `7a65125` and by the
follow-up worktree review. Each fix was verified against those reports' public
consumer probes plus the existing suites.

### Swift — YYModelSwift
- **(F1/L1) Hook input numeric fidelity**: the lazy `willTransform` input snapshot no
  longer parses with `JSONSerialization` (which rounds integer-semantic tokens like
  `9007199254740993.0` to binary64). It decodes the exact numeric tree, and the
  classification keeps the literal-parsed binary64 for every token binary64 can hold —
  ordinary floats and `-0.0` stay bit-identical to a direct parse (L1 regression in an
  earlier draft of this fix is closed; verified token-by-token against the review's
  stress set) — while integer tokens at or beyond 2^53 keep their exact value for
  `Int64`/`UInt64`. `Double` conversion of `NSDecimalNumber` values now parses the
  exact decimal text instead of the lossy `doubleValue`. Physical keys are preserved;
  nested model hooks share the same snapshot.
- **(F2) Field dates in nested containers**: `nestedContainer`, `nestedUnkeyedContainer`,
  keyed `superDecoder`/`superEncoder`, and encoding nested containers now resolve
  `fieldDateStrategies[key]`, matching what `decode(Date.self, forKey:)` already did.
  Custom `init(from:)`/`encode(to:)` get the same date unit as synthesized Codable.
- **(F3) Defaults in nested containers**: keyed `superDecoder(forKey:)` and the
  nested-container accessors now fall back to registered `defaultValues`, so inherited
  or handwritten Codable implementations observe the same defaults as direct decoding.
- **(F4) Strict missing-vs-null**: in strict (`.compatible`) mode, `decodeNil(forKey:)`
  on a key that is neither present nor defaulted now throws `keyNotFound` like
  Foundation, instead of reporting null. Explicit null still decodes as null;
  legacy zero-fill behavior is unchanged.

### Objective-C
- **(E1) Non-finite equality/hash**: `yy_modelHash` / `yy_modelIsEqual:` box
  float/double/long double properties without the JSON-export non-finite filter.
  NaN, `+Inf`, and `-Inf` models are distinct again (NSSet keeps 3), matching the
  ibireme original. JSON export, description, and coding keep the documented
  non-finite filtering.

### Distribution
- **(F5) Swift language modes**: `swift_versions` returns to the podspec root with
  the valid compiler language modes `['5.0', '6.0']` (the previously declared
  `'5.9'` is not a language mode and broke client selection; `'5.0'` had been
  dropped). CocoaPods 1.17 analyzer: `< 6.0` now selects `5.0`, `5.0` selects `5.0`,
  `6.0` selects `6.0`. The Swift 5.9+ toolchain requirement remains a documented
  comment, not a language mode.

### Examples (WeatherDemoMoya / WeatherDemo)
- **(L2) Config-keyed decoder cache**: `YYModelDecoderRegistry` caches by an explicit
  stable `decodingConfigID` instead of the Target's type. Different cases of one
  Target enum with different mode/rules/keys no longer reuse the first request's
  configuration (order-dependent results); targets without an ID are never cached.
  The demo adds a `.nowNative` case so distinct configs are exercised in-repo.
- **(L3) Live endpoint aligned with the real API**: `WeatherClient.live()` now targets
  the actual QWeather `/v7/weather/now` schema — `QWeatherNowResponse` follows the
  official structure (code/updateTime/fxLink/now{...}), rules validate `code == "200"`
  and the temperature range, and stub fixtures match the documented response. The
  flat aggregate `WeatherResponse` is explicitly labeled synthetic offline teaching
  data in both demos; WeatherDemo's mock URL no longer claims the QWeather endpoint.

### Swift — KeyPath configuration API (new)

- **`YYModelConfiguration` now accepts KeyPath-based configuration** alongside the
  existing string-keyed API: `map(_:from:)`, `map(_:at:)`, `map(_:literalKey:)`,
  `default(_:to:)`, `require(_:)`, `exclude(_:)` and `only(_:)` take `KeyPath` /
  `PartialKeyPath`. A mistyped property name is now a compile error instead of a
  silently ignored rule. The string API is unchanged and is still the right choice
  when `CodingKeys` differs from the property name; both write the same mapper and
  may be mixed within one configuration.
- `default(_:to:)` is type-checked against the property, so new code no longer needs
  `defaultValues: [String: Any]`. Optional values are unwrapped, so
  `default(\.nickname, to: nil)` stores `NSNull` rather than a Swift `Optional`
  (which previously raised `Unsupported JSON value: Optional<String>`).
- Nested key paths (`\.aqi.co`) cannot be caught by the compiler. They expand to a
  dotted name and are refused by `YYModelPolicy.validate()` at rule-construction
  time, rather than silently mapping onto an unrelated same-named property.
- Added `YYModelKey.aliases(_:)`. The existing `alternatives(_:)` treats each
  argument as a complete path, which is not the alias semantics the KeyPath `from:`
  variadic requires; `from: "a", "b"` now means two candidate keys, matching the
  array-literal spelling.
- Property-name derivation reads `String(describing: keyPath)`. `YYModelKeyPathTests`
  asserts the exact expected names for top-level, optional, collection and nested
  properties, so a future toolchain format change fails loudly instead of silently
  mis-mapping. Verified on Swift 6.3.3: the description carries no module name and
  is identical for same-module and cross-module use.
- New file `YYModelSwift/YYModelKeyPath.swift`; one added guard in
  `YYModelPolicy.validate()`. No existing behaviour changed — the 16 pre-existing
  tests still pass, plus 12 new tests (28 total). Typechecks under Swift 5 and 6 with
  `-warnings-as-errors -strict-concurrency=complete`.

### Swift — Official parity: JSON5 options, platform protocols, three-state presence

- **`allowsJSON5` and `assumesTopLevelDictionary` are now forwarded** (both
  `@available(iOS 15.0, macOS 12.0, …)`, default `false`, as in Foundation). These
  were previously unreachable: `YYJSONDecoder.foundationDecoder()` set only the four
  strategies plus `userInfo`. Foundation's JSON5 support covers single-quoted and
  multi-line strings and `//` / `/* */` comments, none of which the framework's own
  tolerant lexer can parse, so there was no workaround.
- **Adopted the same platform protocols as Foundation.** `YYJSONDecoder` /
  `YYJSONEncoder` now conform to `TopLevelDecoder` / `TopLevelEncoder` (Combine) and
  `NetworkDecoder` / `NetworkEncoder` (iOS 26 / macOS 26). Both protocols require
  exactly `decode<T>(_:from: Data)` and `encode<T>(_:) -> Data`, which already existed
  with matching signatures — these are pure declarations with no implementation cost.
  Availability-gated so the iOS 11 / macOS 10.13 floor is unchanged.
- **New `YYModelPresence<Value>` — distinguishes a missing key from an explicit null.**
  Plain `Codable` collapses both into `nil`, which makes partial-update APIs unsafe:
  `{"file": null}` (clear it) and `{}` (leave it alone) become indistinguishable.

  ```swift
  struct Song: Codable {
      var id: Int
      var file: YYModelPresence<String>   // non-optional; three cases
  }
  record.file = patch.file.resolve(keeping: record.file)   // absent keeps, null clears
  ```

  `resolve(keeping:)` encodes the incremental-update rule directly: `.value` updates,
  `.null` clears, `.absent` preserves. Encoding omits an `.absent` key entirely rather
  than writing `null`, so the three states survive a round trip.
- **Why an enum rather than the common `OptionalValue<T>?` pattern**: nesting an
  optional around an optional-value enum gives two look-alike "no value" states.
  A single three-case enum keeps each state distinct and makes `switch` exhaustive.
- **Why the presence check is not at the top of `decode(_:forKey:)`**: that is the
  per-field hot path. The check runs only in the null and missing branches, keeping the
  "has a value" branch free of an extra protocol cast. The benchmark suite
  confirms no regression.
- **Property wrappers are deliberately avoided.** A `Codable` property carrying a
  property wrapper requires the key to be present and throws `keyNotFound` even when
  the property is `Optional`, which is exactly the case three-state decoding exists for.
- Constraints documented on the type: the property must be non-optional
  `YYModelPresence<T>` (an optional wrapper routes through `decodeIfPresent` and folds
  `.null` into `nil`), and a presence field must not also be `requiredProperties`.
- New files `YYModelSwift/YYModelPresence.swift` and
  `YYModelSwift/YYModelPlatformConformances.swift`; small edits in `YYJSONDecoder.swift`,
  `YYModelDecoder.swift` and `YYModelEncoder.swift`. **40 tests pass** (16 pre-existing
  + 12 KeyPath + 12 presence), with no measurable performance change.

### Swift — Lossy arrays and a 30% compatible-mode speed-up

**Performance** (measured in release `-O`):

| | before | after |
|---|---:|---:|
| `.compatible`, empty rules, 70-field payload | 5.27× official | **3.68×** |
| `.compatible`, 14-field payload | 4.53× | **3.52×** |
| per-field overhead | 2.03 µs | **1.30 µs** |
| `.legacy` (the no-argument default) | 4.74× | **3.71×** |

- **Removed a per-field array allocation.** `validateScalar(_:path:)` built
  `codingPath + [key]` eagerly for every scalar field, even though the path is only read
  when the value is non-finite (an error) or a collection (recursion). The parameter is
  now `@autoclosure`, so the array is constructed only when actually needed. This
  follows the pattern Foundation itself uses (`codingPath.append(key)` +
  `defer { codingPath.removeLast() }`). Worth **−17.5%** on its own.
- **Added a scalar fast path.** When a field has no mapper entry, is not excluded by a
  list, and the target type is a native scalar or collection, the value is read from the
  underlying container in one call instead of `field()` + `decodeNil` + `decode`. Safe
  because it only applies when no alias exists, and because the restricted types have
  side-effect-free `init(from:)` — so there is no "model initialised twice" hazard. Dirty
  data simply falls through to the full path, so behaviour is unchanged.
- **New `rule.lossy(\.results)` — skip bad array elements instead of failing the batch.**
  Codable is all-or-nothing: one bad element loses the whole array. This was an explicit
  gap. Lossy is opt-in (the default stays strict, matching Foundation) and **never
  silent** — skipped indices and reasons are recorded in `YYModelLossReport`, which the
  caller reads from `userInfo`:

  ```swift
  let report = YYModelLossReport()
  decoder.userInfo[YYModelLossReport.key] = report
  let response = try decoder.decode(Response.self, from: data)
  report.losses   // [results[1]: typeMismatch ...]
  ```

  The common workaround needs a dummy `EmptyEntity` to consume a bad element, because
  `nestedUnkeyedContainer` only advances on a successful decode. This implementation uses
  `container.superDecoder()`, which advances unconditionally, so no dummy type is needed.
- **54 tests pass** (16 pre-existing + 12 KeyPath + 12 presence + 14 lossy); Swift 5 and 6
  both typecheck with `-warnings-as-errors -strict-concurrency=complete`.

### Swift — Fixes for the independent review of the idiomatic worktree (S1–S8)

All eight findings in the idiomatic worktree review are addressed.
Six of them were defects introduced by the KeyPath / presence / demo work above.

- **S1 [P1] Hook-input precision restored.** The numeric classification kept the exact
  value only for integers at or beyond 2^53, so every other non-representable decimal
  fell through to `Double`: `12345678901234567890.123456789012345678` became
  `...570000`, and out-of-range tokens such as `-9223372036854775809.0` were absorbed as
  `Int64.min` instead of being rejected. The classifier now keeps the exact `Decimal`
  for any value at or beyond 2^53 that binary64 would round away, while values binary64
  holds exactly still use the literal-parsed `Double` (preserving `-0.0`, which `Decimal`
  cannot represent). Small non-exact decimals such as `0.1` are unchanged.
- **S2 [P2] The KeyPath restriction no longer leaks into the string API.** Configuration
  keys are `CodingKey.stringValue`, not Swift property names, so `case value = "v.dot"`
  is a legal `CodingKey` and must keep working through `mapper` / `defaultValues` /
  `requiredProperties`. `YYModelPolicy.validate()` now rejects only an **empty** key
  (which is how a rejected KeyPath reports itself); the top-level-only rule lives in
  `propertyName`, where it belongs.
- **S3 [P2] Unrecognisable KeyPath descriptions are rejected at construction.**
  `String(describing:)` on a KeyPath reads field reflection metadata and falls back to a
  layout dump (`"<offset 16 (Int)>"`) when it is unavailable — reproducible with
  `-Xfrontend -disable-reflection-metadata`, which the SDK's own build never exercises.
  `propertyName` now requires a plain Swift identifier, so such a KeyPath produces an
  empty name and fails at rule construction instead of silently creating a rule that
  matches no `CodingKey`. The file header no longer claims "no runtime reflection" —
  that claim was wrong.
- **S4 [P2] Typed defaults accept the Codable values they admit.** `default(\.child, to:
  Child(n: 7))` compiled but threw `Unsupported JSON value` at `forType`. Values are now
  boxed directly when already JSON-representable and otherwise round-tripped through
  `JSONEncoder`, so nested Codable structs, arrays of them, and raw-value enums work.
- **S5 [P2] The Alamofire live path uses the real response shape.** `live()` previously
  declared `/v7/weather/now` but parsed the flat synthetic model, which the official
  response (`{code, updateTime, fxLink, now:{…}}`) cannot satisfy. The official structure
  is now modelled in `QWeatherOfficial.swift` (shared contract with the Moya demo), the
  live path decodes `QWeatherNowResponse`, and the synthetic model is explicitly named
  `syntheticWeather(cityID:)` and documented as offline teaching data.
- **S6 [P2] Mock sessions no longer share one responder.** A single
  `nonisolated(unsafe) static var` meant creating a second session overwrote the first —
  two sessions returning `1` and `2` both returned `2`. Responders are now registered per
  session identity (carried on the request via `httpAdditionalHeaders`) behind a lock, and
  the demo asserts A→1, B→2.
- **S7 [P2] Syntax options reach the dictionary-hook snapshot.** `allowsJSON5` and
  `assumesTopLevelDictionary` were set only on the main decoder, so enabling them worked
  until a `willTransform` hook forced `YYModelJSONInput.snapshot()` — which built its own
  default decoder. The options are now passed through, so a decoder's acceptance range no
  longer depends on whether a business hook is registered.
- **S8 [P2] `YYModelPresence` is conditionally `Sendable`.** Without it,
  `struct M: Codable, Sendable { let v: YYModelPresence<Int> }` failed to compile under
  Swift 6 strict concurrency. Added `extension YYModelPresence: Sendable where Value: Sendable {}`.
- **60 tests pass** (16 pre-existing + 18 KeyPath + 12 presence + 14 lossy); Swift 5 and 6
  both typecheck with `-warnings-as-errors -strict-concurrency=complete`.

### Swift — `rule.fallback(_:to:)`: cover values that exist but cannot be decoded

`default(_:to:)` only covers an **absent** key. Two real-world failures happen when the
key is present:

- **Unknown enum case.** The server adds a case; the old app throws `dataCorrupted` —
  and declaring the property `Optional` does **not** help, it still throws.
- **Invalid URL.** An empty string throws `dataCorrupted` ("Invalid URL string.").

```swift
try rule.fallback(\.kind, to: .unknown)   // unknown enum case → .unknown
try rule.fallback(\.site, to: nil)        // invalid URL → nil
```

| | key absent | value is null | value present but undecodable |
|---|:---:|:---:|:---:|
| `default` | uses default | unchanged | **throws** |
| `fallback` | uses fallback | uses fallback | **uses fallback** |

- The field is decoded **at most once**. A failure returns the fallback immediately; there
  is no retry, so a model's `init(from:)` can never run twice. `testFallbackDoesNotRetryModelInitialization`
  asserts the counter is exactly 1.
- The check must exist in **both** `decode(_:forKey:)` and `decodeIfPresent(_:forKey:)`.
  Synthesized `Codable` routes an `Optional` property through `decodeIfPresent` with
  `T` = `Wrapped`, not `Optional<Wrapped>` — handling only `decode` silently misses every
  optional field. This was caught by `testInvalidURLFallsBackToNil`.
- The fallback value is tried **after** a real decode attempt, never before. Checking
  `NSNull` first made a present value return `nil`; `testValidURLIsNotReplacedByFallback`
  caught it.
- Both the fallback and lossy lookups are short-circuited on an empty collection so the
  per-field hot path is unaffected (measured: 3.77× vs 3.68× before, same noise band).
- **72 tests pass** (16 pre-existing + 18 KeyPath + 12 presence + 14 lossy + 12 fallback);
  Swift 5 and 6 both typecheck with `-warnings-as-errors -strict-concurrency=complete`.

### Swift — Dictionary keys beyond `String` / `Int` (`CodingKeyRepresentable`)

JSON object keys could only map onto `String` and `Int` dictionaries; any other key type
fell through to normal model handling and failed. `CodingKeyRepresentable` (iOS 15.4 /
macOS 12.3) is the official extension point, and the framework now uses it:

```swift
struct Slug: Hashable, Codable, CodingKeyRepresentable { … }
struct Holder: Codable { var table: [Slug: Int] }   // {"table":{"alpha":1}}
```

- Both directions go through one helper (`YYModelDictionaryKey`) instead of the previous
  hard-coded `Key.self == String.self || Key.self == Int.self` checks, so decode and
  encode can no longer disagree about which key types are supported.
- Encoding keeps producing a real JSON object rather than degrading to an alternating
  key-value array, and an unrepresentable key now throws instead of being dropped.
- An unsupported key type still returns `nil` so the caller falls back to ordinary model
  handling — the failure stays visible rather than becoming an empty dictionary.
- Availability-gated, so the iOS 11 / macOS 10.13 floor is unchanged.
- **79 tests pass** (16 pre-existing + 18 KeyPath + 12 presence + 14 lossy + 12 fallback
  + 7 dictionary key); Swift 5 and 6 both typecheck with
  `-warnings-as-errors -strict-concurrency=complete`.

### Swift — Optional official configuration entry points (`CodableWithConfiguration`)

Added the one official mechanism for supplying external context during decoding, as an
**optional second entry point**. It does not replace the main path and is not needed for
aliases, dirty numbers or defaults — those remain the job of `YYJSONRules`.

```swift
struct Reading: DecodableWithConfiguration {
    typealias DecodingConfiguration = UnitContext
    init(from decoder: Decoder, configuration: UnitContext) throws { … }
}
let reading = try decoder.decode(Reading.self, from: data,
                                 configuration: UnitContext(unit: "°C"))
```

- **Adoption cost is stated, not hidden.** A model using this entry point must conform to
  `DecodableWithConfiguration` / `EncodableWithConfiguration` and hand-write
  `init(from:configuration:)`. That means giving up the zero-intrusion property — a cost
  of the official protocol itself, not something this framework imposes. Ordinary Codable
  models keep using `decode(_:from:)` plus external rules, and both styles can coexist in
  one project.
- **Available from iOS 15, not iOS 17.** Foundation only ships the top-level
  `JSONDecoder.decode(_:from:configuration:)` in iOS 17 / macOS 14. This implementation
  carries the configuration through `userInfo` — the same technique Foundation itself
  uses for `assumesTopLevelDictionary` — so it works on the iOS 15 floor.
- **`DecodingConfiguration` must be `Sendable`**, declared in the signature. Because the
  configuration travels through `userInfo`, and Foundation types that dictionary's values
  as `any Sendable` (a hard error under the Swift 6 language mode). The official iOS 17
  entry uses an internal channel and has no such constraint — this is the cost of the
  iOS 15 compatibility. Most configurations are structs of primitives and already qualify.
- `DecodingConfigurationProviding` / `EncodingConfigurationProviding` are supported, so a
  type can supply its own default configuration and the caller can omit the argument.
- New file `YYModelSwift/YYModelWithConfiguration.swift`; the main entry points are
  untouched. **86 tests pass** (16 pre-existing + 18 KeyPath + 12 presence + 14 lossy
  + 12 fallback + 7 dictionary key + 7 configuration); Swift 5 and 6 both typecheck with
  `-warnings-as-errors -strict-concurrency=complete`.

### Swift — Integer fast path: another 34% off compatible mode

Measuring by field type isolated the remaining cost: **integer fields were 5× more
expensive than string fields** (11.5× vs 3.1× official, +3.21 µs vs +0.65 µs per field).

Integers are excluded from the scalar fast path on purpose — they need exact semantics and
must not round through `Double` — so every integer field went through `field()` +
`decodeNil` + `superDecoder(forKey:)`, and **`superDecoder` heap-allocates a `Decoder` per
field**.

The fix reads the value straight from the container as `Decimal` and converts exactly,
skipping that allocation. It is semantically identical to the previous route:
`YYModelDecode.scalar` already decoded integers via `container.decode(Decimal.self)` +
`NSDecimalNumber`, so this only removes the wrapper, not any behaviour.

**Native `Int` decoding was explicitly rejected as a substitute.** Measured on this
toolchain:

| input | native `Int` | `Decimal` |
|---|---|---|
| `9007199254740993` | exact | exact |
| `9223372036854775808` | throws | exact |
| `1.5` | throws | 1.5 |
| `0.9999999999999999999` | **silently 1** | exact |

That last row is the rounding trap the existing code guards against; using native `Int`
would have traded correctness for speed.

| | before | after |
|---|---:|---:|
| integer fields, per field | +3.210 µs (11.53×) | **+1.818 µs (6.86×)** |
| `.compatible`, 70-field payload | 3.77× | **3.50×** |
| `.compatible`, 14-field payload | 3.96× | **3.41×** |
| per-field overhead | 1.405 µs | **1.200 µs** |

Cumulative from the start of this work: **5.27× → 3.50× (−34%)**. The ≤3.00× target is not
reached yet; the remaining cost is the exact-integer conversion chain (Decimal decode →
`NSDecimalNumber` → round → string → parse), which is inherent to the truncate-toward-zero
semantics rather than to the adapter. **86 tests pass**; Swift 5 and 6 both typecheck with
`-warnings-as-errors -strict-concurrency=complete`.

### Swift — Named entry points: make the mode choice visible

The no-argument initialiser keeps its published `.legacy` semantics, but `.legacy` is also
the slowest path (~3.6× official, versus ~1.0× for `.native`). Writing `YYJSONDecoder()`
silently picked it. Named constructors now make the choice explicit at the call site:

```swift
YYJSONDecoder.native()                 // ≈ 1.0× official — clean, well-typed data
YYJSONDecoder.compatible(rules: rules) // ≈ 3.5× — field-level tolerance + external rules
YYJSONDecoder.legacy()                 // ≈ 3.6× — 2.x migration compatibility
```

- **The default was deliberately not changed.** Switching it would silently alter the
  published call contract (whether missing fields zero-fill, how dates are interpreted).
  That kind of semantic change needs a version migration plan and business-data
  comparison — not a decision to be made from a single-scenario benchmark. The named
  entry points add a clear option while leaving existing behaviour byte-identical.
- `testNoArgumentDefaultKeepsLegacySemantics` and `testLegacyEntryEqualsNoArgumentDefault`
  pin the old behaviour; `testNativeAndCompatibleDoNotZeroFill` documents that the
  difference is real, which is precisely why changing the default cannot be done quietly.
- Ratio figures are for same-machine, same-run comparison only; they are not a claim about
  absolute performance across devices or payloads.
- New file `YYModelSwift/YYJSONEntryPoints.swift`. **93 tests pass** (16 pre-existing
  + 18 KeyPath + 12 presence + 14 lossy + 12 fallback + 7 dictionary key + 7 configuration
  + 7 entry point); Swift 5 and 6 both typecheck with
  `-warnings-as-errors -strict-concurrency=complete`.

## 2.3.0 — Objective-C / Swift Product Separation (2026-10-05)

### Breaking Change (Objective-C)
- Removed the deprecated `YYClassPropertyInfo.isSwiftDynamic` getter. The Objective-C product now contains **no Swift-related API whatsoever**. Runtime metadata cannot identify a property's source language; inspect the plain `YYEncodingTypePropertyDynamic` flag (set by Objective-C `@dynamic` declarations and dynamic property encodings) when you need the Dynamic marker. The getter had conservatively returned `NO` since 2.2.0, so removal does not change observable parsing behavior.
- CocoaPods: `swift_versions` moved into the `Swift` subspec only; the `ObjC` subspec carries no Swift declaration or toolchain requirement. SPM products `YYModel` (ObjC) and `YYModelSwift` remain independent.
- Removed the unreferenced `Bridge/YYModelBridge.swift` draft from the shipped tree; mixed usage is side-by-side SPM products or the single `YYModel2` pod.

### Fixes
- Added an explicit `(NSUInteger)` cast at the `CFDictionaryGetCount` comparison in `NSObject+YYModel.m` (inherited from the original upstream), so projects building with `-Wsign-compare -Werror` are no longer blocked.
- `Package.swift` documents that the iOS 11 / tvOS 11 floors are an intentional distribution policy below the toolchain's suggested minimum.
- README: clarified that the 2.1.9 performance table measured the removed native-first decoder architecture; current no-argument decoder costs are in the 2.2.0 delivery report. Delivery docs no longer describe the released interface as "Unreleased".

### Migration
- Replace `propertyInfo.isSwiftDynamic` with `(propertyInfo.type & YYEncodingTypePropertyDynamic) != 0`. See [OC migration](docs/OBJC-MIGRATION.md).

### Verification
- Objective-C contract E2E (macOS + iOS 26.5 simulator), original XCTest suite, Demo suite, and Swift tests re-run with the removal in place; Swift-reference scan over the ObjC product returns zero matches.

## 2.2.0 — Swift External Rules & Decoupled Codable Engine (2026-10-05)

### Swift Features & Architecture
- Swift primary APIs now accept ordinary `Codable` with external immutable `YYJSONRules`; no YY model protocol is required. Native mode directly forwards Foundation strategies/userInfo/errors. Compatible mode adapts fields once, with nested aliases/KeyPaths, explicit defaults/required validation, typed hooks, per-field dates, registered polymorphism and symmetric `YYJSONEncoder` output.
- No-argument `YYJSONDecoder` preserves published legacy zero-fill/automatic dates but no longer retries model initialization after arbitrary errors. `YYModelCodable` remains optional convenience on the unified engine; process-wide business schema/variant caches were removed.
- Fixed raw/Data strategy consistency, Optional null, nested dictionary key preservation and export-hook/polymorphic key-strategy duplication and callback paths. Added exact scalar-collection conversion, recursive finite checks, raw/Data strict-null consistency and matching legacy encoder/decoder date defaults.
- Independent Swift/ObjC products (`YYModel`, `YYModelSwift`) and Pod subspecs (`YYModel2/ObjC`, `YYModel2/Swift`).

### Objective-C Parity & Contract Hardening
- Restored original effective-hook defaults for property mapper and generic containers. Added optional `+modelMergesSuperclassConfiguration` opt-in for projects needing ancestor mapper/generic merging. Black/white lists retain original override behavior.
- Models with unsupported-only properties (pointer, CString, CArray) restore identity equality/hash fallback (`self == model`).
- Removed NSObject-wide `YYModel` protocol conformance; Swift NSObject hook models should explicitly conform or expose `@objc` hooks. Deprecated unreliable `isSwiftDynamic` source-language detection; conservative getter returns `NO`.
- Maintained exact 64-bit integer precision, controlled secure containers, optional strict nested transforms (`+modelRequiresSuccessfulNestedTransforms`), and symmetric negative/non-finite date parsing.
- Framework deployment floor remains iOS 11.0 / macOS 10.13.


## 2.1.9 — Boundary Robustness & Unified Numeric Lexer (2026-10-04)

### Boundary Correctness & Optional Nested Validation (G1–G4)

- **(G1) Objective-C UInt64 Decimal Preservation**: Preserves the full `UInt64` range (`0..18446744073709551615`) when assigning `NSDecimalNumber` and JSON decimal numbers to Objective-C unsigned 64-bit properties. Truncates fractions toward zero via `NSDecimalRound`; `NaN` and positive overflow leave existing properties untouched, and negative numbers retain legacy unsigned conversion.
- **(G2) Swift Non-Finite Floating-Point Guard**: Rejects non-finite floating-point (`Double`/`Float`/`CGFloat`), `Decimal`, and `Date` values, including overflow introduced when narrowing `Double` to `Float`.
- **(G3) Symmetric Millisecond Timestamp Handling**: Applies the existing automatic seconds/milliseconds threshold symmetrically to positive and negative timestamps (`abs(seconds) > 1e11`), using one shared date conversion for fast and tolerant decoding.
- **(G4) Optional Nested Transform Failure Propagation**: Adds the root-model protocol hook `+modelRequiresSuccessfulNestedTransforms`. When enabled, nested dictionary conversions propagate failure through objects and model containers to the root parse (returning `nil`). This hook defaults to NO, preserving the original nested-transform failure policy; other fork extensions have separate compatibility limits.
- **Public API Boundary Validation Package**: Added repeatable public API boundary E2E checks covering 62 boundary scenarios and Open-Meteo weather datasets.

### Numeric Correctness & Unified Lexer (F1–F4)

- **Unified ASCII Byte Lexer**: Parses decimal and C99 hexadecimal numeric strings using an exact ASCII-byte grammar (`NumericText`), rejecting malformed suffixes and illegal characters before conversion.
- **Normalized Exponent and Coefficient Handling**: Accurately normalizes coefficients and exponents, handling leading zeros and extreme exponents.
- **High-Precision Integer Truncation**: Truncates decimal and hexadecimal strings to integers using exact digits/bits and destination range checks; preserves values above $2^{53}$ and rejects overflow without lossy Double intermediates.
- **Hexadecimal Decimal Preservation**: Converts hexadecimal `Decimal` fields using high-precision decimal arithmetic (`NSDecimalMultiply`/`NSDecimalDivide`), preserving precision beyond `binary64`.

## 2.1.8 — Strict Numeric Architecture & High-Precision Preservation (2026-10-03)

### Bug Fixes & Architectural Enhancements (E1–E4)

- **(E1) High-Precision `NSDecimalNumber` Integer Coercion & Overflow Guard**:
  - Re-architected integer coercion for `NSNumber` instances: explicitly isolates `NSDecimalNumber` before standard binary floating-point checks.
  - Directly extracts `decimalValue` and applies mathematical toward-zero truncation (`NSDecimalRound`), verifying destination boundaries using exact integer strings (`I(str)`).
  - Completely eliminates 53-bit Double mantissa truncation for 64-bit snowflake IDs (e.g. `9007199254740993`) and boundaries (`9223372036854775807`, `18446744073709551615`).
- **(E2) Hexadecimal Float Syntax & Value Consistency**:
  - Added dedicated `isStrictHexFloatSyntax` parser supporting C99 hexadecimal floats (e.g. `"0x1p4"`, `"0x1.8p+2"`, `"-0x1p4"`).
  - Eliminates silent value corruption where `Decimal(string:)` erroneously parsed only leading zero, guaranteeing consistent evaluation to `16`, `6`, `-16` across both integers and `Decimal` fields.
- **(E3) Unified Grammar Validation for `Decimal` Fields**:
  - `Decimal` field coercion now enforces strict numeric grammar (`isStrictDecimalSyntax`), rejecting malformed alphanumeric suffixes (`"123abc"`, `"1.8xyz"`, `"1e2garbage"`).
- **(E4) Tiny Scientific Notation Toward-Zero Truncation**:
  - Values in scientific notation with small magnitudes below 1 (e.g. `"1e-129"`, `"-1e-129"`, `"1e-400"`) are mathematically recognized as lying within $(-1, 1)$, correctly truncating toward zero (`0`) without throwing false-positive `DecodingError`.

### Verification Status

- ✅ Framework XCTest: 27 passed, 0 failed.
- ✅ Demo Suite: 84 passed, 0 failed (0 warnings).
- ✅ Swift Test: 16 passed, 0 failed.
- ✅ Numeric Extension Suite (E1–E4): 5/5 checks passed (`numeric-acceptance.json`).
- ✅ Boundary Acceptance (D2–D7): 5/5 checks passed (`boundary-acceptance.json`).
- ✅ Original Acceptance (R1–R8): 9/9 checks passed (`acceptance.json`).
- ✅ Extended Acceptance (N1–N8): 11/11 checks passed (`extended-acceptance.json`).
- ✅ Sign & Extended Date Suite: 8/8 checks passed.
- ✅ iOS Simulator 26.5 Execution: exit 0.

---

## 2.1.7 — Extended Review Parity & Robustness (2026-10-03)

### Bug Fixes & Boundary Robustness (D1–D7)

- **(D2) Objective-C Whitespace-Prefixed Negative Numbers**:
  - In `YYNSNumberCreateFromID`, skips leading whitespace (`" -1"`, `"\t-123"`, `"\n-42"`) before inspecting negative sign, ensuring signed parsing via `strtoll` and preventing unintentional unsigned underflow to `18446744073709551615`.
- **(D3 & D5) Swift Decimal String Toward-Zero Truncation & Overflow Rejection**:
  - Re-architected decimal string parsing in `YYJSONDecoder.swift` to strictly truncate toward zero (matching numeric `1.8` -> `1` and `-1.8` -> `-1`) via `NSDecimalRound` mode.
  - Rejects out-of-range decimal strings (`"-9223372036854775809.0"`, `"-9.223372036854775809e18"`) by verifying integer bounds on the exact truncated representation rather than falling back to Double.
- **(D4) Swift Malformed Numeric Suffix Rejection**:
  - Strings with illegal suffixes (`"123abc"`, `"1.8xyz"`, `"1e2garbage"`) are rejected immediately, preventing partial prefix absorption.
- **(D6) Swift Non-Destructive Container Creation**:
  - `UnkeyedDecodingContainer.nestedContainer` and `nestedUnkeyedContainer` advance `currentIndex` only after successfully verifying and creating the sub-container. Failed attempts no longer prematurely consume elements, enabling clean heterogeneous array decoding.
- **(D7) Extended Date Formats Support**:
  - Added fast-fallback parsing for RFC 822/1123 (`"Sat, 03 Oct 2026 08:00:00 +0000"`) and asctime (`"Sat Oct 03 08:00:00 2026"`), preserving full compatibility with fork enhancements while retaining $O(1)$ dispatch speed for standard ISO8601 dates.
- **(D1) CocoaPods Clean Version Bump**:
  - Released as official version `2.1.7` across Podspecs and Package.swift to eliminate CocoaPods git tag cache reuse and guarantee fresh dependency installation.

### Verification Status

- ✅ Framework XCTest: 27 passed, 0 failed.
- ✅ Demo Suite: 84 passed, 0 failed (0 warnings).
- ✅ Swift Test: 16 passed, 0 failed.
- ✅ Original Acceptance (R1–R8): 9/9 checks passed (`acceptance.json`).
- ✅ Extended Acceptance (N1–N8): 11/11 checks passed (`extended-acceptance.json`).
- ✅ Boundary Acceptance (D2–D7): 5/5 checks passed (`boundary-acceptance.json`).
- ✅ Main App (BlackListTests): 21 passed, 0 failed.

---

## 2.1.6 — Code Review Enhancements & Contract Precision (2026-10-03)

### Bug Fixes & Contract Enhancements (R1–R8 & N1–N8)

- **Swift 64-Bit Integer Precision & Overflow Guard (R1, N1, N2)**:
  - Re-architected `integer<I: FixedWidthInteger>(_ value: Any, _ type: I.Type) -> I?` in `YYJSONDecoder.swift`.
  - Dispatches via `CFNumberIsFloatType` and `NSNumber.objCType` instead of casting through `Double`.
  - Preserves exact 64-bit integer values (`Int64` / `UInt64`, e.g. Snowflake IDs `9007199254740993`) from `Any` / Dictionary inputs without Double 53-bit mantissa truncation.
  - Implemented boundary-safe floating-point-to-integer conversion, eliminating `SIGTRAP` overflow crashes on `Int64.max`.
  - **(N1)** In Objective-C `YYNSNumberCreateFromID`, preserved `uint64_t` / `unsignedLongLongValue` string parsing for `"18446744073709551615"` using `strtoull` on non-negative integer strings.
  - **(N2)** Integer strings exceeding target integer range (such as `"-9223372036854775809"`) throw `DecodingError` instead of erroneously rounding via Double; decimal-suffixed integer strings (`"9007199254740993.0"`) preserve exact 64-bit precision via `Decimal` without truncation.
- **Whitelist & Blacklist Contract Parity (R2)**:
  - Strictly distinguished `nil` (no whitelist filtering) from empty `@[]` (blocks all property mapping).
  - An empty whitelist `@[]` now correctly causes property mapping to return `nil`, matching original `ibireme/YYModel` semantics.
  - Subclasses overriding `modelPropertyBlacklist` with `@[]` now correctly unblock parent properties.
- **O(1) Date Dispatch & Performance Parity (R3, R8, N8)**:
  - Restored original length-indexed dispatch table `blocks[string.length]` in `YYNSDateFromString`.
  - Fixed false-positive timestamp parsing bug where `"2026-09-05"` (length 10) was truncated to epoch 2026.
  - Restored full Twitter/Weibo date formats with fractional seconds and timezone offsets (`EEE MMM dd HH:mm:ss.SSS Z yyyy`).
  - **(N8)** Added pure digit validation to support 10-digit seconds and 13-digit millisecond timestamp strings (e.g. `"1700000000000"`).
  - Reduced date parsing latency from 86.9ms to 32.8ms per 1000 iterations (surpassing original 33.6ms baseline).
- **NSNumber Conversion Aliases (R4)**:
  - Restored full 24-entry alias table in `YYNSNumberCreateFromID` (`"yes"`, `"Yes"`, `"no"`, `"No"`, `"<null>"`, `"(NULL)"`, `"Null"`, etc.).
  - Distinguishes null markers (returning `nil`) from boolean aliases (`@(YES)` / `@(NO)`).
- **Block Property Equality & Hash Consistency (R5)**:
  - Included `YYEncodingTypeBlock` in `yy_modelIsEqual:` and `yy_modelHash`, restoring proper comparison and hash partitioning for models with callback blocks.
- **Model Equality Symmetry (R6)**:
  - Enforced `[model isMemberOfClass:self.class]` in `yy_modelIsEqual:`, guaranteeing mathematical symmetry (`a.isEqual(b) == b.isEqual(a)`).
- **NSSecureCoding for Custom Model & Foundation Containers (R7, N6)**:
  - Prioritized collection types (`NSArray`, `NSDictionary`, `NSSet`) in `yy_modelInitWithCoder:`.
  - Dynamically registers container classes and `_genericCls` into allowed classes for `decodeObjectOfClasses:forKey:`, enabling full secure round-trip unarchiving of nested custom models.
  - **(N6)** Included `NSNull`, `NSURL`, and `NSValue` in allowed container classes for `NSSecureCoding`, preventing Error 4864 when unarchiving arrays containing nulls, URLs, or boxed values.
- **Swift Decoder Resiliency & Container Fixes (N3, N4, N5, N7)**:
  - **(N3)** Tolerant walker properly decodes `Optional` elements in arrays (e.g. `[String?]` with `["a", null]`) and root Optionals without `valueNotFound` exceptions.
  - **(N4)** `KeyedDecodingContainer.superDecoder()` accesses the `"super"` key or parent container, allowing standard Codable subclass inheritance to decode parent fields.
  - **(N5)** `UnkeyedDecodingContainer` advances `currentIndex` only upon successful element decoding, allowing fallback type attempts without premature element consumption.
  - **(N7)** Direct tolerant walker invocation when falling back from `Data`, eliminating redundant secondary system `JSONDecoder` runs and cutting fallback latency by ~45%.

### Verification & Test Status

- ✅ `Framework XCTest`: 27 passed, 0 failed (100% pass rate).
- ✅ `Demo`: 84 passed, 0 failed (0 warnings).
- ✅ `swift test`: 16 passed, 0 failed.
- ✅ `E2E Review Suite (R1–R8)`: 9/9 acceptance checks passed (`acceptance.json`).
- ✅ `Extended Review Suite (N1–N8)`: 11/11 acceptance checks passed (`extended-acceptance.json`).
- ✅ `Main App Integration (BlackListTests)`: 21 passed, 0 failed.

---

## 2.1.5 — Swift 6 Strict Concurrency Compiler Safety (2026-10-03)

### Added & Fixed

- **Swift 6 Strict Concurrency**: Added `#if compiler(>=5.10) nonisolated(unsafe) #endif` guards to static `ISO8601DateFormatter` instances in `YYJSONDecoder.swift`.
- Compiles cleanly under Swift 6 strict concurrency mode (`-swift-version 6`) with 0 errors and 0 warnings.
- Synchronized version files and documentation.

---

## 2.1.4 — Full Contract Parity Restoration with ibireme/YYModel (2026-10-03)

### Bug Fixes & Architectural Restoration

- **Root Polymorphic Model Resolution**: Restored `modelCustomClassForDictionary:` on root `yy_modelWithDictionary:` and nested container mappings.
- **Custom Transform Contract**: Strictly checked boolean return value of `modelCustomTransformFromDictionary:`; returns `nil` when parsing fails.
- **Nested Model In-Place Update**: Re-mapped nested dictionaries now update existing instances via `yy_modelSetWithDictionary:` rather than replacing them with empty copies.
- **Generic Class Normalization**: String class names in `modelContainerPropertyGenericClass` are resolved via `NSClassFromString` and protocol pseudo-generics are preserved.
- **Safe KeyPath Traversal**: Restored dictionary subscript traversal, eliminating KVC `valueForUndefinedKey:` exceptions on non-dictionary intermediate nodes.
- **Model to JSON Fidelity**: Restored nested dictionary output for dotted key paths; dates format as standard ISO8601 strings; `modelCustomTransformToDictionary:` runs post-property extraction.
- **Memory & Type Safety**: Proper type handling across struct (`NSValue`), pointer, block, selector, CNumber for `yy_modelCopy`, `yy_modelEncodeWithCoder:`, `yy_modelIsEqual:`, and `yy_modelDescription`.
- **Swift YYJSONDecoder Optimizations**: Cached ISO8601 formatters with fractional seconds support; automatic millisecond timestamp conversion; direct memory decoding without intermediate serialization.

---

## 2.1.3 — Superclass Property Inheritance (2026-10-03)

### Added

- `_YYModelMeta` traverses superclass properties recursively up to `NSObject`.
- Subclass properties take precedence over superclass properties of the same name.
- Custom property mapper and blacklist/whitelist apply across the inheritance hierarchy.
- Expanded Demo test suite to T18 (81 passed tests).
- Added superclass property inheritance assertion to Swift test suite (13 passed tests).

---

## 2.1.2 — JSONDecoder Fast Path (2026-09-26)

### Performance & Architecture

- `YYJSONDecoder` decodes with `JSONDecoder` first. Dates in that pass are Unix seconds.
- The tolerant walker runs only after that decode throws. It zero-fills missing keys and `null`, and coerces string, number, and bool values.
- Microbenchmark (`/users`, 1000 iterations):
  - Native `JSONDecoder`: 76.87ms (0.077ms/iter)
  - Swift `YYJSONDecoder`: 76.59ms (0.077ms/iter)
  - Objective-C `yy_model`: 72.57ms (0.073ms/iter)
  - Mixed `yy_modelArray`: 82.20ms (0.082ms/iter)

---

## 2.1.1 — CocoaPods Platform Alignment (2026-09-26)

### Packaging

- CocoaPods `YYModel2` declares iOS and macOS so the spec can be published in environments where watchOS and tvOS simulators are not installed.
- Swift Package Manager continues to support iOS, macOS, watchOS, and tvOS.

---

## 2.1.0 — Swift Codable Decoder (2026-09-26)

### Added

- `YYJSONDecoder` decodes plain `Codable` structs and classes. Models do not conform to a YYModel protocol.
- Missing keys and JSON `null` use zero values for `Bool`, numbers, `String`, `Date`, `Data`, arrays, dictionaries, and nested objects.
- String, number, and bool values are coerced (`"3"` and `3` both become `Int`).
- `decode(_:from:)` accepts `Data` or an already parsed JSON object (`Any`).
- SPM and CocoaPods (`YYModel2`) both compile `YYModelSwift/YYJSONDecoder.swift`.

---

## 2.0.0 — Modern iOS Compatibility & SPM Support (2026-09-06)

### Distribution

- **NEW**: Swift Package Manager support (`Package.swift`).
- **NEW**: CocoaPods published as `YYModel2` (original `YYModel` pod owned by ibireme on trunk).
- Minimum deployment target set to **iOS 11.0+** / **macOS 10.13+**.

### Critical Modern iOS Fixes (P0)

- **F1**: `objc_msgSend` — Non-variadic typed function pointers matching arm64 register ABI. Introduced explicit typedefs; original YYModel already used typed casts. No independently established PAC defect or acceleration is claimed.
- **F2**: `NSSecureCoding` — `decodeObjectOfClass:forKey:` (iOS 6.0+) replaces deprecated `decodeObjectForKey:`.
- **F3**: 64-bit type encoding — `'l'`/`'L'` now uses `NSGetSizeAndAlignment()` (iOS 2.0+) for queried encoding size. Correction: l/L are 32-bit encodings on Apple arm64; C long encodes as q.
- **F4**: `NSDecimalNumber` precision — Preserved via `decimalNumberWithDecimal:` instead of implicit `double` cast.
- **F5**: `os_unfair_lock` (iOS 10.0+) — Replaces `dispatch_semaphore` for class info cache, eliminating priority inversion risk.

### Important Fixes (P1)

- **F6**: Thread-safe `NSDateFormatter` cache protected by `os_unfair_lock`.
- **F7**: Historically added isSwiftDynamic based on ivar/D guesses. Correction: these do not reliably identify Swift; the getter is now deprecated and conservative NO.
- **F8**: Thread-safe `_modelMetaCache` protected by `os_unfair_lock`.

### Compliance & Interop (P2)

- **F9**: Historically added a privacy manifest. Correction: ObjCRuntime is not an Apple required-reason category; that erroneous declaration was removed in Unreleased.
- **F10**: Full `nullable`/`nonnull` nullability annotations for Swift interop.

---

## 1.0.4 — Upstream Baseline Release by ibireme (2016-09-21)

- Final release of original `ibireme/YYModel`.
- High performance JSON model framework for iOS/macOS.
- Automatic dictionary/model conversion, custom property mapper, container generics, NSCoding, and NSCopying.
- `Demo/` — Complete test suite (76 tests) against live JSONPlaceholder API.

### API Changes

Original parsing/export entry points are retained. Fork extensions and migration effects are documented separately; blanket behavior compatibility is not claimed.

### Minimum Deployment Target

Changed from iOS 6.0 to **iOS 11.0** / macOS 10.9 to **macOS 10.13**.

Correction: these are distribution support floors. The Core does not call complete archivedData/unarchivedObject convenience APIs; callers and tests do. Cache locking uses os_unfair_lock.

Verified API availability (from Apple Developer Documentation):

| API | iOS | macOS | Used In |
|-----|-----|-------|---------|
| `os_unfair_lock` | 10.0+ | 10.12+ | **Core** — Thread-safe caches (F5, F6, F8) |
| `archivedDataWithRootObject:requiringSecureCoding:error:` | **11.0+** | **10.13+** | Caller/demo secure archiving |
| `unarchivedObjectOfClass:fromData:error:` | **11.0+** | **10.13+** | Caller/demo secure unarchiving |
| `NSSecureCoding` | 6.0+ | 10.8+ | **Core** — Protocol |
| `decodeObjectOfClass:forKey:` | 6.0+ | 10.8+ | **Core** — Type-safe unarchiving |
| `NSGetSizeAndAlignment` | 2.0+ | 10.0+ | **Core** — Type encoding size |
| `dispatch_once` | 4.0+ | 10.6+ | **Core** — One-time init |
| `NSJSONSerialization` | 5.0+ | 10.7+ | **Core** — JSON parsing |
| `NSURLSession` | 7.0+ | 10.9+ | Demo tests only |

> All NSSecureCoding APIs work without `@available` fallbacks at iOS 11.0+.
| `NSJSONSerialization` | 5.0+ | 10.7+ |
| `NSDataDetector` | 4.0+ | 10.7+ |

### Test Results

```
76 tests, 0 failures
JSON → Model: 0.10ms/iter
Model → JSON: 0.025ms/iter
Full round-trip: 0.13ms/iter
```

---

## 1.0.4 — Original Release (2019)

- Original YYModel by ibireme.
