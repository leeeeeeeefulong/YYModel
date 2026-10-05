#!/usr/bin/env python3
"""Compile current library and public consumers; retain a repeatable acceptance receipt."""
import argparse
import hashlib
import json
import platform
import subprocess
import struct
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--source-root', type=Path, default=ROOT,
                    help='Library source root; defaults to the current checkout')
parser.add_argument('--simulator', help='Booted arm64 iOS simulator UUID (runtime >= iOS 17)')
args = parser.parse_args()
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=False)
source_root = args.source_root.resolve()
source_paths = sorted((source_root / 'YYModelSwift').glob('*.swift'))
if not source_paths:
    raise RuntimeError(f'No Swift sources in {source_root}')
receipt = {'sources': {}, 'startedAt': datetime.now(timezone.utc).isoformat(),
           'platform': platform.platform(), 'commands': [], 'checks': [], 'passed': False}
if args.simulator:
    devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', '--json']))
    matches = [(runtime, device) for runtime, values in devices['devices'].items()
               for device in values if device['udid'] == args.simulator]
    if len(matches) != 1 or matches[0][1]['state'] != 'Booted':
        raise RuntimeError('The requested simulator must be available and booted')
    receipt['simulator'] = {'runtime': matches[0][0], 'device': matches[0][1]}

def error_fields_match(row, expected):
    """C12: when an expectation pins errorType/errorPath/errorKey, the observed row must
    match exactly. Absent pins fall back to the historical lenient 'any error' check.
    P2-4 attachments may additionally pin attachedLosses (absorbed-element count)."""
    for field in ('errorType', 'errorPath', 'errorKey', 'attachedLosses'):
        if field in expected and row.get(field) != expected[field]:
            return False
    return True

def freeze(path, relative):
    data = path.read_bytes()
    target = out / 'source' / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
    receipt['sources'][str(relative)] = hashlib.sha256(data).hexdigest()
    return target

sources = [freeze(p, Path('YYModelSwift') / p.name) for p in source_paths]
harness = {p.name: freeze(p, Path('Validation/remediation') / p.name)
           for p in sorted(HERE.glob('*.swift'))}
freeze(HERE / 'run.py', Path('Validation/remediation/run.py'))
expectations = {p.name: freeze(p, Path('Validation/remediation/expectations') / p.name)
                for p in sorted((HERE / 'expectations').glob('*.json'))}
for path in source_paths:
    relative = str(Path('YYModelSwift') / path.name)
    if hashlib.sha256(path.read_bytes()).hexdigest() != receipt['sources'][relative]:
        raise RuntimeError('Sources changed while creating the snapshot; rerun acceptance')

def run(command):
    command = list(map(str, command))
    if args.simulator and Path(command[0]).parent == out:
        command = ['xcrun', 'simctl', 'spawn', args.simulator, *command]
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
    index = len(receipt['commands'])
    (out / f'command-{index:02d}.log').write_text(result.stdout + result.stderr)
    receipt['commands'].append({'command': command, 'exitCode': result.returncode,
                                'log': f'command-{index:02d}.log'})
    (out / 'receipt.json').write_text(json.dumps(receipt, indent=2))
    if result.returncode:
        raise RuntimeError(result.stderr or result.stdout)

run(['swiftc', '--version'])
flags = ['-O', '-parse-as-library', '-swift-version', '6',
         '-strict-concurrency=complete', '-warnings-as-errors']
if args.simulator:
    sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], text=True).strip()
    flags += ['-sdk', sdk, '-target', 'arm64-apple-ios17.0-simulator']
run(['swiftc', *flags, '-emit-library', '-emit-module', '-module-name', 'YYModelSwift',
     '-emit-module-path', out / 'YYModelSwift.swiftmodule', *sources,
     '-o', out / 'libYYModelSwift.dylib'])
run(['swiftc', *flags, '-I', out, '-L', out, '-lYYModelSwift',
     '-Xlinker', '-rpath', '-Xlinker', out, harness['KeymapCollectionsE2E.swift'],
     '-o', out / 'KeymapCollectionsE2E'])
run([out / 'KeymapCollectionsE2E', out / 'observations.json'])
rows = json.loads((out / 'observations.json').read_text())
expected = {'set-distinct': 'count=2;bits=4607182418800017408,4607182418800017409',
            'set-single': 'count=1;bits=4607182418800017409',
            'model-array-path': 'value.Index 0', 'model-optional-path': 'value',
            'unkeyed-nested-cursor': '4607182418800017409,4611686018427387905',
            'set-float-distinct': 'count=2;bits=1065353216,1065353217',
            'dictionary-model-path': 'value.key'}
for scenario in ['optional-nested-array', 'renamed-parent', 'snake-parent',
                 'int-dictionary', 'path-collision']:
    expected[scenario] = '4607182418800017409'
for scenario, value in expected.items():
    pair = [r for r in rows if r['scenario'] == scenario]
    passed = len(pair) == 2 and {r['hook'] for r in pair} == {False, True} and all(
        r.get('result') == value and 'error' not in r for r in pair)
    receipt['checks'].append({'scenario': scenario, 'expected': value,
                              'observed': pair, 'passed': passed})
for consumer in ['NumericE2E', 'NumericBoundaryE2E', 'FloatMidpointE2E', 'RegistryE2E', 'ExtendedE2E', 'FieldResolutionE2E', 'DateAndCoercionE2E', 'LegacyNumberRouteE2E', 'R2EncodingE2E', 'BoundaryLifetimeE2E', 'TreeFoundationParityE2E', 'HookAncestorE2E', 'IntegerRouteSignedZeroE2E', 'TreeProtocolE2E', 'RepeatedEncodingE2E']:
    run(['swiftc', *flags, '-I', out, '-L', out, '-lYYModelSwift',
         '-Xlinker', '-rpath', '-Xlinker', out, harness[consumer + '.swift'],
         '-o', out / consumer])
    run([out / consumer, out / (consumer + '.json')])
    observations = json.loads((out / (consumer + '.json')).read_text())
    if not observations or len({r['scenario'] for r in observations}) != len(observations):
        raise RuntimeError(f'{consumer}: empty or duplicate observations')
    receipt['checks'].extend(observations)
for consumer, extra in [('BridgePathsConsumer', []), ('BridgeConsumer', []),
                        ('DoubleStressConsumer', []), ('ExternalRulesE2E', ['-DPUBLIC_API']),
                        ('CompositionConsumer', []), ('FastPathConsumer', []),
                        ('DesignConsumer', ['-D', 'KEY_PATH']), ('NewConsumer', []),
                        ('AutomaticDatesConsumer', []), ('ErrorContractConsumer', []),
                        ('WConsumer', []), ('PolymorphismConsumer', []),
                        ('TransformConsumer', []), ('StringToNumberConsumer', []),
                        ('LossyConsumer', []), ('PresenceConsumer', []),
                        ('LossyArrayConsumer', []), ('LossyAttachmentConsumer', [])]:
    run(['swiftc', *flags, *extra, '-I', out, '-L', out, '-lYYModelSwift',
         '-Xlinker', '-rpath', '-Xlinker', out, harness[consumer + '.swift'],
         '-o', out / consumer])
    run([out / consumer, out / (consumer + '.json')])
    values = json.loads((out / (consumer + '.json')).read_text())
    checks = []
    if consumer == 'ExternalRulesE2E':
        checks = [(k, v is True) for k, v in values['checks'].items()]
    elif consumer == 'DoubleStressConsumer':
        for row in values:
            expected_bits = str(struct.unpack('Q', struct.pack('d', float(row['token'])))[0])
            checks.append((row['token'], row.get('normalBits') == expected_bits and
                           row.get('hookedBits') == expected_bits))
    elif consumer == 'BridgeConsumer':
        checks = [(r['name'], r.get('bits') == '4607182418800017409') for r in values]
    elif consumer == 'BridgePathsConsumer':
        for scenario in sorted({r['scenario'] for r in values}):
            pair = [r for r in values if r['scenario'] == scenario]
            passed = len(pair) == 2 and (
                all('error' in r and 'typeMismatch' in r['error'] for r in pair)
                if 'type' in scenario else all(r.get('result') ==
                    '1.0000000000000002|4607182418800017409' for r in pair))
            checks.append((scenario, passed))
    elif consumer == 'CompositionConsumer':
        for row in values:
            if row['expected'] == 'review-validation error':
                passed = 'review-validation' in row.get('error', '')
            elif row['expected'] == 'configuration error':
                passed = 'configuration key' in row.get('error', '')
            elif isinstance(row.get('result'), str) and row['result'].startswith('{'):
                passed = json.loads(row['result']) == json.loads(row['expected'])
            else:
                passed = row.get('result') == row['expected'] and 'error' not in row
            checks.append((row['name'], passed))
    else:
        # These consumers intentionally contain rejected inputs and observational
        # diagnostics. Retain the historical contracts, allowing richer error paths.
        baseline = json.loads(expectations[consumer + '.json'].read_text())
        previous = {r['name']: r for r in baseline}
        for row in values:
            old = previous.get(row['name'], {})
            actual, expected_result = row.get('result'), old.get('result')
            if isinstance(actual, str) and isinstance(expected_result, str) and actual.startswith('{') and expected_result.startswith('{'):
                actual, expected_result = json.loads(actual), json.loads(expected_result)
            if 'result' in old:
                # C12: an expectation may additionally assert the structured error fields.
                passed = actual == expected_result and 'error' not in row and error_fields_match(row, old)
            else:
                # Historical "rejected input" rows still pass on any error unless the
                # baseline pinned errorType/errorPath (then those must match exactly).
                passed = 'error' in row and error_fields_match(row, old)
            checks.append((row['name'], passed))
        checks.append(('complete-observation-set', {r['name'] for r in values} == set(previous)))
    if not checks:
        raise RuntimeError(f'{consumer}: no acceptance checks')
    receipt['checks'].extend({'scenario': consumer + ':' + name, 'passed': passed}
                             for name, passed in checks)
receipt['passed'] = all(r['passed'] for r in receipt['checks'])
(out / 'receipt.json').write_text(json.dumps(receipt, indent=2))
for check in receipt['checks']:
    print(('PASS' if check['passed'] else 'FAIL') + ' ' + check['scenario'])
print(f"Receipt: {out / 'receipt.json'}")
raise SystemExit(0 if receipt['passed'] else 1)
