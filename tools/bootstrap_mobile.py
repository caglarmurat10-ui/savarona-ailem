#!/usr/bin/env python3
from __future__ import annotations
import argparse,base64,json,os,re,shutil,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];MOBILE=ROOT/'mobile';NATIVE=MOBILE/'native'
def run(*args:str,cwd:Path|None=None)->None: subprocess.run(args,cwd=cwd,check=True)
def patch_android()->None:
 m=MOBILE/'android/app/src/main/AndroidManifest.xml';text=m.read_text();perms=['android.permission.INTERNET','android.permission.ACCESS_FINE_LOCATION','android.permission.ACCESS_COARSE_LOCATION','android.permission.ACCESS_BACKGROUND_LOCATION','android.permission.FOREGROUND_SERVICE','android.permission.FOREGROUND_SERVICE_LOCATION','android.permission.POST_NOTIFICATIONS','android.permission.RECEIVE_BOOT_COMPLETED'];root_end=text.find('>')+1
 for p in perms:
  if p not in text:text=text[:root_end]+f'\n    <uses-permission android:name="{p}" />'+text[root_end:];root_end=text.find('>')+1
 text=re.sub(r'android:label="[^"]*"','android:label="Savarona Ailem"',text,count=1);service='''\n        <service android:name=".LocationTrackingService" android:exported="false" android:foregroundServiceType="location" />\n        <receiver android:name=".BootReceiver" android:enabled="true" android:exported="false"><intent-filter><action android:name="android.intent.action.BOOT_COMPLETED" /></intent-filter></receiver>\n'''
 if '.LocationTrackingService' not in text:text=text.replace('</application>',service+'    </application>')
 m.write_text(text)
 k=MOBILE/'android/app/src/main/kotlin/com/savarona/ailem';k.mkdir(parents=True,exist_ok=True);gm=next((MOBILE/'android/app/src/main/kotlin').rglob('MainActivity.kt'),None)
 if gm and gm.parent!=k:gm.unlink(missing_ok=True)
 shutil.copy2(NATIVE/'android/MainActivity.fragment.kt',k/'MainActivity.kt')
 for n in ['LocationTrackingService.kt','TrackingStatusStore.kt','TrackingUploadQueue.kt','SecureCredentialStore.kt','BootReceiver.kt']:shutil.copy2(NATIVE/'android'/n,k/n)
 gfile=MOBILE/'android/app/build.gradle.kts';g=gfile.read_text();dep='implementation("com.google.android.gms:play-services-location:21.3.0")'
 if dep not in g:g+=f'\n\ndependencies {{\n    {dep}\n}}\n'
 signing_bundle=os.environ.get('ANDROID_SIGNING_BUNDLE','').strip()
 if signing_bundle:
  cfg=json.loads(signing_bundle);ks_b64=str(cfg.get('keystore_base64',''));password=str(cfg.get('password',''));alias=str(cfg.get('alias','savarona-ailem'))
  if not ks_b64 or not password:raise SystemExit('ANDROID_SIGNING_BUNDLE is missing keystore_base64/password')
  (MOBILE/'android/app/savarona-release.p12').write_bytes(base64.b64decode(ks_b64))
  (MOBILE/'android/key.properties').write_text(f'storePassword={password}\nkeyPassword={password}\nkeyAlias={alias}\nstoreFile=savarona-release.p12\n')
  marker='// SAVARONA_RELEASE_SIGNING'
  signing=f'''\n    {marker}\n    val savaronaSigning = java.util.Properties().apply {{\n        rootProject.file("key.properties").inputStream().use {{ load(it) }}\n    }}\n    signingConfigs {{\n        create("savaronaRelease") {{\n            storeFile = file(savaronaSigning["storeFile"] as String)\n            storePassword = savaronaSigning["storePassword"] as String\n            keyAlias = savaronaSigning["keyAlias"] as String\n            keyPassword = savaronaSigning["keyPassword"] as String\n        }}\n    }}\n'''
  if marker not in g:g=g.replace('android {','android {'+signing,1)
  g=g.replace('signingConfig = signingConfigs.getByName("debug")','signingConfig = signingConfigs.getByName("savaronaRelease")')
 gfile.write_text(g)
def strip_swift_imports(text:str)->str:return '\n'.join(line for line in text.splitlines() if not line.startswith('import '))
def patch_ios()->None:
 ad=MOBILE/'ios/Runner/AppDelegate.swift';text=ad.read_text();imports='import Flutter\nimport UIKit\nimport Foundation\nimport CoreLocation\nimport Security\n';text=re.sub(r'^(?:import .*\n)+',imports,text);needle='GeneratedPluginRegistrant.register(with: self)';reg='''GeneratedPluginRegistrant.register(with: self)\n    if let controller = window?.rootViewController as? FlutterViewController {\n      TrackingPlugin.register(with: controller.engine.binaryMessenger)\n    }\n    LocationTracker.shared.restoreIfAuthorized()'''
 if 'TrackingPlugin.register' not in text:text=text.replace(needle,reg)
 src=['KeychainCredentialStore.swift','TrackingStatusStore.swift','LocationUploadQueue.swift','LocationTracker.swift','TrackingPlugin.swift'];marker='// === SAVARONA_NATIVE_TRACKING_BUNDLE ==='
 if marker in text:text=text.split(marker,1)[0].rstrip()+'\n'
 bundle='\n\n'.join(strip_swift_imports((NATIVE/'ios'/n).read_text()) for n in src);ad.write_text(text.rstrip()+f'\n\n{marker}\n{bundle}\n')
 plist=MOBILE/'ios/Runner/Info.plist';p=plist.read_text();frag='\n'.join(line for line in (NATIVE/'ios/Info.plist.fragment.xml').read_text().splitlines() if not line.strip().startswith('<!--'))
 if 'NSLocationAlwaysAndWhenInUseUsageDescription' not in p:p=p.replace('</dict>',frag+'\n</dict>')
 if 'CFBundleDisplayName' in p:p=re.sub(r'(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)',r'\1Savarona Ailem\2',p)
 plist.write_text(p)
def main()->None:
 parser=argparse.ArgumentParser();parser.add_argument('--keep-existing',action='store_true');args=parser.parse_args()
 if shutil.which('flutter') is None:raise SystemExit('Flutter SDK not found in PATH')
 with tempfile.TemporaryDirectory(prefix='savarona-flutter-') as tmp:
  shell=Path(tmp)/'shell';run('flutter','create','--platforms=android,ios','--org','com.savarona','--project-name','ailem',str(shell))
  for platform in ('android','ios'):
   dst=MOBILE/platform
   if dst.exists() and args.keep_existing:continue
   shutil.rmtree(dst,ignore_errors=True);shutil.copytree(shell/platform,dst)
 patch_android();patch_ios();print('Savarona mobile shell ready: android + ios')
if __name__=='__main__':main()
