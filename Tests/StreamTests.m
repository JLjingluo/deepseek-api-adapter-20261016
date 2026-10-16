#import <Foundation/Foundation.h>
#import "DSStreamDecoder.h"
#import "DSAPIConfiguration.h"

static void check(BOOL condition, NSString *message) {
    if (!condition) { fprintf(stderr,"FAIL: %s\n",message.UTF8String); exit(1); }
}
static NSString *event(NSDictionary *delta, id finish) {
    NSDictionary *value = @{@"choices":@[@{@"index":@0,@"delta":delta,@"finish_reason":finish ?: NSNull.null}]};
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:0 error:NULL];
    return [NSString stringWithFormat:@"data: %@\n\n",[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]];
}
static void fragmented(NSString *stream, NSString *text, NSString *thought) {
    NSData *bytes = [stream dataUsingEncoding:NSUTF8StringEncoding];
    for (NSUInteger split = 0; split <= bytes.length; split++) {
        DSStreamDecoder *decoder = [DSStreamDecoder new];
        NSMutableString *body = [NSMutableString string], *reasoning = [NSMutableString string];
        __block NSUInteger finished = 0, failed = 0;
        decoder.onDelta = ^(NSString *a, NSString *b) { [body appendString:a]; [reasoning appendString:b]; };
        decoder.onFinish = ^(NSString *reason) { finished++; };
        decoder.onError = ^(NSError *error) { failed++; };
        [decoder consume:[bytes subdataWithRange:NSMakeRange(0,split)]];
        [decoder consume:[bytes subdataWithRange:NSMakeRange(split,bytes.length-split)]];
        [decoder endOfInput];
        check(finished == 1 && failed == 0, @"single successful terminal delivery");
        check([body isEqual:text] && [reasoning isEqual:thought], @"fragmented UTF-8 and reasoning preserved");
    }
}
static void fails(NSString *stream, NSString *label) {
    DSStreamDecoder *decoder = [DSStreamDecoder new];
    __block NSUInteger failed = 0, finished = 0;
    decoder.onFinish = ^(NSString *reason) { finished++; };
    decoder.onError = ^(NSError *error) { failed++; };
    [decoder consume:[stream dataUsingEncoding:NSUTF8StringEncoding]];
    [decoder endOfInput]; [decoder endOfInput];
    check(failed == 1 && finished == 0, label);
}
int main(void) {
    @autoreleasepool {
        NSString *stream = [@[event(@{@"role":@"assistant"},nil), event(@{@"reasoning_content":@"思考🧠"},nil),
            event(@{@"content":@"你好 🌍"},nil), event(@{},@"stop"), @"data: [DONE]\n\n"] componentsJoinedByString:@""];
        fragmented(stream,@"你好 🌍",@"思考🧠");
        fragmented([stream stringByReplacingOccurrencesOfString:@"\n" withString:@"\r\n"],@"你好 🌍",@"思考🧠");
        fragmented([stream stringByReplacingOccurrencesOfString:@"\n" withString:@"\r"],@"你好 🌍",@"思考🧠");
        fragmented([@"\ufeff: heartbeat\n\n" stringByAppendingString:stream],@"你好 🌍",@"思考🧠");
        fragmented([event(@{@"content":@"ok"},@"length") stringByAppendingString:@"data: {\"choices\":[]}\n\n"],@"ok",@"");
        fails(event(@{@"content":@"partial"},nil),@"disconnect is not success");
        fails(@"data: {\"choices\":[]}",@"truncated event");
        fails(@"data: {invalid}\n\n",@"malformed JSON");
        fails(@"data: {\"error\":{}}\n\n",@"API error");
        fails(event(@{@"tool_calls":@[]},nil),@"unhandled tool calls fail explicitly");
        DSAPIConfiguration *configuration = [DSAPIConfiguration new];
        for (NSString *base in @[@"https://example.com/v1",@"https://example.com/v1/",@"https://example.com/v1/chat/completions"]) {
            configuration.baseURL = base;
            check([[configuration completionURL:NULL].absoluteString isEqual:@"https://example.com/v1/chat/completions"],@"URL composition");
        }
        for (NSString *base in @[@"http://example.com/v1",@"https://user:secret@example.com",@"https://example.com?key=secret",@"file:///tmp/test"]) {
            configuration.baseURL = base; check([configuration completionURL:NULL] == nil,@"unsafe URL rejected");
        }
        puts("PASS: stream fragmentation, terminal errors, reasoning, URL validation");
    }
    return 0;
}
