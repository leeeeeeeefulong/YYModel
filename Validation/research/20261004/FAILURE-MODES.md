# Swift architecture review: failure modes declared before executing probes

Production source is read only. The executable exercises the existing public APIs, not a proposed replacement.

1. Native-first retry invokes a model's custom initializer twice after a business rejection, causing duplicated side effects.
2. A decoder retry changes Optional null behavior or loses the original business error.
3. Declaration defaults are assumed to be Codable decoding defaults; missing required fields actually fail natively and become zero in the legacy decoder.
4. A YYModelCodable mapper is silently ignored through the YYJSONDecoder entry point.
5. Default Foundation Date semantics are incorrectly claimed identical to YY's Unix timestamp interpretation.
6. Ordinary nested Codable arrays are assumed to require a YY-specific model protocol.
7. A string numeric conversion silently absorbs malformed suffixes or loses integers above 2^53.
8. External mapping is assumed possible only after adding a model protocol. Exercise a plain Codable model through the existing internal container adapter as a narrowly scoped feasibility check.
9. A nested JSON path with a non-object intermediate node crashes instead of returning a decoding error/default under the declared policy.

Expected evidence: initializer invocation counts, actual values/errors for each public entry, toolchain version, production source commit/hash, probe source hash, repeatable command, and JSON receipt.

Separate design constraints, not yet implementation claims:

- No additional model conformance, unsafe Swift memory writes, mandatory macro dependency, or global Codable behavior override.
- Model validation errors must propagate unchanged in the proposed enhanced path; repair only known requested scalar/container differences.
- Model configuration must be scoped to a decoder instance and propagated to nested models without leaking between requests.
- Clean native execution and enhanced execution must be benchmarked separately, with the same model shape and complete output checks.
