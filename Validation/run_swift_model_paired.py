#!/usr/bin/env python3
"""Adjacent ABBA comparisons using already validated Swift-only/mixed artifacts."""
import argparse
import json
import statistics
from pathlib import Path
import run as common


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--swift-output',type=Path,required=True)
    p.add_argument('--mixed-output',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    a=p.parse_args(); a.output=a.output.resolve();a.output.mkdir(parents=True,exist_ok=True)
    left=a.swift_output.resolve();right=a.mixed_output.resolve()
    environments=[json.loads((root/'environment.json').read_text()) for root in [left,right]]
    for key in ['sourceHashes','validationHashes','runtime','simulator','provider']:
        if environments[0][key]!=environments[1][key]:raise RuntimeError('Artifact identity mismatch: '+key)
    for root in [left,right]:
        if not json.loads((root/'acceptance.json').read_text())['allPassed']:raise RuntimeError('Correctness gate failed')
    a.simulator=environments[0]['simulator']
    pairs=[('native/model:clean',left,'native',left,'model','clean'),
           ('legacy/model:dirty',left,'legacy',left,'model','dirty'),
           ('legacy/model:sparse',left,'legacy',left,'model','sparse')]
    pairs += [('mixed:'+mode+':'+fixture,left,mode,right,mode,fixture) for fixture,mode in [('clean','model'),('dirty','model'),('large','model'),('clean','object'),('clean','encode')]]
    results=[]
    for index,(label,l,lmode,r,rmode,fixture) in enumerate(pairs):
        samples={'left':[],'right':[]}; hashes=[]
        expected=json.loads((l/'weather-expected.json').read_text())[fixture]['model']
        iterations=3 if fixture=='large' else 100
        for phase,(side,root,mode) in enumerate([('left',l,lmode),('right',r,rmode),('right',r,rmode),('left',l,lmode)]):
            output=a.output/f'{index}-{phase}.json'
            common.execute(common.binary_command(a,[root/'weather',root/f'weather-{fixture}.json',output,mode,str(iterations)]),a.output,f'{index}-{phase}.log')
            value=json.loads(output.read_text())
            if 'error' in value or not common.model_matches(value.get('modelJSON'),expected):raise RuntimeError('Model mismatch: '+label)
            if mode=='encode' and not common.model_matches(value.get('encodedJSON'),expected):raise RuntimeError('Export mismatch: '+label)
            samples[side].extend(x*1000/iterations for x in value['sampleMilliseconds']);hashes.append(common.sha(output))
        lm=statistics.median(samples['left']);rm=statistics.median(samples['right'])
        results.append(dict(label=label,fixture=fixture,leftEngine=lmode,rightEngine=rmode,order=['left','right','right','left'],samplesMicroseconds=samples,leftMedianMicroseconds=lm,rightMedianMicroseconds=rm,rightOverLeftRatio=rm/lm,resultHashes=hashes))
        print(label,round(rm/lm,4),flush=True)
    result=dict(environments=environments,harnessSHA256=common.sha(Path(__file__)),pairs=results)
    (a.output/'paired.json').write_text(json.dumps(result,indent=2))
    return 0

if __name__=='__main__':raise SystemExit(main())
