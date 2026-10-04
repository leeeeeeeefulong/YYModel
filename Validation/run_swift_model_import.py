#!/usr/bin/env python3
"""Real SwiftPM consumers, verifying Swift-only and mixed products independently."""
import argparse
import json
from pathlib import Path
import run as common

HERE = Path(__file__).resolve().parent

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--source-root',type=Path,default=HERE.parent)
    p.add_argument('--output',type=Path,default=HERE/'artifacts/swift-model-import')
    a = p.parse_args(); a.source_root=a.source_root.resolve(); a.output=a.output.resolve(); a.output.mkdir(parents=True,exist_ok=True)
    consumer=a.output/'consumer'
    for target in ['SwiftOnly','Mixed']:(consumer/'Sources'/target).mkdir(parents=True,exist_ok=True)
    source_literal=json.dumps(str(a.source_root),ensure_ascii=False)
    (consumer/'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name:"PublicConsumer",platforms:[.macOS(.v13)],dependencies:[.package(name:"YYModel",path:'''+source_literal+''')],targets:[
.executableTarget(name:"SwiftOnly",dependencies:[.product(name:"YYModelSwift",package:"YYModel")]),
.executableTarget(name:"Mixed",dependencies:[.product(name:"YYModelSwift",package:"YYModel"),.product(name:"YYModel",package:"YYModel")])])
''')
    (consumer/'Sources/SwiftOnly/Run.swift').write_text('import YYModelSwift\n'+(HERE/'SwiftModelE2E.swift').read_text())
    (consumer/'Sources/Mixed/Run.swift').write_text((HERE/'SwiftModelMixedE2E.swift').read_text())
    metadata=dict(sourceHashes={str(x.relative_to(a.source_root)):common.sha(x) for x in [a.source_root/'Package.swift',*sorted((a.source_root/'YYModelSwift').glob('*.swift'))]},
                  validationHashes={x:common.sha(HERE/x) for x in ['run_swift_model_import.py','SwiftModelE2E.swift','SwiftModelMixedE2E.swift']})
    (a.output/'environment.json').write_text(json.dumps(metadata,indent=2))
    common.execute(['swift','run','--package-path',consumer,'-c','release','SwiftOnly',a.output/'swift.json'],a.output,'swift-build-run.log')
    pure = json.loads((a.output/'swift.json').read_text())
    checks=dict(pure['checks'])
    checks['SwiftOnlyDoesNotCompileObjC']=not any((consumer/'.build').rglob('NSObject+YYModel.m.o'))
    common.execute(['swift','run','--package-path',consumer,'-c','release','Mixed',a.output/'mixed.json'],a.output,'mixed-build-run.log')
    checks.update(json.loads((a.output/'mixed.json').read_text()))
    result=dict(checks=checks,total=len(checks),passed=sum(checks.values()),failed=sum(not v for v in checks.values()),allPassed=all(checks.values()))
    (a.output/'acceptance.json').write_text(json.dumps(result,indent=2));print(json.dumps({k:v for k,v in result.items() if k!='checks'}))
    return 0 if result['allPassed'] else 1

if __name__=='__main__':raise SystemExit(main())
