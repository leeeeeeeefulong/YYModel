#!/usr/bin/env python3
"""Fetch a fresh Open-Meteo multi-city response and preserve original bytes/provenance."""
import argparse, hashlib, json, urllib.request, urllib.parse, urllib.error
from pathlib import Path
from datetime import datetime, timezone
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
a.output.mkdir(parents=True,exist_ok=True)
if (a.output/'weather-api.json').exists():raise SystemExit('Refusing to overwrite an existing frozen snapshot')
params={'latitude':'31.23,40.71,35.68','longitude':'121.47,-74.01,139.69','current':'temperature_2m,relative_humidity_2m,is_day,precipitation,wind_speed_10m','hourly':'temperature_2m,relative_humidity_2m,precipitation,wind_speed_10m','daily':'temperature_2m_max,temperature_2m_min,precipitation_sum','forecast_days':'3','timezone':'auto'}
url='https://api.open-meteo.com/v1/forecast?'+urllib.parse.urlencode(params)
req=urllib.request.Request(url,headers={'User-Agent':'YYModel-public-api-verification/1.0','Accept':'application/json'})
with urllib.request.urlopen(req,timeout=45) as response:
 data=response.read();status=response.status;headers={k:response.headers.get(k) for k in ['Content-Type','Date','ETag','Last-Modified']}
parsed=json.loads(data)
if not isinstance(parsed,list) or len(parsed)!=3:raise RuntimeError('Expected three independent city responses')
for city in parsed:
 for key in ['latitude','longitude','current','hourly','daily']:assert key in city,key
 assert len(city['hourly']['time'])>0 and len(city['daily']['time'])>0
(a.output/'weather-api.json').write_bytes(data)
metadata={'provider':'Open-Meteo','providerURL':'https://open-meteo.com/','documentation':'https://open-meteo.com/en/docs','license':'CC BY 4.0','attribution':'Weather data by Open-Meteo (https://open-meteo.com/)','fetchedAtUTC':datetime.now(timezone.utc).isoformat(),'url':url,'httpStatus':status,'headers':headers,'sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data),'cities':['Shanghai','New York','Tokyo'],'hourlyRows':[len(c['hourly']['time']) for c in parsed],'dailyRows':[len(c['daily']['time']) for c in parsed]}
(a.output/'weather-source.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(metadata,ensure_ascii=False))

# A separately captured real service error; no malformed synthetic forecast is
# presented as an API response. Preserve both responses for offline replay.
error_params={'latitude':'31.23','longitude':'121.47','hourly':'invalid_variable_for_validation'}
error_url='https://api.open-meteo.com/v1/forecast?'+urllib.parse.urlencode(error_params)
try:
 with urllib.request.urlopen(urllib.request.Request(error_url,headers={'User-Agent':'YYModel-public-api-verification/1.0'}),timeout=45) as response:
  raise RuntimeError('Expected API to reject the invalid hourly variable with HTTP400')
except urllib.error.HTTPError as response:
 error_data=response.read()
 if response.code != 400:raise
 error_object=json.loads(error_data)
 if error_object.get('error') is not True or not isinstance(error_object.get('reason'),str):raise RuntimeError('Unexpected API error schema')
 (a.output/'weather-error.json').write_bytes(error_data)
 error_metadata={'provider':'Open-Meteo','url':error_url,'httpStatus':response.code,'fetchedAtUTC':datetime.now(timezone.utc).isoformat(),'sha256':hashlib.sha256(error_data).hexdigest(),'bytes':len(error_data),'attribution':metadata['attribution']}
 (a.output/'weather-error-source.json').write_text(json.dumps(error_metadata,ensure_ascii=False,indent=2)+'\n')
 print(json.dumps(error_metadata,ensure_ascii=False))
