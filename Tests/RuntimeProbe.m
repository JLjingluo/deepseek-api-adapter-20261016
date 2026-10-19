#import <Foundation/Foundation.h>
#import "DSAPIConfiguration.h"
#include <stdlib.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#include <dlfcn.h>
extern void DSAPIRunRuntimeProbe(void);
static id (*originalFixtureLoad)(id,SEL);
static id DSLoadLocalFixture(id cls,SEL selector) {
    NSDictionary *fixture=[NSUserDefaults.standardUserDefaults dictionaryForKey:@"DSAPIAdapter.localTestFixture"];
    BOOL local=[[NSURL URLWithString:fixture[@"baseURL"] ?: @""].host isEqual:@"127.0.0.1"];
    DSAPIConfiguration *configuration=local ? [cls loadConfigurationWithoutAPIKey] : originalFixtureLoad(cls,selector);
    if ([[NSURL URLWithString:fixture[@"baseURL"] ?: @""].host isEqual:@"127.0.0.1"]) {
        configuration.baseURL=fixture[@"baseURL"]; configuration.model=@"ci-mock-model"; configuration.apiKey=@"ci-dummy-key";
    }
    return configuration;
}

// Disposable simulator only: use Swift's public runtime debugging hook to
// retain the real serialization error before the app maps it to _systemError.
static void (*oldWillThrow)(void *);
static void (*retainSwiftError)(void *);
static void *(*bridgeSwiftError)(void *);
static __thread BOOL recordingSwiftError;
static unsigned recordedSwiftErrors;
static void probeWillThrow(void *raw) {
    if (__atomic_load_n(&recordedSwiftErrors,__ATOMIC_RELAXED)<40 && !recordingSwiftError && raw && [NSUserDefaults.standardUserDefaults dictionaryForKey:@"DSAPIAdapter.lastAttachmentImport"]) {
        recordingSwiftError=YES;
        @try {
            retainSwiftError(raw);
            NSError *error=CFBridgingRelease(bridgeSwiftError(raw));
            NSString *detail=error.userInfo[NSDebugDescriptionErrorKey] ?: error.description ?: @"";
            if (detail.length>1800) detail=[detail substringToIndex:1800];
            @synchronized(NSUserDefaults.class) {
                NSMutableArray *errors=[[NSUserDefaults.standardUserDefaults arrayForKey:@"DSAPIAdapter.probeSwiftUploadErrors"] mutableCopy] ?: [NSMutableArray array];
                if (errors.count<40) { __atomic_fetch_add(&recordedSwiftErrors,1,__ATOMIC_RELAXED); [errors addObject:@{@"domain":error.domain ?: @"",@"code":@(error.code),@"description":detail}]; [NSUserDefaults.standardUserDefaults setObject:errors forKey:@"DSAPIAdapter.probeSwiftUploadErrors"]; }
            }
        } @finally { recordingSwiftError=NO; }
    }
    if (oldWillThrow) oldWillThrow(raw);
}
static void installSwiftErrorProbe(void) {
    recordedSwiftErrors=(unsigned)[[NSUserDefaults.standardUserDefaults arrayForKey:@"DSAPIAdapter.probeSwiftUploadErrors"] count];
    void **slot=dlsym(RTLD_DEFAULT,"_swift_willThrow");
    retainSwiftError=dlsym(RTLD_DEFAULT,"swift_errorRetain"); bridgeSwiftError=dlsym(RTLD_DEFAULT,"_swift_stdlib_bridgeErrorToNSError");
    if (slot && retainSwiftError && bridgeSwiftError) {
        oldWillThrow=(void *)__atomic_exchange_n(slot,(void *)probeWillThrow,__ATOMIC_ACQ_REL);
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"DSAPIAdapter.probeSwiftErrorHookInstalled"];
    }
}
static BOOL preparingFixture;
static BOOL (*originalProbeSaveKey)(id,SEL,NSData *,NSError **);
static BOOL DSProbeSaveKey(id self,SEL selector,NSData *data,NSError **error) {
    NSString *base=[self valueForKey:@"baseURL"];
    if ([[NSURL URLWithString:base].host isEqual:@"127.0.0.1"] && [data isEqual:[@"ci-dummy-key" dataUsingEncoding:NSUTF8StringEncoding]]) {
        if (!preparingFixture) {
            [NSUserDefaults.standardUserDefaults setBool:!NSThread.isMainThread forKey:@"DSAPIAdapter.probeSaveOffMain"];
            [NSThread sleepForTimeInterval:0.8];
        } // Observe UI responsiveness during a slow security service.
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
            if (copyUser) { void *value=copyUser(); if (value) {
                NSData *base=CFBridgingRelease(value);
                NSMutableDictionary *user=[NSJSONSerialization JSONObjectWithData:base options:NSJSONReadingMutableContainers error:NULL];
                user[@"token"]=@"ci-original-account-token";
                canonical=[NSJSONSerialization dataWithJSONObject:user options:0 error:NULL];
            } }
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
    BOOL cloud=[NSURLProtocol propertyForKey:@"DSAPI.DirectAPI" inRequest:request] && ([path hasPrefix:@"/api/v0/chat_session/"] || [path hasSuffix:@"/chat/history_messages"]);
    return [request.URL.host.lowercaseString isEqual:@"chat.deepseek.com"] && [path hasPrefix:@"/api/"] &&
        (cloud || (![path hasPrefix:@"/api/v0/chat/"] && ![path hasPrefix:@"/api/v0/chat_session/"]));
}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)stopLoading {}
- (void)startLoading {
    NSString *path=self.request.URL.path;
    BOOL guest=[NSUserDefaults.standardUserDefaults boolForKey:@"DSAPIAdapter.probeGuestContext"];
    if (guest && ([path hasSuffix:@"/users/current"] || [path hasSuffix:@"/index/prepare"])) {
        NSData *data=[@"{\"code\":401,\"msg\":\"Not signed in\",\"data\":{}}" dataUsingEncoding:NSUTF8StringEncoding];
        NSHTTPURLResponse *response=[[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:401 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":@"application/json"}];
        [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed]; [self.client URLProtocol:self didLoadData:data]; [self.client URLProtocolDidFinishLoading:self]; return;
    }
    NSDictionary *user=@{@"id":@"local-api",@"token":@"ci-original-account-token",@"email":@"",@"mobile_number":@"",@"area_code":@"",@"status":@0,@"id_profiles":@[],@"chat":@{@"is_muted":@0},@"has_legacy_chat_history":@NO,@"need_birthday":@NO,@"is_mainland":@NO};
    id payload=@{};
    NSDictionary *cloud=@{@"id":@"ci-cloud-history",@"title":@"Cloud history fixture",@"title_type":@"USER",@"pinned":@NO,@"updated_at":@1760000000,@"inserted_at":@1760000000,@"is_empty":@NO,@"model_type":@"default",@"version":@1,@"current_message_id":@42};
    if ([NSURLProtocol propertyForKey:@"DSAPI.DirectAPI" inRequest:self.request] && [path hasSuffix:@"/chat_session/fetch_page"]) payload=@{@"chat_sessions":@[cloud],@"has_more":@NO};
    else if ([NSURLProtocol propertyForKey:@"DSAPI.DirectAPI" inRequest:self.request] && [path hasSuffix:@"/chat/history_messages"]) {
        NSMutableArray *messages=[NSMutableArray array];
        for (NSNumber *mid in @[@41,@42]) {
            BOOL userMessage=[mid isEqual:@41];
            [messages addObject:@{@"message_id":mid,@"parent_id":userMessage ? NSNull.null : @41,@"role":userMessage ? @"USER" : @"ASSISTANT",@"fragments":@[@{@"id":mid,@"type":userMessage ? @"REQUEST" : @"RESPONSE",@"content":userMessage ? @"earlier question" : @"earlier answer",@"references":@[],@"stage_id":@0}],@"status":@"FINISHED",@"quasi_status":@"FINISHED",@"thinking_enabled":@NO,@"ban_edit":@NO,@"ban_regenerate":@NO,@"tips":@[],@"conversation_mode":@"CHAT",@"search_enabled":@NO,@"search_triggered":@NO,@"extra_search_providers":@[]}];
        }
        payload=@{@"chat_session":cloud,@"chat_messages":messages,@"cache_control":@"REPLACE",@"cache_reset_at":@0};
    }
    else if ([path hasSuffix:@"/users/current"]) { NSMutableDictionary *value=[user mutableCopy]; value[@"user"]=user; payload=value; }
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
    BOOL guest=[NSUserDefaults.standardUserDefaults boolForKey:@"DSAPIAdapter.probeGuestContext"];
    Method method=class_getInstanceMethod(mmkv,key);
    if (method && !guest) { originalProbeUser=(void *)method_getImplementation(method); class_replaceMethod(mmkv,key,(IMP)DSProbeUser,method_getTypeEncoding(method)); }
    method=class_getClassMethod(NSURLSession.class,@selector(sessionWithConfiguration:delegate:delegateQueue:));
    originalProbeSession=(void *)method_setImplementation(method,(IMP)DSProbeSession);
    [NSUserDefaults.standardUserDefaults setBool:!guest forKey:@"DSAPIAdapter.accountFixtureActive"];
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
    if ([NSUserDefaults.standardUserDefaults boolForKey:@"DSAPIAdapter.directLiveTest"]) {
        // Only the separate initial smoke launch receives this process variable.
        // XCTest pastes it through the real secure text field; no read/save hook.
        const char *key=getenv("DSAPI_TEST_API_KEY");
        if (key && key[0]) { UIPasteboard.generalPasteboard.string=[NSString stringWithUTF8String:key]; unsetenv("DSAPI_TEST_API_KEY"); }
        [NSUserDefaults.standardUserDefaults setBool:NO forKey:@"DSAPIAdapter.testKeychainBypassed"];
        return;
    }
    const char *base = getenv("DSAPI_TEST_BASE_URL");
    NSString *baseURL=base ? [NSString stringWithUTF8String:base] : [NSUserDefaults.standardUserDefaults dictionaryForKey:@"DSAPIAdapter.localTestFixture"][@"baseURL"];
    if (!baseURL || ![[NSURL URLWithString:baseURL].host isEqual:@"127.0.0.1"]) return;
    Class configurationClass = NSClassFromString(@"DSAPIConfiguration");
    DSAPIConfiguration *configuration = [configurationClass loadConfigurationWithoutAPIKey];
    if (!configuration) return;
    Method storage=class_getInstanceMethod(configurationClass,NSSelectorFromString(@"saveKeyData:error:"));
    if (storage && !originalProbeSaveKey) originalProbeSaveKey=(void *)method_setImplementation(storage,(IMP)DSProbeSaveKey);
    UIPasteboard.generalPasteboard.image=[[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(512,512)] imageWithActions:^(UIGraphicsImageRendererContext *context) { [UIColor.redColor setFill]; UIRectFill(CGRectMake(0,0,512,512)); }];
    configuration.baseURL = baseURL;
    configuration.apiKey = @"ci-dummy-key";
    configuration.model = @"ci-mock-model";
    NSError *error = nil;
    preparingFixture=YES;
    BOOL saved = [configuration save:&error];
    preparingFixture=NO;
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
    DSInstallAccountFixture(); installSwiftErrorProbe();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        DSPrepareMockConfiguration();
        DSAPIRunRuntimeProbe();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,6*NSEC_PER_SEC),dispatch_get_main_queue(),^{ DSPresentAPIProbe(); });
    });
    for (int delay=9;delay<=249;delay+=10)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delay*NSEC_PER_SEC), dispatch_get_main_queue(), ^{ DSAPIRunRuntimeProbe(); });
}
