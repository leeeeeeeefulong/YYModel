#!/usr/bin/env python3
"""Read-only adjacent ABBA public-API remeasurement of existing optimized binaries."""
import argparse,datetime,hashlib,json,math,pathlib,platform,statistics,sys
REPO=pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0,str(REPO/'Validation'))
import run as common
import run_delivery as delivery

def main():
    p=argparse.ArgumentParser();p.add_argument('--existing',type=pathlib.Path,default=pathlib.Path('/tmp/YYModel-swift-contract-20261004/interop-ios'));p.add_argument('--output',type=pathlib.Path,required=True);p.add_argument('--original-root',type=pathlib.Path,required=True);p.add_argument('--iterations',type=int,default=1000);a=p.parse_args()
    source=a.existing.resolve();a.output=a.output.resolve();a.output.mkdir(parents=True,exist_ok=True)
    env=json.loads((source/'environment.json').read_text());expected=json.loads((source/'weather-expected.json').read_text())
    if not json.loads((source/'correctness.json').read_text())['allPassed']:raise RuntimeError('Existing correctness failed')
    for name,h in env['validationHashes'].items():
        if common.sha(REPO/'Validation'/name)!=h:raise RuntimeError('Harness mismatch: '+name)
    for name,h in env['sourceHashes'].items():
        if common.sha(REPO/name)!=h:raise RuntimeError('Current source mismatch: '+name)
    original=a.original_root.resolve()
    for name,h in env['originalSourceHashes'].items():
        if common.sha(original/name)!=h:raise RuntimeError('Original source mismatch: '+name)
    for scenario,oracle in expected.items():
        if common.sha(source/f'weather-{scenario}.json')!=oracle['sha256']:raise RuntimeError('Fixture mismatch')
    (a.output/'build').symlink_to(source/'build')
    for item in source.glob('weather-*.json'):(a.output/item.name).symlink_to(item)
    a.simulator=env['simulator'];start=datetime.datetime.now(datetime.timezone.utc).isoformat();all_pairs={}
    for channel,scenario,rounds in [('data','dirty',6),('data','clean',3),('object','dirty',3)]:
        case_name=channel+':'+scenario;observations=[];raw={}
        for round_index in range(rounds):
            blocks={'original':[],'current':[]}
            for phase,version in enumerate(['original','current','current','original']):
                label,value,file=delivery.run_case(a,version,'oc-only','oc',channel,scenario,a.iterations,'round-'+case_name.replace(':','-')+'-'+str(round_index)+'-'+str(phase))
                if not delivery.result_matches(value,expected[scenario],'oc',channel):raise RuntimeError('Public API result mismatch: '+label)
                expected_score=float(expected[scenario]['model']['payload']['locations'][0]['current']['temperature_2m'])
                if not math.isclose(value['consumed'],expected_score*a.iterations*7,rel_tol=1e-10,abs_tol=1e-8):raise RuntimeError('Consumed result mismatch')
                samples=[x/a.iterations for x in value['sampleMilliseconds']]
                if len(samples)!=7 or not all(math.isfinite(x) and x>0 for x in samples):raise RuntimeError('Invalid timing')
                blocks[version].extend(samples);raw[file.name]={'SHA256':common.sha(file),'values':samples}
            medians={v:statistics.median(xs) for v,xs in blocks.items()};ratio=medians['current']/medians['original'];observations.append({'round':round_index+1,'medians':medians,'currentOverOriginal':ratio,'samples':blocks})
            print(case_name,'round',round_index+1,'ratio',round(ratio,6),flush=True)
        ratios=[v['currentOverOriginal'] for v in observations];pooled={v:[s for o in observations for s in o['samples'][v]] for v in ['original','current']};pooled_medians={v:statistics.median(xs) for v,xs in pooled.items()}
        all_pairs[case_name]={'rounds':observations,'medianRoundRatio':statistics.median(ratios),'minRoundRatio':min(ratios),'maxRoundRatio':max(ratios),'pooledMedians':pooled_medians,'pooledMedianRatio':pooled_medians['current']/pooled_medians['original'],'rawResultHashes':raw}
    receipt={'startedUTC':start,'finishedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'runtime':'iOS Simulator','simulator':a.simulator,'priorEnvironment':env,'execution':'Existing standalone OC -O2 binaries, single-process sequential ABBA','iterationsPerSample':a.iterations,'samplesPerBlock':7,'warmups':5,'ABBA':['original','current','current','original'],'runnerSHA256':common.sha(pathlib.Path(__file__)),'binarySHA256':{p.name:common.sha(p) for p in [source/'build/current-oc-only',source/'build/original-oc-only']},'pairs':all_pairs,'allResultAndConsumedChecksPassed':True}
    (a.output/'receipt.json').write_text(json.dumps(receipt,indent=2));print(json.dumps({k:{x:v[x] for x in ['medianRoundRatio','minRoundRatio','maxRoundRatio','pooledMedianRatio']} for k,v in all_pairs.items()},indent=2),flush=True)

if __name__=='__main__':main()
