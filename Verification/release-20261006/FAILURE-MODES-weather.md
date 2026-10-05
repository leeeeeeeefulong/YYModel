# Fresh weather public-API E2E contract

Written before the consumer implementation. The input is one newly downloaded,
unmodified multi-city Open-Meteo response. The adjacent source metadata supplies
its request, retrieval time and provenance. Mutations below are synthetic copies
of that response, explicitly labelled `mutation`; they are never represented as
API responses or as forecasts. No release is authorized by this verification.

## Independent oracle and business workflow

Foundation `JSONSerialization` parses the original response independently of
YYModelSwift. Ordinary synthesized `Codable` DTOs model all returned fields,
including the current, hourly and daily values and their unit dictionaries.
Foundation `JSONEncoder` projects each decoded DTO back to a JSON object; a
recursive comparison requires exactly the original keys, array lengths and all
leaf values. This detects dropped cities, truncated arrays, missing units,
incorrect coercion, metadata loss and wrong values even when decoding succeeds.

The business workflow validates time/value array alignment, numeric domains,
strictly increasing local timestamps, daily high >= low, nonnegative rain/wind,
0...100 humidity, and `is_day` in 0...1. It derives a per-city summary containing
current temperature, daily extrema and rainfall totals. The summary is also
computed directly from the raw Foundation object and must match. Forecasts are
asserted against the downloaded snapshot, never against hard-coded future values.

## Scenarios fixed before implementation

| Scenario | Expected contract |
| --- | --- |
| Live snapshot / Foundation native control | Entire response decodes, all fields match the independent oracle, business summary matches. |
| Real API HTTP 400 response | Parse the independently downloaded `error: true` and `reason` object as a service error in every mode. Preserve the complete error fields on export; never produce a city forecast from it. |
| Live snapshot / YY native, compatible, legacy / Data and raw-object inputs | All cities and every typed field/array entry match the oracle. Raw native entry serializes through Foundation by the public contract. |
| Live snapshot / YY encoders / Data and object outputs | Structurally equal to original JSON, with all keys and leaves, then Foundation decoding and the business workflow succeed. |
| Live snapshot / no-op will/did/export rules | Compatible and legacy data/raw decode and data/object encode preserve every value. Hooks run exactly once per city for each applicable operation. |
| Live snapshot / mapped envelope and explicit date policy | A synthetic application envelope maps nested payload keys; seconds-based retrieval date round-trips exactly under an explicit policy. A distinct Foundation-native date/key strategy control must also succeed. |
| Mutation / current temperature numeric string | Foundation and YY native reject a nonoptional Double string. Compatible and legacy accept the lossless numeric string, preserving the original temperature and business output. |
| Mutation / missing current temperature | Foundation, YY native and compatible reject. Legacy produces zero only for this field; it must match the explicit zero-valued synthetic oracle. This is compatibility behavior, not a valid live forecast assertion. |
| Mutation / null current temperature | Foundation, YY native and compatible reject. Legacy produces zero only for this field; it must match the explicit zero-valued synthetic oracle. |
| Mutation / null/missing nested current object | Foundation, native and compatible reject. Published legacy zero-fill creates an explicit zero-valued current placeholder; compare that placeholder and every unaffected value, then require the business workflow to reject `interval == 0` before producing a usable forecast. |
| Mutation / malformed JSON | Foundation and every YY Data entry reject. The output records rejection rather than a skipped row. |
| Mutation / shortened hourly array | Decoding may succeed; the business workflow must reject before producing a usable forecast. Every mode must retain the malformed array rather than pad/drop it. |
| Mutation / object mixed into numeric hourly array | Every Foundation/YY Data/raw entry rejects; no silent element dropping. |
| Mutation / valid numeric string mixed into hourly numeric array | Native rejects; compatible and legacy accept and preserve the original values and complete array. |
| Mutation / invalid current humidity/day/rain values | Decoding may succeed; the business workflow rejects the out-of-domain forecast. |

All cases are unique rows with `scenario`, `expected`, `actual`, and `passed`.
An expected rejection is a passing assertion only when the recorded contract is
met. No known failure is downgraded to a skip or accepted retrospectively. The
consumer preserves its JSON artifact even when it exits nonzero. Native controls
distinguish a YY-specific issue from Foundation behavior. Source compilation and
consumer compilation use Swift 6, optimization and warnings as errors.

Before the first E2E run, baseline source inspection corrected one unverified
assumption in this plan: `YYModelDecoder.zeroFilled(type:forKey:)` decodes an empty
dictionary for a missing complex value under legacy mode. Therefore expecting
legacy decode itself to reject the missing current object would contradict its
published compatibility contract. The required application rejection remains
strict and is checked independently after the exact placeholder comparison.

## Limits and maintenance

This proves business behavior for the exact recorded schema and machine/OS in
the artifact. It does not establish unexecuted deployment floors or future API
schema compatibility. Unknown new API fields fail the full-key equality check,
requiring an intentional DTO/oracle update. API instability is handled by the
saved response plus provenance, so replay requires no network. The single fixture
is reused for all mutations; no duplicate fixture corpus is maintained.
