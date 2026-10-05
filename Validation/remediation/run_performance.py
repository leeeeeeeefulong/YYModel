#!/usr/bin/env python3
"""Benchmark an accepted frozen library and retain commands, inputs and results."""
import argparse
import hashlib
import json
import platform
import re
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--acceptance-root', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
accepted = args.acceptance_root.resolve()
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=False)
acceptance = json.loads((accepted / 'receipt.json').read_text())
if not acceptance.get('passed'):
    raise RuntimeError('Use a complete accepted frozen library')
receipt = {'platform': platform.platform(), 'acceptanceRoot': str(accepted),
           'sourceHashes': acceptance['sources'], 'commands': [], 'completed': False}
for name in ['receipt.json', 'libYYModelSwift.dylib', 'YYModelSwift.swiftmodule']:
    receipt.setdefault('inputHashes', {})[name] = hashlib.sha256((accepted / name).read_bytes()).hexdigest()
consumer = out / 'PerformanceConsumer.swift'
consumer.write_bytes((HERE / consumer.name).read_bytes())
(out / 'run_performance.py').write_bytes(Path(__file__).read_bytes())
receipt['consumerHash'] = hashlib.sha256(consumer.read_bytes()).hexdigest()

def run(command):
    command = list(map(str, command))
    result = subprocess.run(command, capture_output=True, text=True)
    log = f'command-{len(receipt["commands"]):02d}.log'
    (out / log).write_text(result.stdout + result.stderr)
    receipt['commands'].append({'command': command, 'exitCode': result.returncode, 'log': log})
    (out / 'receipt.json').write_text(json.dumps(receipt, indent=2))
    if result.returncode:
        raise RuntimeError(f'Benchmark failed: see {out / log}')
    return result.stdout

run(['swiftc', '--version'])
run(['swiftc', '-O', '-swift-version', '6', '-I', accepted, '-L', accepted,
     '-lYYModelSwift', '-Xlinker', '-rpath', '-Xlinker', accepted,
     consumer, '-o', out / 'PerformanceConsumer'])
log = run([out / 'PerformanceConsumer'])
rows = re.findall(r'\s+(Tiny|Mid|Payload)\s+\(\d+ fields\) official ([\d.]+) \| yy ([\d.]+) \| ratio ([\d.]+)x', log)
if len(rows) != 7:
    raise RuntimeError('Missing benchmark results')
receipt['measurements'] = [{'mode': mode, 'model': row[0], 'officialMs': float(row[1]),
                            'yyMs': float(row[2]), 'ratio': float(row[3])}
                           for mode, row in zip(['native'] * 3 + ['compatible'] * 3 + ['legacy'], rows)]
receipt['completed'] = True
(out / 'receipt.json').write_text(json.dumps(receipt, indent=2))
print(log)
