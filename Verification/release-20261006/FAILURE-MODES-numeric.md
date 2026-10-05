# Public numeric and date boundary E2E contract

Written before this consumer. These are synthetic, literal boundary inputs,
separate from live weather data. Only public Codable/YYJSONDecoder/YYJSONEncoder
entry points are exercised; production source is read-only for this consumer.

## Failure modes and required outcomes

1. `Int64.min`, `Int64.max`, and `UInt64.max` may pass through Double and lose
   integer precision. Compatible/legacy Data and raw inputs must match the exact
   typed integer literals. Export Data and object values must preserve them.
2. The adjacent-to-one Double token `1.0000000000000002` may round to 1. Its
   required IEEE-754 bit pattern is `0x3ff0000000000001`, independently supplied
   as a literal. The same field must retain its bit pattern on round-trip.
3. Numeric strings at the same boundaries may coerce through an imprecise float.
   Compatible/legacy must retain the literal expected values. Native delegates
   rejection/acceptance to a matching Foundation control.
4. Integer overflow tokens `9223372036854775808` and `18446744073709551616`
   must not wrap, clamp or silently round into the target Int64/UInt64. Every
   decoder path must reject. Native observations are checked against independent
   Foundation Data and serialize-then-decode raw controls.
5. Nonfinite Double input (`1e309` Data, NaN/infinity raw objects) and output
   must reject under the default `.throw` float strategy. Raw native input may
   reject during JSON validation; a public Swift rejection is still required.
   Observed on the first run: Foundation serialization of infinity throws an
   Objective-C exception, terminating the process outside Swift `do/catch`.
   Therefore the independent invalid-raw Foundation control uses
   `isValidJSONObject` to reject before writing; the YY native raw path must
   provide a safe rejection and must not expose that process termination.
   Isolated direct YY native probes subsequently confirmed SIGABRT for each of
   infinity, NaN, Date and NSObject dictionary values. Native preflight must
   reject these safely while finite UInt64/Double/Bool/null top-level fragments
   keep Foundation's supported fragment semantics.
6. A finite fractional epoch `1700000000.125` must round-trip with explicit
   seconds, milliseconds and microseconds date policies. Native seconds and
   milliseconds use Foundation strategies and an independent Foundation control;
   microseconds are an explicit enhanced policy only.
7. A finite Date whose milliseconds/microseconds scaling overflows Double must
   reject on export under the default float `.throw` strategy. Infinite Date
   output must reject. A rejected model must never produce a usable JSON result.

## Native semantics, oracle, and artifact

For native decoding, compare each route with the corresponding Foundation
route on the same machine: Data -> JSONDecoder; raw object -> JSONSerialization
Data -> JSONDecoder. Do not assert cross-route precision equality as a universal
Foundation contract. The enhanced paths use exact literal expected values,
independent of either library's decode result. Foundation JSONDecoder consumes
each exported numeric model and verifies integer equality and Double bit pattern.
Object exports additionally expose and verify NSNumber signed/unsigned values.

Each scenario records expected, actual and passed; rejections are explicit
assertions, with no skips. All rows are saved before a nonzero exit if any fail.
Compile the frozen library and external consumer with Swift 6, optimization,
complete concurrency checking and warnings as errors.

This deliberately does not establish Decimal precision, smaller integer widths,
Float rounding, JSON5, timezone/calendar representability, non-default
nonconforming-float conversions, or unexecuted operating systems. It complements
the weather workflow rather than duplicating it.
