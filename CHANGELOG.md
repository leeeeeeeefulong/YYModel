# Changelog

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
