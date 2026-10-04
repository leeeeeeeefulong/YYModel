#!/usr/bin/env python3
"""Collect public-API architecture observations; this is not a parity pass gate."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
ORIGINAL = "c7df27538c043e5f54f5b6605958544bb529892f"
TAG = "00329f245752ed0e264e8c90bc14a6bd4e4e46e5"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command, log, cwd):
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True)
    log.write_text(json.dumps(command) + "\n" + result.stdout + result.stderr)
    if result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}); see {log}")
    return result.stdout


def snapshot(repo, output, ref):
    names = subprocess.check_output(
        ["git", "ls-tree", "-r", "--name-only", ref, "YYModel"], cwd=repo, text=True
    ).splitlines()
    for name in names:
        if Path(name).suffix in (".h", ".m"):
            target = output / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(subprocess.check_output(["git", "show", f"{ref}:{name}"], cwd=repo))
    return output


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, default=HERE.parents[2])
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--only", choices=["all", "swift", "objc"], default="all")
    args = parser.parse_args()
    repo = args.source_root.resolve()
    output = args.output.resolve()
    if output.exists() and any(output.iterdir()):
        raise RuntimeError("Choose a new/empty output directory to preserve prior observations")
    output.mkdir(parents=True, exist_ok=True)
    receipt = {
        "startedUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "scope": "Observed behavior, including reproduced failures; not an all-passed claim",
        "currentCommit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip(),
        "runnerSHA256": sha(Path(__file__)),
    }
    if args.only in ("all", "swift"):
        sources = sorted((repo / "YYModelSwift").glob("*.swift"))
        binary = output / "swift-probe"
        command = ["swiftc", "-O", "-swift-version", "6", "-warnings-as-errors", *map(str, sources),
                   str(HERE / "ArchitectureProbe.swift"), "-o", str(binary)]
        run(command, output / "swift-build.log", repo)
        observations = run([str(binary)], output / "swift-run.log", repo)
        receipt["swift"] = {
            "sourceHashes": {str(p.relative_to(repo)): sha(p) for p in sources},
            "probeSHA256": sha(HERE / "ArchitectureProbe.swift"),
            "observations": json.loads(observations),
        }
    if args.only in ("all", "objc"):
        roots = {
            "original": snapshot(repo, output / "original", ORIGINAL),
            "tag": snapshot(repo, output / "tag", TAG),
            "master": repo,
        }
        values = {}
        for label, root in roots.items():
            sources = sorted((root / "YYModel").glob("*.m"))
            binary = output / (label + "-probe")
            command = ["clang", "-O2", "-fobjc-arc", "-framework", "Foundation",
                       "-Wno-deprecated-declarations", "-Wno-nullability-completeness",
                       "-I", str(root / "YYModel"), *map(str, sources), str(HERE / "ObjCProbe.m"), "-o", str(binary)]
            run(command, output / (label + "-build.log"), repo)
            result_path = output / (label + ".json")
            run([str(binary), str(result_path)], output / (label + "-run.log"), repo)
            values[label] = {
                "sourceHashes": {str(p.relative_to(root)): sha(p) for p in sorted((root / "YYModel").glob("*.[mh]"))},
                "result": json.loads(result_path.read_text()),
            }
        receipt["objc"] = values
        receipt["objcProbeSHA256"] = sha(HERE / "ObjCProbe.m")
    receipt["finishedUTC"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    path = output / "receipt.json"
    path.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n")
    print(f"Observations saved: {path}")
    if "objc" in receipt:
        for label, data in receipt["objc"].items():
            print(label, "pointerEqual:", data["result"]["differentPointers"]["equal"],
                  "mapperName:", data["result"]["mapperOverride"]["name"])


if __name__ == "__main__":
    main()
