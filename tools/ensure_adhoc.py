#!/usr/bin/env python3
import base64,json,os,subprocess,tempfile,time,urllib.parse,urllib.request,urllib.error
API='https://api.appstoreconnect.apple.com/v1'
BUNDLE=os.environ.get('BUNDLE_ID','com.savarona.ailem')
PROFILE=os.environ.get('ADHOC_PROFILE_NAME','Savarona Ailem AdHoc')
ISS=os.environ['APPSTORE_ISSUER_ID']; KID=os.environ['APPSTORE_API_KEY_ID']
KEY=os.environ['APPSTORE_API_PRIVATE_KEY']; CERT_SERIAL=os.environ['APPLE_CERT_SERIAL']

def b64(b): return base64.urlsafe_b64encode(b).rstrip(b'=')
def der_raw(s):
    i=2+(s[1]&0x7f) if s[1]&0x80 else 2
    assert s[i]==2; lr=s[i+1]; i+=2; r=s[i:i+lr]; i+=lr
    assert s[i]==2; ls=s[i+1]; i+=2; q=s[i:i+ls]
    return r.lstrip(b'\0').rjust(32,b'\0')+q.lstrip(b'\0').rjust(32,b'\0')

def token():
    now=int(time.time())
    h=b64(json.dumps({'alg':'ES256','kid':KID,'typ':'JWT'},separators=(',',':')).encode())
    p=b64(json.dumps({'iss':ISS,'iat':now,'exp':now+900,'aud':'appstoreconnect-v1'},separators=(',',':')).encode())
    msg=h+b'.'+p
    with tempfile.NamedTemporaryFile('w',delete=False) as k: k.write(KEY); kp=k.name
    with tempfile.NamedTemporaryFile(delete=False) as f: f.write(msg); mp=f.name
    sig=subprocess.check_output(['openssl','dgst','-sha256','-sign',kp,mp]); os.unlink(kp); os.unlink(mp)
    return (msg+b'.'+b64(der_raw(sig))).decode()

JWT=token()
def req(method,path,body=None):
    data=None if body is None else json.dumps(body).encode()
    r=urllib.request.Request(API+path,data=data,method=method,headers={'Authorization':'Bearer '+JWT,'Content-Type':'application/json'})
    try:
        with urllib.request.urlopen(r,timeout=30) as x:
            raw=x.read(); return x.status,(json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        detail=e.read().decode('utf-8','replace')
        raise RuntimeError(f'{method} {path} -> {e.code}: {detail[:1200]}')

def first(path):
    _,j=req('GET',path); rows=j.get('data',[]) if j else []
    return rows[0] if rows else None

bundle=first('/bundleIds?'+urllib.parse.urlencode({'filter[identifier]':BUNDLE}))
if not bundle: raise RuntimeError('Bundle ID not found')
cert=first('/certificates?'+urllib.parse.urlencode({'filter[serialNumber]':CERT_SERIAL}))
if not cert: raise RuntimeError('Apple Distribution certificate not found')
_,dj=req('GET','/devices?'+urllib.parse.urlencode({'filter[status]':'ENABLED','limit':200}))
devices=[d for d in dj.get('data',[]) if d.get('attributes',{}).get('platform') in ('IOS','MAC_OS')]
ios_devices=[d for d in devices if d.get('attributes',{}).get('platform')=='IOS']
if not ios_devices:
    raise RuntimeError('No enabled iPhone/iPad devices are registered in Apple Developer. Register UDIDs first.')
print('REGISTERED_IOS_DEVICES',len(ios_devices))
for d in ios_devices:
    a=d.get('attributes',{})
    print('DEVICE',a.get('deviceClass'),a.get('name'),a.get('status'))

existing=first('/profiles?'+urllib.parse.urlencode({'filter[name]':PROFILE}))
if existing:
    req('DELETE','/profiles/'+existing['id'])
    print('OLD_ADHOC_PROFILE_DELETED')
body={'data':{'type':'profiles','attributes':{'name':PROFILE,'profileType':'IOS_APP_ADHOC'},
      'relationships':{'bundleId':{'data':{'type':'bundleIds','id':bundle['id']}},
      'certificates':{'data':[{'type':'certificates','id':cert['id']}]},
      'devices':{'data':[{'type':'devices','id':d['id']} for d in ios_devices]}}}}
_,created=req('POST','/profiles',body)
p=created['data']; a=p.get('attributes',{})
print('ADHOC_PROFILE_READY',a.get('name'),a.get('profileState'),a.get('expirationDate'))
