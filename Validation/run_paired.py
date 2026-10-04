#!/usr/bin/env python3
"""Adjacent ABBA remeasurement, without rebuilding or changing acceptance inputs."""
import argparse
import json
import math
import statistics
from pathlib import Path
import run as common
import run_delivery as delivery


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--delivery-output', type=Path, required=True)
    args = parser.parse_args()
    args.output = args.delivery_output.resolve()
    environment = json.loads((args.output/'environment.json').read_text())
    if not json.loads((args.output/'correctness.json').read_text())['allPassed']: raise RuntimeError('Correctness failed')
    args.simulator = environment['simulator']
    for name, h in environment['validationHashes'].items():
        if common.sha(delivery.HERE/name) != h: raise RuntimeError('Delivery harness changed')
    expected = json.loads((args.output/'weather-expected.json').read_text())
    pairs = []
    for channel, scenarios in [('data',list(expected)),('object',['clean','dirty','large']),('encode',['clean','large'])]:
        for scenario in scenarios:
            pairs.append(('OC-original:'+channel+':'+scenario,
                         ('original','oc-only','oc',channel,scenario),('current','oc-only','oc',channel,scenario)))
    pairs.extend([
        ('Swift-native:clean',('current','swift-only','native','data','clean'),('current','swift-only','yy','data','clean')),
        ('Swift-mixed:clean',('current','swift-only','yy','data','clean'),('current','mixed','yy','data','clean')),
        ('Swift-OC-caller:clean',('current','mixed','oc','data','clean'),('current','mixed','swift-oc','data','clean')),
        ('OC-mixed:clean',('current','oc-only','oc','data','clean'),('current','mixed','oc','data','clean'))])
    results = {}
    for index,(name,left,right) in enumerate(pairs):
        value = dict(left=':'.join(left),right=':'.join(right),order=['left','right','right','left'],samples={})
        for phase,case in enumerate([left,right,right,left]):
            iterations = 32 if case[-1]=='large' else 500
            label,result,file = delivery.run_case(args,*case,iterations,'paired'+str(index)+'-'+str(phase))
            if not delivery.result_matches(result,expected[case[-1]],case[2],case[3]): raise RuntimeError('Model mismatch: '+label)
            consumed = result['encodedBytes'] if case[3]=='encode' else float(expected[case[-1]]['model']['payload']['locations'][0]['current']['temperature_2m'])
            if not math.isclose(result['consumed'],consumed*iterations*7,rel_tol=1e-10,abs_tol=1e-8): raise RuntimeError('Invalid consumed result')
            samples = [x/iterations for x in result['sampleMilliseconds']]
            if len(samples)!=7 or not all(math.isfinite(x) and x>0 for x in samples): raise RuntimeError('Invalid timing')
            entry=value['samples'].setdefault(label,dict(values=[],resultHashes=[],iterationsPerSample=iterations))
            entry['values'].extend(samples);entry['resultHashes'].append(common.sha(file))
        for entry in value['samples'].values():
            entry['medianMilliseconds']=statistics.median(entry['values'])
            entry['minMilliseconds']=min(entry['values']);entry['maxMilliseconds']=max(entry['values'])
        value['rightOverLeftRatio']=value['samples'][value['right']]['medianMilliseconds']/value['samples'][value['left']]['medianMilliseconds']
        results[name]=value
        print(index+1,'/',len(pairs),name,'ratio',round(value['rightOverLeftRatio'],4),flush=True)
    metadata=dict(deliveryEnvironment=environment,validationSHA256=common.sha(Path(__file__)),pairs=results)
    (args.output/'paired.json').write_text(json.dumps(metadata,indent=2))
    return 0


if __name__=='__main__':raise SystemExit(main())
