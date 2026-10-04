#!/usr/bin/env python3
"""Same-process alternating APIs and Foundation dictionary bridging probe."""
import argparse
import copy
import json
import math
import statistics
import subprocess
from pathlib import Path
import run as common
from run_delivery import source_hashes

HERE = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--delivery-output', type=Path, required=True)
    parser.add_argument('--source-root', type=Path, default=HERE.parent)
    parser.add_argument('--no-benchmark', action='store_true')
    parser.add_argument('--benchmark-only', action='store_true')
    args = parser.parse_args()
    args.delivery_output = args.delivery_output.resolve()
    args.source_root = args.source_root.resolve()
    base = args.delivery_output
    environment = json.loads((base/'environment.json').read_text())
    if source_hashes(args.source_root) != environment['sourceHashes']: raise RuntimeError('Source differs from validated delivery build')
    if not json.loads((base/'correctness.json').read_text())['allPassed']: raise RuntimeError('Delivery correctness failed')
    args.simulator = environment['simulator']
    args.sdk = subprocess.check_output(['xcrun','--sdk','iphonesimulator','--show-sdk-path'], text=True).strip() if args.simulator else None
    output = base/'coexist'
    output.mkdir(exist_ok=True)
    binary = output/'coexist-e2e'
    metadata = dict(deliveryEnvironment=environment, validationHashes={p:common.sha(HERE/p) for p in ['run_coexist.py','CoexistE2E.swift']},
                    objectHashes={p.name:common.sha(p) for p in (base/'build').glob('current-*.o')})
    if args.benchmark_only:
        if metadata != json.loads((output/'environment.json').read_text()): raise RuntimeError('Coexist build identity changed')
        if not json.loads((output/'correctness.json').read_text())['allPassed']: raise RuntimeError('Coexist correctness failed')
    else:
        (output/'environment.json').write_text(json.dumps(metadata, indent=2))
        common.execute(['xcrun','--sdk','iphonesimulator' if args.simulator else 'macosx','swiftc',*common.swift_flags(args),
                        '-import-objc-header', HERE/'InteropSupport.h', '-Xcc', '-I'+str(args.source_root/'YYModel'),
                        '-Xcc','-I'+str(base/'build'),'-Xcc','-Wno-nullability-completeness',
                        *sorted((args.source_root/'YYModelSwift').glob('*.swift')),base/'build/WeatherModels.swift',HERE/'CoexistE2E.swift',
                        *sorted((base/'build').glob('current-*.o')),'-o',binary],output,'build.log')
    expected = json.loads((base/'weather-expected.json').read_text())
    cases = [(mode, scenario) for mode in ['alternating','foundation-object'] for scenario in ['clean','dirty','large']]
    oracles = {}
    for scenario in ['clean','dirty','large']:
        original = json.loads((base/f'weather-{scenario}.json').read_text())
        for engine in ['oc','swift']:
            doc = copy.deepcopy(original)
            doc['request']['trace_id'] = 'independent-'+engine+'-response'
            (output/f'{scenario}-{engine}.json').write_text(json.dumps(doc,separators=(',',':')))
            oracles[scenario+':'+engine] = common.canonical_model(doc)

    def run_case(mode, scenario, iterations, order, prefix):
        file = output/f'{prefix}-{mode}-{scenario}.json'
        common.execute(common.binary_command(args,[binary, output/f'{scenario}-oc.json',output/f'{scenario}-swift.json',
                        file,mode,str(iterations),order]),output,file.stem+'.log')
        value = json.loads(file.read_text())
        ok = common.model_matches(value.get('modelJSON'), oracles[scenario+':oc']) and common.model_matches(value.get('roundTripModelJSON'), oracles[scenario+':oc'])
        ok = ok and common.model_matches(value.get('swiftModelJSON'), oracles[scenario+':swift'])
        return value,ok

    if not args.benchmark_only:
        checks = {}
        for mode, scenario in cases:
            for order in ['oc-first','swift-first']:
                _,ok = run_case(mode,scenario,0,order,'check-'+order)
                checks[mode+':'+scenario+':'+order] = ok
        (output/'correctness.json').write_text(json.dumps(dict(checks=checks,allPassed=all(checks.values())),indent=2))
        print('Coexist correctness:',sum(checks.values()),'/',len(checks),flush=True)
        if not all(checks.values()): return 1
    if args.no_benchmark: return 0
    results = {}
    for phase, order in enumerate(['oc-first','swift-first']):
        for mode, scenario in (cases if phase==0 else list(reversed(cases))):
            iterations = 8 if scenario=='large' else environment['parameters']['iterations']
            value,ok = run_case(mode,scenario,iterations,order,'phase'+str(phase))
            if not ok: raise RuntimeError('Coexist model mismatch')
            ops = 2 if mode=='alternating' else 1
            score = float(oracles[scenario+':oc']['payload']['locations'][0]['current']['temperature_2m'])*ops
            if not math.isclose(value['consumed'],score*iterations*7,rel_tol=1e-10,abs_tol=1e-8): raise RuntimeError('Coexist consumption mismatch')
            entry = results.setdefault(mode+':'+scenario, dict(operationsPerIteration=ops,samplesMillisecondsPerIteration=[]))
            entry['samplesMillisecondsPerIteration'].extend([x/iterations for x in value['sampleMilliseconds']])
    for entry in results.values():
        entry['medianMillisecondsPerIteration'] = statistics.median(entry['samplesMillisecondsPerIteration'])
        entry['medianMillisecondsPerOperation'] = entry['medianMillisecondsPerIteration']/entry['operationsPerIteration']
    (output/'measurements.json').write_text(json.dumps(results,indent=2))
    print('Coexist measurements:',len(results),'paths, 14 samples each',flush=True)
    return 0


if __name__ == '__main__': raise SystemExit(main())
