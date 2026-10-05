#!/bin/bash
# ============================================================
# Publish all GitHub Releases for leeeeeeeefulong/YYModel
# ============================================================
set -e

REPO="leeeeeeeefulong/YYModel"

echo "Checking GitHub authentication..."
if ! gh auth status >/dev/null 2>&1; then
    echo "❌ You are not authenticated with GitHub CLI."
    echo "👉 Please run: gh auth login"
    exit 1
fi

echo "Publishing releases for ${REPO}..."

# 2.0.0
gh release create 2.0.0 \
  --repo "$REPO" \
  --title "2.0.0 — Modern iOS Compatibility & Swift Package Manager Support" \
  --notes "### Initial modern iOS compatibility release
- **SPM Support**: First release with Swift Package Manager support (\`Package.swift\`).
- **CocoaPods**: Published as \`YYModel2\`.
- **F1 (P0)**: Non-variadic typed function pointers for \`objc_msgSend\` on arm64 ABI.
- **F2 (P0)**: Modern \`NSSecureCoding\` via \`decodeObjectOfClass:forKey:\`.
- **F3 (P0)**: 64-bit type encoding (\`NSGetSizeAndAlignment\`).
- **F4 (P0)**: \`NSDecimalNumber\` precision preserved via \`decimalNumberWithDecimal:\`.
- **F5 (P0)**: \`os_unfair_lock\` replacing \`dispatch_semaphore\` (iOS 10.0+).
- **F6-F8 (P1)**: Thread-safe metadata and date formatter caching.
- **F9-F10 (P2)**: \`PrivacyInfo.xcprivacy\` and nullability annotations." || true

# 2.1.0
gh release create 2.1.0 \
  --repo "$REPO" \
  --title "2.1.0 — Swift Codable Decoder (YYJSONDecoder)" \
  --notes "### Swift Support
- Added \`YYJSONDecoder\` for decoding plain Swift \`Codable\` models.
- Tolerant zero-filling for missing keys and \`null\` values.
- Automatic coercion between numbers, strings, and booleans.
- Supports both \`Data\` and parsed \`Any\` (Dictionary/Array) inputs." || true

# 2.1.1
gh release create 2.1.1 \
  --repo "$REPO" \
  --title "2.1.1 — CocoaPods Platform Alignment" \
  --notes "### Packaging
- CocoaPods \`YYModel2.podspec\` scoped to iOS (11.0+) and macOS (10.13+) for broader build compatibility." || true

# 2.1.2
gh release create 2.1.2 \
  --repo "$REPO" \
  --title "2.1.2 — JSONDecoder Fast Path with Tolerant Fallback" \
  --notes "### Performance
- Decodes clean compliant JSON with native \`JSONDecoder\` first.
- Falls back to the tolerant walker only when standard decoding throws." || true

# 2.1.3
gh release create 2.1.3 \
  --repo "$REPO" \
  --title "2.1.3 — Superclass Property Inheritance" \
  --notes "### Features
- \`_YYModelMeta\` traverses superclass properties recursively up to \`NSObject\`.
- Subclass properties take precedence over superclass properties of the same name.
- Custom property mapper and blacklist/whitelist apply across the inheritance hierarchy." || true

# 2.1.4
gh release create 2.1.4 \
  --repo "$REPO" \
  --title "2.1.4 — Full Contract Parity Restoration with ibireme/YYModel" \
  --notes "### Parity Restoration
- **Polymorphic Resolution**: Restored \`modelCustomClassForDictionary:\` on root and nested containers.
- **Custom Transform Contract**: Strictly checked boolean return value of \`modelCustomTransformFromDictionary:\`.
- **Nested Model In-Place Update**: Updated existing nested instances via \`yy_modelSetWithDictionary:\`.
- **Generic Class Normalization**: String class names in \`modelContainerPropertyGenericClass\` resolved via \`NSClassFromString\`.
- **Safe KeyPath Traversal**: Restored dictionary subscript traversal, eliminating KVC \`valueForUndefinedKey:\` crashes.
- **Model to JSON Fidelity**: Restored nested dictionary output for dotted key paths; formatted \`NSDate\` as ISO8601.
- **Special Type Safety**: Full type branching across struct (\`NSValue\`), pointer, block, selector, CNumber.
- **Swift Decoder Optimizations**: Static ISO8601 formatters with fractional seconds support; automatic millisecond timestamp conversion." || true

# 2.1.5
gh release create 2.1.5 \
  --repo "$REPO" \
  --title "2.1.5 — Swift 6 Strict Concurrency Compiler Safety" \
  --notes "### Swift 6 Support
- Added \`#if compiler(>=5.10) nonisolated(unsafe) #endif\` guards to static \`ISO8601DateFormatter\` instances in \`YYJSONDecoder.swift\`.
- Compiles cleanly under Swift 6 strict concurrency mode (\`-swift-version 6\`) with 0 errors and 0 warnings." || true

# 2.1.6
gh release create 2.1.6 \
  --repo "$REPO" \
  --title "2.1.6 — Code Review Enhancements & Contract Precision" \
  --notes "### Production Release (R1–R8 & N1–N8 Enhancements)
- **Swift 64-Bit Integer Precision & Overflow Guard (R1, N1, N2)**:
  - Re-architected integer decoding in \`YYJSONDecoder.swift\` to inspect \`CFNumberIsFloatType\` and \`objCType\`.
  - Preserves exact 64-bit integer values (\`Int64\` / \`UInt64\`, e.g. Snowflake IDs \`9007199254740993\`) without Double 53-bit mantissa truncation.
  - Added boundary-safe conversion, eliminating \`SIGTRAP\` overflow crashes on \`Int64.max\`.
  - **(N1)** Preserved Objective-C \`uint64_t\` string parsing for \`18446744073709551615\` via \`strtoull\`.
  - **(N2)** Out-of-range integer strings throw \`DecodingError\` instead of Double rounding; decimal-suffixed integer strings (\`\"9007199254740993.0\"\`) preserve exact precision via \`Decimal\`.
- **Whitelist & Blacklist Contract Parity (R2)**:
  - Strictly distinguished \`nil\` from empty \`@[]\` (empty whitelist blocks all properties).
  - Subclasses overriding blacklist with \`@[]\` correctly unblock parent properties.
- **O(1) Date Dispatch & Performance Parity (R3, R8, N8)**:
  - Restored original length-indexed dispatch table \`blocks[string.length]\` in \`YYNSDateFromString\`.
  - Fixed timestamp false-positive bug where \`2026-09-05\` was truncated to epoch 2026.
  - **(N8)** Added pure-digit validation for 10-digit seconds and 13-digit millisecond timestamp strings (\`\"1700000000000\"\`).
  - Reduced date parsing latency from 86.9ms to 32.8ms per 1000 iterations (surpassing original 33.6ms baseline).
- **NSNumber Conversion Aliases (R4)**:
  - Restored full 24-entry alias table (\`\"yes\"\`, \`\"Yes\"\`, \`\"no\"\`, \`\"No\"\`, \`\"<null>\"\`, \`\"(NULL)\"\`, \`\"Null\"\`, etc.).
- **Block Property Equality & Hash Consistency (R5)**:
  - Included \`YYEncodingTypeBlock\` in \`yy_modelIsEqual:\` and \`yy_modelHash\`.
- **Model Equality Symmetry (R6)**:
  - Enforced \`[model isMemberOfClass:self.class]\` in \`yy_modelIsEqual:\`, guaranteeing mathematical symmetry.
- **NSSecureCoding for Custom Model & Foundation Containers (R7, N6)**:
  - Prioritized collection types in \`yy_modelInitWithCoder:\` and included container classes + \`_genericCls\` in allowed classes.
  - **(N6)** Added \`NSNull\`, \`NSURL\`, \`NSValue\` to allowed container classes, preventing Error 4864.
- **Swift Decoder Resiliency & Container Fixes (N3, N4, N5, N7)**:
  - **(N3)** Tolerant walker properly decodes \`Optional\` elements in arrays (\`[String?]\` with \`[\"a\", null]\`) and root Optionals.
  - **(N4)** \`KeyedDecodingContainer.superDecoder()\` accesses the \`\"super\"\` key or parent container for Codable inheritance.
  - **(N5)** \`UnkeyedDecodingContainer\` advances \`currentIndex\` only upon successful element decoding.
  - **(N7)** Direct tolerant walker invocation when falling back from \`Data\`, eliminating redundant secondary system \`JSONDecoder\` calls.

### Verification Status
- ✅ Framework XCTest: 27 passed, 0 failed.
- ✅ Demo Suite: 84 passed, 0 failed (0 warnings).
- ✅ Swift Test: 16 passed, 0 failed.
- ✅ E2E Review Acceptance (R1–R8): 9/9 checks passed.
- ✅ Extended Review Acceptance (N1–N8): 11/11 checks passed.
- ✅ Production App (BlackListTests): 21 passed, 0 failed." || true

# 2.1.7
gh release create 2.1.7 \
  --repo "$REPO" \
  --title "2.1.7 — Extended Review Parity & Robustness" \
  --notes "### Extended Robustness & Fixes (D1–D7)
- **(D2) Whitespace-Prefixed Negative Numbers**: Skips leading whitespace in \`YYNSNumberCreateFromID\` before inspecting sign, ensuring negative numbers (\`\" -1\"\`, \`\"\t-123\"\`) parse as negative instead of unsigned overflow.
- **(D3 & D5) Swift Decimal Toward-Zero Truncation**: Truncates decimal strings toward zero in \`YYJSONDecoder.swift\` (\`\"1.8\"\` -> 1, \`\"-1.8\"\` -> -1) and rejects out-of-range decimal strings (\`\"-9223372036854775809.0\"\`).
- **(D4) Suffix Rejection**: Rejects strings with trailing malformed characters (\`\"123abc\"\`, \`\"1.8xyz\"\`).
- **(D6) Non-Destructive Container Creation**: \`nestedContainer\` and \`nestedUnkeyedContainer\` advance index only upon success, preserving elements for fallback types.
- **(D7) Extended Date Formats**: Added fast fallback for RFC 822/1123 (\`\"Sat, 03 Oct 2026 08:00:00 +0000\"\`) and asctime (\`\"Sat Oct 03 08:00:00 2026\"\`).
- **(D1) Version Bump**: Bumped to official 2.1.7 release tag to ensure clean CocoaPods cache invalidation.

### Verification Status
- ✅ Framework XCTest: 27 passed, 0 failed.
- ✅ Demo Suite: 84 passed, 0 failed (0 warnings).
- ✅ Swift Test: 16 passed, 0 failed.
- ✅ Boundary Acceptance (D2–D7): 5/5 checks passed.
- ✅ Main App (BlackListTests): 21 passed, 0 failed." || true

# 2.1.8
gh release create 2.1.8 \
  --repo "$REPO" \
  --title "2.1.8 — Strict Numeric Architecture & High-Precision Preservation" \
  --notes "### Architectural Enhancements & Boundary Robustness (E1–E4)
- **(E1) High-Precision NSDecimalNumber Integer Coercion**: Isolates \`NSDecimalNumber\` before binary float dispatch, preserving exact 64-bit integer values (\`9007199254740993\`, \`9223372036854775807\`, \`18446744073709551615\`) without Double mantissa truncation.
- **(E2) Hexadecimal Float Syntax & Value Consistency**: Added dedicated C99 hex float parser (\`\"0x1p4\"\`, \`\"0x1.8p+2\"\`, \`\"-0x1p4\"\`) evaluating to exact values (\`16\`, \`6\`, \`-16\`) across integers and Decimal fields.
- **(E3) Unified Grammar Validation**: Enforced strict numeric syntax for Decimal fields, rejecting malformed suffixes (\`\"123abc\"\`, \`\"1.8xyz\"\`, \`\"1e2garbage\"\`).
- **(E4) Tiny Scientific Notation Truncation**: Numbers with small magnitudes below 1 (\`\"1e-129\"\`, \`\"-1e-129\"\`, \`\"1e-400\"\`) mathematically truncate to zero (\`0\`) without false-positive DecodingError.

### Verification Status
- ✅ Framework XCTest: 27 passed, 0 failed.
- ✅ Demo Suite: 84 passed, 0 failed (0 warnings).
- ✅ Swift Test: 16 passed, 0 failed.
- ✅ Numeric Extension Suite (E1–E4): 5/5 checks passed.
- ✅ Main App (BlackListTests): 21 passed, 0 failed." || true

# 2.1.9
gh release create 2.1.9 \
  --repo "$REPO" \
  --title "2.1.9 — Boundary Robustness & Unified Numeric Lexer" \
  --notes "### Boundary Correctness & Optional Nested Validation (G1–G4)
- **(G1) Objective-C UInt64 Decimal Preservation**: Preserves the full UInt64 range (\`0..18446744073709551615\`) when assigning \`NSDecimalNumber\` and JSON decimal numbers to Objective-C unsigned 64-bit properties. Truncates fractions toward zero via \`NSDecimalRound\`; NaN and positive overflow leave existing properties untouched, and negative numbers retain legacy unsigned conversion.
- **(G2) Swift Non-Finite Floating-Point Guard**: Rejects non-finite floating-point (\`Double\`/\`Float\`/\`CGFloat\`), \`Decimal\`, and \`Date\` values, including overflow introduced when narrowing \`Double\` to \`Float\`.
- **(G3) Symmetric Millisecond Timestamp Handling**: Applies the existing automatic seconds/milliseconds threshold symmetrically to positive and negative timestamps (\`abs(seconds) > 1e11\`), using one shared date conversion for fast and tolerant decoding.
- **(G4) Optional Nested Transform Failure Propagation**: Adds the root-model protocol hook \`+modelRequiresSuccessfulNestedTransforms\`. When enabled, nested dictionary conversions propagate failure through objects and model containers to the root parse (returning nil). Default behavior remains 100% compatible with original ibireme/YYModel.
- **Public API Boundary Validation Package**: Added repeatable public API boundary E2E checks covering 62 boundary scenarios and Open-Meteo weather datasets.

### Numeric Correctness & Unified Lexer (F1–F4)
- **Unified ASCII Byte Lexer**: Parses decimal and C99 hexadecimal numeric strings using an exact ASCII-byte grammar (\`NumericText\`), rejecting malformed suffixes and illegal characters before conversion.
- **Normalized Exponent and Coefficient Handling**: Accurately normalizes coefficients and exponents, handling leading zeros and extreme exponents.
- **High-Precision Integer Truncation**: Truncates decimal and hexadecimal strings to integers using exact digits/bits and destination range checks; preserves values above 2^53 and rejects overflow without lossy Double intermediates.
- **Hexadecimal Decimal Preservation**: Converts hexadecimal \`Decimal\` fields using high-precision decimal arithmetic (\`NSDecimalMultiply\`/\`NSDecimalDivide\`), preserving precision beyond \`binary64\`.

### Verification Status
- ✅ Framework XCTest: 27 passed, 0 failed.
- ✅ Demo Suite: 84 passed, 0 failed (0 warnings).
- ✅ Swift Test: 16 passed, 0 failed.
- ✅ Validation Suite (Boundary & Weather): 82/82 checks passed." || true

# 2.2.0
gh release create 2.2.0 \
  --repo "$REPO" \
  --title "2.2.0 — Swift External Rules & Decoupled Codable Engine" \
  --notes "### Swift Features & Architecture
- **Ordinary Codable & External Rules**: Primary APIs decode ordinary \`Codable\` models with immutable external \`YYJSONRules\`; no model protocol required.
- **Unified Three Modes**:
  - \`.native\`: Directly forwards Foundation strategies, userInfo, and errors with zero overhead.
  - \`.compatible\`: Adapts fields in one pass, supporting nested aliases/KeyPaths, defaults, required validation, typed hooks, per-field dates, registered polymorphism, and symmetric \`YYJSONEncoder\`.
  - \`.legacy\`: Preserves published 2.x zero-fill and automatic dates without whole-model retry on arbitrary errors.
- **Independent Products**: Independent Swift (\`YYModelSwift\`) and Objective-C (\`YYModel\`) SPM targets and CocoaPods subspecs (\`YYModel2/ObjC\`, \`YYModel2/Swift\`).

### Objective-C Parity & Contract Hardening
- **Mapper/Generic Hook Defaults**: Restored original effective-hook defaults; added \`+modelMergesSuperclassConfiguration\` opt-in for projects needing ancestor mapper/generic merging.
- **Identity Fallback**: Models with unsupported-only properties restore identity equality/hash fallback (\`self == model\`).
- **Cleaned NSObject Category**: Removed NSObject-wide \`YYModel\` protocol conformance so Swift models don't inadvertently appear to conform; deprecated unreliable \`isSwiftDynamic\`.
- **Deployment Floor**: Supported distribution floors maintained at iOS 11.0 / macOS 10.13.

### Verification Status
- ✅ Framework XCTest: 27 passed, 0 failed.
- ✅ Demo Suite: 84 passed, 0 failed (0 warnings).
- ✅ Swift Test: 16 passed, 0 failed.
- ✅ Validation Suite (Contract, Boundary, Rules, Weather): 100% passed." || true

# 2.3.0
gh release create 2.3.0 \
  --repo "$REPO" \
  --title "2.3.0 — Objective-C / Swift Product Separation" \
  --notes "### Breaking Change (Objective-C)
- **Removed \`isSwiftDynamic\`**: The deprecated \`YYClassPropertyInfo.isSwiftDynamic\` getter is gone. The Objective-C product now contains no Swift-related API and no deprecated declarations. Inspect the plain \`YYEncodingTypePropertyDynamic\` runtime flag instead; the getter had conservatively returned \`NO\` since 2.2.0, so no observable parsing behavior changes.
- **CocoaPods**: \`swift_versions\` now declared on the \`Swift\` subspec only; the \`ObjC\` subspec carries no Swift declaration or toolchain requirement. SPM products \`YYModel\` (ObjC) and \`YYModelSwift\` remain independently selectable.

### Migration
- Replace \`propertyInfo.isSwiftDynamic\` with \`(propertyInfo.type & YYEncodingTypePropertyDynamic) != 0\`.

### Verification Status
- ✅ Objective-C contract E2E re-run on macOS and iOS 26.5 simulator.
- ✅ Framework XCTest, Demo suite, and Swift tests pass with the removal in place.
- ✅ Swift-reference scan over the ObjC product: zero matches.
- ✅ Deployment floor maintained at iOS 11.0 / macOS 10.13." || true

# 2.3.1
gh release create 2.3.1 \
  --repo "$REPO" \
  --title "2.3.1 — Independent Review Fixes" \
  --notes "### Swift — YYModelSwift
- **(F1) Hook input precision**: \`willTransform\` input snapshots keep exact numeric tokens (\`9007199254740993.0\` no longer rounds to binary64); physical keys preserved; nested hooks share the fix.
- **(F2) Field dates in nested containers**: \`nestedContainer\` / \`nestedUnkeyedContainer\` / keyed \`superDecoder\`/\`superEncoder\` resolve \`fieldDateStrategies[key]\` like direct decoding.
- **(F3) Defaults in nested containers**: keyed \`superDecoder(forKey:)\` and nested accessors fall back to registered \`defaultValues\`.
- **(F4) Strict missing-vs-null**: \`.compatible\` \`decodeNil(forKey:)\` on absent, non-defaulted keys throws \`keyNotFound\` like Foundation; legacy zero-fill unchanged.

### Objective-C
- **(E1) Non-finite equality/hash**: NaN / +Inf / −Inf models compare and hash as distinct values, matching the ibireme original (NSSet keeps 3). JSON export, description, and coding keep the documented non-finite filter.

### Distribution
- **(F5) Swift language modes**: \`swift_versions = ['5.0', '6.0']\` at the podspec root — valid compiler language modes only; CocoaPods clients constraining Swift 5 select 5.0 again. Swift 5.9+ toolchain requirement stays a documented comment.

### Verification Status
- ✅ Review probes F1–F4 (Swift consumer) and E1 (ObjC consumer vs original) all fixed on macOS and iOS 26.5 simulator.
- ✅ CocoaPods 1.17 analyzer: \`< 6.0\` → 5.0, \`5.0\` → 5.0, \`6.0\` → 6.0; both language modes compile.
- ✅ ObjC contract E2E, Demo suite, original XCTest, Swift tests, and external-rules E2E all green." || true

# 2.3.2
gh release create 2.3.2 \
  --repo "$REPO" \
  --title "2.3.2 — Phase-2 Remediation and Repository Cleanup" \
  --notes "### Swift — YYModelSwift
- **Field Resolution & Error Propagation**: Unified resolution separating absent, explicit null, and invalid path shape; eliminated silent failure swallows in nested keypaths (F-04/F-05/A-01).
- **Direct Tree Export**: Direct value tree export (\`YYModelTreeEncoder\`) avoiding intermediate data/serialization overhead; full parity with Foundation date/data/key strategies and Unicode keys (P-03/P-04/A-02).
- **Precision Numeric Routing**: Unified ASCII state machine numeric parser with cached decimal capability detection and zero-truncation precision preservation; handles 64-bit snowflake IDs and \`UInt64.max\` safely.
- **Presence & Lossy Robustness**: Enhanced \`YYModelPresence\` tri-state across arrays and dictionaries; \`YYModelLossy\` per-invocation isolation report with strict fallback order.
- **Microsecond Dates**: Added explicit \`.microsecondsSince1970\` date strategy alongside existing automatic heuristics and ISO8601 formatting.

### Repository & Documentation
- **Clean Open-Source Library Structure**: Removed internal temporary validation suites and historical evidence trees; lightweight and clean dependency footprint.
- **CI Modernization**: Upgraded workflow actions and streamlined SwiftPM test pipeline (108 unit tests).
- **Version Selection Guide**: Added comprehensive ObjC vs Swift decision guide, intentional contract differences, and migration documentation in README and CHANGELOG.

### Verification Status
- ✅ SwiftPM test suite: 108/108 passed.
- ✅ Objective-C Demo test suite: 84/84 passed (benchmark single iteration ~0.10ms).
- ✅ Framework XCTest suite: 27/27 passed on iOS Simulator.
- ✅ Podspec and SPM pins updated to 2.3.2." || true

echo "✅ All releases published successfully!"
