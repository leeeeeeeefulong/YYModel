# Final accepted snapshot — 2026-10-05

Public API E2E 475/475. Frozen Swift production, all consumers, expectations, harness,
SPM package/tests and auxiliary business replay inputs are in source/. No build products
are required to replay. receipt.json contains original source SHA-256 and command/log
records; delivery.json additionally seals every delivered file (excluding itself).
Original /tmp command paths record provenance; the replay builds new outputs.

From repository root, use fresh output paths:

```sh
python3 Validation/remediation/evidence/final/source/Validation/remediation/run.py --output /tmp/yymodel-sealed-replay-new
python3 Validation/remediation/evidence/final/source/Validation/remediation/verify_platforms.py --acceptance-root /tmp/yymodel-sealed-replay-new --output /tmp/yymodel-sealed-platforms-new
python3 Validation/remediation/evidence/final/source/Validation/run_swift_model_data.py --source-root Validation/remediation/evidence/final/source --output /tmp/yymodel-sealed-business-new --samples 1 --iterations 1
python3 Validation/remediation/evidence/final/source/Validation/remediation/run_performance.py --acceptance-root /tmp/yymodel-sealed-replay-new --output /tmp/yymodel-sealed-performance-new
swift test -c release --package-path Validation/remediation/evidence/final/source --scratch-path /tmp/yymodel-sealed-spm-new
```

Platform compilation uses the installed modern SDK, not an old runtime. Formal external
signatures and real old OS acceptance remain pending. No release was performed.
Independent reviewers used stage11; final production differs only by deleting one blank
line at EOF in YYModelEncoder.swift, followed by complete fresh verification.
