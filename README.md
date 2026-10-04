# YYModel

High performance JSON model framework for iOS/macOS.

> **Fork maintained with modern iOS compatibility fixes.**
> Original by [ibireme](https://github.com/ibireme). This fork retains the original Objective-C entry points and adds modern toolchain fixes and a Swift Decodable API. Behavioral extensions and verified limits are documented in the delivery report.

[![CocoaPods](https://img.shields.io/cocoapods/v/YYModel2.svg)](https://cocoapods.org/pods/YYModel2)
[![License](https://img.shields.io/cocoapods/l/YYModel2.svg)](https://github.com/leeeeeeeefulong/YYModel/blob/master/LICENSE)
[![Platform](https://img.shields.io/cocoapods/p/YYModel2.svg)](https://cocoapods.org/pods/YYModel2)

[2.1.9 中文交付说明与完整性能数据](docs/DELIVERY-2.1.9-zh.md) · [公开验证回执](Validation/receipts/delivery-2.1.9-20261004.json) · [192 路径 CSV](Validation/receipts/delivery-2.1.9-measurements.csv)

Current release: **2.1.9** (`pod 'YYModel2', '2.1.9'`, SPM `from: "2.1.9"`).

---

## Modern iOS Compatibility (2026.09)

This fork addresses verified modern Xcode / Clang compatibility issues. Passing the component checks does not establish compatibility with every model, payload or device.

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

Existing Objective-C method signatures are retained. Mapper/container configuration now merges ancestor entries, and strict nested transform validation is opt-in. See the delivery report for defaults, behavioral differences and date limitations.

```objc
// Existing Objective-C entry points
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

All 11 test suites and 27 test cases from the official test suite pass. This is test-suite coverage, not proof of complete behavioral equivalence:

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

### 2.1.9 Component Performance Verification

Measured on Apple M1 Max / arm64, macOS 26.7 and iOS 26.5 Simulator, Xcode 26.6 / Swift 6.3.3, OC `-O2` and Swift `-O`. The offline Open-Meteo clean fixture is 15,785 bytes with 3 cities and 288 hourly rows. No business App is used.

Main matrix medians, **milliseconds per Data → Model operation**:

| Runtime | ibireme OC | 2.1.9 OC | Swift → 2.1.9 OC | Native JSONDecoder | YYJSONDecoder |
| --- | --- | --- | --- | --- | --- |
| macOS | 0.266003 | 0.257716 | 0.279094 | 0.882299 | 0.917215 |
| iOS Simulator | 0.305095 | 0.298042 | 0.300604 | 0.840059 | 0.854160 |

OC and Swift have different array representations: OC retains Foundation values, while the Swift DTO builds typed optional numeric arrays. Cross-language ratios therefore include different model work. Original/fork OC, Native/YY Swift and OC/Swift callers each use identical models within their respective comparisons.

The complete matrix contains 96 paths per runtime with 14 batch-average samples each. It retains slower first-round results; adjacent ABBA remeasurement of all 10 OC workloads found changes from −8.39% to +8.47% relative to fixed ibireme commit `c7df275`. No persistent regression above the predeclared +10% observation line was reproduced; this is neither a statistical equivalence test nor a universal speedup claim.

`YYJSONDecoder` still tries native `JSONDecoder` first, then its tolerant decoder after failure. Dirty data costs about 5× clean decoding in this fixture. Native dirty/sparse rejection is excluded from successful throughput. OC setters are invoked via typed `objc_msgSend`; metadata caching was already present in the original. No independent evidence attributes these timings to direct memory writes, a particular lock, or a new parsing algorithm.

**Known date limits:** configure Swift `JSONEncoder.dateEncodingStrategy = .secondsSince1970` for YY date round-trips. Objective-C negative millisecond timestamps remain unsupported or misinterpreted; Swift timestamp handling is separate.

[Full Chinese delivery report](docs/DELIVERY-2.1.9-zh.md) includes all datasets, mapping/encoding stages, mixed-process checks, paired comparisons, source identity, limitations and reproduction commands. [JSON receipt](Validation/receipts/delivery-2.1.9-20261004.json) and [CSV](Validation/receipts/delivery-2.1.9-measurements.csv) preserve the complete samples and statistics.

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

### Optional strict nested validation (2.1.9)

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

Swift decoding in 2.1.9 rejects NaN, infinity and Float overflow. Automatic date
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

### Swift YYModel on master (unreleased)

The Swift product now provides `YYModelCodable` for ordinary structs with synthesized Codable, `yy_model(withJSON:)`, dictionary/array entry points, declarative aliases and KeyPaths, filters, defaults, required fields, model transforms, registered enum variants, and symmetric JSON export. No NSObject or handwritten decoding is needed for ordinary models. See [the Swift model contract and examples](docs/SWIFT-MODEL.md) and [validation measurements](Validation/RESULTS-swift-model.md).

SPM products remain independent. CocoaPods now offers `YYModel2/ObjC` and `YYModel2/Swift`; the default includes both. These APIs and subspecs are on master, **not in the published 2.1.9 tag**. Pin the delivered commit until a new version is released.

### Published 2.1.9 compatibility APIs

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
| ✅ CocoaPods `YYModel2` 2.1.9 | `#import "YYModel.h"` or `@import YYModel2;` |
| ✅ SPM product `YYModel` | `#import <YYModel/YYModel.h>` |

#### 2. Swift only

For existing models that conform only to `Codable`, use `YYJSONDecoder`. New `YYModelCodable` models use the shortcuts described above.

```swift
import YYModelSwift          // SPM product YYModelSwift
// import YYModel2           // CocoaPods 2.1.9: YYJSONDecoder is in this module

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
| ✅ CocoaPods `YYModel2` 2.1.9 | `import YYModel2` | `YYJSONDecoder` |

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
| ✅ CocoaPods `YYModel2` 2.1.9 | `import YYModel2` | `YYJSONDecoder` and `yy_model(withJSON:)` / `yy_modelArray(with:json:)` |
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
