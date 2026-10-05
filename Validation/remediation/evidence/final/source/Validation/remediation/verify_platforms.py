#!/usr/bin/env python3
"""Strict language/deployment-floor compilation against an accepted source snapshot."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--acceptance-root', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
accepted = args.acceptance_root.resolve()
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=False)
acceptance = json.loads((accepted / 'receipt.json').read_text())
if not acceptance.get('passed'):
    raise RuntimeError('A complete accepted source snapshot is required')
sources = sorted((accepted / 'source/YYModelSwift').glob('*.swift'))
for p in sources:
    if hashlib.sha256(p.read_bytes()).hexdigest() != acceptance['sources']['YYModelSwift/' + p.name]:
        raise RuntimeError(f'Snapshot hash mismatch: {p}')
receipt = {'sourceHashes': {k: v for k, v in acceptance['sources'].items() if k.startswith('YYModelSwift/')},
           'commands': [], 'passed': False, 'runtimeTested': False}

def run(command):
    command = list(map(str, command))
    result = subprocess.run(command, capture_output=True, text=True)
    log = f'command-{len(receipt["commands"]):02d}.log'
    (out / log).write_text(result.stdout + result.stderr)
    receipt['commands'].append({'command': command, 'exitCode': result.returncode, 'log': log})
    (out / 'receipt.json').write_text(json.dumps(receipt, indent=2))
    if result.returncode:
        raise RuntimeError(f'Compilation failed: {out / log}')
    return result.stdout.strip()

run(['swiftc', '--version'])
for version in ['5', '6']:
    run(['swiftc', '-typecheck', '-swift-version', version, '-strict-concurrency=complete',
         '-warnings-as-errors', *sources])
consumer = out / 'FloorConsumer.swift'
consumer.write_text('''import Foundation
import YYModelSwift
struct Payload: Codable { let value: Int64 }
func compileOnly(_ data: Data) throws {
    var decoder = YYJSONDecoder.compatible()
    decoder.numberParsingStrategy = .integerTokens
    decoder.userInfo[YYModelCoercionReport.key] = YYModelCoercionReport()
    let value = try decoder.decode(Payload.self, from: data)
    var encoder = YYJSONEncoder.compatible()
    let rules = try YYJSONRules().forType(Date.self) { $0.dateStrategy = .microsecondsSince1970 }
    encoder = YYJSONEncoder.compatible(rules: rules)
    _ = try encoder.encodeJSONObject(value)
    _ = YYModelCapability.foundationExactDecimal
}
''')
for sdk, target in [('iphoneos', 'arm64-apple-ios11.0'), ('watchos', 'arm64-apple-watchos4.0'),
                    ('appletvos', 'arm64-apple-tvos11.0'), ('macosx', 'x86_64-apple-macos10.13')]:
    sdk_path = run(['xcrun', '--sdk', sdk, '--show-sdk-path'])
    module_dir = out / sdk
    module_dir.mkdir()
    flags = ['-sdk', sdk_path, '-target', target, '-swift-version', '6',
             '-strict-concurrency=complete', '-warnings-as-errors']
    run(['swiftc', '-emit-module', '-parse-as-library', '-module-name', 'YYModelSwift',
         '-emit-module-path', module_dir / 'YYModelSwift.swiftmodule', *flags, *sources])
    run(['swiftc', '-typecheck', *flags, '-I', module_dir, consumer])
receipt['passed'] = True
(out / 'receipt.json').write_text(json.dumps(receipt, indent=2))
(out / 'verify_platforms.py').write_bytes(Path(__file__).read_bytes())
print('Swift 5/6 strict compilation and four library/consumer floors passed; no old OS runtime tested.')
