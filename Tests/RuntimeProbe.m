#import <Foundation/Foundation.h>
#import "DSAPIConfiguration.h"
#include <stdlib.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#include <dlfcn.h>
extern void DSAPIRunRuntimeProbe(void);
static id (*originalFixtureLoad)(id,SEL);
static id DSLoadLocalFixture(id cls,SEL selector) {
    DSAPIConfiguration *configuration=originalFixtureLoad(cls,selector);
    NSDictionary *fixture=[NSUserDefaults.standardUserDefaults dictionaryForKey:@"DSAPIAdapter.localTestFixture"];
    if ([[NSURL URLWithString:fixture[@"baseURL"] ?: @""].host isEqual:@"127.0.0.1"]) {
        configuration.baseURL=fixture[@"baseURL"]; configuration.model=@"ci-mock-model"; configuration.apiKey=@"ci-dummy-key";
    }
    return configuration;
}

static BOOL (*originalProbeSaveKey)(id,SEL,NSData *,NSError **);
static BOOL DSProbeSaveKey(id self,SEL selector,NSData *data,NSError **error) {
    NSString *base=[self valueForKey:@"baseURL"];
    if ([[NSURL URLWithString:base].host isEqual:@"127.0.0.1"] && [data isEqual:[@"ci-dummy-key" dataUsingEncoding:NSUTF8StringEncoding]]) {
        [NSUserDefaults.standardUserDefaults setBool:!NSThread.isMainThread forKey:@"DSAPIAdapter.probeSaveOffMain"];
        [NSThread sleepForTimeInterval:0.8]; // Observe UI responsiveness during a slow security service.
        return YES;
    }
    return originalProbeSaveKey(self,selector,data,error);
}
static NSData *(*originalProbeUser)(id,SEL,NSString *);
static NSData *DSProbeUser(id self,SEL selector,NSString *key) {
    if ([key isEqual:@"currentUser"]) {
        static NSData *canonical; static dispatch_once_t once;
        dispatch_once(&once,^{
            void *(*copyUser)(void)=dlsym(RTLD_DEFAULT,"DSAPICopyLocalUserData");
            if (copyUser) { void *value=copyUser(); if (value) canonical=CFBridgingRelease(value); }
        });
        if (canonical) return canonical;
    }
    return originalProbeUser(self,selector,key);
}
@interface DSProbeAccountProtocol : NSURLProtocol
@end
@implementation DSProbeAccountProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSString *path=request.URL.path;
    return [request.URL.host.lowercaseString isEqual:@"chat.deepseek.com"] && [path hasPrefix:@"/api/"] &&
        ![path hasPrefix:@"/api/v0/chat/"] && ![path hasPrefix:@"/api/v0/chat_session/"];
}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)stopLoading {}
- (void)startLoading {
    NSString *path=self.request.URL.path;
    NSDictionary *user=@{@"id":@"local-api",@"token":@"local-api-no-official-account",@"email":@"",@"mobile_number":@"",@"area_code":@"",@"status":@0,@"id_profiles":@[],@"chat":@{@"is_muted":@0},@"has_legacy_chat_history":@NO,@"need_birthday":@NO,@"is_mainland":@NO};
    id payload=@{};
    if ([path hasSuffix:@"/users/current"]) { NSMutableDictionary *value=[user mutableCopy]; value[@"user"]=user; payload=value; }
    else if ([path hasSuffix:@"/users/auth_token/check_device"]) payload=@{@"rotate":NSNull.null};
    else if ([path hasSuffix:@"/client/settings"]) payload=@{@"version":@0,@"settings":@{}};
    else if ([path hasSuffix:@"/index/prepare"]) {
        id store=[NSClassFromString(@"DSLocalStore") performSelector:NSSelectorFromString(@"shared")];
        payload=@{@"user":user,@"settings":@{},@"chat_sessions":[store valueForKey:@"sessions"] ?: @[]};
    } else if ([path hasSuffix:@"/check_client_update"]) payload=@{@"need_update":@NO,@"force_update":@NO};
    NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"code":@0,@"msg":@"",@"data":@{@"biz_code":@0,@"biz_msg":@"",@"biz_data":payload}} options:0 error:NULL];
    NSHTTPURLResponse *response=[[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":@"application/json"}];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:data]; [self.client URLProtocolDidFinishLoading:self];
}
@end
static id (*originalProbeSession)(id,SEL,NSURLSessionConfiguration *,id,NSOperationQueue *);
static id DSProbeSession(id cls,SEL selector,NSURLSessionConfiguration *configuration,id delegate,NSOperationQueue *queue) {
    NSURLSessionConfiguration *copy=[configuration copy];
    copy.protocolClasses=[@[DSProbeAccountProtocol.class] arrayByAddingObjectsFromArray:copy.protocolClasses ?: @[]];
    return originalProbeSession(cls,selector,copy,delegate,queue);
}
static void DSInstallAccountFixture(void) {
    NSString *base=[NSUserDefaults.standardUserDefaults dictionaryForKey:@"DSAPIAdapter.localTestFixture"][@"baseURL"];
    if (![[NSURL URLWithString:base ?: @""].host isEqual:@"127.0.0.1"]) return;
    Class mmkv=NSClassFromString(@"MMKV"); SEL key=NSSelectorFromString(@"getDataForKey:");
    Method method=class_getInstanceMethod(mmkv,key);
    if (method) { originalProbeUser=(void *)method_getImplementation(method); class_replaceMethod(mmkv,key,(IMP)DSProbeUser,method_getTypeEncoding(method)); }
    method=class_getClassMethod(NSURLSession.class,@selector(sessionWithConfiguration:delegate:delegateQueue:));
    originalProbeSession=(void *)method_setImplementation(method,(IMP)DSProbeSession);
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"DSAPIAdapter.accountFixtureActive"];
}
static void DSPresentAPIProbe(void) {
    if (![NSUserDefaults.standardUserDefaults boolForKey:@"DSAPIAdapter.probePresentAPI"]) return;
    UIWindow *window=nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) if ([scene isKindOfClass:UIWindowScene.class])
        for (UIWindow *candidate in ((UIWindowScene *)scene).windows) if (candidate.isKeyWindow) window=candidate;
    UIViewController *root=window.rootViewController;
    while (root.presentedViewController) root=root.presentedViewController;
    if (!root.view.window) return;
    UIViewController *(*factory)(UIFont *)=dlsym(RTLD_DEFAULT,"DSAPICreateSettingsController");
    if (factory) [root presentViewController:factory([UIFont preferredFontForTextStyle:UIFontTextStyleBody]) animated:NO completion:nil];
}
static void DSPrepareMockConfiguration(void) {
    const char *base = getenv("DSAPI_TEST_BASE_URL");
    NSString *baseURL=base ? [NSString stringWithUTF8String:base] : [NSUserDefaults.standardUserDefaults dictionaryForKey:@"DSAPIAdapter.localTestFixture"][@"baseURL"];
    if (!baseURL || ![[NSURL URLWithString:baseURL].host isEqual:@"127.0.0.1"]) return;
    Class configurationClass = NSClassFromString(@"DSAPIConfiguration");
    DSAPIConfiguration *configuration = [configurationClass loadConfiguration];
    if (!configuration) return;
    Method storage=class_getInstanceMethod(configurationClass,NSSelectorFromString(@"saveKeyData:error:"));
    if (storage && !originalProbeSaveKey) originalProbeSaveKey=(void *)method_setImplementation(storage,(IMP)DSProbeSaveKey);
    UIPasteboard.generalPasteboard.image=[UIImage imageWithData:[[NSData alloc] initWithBase64EncodedString:@"iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEklEQVR4nGP4z8CAFWEXHbQSACj/P8Fu7N9hAAAAAElFTkSuQmCC" options:0]];
    configuration.baseURL = baseURL;
    configuration.apiKey = @"ci-dummy-key";
    configuration.model = @"ci-mock-model";
    NSError *error = nil;
    BOOL saved = [configuration save:&error];
    [NSUserDefaults.standardUserDefaults setBool:saved forKey:@"DSAPIAdapter.testConfigurationSaved"];
    if (!saved) [NSUserDefaults.standardUserDefaults setObject:[NSString stringWithFormat:@"%@ (%@:%ld)", error.localizedDescription ?: @"unknown", error.domain, (long)error.code]
        forKey:@"DSAPIAdapter.testConfigurationError"];
    // The loopback fixture has its own dummy key, including after a simulated
    // successful write. Actual device Keychain behavior is a separate check.
    [NSUserDefaults.standardUserDefaults setObject:@{@"baseURL":baseURL} forKey:@"DSAPIAdapter.localTestFixture"];
    if (!originalFixtureLoad) {
        Method method=class_getClassMethod(configurationClass,@selector(loadConfiguration));
        originalFixtureLoad=(void *)method_setImplementation(method,(IMP)DSLoadLocalFixture);
    }
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"DSAPIAdapter.testKeychainBypassed"];

}
__attribute__((constructor)) static void DSInstallRuntimeProbe(void) {
    DSInstallAccountFixture();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        DSPrepareMockConfiguration();
        DSAPIRunRuntimeProbe();
        DSPresentAPIProbe();
    });
    for (int delay=9;delay<=249;delay+=10)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delay*NSEC_PER_SEC), dispatch_get_main_queue(), ^{ DSAPIRunRuntimeProbe(); });
}
