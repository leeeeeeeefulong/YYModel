# Public E2E review failure hypotheses (before consumer implementation)
- Asking for the same nested keyed container twice may erase fields written through the first container; Foundation should reuse the object.
- Asking for the same nested unkeyed container twice may erase earlier elements; Foundation should reuse the array.
- A CodingKeyRepresentable dictionary key with a meaningful intValue may lose metadata in native encodeJSONObject custom Date strategy.
- Unicode titlecase/acronym and digit boundaries in convertToSnakeCase may differ from Foundation.
- superEncoder may fail to apply custom key strategy or replace direct super content incorrectly.
- State-changing key/date strategies may run more than once or in a different order in no-op export hook paths.

# Focused follow-up hypotheses before consumer implementation
- Compatible no-hook Data should preserve repeated same nested key with no mapper; JSONObject may erase it in the tree.
- With mapper payload -> envelope, repeated same logical nested key may falsely trigger reserve collision independent of tree replacement.
- Distinct logical fields first/second both mapped to envelope must remain rejected in Data and JSONObject routes.
