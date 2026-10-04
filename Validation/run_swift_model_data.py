#!/usr/bin/env python3
"""Full-object weather oracle, precise number oracle, then sequential timing samples."""
import argparse
import json
import platform
import statistics
import subprocess
from pathlib import Path
import run as common

HERE = Path(__file__).resolve().parent

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source-root', type=Path, default=HERE.parent)
    parser.add_argument('--output', type=Path, default=HERE/'artifacts/swift-model-data')
    parser.add_argument('--simulator')
    parser.add_argument('--mixed', action='store_true', help='Link the Objective-C component into the same Swift executable.')
    parser.add_argument('--samples', type=int, default=2, help='Each execution records seven samples; two executions = fourteen.')
    parser.add_argument('--iterations', type=int, default=100)
    args = parser.parse_args()
    args.source_root = args.source_root.resolve(); args.output = args.output.resolve(); args.output.mkdir(parents=True, exist_ok=True)
    args.sdk = subprocess.check_output(['xcrun','--sdk','iphonesimulator','--show-sdk-path'], text=True).strip() if args.simulator else None
    sources = sorted((args.source_root/'YYModelSwift').glob('*.swift'))
    provider=json.loads((HERE/'fixtures/weather-source.json').read_text())
    if common.sha(HERE/'fixtures/weather-api.json') != provider['sha256']:raise RuntimeError('Weather snapshot provenance changed')
    expected = common.fixtures(args.output)
    metadata = dict(binaryKind='mixed link' if args.mixed else 'Swift only',provider=provider,runtime='iOS 26.5 Simulator' if args.simulator else 'macOS', system=platform.platform(),
                    parameters=dict(iterations=args.iterations,largeIterations=max(3,args.iterations//32),executions=args.samples,samplesPerExecution=7,optimization='Swift -O / OC -O2',excludes=['network','file reads','initial object JSON parsing','initial model parse for export']),
                    xcode=subprocess.check_output(['xcodebuild','-version'],text=True).strip(),swift=subprocess.check_output(['swiftc','-version'],text=True,stderr=subprocess.STDOUT).strip(),cpu=subprocess.check_output(['sysctl','-n','machdep.cpu.brand_string'],text=True).strip(),simulator=args.simulator,
                    sourceHashes={str(p.relative_to(args.source_root)):common.sha(p) for p in sources},
                    validationHashes={p:common.sha(HERE/p) for p in ['SwiftModelNumericE2E.swift','SwiftModelWeatherE2E.swift','run_swift_model_data.py','generate_numeric.py','run.py','fixtures/weather-api.json','fixtures/weather-source.json']})
    if args.mixed:metadata['objcSourceHashes']={str(p.relative_to(args.source_root)):common.sha(p) for p in sorted((args.source_root/'YYModel').glob('*.[mh]'))}
    (args.output/'environment.json').write_text(json.dumps(metadata,indent=2))
    objects=[]
    if args.mixed:
        for source in sorted((args.source_root/'YYModel').glob('*.m')):
            obj=args.output/(source.stem+'.o');objects.append(obj)
            flags=['-O2','-fobjc-arc','-c']+(['-isysroot',args.sdk,'-target','arm64-apple-ios17.0-simulator'] if args.simulator else [])
            common.execute(['clang',*flags,'-I',args.source_root/'YYModel',source,'-o',obj],args.output,source.stem+'-build.log')
    for name, harness in [('weather','SwiftModelWeatherE2E.swift'), ('numeric','SwiftModelNumericE2E.swift')]:
        common.execute(['xcrun','--sdk','iphonesimulator' if args.simulator else 'macosx','swiftc',*common.swift_flags(args),'-swift-version','6','-strict-concurrency=complete',*sources,HERE/harness,*objects,'-o',args.output/name],args.output,f'{name}-build.log')
    numeric = common.cases()
    (args.output/'numeric-input.json').write_text(json.dumps(numeric,indent=2))
    common.execute(common.binary_command(args,[args.output/'numeric',args.output/'numeric-input.json',args.output/'numeric-results.json']),args.output,'numeric.log')
    numeric_output = json.loads((args.output/'numeric-results.json').read_text())
    checks = {f'number:{i}:{r["label"]}':r['passed'] for i,r in enumerate(numeric_output)}
    # Gate timing on the complete exported business model, never on a checksum alone.
    accepted = {}
    for name in expected:
        for mode in ['native','legacy','model','mapped','hooked','object','encode','nativeEncode','hookEncode']:
            output = args.output/f'{name}-{mode}-correctness.json'
            common.execute(common.binary_command(args,[args.output/'weather',args.output/f'weather-{name}.json',output,mode,'0']),args.output,f'{name}-{mode}-correctness.log')
            result = json.loads(output.read_text())
            supported = mode != 'native' or expected[name]['nativeSupported']
            valid = common.model_matches(result.get('modelJSON'), expected[name]['model'])
            if mode in ['encode','nativeEncode','hookEncode']:valid = valid and common.model_matches(result.get('encodedJSON'),expected[name]['model'])
            if mode == 'hookEncode':valid = valid and result.get('encodedJSON',{}).get('processed') is True
            checks[f'weather:{name}:{mode}'] = valid if supported else 'error' in result
            accepted[name,mode] = supported and valid
    measurements = []
    if all(checks.values()):
        for name in expected:
            iterations = max(3,args.iterations//32) if name == 'large' else args.iterations
            for mode in ['native','legacy','model','mapped','hooked','object','encode','nativeEncode','hookEncode']:
                if not accepted[name,mode]: continue
                samples = []
                for execution in range(args.samples):
                    output = args.output/f'{name}-{mode}-sample-{execution}.json'
                    common.execute(common.binary_command(args,[args.output/'weather',args.output/f'weather-{name}.json',output,mode,str(iterations)]),args.output,f'{name}-{mode}-sample-{execution}.log')
                    result = json.loads(output.read_text())
                    if 'error' in result or not common.model_matches(result.get('modelJSON'),expected[name]['model']):
                        raise RuntimeError(f'Timing gate failed: {name}/{mode}')
                    samples.extend([1000*v/iterations for v in result['sampleMilliseconds']])
                measurements.append(dict(fixture=name,engine=mode,iterations=iterations,samplesMicroseconds=samples,medianMicroseconds=statistics.median(samples)))
    result = dict(total=len(checks),passed=sum(checks.values()),failed=sum(not v for v in checks.values()),allPassed=all(checks.values()),checks=checks,measurements=measurements)
    (args.output/'acceptance.json').write_text(json.dumps(result,indent=2)); print(json.dumps({k:v for k,v in result.items() if k not in ['checks','measurements']}))
    return 0 if result['allPassed'] else 1

if __name__ == '__main__': raise SystemExit(main())
