#import <Foundation/Foundation.h>
#import "DSOpenAIClient.h"

static NSMutableArray *results;
static BOOL runCase(NSString *name, NSString *key, NSString *model, BOOL thinking,
    NSArray *history, NSString *system, NSString *expected, NSInteger expectedError, BOOL cancel) {
    DSAPIConfiguration *config=[DSAPIConfiguration new];
    config.baseURL=@"https://api.deepseek.com/v1"; config.apiKey=key; config.model=model;
    config.reasoningModel=@""; config.systemPrompt=system; config.timeout=30;
    DSOpenAIClient *client=[[DSOpenAIClient alloc] initWithConfiguration:config];
    __block NSUInteger terminals=0, chunks=0;
    __block NSError *failure=nil;
    NSMutableString *text=[NSMutableString string], *reasoning=[NSMutableString string];
    CFAbsoluteTime start=CFAbsoluteTimeGetCurrent();
    __block double first=-1;
    [client startMessages:history reasoning:thinking delta:^(NSString *a,NSString *b) {
        [text appendString:a]; [reasoning appendString:b]; chunks++;
        if (first<0) first=CFAbsoluteTimeGetCurrent()-start;
        if (cancel) [client cancel];
    } completion:^(NSString *reason,NSError *error) { terminals++; failure=error; }];
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:60];
    while (!terminals && deadline.timeIntervalSinceNow>0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    BOOL passed=terminals==1;
    if (expectedError) passed &= failure.code==expectedError;
    else passed &= !failure && text.length>0 && (!expected.length || [text containsString:expected]);
    if (thinking && !expectedError) passed &= reasoning.length>0;
    if (cancel) passed &= chunks>0 && [failure.domain isEqual:NSURLErrorDomain];
    [client cancel];
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    passed &= terminals==1;
    NSMutableDictionary *record=[@{@"name":name,@"passed":@(passed),@"model":model,@"thinking":@(thinking),
        @"delta_callbacks":@(chunks),@"text_characters":@(text.length),@"reasoning_characters":@(reasoning.length),
        @"terminal_callbacks":@(terminals),@"elapsed_seconds":@(CFAbsoluteTimeGetCurrent()-start),
        @"first_delta_seconds":@(first)} mutableCopy];
    if (failure) { record[@"error_domain"]=failure.domain; record[@"error_code"]=@(failure.code); }
    [results addObject:record];
    printf("%s: %s\n",passed ? "PASS" : "FAIL",name.UTF8String);
    return passed;
}
int main(void) {
    @autoreleasepool {
        NSString *key=NSProcessInfo.processInfo.environment[@"TEST_API_KEY"];
        if (!key.length) { fputs("Missing runtime test secret\n",stderr); return 1; }
        results=[NSMutableArray array]; BOOL passed=YES;
        NSArray *simple=@[@{@"role":@"user",@"content":@"Reply briefly with DSAPI_OK and a globe emoji."}];
        passed &= runCase(@"native_unicode_stream",key,@"deepseek-flash",NO,simple,@"",@"DSAPI_OK",0,NO);
        passed &= runCase(@"native_thinking_stream",key,@"deepseek-flash",YES,
            @[@{@"role":@"user",@"content":@"Compute 17*23; reply with the answer only."}],@"",@"391",0,NO);
        passed &= runCase(@"native_context_and_system",key,@"deepseek-flash",NO,
            @[@{@"role":@"user",@"content":@"Remember code 7319."},@{@"role":@"assistant",@"content":@"Code remembered: 7319."},
              @{@"role":@"user",@"content":@"What is the code?"}],@"Reply with the numeric code only.",@"7319",0,NO);
        passed &= runCase(@"native_cancel",key,@"deepseek-flash",NO,
            @[@{@"role":@"user",@"content":@"Count from 1 to 100, one number per line."}],@"",@"",NSURLErrorCancelled,YES);
        passed &= runCase(@"native_invalid_key",@"invalid-ci-key",@"deepseek-flash",NO,simple,@"",@"",401,NO);
        passed &= runCase(@"native_invalid_model",key,@"dsapi-nonexistent-model",NO,simple,@"",@"",400,NO);
        NSDictionary *report=@{@"scope":@"Actual production Objective-C client on macOS; not IPA UI or device signing acceptance",
            @"base_url":@"https://api.deepseek.com/v1",@"passed":@(passed),@"cases":results};
        [NSFileManager.defaultManager createDirectoryAtPath:@"diagnostics" withIntermediateDirectories:YES attributes:nil error:NULL];
        [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:NULL]
            writeToFile:@"diagnostics/live-native-client.json" atomically:YES];
        return passed ? 0 : 1;
    }
}
