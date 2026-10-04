#!/usr/bin/env python3
"""Standalone, offline public-API validation and gated parsing benchmark."""
import argparse
import collections
import copy
import hashlib
import json
import math
import platform
import statistics
import subprocess
import sys
from pathlib import Path
from generate_numeric import cases

HERE=Path(__file__).resolve().parent

def swift_flags(args):
    return ['-O']+(['-sdk',args.sdk,'-target','arm64-apple-ios17.0-simulator'] if args.simulator else [])

def objc_flags(args):
    return ['-O2','-fobjc-arc','-framework','Foundation','-Wall','-Wno-deprecated-declarations']+(['-isysroot',args.sdk,'-target','arm64-apple-ios17.0-simulator'] if args.simulator else [])

def binary_command(args,command):
    return (['xcrun','simctl','spawn',args.simulator] if args.simulator else [])+command

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def execute(args, output, log):
    p=subprocess.run([str(x) for x in args],capture_output=True,text=True)
    (output/log).write_text('Command: '+json.dumps([str(x) for x in args])+'\n'+p.stdout+p.stderr)
    if p.returncode: raise RuntimeError(f'Command exited {p.returncode}; see {output/log}')
    return p.stdout.strip()

def projection(document):
    forecasts=document['payload']['locations']
    return dict(locations=len(forecasts),hours=sum(len(f.get('hourly',{}).get('time',[])) for f in forecasts),
                days=sum(len(f['daily']['time']) for f in forecasts),
                latitudeSum=sum(float(f.get('latitude',0)) for f in forecasts),
                currentTemperatureSum=sum(float(f['current']['temperature_2m']) for f in forecasts),
                hourlyTemperatureSum=sum(sum(float(v) for v in f.get('hourly',{}).get('temperature_2m',[]) if v is not None) for f in forecasts),
                hourlyTemperatureCount=sum(len(f.get('hourly',{}).get('temperature_2m',[])) for f in forecasts),
                unitKeys=sum(len(f[key]) for f in forecasts for key in ['current_units','hourly_units','daily_units']),
                trace=document['request']['trace_id'],ok=document['ok'] in [True,'yes'],warnings=len(document['warnings']),
                nullWarnings=sum(v is None for v in document['warnings']),firstTime=forecasts[0].get('hourly',{}).get('time',[''])[0])

def equivalent(actual,expected):
    if not isinstance(actual,dict) or set(actual)!=set(expected):return False
    for key,value in expected.items():
        if isinstance(value,float):
            if not isinstance(actual[key],(int,float)) or not math.isclose(actual[key],value,rel_tol=1e-10,abs_tol=1e-8):return False
        elif actual[key]!=value:return False
    return True

def canonical_model(document):
    """Common business types; OC raw NSArray values are explicitly normalized."""
    forecasts=[]
    for f in document['payload']['locations']:
        model={key:float(f.get(key,0)) for key in ['latitude','longitude','generationtime_ms','elevation']}
        model['utc_offset_seconds']=int(f['utc_offset_seconds'])
        for key in ['timezone','timezone_abbreviation','current_units','hourly_units','daily_units']:model[key]=f[key]
        current=f['current']
        model['current']={key:(current[key] if key=='time' else float(current[key])) for key in ['time','interval','temperature_2m','relative_humidity_2m','is_day','precipitation','weather_code','wind_speed_10m']}
        if 'hourly' in f:
            model['hourly']={key:([str(v) for v in f['hourly'][key]] if key=='time' else [None if v is None else float(v) for v in f['hourly'][key]]) for key in ['time','temperature_2m','relative_humidity_2m','precipitation_probability','precipitation','weather_code','wind_speed_10m']}
        model['daily']={key:([str(v) for v in f['daily'][key]] if key in ['time','sunrise','sunset'] else [None if v is None else float(v) for v in f['daily'][key]]) for key in ['time','temperature_2m_max','temperature_2m_min','precipitation_sum','sunrise','sunset']}
        forecasts.append(model)
    return dict(request=document['request'],payload=dict(locations=forecasts),ok=document['ok'] in [True,'yes'],warnings=document['warnings'])

def deep_equivalent(actual,expected):
    if isinstance(expected,dict):
        return isinstance(actual,dict) and set(actual)==set(expected) and all(deep_equivalent(actual[k],v) for k,v in expected.items())
    if isinstance(expected,list):
        return isinstance(actual,list) and len(actual)==len(expected) and all(deep_equivalent(a,b) for a,b in zip(actual,expected))
    if isinstance(expected,float):
        return isinstance(actual,(int,float)) and math.isclose(actual,expected,rel_tol=1e-10,abs_tol=1e-8)
    return actual==expected

def model_matches(actual,expected):
    if not isinstance(actual,dict):return False
    try:return deep_equivalent(canonical_model(actual),expected)
    except (KeyError,TypeError,ValueError):return False

def fixtures(output):
    raw=json.loads((HERE/'fixtures/weather-api.json').read_text())
    clean=dict(ok=True,request={'trace_id':'open-weather-1729'},payload={'locations':raw},warnings=[None,'public fixture'])
    dirty=copy.deepcopy(clean)
    dirty['ok']='yes'
    dirty['payload']['locations'][0]['latitude']=str(raw[0]['latitude'])
    dirty['payload']['locations'][0]['current']['temperature_2m']=str(raw[0]['current']['temperature_2m'])
    dirty['payload']['locations'][0]['hourly']['temperature_2m'][0]=str(raw[0]['hourly']['temperature_2m'][0])
    nullable=copy.deepcopy(clean)
    nullable['payload']['locations'][0]['hourly']['temperature_2m'][2]=None
    sparse=copy.deepcopy(clean)
    del sparse['payload']['locations'][0]['latitude']
    del sparse['payload']['locations'][0]['hourly']
    large=copy.deepcopy(clean)
    large['payload']['locations']=copy.deepcopy(raw*32)
    data={name:document for name,document in [('clean',clean),('dirty',dirty),('nullable',nullable),('sparse',sparse),('large',large)]}
    expected={}
    for name,document in data.items():
        path=output/f'weather-{name}.json'
        path.write_text(json.dumps(document,separators=(',',':'),ensure_ascii=False))
        expected[name]=dict(projection=projection(document),model=canonical_model(document),bytes=path.stat().st_size,sha256=sha(path),nativeSupported=name not in ['dirty','sparse'])
    (output/'weather-expected.json').write_text(json.dumps(expected,indent=2))
    return expected

def run_weather(args,output):
    expected=fixtures(output)
    swift=output/'weather-swift'
    execute(['swiftc',*swift_flags(args),*sorted((args.source_root/'YYModelSwift').glob('*.swift')),HERE/'WeatherE2E.swift','-o',swift],output,'weather-swift-build.log')
    engines={'swiftNative':(swift,'native'),'swiftYY':(swift,'yy')}
    for name,sources in [('ocCurrent',args.source_root/'YYModel'),('ocOriginal',args.original_source)]:
        if sources is None:continue
        binary=output/name
        execute(['clang',*objc_flags(args),'-I',sources,*sources.glob('*.m'),HERE/'WeatherE2E.m','-o',binary],output,f'{name}-build.log')
        engines[name]=(binary,None)
    gates={}; benchmark={}
    for scenario,oracle in expected.items():
        for engine,(binary,mode) in engines.items():
            key=f'{scenario}-{engine}'
            result_path=output/f'correctness-{key}.json'
            command=[binary,output/f'weather-{scenario}.json',result_path]
            command += [mode,'0'] if mode else ['0']
            execute(binary_command(args,command),output,f'correctness-{key}.log')
            result=json.loads(result_path.read_text())
            if engine=='swiftNative' and not oracle['nativeSupported']:
                gates[key]='error' in result
                continue
            gates[key]=equivalent(result.get('summary'),oracle['projection'])
            gates[key]=gates[key] and model_matches(result.get('modelJSON'),oracle['model'])
            if mode is None:
                gates[key]=gates[key] and result.get('nestedExport') is True and equivalent(result.get('roundTripSummary'),oracle['projection']) and model_matches(result.get('roundTripModelJSON'),oracle['model'])
    # Correctness for every scenario/engine is decided before any timing begins.
    if args.no_benchmark:
        (output/'weather-results.json').write_text(json.dumps(dict(correctness=gates,benchmark={},allCorrect=all(gates.values())),indent=2))
        return all(gates.values())
    for scenario,oracle in expected.items():
        for engine,(binary,mode) in engines.items():
            key=f'{scenario}-{engine}'
            if not gates[key] or (engine=='swiftNative' and not oracle['nativeSupported']):continue
            iterations=8 if scenario=='large' else args.iterations
            result_path=output/f'benchmark-{key}.json'
            command=[binary,output/f'weather-{scenario}.json',result_path]
            command += [mode,str(iterations)] if mode else [str(iterations)]
            execute(binary_command(args,command),output,f'benchmark-{key}.log')
            result=json.loads(result_path.read_text())
            if 'sampleMilliseconds' not in result or not equivalent(result.get('summary'),oracle['projection']) or not model_matches(result.get('modelJSON'),oracle['model']):
                gates[key]=False;continue
            per=[v/iterations for v in result['sampleMilliseconds']]
            benchmark[key]=dict(medianMillisecondsPerDecode=statistics.median(per),minMillisecondsPerDecode=min(per),maxMillisecondsPerDecode=max(per),samplesMillisecondsPerDecode=per,iterationsPerSample=iterations,bytes=oracle['bytes'])
    (output/'weather-results.json').write_text(json.dumps(dict(correctness=gates,benchmark=benchmark,allCorrect=all(gates.values())),indent=2))
    return all(gates.values())

def run_numeric(args,output):
    inputs=output/'numeric-cases.json'; inputs.write_text(json.dumps(cases(),indent=2,ensure_ascii=False))
    binary=output/'numeric-e2e'
    execute(['swiftc',*swift_flags(args),*sorted((args.source_root/'YYModelSwift').glob('*.swift')),HERE/'NumericE2E.swift','-o',binary],output,'numeric-build.log')
    result=output/'numeric-results.json'
    execute(binary_command(args,[binary,inputs,result]),output,'numeric.log')
    values=json.loads(result.read_text()); failures=[x for x in values if not x['passed']]
    summary=dict(total=len(values),passed=len(values)-len(failures),failed=len(failures),failuresByLabel=dict(collections.Counter(x['label'] for x in failures)))
    (output/'numeric-summary.json').write_text(json.dumps(summary,indent=2))
    return not failures

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--source-root',type=Path,default=HERE.parent)
    parser.add_argument('--original-source',type=Path,help='ibireme YYModel source folder containing *.m')
    parser.add_argument('--output',type=Path,default=HERE/'artifacts')
    parser.add_argument('--iterations',type=int,default=100)
    parser.add_argument('--only',choices=['all','numeric','weather'],default='all')
    parser.add_argument('--simulator',help='UUID of a booted arm64 iOS simulator; no application project needed')
    parser.add_argument('--no-benchmark',action='store_true',help='Check correctness only; safe to run concurrent validation jobs')
    args=parser.parse_args()
    args.source_root=args.source_root.resolve(); args.output=args.output.resolve()
    if args.original_source:args.original_source=args.original_source.resolve()
    if args.iterations<1:parser.error('iterations must be positive')
    args.sdk=subprocess.check_output(['xcrun','--sdk','iphonesimulator','--show-sdk-path'],text=True).strip() if args.simulator else None
    args.output.mkdir(parents=True,exist_ok=True)
    print('Source:',args.source_root,'; output:',args.output,flush=True)
    provider=json.loads((HERE/'fixtures/weather-source.json').read_text())
    if sha(HERE/'fixtures/weather-api.json')!=provider['sha256']:raise RuntimeError('Weather snapshot SHA-256 differs from provenance')
    metadata=dict(architecture=platform.machine(),system=platform.platform(),runtime='iOS Simulator' if args.simulator else 'macOS',simulator=args.simulator,
                  cpu=subprocess.check_output(['sysctl','-n','machdep.cpu.brand_string'],text=True).strip(),xcode=subprocess.check_output(['xcodebuild','-version'],text=True).strip(),
                  swift=subprocess.check_output(['swiftc','-version'],text=True,stderr=subprocess.STDOUT).strip(),
                  sourceHashes={p:sha(args.source_root/p) for p in ['YYModel/NSObject+YYModel.m','YYModel/YYClassInfo.m','YYModelSwift/YYJSONDecoder.swift']},
                  validationHashes={p:sha(HERE/p) for p in ['run.py','generate_numeric.py','NumericE2E.swift','WeatherE2E.swift','WeatherE2E.m']},
                  fixtureProvider=provider,
                  parameters=dict(iterations=args.iterations,samples=7,warmups=5,benchmarkEnabled=not args.no_benchmark,networkIncludedInTiming=False,swiftOptimization='-O',objcOptimization='-O2'))
    (args.output/'environment.json').write_text(json.dumps(metadata,indent=2))
    results={}
    if args.only in ['all','numeric']:results['numeric']=run_numeric(args,args.output)
    if args.only in ['all','weather']:results['weather']=run_weather(args,args.output)
    acceptance='acceptance.json' if args.only=='all' else f'acceptance-{args.only}.json'
    (args.output/acceptance).write_text(json.dumps(dict(checks=results,allPassed=all(results.values())),indent=2))
    print(json.dumps(results),flush=True)
    return 0 if all(results.values()) else 1

if __name__=='__main__':raise SystemExit(main())
