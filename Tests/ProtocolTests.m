#import <Foundation/Foundation.h>
#import "DSCompatibilityProtocol.h"
#import "DSLocalStore.h"
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
int main(void) {
    @autoreleasepool {
        check(![DSCompatibilityProtocol canInitWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://api.example.com/v1/chat/completions"]]],@"caller API endpoint is not intercepted");
        check([DSCompatibilityProtocol canInitWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://chat.deepseek.com/api/v0/users/login"]]],@"original login endpoint stays local");
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
        for (NSDictionary *message in history[@"chat_messages"]) check([message[@"quasi_status"] isKindOfClass:NSString.class],@"native mandatory enum is not null");
        NSDictionary *settings=payload(request(@"/client/settings",@{}));
        check([settings[@"settings"] isKindOfClass:NSDictionary.class],@"native settings collection is a map");
        check(request(@"/users/login",@{}).error!=nil,@"original login never falls back to remote service");
        check(request(@"/unsupported",@{}).error!=nil,@"unknown route fails instead of forwarding");
        payload(request(@"/chat_session/delete",@{@"chat_session_ids":@[sid]}));
        check([payload(request(@"/chat_session/fetch_page",@{}))[@"chat_sessions"] count]==0,@"delete updates native inventory");
        puts("PASS: native URLProtocol CRUD, envelopes, required status, local-only login rejection, unknown-route rejection");
    }
    return 0;
}
