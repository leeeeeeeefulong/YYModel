#!/usr/bin/env python3
"""Verify preserved artifact bytes and that final receipts match current source."""
import hashlib
import json
import pathlib

here = pathlib.Path(__file__).resolve().parent
ev = here / "Evidence"
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
manifest = json.loads((ev / "artifact-manifest.json").read_text())
for name, digest in manifest["files"].items():
    assert sha(ev / name) == digest, f"Evidence bytes changed: {name}"
source = here.parents[1] / "YYModelSwift"
current = {p.name: sha(p) for p in source.glob("*.swift")}
counts = {"RecoveryScenarioRows": 48, "PrimitiveRecoveryScenarioRows": 72,
          "FoundationRecoveryScenarioControl": 4, "PolymorphicPolicyScenarioRows": 22,
          "WeatherBusinessE2E": 136, "KeymapCombinationE2E": 18,
          "SuperContainerLifetimeE2E": 42, "NumericBoundaryE2E": 112}
for platform in ["macos", "ios18", "ios26"]:
    directory = ev / "final" / platform
    r = json.loads((directory / "receipt.json").read_text())
    assert r["passed"] and r["sourceSHA256"] == current, platform
    for name, count in counts.items():
        result = directory / (name + ".json")
        artifact = json.loads(result.read_text())
        rows = artifact["rows"] if isinstance(artifact, dict) else artifact
        assert len(rows) == count and all(row["passed"] for row in rows), (platform, name)
        assert sha(result) == r["suites"][name]["resultSHA256"]
        assert sha(here / (name + ".swift")) == r["consumerSHA256"][name]
print(f"Verified {len(manifest['files'])} evidence files; identical 20-source candidate; 454 rows per platform")
