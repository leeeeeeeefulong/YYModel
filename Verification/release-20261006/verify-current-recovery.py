#!/usr/bin/env python3
"""Rebuild public Swift consumers; retain frozen sources, commands, and JSON.

Run from any directory:
  python3 Verification/release-20261006/verify-current-recovery.py --output /tmp/yymodel-recovery-evidence
Use --source /path/to/20-swift-files to verify an already frozen candidate.
This is an external optimized-library E2E consumer run, not a unit-test suite.
"""

import argparse
import hashlib
import json
import pathlib
import shutil
import subprocess
import sys


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")


def main():
    here = pathlib.Path(__file__).resolve().parent
    repo = here.parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=pathlib.Path, default=repo / "YYModelSwift")
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    source = args.source.resolve()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    source_files = sorted(source.glob("*.swift"))
    if len(source_files) != 20:
        raise SystemExit(f"Expected 20 production Swift files, found {len(source_files)} in {source}")

    # Record possible failures before building any implementation or consumer.
    (out / "FAILURE-HYPOTHESES.md").write_text("""# Focused failure modes

1. A caught child error leaves an empty/partial tree node, replaces an earlier valid key, or changes array count. Encode into an unattached node and commit only on success.
2. Direct String/Int/Bool/Double writes enter Foundation's generic overload after a child throws and receive its draft. Concrete primitive overloads must retain direct Foundation behavior.
3. A retained superEncoder is disconnected by a later parent write of the same key. Its release within encode(to:) must commit as observed with Foundation. The last keyed/unkeyed/single or derived container must retain that commit lifetime, including descendant super encoders.
4. Polymorphic roots accept unsupported fallback/lossy/typed-default/missing field policies. Reject these in both registration orders, retaining payload policies.
5. An unencodable typed default replaces business value 7 with 99 but leaves JSON 7. Direct typed decode must see 99; superDecoder must reject unavailable JSON, never return 7.

Foundation controls: caller-written generic helper and single-value recovery outputs are runtime-dependent observations. No tree route is required to emulate retained drafts. Primitive generic Data and single-value Data rows compare the same Foundation consumer; tree rows require the successful scalar without a failed child. Control rows are counted separately from business assertions.
""")
    frozen = out / "source"
    frozen.mkdir(exist_ok=True)
    if frozen.resolve() != source:
        for old in frozen.glob("*.swift"):
            old.unlink()
        for path in source_files:
            shutil.copy2(path, frozen / path.name)
    consumers = [
        ("RecoveryScenarioRows", "recovery-results.json", 48),
        ("PrimitiveRecoveryScenarioRows", "primitive-results.json", 72),
        ("FoundationRecoveryScenarioControl", "foundation-control-results.json", 4),
        ("PolymorphicPolicyScenarioRows", "polymorphic-results.json", 22),
        ("SuperContainerLifetimeE2E", "super-container-results.json", 42),
    ]
    for name, _, _ in consumers:
        shutil.copy2(here / f"{name}.swift", out / f"{name}.swift")
    receipt = {
        "sourceDirectory": str(source),
        "sourceCount": len(source_files),
        "sourceSha256": {p.name: digest(p) for p in sorted(frozen.glob("*.swift"))},
        "consumerSha256": {name: digest(out / f"{name}.swift") for name, _, _ in consumers},
        "hypothesesSha256": digest(out / "FAILURE-HYPOTHESES.md"),
        "commands": [],
    }
    commit = subprocess.run(["git", "rev-parse", "HEAD"], cwd=repo, capture_output=True, text=True)
    receipt["repositoryHeadAtRun"] = commit.stdout.strip() if commit.returncode == 0 else None
    flags = ["-O", "-parse-as-library", "-swift-version", "6", "-strict-concurrency=complete", "-warnings-as-errors"]
    commands = [
        ["swiftc", "--version"],
        ["swiftc", *flags, "-emit-library", "-emit-module", "-module-name", "YYModelSwift", "-emit-module-path", str(out / "YYModelSwift.swiftmodule"), *map(str, sorted(frozen.glob("*.swift"))), "-o", str(out / "libYYModelSwift.dylib")],
    ]
    for name, result, _ in consumers:
        link = [] if name == "FoundationRecoveryScenarioControl" else ["-I", str(out), "-L", str(out), "-lYYModelSwift", "-Xlinker", "-rpath", "-Xlinker", str(out)]
        commands.extend([
            ["swiftc", *flags, *link, str(out / f"{name}.swift"), "-o", str(out / name)],
            [str(out / name), str(out / result)],
        ])
    for index, command in enumerate(commands):
        result = subprocess.run(command, capture_output=True, text=True)
        (out / f"command-{index}.log").write_text(result.stdout + result.stderr)
        receipt["commands"].append({"command": command, "exitCode": result.returncode})
        write_json(out / "receipt.json", receipt)
        if result.returncode:
            print(result.stdout + result.stderr, file=sys.stderr)
            raise SystemExit(result.returncode)

    routes = {"native-data", "native-object", "compatible-data", "compatible-object", "hook-data", "hook-object"}
    summary = {"matrices": {}, "regressionFailures": [], "controlFailures": [], "observedControls": [], "businessAssertionCount": 0, "controlRowCount": 0}
    def is_control(row):
        return row.get("category", "").startswith("foundation-")
    for name, result_name, count in consumers:
        rows = json.loads((out / result_name).read_text())
        assert len(rows) == count, (name, len(rows), count)
        identities = set()
        for row in rows:
            identity = (row["scenario"], row.get("route"))
            assert identity not in identities, identity
            identities.add(identity)
            assert type(row["passed"]) is bool
            assert row["passed"] == (row.get("actual") == row["expected"]), row
        if name in {"RecoveryScenarioRows", "PrimitiveRecoveryScenarioRows", "SuperContainerLifetimeE2E"}:
            for scenario in {row["scenario"] for row in rows}:
                group = [row for row in rows if row["scenario"] == scenario]
                assert {row["route"] for row in group} == routes, (name, scenario)
                assert len(group) == 6, (name, scenario)
        failures = [row for row in rows if not row["passed"]]
        controls = [row for row in rows if is_control(row)]
        business = [row for row in rows if not is_control(row)]
        summary["businessAssertionCount"] += len(business)
        summary["controlRowCount"] += len(controls)
        summary["matrices"][name] = {"rows": count, "passed": count - len(failures), "failed": len(failures), "businessRows": len(business), "controlRows": len(controls), "resultSha256": digest(out / result_name)}
        summary["observedControls"].extend({"matrix": name, **row} for row in controls)
        for row in failures:
            # Runtime Foundation controls are kept apart from business-safe rows.
            if is_control(row):
                summary["controlFailures"].append({"matrix": name, **row})
            else:
                summary["regressionFailures"].append({"matrix": name, **row})
    summary["passed"] = not summary["regressionFailures"] and not summary["controlFailures"]
    write_json(out / "summary.json", summary)
    print(json.dumps({"passed": summary["passed"], "regressionFailures": len(summary["regressionFailures"]), "controlFailures": len(summary["controlFailures"]), "businessAssertionCount": summary["businessAssertionCount"], "controlRowCount": summary["controlRowCount"], "matrices": summary["matrices"], "evidence": str(out)}, ensure_ascii=False))
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
