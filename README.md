# YYModel

High performance JSON model framework for iOS/macOS.

> **Fork maintained with modern iOS compatibility fixes.**
> Original by [ibireme](https://github.com/ibireme). This fork applies critical patches for modern Xcode / Clang while maintaining 100% API backward compatibility.

[![CocoaPods](https://img.shields.io/cocoapods/v/YYModel.svg)](https://cocoapods.org/pods/YYModel)
[![License](https://img.shields.io/cocoapods/l/YYModel.svg)](https://github.com/leeeeeeeefulong/YYModel/blob/master/LICENSE)
[![Platform](https://img.shields.io/cocoapods/p/YYModel.svg)](https://cocoapods.org/pods/YYModel)

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

### Verified Test Results

Objective-C suite: `Demo/main.m`, run on 2026-09-26 against live [JSONPlaceholder](https://jsonplaceholder.typicode.com). The file contains 78 `TEST_ASSERT`s. Two of them run only when `/users` is a dictionary, and that API returns an array, so the run reports 76.

```
T1  Basic Types         NSString / NSNumber / BOOL / int
T2  Nested Objects      Address → Geo
T3  String Arrays       NSObject generic parsing
T4  Object Arrays       [Post] from /posts?_limit=5
T5  Key-Path Mapping    company.name → companyName
T6  Multi-Key Fallback  website / homepage / url
T7  Property Blacklist  internalNote ignored
T8  Custom Transform    email → uppercase
T9  Decimal Precision   NSDecimalNumber "99999999.9999999999"
T10 NSSecureCoding      archive / unarchive
T11 Model Copy          yy_modelCopy
T12 Hash & Equal        yy_modelHash / yy_modelIsEqual
T13 Full Round-Trip     model → JSON → model
T14 Null / Missing      null → nil, missing id → 0
T15 Date JSON           ISO8601 / unix / millisecond payloads parse
T16 Live API            10 users, companyName filled for all 10
T17 Performance         1000 iterations of /users

RESULTS: 76 passed, 0 failed
```

Swift Codable suite: `swift test`. Input files are `Tests/YYJSONDecoderTests/Fixtures/`.

| Fixture | Expected |
|---------|----------|
| `s1-coercion.json` | `"floor":"3"` → `floorNumber` 3, `title` 8 → `"8"`, `"hot":"true"` → `true`, `"score":"1.5"` → 1.5, `age` `"18"` → 18, missing `age` stays nil, `extra` ignored |
| `s2-null.json` | null `floor` / `title` / `hot` / `score` / `anchors` → 0, `""`, `false`, 0, `[]` |
| `s3-missing.json` | `{}` → the same zero value as `s2` |
| `s4-anchors.json` | top-level array, numeric `nick` 1 → `"1"` |
| `s5-bool-number.json` | `hot` 0 → `false`, `floor` 1 → 1, missing `anchors` → `[]` |
| `s6-date-iso.json` | `2026-09-05T12:00:00Z` |
| `s7-date-unix.json` | `1700000000` seconds |
| `s8-link.json` | optional `https://example.com` and enum `live` |
| `s9-link-missing.json` | missing optional URL and enum → nil |
| `s10-bad-floor.json` | `"floor":"nope"` throws |

`Tests/YYJSONDecoderTests` also checks that an already parsed dictionary matches `s5-bool-number.json`, and that an Objective-C `NSObject` still decodes with `yy_model(withJSON:)`.

### Performance

`Demo` T17, 1000 iterations, JSONPlaceholder `/users`, measured 2026-09-26:

| Operation | 1000 iterations | Per iteration |
|-----------|-----------------|---------------|
| JSON → Model | 76.51ms | 0.077ms |
| Model → JSON | 24.82ms | 0.025ms |
| Full round-trip | 123.88ms | 0.124ms |

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
    .package(url: "https://github.com/leeeeeeeefulong/YYModel", from: "2.0.0")
]
```

> SPM is the long-term supported distribution channel. CocoaPods trunk closes 2026-12-02.

### CocoaPods

```ruby
# New pod name (original YYModel owned by ibireme on trunk)
pod 'YYModel2', '~> 2.0.0'
```

> **Note**: The original `YYModel` pod on CocoaPods trunk is owned by ibireme and will not receive updates. This fork is published as `YYModel2`. CocoaPods trunk becomes read-only on 2026-12-02.

### Manual

Copy the `YYModel/` directory into your project:
- `YYModel.h`
- `YYClassInfo.h` / `YYClassInfo.m`
- `NSObject+YYModel.h` / `NSObject+YYModel.m`
- `PrivacyInfo.xcprivacy`

## Usage

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

### Swift Codable

Swift models stay plain `Codable` structs. They do not adopt a YYModel protocol.
`YYJSONDecoder` accepts JSON `Data` or an already parsed object. Missing keys and
JSON `null` become zero values (`0`, `""`, `false`, `[]`, empty nested objects).
Strings, numbers, and bools are coerced. Rename keys with `CodingKeys`.
`URL` and raw-value enums have no zero value; make those properties optional when
the key may be absent. A value that cannot be coerced throws.

```swift
import YYModelSwift     // Swift Package Manager
import YYModel          // Objective-C API, Swift Package Manager
// import YYModel2      // CocoaPods: both APIs are in this module

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

Existing Objective-C models keep using `yy_modelWithJSON:` / `yy_model(with:)`.
`Bridge/YYModelBridge.swift` is not part of the pod or the Swift package.

## Demo

```bash
cd Demo && make     # Objective-C T1–T17. Last run: 76 passed, 0 failed
swift test          # Swift Codable fixtures under Tests/YYJSONDecoderTests/Fixtures
```

## License

YYModel is available under the MIT license. See the LICENSE file for more info.

## Credits

Original YYModel by [ibireme](https://github.com/ibireme).
Modern iOS compatibility patches by [leeeeeeeefulong](https://github.com/leeeeeeeefulong).
