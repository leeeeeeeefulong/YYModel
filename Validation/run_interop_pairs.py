#!/usr/bin/env python3
"""Measure current cross-language/mixed public APIs after full delivery gates."""
import argparse
import datetime
import json
import math
import statistics
from pathlib import Path
import run as common
import run_delivery as delivery


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--existing', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--rounds', type=int, default=3)
    parser.add_argument('--iterations', type=int, default=250)
    args = parser.parse_args()
    existing = args.existing.resolve(); args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    environment = json.loads((existing/'environment.json').read_text())
    if not json.loads((existing/'correctness.json').read_text())['allPassed']:
        raise RuntimeError('Delivery correctness gate failed')
    for name, digest in environment['sourceHashes'].items():
        if common.sha(delivery.HERE.parent/name) != digest:
            raise RuntimeError('Source changed: '+name)
    for name, digest in environment['validationHashes'].items():
        if common.sha(delivery.HERE/name) != digest:
            raise RuntimeError('Delivery harness changed: '+name)
    expected = json.loads((existing/'weather-expected.json').read_text())
    for scenario, oracle in expected.items():
        if common.sha(existing/f'weather-{scenario}.json') != oracle['sha256']:
            raise RuntimeError('Fixture changed: '+scenario)
    args.simulator = environment['simulator']
    (args.output/'build').symlink_to(existing/'build')
    for file in existing.glob('weather-*.json'):
        (args.output/file.name).symlink_to(file)
    pairs = [
        ('Swift-to-OC:data', ('mixed', 'oc', 'data'), ('mixed', 'swift-oc', 'data')),
        ('Swift-to-OC:object', ('mixed', 'oc', 'object'), ('mixed', 'swift-oc', 'object')),
        ('OC:mixed-link', ('oc-only', 'oc', 'data'), ('mixed', 'oc', 'data')),
        ('Swift-legacy:mixed-link', ('swift-only', 'yy', 'data'), ('mixed', 'yy', 'data')),
    ]
    results = {}
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    for name, first, second in pairs:
        rounds = []; pooled = {'first': [], 'second': []}
        for round_index in range(args.rounds):
            samples = {'first': [], 'second': []}
            for phase, (side, case) in enumerate([('first', first), ('second', second), ('second', second), ('first', first)]):
                binary, engine, channel = case
                label, value, file = delivery.run_case(args, 'current', binary, engine, channel, 'dirty', args.iterations,
                                                     name.replace(':', '-')+f'-r{round_index}-b{phase}')
                if not delivery.result_matches(value, expected['dirty'], engine, channel):
                    raise RuntimeError('Whole-model mismatch: '+label)
                score = float(expected['dirty']['model']['payload']['locations'][0]['current']['temperature_2m'])
                values = [1000*sample/args.iterations for sample in value['sampleMilliseconds']]
                if len(values) != 7 or not all(math.isfinite(v) and v > 0 for v in values):
                    raise RuntimeError('Invalid timing: '+label)
                if not math.isclose(value['consumed'], score*args.iterations*7, rel_tol=1e-10, abs_tol=1e-8):
                    raise RuntimeError('Consumed result mismatch: '+label)
                samples[side].extend(values); pooled[side].extend(values)
            ratio = statistics.median(samples['second'])/statistics.median(samples['first'])
            rounds.append({'round': round_index+1, 'secondOverFirst': ratio, 'samplesMicroseconds': samples})
            print(name, round_index+1, round(ratio, 6), flush=True)
        results[name] = dict(first=first, second=second, rounds=rounds,
                             medianRoundRatio=statistics.median(r['secondOverFirst'] for r in rounds),
                             medianMicroseconds={side: statistics.median(values) for side, values in pooled.items()})
    receipt = dict(startedUTC=started, finishedUTC=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                   environment=environment, runtime='iOS Simulator' if args.simulator else 'macOS',
                   iterations=args.iterations, samplesPerBlock=7, warmup=5, order=['first', 'second', 'second', 'first'],
                   scenario='dirty', swiftMode='legacy (no-argument YYJSONDecoder)',
                   excluded=['network', 'file reads', 'initial object bridge', 'compilation', 'verification export'],
                   runnerSHA256=common.sha(Path(__file__)),
                   binarySHA256={name: common.sha(existing/'build'/name) for name in ['current-oc-only', 'current-mixed', 'current-swift-only']},
                   pairs=results, allResultAndConsumedChecksPassed=True)
    (args.output/'receipt.json').write_text(json.dumps(receipt, indent=2))


if __name__ == '__main__':
    main()
