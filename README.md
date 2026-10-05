# YYModel

High performance JSON model framework for iOS/macOS.

> **Fork maintained with modern iOS compatibility fixes.**
> Original by [ibireme](https://github.com/ibireme). This fork retains the original Objective-C entry points and adds modern toolchain fixes and a Swift Decodable API. Behavioral extensions and verified limits are documented in the migration guide.

[![CocoaPods](https://img.shields.io/cocoapods/v/YYModel2.svg)](https://cocoapods.org/pods/YYModel2)
[![License](https://img.shields.io/cocoapods/l/YYModel2.svg)](https://github.com/leeeeeeeefulong/YYModel/blob/master/LICENSE)
[![Platform](https://img.shields.io/cocoapods/p/YYModel2.svg)](https://cocoapods.org/pods/YYModel2)

Current release: **2.3.1** (`pod 'YYModel2', '2.3.1'`, SPM `from: "2.3.1"`).

---

## Which Version Should I Use?

This repository ships two fully separate products. They share no mapping table, and the Swift product is **not a drop-in replacement** for the Objective-C one.

| | `YYModel` — Objective-C | `YYModelSwift` — Swift `Codable` |
|---|---|---|
| Model | `NSObject` subclass with `@property` | `struct` conforming to `Codable` |
| Semantics | Reference semantics; runtime property metadata and type encoding | Value semantics; compiler-synthesized `CodingKeys` |
| Configuration | Class hooks: `modelCustomPropertyMapper`, `modelContainerPropertyGenericClass`, blacklist/whitelist | Immutable `YYJSONRules` snapshot per call; **no process-wide cache** |
| Intrusion | Base class plus class methods | No base class, no required protocol, no property wrapper or macro |
| Engine | Own Objective-C runtime parser | Foundation `JSONDecoder` / `JSONEncoder` plus field adaptation |

Choose **Objective-C** when models are already `NSObject` subclasses, when you depend on runtime introspection / KVC, or when you must mutate an existing instance in place.

Choose **Swift** when models are plain structs, when you want value semantics and no global caches, or when you need `Codable` interoperability with the rest of the Swift ecosystem.

### Known Differences (the Swift version is not a behavior mirror)

Migrating from the Objective-C product to the Swift product is **not** a drop-in operation. The following contracts intentionally differ:

| Behavior | Objective-C product | Swift product |
|---|---|---|
| String → number (`"30"` → `30`) | tolerant by default | `.native` rejects with `typeMismatch`; coercion only through the explicit `.compatible` / `.legacy` modes |
| Number → `Bool` (`2` → `true`) | tolerated | **throws** — only `0` / `1` (and common boolean strings) are accepted |
| Integer overflow | tolerant conversion | **throws** (`typeMismatch` at the offending `codingPath`); never silently truncated |
| `String` → `Data` | UTF-8 style conversion | **Base64** decode (Foundation contract) |
| `Date` export / auto parse | original formats | exports Unix **seconds**; `.automatic` treats `abs(value) > 1e11` as milliseconds (including negative values) |

The full per-behavior table and the configurable escape hatches live in [Swift external rules](docs/SWIFT-EXTERNAL-RULES.md); the Objective-C side is covered by the [OC migration guide](docs/OBJC-MIGRATION.md) and the [upgrade & compatibility guide](docs/UPGRADE-COMPAT-GUIDE-20261004.md).

### Swift Capability Boundaries

Some Objective-C capabilities have no Swift equivalent and are **not** provided by the Swift product. These are language limits, not missing work:

| Objective-C capability | Swift status |
|---|---|
| Write into an existing instance in place (`yy_modelSetWithDictionary:`) | Not possible — structs are value types; decoding always returns a new value |
| Runtime property metadata / type encoding | None — `Mirror` is read-only reflection and exposes no type encodings |
| Runtime assignment to arbitrary members / KVC | None — there is no runtime setter for struct members |
| C `struct` / `union` / pointer / `SEL` / `Block` members | Not supported — use Swift types instead |
| Object identity in copy / hash / equality | Value semantics from the Swift standard library; the framework does not fake object identity |

`YYModelCodable` remains an optional convenience over the same engine; plain `Codable` plus `YYJSONRules` is the recommended entry point. See [Swift model usage](docs/SWIFT-MODEL.md).

---

## Modern iOS Compatibility (2026.09)

This fork addresses verified modern Xcode / Clang compatibility issues. Passing the component checks does not establish compatibility with every model, payload or device.

> All API availability claims below are verified against [Apple Developer Documentation](https://developer.apple.com/documentation/).

### Maintained behavior and extensions

| Area | Current behavior |
|------|------------------|
| Runtime calls and cache | Explicit msgSend typedefs and os_unfair_lock. Original YYModel already had typed casts and metadata caches; no standalone PAC/performance claim. |
| Type encoding | l/L size queries retained; these encodings are 32-bit on Apple arm64, while `@encode(long)` uses q. |
| Numeric precision | UInt64 and NSDecimalNumber boundary corrections, with documented tolerant OC conversion semantics. |
| Secure decoding | Allowed property/container classes; custom members still need NSSecureCoding and correct declared classes. |
| Dates | Original formats plus explicit fork extensions; ISO output access is serialized. Automatic units remain heuristic. |
| Runtime language metadata | `isSwiftDynamic` was removed in 2.3.0: the ObjC product contains no Swift-related API. Inspect `YYEncodingTypePropertyDynamic` for the plain runtime Dynamic flag. |
| Privacy manifest | Component-only declarations; no invented ObjCRuntime required-reason category. See [Apple TN3183](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest). |

**Supported distribution floors: iOS 11.0 / macOS 10.13.** Core uses os_unfair_lock (iOS10/macOS10.12) and coder allowed-class methods; complete archive convenience methods used by callers/tests are not a Core dependency. Current SDK may warn about the older deployment floor.

### API Compatibility

Existing Objective-C method signatures are retained. Mapper/container hooks now follow original subclass override defaults. Ancestor merging and strict nested transform validation are explicit opt-ins. See [OC migration](docs/OBJC-MIGRATION.md) for fork migration and documented limits.

```objc
// Existing Objective-C entry points
User *user = [User yy_modelWithJSON:jsonString];
NSDictionary *json = [user yy_modelToJSONObject];
NSData *data = [user yy_modelToJSONData];
NSString *str = [user yy_modelToJSONString];
NSArray *users = [NSArray yy_modelArrayWithClass:[User class] json:jsonArray];
```

### Verified Test Results — YYModel 2.1.7 (historical)

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

### 2.1.9 Component Performance Verification (historical)

> **Architecture note**: this table was measured on the 2.1.9 decoder, which still tried native `JSONDecoder` first and fell back to the tolerant decoder on failure. That native-first architecture was **removed** in 2.2.0: the no-argument `YYJSONDecoder()` now runs the field-adaptation path directly and costs about 5× native `JSONDecoder` on standard data. Use `.native` mode for Foundation-level speed.

Measured on Apple M1 Max / arm64, macOS 26.7 and iOS 26.5 Simulator, Xcode 26.6 / Swift 6.3.3, OC `-O2` and Swift `-O`. The offline Open-Meteo clean fixture is 15,785 bytes with 3 cities and 288 hourly rows. No business App is used.

Main matrix medians, **milliseconds per Data → Model operation**:

| Runtime | ibireme OC | 2.1.9 OC | Swift → 2.1.9 OC | Native JSONDecoder | YYJSONDecoder |
| --- | --- | --- | --- | --- | --- |
| macOS | 0.266003 | 0.257716 | 0.279094 | 0.882299 | 0.917215 |
| iOS Simulator | 0.305095 | 0.298042 | 0.300604 | 0.840059 | 0.854160 |

OC and Swift have different array representations: OC retains Foundation values, while the Swift DTO builds typed optional numeric arrays. Cross-language ratios therefore include different model work. Original/fork OC, Native/YY Swift and OC/Swift callers each use identical models within their respective comparisons.

The complete matrix contains 96 paths per runtime with 14 batch-average samples each. It retains slower first-round results; adjacent ABBA remeasurement of all 10 OC workloads found changes from −8.39% to +8.47% relative to fixed ibireme commit `c7df275`. No persistent regression above the predeclared +10% observation line was reproduced; this is neither a statistical equivalence test nor a universal speedup claim.

In the 2.1.9 architecture, `YYJSONDecoder` tried native `JSONDecoder` first, then its tolerant decoder after failure; dirty data cost about 5× clean decoding in this fixture. OC setters are invoked via typed `objc_msgSend`; metadata caching was already present in the original. No independent evidence attributes these timings to direct memory writes, a particular lock, or a new parsing algorithm.

**Known date limits:** configure Swift `JSONEncoder.dateEncodingStrategy = .secondsSince1970` for YY date round-trips. Objective-C negative millisecond timestamps remain unsupported or misinterpreted; Swift timestamp handling is separate.

---

## Features

- **High performance**: See benchmarks above. No runtime code generation, no method swizzling.
- **Full type support**: All JSON types, all Objective-C types, all C number types, struct, union, pointer, SEL, Block.
- **Thread safe**: All caching uses `os_unfair_lock`.
- **Customizable**: Property mapper, container generic class, custom transform, blacklist/whitelist.
- **NSSecureCoding**: Full support for secure archiving.
- **Debug friendly**: `-yy_modelDescription` returns all property values.

## Requirements

- **iOS 11.0+** / **macOS 10.13+** (supported distribution policy)
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
    .package(url: "https://github.com/leeeeeeeefulong/YYModel", from: "2.3.1")
]
```

> SPM is the long-term supported distribution channel. CocoaPods trunk closes 2026-12-02.

### CocoaPods

```ruby
# New pod name (original YYModel owned by ibireme on trunk)
pod 'YYModel2', '2.3.1'
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

### Swift API: ordinary Codable + external rules

The main APIs are `YYJSONDecoder`, `YYJSONEncoder` and immutable `YYJSONRules`. No YY model protocol, property wrapper, macro or NSObject is required. Use `.native` for direct Foundation semantics; `.compatible` adds field-local conversions, aliases/KeyPaths, explicit defaults, required validation, typed hooks, dates, registered polymorphism and symmetric export. `YYModelCodable` remains optional convenience on the same engine.

```swift
struct User: Codable { let id: UInt64; let name: String; let age: Int? }
let rules = try YYJSONRules().forType(User.self) {
    $0.mapper = ["id": ["id", "uid"], "name": "profile.name"]
    $0.requiredProperties = ["id"]
}
let decoder = YYJSONDecoder(mode: .compatible, rules: rules)
let user = try decoder.decode(User.self, from: data)
let output = try YYJSONEncoder(mode: .compatible, rules: rules).encode(user)
```

The no-argument `YYJSONDecoder()` retains legacy zero-fill and automatic-date behavior. Enhanced modes no longer retry an entire model after an arbitrary error. `.native` rejects YY rules instead of silently ignoring them. See [Swift usage and limits](docs/SWIFT-EXTERNAL-RULES.md), [OC migration](docs/OBJC-MIGRATION.md), and [verified upgrade guide](docs/UPGRADE-COMPAT-GUIDE-20261004.md).

> **Not a drop-in replacement for `JSONDecoder`.** In `.compatible`/`.legacy` mode, numeric strings are coerced (`"30"` → `30`), a non-zero numeric `Bool` (only `0`/`1`) and common string booleans are tolerated, integers still **throw on overflow** (`typeMismatch` at the offending codingPath — never silently rounded), and `Data` stays Base64 (C4). Automatic dates read Unix seconds and treat `|timestamp| > 1e11` as milliseconds (including negative timestamps); implausible-magnitude dates record a `"implausible-date-magnitude"` reason in `YYModelCoercionReport` (D1). These are deliberate contracts, not missing features — the full per-behavior table lives in the [Swift rules doc](docs/SWIFT-EXTERNAL-RULES.md).

SPM products `YYModel` and `YYModelSwift` remain independent. CocoaPods provides `YYModel2/ObjC` and `YYModel2/Swift`; default includes both.

### Lossy arrays and loss reports

Array decode is strict by default (a single bad element fails the whole array,
matching Foundation). Skip bad elements explicitly — either per-property with
`lossy(\.field)` rules, or at the top level with `decodeLossyArray`. Skipped
elements are **never silent**; each one is recorded in a `YYModelLossReport`.

The report is most convenient through `decodeWithReport`, which creates an
isolated report for that one call and returns it alongside the value:

```swift
let (response, report) = try YYJSONDecoder(mode: .compatible, rules: rules)
    .decodeWithReport(Response.self, from: data)
// response.results == [Item(id:1), Item(id:2)]  — "bad" skipped
// report.losses    == [results[1]...]
if !report.losses.isEmpty {
    print("skipped \(report.losses.count) bad element(s): \(report.losses)")
}
```

For a top-level array, `decodeLossyArray` needs no rule configuration at all:

```swift
let (values, report) = try YYJSONDecoder.compatible()
    .decodeLossyArray([Int].self, from: data)
// values == [1, 3], report.losses.count == 1, report.losses.first?.property == "(root)"
```

You may also install your own `YYModelLossReport` into `decoder.userInfo[YYModelLossReport.key]`
to collect losses across one decode when you are not using the `decodeWithReport`
return value; `decodeWithReport` is the recommended way because it isolates the report
per call and always returns it.

### Published compatibility APIs (introduced 2.2.0)

`YYJSONDecoder` accepts `Data` or an already parsed object. Swift models stay plain `Codable` structs and do not adopt a YYModel protocol. Missing keys and JSON `null` become `0`, `""`, `false`, `[]`, or an empty nested object. Strings, numbers, and bools are coerced. Rename keys with `CodingKeys`. `URL` and raw-value enums have no zero value; make those properties optional when the key may be absent. A value that cannot be coerced throws.

Mixed ObjC + Swift usage is supported by importing the two SPM products (or the single `YYModel2` pod) side by side; there is no separate bridge file to ship.

#### 1. Objective-C only

Use this from `.m` files. The parser is `yy_modelWithJSON:` / `yy_modelWithDictionary:`.

```objc
#import "YYModel.h"   // or @import YYModel2; when the pod is a module

User *user = [User yy_modelWithJSON:jsonString];
NSArray *users = [NSArray yy_modelArrayWithClass:[User class] json:data];
```

| Distribution | Import |
|--------------|--------|
| ✅ CocoaPods `YYModel2` 2.3.0 | `#import "YYModel.h"` or `@import YYModel2;` |
| ✅ SPM product `YYModel` | `#import <YYModel/YYModel.h>` |

#### 2. Swift only

Ordinary Codable models use YYJSONDecoder with optional external rules (`YYJSONRules`). YYModelCodable shortcuts are optional.

```swift
import YYModelSwift          // SPM product YYModelSwift
// import YYModel2           // CocoaPods 2.3.0: YYJSONDecoder is in this module

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
| ✅ CocoaPods `YYModel2` 2.3.0 | `import YYModel2` | `YYJSONDecoder` |

SPM keeps the Swift decoder in its own target because a Swift package target cannot mix `.swift` and `.m`.

#### 3. Mixed

Use this when one Swift file both decodes new `Codable` structs and fills existing Objective-C models.

```swift
import YYModel                // SPM: Objective-C yy_model
import YYModelSwift           // SPM: YYJSONDecoder
// CocoaPods 2.3.0: a single `import YYModel2` exposes both.

let level = try YYJSONDecoder().decode(Level.self, from: data)
let user = User.yy_model(withJSON: jsonString)
let users = NSArray.yy_modelArray(with: User.self, json: data) as? [User]
```

| Distribution | What you import | What you call |
|--------------|-----------------|---------------|
| ✅ CocoaPods `YYModel2` 2.3.0 | `import YYModel2` | `YYJSONDecoder` and `yy_model(withJSON:)` / `yy_modelArray(with:json:)` |
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
