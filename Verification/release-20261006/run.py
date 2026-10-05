#!/usr/bin/env python3
"""Freeze and replay public E2E consumers, without a network dependency.

python3 Verification/release-20261006/run.py --output /tmp/yymodel-weather-macos
python3 Verification/release-20261006/run.py --output /tmp/yymodel-weather-ios --simulator BOOTED_UDID
--source accepts a project directory or the source directory of a previous run.
The simulator must already be booted; the runner never changes device state.
"""
import argparse
import datetime
import hashlib
import json
import pathlib
import shutil
import subprocess


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def main():
    here = pathlib.Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=pathlib.Path, default=here / "source" if (here / "source/YYModelSwift").exists() else here.parents[1])
    parser.add_argument("--fixtures", type=pathlib.Path, default=here / "fixtures")
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--simulator")
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    frozen = out / "source"
    frozen.mkdir()
    source = args.source.resolve() / "YYModelSwift"
    shutil.copytree(source, frozen / "YYModelSwift")
    shutil.copytree(args.fixtures, out / "fixtures")
    consumers = {"RecoveryScenarioRows": 48, "PrimitiveRecoveryScenarioRows": 72,
                 "FoundationRecoveryScenarioControl": 4, "PolymorphicPolicyScenarioRows": 22,
                 "WeatherBusinessE2E": 136, "KeymapCombinationE2E": 18,
                 "SuperContainerLifetimeE2E": 42, "NumericBoundaryE2E": None}
    for name in consumers:
        shutil.copy2(here / (name + ".swift"), out / (name + ".swift"))
    for name in ("run.py", "fetch_weather.py", "FAILURE-MODES.md", "FAILURE-MODES-weather.md", "FAILURE-MODES-numeric.md"):
        shutil.copy2(here / name, out / name)
    for data_name, metadata_name in [("weather-api.json", "weather-source.json"), ("weather-error.json", "weather-error-source.json")]:
        metadata = json.loads((out / "fixtures" / metadata_name).read_text())
        assert sha(out / "fixtures" / data_name) == metadata["sha256"], "Fixture provenance hash mismatch"
        assert (out / "fixtures" / data_name).stat().st_size == metadata["bytes"], "Fixture byte count mismatch"
    swift_files = sorted((frozen / "YYModelSwift").glob("*.swift"))
    assert len(swift_files) == 20, "Unexpected production source inventory"
    receipt = {"createdAtUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(),
               "sourceSHA256": {p.name: sha(p) for p in swift_files},
               "inputSHA256": {str(p.relative_to(out)): sha(p) for p in out.glob("fixtures/*")},
               "consumerSHA256": {name: sha(out / (name + ".swift")) for name in consumers},
               "commands": [], "passed": False}

    def run(command):
        result = subprocess.run(command, capture_output=True, text=True)
        log = f"command-{len(receipt['commands']):02}.log"
        (out / log).write_text(result.stdout + result.stderr)
        receipt["commands"].append({"argv": command, "exitCode": result.returncode, "log": log})
        save(out / "receipt.json", receipt)
        if result.returncode:
            raise RuntimeError(f"Command failed ({result.returncode}): see {out / log}")
        return result.stdout

    receipt["toolchain"] = run(["swiftc", "--version"]).strip()
    flags = ["-O", "-parse-as-library", "-swift-version", "6", "-strict-concurrency=complete", "-warnings-as-errors"]
    if args.simulator:
        devices = json.loads(run(["xcrun", "simctl", "list", "devices", "--json"]))["devices"]
        matched = [(runtime, d) for runtime, ds in devices.items() for d in ds if d["udid"] == args.simulator]
        assert len(matched) == 1 and matched[0][1]["state"] == "Booted", "A booted simulator is required"
        receipt["runtime"], receipt["device"] = matched[0]
        sdk = run(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"]).strip()
        flags += ["-sdk", sdk, "-target", "arm64-apple-ios17.0-simulator"]
        launch = ["xcrun", "simctl", "spawn", args.simulator]
    else:
        receipt["runtime"] = run(["sw_vers"]).strip()
        launch = []
    run(["swiftc", *flags, "-emit-library", "-emit-module", "-module-name", "YYModelSwift",
         "-emit-module-path", str(out / "YYModelSwift.swiftmodule"), *map(str, swift_files),
         "-o", str(out / "libYYModelSwift.dylib")])
    all_failures = []
    receipt["suites"] = {}
    for name, expected_count in consumers.items():
        link = [] if name == "FoundationRecoveryScenarioControl" else ["-I", str(out), "-L", str(out),
                "-lYYModelSwift", "-Xlinker", "-rpath", "-Xlinker", str(out)]
        run(["swiftc", *flags, *link, str(out / (name + ".swift")), "-o", str(out / name)])
        result_path = out / (name + ".json")
        inputs = [str(out / "fixtures/weather-api.json")] if name == "WeatherBusinessE2E" else []
        run([*launch, str(out / name), *inputs, str(result_path)])
        artifact = json.loads(result_path.read_text())
        rows = artifact["rows"] if isinstance(artifact, dict) else artifact
        assert rows and (expected_count is None or len(rows) == expected_count), (name, len(rows))
        identities = [(r["scenario"], r.get("route")) for r in rows]
        assert len(set(identities)) == len(rows), f"Duplicate scenario in {name}"
        for row in rows:
            assert isinstance(row["passed"], bool) and "expected" in row and "actual" in row, row
        failures = [r for r in rows if not r["passed"]]
        receipt["suites"][name] = {"rows": len(rows), "passed": len(rows) - len(failures),
                                  "failed": len(failures), "resultSHA256": sha(result_path)}
        all_failures += [{"suite": name, **r} for r in failures]
        save(out / "receipt.json", receipt)
    receipt["failures"] = all_failures
    receipt["passed"] = not all_failures
    save(out / "receipt.json", receipt)
    print(json.dumps({"passed": receipt["passed"], "runtime": receipt["runtime"],
                      "suites": receipt["suites"], "evidence": str(out)}, ensure_ascii=False))
    return 0 if receipt["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
