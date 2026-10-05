#!/usr/bin/env python3
"""Run the new weather mixed ObjC/Swift consumer on an already booted simulator.

--library is the frozen output of run.py for the same simulator SDK.
--project is the frozen project from the delivery verification.
"""
import argparse
import hashlib
import json
import pathlib
import shutil
import subprocess

p = argparse.ArgumentParser(description=__doc__)
p.add_argument("--library", type=pathlib.Path, required=True)
p.add_argument("--project", type=pathlib.Path, required=True)
p.add_argument("--output", type=pathlib.Path, required=True)
p.add_argument("--simulator", required=True)
a = p.parse_args()
out = a.output.resolve(); out.mkdir(parents=True, exist_ok=False)
library = a.library.resolve(); project = a.project.resolve()
here = pathlib.Path(__file__).resolve().parent
shutil.copy2(here / "MixedWeatherE2E.swift", out / "MixedWeatherE2E.swift")
shutil.copytree(project / "YYModel", out / "YYModel")
shutil.copytree(library / "fixtures", out / "fixtures")
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
receipt = {"simulator": a.simulator, "swiftSourceSHA256": {f.name: sha(f) for f in (library / "source/YYModelSwift").glob("*.swift")},
           "objcSourceSHA256": {f.name: sha(f) for f in (out / "YYModel").iterdir() if f.is_file()},
           "consumerSHA256": sha(out / "MixedWeatherE2E.swift"), "commands": [], "passed": False}

def run(command):
    result = subprocess.run(command, capture_output=True, text=True)
    log = f"command-{len(receipt['commands']):02}.log"
    (out / log).write_text(result.stdout + result.stderr)
    receipt["commands"].append({"argv": command, "exitCode": result.returncode, "log": log})
    (out / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    if result.returncode: raise RuntimeError(f"See {out / log}")
    return result.stdout

sdk = run(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"]).strip()
(out / "module.modulemap").write_text('module YYModel { umbrella header "YYModel/YYModel.h" export * }\n')
run(["clang", "-target", "arm64-apple-ios17.0-simulator", "-isysroot", sdk, "-dynamiclib", "-fobjc-arc",
     "-framework", "Foundation", "-framework", "CoreFoundation", "-Wno-deprecated-declarations",
     str(out / "YYModel/YYClassInfo.m"), str(out / "YYModel/NSObject+YYModel.m"), "-o", str(out / "libYYModelObjC.dylib")])
run(["swiftc", "-O", "-parse-as-library", "-swift-version", "6", "-strict-concurrency=complete", "-warnings-as-errors",
     "-sdk", sdk, "-target", "arm64-apple-ios17.0-simulator", "-I", str(out), "-I", str(library), "-L", str(out),
     "-L", str(library), "-lYYModelObjC", "-lYYModelSwift", "-Xlinker", "-rpath", "-Xlinker", str(out),
     "-Xlinker", "-rpath", "-Xlinker", str(library), str(out / "MixedWeatherE2E.swift"), "-o", str(out / "MixedWeatherE2E")])
run(["xcrun", "simctl", "spawn", a.simulator, str(out / "MixedWeatherE2E"), str(out / "fixtures/weather-api.json"), str(out / "results.json")])
rows = json.loads((out / "results.json").read_text())
assert len(rows) == 9 and len({r["scenario"] for r in rows}) == 9
assert all(r["passed"] and r["actual"] == r["expected"] for r in rows)
receipt["rows"] = len(rows); receipt["passed"] = True; receipt["resultSHA256"] = sha(out / "results.json")
(out / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
print(json.dumps({"passed": True, "rows": len(rows), "evidence": str(out)}))
