#import <Foundation/Foundation.h>
#import "DSOpenAIClient.h"
#import "DSUsageStore.h"
#import <objc/runtime.h>

static void check(BOOL value, NSString *name) {
    if (!value) { fprintf(stderr,"FAIL: %s\n",name.UTF8String); exit(1); }
}
static NSDictionary *lastBody;
static NSString *lastAuthorization;
static NSString *scenario;
@interface ClientFixture : NSURLProtocol
@property(nonatomic) BOOL cancelled;
@end

@interface NSURLSession (FixtureSession)
+ (NSURLSession *)fixtureSessionWithConfiguration:(NSURLSessionConfiguration *)config
    delegate:(id<NSURLSessionDelegate>)delegate delegateQueue:(NSOperationQueue *)queue;
@end
@implementation NSURLSession (FixtureSession)
+ (NSURLSession *)fixtureSessionWithConfiguration:(NSURLSessionConfiguration *)config
    delegate:(id<NSURLSessionDelegate>)delegate delegateQueue:(NSOperationQueue *)queue {
    NSURLSessionConfiguration *copy=[config copy];
    copy.protocolClasses=@[ClientFixture.class];
    return [self fixtureSessionWithConfiguration:copy delegate:delegate delegateQueue:queue];
}
@end
@implementation ClientFixture
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    return [request.URL.host isEqualToString:@"api.fixture.test"];
}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)stopLoading { self.cancelled=YES; }
- (void)startLoading {
    NSData *body=self.request.HTTPBody;
    if (!body && self.request.HTTPBodyStream) {
        NSInputStream *stream=self.request.HTTPBodyStream; [stream open];
        NSMutableData *bytes=[NSMutableData data]; uint8_t buffer[1024]; NSInteger length;
        while ((length=[stream read:buffer maxLength:sizeof(buffer)])>0) [bytes appendBytes:buffer length:length];
        [stream close]; body=bytes;
    }
    lastBody=body ? [NSJSONSerialization JSONObjectWithData:body options:0 error:NULL] : nil;
    lastAuthorization=[self.request valueForHTTPHeaderField:@"Authorization"];
    NSString *mode=[scenario copy];
    if ([mode isEqual:@"timeout"]) {
        [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil]];
        return;
    }
    if ([mode isEqual:@"cancel"]) return;
    NSInteger status=[mode hasPrefix:@"http"] ? [[mode substringFromIndex:4] integerValue] : 200;
    NSString *mime=[mode isEqual:@"mime"] ? @"application/json" : @"text/event-stream";
    NSHTTPURLResponse *response=[[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:status HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":mime}];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    NSString *wire=@"data: {\"choices\":[{\"index\":0,\"delta\":{\"reasoning_content\":\"思考🧠\"}}]}\n\ndata: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"你好🌏\"}}]}\n\ndata: {\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n";
    if ([mode isEqual:@"malformed"]) wire=@"data: {invalid}\n\n";
    if ([mode isEqual:@"truncated"]) wire=@"data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"partial\"}}]}\n\n";
    if ([mode isEqual:@"success"]) wire=[wire stringByReplacingOccurrencesOfString:@"data: [DONE]" withString:@"data: {\"choices\":[],\"usage\":{\"prompt_tokens\":5,\"completion_tokens\":3,\"total_tokens\":8}}\n\ndata: [DONE]"];
    NSData *bytes=[wire dataUsingEncoding:NSUTF8StringEncoding];
    for (NSUInteger offset=0;offset<bytes.length;offset+=3) {
        [self.client URLProtocol:self didLoadData:[bytes subdataWithRange:NSMakeRange(offset,MIN(3,bytes.length-offset))]];
    }
    [self.client URLProtocolDidFinishLoading:self];
}
@end

static void runCase(NSString *name, BOOL success) {
    NSDictionary *usageBefore=DSAPIUsageSnapshot();
    scenario=name;
    DSAPIConfiguration *config=[DSAPIConfiguration new];
    config.baseURL=@"https://api.fixture.test/v1"; config.model=@"base-model";
    config.reasoningModel=@"reason-model"; config.apiKey=@"test-dummy-key";
    config.systemPrompt=@"system instruction"; config.timeout=10;
    config.requestUsage=![name isEqual:@"usage-off"];
    DSOpenAIClient *client=[[DSOpenAIClient alloc] initWithConfiguration:config];
    __block NSUInteger terminals=0; __block NSError *failure=nil;
    NSMutableString *text=[NSMutableString string], *thought=[NSMutableString string];
    [client startMessages:@[@{@"role":@"user",@"content":@"hello"}] reasoning:YES
        delta:^(NSString *a,NSString *b) { [text appendString:a]; [thought appendString:b]; }
        completion:^(NSString *reason,NSError *error) { terminals++; failure=error; }];
    if ([name isEqual:@"cancel"]) [client cancel];
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:5];
    while (!terminals && deadline.timeIntervalSinceNow>0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    check(terminals==1,[name stringByAppendingString:@" finishes once"]);
    if (success && failure) fprintf(stderr,"Client failure: %s:%ld (%s); fixture reached=%s\n",
        failure.domain.UTF8String,(long)failure.code,failure.localizedDescription.UTF8String,lastBody ? "yes" : "no");
    check(success ? !failure : failure!=nil,[name stringByAppendingString:@" expected outcome"]);
    if (success) {
        NSDictionary *snapshot=DSAPIUsageSnapshot();
        long long tokens=[snapshot[@"total_tokens"] longLongValue]-[usageBefore[@"total_tokens"] longLongValue];
        check(tokens==([name isEqual:@"usage-off"] ? 0 : 8),@"usage records server counts and never estimates absent counts");
        if ([name isEqual:@"usage-off"]) check([snapshot[@"unreported_requests"] longLongValue]-[usageBefore[@"unreported_requests"] longLongValue]==1,@"successful stream without usage remains explicitly unreported");
        NSData *json=[NSJSONSerialization dataWithJSONObject:snapshot options:0 error:NULL];
        check(![[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] containsString:@"test-dummy-key"],@"usage history never contains the API key");
        check([text isEqual:@"你好🌏"] && [thought isEqual:@"思考🧠"],@"native client preserves byte-fragmented text and reasoning");
        check([lastBody[@"model"] isEqual:@"reason-model"] && [lastBody[@"stream"] boolValue],@"reasoning model selection and SSE request");
        check([lastBody[@"messages"][0][@"role"] isEqual:@"system"] && [lastBody[@"messages"] count]==2,@"system instruction precedes caller history");
        check(lastBody[@"thinking"]==nil,@"generic compatible endpoint has no provider-specific parameters");
        check(config.requestUsage ? [lastBody[@"stream_options"][@"include_usage"] boolValue] : lastBody[@"stream_options"]==nil,@"standard usage option follows the saved provider setting");
        check([lastAuthorization isEqual:@"Bearer test-dummy-key"],@"caller key sent to chosen endpoint");
    }
    [client cancel];
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    check(terminals==1,@"cancelling a completed request does not duplicate terminal callback");
    check([DSAPIUsageSnapshot()[@"requests"] longLongValue]-[usageBefore[@"requests"] longLongValue]==1,@"stream chunks and repeated cancellation do not duplicate usage records");
}
int main(void) {
    @autoreleasepool {
        [NSURLProtocol registerClass:ClientFixture.class];
        Method normal=class_getClassMethod(NSURLSession.class,@selector(sessionWithConfiguration:delegate:delegateQueue:));
        Method fixture=class_getClassMethod(NSURLSession.class,@selector(fixtureSessionWithConfiguration:delegate:delegateQueue:));
        method_exchangeImplementations(normal,fixture);
        runCase(@"success",YES);
        runCase(@"usage-off",YES);
        for (NSString *name in @[@"http401",@"http429",@"http500",@"mime",@"malformed",@"truncated",@"timeout",@"cancel"])
            runCase(name,NO);
        [NSURLProtocol unregisterClass:ClientFixture.class];
        method_exchangeImplementations(normal,fixture);
        puts("PASS: native client streaming, reasoning, history, HTTP errors, malformed/truncated streams, timeout, cancellation");
    }
    return 0;
}
