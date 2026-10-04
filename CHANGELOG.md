# Changelog

All notable changes to this project will be documented in this file.
This project adheres to [Semantic Versioning](https://semver.org/).

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
- **Public API Boundary Validation Package**: Added repeatable public API boundary E2E checks (`Validation/`) covering 62 boundary scenarios and Open-Meteo weather datasets.

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
