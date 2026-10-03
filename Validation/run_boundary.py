#!/usr/bin/env python3
"""Public API G1-G4 acceptance, independent of any application or test framework."""
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
    parser.add_argument('--output', type=Path, default=HERE/'artifacts/boundary')
    parser.add_argument('--original-source', type=Path)
    parser.add_argument('--simulator')
    args = parser.parse_args()
    args.source_root = args.source_root.resolve()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    args.sdk = subprocess.check_output(['xcrun','--sdk','iphonesimulator','--show-sdk-path'],text=True).strip() if args.simulator else None
    swift = args.output/'swift-boundary'
    common.execute(['swiftc',*common.swift_flags(args),args.source_root/'YYModelSwift/YYJSONDecoder.swift',HERE/'BoundaryE2E.swift','-o',swift],args.output,'swift-build.log')
    common.execute(common.binary_command(args,[swift,args.output/'swift.json']),args.output,'swift.log')
    for label, source in [('current',args.source_root/'YYModel'),('original',args.original_source)]:
        if source is None: continue
        binary = args.output/f'objc-{label}'
        common.execute(['clang',*common.objc_flags(args),'-I',source,*source.glob('*.m'),HERE/'ContractE2E.m','-o',binary],args.output,f'objc-{label}-build.log')
        common.execute(common.binary_command(args,[binary,args.output/f'objc-{label}.json']),args.output,f'objc-{label}.log')
    swift_result = json.loads((args.output/'swift.json').read_text())
    objc = json.loads((args.output/'objc-current.json').read_text())
    checks = {}
    for n in ['9223372036854775808','18446744073709551615']:
        for channel in ['decimalActual','jsonActual']:
            checks[f'G1:{n}:{channel}'] = objc[n][channel] == n
    edges = {'0':'0','1.9':'1','18446744073709551615.9':'18446744073709551615','-0.9':'0','-1':'18446744073709551615','18446744073709551616':'42','NaN':'42'}
    checks.update({f'G1:edge:{text}':objc['unsignedEdges'][text] == expected for text,expected in edges.items()})
    for key, value in swift_result.items():
        if key.startswith(('float:','double:','date:','any:')) or key=='dateAnyInf':
            checks['G2:'+key] = not value['ok'] or value['finite']
            if key.startswith('any:') and key.endswith(':overflow') and not key.startswith('any:Float:'):
                checks['finiteAny:'+key] = value['ok'] and value['finite']
        elif key.startswith('timestamp:'):
            checks['G3:'+key] = value.get('epoch') == value['expectedEpoch']
    checks['finiteControl'] = swift_result['finiteControl']['ok']
    checks.update({'G4:'+key:value for key,value in objc['strict'].items()})
    checks['legacyRootRejectsInvalid'] = bool(objc['validation']['rootRejected'])
    checks['legacyNestedBehaviorPreserved'] = bool(objc['validation']['childPresent']) and objc['validation']['childrenCount'] == 1
    if args.original_source:
        original = json.loads((args.output/'objc-original.json').read_text())
        checks['legacyMatchesOriginal'] = objc['validation'] == original['validation']
    metadata = dict(runtime='iOS Simulator' if args.simulator else 'macOS',system=platform.platform(),simulator=args.simulator,
        xcode=subprocess.check_output(['xcodebuild','-version'],text=True).strip(),
        sourceHashes={p:common.sha(args.source_root/p) for p in ['YYModel/NSObject+YYModel.m','YYModel/NSObject+YYModel.h','YYModel/YYClassInfo.m','YYModelSwift/YYJSONDecoder.swift']},
        validationHashes={p:common.sha(HERE/p) for p in ['run_boundary.py','BoundaryE2E.swift','ContractE2E.m']})
    (args.output/'environment.json').write_text(json.dumps(metadata,indent=2))
    summary = dict(checks=checks,total=len(checks),passed=sum(checks.values()),failed=sum(not x for x in checks.values()),allPassed=all(checks.values()))
    (args.output/'acceptance.json').write_text(json.dumps(summary,indent=2))
    print(json.dumps({k:v for k,v in summary.items() if k!='checks'}))
    return 0 if summary['allPassed'] else 1

if __name__=='__main__': raise SystemExit(main())
