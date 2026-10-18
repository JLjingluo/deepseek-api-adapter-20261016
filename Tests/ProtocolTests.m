#import <Foundation/Foundation.h>
#import "DSCompatibilityProtocol.h"
#import "DSLocalStore.h"
#import "DSAPIConfiguration.h"
#import "DSAttachmentStore.h"
#import <objc/runtime.h>
#include <string.h>
#import <CommonCrypto/CommonDigest.h>
static NSString *identityHash(NSString *value) { NSData *data=[value dataUsingEncoding:NSUTF8StringEncoding]; unsigned char digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(data.bytes,(CC_LONG)data.length,digest); NSMutableString *text=[NSMutableString string]; for (NSUInteger i=0;i<sizeof(digest);i++) [text appendFormat:@"%02x",digest[i]]; return text; }
static void bindIdentity(NSString *identifier,NSString *token) { [NSUserDefaults.standardUserDefaults setObject:identifier forKey:@"DSAPIAdapter.currentOfficialUserID"]; [NSUserDefaults.standardUserDefaults setObject:@{@"id":identifier,@"tokenFingerprint":identityHash(token)} forKey:@"DSAPIAdapter.currentOfficialIdentity"]; }
static NSDictionary *retryPayload;
static BOOL configurationReadOffMain=YES;
@interface RetryFixture : NSURLProtocol
@end
@implementation RetryFixture
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return [request.URL.host isEqual:@"api.fixture.test"]; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)stopLoading {}
- (void)startLoading {
    NSData *body=self.request.HTTPBody;
    if (!body && self.request.HTTPBodyStream) {
        NSInputStream *stream=self.request.HTTPBodyStream; [stream open];
        NSMutableData *bytes=[NSMutableData data]; uint8_t buffer[1024]; NSInteger length;
        while ((length=[stream read:buffer maxLength:sizeof(buffer)])>0) [bytes appendBytes:buffer length:length];
        [stream close]; body=bytes;
    }
    retryPayload=body ? [NSJSONSerialization JSONObjectWithData:body options:0 error:NULL] : nil;
    NSHTTPURLResponse *response=[[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":@"text/event-stream"}];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    NSData *wire=[@"data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"replacement\"},\"finish_reason\":null}]}\n\ndata: [DONE]\n\n" dataUsingEncoding:NSUTF8StringEncoding];
    [self.client URLProtocol:self didLoadData:wire]; [self.client URLProtocolDidFinishLoading:self];
}
@end
@interface DSAPIConfiguration (RetryFixture)
+ (instancetype)retryConfiguration;
@end
@implementation DSAPIConfiguration (RetryFixture)
+ (instancetype)retryConfiguration {
    configurationReadOffMain &= !NSThread.isMainThread;
    DSAPIConfiguration *c=[self new]; c.baseURL=@"https://api.fixture.test/v1"; c.apiKey=@"protocol-fixture-key";
    c.model=@"fixture-model"; c.reasoningModel=@""; c.systemPrompt=@""; c.timeout=30; return c;
}
@end
static NSString *cloudAuthorization;
static BOOL cloudDeleted,cloudFail,cloudPinned;
static NSString *cloudTitle;
static NSDictionary *cloudSession(void) {
    return @{@"id":@"cloud-history-fixture",@"title":cloudTitle ?: @"Cloud history fixture",@"title_type":@"USER",@"pinned":@(cloudPinned),@"updated_at":@1760000000,@"inserted_at":@1760000000,@"is_empty":@NO,@"model_type":@"default",@"version":@1,@"current_message_id":@42};
}
static NSArray *cloudMessages(void) {
    NSMutableArray *messages=[NSMutableArray array];
    for (NSNumber *mid in @[@41,@42]) [messages addObject:@{@"message_id":mid,@"parent_id":[mid isEqual:@41] ? NSNull.null : @41,@"role":[mid isEqual:@41] ? @"USER" : @"ASSISTANT",@"status":@"FINISHED",@"quasi_status":@"FINISHED",@"fragments":@[@{@"id":mid,@"type":[mid isEqual:@41] ? @"REQUEST" : @"RESPONSE",@"content":[mid isEqual:@41] ? @"earlier question" : @"earlier answer"}]}]; return messages;
}
@interface CloudFixture : NSURLProtocol
@end
@implementation CloudFixture
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return [request.URL.host isEqual:@"chat.deepseek.com"] && [NSURLProtocol propertyForKey:@"DSAPI.DirectAPI" inRequest:request]!=nil; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)stopLoading {}
- (void)startLoading {
    NSString *path=self.request.URL.path; NSData *body=self.request.HTTPBody;
    if (!body && self.request.HTTPBodyStream) { NSInputStream *stream=self.request.HTTPBodyStream; [stream open]; NSMutableData *bytes=[NSMutableData data]; uint8_t buffer[1024]; NSInteger n; while ((n=[stream read:buffer maxLength:sizeof(buffer)])>0) [bytes appendBytes:buffer length:n]; [stream close]; body=bytes; }
    NSDictionary *p=body ? [NSJSONSerialization JSONObjectWithData:body options:0 error:NULL] : @{};
    id payload=@{};
    if ([path hasSuffix:@"/fetch_page"]) payload=@{@"chat_sessions":cloudDeleted ? @[] : @[cloudSession()],@"has_more":@NO};
    else if ([path hasSuffix:@"/history_messages"]) payload=@{@"chat_session":cloudSession(),@"chat_messages":cloudMessages(),@"cache_control":@"REPLACE"};
    else if (!cloudFail && [path hasSuffix:@"/update_title"]) cloudTitle=p[@"title"];
    else if (!cloudFail && [path hasSuffix:@"/batch_update_pinned"]) cloudPinned=[p[@"pinned"] boolValue];
    else if (!cloudFail && [path hasSuffix:@"/delete"]) cloudDeleted=YES;
    NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"code":@0,@"msg":@"",@"data":@{@"biz_code":@0,@"biz_msg":@"",@"biz_data":payload}} options:0 error:NULL];
    NSHTTPURLResponse *response=[[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:cloudFail ? 401 : 200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":@"application/json"}];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed]; [self.client URLProtocol:self didLoadData:data]; [self.client URLProtocolDidFinishLoading:self];
}
@end
@interface NSURLSession (RetryFixture)
+ (NSURLSession *)retrySession:(NSURLSessionConfiguration *)config delegate:(id<NSURLSessionDelegate>)delegate queue:(NSOperationQueue *)queue;
@end
@implementation NSURLSession (RetryFixture)
+ (NSURLSession *)retrySession:(NSURLSessionConfiguration *)config delegate:(id<NSURLSessionDelegate>)delegate queue:(NSOperationQueue *)queue {
    NSURLSessionConfiguration *copy=[config copy]; copy.protocolClasses=@[CloudFixture.class,RetryFixture.class];
    return [self retrySession:copy delegate:delegate queue:queue];
}
@end
@interface Capture : NSObject <NSURLProtocolClient>
@property(nonatomic, strong) NSMutableData *bytes;
@property(nonatomic, strong) NSError *error;
@property(nonatomic) BOOL done;
@end
@implementation Capture
- (instancetype)init { if ((self=[super init])) _bytes=[NSMutableData data]; return self; }
- (void)URLProtocol:(NSURLProtocol *)p didLoadData:(NSData *)data { [self.bytes appendData:data]; }
- (void)URLProtocolDidFinishLoading:(NSURLProtocol *)p { self.done=YES; }
- (void)URLProtocol:(NSURLProtocol *)p didFailWithError:(NSError *)error { self.error=error; self.done=YES; }
- (void)URLProtocol:(NSURLProtocol *)p didReceiveResponse:(NSURLResponse *)response cacheStoragePolicy:(NSURLCacheStoragePolicy)policy {}
- (void)URLProtocol:(NSURLProtocol *)p wasRedirectedToRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response {}
- (void)URLProtocol:(NSURLProtocol *)p cachedResponseIsValid:(NSCachedURLResponse *)cachedResponse {}
- (void)URLProtocol:(NSURLProtocol *)p didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {}
- (void)URLProtocol:(NSURLProtocol *)p didCancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {}
@end
static void check(BOOL value,NSString *message) {
    if (!value) { fprintf(stderr,"FAIL: %s\n",message.UTF8String); exit(1); }
}
static Capture *request(NSString *path,NSDictionary *body) {
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:[@"https://chat.deepseek.com/api/v0" stringByAppendingString:path]]];
    request.HTTPMethod=@"POST";
    if (cloudAuthorization) [request setValue:cloudAuthorization forHTTPHeaderField:@"Authorization"];
    request.HTTPBody=[NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
    Capture *capture=[Capture new];
    DSCompatibilityProtocol *protocol=[[DSCompatibilityProtocol alloc] initWithRequest:request cachedResponse:nil client:capture];
    [protocol startLoading];
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:5];
    while (!capture.done && deadline.timeIntervalSinceNow>0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    check(capture.done,@"local request completes without an external server");
    return capture;
}
static NSDictionary *payload(Capture *capture) {
    check(capture.error==nil,@"successful local route");
    NSDictionary *envelope=[NSJSONSerialization JSONObjectWithData:capture.bytes options:0 error:NULL];
    check([envelope[@"code"] isEqual:@0] && [envelope[@"data"][@"biz_code"] isEqual:@0],@"native response envelope");
    return envelope[@"data"][@"biz_data"];
}
int main(int argc,const char *argv[]) {
    @autoreleasepool {
        BOOL guest=argc>1 && strcmp(argv[1],"--guest-offline-mode")==0;
        BOOL enabled=!(argc>1 && strcmp(argv[1],"--official-mode")==0) && !guest;
        [NSUserDefaults.standardUserDefaults setBool:guest forKey:@"DSAPIAdapter.localGuestActive"];
        [NSUserDefaults.standardUserDefaults setObject:@{@"enabled":@(enabled)} forKey:@"DSAPIAdapter.configuration.v1"];
        if (guest) {
            __block NSUInteger notices=0;
            id observer=[NSNotificationCenter.defaultCenter addObserverForName:@"DSAPIAdapter.GuestSignInRequired" object:nil queue:nil usingBlock:^(NSNotification *note) { notices++; }];
            NSURLRequest *chat=[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://chat.deepseek.com/api/v0/chat/completion"]];
            check([DSCompatibilityProtocol canInitWithRequest:chat],@"local guest chat cannot fall through to the original service");
            check(request(@"/chat/completion",@{@"prompt":@"guest"}).error!=nil && notices==1,@"guest without API posts sign-in/API guidance without loading a key or calling a provider");
            NSDictionary *session=payload(request(@"/chat_session/create",@{})); check([session[@"id"] length]>0,@"guest can enter the original conversation UI before choosing a service");
            payload(request(@"/chat_session/delete_all",@{}));
            [NSNotificationCenter.defaultCenter removeObserver:observer];
            [NSUserDefaults.standardUserDefaults setBool:NO forKey:@"DSAPIAdapter.localGuestActive"];
            puts("PASS: offline guest local UI and sign-in/API guidance without official authentication"); return 0;
        }
        for (NSString *path in @[@"/users/login",@"/users/current",@"/users/logout",@"/users/update_settings",@"/index/prepare",@"/client/settings"]) {
            NSURL *url=[NSURL URLWithString:[@"https://chat.deepseek.com/api/v0" stringByAppendingString:path]];
            check(![DSCompatibilityProtocol canInitWithRequest:[NSURLRequest requestWithURL:url]],@"original login/account/bootstrap/settings always pass through");
        }
        NSURLRequest *chat=[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://chat.deepseek.com/api/v0/chat/completion"]];
        for (NSString *route in @[@"/file/upload_file",@"/file/fetch_files",@"/guest/chat/completion",@"/users/create_guest_challenge"]) {
            NSURL *url=[NSURL URLWithString:[@"https://chat.deepseek.com/api/v0" stringByAppendingString:route]];
            check([DSCompatibilityProtocol canInitWithRequest:[NSURLRequest requestWithURL:url]]==enabled,@"API attachments and guest chat never fall through to official authentication");
        }
        check([DSCompatibilityProtocol canInitWithRequest:chat]==enabled,@"chat interception follows startup mode");
        if (!enabled) {
            [NSUserDefaults.standardUserDefaults setObject:@{@"enabled":@YES} forKey:@"DSAPIAdapter.configuration.v1"];
            check(!DSAPIIsEnabled(),@"mode remains stable until app relaunch");
            check(DSAPIHasPendingModeChange() && [DSCompatibilityProtocol canInitWithRequest:chat],@"pending switch blocks original chat rather than mixing PoW verification");
            Capture *pending=request(@"/chat/create_pow_challenge",@{});
            check(pending.error!=nil && [pending.error.localizedDescription containsString:@"重新打开"],@"pending switch reports relaunch requirement before any original verification request");
            puts("PASS: original-service mode leaves chat, login and account routes intact"); return 0;
        }
        check(![DSCompatibilityProtocol canInitWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://api.example.com/v1/chat/completions"]]],@"caller API endpoint is not intercepted");
        check(![DSCompatibilityProtocol canInitWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://chat.deepseek.com/api/v0/users/login"]]],@"original login endpoint remains native in API mode");
        [NSUserDefaults.standardUserDefaults setObject:@{@"enabled":@NO} forKey:@"DSAPIAdapter.configuration.v1"];
        check(DSAPIHasPendingModeChange() && request(@"/file/upload_file",@{}).error!=nil,@"pending switch cannot send an upload using the previous service");
        [NSUserDefaults.standardUserDefaults setObject:@{@"enabled":@YES} forKey:@"DSAPIAdapter.configuration.v1"];
        payload(request(@"/chat_session/delete_all",@{}));
        NSDictionary *created=payload(request(@"/chat_session/create",@{@"model_type":@"default"}));
        NSString *sid=created[@"id"]; check(sid.length>0,@"session creation returns an identity");
        payload(request(@"/chat_session/update_title",@{@"chat_session_id":sid,@"title":@"本地🧠"}));
        NSDictionary *page=payload(request(@"/chat_session/fetch_page",@{}));
        check([page[@"chat_sessions"] count]==1 && [page[@"chat_sessions"][0][@"title"] isEqual:@"本地🧠"],@"rename survives independent requests");
        NSError *error=nil;
        check([DSLocalStore.shared beginTurn:sid parent:nil prompt:@"你好" thinking:YES error:&error]!=nil,@"native turn persisted");
        NSDictionary *history=payload(request(@"/chat/history_messages",@{@"chat_session_id":sid}));
        check([history[@"chat_messages"] count]==2,@"history route returns persisted messages");
        NSNumber *assistant=history[@"chat_messages"][1][@"message_id"];
        payload(request(@"/chat/message_feedback",@{@"chat_session_id":sid,@"message_id":assistant,@"feedback_type":@"GOOD"}));
        check([[[DSLocalStore.shared message:assistant session:sid][@"feedback"] objectForKey:@"feedback_type"] isEqual:@"GOOD"],@"native thumbs-up survives history reload");
        payload(request(@"/chat/message_feedback",@{@"chat_session_id":sid,@"message_id":assistant,@"feedback_type":@"NONE"}));
        check([DSLocalStore.shared message:assistant session:sid][@"feedback"]==NSNull.null,@"removing feedback clears the stored rating");
        for (NSDictionary *message in history[@"chat_messages"]) check([message[@"quasi_status"] isKindOfClass:NSString.class],@"native mandatory enum is not null");
        NSDictionary *settings=payload(request(@"/client/settings",@{}));
        check([settings[@"settings"] isKindOfClass:NSDictionary.class],@"native settings collection is a map");
        check(request(@"/users/login",@{}).error!=nil,@"original login never falls back to remote service");
        check(request(@"/unsupported",@{}).error!=nil,@"unknown route fails instead of forwarding");
        method_exchangeImplementations(class_getClassMethod(DSAPIConfiguration.class,@selector(loadConfiguration)),class_getClassMethod(DSAPIConfiguration.class,@selector(retryConfiguration)));
        method_exchangeImplementations(class_getClassMethod(NSURLSession.class,@selector(sessionWithConfiguration:delegate:delegateQueue:)),class_getClassMethod(NSURLSession.class,@selector(retrySession:delegate:queue:)));
        NSNumber *question=history[@"chat_messages"][0][@"message_id"];
        for (NSString *route in @[@"/chat/regenerate",@"/chat/completion"]) {
            Capture *retry=request(route,@{@"chat_session_id":sid,@"parent_message_id":assistant,@"action":@"retry",@"prompt":@""});
            check(!retry.error,@"original retry route completes as native SSE");
            check([retryPayload[@"messages"] count]==1 && [retryPayload[@"messages"][0][@"role"] isEqual:@"user"] && [retryPayload[@"messages"][0][@"content"] isEqual:@"你好"],@"retry sends original question without previous answer or duplicate prompt");
            NSDictionary *replacement=DSLocalStore.shared.sessions.count ? [DSLocalStore.shared messages:sid].lastObject : nil;
            check([replacement[@"parent_id"] isEqual:question],@"regenerated answer is a sibling under the original question");
            assistant=replacement[@"message_id"];
        }
        Capture *nativeRetry=request(@"/chat/regenerate",@{@"chat_session_id":sid,@"child_message_id":assistant,@"thinking_enabled":@NO,@"search_enabled":@NO});
        check(!nativeRetry.error,@"native child_message_id regeneration completes");
        check([retryPayload[@"messages"] count]==1 && [retryPayload[@"messages"][0][@"role"] isEqual:@"user"],@"native regeneration excludes the replaced answer");
        check([[[DSLocalStore.shared messages:sid].lastObject objectForKey:@"parent_id"] isEqual:question],@"native regeneration keeps the original question as parent");
        NSInteger userCount=0; for (NSDictionary *message in [DSLocalStore.shared messages:sid]) if ([message[@"role"] isEqual:@"USER"]) userCount++;
        check(userCount==1,@"regeneration never creates another copy of the user question");
        NSData *png=[[NSData alloc] initWithBase64EncodedString:@"iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEklEQVR4nGP4z8CAFWEXHbQSACj/P8Fu7N9hAAAAAElFTkSuQmCC" options:0];
        NSMutableURLRequest *upload=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://chat.deepseek.com/api/v0/file/upload_file"]];
        [upload setValue:@"multipart/form-data; boundary=image-test" forHTTPHeaderField:@"Content-Type"];
        NSMutableData *body=[[@"--image-test\r\nContent-Disposition: form-data; name=\"file\"; filename=\"red.png\"\r\nContent-Type: image/png\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
        [body appendData:png]; [body appendData:[@"\r\n--image-test--\r\n" dataUsingEncoding:NSUTF8StringEncoding]]; upload.HTTPBody=body;
        NSError *fileError=nil; NSDictionary *file=[DSAttachmentStore.shared importRequest:upload error:&fileError];
        check(file!=nil && !fileError,@"image imported locally without original auth or PoW headers");
        Capture *withImage=request(@"/chat/completion",@{@"chat_session_id":sid,@"parent_message_id":assistant,@"prompt":@"看图",@"ref_file_ids":@[file[@"id"]]});
        check(!withImage.error,@"native image completion reaches the compatible API");
        NSArray *parts=retryPayload[@"messages"][[retryPayload[@"messages"] count]-1][@"content"];
        check([parts isKindOfClass:NSArray.class] && parts.count==2 && [parts[0][@"text"] isEqual:@"看图"] && [parts[1][@"type"] isEqual:@"image_url"],@"last user turn preserves text and multimodal image");
        NSArray *retained=[DSLocalStore.shared apiHistory:sid endingAt:[DSLocalStore.shared messages:sid].lastObject[@"parent_id"] error:&fileError];
        check([retained.lastObject[@"content"] isKindOfClass:NSArray.class],@"image context survives replay and is not dropped");
        NSDictionary *found=payload(request(@"/file/fetch_files",@{@"file_ids":@[file[@"id"]]}));
        check([found[@"files"] count]==1,@"native upload polling returns the local file");
        NSUInteger countBefore=[DSLocalStore.shared messages:sid].count;
        check(request(@"/chat/completion",@{@"chat_session_id":sid,@"prompt":@"missing",@"ref_file_ids":@[@"api-file-missing"]}).error!=nil,@"missing attachment fails before sending partial content");
        check([DSLocalStore.shared messages:sid].count==countBefore,@"missing attachments do not mutate chat history");
        check(configurationReadOffMain,@"chat configuration and keychain reads never block the UI thread");
        payload(request(@"/chat_session/delete",@{@"chat_session_ids":@[sid]}));
        check([payload(request(@"/chat_session/fetch_page",@{}))[@"chat_sessions"] count]==0,@"delete updates native inventory");
        cloudAuthorization=@"Bearer official-account-fixture-token";
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"DSAPIAdapter.currentOfficialUserID"];
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"DSAPIAdapter.currentOfficialIdentity"];
        check([payload(request(@"/chat_session/fetch_page",@{}))[@"chat_sessions"] count]==1,@"API inventory includes original account history");
        bindIdentity(@"fixture-owner-a",@"official-account-fixture-token");
        check([payload(request(@"/chat/history_messages",@{@"chat_session_id":@"cloud-history-fixture"}))[@"chat_messages"] count]==2,@"original messages are imported before continuation");
        check(!request(@"/chat/completion",@{@"chat_session_id":@"cloud-history-fixture",@"parent_message_id":@42,@"prompt":@"continue cloud history"}).error,@"original account conversation can continue through API");
        check([retryPayload[@"messages"] count]==3 && [retryPayload[@"messages"][1][@"content"] isEqual:@"earlier answer"],@"API receives original account context");
        check([payload(request(@"/chat/history_messages",@{@"chat_session_id":@"cloud-history-fixture"}))[@"chat_messages"] count]==4,@"original refresh retains locally generated API turns");
        cloudAuthorization=@"Bearer rotated-account-fixture-token";
        bindIdentity(@"fixture-owner-a",@"rotated-account-fixture-token");
        check([payload(request(@"/chat/history_messages",@{@"chat_session_id":@"cloud-history-fixture"}))[@"chat_messages"] count]==4,@"token rotation keeps the same account cache");
        [NSUserDefaults.standardUserDefaults setObject:@"fixture-owner-b" forKey:@"DSAPIAdapter.currentOfficialUserID"];
        check(request(@"/chat/history_messages",@{@"chat_session_id":@"cloud-history-fixture"}).error!=nil,@"another account cannot read cached cloud history");
        [NSUserDefaults.standardUserDefaults setObject:@"fixture-owner-a" forKey:@"DSAPIAdapter.currentOfficialUserID"];
        payload(request(@"/chat_session/update_title",@{@"chat_session_id":@"cloud-history-fixture",@"title":@"Cloud title changed"}));
        check([cloudTitle isEqual:@"Cloud title changed"],@"cloud rename reaches the original service");
        payload(request(@"/chat_session/batch_update_pinned",@{@"chat_session_ids":@[@"cloud-history-fixture"],@"pinned":@YES})); check(cloudPinned,@"cloud pin reaches original service");
        cloudFail=YES; check(request(@"/chat_session/delete",@{@"chat_session_ids":@[@"cloud-history-fixture"]}).error!=nil && [DSLocalStore.shared session:@"cloud-history-fixture"]!=nil,@"failed cloud deletion preserves the local thread");
        cloudFail=NO; payload(request(@"/chat_session/delete",@{@"chat_session_ids":@[@"cloud-history-fixture"]})); check(cloudDeleted && ![DSLocalStore.shared session:@"cloud-history-fixture"],@"confirmed cloud deletion removes local copy");
        check(![DSLocalStore.shared adoptCloudOwner:identityHash(@"token:Bearer official-account-fixture-token") asOwner:identityHash(@"user:fixture-owner-b") error:NULL],@"a claimed token cache cannot be transferred to another account");
        cloudAuthorization=nil; [NSUserDefaults.standardUserDefaults removeObjectForKey:@"DSAPIAdapter.currentOfficialUserID"];
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"DSAPIAdapter.currentOfficialIdentity"];
        puts("PASS: native URLProtocol CRUD, envelopes, required status, local-only login rejection, unknown-route rejection");
    }
    return 0;
}
