#!/usr/bin/env python3
"""Public Objective-C contract E2E with repeatable receipt; no performance loop."""
import argparse
import json
import platform
import subprocess
from pathlib import Path
import run as common

HERE = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source-root', type=Path, default=HERE.parent)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--simulator')
    args = parser.parse_args()
    args.source_root = args.source_root.resolve()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    args.sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], text=True).strip() if args.simulator else None
    source = args.source_root/'YYModel'
    environment = dict(runtime='iOS Simulator' if args.simulator else 'macOS', simulator=args.simulator,
                       host=platform.platform(), sourceHashes={p.name:common.sha(p) for p in sorted(source.glob('*.[mh]'))},
                       harnessHashes={name:common.sha(HERE/name) for name in ['ObjCContractE2E.m', 'run_objc_contract.py']})
    (args.output/'environment.json').write_text(json.dumps(environment, indent=2))
    binary = args.output/'objc-contract-e2e'
    common.execute(['clang', *common.objc_flags(args), '-I', source, *sorted(source.glob('*.m')),
                    HERE/'ObjCContractE2E.m', '-o', binary], args.output, 'build.log')
    command = [str(v) for v in common.binary_command(args, [binary, args.output/'result.json'])]
    process = subprocess.run(command, capture_output=True, text=True)
    (args.output/'run.log').write_text('Command: '+json.dumps(command)+'\n'+process.stdout+process.stderr)
    result = json.loads((args.output/'result.json').read_text()) if (args.output/'result.json').exists() else None
    acceptance = dict(exitCode=process.returncode, result=result,
                      allPassed=process.returncode == 0 and result is not None and result['allPassed'])
    (args.output/'acceptance.json').write_text(json.dumps(acceptance, indent=2))
    print(json.dumps(acceptance), flush=True)
    return 0 if acceptance['allPassed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
