# Changelog

## 1.0.5 — Modern iOS Compatibility (2026-09-06)

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

Changed from iOS 6.0 to **iOS 10.0** / macOS 10.9 to **macOS 10.12**.

Reason: `os_unfair_lock` requires iOS 10.0+ / macOS 10.12+. All other APIs used are available from iOS 6.0 or earlier.

Verified API availability (from Apple Developer Documentation):

| API | iOS | macOS |
|-----|-----|-------|
| `os_unfair_lock` | 10.0+ | 10.12+ |
| `NSSecureCoding` | 6.0+ | 10.8+ |
| `decodeObjectOfClass:forKey:` | 6.0+ | 10.8+ |
| `archivedDataWithRootObject:requiringSecureCoding:error:` | 11.0+ | 10.13+ |
| `dispatch_once` | 4.0+ | 10.6+ |
| `NSGetSizeAndAlignment` | 2.0+ | 10.0+ |
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
