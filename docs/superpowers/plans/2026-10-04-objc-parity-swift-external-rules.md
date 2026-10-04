# OC parity and Swift external rules implementation plan

**Goal:** Close the independently reproduced OC regressions and provide ordinary Codable models with decoder-owned YYModel features.

**Architecture:** Restore original OC defaults; make configuration merging opt-in. Swift uses a native Foundation path and one contextual container adapter, with immutable external type rules. Published no-argument decoding retains legacy zero-fill/date behavior but stops whole-model retries.

**Tech Stack:** Objective-C runtime, Foundation, Swift 5.9/6, existing SPM and standalone simulator runners; no additional dependencies.

**Spec:** `docs/OBJC-INDEPENDENT-REVIEW-20261004.md`, `docs/SWIFT-ARCHITECTURE-REVIEW-20261004.md`.

## Constraints

- Only this component repository; no PPLive source, tests or dependency changes.
- Ordinary Codable is sufficient; YYModelCodable remains optional convenience compatibility.
- No private Swift memory layout, macros, global business-rule cache or swallowed business errors.
- Do not move released tags. Preserve historical measurements and identify new receipts separately.
- Latest user instruction: complete implementation and review before running one consolidated verification; no new unit tests.

## OC deliverable

Files: `YYModel/NSObject+YYModel.{h,m}`, `YYModel/YYClassInfo.{h,m}`, `docs/OBJC-MIGRATION.md`, standalone acceptance under `Validation`.

- [x] Count only participating properties in hash/equality; unsupported-only objects use identity.
- [x] Use effective class mapper/generic hook by default; add `modelMergesSuperclassConfiguration` opt-in.
- [x] Remove category-wide YYModel conformance, deprecate unreliable Swift detection and correct encoding/PAC claims.
- [x] Keep existing precision/date/secure-container improvements and document extension boundaries.

## Swift deliverable

Files: `YYModelSwift/YYJSONRules.swift`, `YYJSONEncoder.swift`, existing decoder/encoder/configuration/value/polymorphic files.

- [x] Add `.native`, `.compatible`, `.legacy` modes; forward all native strategies and userInfo.
- [x] Add `YYJSONRules.forType(_:configure:)` immutable snapshots; rules are keyed by metatype and CodingKey string.
- [x] Propagate invocation context through Optional, arrays, sets, dictionaries, super containers and custom Codable.
- [x] Strict enhanced missing/null handling, explicit defaults/zero-fill, first-existing alias semantics, required validation, per-field dates and typed validation/transformation.
- [x] External polymorphic registration for ordinary Codable payloads, preserving custom errors and one initialization.
- [x] Same-rule encoder with deterministic output aliases, nested paths and conflict rejection.
- [x] Keep optional model-protocol helpers on this engine; remove global schema/variant cache.

## Verification and delivery

Files: `Validation/external-rules/FAILURE-MODES.md`, public API E2E and runner; README/CHANGELOG and final dated delivery report.

- [x] Write failure criteria and E2E consumer before production Swift edits; defer execution.
- [x] Finish all source, compile both Swift language modes, then review source against failure criteria.
- [x] Run consolidated public E2E on macOS and iOS 26.5 simulator, unchanged existing Swift tests and original OC contract coverage.
- [x] Measure native/compatible Data decoding with the same full weather model, input and oracle; adjacent paired samples, no builds during timing.
- [x] Run final OC original/current comparisons on final source, store source hashes and samples.
- [x] Update migration/usage documentation and prepare reviewed Git delivery; physical-device numbers remain unverified. Git completion is established by the delivered commit and remote SHA check, not an embedded self-referential commit hash.

## Execution notes

- Completed business implementation before concentrated verification; independent review closed Optional/raw strategy/key export/path issues.
- Initial timing exposed integer-collection overhead; Decimal-first lightweight scalar conversion replaced repeated model adaptation. Added finite-collection and raw strict-null gates before those fixes.
- No-argument encoder/decoder both use legacy date semantics; public Date round-trip gate passed.
- Final report and portable JSON receipts: `docs/DELIVERY-EXTERNAL-RULES-20261004.md`, `Validation/receipts/external-rules-20261004.json`.
- Native execution retains Foundation performance on measured weather data. Enhanced execution has documented costs; no general zero-overhead or physical-device claim.
