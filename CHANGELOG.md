# Changelog

## 2.1.4 — 100% Behavioral Parity with ibireme/YYModel & Swift Optimizations (2026-10-03)

- **Polymorphic Resolution**: Restored `modelCustomClassForDictionary:` on root `yy_modelWithDictionary:` and nested container mappings.
- **Custom Transform Contract**: `modelCustomTransformFromDictionary:` boolean return value is strictly checked; returns `nil` when parsing fails.
- **Nested Model In-Place Update**: Re-mapped nested dictionaries now update existing instances via `yy_modelSetWithDictionary:` rather than replacing them.
- **Generic Class Normalization**: String class names in `modelContainerPropertyGenericClass` are resolved via `NSClassFromString` and protocol pseudo-generics are preserved.
- **Safe KeyPath Traversal**: Restored dictionary subscript traversal, eliminating KVC `valueForUndefinedKey:` exceptions on non-dictionary intermediate nodes.
- **Model to JSON Fidelity**: Restored nested dictionary output for dotted key paths; dates format as standard ISO8601 strings; `modelCustomTransformToDictionary:` runs post-property extraction.
- **Memory & Type Safety**: Proper type handling across struct (`NSValue`), pointer, block, selector, CNumber for `yy_modelCopy`, `yy_modelEncodeWithCoder:`, `yy_modelIsEqual:`, and `yy_modelDescription`.
- **Inheritance Traversal**: Subclass merges custom mappers, generic classes, and blacklists/whitelists from ancestors bottom-up.
- **Swift YYJSONDecoder Optimizations**: Cached ISO8601 formatters with fractional seconds support; automatic millisecond timestamp conversion; direct memory decoding without intermediate serialization.
- ✅ `Framework XCTest`: 27 passed, 0 failed (100% pass rate).
- ✅ `Demo`: 84 passed, 0 failed.
- ✅ `swift test`: 15 passed, 0 failed.

## 2.1.3 — Superclass property inheritance (2026-10-03)

- `_YYModelMeta` traverses superclass properties recursively up to `NSObject`.
- Subclass properties take precedence over superclass properties of the same name.
- Custom property mapper and blacklist/whitelist apply across the inheritance hierarchy.
- ✅ `Demo`: 81 passed, 0 failed (added T18 for superclass property inheritance).
- ✅ `swift test`: 13 passed, 0 failed (added inheritance assertion to `testObjectiveCModelStillDecodes`).

## 2.1.2 — JSONDecoder fast path (2026-09-26)

- `YYJSONDecoder` decodes with `JSONDecoder` first. Dates in that pass are Unix seconds.
- The tolerant walker runs only after that decode throws. It zero-fills missing keys and `null`, and coerces string, number, and bool values.
- ✅ `/users`, 1000 iterations: native `JSONDecoder` 76.87ms (0.077ms), `YYJSONDecoder` 76.59ms (0.077ms), Objective-C `yy_model` 72.57ms (0.073ms), mixed `yy_modelArray` 82.20ms (0.082ms).
- ✅ `Demo`: 76 passed, 0 failed. ✅ `swift test`: 13 passed, 0 failed.
- README separates Objective-C only, Swift only, and mixed calls.

## 2.1.1 — CocoaPods platforms (2026-09-26)

- CocoaPods `YYModel2` declares iOS and macOS so the spec can be published where watchOS and tvOS simulators are not installed.
- Swift Package Manager still declares watchOS and tvOS. Decoder behavior is the same as 2.1.0.

## 2.1.0 — Swift Codable decoder (2026-09-26)

### Added

- `YYJSONDecoder` decodes plain `Codable` structs and classes. Models do not conform to a YYModel protocol.
- Missing keys and JSON `null` use zero values for `Bool`, numbers, `String`, `Date`, `Data`, arrays, dictionaries, and nested objects.
- String, number, and bool values are coerced (`"3"` and `3` both become `Int`).
- `decode(_:from:)` accepts `Data` or an already parsed JSON object.
- SPM and CocoaPods (`YYModel2`) both compile `YYModelSwift/YYJSONDecoder.swift`.
- CocoaPods declares iOS and macOS. The Swift package still declares watchOS and tvOS.

### Unchanged

- Objective-C `yy_modelWithJSON:` / `yy_modelWithDictionary:` behavior.
- `URL` and raw-value enums still need to be optional when a key may be missing. An uncoercible value throws instead of becoming zero.

## 2.0.0 — Modern iOS Compatibility + SPM Support (2026-09-06)

### Distribution

- **NEW**: Swift Package Manager support (`Package.swift`)
- **NEW**: CocoaPods published as `YYModel2` (original `YYModel` name owned by ibireme on trunk)
- CocoaPods trunk closes **2026-12-02** — this is the final version that can be published there

### Critical Fixes (P0)

- **F1**: `objc_msgSend` — Non-variadic typed function pointers matching arm64 register ABI. Fixes `PAC` validation and `-Wcast-function-type-strict` compile errors in modern Clang/Xcode.
- **F2**: `NSSecureCoding` — `decodeObjectOfClass:forKey:` (iOS 6.0+) replaces deprecated `decodeObjectForKey:`. Required for secure archiving.
- **F3**: 64-bit type encoding — `'l'`/`'L'` now uses `NSGetSizeAndAlignment()` (iOS 2.0+) for correct size on arm64 (8 bytes, was hardcoded as 4).
- **F4**: `NSDecimalNumber` precision — Preserved via `decimalNumberWithDecimal:` instead of implicit `double` cast.
- **F5**: `os_unfair_lock` (iOS 10.0+) — Replaces `dispatch_semaphore` for class info cache. Eliminates priority inversion risk.

### Important Fixes (P1)

- **F6**: Thread-safe `NSDateFormatter` cache protected by `os_unfair_lock`.
- **F7**: Swift `@objc dynamic` property detection via `isSwiftDynamic` (detects `_$` ivar prefix + `D` attribute).
- **F8**: Thread-safe `_modelMetaCache` protected by `os_unfair_lock`.

### Compliance (P2)

- **F9**: Added `PrivacyInfo.xcprivacy` with `NSPrivacyAccessedAPICategoryObjCRuntime` declaration (reason: `AC6B.1`).
- **F10**: Full `nullable`/`nonnull` nullability annotations for Swift interop.

### New Files

- `PrivacyInfo.xcprivacy` — Required Reason API manifest for iOS 17+.
- `Bridge/YYModelBridge.swift` — Swift ↔ ObjC bridge for Codable coexistence.
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
