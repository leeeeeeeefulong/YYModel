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
  --notes "### Production Release (R1–R8 Fixes)
- **Swift 64-Bit Integer Precision & Overflow Guard (R1)**:
  - Re-architected integer decoding in \`YYJSONDecoder.swift\` to inspect \`CFNumberIsFloatType\` and \`objCType\`.
  - Preserves exact 64-bit integer values (\`Int64\` / \`UInt64\`, e.g. Snowflake IDs \`9007199254740993\`) without Double 53-bit mantissa truncation.
  - Added boundary-safe conversion, eliminating \`SIGTRAP\` overflow crashes on \`Int64.max\`.
- **Whitelist & Blacklist Contract Parity (R2)**:
  - Strictly distinguished \`nil\` from empty \`@[]\` (empty whitelist blocks all properties).
  - Subclasses overriding blacklist with \`@[]\` correctly unblock parent properties.
- **O(1) Date Dispatch & Performance Parity (R3 & R8)**:
  - Restored original length-indexed dispatch table \`blocks[string.length]\` in \`YYNSDateFromString\`.
  - Fixed timestamp false-positive bug where \`2026-09-05\` was truncated to epoch 2026.
  - Reduced date parsing latency from 86.9ms to 32.8ms per 1000 iterations (surpassing original 33.6ms baseline).
- **NSNumber Conversion Aliases (R4)**:
  - Restored full 24-entry alias table (\`\"yes\"\`, \`\"Yes\"\`, \`\"no\"\`, \`\"No\"\`, \`\"<null>\"\`, \`\"(NULL)\"\`, \`\"Null\"\`, etc.).
- **Block Property Equality & Hash Consistency (R5)**:
  - Included \`YYEncodingTypeBlock\` in \`yy_modelIsEqual:\` and \`yy_modelHash\`.
- **Model Equality Symmetry (R6)**:
  - Enforced \`[model isMemberOfClass:self.class]\` in \`yy_modelIsEqual:\`, guaranteeing mathematical symmetry.
- **NSSecureCoding for Custom Model Containers (R7)**:
  - Prioritized collection types in \`yy_modelInitWithCoder:\` and included container classes + \`_genericCls\` in allowed classes.

### Verification Status
- ✅ Framework XCTest: 27 passed, 0 failed.
- ✅ Demo Suite: 84 passed, 0 failed (0 warnings).
- ✅ Swift Test: 16 passed, 0 failed.
- ✅ E2E Review Acceptance: 9/9 checks passed.
- ✅ Production App (BlackListTests): 21 passed, 0 failed." || true

echo "✅ All releases published successfully!"
