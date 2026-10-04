#!/usr/bin/env python3
"""Release delivery: validate first, then measure identical public API workloads."""
import argparse
import json
import math
import platform
import re
import statistics
import subprocess
from pathlib import Path
import run as common

HERE = Path(__file__).resolve().parent
HARNESS = ['run_delivery.py', 'run.py', 'WeatherE2E.m', 'WeatherE2E.swift',
           'InteropSupport.h', 'InteropSupport.m', 'InteropRunner.m', 'InteropRunner.swift']
VARIANTS = [('current', 'oc-only', ['oc']),
            ('current', 'swift-only', ['native', 'native-new', 'yy']),
            ('current', 'mixed', ['oc', 'swift-oc', 'native', 'native-new', 'yy']),
            ('original', 'oc-only', ['oc']), ('original', 'mixed', ['oc', 'swift-oc'])]


def source_hashes(folder):
    files = sorted((folder/'YYModel').glob('*.[mh]'))
    files.extend(sorted((folder/'YYModelSwift').glob('*.swift')))
    return {str(p.relative_to(folder)): common.sha(p) for p in files}


def build(args):
    output = args.output/'build'
    output.mkdir(exist_ok=True)
    declarations = re.findall(r'@interface\b.*?@end', (HERE/'WeatherE2E.m').read_text(), re.S)
    (output/'WeatherModels.h').write_text('#import <Foundation/Foundation.h>\n#import "YYModel.h"\n' + '\n'.join(declarations))
    (output/'WeatherModels.swift').write_text((HERE/'WeatherE2E.swift').read_text().split('@main')[0])
    for version, root in [('current', args.source_root), ('original', args.original_root)]:
        objects = []
        for index, source in enumerate([*(root/'YYModel').glob('*.m'), HERE/'WeatherE2E.m', HERE/'InteropSupport.m']):
            obj = output/f'{version}-{index}.o'
            extra = ['-Dmain=ValidationWeatherReferenceMain'] if source.name == 'WeatherE2E.m' else []
            compile_flags = common.objc_flags(args)
            framework = compile_flags.index('-framework')
            del compile_flags[framework:framework+2]
            common.execute(['clang', *compile_flags, '-I', root/'YYModel', '-I', output,
                            *extra, '-c', source, '-o', obj], args.output, f'build-{version}-{index}.log')
            objects.append(obj)
        common.execute(['clang', *common.objc_flags(args), '-I', root/'YYModel', '-I', output,
                        *objects, HERE/'InteropRunner.m', '-o', output/f'{version}-oc-only'], args.output, f'build-{version}-oc.log')
        common.execute(['xcrun', '--sdk', 'iphonesimulator' if args.simulator else 'macosx', 'swiftc', *common.swift_flags(args), '-DINTEROP', '-import-objc-header', HERE/'InteropSupport.h',
                        '-Xcc', '-I'+str(root/'YYModel'), '-Xcc', '-I'+str(output), '-Xcc', '-Wno-nullability-completeness',
                        *sorted((args.source_root/'YYModelSwift').glob('*.swift')), output/'WeatherModels.swift', HERE/'InteropRunner.swift',
                        *objects, '-o', output/f'{version}-mixed'], args.output, f'build-{version}-mixed.log')
    common.execute(['xcrun', '--sdk', 'iphonesimulator' if args.simulator else 'macosx', 'swiftc', *common.swift_flags(args), *sorted((args.source_root/'YYModelSwift').glob('*.swift')),
                    output/'WeatherModels.swift', HERE/'InteropRunner.swift', '-o', output/'current-swift-only'],
                   args.output, 'build-swift-only.log')


def run_case(args, version, binary_kind, engine, channel, scenario, iterations, prefix):
    label = ':'.join([version, binary_kind, engine, channel, scenario])
    file = args.output/(prefix+'-'+label.replace(':', '-')+'.json')
    common.execute(common.binary_command(args, [args.output/'build'/f'{version}-{binary_kind}',
                    args.output/f'weather-{scenario}.json', file, engine, channel, str(iterations)]),
                   args.output, file.stem+'.log')
    return label, json.loads(file.read_text()), file


def result_matches(value, oracle, engine, channel):
    if engine.startswith('native') and not oracle['nativeSupported']:
        return 'error' in value
    if 'error' in value or not common.model_matches(value.get('modelJSON'), oracle['model']): return False
    if engine in ['oc', 'swift-oc']:
        if not common.model_matches(value.get('roundTripModelJSON'), oracle['model']): return False
        if channel == 'encode' and not common.model_matches(value.get('encodedModelJSON'), oracle['model']): return False
    if channel == 'encode' and value.get('encodedBytes', 0) <= 0: return False
    return True


def correctness(args, expected):
    checks = {}
    for version, kind, engines in VARIANTS:
        for engine in engines:
            for channel in ['data', 'object', 'encode']:
                for scenario, oracle in expected.items():
                    label, value, _ = run_case(args, version, kind, engine, channel, scenario, 0, 'check')
                    checks[label] = result_matches(value, oracle, engine, channel)
    for version in ['current', 'original']:
        binary = args.output/'build'/f'{version}-mixed'
        symbols = common.execute(['nm', '-g', binary], args.output, f'symbols-{version}-mixed.log')
        checks[version+':mixed:linksBoth'] = 'WeatherEnvelope' in symbols and 'YYJSONDecoder' in symbols
    symbols = common.execute(['nm', '-g', args.output/'build/current-swift-only'], args.output, 'symbols-swift-only.log')
    checks['swift-only:noWeatherOCClass'] = 'OBJC_CLASS_$_WeatherEnvelope' not in symbols
    result = dict(checks=checks, total=len(checks), passed=sum(checks.values()), allPassed=all(checks.values()))
    (args.output/'correctness.json').write_text(json.dumps(result, indent=2))
    print('Correctness:', result['passed'], '/', result['total'], flush=True)
    return result['allPassed']


def benchmark_cases(expected):
    cases = []
    for version, kind, engines in VARIANTS:
        for engine in engines:
            for channel, scenarios in [('data', list(expected)), ('object', ['clean', 'dirty', 'large']), ('encode', ['clean', 'large'])]:
                for scenario in scenarios:
                    if engine.startswith('native') and not expected[scenario]['nativeSupported']: continue
                    if engine == 'native-new' and (scenario != 'clean' or channel != 'data'): continue
                    cases.append((version, kind, engine, channel, scenario))
    return cases


def measure(args, expected):
    cases = benchmark_cases(expected)
    results = {}
    for phase, sequence in enumerate([cases, list(reversed(cases))]):
        for index, case in enumerate(sequence):
            version, kind, engine, channel, scenario = case
            iterations = 8 if scenario == 'large' else args.iterations
            label, value, file = run_case(args, *case, iterations, f'phase{phase}')
            if not result_matches(value, expected[scenario], engine, channel): raise RuntimeError('Benchmark model mismatch: '+label)
            samples = [x/iterations for x in value['sampleMilliseconds']]
            if len(samples) != 7 or not all(math.isfinite(x) and x > 0 for x in samples): raise RuntimeError('Invalid timing: '+label)
            expected_score = value['encodedBytes'] if channel == 'encode' else float(expected[scenario]['model']['payload']['locations'][0]['current']['temperature_2m'])
            if not math.isclose(value['consumed'], expected_score*iterations*7, rel_tol=1e-10, abs_tol=1e-8): raise RuntimeError('Result consumption mismatch: '+label)
            entry = results.setdefault(label, dict(samplesMillisecondsPerOperation=[], firstDecodeMilliseconds=[], iterationsPerSample=iterations,
                                                   bytes=expected[scenario]['bytes'], resultHashes=[]))
            entry['samplesMillisecondsPerOperation'].extend(samples)
            entry['firstDecodeMilliseconds'].append(value['firstDecodeMilliseconds'])
            entry['resultHashes'].append(common.sha(file))
            if index % 16 == 0: print('Phase', phase+1, ':', index+1, '/', len(sequence), label, flush=True)
    for entry in results.values():
        samples = entry['samplesMillisecondsPerOperation']
        entry.update(medianMilliseconds=statistics.median(samples), minMilliseconds=min(samples), maxMilliseconds=max(samples),
                     p95Milliseconds=sorted(samples)[math.ceil(len(samples)*0.95)-1], operationsPerSecond=1000/statistics.median(samples))
    (args.output/'measurements.json').write_text(json.dumps(results, indent=2))
    print('Measurements:', len(results), 'paths, 14 samples each', flush=True)
    return results


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source-root', type=Path, default=HERE.parent)
    parser.add_argument('--original-root', type=Path, required=True, help='Fixed ibireme archive root, containing YYModel/')
    parser.add_argument('--output', type=Path, default=HERE/'artifacts/delivery')
    parser.add_argument('--simulator')
    parser.add_argument('--iterations', type=int, default=100)
    parser.add_argument('--no-benchmark', action='store_true')
    parser.add_argument('--benchmark-only', action='store_true', help='Reuse a successful, matching correctness/build artifact')
    args = parser.parse_args()
    for name in ['source_root', 'original_root', 'output']: setattr(args, name, getattr(args, name).resolve())
    if args.iterations < 1: parser.error('iterations must be positive')
    if args.benchmark_only and args.no_benchmark: parser.error('choose only one execution mode')
    args.output.mkdir(parents=True, exist_ok=True)
    args.sdk = subprocess.check_output(['xcrun','--sdk','iphonesimulator','--show-sdk-path'], text=True).strip() if args.simulator else None
    provider = json.loads((HERE/'fixtures/weather-source.json').read_text())
    if common.sha(HERE/'fixtures/weather-api.json') != provider['sha256']: raise RuntimeError('Weather provenance hash mismatch')
    metadata = dict(runtime='iOS Simulator' if args.simulator else 'macOS', system=platform.platform(), simulator=args.simulator,
                    cpu=subprocess.check_output(['sysctl','-n','machdep.cpu.brand_string'], text=True).strip(),
                    xcode=subprocess.check_output(['xcodebuild','-version'], text=True).strip(),
                    swift=subprocess.check_output(['swiftc','-version'], text=True, stderr=subprocess.STDOUT).strip(),
                    sourceHashes=source_hashes(args.source_root), originalSourceHashes=source_hashes(args.original_root),
                    validationHashes={p:common.sha(HERE/p) for p in HARNESS}, provider=provider,
                    parameters=dict(iterations=args.iterations, largeIterations=8, samplesPerPhase=7, phases=2, warmups=5,
                                    order='forward then reverse', optimization='OC -O2 / Swift -O', excludes=['network','file reads','initial JSON parsing in object mode','initial model parsing in encode mode']))
    if args.benchmark_only:
        previous = json.loads((args.output/'environment.json').read_text())
        if metadata != previous: raise RuntimeError('Source, harness, runtime or parameters changed; rebuild and validate')
        if not json.loads((args.output/'correctness.json').read_text())['allPassed']: raise RuntimeError('Correctness failed; timing blocked')
        expected = json.loads((args.output/'weather-expected.json').read_text())
    else:
        (args.output/'environment.json').write_text(json.dumps(metadata, indent=2))
        expected = common.fixtures(args.output)
        build(args)
        if not correctness(args, expected): return 1
    if not args.no_benchmark: measure(args, expected)
    summary = dict(correctnessPassed=True, benchmarkCompleted=not args.no_benchmark,
                   binaryBytes={p.name:p.stat().st_size for p in (args.output/'build').iterdir() if p.name in ['current-oc-only','current-swift-only','current-mixed','original-oc-only','original-mixed']})
    (args.output/'acceptance.json').write_text(json.dumps(summary, indent=2))
    return 0


if __name__ == '__main__': raise SystemExit(main())
