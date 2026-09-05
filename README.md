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
| `os_unfair_lock` | **10.0+** | **10.12+** | **Core** — Thread-safe caches (F5, F6, F8) |
| `NSSecureCoding` | **6.0+** | **10.8+** | **Core** — Secure archiving (F2) |
| `decodeObjectOfClass:forKey:` | **6.0+** | **10.8+** | **Core** — Type-safe unarchiving (F2) |
| `NSGetSizeAndAlignment` | 2.0+ | 10.0+ | **Core** — Type encoding size (F3) |
| `dispatch_once` | 4.0+ | 10.6+ | **Core** — One-time initialization |
| `NSJSONSerialization` | 5.0+ | 10.7+ | **Core** — JSON parsing |
| `archivedDataWithRootObject:requiringSecureCoding:error:` | 11.0+ | 10.13+ | Demo tests only (with `@available` fallback) |
| `NSURLSession` | 7.0+ | 10.9+ | Demo tests only |

**Minimum deployment target: iOS 10.0 / macOS 10.12** (constrained by `os_unfair_lock`).

> APIs requiring iOS 11.0+ are only used in the test demo with `@available` fallbacks. The core library has no iOS 11.0+ dependency.

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

Tested against live [JSONPlaceholder API](https://jsonplaceholder.typicode.com) with 76 test cases:

```
╔═══════════════════════════════════════════════════╗
║     YYModel Verification Test                    ║
║     API: JSONPlaceholder (typicode.com)           ║
╚═══════════════════════════════════════════════════╝

  T1  ✅ Basic Types        — NSString/NSNumber/BOOL/int
  T2  ✅ Nested Objects     — Address → Geo recursive
  T3  ✅ String Arrays      — NSObject generic parsing
  T4  ✅ Object Arrays      — [Post] from /posts API
  T5  ✅ Key-Path Mapping   — company.name → companyName
  T6  ✅ Multi-Key Fallback — @[@"website",@"homepage",@"url"]
  T7  ✅ Property Blacklist — internalNote ignored
  T8  ✅ Custom Transform   — email → uppercase
  T9  ✅ Decimal Precision  — NSDecimalNumber "99999999.9999999999"
  T10 ✅ NSSecureCoding     — Archive/Unarchive round-trip
  T11 ✅ Model Copy         — yy_modelCopy independent
  T12 ✅ Hash & Equal       — yy_modelHash / yy_modelIsEqual
  T13 ✅ Full Round-Trip    — Model → JSON → Model
  T14 ✅ Null/Missing       — null→nil, missing→default, wrong type→safe
  T15 ✅ Date Parsing       — ISO8601 / unix timestamp / ms timestamp
  T16 ✅ Live API (10 users) — All fields parsed, key-path 100%
  T17 ✅ Performance        — Benchmark passed

  RESULTS: ✅ 76 passed  ❌ 0 failed
```

### Performance (Apple M-series)

| Operation | 1000 iterations | Per iteration |
|-----------|----------------|---------------|
| JSON → Model | 100ms | **0.10ms** |
| Model → JSON | 25ms | **0.025ms** |
| Full round-trip | 128ms | **0.13ms** |

YYModel remains one of the fastest JSON model frameworks for Objective-C.

---

## Features

- **High performance**: See benchmarks above. No runtime code generation, no method swizzling.
- **Full type support**: All JSON types, all Objective-C types, all C number types, struct, union, pointer, SEL, Block.
- **Thread safe**: All caching uses `os_unfair_lock`.
- **Customizable**: Property mapper, container generic class, custom transform, blacklist/whitelist.
- **NSSecureCoding**: Full support for secure archiving.
- **Debug friendly**: `-yy_modelDescription` returns all property values.

## Requirements

- **iOS 10.0+** / **macOS 10.12+** (required by `os_unfair_lock`)
- watchOS 3.0+ / tvOS 10.0+
- Xcode 14+ (modern Clang fully supported)
- ARC

## Installation

### CocoaPods

```ruby
pod 'YYModel', '~> 1.0.5'
```

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

### Swift Codable Bridge

For new Swift code, use `Codable` directly. For mixing ObjC models with Swift:

```swift
import YYModel

// Wrap ObjC model in Codable pipeline
struct APIResponse: Codable {
    let data: YYModelWrapper<OldObjCUser>
}

// Decode ObjC model from Swift
let user = OldObjCUser.yy_model(withJSON: jsonString)

// Migrate legacy NSCoding archives
let migrated = OldUser.migrateLegacyArchive(from: legacyData)
```

See `Bridge/YYModelBridge.swift` for full API.

## Demo

See `Demo/` directory for a complete test suite that validates all YYModel features against the live JSONPlaceholder API.

```bash
cd Demo
make        # build and run all 76 tests
```

## License

YYModel is available under the MIT license. See the LICENSE file for more info.

## Credits

Original YYModel by [ibireme](https://github.com/ibireme).
Modern iOS compatibility patches by [leeeeeeeefulong](https://github.com/leeeeeeeefulong).
