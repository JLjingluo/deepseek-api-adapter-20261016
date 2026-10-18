#import <Foundation/Foundation.h>
#import "DSCompatibilityProtocol.h"
#import "DSLocalStore.h"
#import "DSAPIConfiguration.h"
#import <objc/runtime.h>
#include <string.h>
static NSDictionary *retryPayload;
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
    DSAPIConfiguration *c=[self new]; c.baseURL=@"https://api.fixture.test/v1"; c.apiKey=@"protocol-fixture-key";
    c.model=@"fixture-model"; c.reasoningModel=@""; c.systemPrompt=@""; c.timeout=30; return c;
}
@end
@interface NSURLSession (RetryFixture)
+ (NSURLSession *)retrySession:(NSURLSessionConfiguration *)config delegate:(id<NSURLSessionDelegate>)delegate queue:(NSOperationQueue *)queue;
@end
@implementation NSURLSession (RetryFixture)
+ (NSURLSession *)retrySession:(NSURLSessionConfiguration *)config delegate:(id<NSURLSessionDelegate>)delegate queue:(NSOperationQueue *)queue {
    NSURLSessionConfiguration *copy=[config copy]; copy.protocolClasses=@[RetryFixture.class];
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
        BOOL enabled=!(argc>1 && strcmp(argv[1],"--official-mode")==0);
        [NSUserDefaults.standardUserDefaults setObject:@{@"enabled":@(enabled)} forKey:@"DSAPIAdapter.configuration.v1"];
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
            puts("PASS: original-service mode leaves chat, login and account routes intact"); return 0;
        }
        check(![DSCompatibilityProtocol canInitWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://api.example.com/v1/chat/completions"]]],@"caller API endpoint is not intercepted");
        check(![DSCompatibilityProtocol canInitWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://chat.deepseek.com/api/v0/users/login"]]],@"original login endpoint remains native in API mode");
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
        payload(request(@"/chat_session/delete",@{@"chat_session_ids":@[sid]}));
        check([payload(request(@"/chat_session/fetch_page",@{}))[@"chat_sessions"] count]==0,@"delete updates native inventory");
        puts("PASS: native URLProtocol CRUD, envelopes, required status, local-only login rejection, unknown-route rejection");
    }
    return 0;
}
