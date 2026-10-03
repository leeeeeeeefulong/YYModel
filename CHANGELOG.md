# Changelog

All notable changes to this project will be documented in this file.
This project adheres to [Semantic Versioning](https://semver.org/).

## 2.1.6 — Code Review Enhancements & Contract Precision (2026-10-03)

### Bug Fixes & Contract Enhancements (R1–R8)

- **Swift 64-Bit Integer Precision & Overflow Guard (R1)**:
  - Re-architected `integer<I: FixedWidthInteger>(_ value: Any, _ type: I.Type) -> I?` in `YYJSONDecoder.swift`.
  - Dispatches via `CFNumberIsFloatType` and `NSNumber.objCType` instead of casting through `Double`.
  - Preserves exact 64-bit integer values (`Int64` / `UInt64`, e.g. Snowflake IDs `9007199254740993`) from `Any` / Dictionary inputs without Double 53-bit mantissa truncation.
  - Implemented boundary-safe floating-point-to-integer conversion, eliminating `SIGTRAP` overflow crashes on `Int64.max`.
- **Whitelist & Blacklist Contract Parity (R2)**:
  - Strictly distinguished `nil` (no whitelist filtering) from empty `@[]` (blocks all property mapping).
  - An empty whitelist `@[]` now correctly causes property mapping to return `nil`, matching original `ibireme/YYModel` semantics.
  - Subclasses overriding `modelPropertyBlacklist` with `@[]` now correctly unblock parent properties.
- **O(1) Date Dispatch & Performance Parity (R3 & R8)**:
  - Restored original length-indexed dispatch table `blocks[string.length]` in `YYNSDateFromString`.
  - Fixed false-positive timestamp parsing bug where `"2026-09-05"` (length 10) was truncated to epoch 2026.
  - Restored full Twitter/Weibo date formats with fractional seconds and timezone offsets (`EEE MMM dd HH:mm:ss.SSS Z yyyy`).
  - Reduced date parsing latency from 86.9ms to 32.8ms per 1000 iterations (surpassing original 33.6ms baseline).
- **NSNumber Conversion Aliases (R4)**:
  - Restored full 24-entry alias table in `YYNSNumberCreateFromID` (`"yes"`, `"Yes"`, `"no"`, `"No"`, `"<null>"`, `"(NULL)"`, `"Null"`, etc.).
  - Distinguishes null markers (returning `nil`) from boolean aliases (`@(YES)` / `@(NO)`).
- **Block Property Equality & Hash Consistency (R5)**:
  - Included `YYEncodingTypeBlock` in `yy_modelIsEqual:` and `yy_modelHash`, restoring proper comparison and hash partitioning for models with callback blocks.
- **Model Equality Symmetry (R6)**:
  - Enforced `[model isMemberOfClass:self.class]` in `yy_modelIsEqual:`, guaranteeing mathematical symmetry (`a.isEqual(b) == b.isEqual(a)`).
- **NSSecureCoding for Custom Model Containers (R7)**:
  - Prioritized collection types (`NSArray`, `NSDictionary`, `NSSet`) in `yy_modelInitWithCoder:`.
  - Dynamically registers container classes and `_genericCls` into allowed classes for `decodeObjectOfClasses:forKey:`, enabling full secure round-trip unarchiving of nested custom models.

### Verification & Test Status

- ✅ `Framework XCTest`: 27 passed, 0 failed (100% pass rate).
- ✅ `Demo`: 84 passed, 0 failed (0 warnings).
- ✅ `swift test`: 16 passed, 0 failed (added large integer boundary tests).
- ✅ `E2E Review Suite`: 9/9 acceptance checks passed (`acceptance.json`).
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

- **F1**: `objc_msgSend` — Non-variadic typed function pointers matching arm64 register ABI. Fixes `PAC` validation and `-Wcast-function-type-strict` compile errors in Clang 15+.
- **F2**: `NSSecureCoding` — `decodeObjectOfClass:forKey:` (iOS 6.0+) replaces deprecated `decodeObjectForKey:`.
- **F3**: 64-bit type encoding — `'l'`/`'L'` now uses `NSGetSizeAndAlignment()` (iOS 2.0+) for correct size on arm64 (8 bytes, was hardcoded as 4).
- **F4**: `NSDecimalNumber` precision — Preserved via `decimalNumberWithDecimal:` instead of implicit `double` cast.
- **F5**: `os_unfair_lock` (iOS 10.0+) — Replaces `dispatch_semaphore` for class info cache, eliminating priority inversion risk.

### Important Fixes (P1)

- **F6**: Thread-safe `NSDateFormatter` cache protected by `os_unfair_lock`.
- **F7**: Swift `@objc dynamic` property detection via `isSwiftDynamic` (detects `_$` ivar prefix + `D` attribute).
- **F8**: Thread-safe `_modelMetaCache` protected by `os_unfair_lock`.

### Compliance & Interop (P2)

- **F9**: Added `PrivacyInfo.xcprivacy` with `NSPrivacyAccessedAPICategoryObjCRuntime` declaration (reason: `AC6B.1`).
- **F10**: Full `nullable`/`nonnull` nullability annotations for Swift interop.

---

## 1.0.4 — Upstream Baseline Release by ibireme (2016-09-21)

- Final release of original `ibireme/YYModel`.
- High performance JSON model framework for iOS/macOS.
- Automatic dictionary/model conversion, custom property mapper, container generics, NSCoding, and NSCopying.
- `Demo/` — Complete test suite (76 tests) against live JSONPlaceholder API.

### API Changes

**None.** All public method signatures are unchanged. 100% backward compatible.

### Minimum Deployment Target

Changed from iOS 6.0 to **iOS 11.0** / macOS 10.9 to **macOS 10.13**.

Reason: `archivedDataWithRootObject:requiringSecureCoding:error:` requires iOS 11.0+ / macOS 10.13+. This API is used in the core library's NSSecureCoding support and cannot be conditionally compiled away.

Verified API availability (from Apple Developer Documentation):

| API | iOS | macOS | Used In |
|-----|-----|-------|---------|
| `os_unfair_lock` | 10.0+ | 10.12+ | **Core** — Thread-safe caches (F5, F6, F8) |
| `archivedDataWithRootObject:requiringSecureCoding:error:` | **11.0+** | **10.13+** | **Core** — Secure archiving ← bottleneck |
| `unarchivedObjectOfClass:fromData:error:` | **11.0+** | **10.13+** | **Core** — Secure unarchiving ← bottleneck |
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
