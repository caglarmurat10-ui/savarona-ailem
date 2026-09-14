#!/usr/bin/env python3
import base64,json,os,subprocess,tempfile,time,urllib.parse,urllib.request,urllib.error
API='https://api.appstoreconnect.apple.com/v1'
BUNDLE=os.environ.get('BUNDLE_ID','com.savarona.ailem')
APP_NAME='Savarona Ailem'; SKU='savarona-ailem-ios'; PROFILE='Savarona Ailem AppStore'
ISS=os.environ['APPSTORE_ISSUER_ID']; KID=os.environ['APPSTORE_API_KEY_ID']
KEY=os.environ['APPSTORE_API_PRIVATE_KEY']; CERT_SERIAL=os.environ['APPLE_CERT_SERIAL']
def b64(b): return base64.urlsafe_b64encode(b).rstrip(b'=')
def der_raw(s):
 i=2+(s[1]&0x7f) if s[1]&0x80 else 2
 assert s[i]==2; lr=s[i+1]; i+=2; r=s[i:i+lr]; i+=lr
 assert s[i]==2; ls=s[i+1]; i+=2; q=s[i:i+ls]
 return r.lstrip(b'\0').rjust(32,b'\0')+q.lstrip(b'\0').rjust(32,b'\0')
def token():
 now=int(time.time()); h=b64(json.dumps({'alg':'ES256','kid':KID,'typ':'JWT'},separators=(',',':')).encode())
 p=b64(json.dumps({'iss':ISS,'iat':now,'exp':now+900,'aud':'appstoreconnect-v1'},separators=(',',':')).encode()); msg=h+b'.'+p
 with tempfile.NamedTemporaryFile('w',delete=False) as k: k.write(KEY); kp=k.name
 with tempfile.NamedTemporaryFile(delete=False) as f: f.write(msg); mp=f.name
 sig=subprocess.check_output(['openssl','dgst','-sha256','-sign',kp,mp]); os.unlink(kp); os.unlink(mp)
 return (msg+b'.'+b64(der_raw(sig))).decode()
JWT=token()
def req(method,path,body=None):
 data=None if body is None else json.dumps(body).encode(); r=urllib.request.Request(API+path,data=data,method=method,headers={'Authorization':'Bearer '+JWT,'Content-Type':'application/json'})
 try:
  with urllib.request.urlopen(r,timeout=30) as x: return x.status,json.load(x)
 except urllib.error.HTTPError as e:
  detail=e.read().decode('utf-8','replace'); raise RuntimeError(f'{method} {path} -> {e.code}: {detail[:1200]}')
def first(path):
 _,j=req('GET',path); return j.get('data',[None])[0] if j.get('data') else None
bundle=first('/bundleIds?'+urllib.parse.urlencode({'filter[identifier]':BUNDLE}))
if not bundle:
 _,j=req('POST','/bundleIds',{'data':{'type':'bundleIds','attributes':{'identifier':BUNDLE,'name':'Savarona Ailem','platform':'IOS'}}}); bundle=j['data']; print('BUNDLE_ID_CREATED')
else: print('BUNDLE_ID_EXISTS')
app=first('/apps?'+urllib.parse.urlencode({'filter[bundleId]':BUNDLE}))
if not app:
 _,j=req('POST','/apps',{'data':{'type':'apps','attributes':{'bundleId':BUNDLE,'name':APP_NAME,'primaryLocale':'tr','sku':SKU}}}); app=j['data']; print('APP_RECORD_CREATED')
else: print('APP_RECORD_EXISTS')
cert=first('/certificates?'+urllib.parse.urlencode({'filter[serialNumber]':CERT_SERIAL}))
if not cert: raise RuntimeError('Apple Distribution certificate not found in API')
profile=first('/profiles?'+urllib.parse.urlencode({'filter[name]':PROFILE}))
if profile:
 state=profile.get('attributes',{}).get('profileState')
 if state=='ACTIVE': print('PROFILE_EXISTS_ACTIVE'); raise SystemExit(0)
 req('DELETE','/profiles/'+profile['id']); print('OLD_PROFILE_DELETED')
body={'data':{'type':'profiles','attributes':{'name':PROFILE,'profileType':'IOS_APP_STORE'},'relationships':{'bundleId':{'data':{'type':'bundleIds','id':bundle['id']}},'certificates':{'data':[{'type':'certificates','id':cert['id']}]}}}}
req('POST','/profiles',body); print('PROFILE_CREATED')