#!/usr/bin/env python3
"""Public API contract E2E; records missing APIs before implementation."""
import argparse
import json
import subprocess
from pathlib import Path
import run as common

HERE = Path(__file__).resolve().parent

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source-root',type=Path,default=HERE.parent)
    parser.add_argument('--output',type=Path,default=HERE/'artifacts/swift-model')
    parser.add_argument('--simulator')
    parser.add_argument('--only',choices=['date','swift','all'],default='all')
    args = parser.parse_args()
    args.source_root=args.source_root.resolve();args.output=args.output.resolve();args.output.mkdir(parents=True,exist_ok=True)
    args.sdk=subprocess.check_output(['xcrun','--sdk','iphonesimulator','--show-sdk-path'],text=True).strip() if args.simulator else None
    sources=sorted((args.source_root/'YYModelSwift').glob('*.swift'))
    metadata=dict(runtime='iOS Simulator' if args.simulator else 'macOS',xcode=subprocess.check_output(['xcodebuild','-version'],text=True).strip(),
                  sourceHashes={str(p.relative_to(args.source_root)):common.sha(p) for p in [*sources,args.source_root/'YYModel/NSObject+YYModel.m']},
                  validationHashes={p:common.sha(HERE/p) for p in ['SwiftModelE2E.swift','DateContractE2E.m','run_swift_model.py']})
    (args.output/'environment.json').write_text(json.dumps(metadata,indent=2))
    checks={}
    if args.only in ['date','all']:
        binary=args.output/'date-e2e';source=args.source_root/'YYModel'
        common.execute(['clang',*common.objc_flags(args),'-I',source,*source.glob('*.m'),HERE/'DateContractE2E.m','-o',binary],args.output,'date-build.log')
        common.execute(common.binary_command(args,[binary,args.output/'date.json']),args.output,'date.log')
        checks.update({'OC:'+k:v['passed'] for k,v in json.loads((args.output/'date.json').read_text()).items()})
    if args.only in ['swift','all']:
        binary=args.output/'swift-model-e2e'
        command=['xcrun','--sdk','iphonesimulator' if args.simulator else 'macosx','swiftc',*common.swift_flags(args),'-swift-version','6','-strict-concurrency=complete',*sources,HERE/'SwiftModelE2E.swift','-o',binary]
        build=subprocess.run([str(x) for x in command],text=True,capture_output=True)
        (args.output/'swift-build.log').write_text(build.stdout+build.stderr)
        if build.returncode:
            checks['Swift:PublicAPICompiles']=False
            (args.output/'missing-api.json').write_text(json.dumps(dict(compiled=False,exitCode=build.returncode),indent=2))
        else:
            common.execute(common.binary_command(args,[binary,args.output/'swift.json']),args.output,'swift.log')
            checks.update({'Swift:'+k:v for k,v in json.loads((args.output/'swift.json').read_text())['checks'].items()})
    result=dict(checks=checks,total=len(checks),passed=sum(checks.values()),failed=sum(not v for v in checks.values()),allPassed=all(checks.values()))
    (args.output/'acceptance.json').write_text(json.dumps(result,indent=2));print(json.dumps({k:v for k,v in result.items() if k!='checks'}))
    return 0 if result['allPassed'] else 1

if __name__=='__main__':raise SystemExit(main())
