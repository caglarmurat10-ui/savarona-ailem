#!/usr/bin/env python3
import base64,json,os,time,urllib.parse,urllib.request,urllib.error
from pathlib import Path
import jwt

BASE='https://api.appstoreconnect.apple.com/v1'
SECRETS=Path(os.environ.get('TF_SECRETS_DIR','.tfsecrets'))
META=json.loads((SECRETS/'meta.json').read_text(encoding='utf-8-sig'))
KEY=(SECRETS/f"AuthKey_{META['key_id']}.p8").read_text()
now=int(time.time())
TOKEN=jwt.encode({'iss':META['issuer_id'],'iat':now,'exp':now+600,'aud':'appstoreconnect-v1'},KEY,algorithm='ES256',headers={'alg':'ES256','kid':META['key_id'],'typ':'JWT'})

def req(method,path,body=None):
    data=None if body is None else json.dumps(body).encode()
    r=urllib.request.Request(BASE+path,data=data,method=method,headers={'Authorization':'Bearer '+TOKEN,'Content-Type':'application/json'})
    try:
        with urllib.request.urlopen(r,timeout=30) as x:
            raw=x.read().decode(); return x.status,json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raw=e.read().decode(errors='replace')
        print(f'APPLE_HTTP_ERROR {method} {path} HTTP={e.code}')
        print(raw[:3000])
        raise

def first(path):
    _,j=req('GET',path); d=j.get('data',[]); return d[0] if d else None
bundle_q=urllib.parse.quote(META['bundle_id'],safe='')
bundle=first(f'/bundleIds?filter%5Bidentifier%5D={bundle_q}&limit=1')
if not bundle:
    _,j=req('POST','/bundleIds',{'data':{'type':'bundleIds','attributes':{'identifier':META['bundle_id'],'name':'Savarona Ailem','platform':'IOS'}}})
    bundle=j['data']; print('BUNDLE_ID_CREATED='+bundle['id'])
else: print('BUNDLE_ID_EXISTS='+bundle['id'])

app=first(f'/apps?filter%5BbundleId%5D={bundle_q}&limit=1')
if app:
    print('APP_EXISTS='+app['id'])
else:
    print('APP_RECORD_MISSING_MANUAL')

serial=os.environ['APPLE_CERT_SERIAL'].replace(':','').upper()
cert=first('/certificates?filter%5BcertificateType%5D=IOS_DISTRIBUTION&filter%5BserialNumber%5D='+urllib.parse.quote(serial)+'&limit=1')
if not cert:
    cert=first('/certificates?filter%5BcertificateType%5D=DISTRIBUTION&filter%5BserialNumber%5D='+urllib.parse.quote(serial)+'&limit=1')
if not cert: raise SystemExit('distribution_certificate_not_found')
print('CERT_FOUND='+cert['id'])
profile_name='Savarona Ailem AppStore'
profiles=req('GET',f"/bundleIds/{bundle['id']}/profiles?fields%5Bprofiles%5D=name,profileType,profileState,profileContent,uuid&limit=200")[1].get('data',[])
profile=next((p for p in profiles if p.get('attributes',{}).get('name')==profile_name and p.get('attributes',{}).get('profileState')=='ACTIVE'),None)
if not profile:
    body={'data':{'type':'profiles','attributes':{'name':profile_name,'profileType':'IOS_APP_STORE'},'relationships':{'bundleId':{'data':{'type':'bundleIds','id':bundle['id']}},'certificates':{'data':[{'type':'certificates','id':cert['id']}]}}}}
    _,j=req('POST','/profiles',body); profile=j['data']; print('PROFILE_CREATED='+profile['id'])
else: print('PROFILE_EXISTS='+profile['id'])

attrs=profile.get('attributes',{})
content=attrs.get('profileContent')
if not content:
    _,j=req('GET',f"/profiles/{profile['id']}?fields%5Bprofiles%5D=name,profileType,profileState,profileContent,uuid")
    attrs=j['data']['attributes']; content=attrs.get('profileContent')
if not content: raise SystemExit('profile_content_missing')
out=Path(os.environ.get('TF_PROFILE_OUT','Savarona_Ailem_AppStore.mobileprovision'))
out.write_bytes(base64.b64decode(content))
print('PROFILE_UUID='+str(attrs.get('uuid')))
print('PROFILE_PATH='+str(out))
print('APPLE_BOOTSTRAP=PASS')

