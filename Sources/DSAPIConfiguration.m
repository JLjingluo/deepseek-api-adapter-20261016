#import "DSAPIConfiguration.h"
#import <Security/Security.h>
#import "DSAPILocalization.h"

static NSString *const DSConfigKey = @"DSAPIAdapter.configuration.v1";
static NSDictionary *DSKeyQuery(void) {
    return @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService:@"DSAPIAdapter",
        (__bridge id)kSecAttrAccount:@"api-key"};
}
static NSError *DSConfigError(NSString *description) {
    return [NSError errorWithDomain:@"DSAPI.Configuration" code:1
        userInfo:@{NSLocalizedDescriptionKey:description}];
}
@interface DSAPIConfiguration ()
- (BOOL)saveKeyData:(NSData *)data error:(NSError **)error;
@end
@implementation DSAPIConfiguration
- (instancetype)init { if ((self=[super init])) { _requestUsage=YES; _reasoningEffort=@"auto"; } return self; }
+ (instancetype)loadConfigurationWithoutAPIKey {
    DSAPIConfiguration *config = [self new];
    NSDictionary *values = [NSUserDefaults.standardUserDefaults dictionaryForKey:DSConfigKey];
    config.baseURL = [values[@"baseURL"] isKindOfClass:NSString.class] ? values[@"baseURL"] : @"https://api.deepseek.com/v1";
    config.model = [values[@"model"] isKindOfClass:NSString.class] ? values[@"model"] : @"deepseek-chat";
    config.reasoningModel = [values[@"reasoningModel"] isKindOfClass:NSString.class] ? values[@"reasoningModel"] : @"";
    config.systemPrompt = [values[@"systemPrompt"] isKindOfClass:NSString.class] ? values[@"systemPrompt"] : @"";
    config.timeout = [values[@"timeout"] isKindOfClass:NSNumber.class] ? [values[@"timeout"] doubleValue] : 180;
    config.enabled = [values[@"enabled"] boolValue];
    config.showAPIInChat=[values[@"showAPIInChat"] boolValue];
    config.automaticModels=[values[@"automaticModels"] boolValue];
    config.reasoningEffort=[values[@"reasoningEffort"] isKindOfClass:NSString.class] ? values[@"reasoningEffort"] : @"auto";
    config.requestUsage = [values[@"requestUsage"] isKindOfClass:NSNumber.class] ? [values[@"requestUsage"] boolValue] : YES;
    config.apiKey=@"";
    return config;
}
+ (instancetype)loadConfiguration {
    DSAPIConfiguration *config=[self loadConfigurationWithoutAPIKey];
    NSMutableDictionary *query = [DSKeyQuery() mutableCopy];
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    NSData *data = CFBridgingRelease(result);
    config.apiKey = status == errSecSuccess ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"" : @"";
    return config;
}
- (NSURL *)completionURL:(NSError **)error {
    NSString *base = [self.baseURL stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSURLComponents *components = [NSURLComponents componentsWithString:base];
    if (![components.scheme.lowercaseString isEqualToString:@"https"] || !components.host.length ||
        components.user || components.password || components.query || components.fragment) {
        if (error) *error = DSConfigError(DSAPILocalized(@"invalidURL"));
        return nil;
    }
    NSString *path = components.path;
    while ([path hasSuffix:@"/"]) path = [path substringToIndex:path.length - 1];
    if (![path hasSuffix:@"/chat/completions"]) path = [path stringByAppendingString:@"/chat/completions"];
    components.path = path;
    return components.URL;
}
- (NSURL *)modelsURL:(NSError **)error {
    NSURL *completion=[self completionURL:error]; if (!completion) return nil;
    NSURLComponents *parts=[NSURLComponents componentsWithURL:completion resolvingAgainstBaseURL:NO];
    parts.path=[[parts.path substringToIndex:parts.path.length-@"/chat/completions".length] stringByAppendingString:@"/models"];
    return parts.URL;
}
- (NSDictionary *)reasoningParametersForURL:(NSURL *)url thinking:(BOOL)thinking {
    NSString *effort=self.reasoningEffort ?: @"auto";
    if (!thinking || [effort isEqual:@"auto"]) return @{};
    if ([url.host.lowercaseString isEqual:@"api.deepseek.com"]) {
        if ([effort isEqual:@"medium"]) effort=@"high";
    } else if ([effort isEqual:@"max"]) effort=@"xhigh";
    return @{@"reasoning_effort":effort};
}
+ (NSArray<NSDictionary *> *)providerPresets {
    return @[@{@"name":@"DeepSeek",@"baseURL":@"https://api.deepseek.com/v1",@"model":@"deepseek-chat"},
        @{@"name":@"OpenAI / ChatGPT",@"baseURL":@"https://api.openai.com/v1",@"model":@"gpt-5.2"},
        @{@"name":@"Qwen / 通义千问",@"baseURL":@"https://dashscope.aliyuncs.com/compatible-mode/v1",@"model":@"qwen-plus"},
        @{@"name":@"Moonshot / Kimi",@"baseURL":@"https://api.moonshot.cn/v1",@"model":@"moonshot-v1-8k"},
        @{@"name":@"SiliconFlow / 硅基流动",@"baseURL":@"https://api.siliconflow.cn/v1",@"model":@"deepseek-ai/DeepSeek-V3.2"}];
}
+ (NSArray<NSString *> *)modelIDsFromData:(NSData *)data status:(NSInteger)status error:(NSError **)error {
    NSString *failure=nil; NSMutableSet *ids=[NSMutableSet set];
    if (status<200 || status>=300) failure=[NSString stringWithFormat:@"%@ (HTTP %ld)",DSAPILocalized(@"modelsFailed"),(long)status];
    else if (!data.length || data.length>2*1024*1024) failure=DSAPILocalized(@"modelsInvalid");
    else {
        id root=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        id entries=[root isKindOfClass:NSDictionary.class] ? root[@"data"] : nil;
        if (![entries isKindOfClass:NSArray.class]) failure=DSAPILocalized(@"modelsInvalid");
        else for (id item in entries) {
            id name=[item isKindOfClass:NSDictionary.class] ? item[@"id"] : nil;
            if ([name isKindOfClass:NSString.class] && [name length] && [name length]<=512) [ids addObject:name];
            if (ids.count>=500) break;
        }
        if (!failure && !ids.count) failure=DSAPILocalized(@"modelsEmpty");
    }
    if (failure) { if (error) *error=DSConfigError(failure); return nil; }
    return [ids.allObjects sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}
- (BOOL)save:(NSError **)error {
    if (![self completionURL:error]) return NO;
    if (![@[@"auto",@"low",@"medium",@"high",@"max"] containsObject:self.reasoningEffort ?: @"auto"] || !self.model.length || self.timeout < 10 || self.timeout > 3600 ||
        [self.apiKey rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location != NSNotFound) {
        if (error) *error = DSConfigError(DSAPILocalized(@"invalidFields"));
        return NO;
    }
    if (![self saveKeyData:[self.apiKey dataUsingEncoding:NSUTF8StringEncoding] error:error]) return NO;
    [NSUserDefaults.standardUserDefaults setObject:@{ @"baseURL":self.baseURL,
        @"model":self.model, @"reasoningModel":self.reasoningModel ?: @"",
        @"systemPrompt":self.systemPrompt ?: @"", @"timeout":@(self.timeout), @"requestUsage":@(self.requestUsage), @"enabled":@(self.enabled), @"showAPIInChat":@(self.showAPIInChat), @"automaticModels":@(self.automaticModels), @"reasoningEffort":self.reasoningEffort ?: @"auto" } forKey:DSConfigKey];
    return YES;
}
- (BOOL)saveKeyData:(NSData *)keyData error:(NSError **)error {
    NSDictionary *query = DSKeyQuery();
    OSStatus status;
    if (!keyData.length) {
        status = SecItemDelete((__bridge CFDictionaryRef)query);
        if (status == errSecItemNotFound) status = errSecSuccess;
    } else {
        NSDictionary *attributes = @{(__bridge id)kSecValueData:keyData,
            (__bridge id)kSecAttrAccessible:(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly};
        status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)attributes);
        if (status == errSecItemNotFound) {
            NSMutableDictionary *item = [query mutableCopy]; [item addEntriesFromDictionary:attributes];
            status = SecItemAdd((__bridge CFDictionaryRef)item, NULL);
        }
    }
    if (status != errSecSuccess) {
        if (error) *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status
            userInfo:@{NSLocalizedDescriptionKey:DSAPILocalized(@"keychainError")}];
        return NO;
    }
    return YES;
}
@end

BOOL DSAPIIsEnabled(void) {
    static BOOL enabled; static dispatch_once_t once;
    dispatch_once(&once, ^{ enabled=[[NSUserDefaults.standardUserDefaults dictionaryForKey:DSConfigKey][@"enabled"] boolValue]; });
    return enabled;
}

BOOL DSAPIHasPendingModeChange(void) {
    BOOL desired=[[NSUserDefaults.standardUserDefaults dictionaryForKey:DSConfigKey][@"enabled"] boolValue];
    return desired!=DSAPIIsEnabled();
}
