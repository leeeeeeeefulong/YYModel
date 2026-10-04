#!/usr/bin/env python3
"""Independent public Swift consumer, full weather oracle and optional paired measurements."""
import argparse
import datetime
import json
import math
import platform
import statistics
import subprocess
from pathlib import Path
import run as common

HERE = Path(__file__).resolve().parent
PUBLISHED = '00329f245752ed0e264e8c90bc14a6bd4e4e46e5'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source-root', type=Path, default=HERE.parent)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--simulator')
    parser.add_argument('--benchmark', action='store_true')
    parser.add_argument('--rounds', type=int, default=3)
    parser.add_argument('--iterations', type=int, default=100)
    args = parser.parse_args()
    args.source_root = args.source_root.resolve(); args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    args.sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], text=True).strip() if args.simulator else None
    sources = sorted((args.source_root/'YYModelSwift').glob('*.swift'))
    receipt = dict(startedUTC=datetime.datetime.now(datetime.timezone.utc).isoformat(), runtime='iOS Simulator' if args.simulator else 'macOS',
                   host=platform.platform(), simulator=args.simulator, publishedCommit=PUBLISHED,
                   sourceHashes={str(p.relative_to(args.source_root)):common.sha(p) for p in sources},
                   harnessHashes={p.name:common.sha(p) for p in [Path(__file__), *sorted((HERE/'external-rules').glob('*'))] if p.is_file()},
                   xcode=subprocess.check_output(['xcodebuild', '-version'], text=True).strip(),
                   swift=subprocess.check_output(['swiftc', '-version'], text=True, stderr=subprocess.STDOUT).strip(),
                   parameters=dict(optimization='Swift -O', rounds=args.rounds, iterations=args.iterations, samplesPerBlock=7, warmup=5,
                                   excluded=['network', 'file reads', 'initial object serialization', 'verification export', 'compilation']))
    (args.output/'environment.json').write_text(json.dumps(receipt, indent=2))
    flags = [*common.swift_flags(args), '-swift-version', '6', '-strict-concurrency=complete', '-warnings-as-errors']
    for module, files in [('YYModelSwift', sources), ('PublishedYY', [args.output/'Published.swift'])]:
        if module == 'PublishedYY':
            files[0].write_bytes(subprocess.check_output(['git', 'show', f'{PUBLISHED}:YYModelSwift/YYJSONDecoder.swift'], cwd=args.source_root))
            receipt['publishedSourceHash'] = common.sha(files[0])
        common.execute(['swiftc', *flags, '-emit-library', '-emit-module', '-module-name', module,
                        '-emit-module-path', args.output/(module+'.swiftmodule'), *files,
                        '-o', args.output/('lib'+module+'.dylib')], args.output, module+'-build.log')
    link = ['-I', args.output, '-L', args.output, '-lYYModelSwift', '-lPublishedYY', '-Xlinker', '-rpath', '-Xlinker', args.output]
    for name, harness in [('contract', 'ExternalRulesE2E.swift'), ('weather', 'WeatherRulesE2E.swift')]:
        common.execute(['swiftc', *flags, '-DPUBLIC_API', '-parse-as-library', *link,
                        HERE/'external-rules'/harness, '-o', args.output/name], args.output, name+'-build.log')
    common.execute(common.binary_command(args, [args.output/'contract', args.output/'contract.json']), args.output, 'contract-run.log')
    result = json.loads((args.output/'contract.json').read_text())
    checks = {'contract:'+key:value for key,value in result['checks'].items()}
    expected = common.fixtures(args.output)

    def run_weather(engine, scenario, iterations, label):
        file = args.output/(label+'.json')
        common.execute(common.binary_command(args, [args.output/'weather', args.output/f'weather-{scenario}.json', file, engine, iterations]), args.output, label+'.log')
        value = json.loads(file.read_text())
        supported = engine not in ('foundation', 'native') or expected[scenario]['nativeSupported']
        valid = common.model_matches(value.get('modelJSON'), expected[scenario]['model']) and common.model_matches(value.get('roundTripJSON'), expected[scenario]['model'])
        passed = valid if supported else 'error' in value
        if not passed: raise RuntimeError(f'Whole-model oracle failed: {label}')
        if iterations and not valid: raise RuntimeError(f'Cannot time failed decoding: {label}')
        return value

    for scenario in expected:
        for engine in ['foundation', 'native', 'compatible', 'published', 'object']:
            label = f'check-{scenario}-{engine}'
            run_weather(engine, scenario, 0, label); checks[label] = True
    measurements = []
    if args.benchmark:
        for scenario, first, second in [('clean', 'foundation', 'native'), ('clean', 'foundation', 'compatible'), ('dirty', 'published', 'compatible')]:
            pair_samples = {first:[], second:[]}; ratios = []
            for round_index in range(args.rounds):
                samples = {first:[], second:[]}
                for block, engine in enumerate([first, second, second, first]):
                    value = run_weather(engine, scenario, args.iterations, f'bench-{scenario}-{first}-{second}-r{round_index}-b{block}')
                    normalized = [1000*sample/args.iterations for sample in value['sampleMilliseconds']]
                    expected_consumed = float(expected[scenario]['model']['payload']['locations'][0]['current']['temperature_2m'])*args.iterations*7
                    if len(normalized) != 7 or not all(math.isfinite(v) and v > 0 for v in normalized) or not math.isclose(value['consumed'], expected_consumed, rel_tol=1e-9, abs_tol=1e-6):
                        raise RuntimeError('Invalid samples or consumption')
                    samples[engine].extend(normalized); pair_samples[engine].extend(normalized)
                ratios.append(statistics.median(samples[second])/statistics.median(samples[first]))
            measurements.append(dict(scenario=scenario, first=first, second=second, roundRatios=ratios, medianRoundRatio=statistics.median(ratios),
                                     medianMicroseconds={key:statistics.median(value) for key,value in pair_samples.items()}, samplesMicroseconds=pair_samples))
    receipt.update(checks=checks, total=len(checks), passed=sum(checks.values()), allPassed=all(checks.values()), measurements=measurements,
                   binaryHashes={name:common.sha(args.output/name) for name in ['contract', 'weather', 'libYYModelSwift.dylib', 'libPublishedYY.dylib']},
                   finishedUTC=datetime.datetime.now(datetime.timezone.utc).isoformat())
    (args.output/'acceptance.json').write_text(json.dumps(receipt, indent=2))
    print(json.dumps({key:receipt[key] for key in ['total', 'passed', 'allPassed', 'measurements']}))
    return 0 if receipt['allPassed'] else 1


if __name__ == '__main__': raise SystemExit(main())
