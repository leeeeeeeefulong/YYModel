# Failure criteria written before Swift implementation

1. Ordinary Codable root/array/dictionary/Optional loses nested type rules.
2. Separate decoder rule sets leak into one another or a global cache.
3. Native mode ignores enhanced rules, changes Foundation dates/keys/Data/userInfo/custom errors, or retries a model.
4. Enhanced mode retries a custom model or replaces its business error.
5. Missing/null required scalars silently become valid zero; Optional defaults overwrite explicit null unintentionally.
6. Aliases have unstable precedence; null first alias silently selects later alias; malformed intermediate path crashes.
7. Integer/Decimal precision is lost or malformed/out-of-range numeric text is accepted.
8. Date policy is lost through nested/Optional collections or differs between encode and decode.
9. Export emits dotted flat keys, overwrites colliding paths or omits nested type rules.
10. Required/filtered field conflicts are accepted, invalid defaults retain mutable Foundation objects.
11. Type-safe validation/transform hooks materialize all JSON or execute more than once.
12. Polymorphism requires YYModelCodable or cannot preserve nested external rules and output discriminator.
13. Failed unkeyed alternatives consume data; custom superDecoder loses userInfo/context.
14. Legacy no-argument input behavior changes for published fixtures (zero fill, dates, scalar conversion).
15. Benchmark compares failed native decoding, different DTOs or unchecked fields, or includes network/compilation time.

Collections remain strict and retain cardinality. This implementation does not offer a silent lossy-array option. Explicit element skipping belongs in a caller's custom Codable until a diagnostic-preserving public policy is designed.
# Performance correction gate (before the scalar-path change)

- Native integer results below 2^53 are not sufficient proof of exact conversion: a long fractional token just below 1 can round to 1. Preserve Decimal-before-integer conversion for every numeric token.
- Lightweight scalar collections must preserve nested Optional nulls, full UInt64 range, fractional truncation, range rejection and array position. They must never contain a user model initializer, Date/Data strategy or business hook.
- Whole native collection results must not bypass finite Float/Double/CGFloat validation, including Optional values and dictionaries.
- Raw Foundation-object collections must have the same strict null policy as Data, rather than implicitly using the old decoder's zero fill.
- No-argument encoder and decoder must share the legacy date epoch, so a simple Date round trip cannot shift by the Foundation/Unix epoch difference.
- Compare complete weather DTOs before timing. Keep the initial slow measurement as evidence; do not claim native performance from a correctness pass.
