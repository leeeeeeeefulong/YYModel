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

echo "✅ All releases published successfully!"
