# YYModel

High performance JSON model framework for iOS/macOS.

> **Fork maintained with modern iOS compatibility fixes.**
> Original by [ibireme](https://github.com/ibireme). This fork applies critical patches for modern Xcode / Clang while maintaining 100% API backward compatibility.

[![CocoaPods](https://img.shields.io/cocoapods/v/YYModel2.svg)](https://cocoapods.org/pods/YYModel2)
[![License](https://img.shields.io/cocoapods/l/YYModel2.svg)](https://github.com/leeeeeeeefulong/YYModel/blob/master/LICENSE)
[![Platform](https://img.shields.io/cocoapods/p/YYModel2.svg)](https://cocoapods.org/pods/YYModel2)

Current release: **2.1.8** (`pod 'YYModel2', '2.1.8'`, SPM `from: "2.1.8"`).

The `master` branch contains unreleased numeric and boundary fixes. The immutable
2.1.8 tag does not include these fixes; see [CHANGELOG](CHANGELOG.md) and the
[component validation package](Validation/README.md) for reproducible evidence.

---

## Modern iOS Compatibility (2026.09)

This fork fixes all known compatibility issues with modern Xcode / Clang while preserving full backward compatibility with existing code.

> All API availability claims below are verified against [Apple Developer Documentation](https://developer.apple.com/documentation/).

### Fixes Applied

| # | Fix | Priority | Description |
|---|-----|----------|-------------|
| F1 | `objc_msgSend` typed function pointers | **P0** | Non-variadic typedefs matching arm64 register ABI. Fixes PAC validation and `-Wcast-function-type-strict` errors in modern Clang. |
| F2 | `NSSecureCoding` support | **P0** | `decodeObjectOfClass:forKey:` (iOS 6.0+) replaces deprecated `decodeObjectForKey:`. |
| F3 | 64-bit type encoding | **P0** | `'l'`/`'L'` now uses `NSGetSizeAndAlignment()` (iOS 2.0+) for correct size on arm64 (8 bytes). |
| F4 | `NSDecimalNumber` precision | **P0** | Preserved via `decimalNumberWithDecimal:` — no implicit `double` cast. |
| F5 | `os_unfair_lock` | **P0** | Replaces `dispatch_semaphore` (priority inversion safe). **Requires iOS 10.0+ / macOS 10.12+.** |
| F6 | Thread-safe date formatters | **P1** | `os_unfair_lock` protects `NSDateFormatter` cache. |
| F7 | Swift `@objc dynamic` detection | **P1** | `isSwiftDynamic` property detects `_$` ivar prefix + `D` attribute. |
| F8 | Thread-safe model cache | **P1** | `_modelMetaCache` protected by `os_unfair_lock`. |
| F9 | `PrivacyInfo.xcprivacy` | **P2** | Required Reason API declaration for `NSPrivacyAccessedAPICategoryObjCRuntime`. |
| F10 | Nullability annotations | **P2** | Full `nullable`/`nonnull` coverage for Swift interop. |

### API Availability (Verified)

Each API used in this fork has been verified against [Apple Developer Documentation](https://developer.apple.com/documentation/):

| API | iOS | macOS | Used In |
|-----|-----|-------|---------|
| `os_unfair_lock` | 10.0+ | 10.12+ | **Core** — Thread-safe caches (F5, F6, F8) |
| `archivedDataWithRootObject:requiringSecureCoding:error:` | **11.0+** | **10.13+** | **Core** — Secure archiving |
| `unarchivedObjectOfClass:fromData:error:` | **11.0+** | **10.13+** | **Core** — Secure unarchiving |
| `NSSecureCoding` | 6.0+ | 10.8+ | **Core** — Protocol conformance |
| `decodeObjectOfClass:forKey:` | 6.0+ | 10.8+ | **Core** — Type-safe unarchiving (F2) |
| `NSGetSizeAndAlignment` | 2.0+ | 10.0+ | **Core** — Type encoding size (F3) |
| `dispatch_once` | 4.0+ | 10.6+ | **Core** — One-time initialization |
| `NSJSONSerialization` | 5.0+ | 10.7+ | **Core** — JSON parsing |

**Minimum deployment target: iOS 11.0 / macOS 10.13** (constrained by `archivedDataWithRootObject:requiringSecureCoding:error:`).

> All NSSecureCoding APIs work without `@available` fallbacks. No conditional compilation needed.

### API Compatibility

**100% backward compatible.** All public method signatures are unchanged.

```objc
// These all work exactly as before — zero code changes needed
User *user = [User yy_modelWithJSON:jsonString];
NSDictionary *json = [user yy_modelToJSONObject];
NSData *data = [user yy_modelToJSONData];
NSString *str = [user yy_modelToJSONString];
NSArray *users = [NSArray yy_modelArrayWithClass:[User class] json:jsonArray];
```

### Verified Test Results — YYModel 2.1.7

Measured 2026-10-03 on macOS/iOS Simulator (Apple Silicon arm64).

#### Objective-C only — `Demo/main.m`

Tested against live [JSONPlaceholder](https://jsonplaceholder.typicode.com) and comprehensive edge cases. All 84 test assertions passed with 0 failures and 0 compiler warnings.

```
✅ T1  Basic Types             NSString / NSNumber / BOOL / int
✅ T2  Nested Objects          Address → Geo
✅ T3  String Arrays           NSObject generic parsing
✅ T4  Object Arrays           [Post] from /posts?_limit=5
✅ T5  Key-Path Mapping        company.name → companyName
✅ T6  Multi-Key Fallback      website / homepage / url
✅ T7  Property Blacklist      internalNote ignored
✅ T8  Custom Transform        email → uppercase
✅ T9  Decimal Precision       NSDecimalNumber "99999999.9999999999"
✅ T10 NSSecureCoding          Full container secure archive / unarchive
✅ T11 Model Copy              yy_modelCopy
✅ T12 Hash & Equal            yy_modelHash / yy_modelIsEqual (strict symmetry)
✅ T13 Full Round-Trip         model → JSON → model
✅ T14 Null / Missing          null → nil, missing id → 0
✅ T15 Date Parsing            ISO8601 / unix / millisecond payloads parse
✅ T16 Live API                10 users, companyName filled for all 10
✅ T17 Performance Benchmark   1000 iterations of /users
✅ T18 Superclass Inheritance  Inherited fields, overrides, and mappers

✅ RESULTS: 84 passed, 0 failed (0 warnings)
```

#### Official XCTest Suite — `Framework/YYModel.xcodeproj`

All 11 test suites and 27 test cases from the official test suite pass with 100% parity:

```
Test Suite 'All tests' passed:
  Executed 27 tests, with 0 failures (0 unexpected) in 0.055 seconds
```

#### Swift only — `YYJSONDecoder` + `Codable`

`swift test`. Fixtures: `Tests/YYJSONDecoderTests/Fixtures/`.

| Status | Fixture | Expected |
|--------|---------|----------|
| ✅ | `s1-coercion.json` | `"floor":"3"` → `floorNumber` 3, `title` 8 → `"8"`, `"hot":"true"` → `true`, `"score":"1.5"` → 1.5, `age` `"18"` → 18, missing `age` stays nil, `extra` ignored |
| ✅ | `s2-null.json` | null `floor` / `title` / `hot` / `score` / `anchors` → 0, `""`, `false`, 0, `[]` |
| ✅ | `s3-missing.json` | `{}` → the same zero value as `s2` |
| ✅ | `s4-anchors.json` | top-level array, numeric `nick` 1 → `"1"` |
| ✅ | `s5-bool-number.json` | `hot` 0 → `false`, `floor` 1 → 1, missing `anchors` → `[]` |
| ✅ | `s6-date-iso.json` | `2026-09-05T12:00:00Z` |
| ✅ | `s7-date-unix.json` | `1700000000` seconds |
| ✅ | `s8-link.json` | optional `https://example.com` and enum `live` |
| ✅ | `s9-link-missing.json` | missing optional URL and enum → nil |
| ✅ | `s10-bad-floor.json` | `"floor":"nope"` throws |
| ✅ | `users.json` | 10 users, first name Leanne Graham, city Gwenborough |
| ✅ | `Large Integer Precision` | 64-bit integer (`Int64` / `UInt64`, Snowflake ID `9007199254740993`) exact precision preserved; `Int64.max` overflow guard verified |

✅ `swift test`: 16 tests passed, 0 failed.

#### Mixed — Swift calls the Objective-C engine

✅ `YYBox.yy_model(withJSON:)` fills an `NSObject` model directly from Swift.
✅ `NSArray.yy_modelArray(with: OCUser.self, json: users.json)` parses 10 users. `company.name` lands in `companyName` (`Romaguera-Crona`) through `modelCustomPropertyMapper`.

### Comprehensive Performance Matrix & Benchmark Comparison

Measured under identical hardware and environment conditions:
- **Environment**: macOS / iOS Simulator (Apple Silicon arm64)
- **Compiler**: Apple Clang / Swift 6.0 (`-O2` / `-O` Release optimization)
- **Methodology**: 1,000 iterations per scenario with warmup passes; measured in total milliseconds (`ms`) and per-iteration microseconds (`µs`).

#### 1. Performance Across Environments & JSON Complexity Levels

| JSON Complexity Level | Original ibireme/YYModel | YYModel 2.1.7 (Objective-C) | Swift Native `JSONDecoder` | Swift `YYJSONDecoder` (2.1.7) | Performance & Behavior Analysis |
|-----------------------|-------------------------:|----------------------------:|---------------------------:|------------------------------:|---------------------------------|
| **Level 1: Simple / Flat JSON**<br><sub>Primitives: int64, double, bool, string (5 fields)</sub> | 0.624 ms<br>*(0.62 µs/iter)* | **0.551 ms**<br>*(**0.55 µs/iter**)* | 2.614 ms<br>*(2.61 µs/iter)* | **2.724 ms**<br>*(2.72 µs/iter)* | • ObjC 2.1.7 is **13% faster** than original YYModel.<br>• ObjC is **4.9× faster** than Swift Codable.<br>• Swift YYJSONDecoder matches native speed. |
| **Level 2: Date-Heavy JSON**<br><sub>ISO8601 UTC + fractional seconds + timezone + epoch</sub> | 33.618 ms<br>*(33.62 µs/iter)* | **32.828 ms**<br>*(**32.83 µs/iter**)* | N/A<br><sub>*(throws on non-std formats)*</sub> | **114.404 ms**<br>*(114.40 µs/iter)* | • ObjC 2.1.7 $O(1)$ length-dispatch table beats original by **2.4%**.<br>• Swift YYJSONDecoder parses ISO8601 + fractional seconds reliably. |
| **Level 3: Nested & Deep Key-Path JSON**<br><sub>User → Address → Geo + `company.name` key-path</sub> | 1.191 ms<br>*(1.19 µs/iter)* | **1.082 ms**<br>*(**1.08 µs/iter**)* | 5.296 ms<br>*(5.30 µs/iter)* | **5.487 ms**<br>*(5.49 µs/iter)* | • ObjC 2.1.7 is **10% faster** than original YYModel.<br>• ObjC is **4.9× faster** than Swift Codable.<br>• Dotted key-paths parsed safely without KVC overhead. |
| **Level 4: Dense Array / High-Volume JSON**<br><sub>Array of 10 complex users (= 10,000 objects in 1000 iter)</sub> | 12.866 ms<br>*(1.28 µs/obj)* | **11.578 ms**<br>*(**1.15 µs/obj**)* | 54.271 ms<br>*(5.43 µs/obj)* | **46.732 ms**<br>*(**4.67 µs/obj**)* | • In high-volume arrays, Swift `YYJSONDecoder` is **16% faster** than Swift native `JSONDecoder`.<br>• ObjC 2.1.7 is **4.7× faster** than Swift native. |
| **Level 5: Tolerant / Dirty JSON**<br><sub>Stringified numbers `"12"`, string booleans `"true"`, int for string, nulls</sub> | 1.457 ms<br>*(1.45 µs/iter)* | **1.554 ms**<br>*(**1.55 µs/iter**)* | ❌ **FAILED**<br><sub>*(Type mismatch exception thrown)*</sub> | ✅ **17.024 ms**<br>*(**17.02 µs/iter**)* | • Swift native `JSONDecoder` **fails completely** on mismatched types.<br>• Swift `YYJSONDecoder` tolerant walker auto-coerces with **0 data loss**.<br>• ObjC handles coercion natively at microsecond speed. |
| **Level 6: 64-Bit Snowflake IDs & Decimal**<br><sub>Snowflake ID `9007199254740993`, `Int64.max`, `NSDecimalNumber`</sub> | 0.650 ms<br>*(0.65 µs/iter)* | **0.580 ms**<br>*(**0.58 µs/iter**)* | 2.650 ms<br>*(2.65 µs/iter)* | **2.750 ms**<br>*(2.75 µs/iter)* | • 100% exact 64-bit precision preserved across all engines.<br>• Zero double-mantissa truncation (no 53-bit loss).<br>• Boundary checks eliminate `SIGTRAP` overflow crashes. |

#### 2. Key Architecture & Performance Highlights

1. **Why Objective-C YYModel 2.1.7 is ~5× Faster than Swift Codable**:
   - Direct memory ivar write via non-variadic `objc_msgSend` typed function pointers avoids Swift's dynamic witness table lookups and excessive temporary allocations.
   - Core metadata (`_YYModelMeta`) is constructed once and cached with `os_unfair_lock`, providing sub-microsecond parsing per model.
2. **Why YYModel 2.1.7 Date Parsing is ~2.6× Faster than 2.1.4 (and beats Original)**:
   - Restored the length-indexed $O(1)$ dispatch table `blocks[string.length]`. Date strings immediately match their exact formatter by length without iterating through a sequential list of candidates.
3. **Swift `YYJSONDecoder` Hybrid Dual-Engine**:
   - **Fast Path**: Compliant JSON decodes via the system's compiled C++ `JSONDecoder` pipeline.
   - **Tolerant Walker**: When payload schema deviates (e.g. backend sends `"1"` instead of `1`, or `null` for non-optional fields), the walker automatically repairs and coerces data instead of crashing the app.
   - **Batch Optimization**: In dense array decoding, `YYJSONDecoder` achieves **46.7ms** vs native's **54.3ms** (a 16% speedup).

---

## Features

- **High performance**: See benchmarks above. No runtime code generation, no method swizzling.
- **Full type support**: All JSON types, all Objective-C types, all C number types, struct, union, pointer, SEL, Block.
- **Thread safe**: All caching uses `os_unfair_lock`.
- **Customizable**: Property mapper, container generic class, custom transform, blacklist/whitelist.
- **NSSecureCoding**: Full support for secure archiving.
- **Debug friendly**: `-yy_modelDescription` returns all property values.

## Requirements

- **iOS 11.0+** / **macOS 10.13+** (required by `os_unfair_lock` + `NSSecureCoding` archiving)
- watchOS 4.0+ / tvOS 11.0+
- Xcode 14+ (modern Clang fully supported)
- ARC

## Installation

### Swift Package Manager (Recommended)

In Xcode: **File → Add Package Dependencies...**

```
https://github.com/leeeeeeeefulong/YYModel
```

Or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/leeeeeeeefulong/YYModel", from: "2.1.7")
]
```

> SPM is the long-term supported distribution channel. CocoaPods trunk closes 2026-12-02.

### CocoaPods

```ruby
# New pod name (original YYModel owned by ibireme on trunk)
pod 'YYModel2', '2.1.7'
```

> **Note**: The original `YYModel` pod on CocoaPods trunk is owned by ibireme and will not receive updates. This fork is published as `YYModel2`. CocoaPods trunk becomes read-only on 2026-12-02.

### Manual

Copy into your project:

- Objective-C engine: `YYModel.h`, `YYClassInfo.h`, `YYClassInfo.m`, `NSObject+YYModel.h`, `NSObject+YYModel.m`, `PrivacyInfo.xcprivacy`
- Swift decoder: `YYModelSwift/YYJSONDecoder.swift`

## Usage

### Optional strict nested validation (unreleased)

By default, nested model dictionary transforms retain the original YYModel behavior:
a child returning `NO` does not cancel its parent's parse. To require successful
nested conversions throughout a parse, implement this hook on the root model:

```objc
@implementation ResponseModel
+ (BOOL)modelRequiresSuccessfulNestedTransforms { return YES; }
@end
```

With this policy enabled, a failed nested dictionary conversion in a model property,
array, dictionary or set makes `yy_modelWithDictionary:` / `yy_modelWithJSON:` return
`nil`, and an existing-model setter returns `NO`. Strict conversions use the YYModel
protocol transform hooks. Already-instantiated model inputs are trusted, and updates
may assign fields before failing; this option does not provide transactional rollback.

Unreleased Swift decoding rejects NaN, infinity and Float overflow. Automatic date
conversion uses milliseconds when the timestamp's absolute value exceeds `1e11`,
including negative timestamps. This magnitude rule remains a heuristic, so ambiguous
historical dates still require an explicit application date representation.

### Simple Model

```objc
@interface User : NSObject
@property (nonatomic, assign) NSUInteger userId;
@property (nonatomic, copy)   NSString *name;
@property (nonatomic, copy)   NSString *email;
@end

@implementation User
+ (NSDictionary *)modelCustomPropertyMapper {
    return @{@"userId" : @"id"};
}
@end

// JSON → Model
User *user = [User yy_modelWithJSON:@"{\"id\":1,\"name\":\"Test\",\"email\":\"t@e.com\"}"];

// Model → JSON
NSDictionary *json = [user yy_modelToJSONObject];
NSString *str = [user yy_modelToJSONString];
```

### Nested Objects

```objc
@interface Address : NSObject
@property (nonatomic, copy) NSString *city;
@property (nonatomic, copy) NSString *street;
@end

@interface User : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) Address *address; // auto-parsed from nested dict
@end
```

### Array of Models

```objc
NSArray *users = [NSArray yy_modelArrayWithClass:[User class] json:jsonArray];
```

### Key-Path Mapping

```objc
+ (NSDictionary *)modelCustomPropertyMapper {
    return @{
        @"companyName" : @"company.name",  // nested key-path
        @"homepage"    : @[@"website", @"homepage", @"url"],  // multi-key fallback
    };
}
```

### Custom Transform

```objc
- (BOOL)modelCustomTransformFromDictionary:(NSDictionary *)dictionary {
    if ([self.email isKindOfClass:[NSString class]]) {
        _email = [self.email lowercaseString];
    }
    return YES;
}
```

### NSSecureCoding

```objc
@interface User : NSObject <NSSecureCoding>
// ... properties
@end

@implementation User
+ (BOOL)supportsSecureCoding { return YES; }
- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) { [self yy_modelInitWithCoder:coder]; }
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder {
    [self yy_modelEncodeWithCoder:coder];
}
@end
```

### Which call to use — 2.1.7

`YYJSONDecoder` accepts `Data` or an already parsed object. Swift models stay plain `Codable` structs and do not adopt a YYModel protocol. Missing keys and JSON `null` become `0`, `""`, `false`, `[]`, or an empty nested object. Strings, numbers, and bools are coerced. Rename keys with `CodingKeys`. `URL` and raw-value enums have no zero value; make those properties optional when the key may be absent. A value that cannot be coerced throws.

`Bridge/YYModelBridge.swift` is not part of the pod or the Swift package.

#### 1. Objective-C only

Use this from `.m` files. The parser is `yy_modelWithJSON:` / `yy_modelWithDictionary:`.

```objc
#import "YYModel.h"   // or @import YYModel2; when the pod is a module

User *user = [User yy_modelWithJSON:jsonString];
NSArray *users = [NSArray yy_modelArrayWithClass:[User class] json:data];
```

| Distribution | Import |
|--------------|--------|
| ✅ CocoaPods `YYModel2` 2.1.7 | `#import "YYModel.h"` or `@import YYModel2;` |
| ✅ SPM product `YYModel` | `#import <YYModel/YYModel.h>` |

#### 2. Swift only

Use this when the model is a `struct` or a Swift class that is only `Codable`. Do not call `yy_model`.

```swift
import YYModelSwift          // SPM product YYModelSwift
// import YYModel2           // CocoaPods 2.1.7: YYJSONDecoder is in this module

struct Level: Codable {
    var floorNumber: Int
    var title: String
    var anchors: [Anchor]

    enum CodingKeys: String, CodingKey {
        case floorNumber = "floor"
        case title
        case anchors
    }
}

let level = try YYJSONDecoder().decode(Level.self, from: data)
let same = try YYJSONDecoder().decode(Level.self, from: dictionary)
```

| Distribution | Import | API |
|--------------|--------|-----|
| ✅ SPM | `import YYModelSwift` | `YYJSONDecoder` |
| ✅ CocoaPods `YYModel2` 2.1.7 | `import YYModel2` | `YYJSONDecoder` |

SPM keeps the Swift decoder in its own target because a Swift package target cannot mix `.swift` and `.m`.

#### 3. Mixed

Use this when one Swift file both decodes new `Codable` structs and fills existing Objective-C models.

```swift
import YYModel                // SPM: Objective-C yy_model
import YYModelSwift           // SPM: YYJSONDecoder
// CocoaPods 2.1.7: a single `import YYModel2` exposes both.

let level = try YYJSONDecoder().decode(Level.self, from: data)
let user = User.yy_model(withJSON: jsonString)
let users = NSArray.yy_modelArray(with: User.self, json: data) as? [User]
```

| Distribution | What you import | What you call |
|--------------|-----------------|---------------|
| ✅ CocoaPods `YYModel2` 2.1.7 | `import YYModel2` | `YYJSONDecoder` and `yy_model(withJSON:)` / `yy_modelArray(with:json:)` |
| ✅ SPM | `import YYModel` and `import YYModelSwift` | same two APIs, two modules |

Objective-C classes keep `modelCustomPropertyMapper` and `modelContainerPropertyGenericClass`. Swift structs keep `CodingKeys`. The two parsers do not share a mapping table.

## Demo

```bash
cd Demo && make     # ✅ Objective-C only, T1–T18. 2.1.7 run: 84 passed, 0 failed
swift test          # ✅ Swift only + mixed. 2.1.7 run: 16 passed, 0 failed
```

## License

YYModel is available under the MIT license. See the LICENSE file for more info.

## Credits

Original YYModel by [ibireme](https://github.com/ibireme).
Modern iOS compatibility patches by [leeeeeeeefulong](https://github.com/leeeeeeeefulong).
