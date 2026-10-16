#import "DSOpenAIClient.h"
#import "DSStreamDecoder.h"
@implementation DSOpenAIClient {
    DSAPIConfiguration *_configuration;
    NSURLSession *_session;
    NSURLSessionDataTask *_task;
    DSStreamDecoder *_decoder;
    void (^_completion)(NSString *, NSError *);
    BOOL _finished, _started;
}
- (instancetype)initWithConfiguration:(DSAPIConfiguration *)configuration {
    if ((self = [super init])) _configuration = configuration;
    return self;
}
- (void)complete:(NSString *)reason error:(NSError *)error {
    if (_finished) return;
    _finished = YES;
    void (^callback)(NSString *, NSError *) = _completion; _completion = nil;
    _decoder.onDelta = nil; _decoder.onFinish = nil; _decoder.onError = nil;
    [_task cancel]; [_session invalidateAndCancel];
    _task = nil; _session = nil;
    if (callback) callback(reason, error);
}
- (void)startMessages:(NSArray<NSDictionary *> *)messages reasoning:(BOOL)reasoning
    delta:(void (^)(NSString *, NSString *))delta
    completion:(void (^)(NSString *, NSError *))completion {
    NSAssert(NSThread.isMainThread, @"Start on the main queue");
    if (_started) {
        completion(nil, [NSError errorWithDomain:@"DSAPI.Client" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Client already started"}]);
        return;
    }
    _started = YES; _completion = [completion copy];
    NSError *error = nil;
    NSURL *url = [_configuration completionURL:&error];
    if (!url) { [self complete:nil error:error]; return; }
    NSString *model = reasoning && _configuration.reasoningModel.length ? _configuration.reasoningModel : _configuration.model;
    if (!model.length || !messages.count) {
        [self complete:nil error:[NSError errorWithDomain:@"DSAPI.Client" code:2
            userInfo:@{NSLocalizedDescriptionKey:@"A model and message history are required"}]]; return;
    }
    NSMutableArray *history = [messages mutableCopy];
    if (_configuration.systemPrompt.length) [history insertObject:@{@"role":@"system", @"content":_configuration.systemPrompt} atIndex:0];
    NSData *body = [NSJSONSerialization dataWithJSONObject:@{@"model":model, @"messages":history, @"stream":@YES}
        options:0 error:&error];
    if (!body) { [self complete:nil error:error]; return; }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST"; request.HTTPBody = body;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"text/event-stream" forHTTPHeaderField:@"Accept"];
    if (_configuration.apiKey.length) [request setValue:[@"Bearer " stringByAppendingString:_configuration.apiKey] forHTTPHeaderField:@"Authorization"];
    NSURLSessionConfiguration *sessionConfig = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    sessionConfig.timeoutIntervalForRequest = _configuration.timeout;
    sessionConfig.timeoutIntervalForResource = 3600;
    sessionConfig.HTTPCookieStorage = nil; sessionConfig.URLCache = nil;
    _session = [NSURLSession sessionWithConfiguration:sessionConfig delegate:self delegateQueue:NSOperationQueue.mainQueue];
    _decoder = [DSStreamDecoder new];
    __weak typeof(self) weakSelf = self;
    _decoder.onDelta = delta;
    _decoder.onFinish = ^(NSString *reason) { [weakSelf complete:reason error:nil]; };
    _decoder.onError = ^(NSError *streamError) { [weakSelf complete:nil error:streamError]; };
    _task = [_session dataTaskWithRequest:request]; [_task resume];
}
- (void)cancel {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self complete:nil error:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]];
    });
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task
    didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))handler {
    NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
    NSInteger status = [http isKindOfClass:NSHTTPURLResponse.class] ? http.statusCode : 0;
    NSString *type = response.MIMEType.lowercaseString;
    if (status < 200 || status >= 300 ||
        ![type isEqualToString:@"text/event-stream"]) {
        handler(NSURLSessionResponseCancel);
        [self complete:nil error:[NSError errorWithDomain:@"DSAPI.HTTP" code:status
            userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"API HTTP %ld：需要成功的 SSE 响应。",(long)status]}]];
    } else handler(NSURLSessionResponseAllow);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    if (!_finished) [_decoder consume:data];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (_finished) return;
    if (error) [self complete:nil error:error]; else [_decoder endOfInput];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
    willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request
    completionHandler:(void (^)(NSURLRequest * _Nullable))handler {
    // Do not forward the caller's key to a redirected endpoint.
    handler(nil);
    [self complete:nil error:[NSError errorWithDomain:@"DSAPI.HTTP" code:response.statusCode
        userInfo:@{NSLocalizedDescriptionKey:@"API 重定向已拒绝；请在设置中填写最终 Base URL。"}]];
}
@end
