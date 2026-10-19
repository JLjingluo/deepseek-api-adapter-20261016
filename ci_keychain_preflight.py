"""Test-only: find a simulator signature that supports real Security.framework.

Uses a disposable, independently compiled app and a non-secret sentinel. Nothing
here is included in the production adapter or replaces Keychain implementations.
"""
import json, os, pathlib, plistlib, subprocess, time


def select_keychain_entitlements(device, root, diagnostics, run, bundle):
    app = root/'KeychainPreflight.app'
    app.mkdir(exist_ok=True)
    probe_id='org.dsapi.keychainpreflight'
    (app/'Info.plist').write_bytes(plistlib.dumps({
        'CFBundleIdentifier':probe_id, 'CFBundleExecutable':'KeychainPreflight',
        'CFBundleName':'KeychainPreflight', 'CFBundlePackageType':'APPL',
        'CFBundleVersion':'1', 'CFBundleShortVersionString':'1.0',
        'CFBundleSupportedPlatforms':['iPhoneSimulator'], 'MinimumOSVersion':'18.0',
        'UIDeviceFamily':[1,2], 'UILaunchScreen':{}}))
    source=root/'KeychainPreflight.m'
    source.write_text(r'''
#import <UIKit/UIKit.h>
#import <Security/Security.h>
@interface ProbeDelegate : UIResponder <UIApplicationDelegate>
@property(strong,nonatomic) UIWindow *window;
@end
@implementation ProbeDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController=[UIViewController new];
    [self.window makeKeyAndVisible];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        [[NSFileManager defaultManager] createDirectoryAtPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"] withIntermediateDirectories:YES attributes:nil error:NULL];
        NSDictionary *q=@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
          (__bridge id)kSecAttrService:@"DSAPI.Preflight",(__bridge id)kSecAttrAccount:@"sentinel"};
        SecItemDelete((__bridge CFDictionaryRef)q);
        NSMutableDictionary *a=[q mutableCopy];
        a[(__bridge id)kSecValueData]=[@"non-secret-test-sentinel" dataUsingEncoding:NSUTF8StringEncoding];
        a[(__bridge id)kSecAttrAccessible]=(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
        OSStatus add=SecItemAdd((__bridge CFDictionaryRef)a,NULL);
        NSMutableDictionary *read=[q mutableCopy];read[(__bridge id)kSecReturnData]=@YES;
        CFTypeRef value=NULL;OSStatus get=SecItemCopyMatching((__bridge CFDictionaryRef)read,&value);
        NSData *data=CFBridgingRelease(value);
        BOOL matches=[data isEqual:a[(__bridge id)kSecValueData]];
        NSDictionary *result=@{@"add":@(add),@"read":@(get),@"matches":@(matches)};
        [[NSJSONSerialization dataWithJSONObject:result options:0 error:NULL]
          writeToFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/keychain-preflight.json"] atomically:YES];
        SecItemDelete((__bridge CFDictionaryRef)q);
    });
    return YES;
}
@end
int main(int argc,char **argv) { @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(ProbeDelegate.class)); } }
''')
    sdk=run(['xcrun','--sdk','iphonesimulator','--show-sdk-path']).stdout.strip()
    run(['xcrun','clang','-target','arm64-apple-ios18.0-simulator','-isysroot',sdk,
         '-fobjc-arc','-fmodules',str(source),'-framework','UIKit','-framework','Security',
         '-o',str(app/'KeychainPreflight')])
    sandbox={'com.apple.security.app-sandbox':True,'com.apple.security.network.client':True}
    identity='DSAPITEST0.'+probe_id
    variants=[
        {'com.apple.application-identifier':identity},
        {'keychain-access-groups':[identity]},
        {'com.apple.application-identifier':identity,'keychain-access-groups':[identity]},
        {'application-identifier':identity,'keychain-access-groups':[identity]},
        {**sandbox,'com.apple.application-identifier':identity,'keychain-access-groups':[identity]},
        {'application-identifier':identity},
        {},
    ]
    attempts=[]
    for i,entitlements in enumerate(variants):
        path=root/'keychain-preflight.entitlements.plist'
        path.write_bytes(plistlib.dumps(entitlements))
        run(['codesign','--force','--sign','-','--generate-entitlement-der','--entitlements',str(path),str(app)])
        run(['xcrun','simctl','install',device,str(app)])
        container=pathlib.Path(run(['xcrun','simctl','get_app_container',device,probe_id,'data']).stdout.strip())
        result_path=container/'Documents/keychain-preflight.json'
        result_path.unlink(missing_ok=True)
        try:
            launch=run(['xcrun','simctl','launch',device,probe_id],check=False,timeout=30)
            launch_code=launch.returncode
        except subprocess.TimeoutExpired:
            launch_code=124
        for _ in range(15):
            if result_path.exists():break
            time.sleep(1)
        result=json.loads(result_path.read_text()) if result_path.exists() else None
        attempt={'entitlements':entitlements,'launch_exit_code':launch_code,'result':result}
        attempts.append(attempt)
        (diagnostics/'keychain-preflight.json').write_text(json.dumps(attempts,indent=2))
        # simctl launch/terminate can hang on a cold simulator even while the
        # app is running. The saved result, not the RPC return, is the gate.
        processes=subprocess.run(['ps','-axo','pid=,comm='],text=True,stdout=subprocess.PIPE)
        for line in processes.stdout.splitlines():
            parts=line.strip().split(None,1)
            if len(parts)==2 and parts[1].endswith('/KeychainPreflight.app/KeychainPreflight'):
                try:os.kill(int(parts[0]),9)
                except ProcessLookupError:pass
        if result and result['add']==0 and result['read']==0 and result['matches']:
            # Rebind only the public test identifiers; no credential data exists.
            return {k:([v[0].replace(probe_id,bundle)] if isinstance(v,list)
                       else v.replace(probe_id,bundle) if isinstance(v,str) else v)
                    for k,v in entitlements.items()}
    raise RuntimeError('No tested simulator signature permits real Keychain add/read; see keychain-preflight.json')
