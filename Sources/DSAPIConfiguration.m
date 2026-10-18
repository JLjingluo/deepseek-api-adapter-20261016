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
- (instancetype)init { if ((self=[super init])) _requestUsage=YES; return self; }
+ (instancetype)loadConfigurationWithoutAPIKey {
    DSAPIConfiguration *config = [self new];
    NSDictionary *values = [NSUserDefaults.standardUserDefaults dictionaryForKey:DSConfigKey];
    config.baseURL = [values[@"baseURL"] isKindOfClass:NSString.class] ? values[@"baseURL"] : @"https://api.deepseek.com/v1";
    config.model = [values[@"model"] isKindOfClass:NSString.class] ? values[@"model"] : @"deepseek-chat";
    config.reasoningModel = [values[@"reasoningModel"] isKindOfClass:NSString.class] ? values[@"reasoningModel"] : @"";
    config.systemPrompt = [values[@"systemPrompt"] isKindOfClass:NSString.class] ? values[@"systemPrompt"] : @"";
    config.timeout = [values[@"timeout"] isKindOfClass:NSNumber.class] ? [values[@"timeout"] doubleValue] : 180;
    config.enabled = [values[@"enabled"] boolValue];
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
- (BOOL)save:(NSError **)error {
    if (![self completionURL:error]) return NO;
    if (!self.model.length || self.timeout < 10 || self.timeout > 3600 ||
        [self.apiKey rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location != NSNotFound) {
        if (error) *error = DSConfigError(DSAPILocalized(@"invalidFields"));
        return NO;
    }
    if (![self saveKeyData:[self.apiKey dataUsingEncoding:NSUTF8StringEncoding] error:error]) return NO;
    [NSUserDefaults.standardUserDefaults setObject:@{ @"baseURL":self.baseURL,
        @"model":self.model, @"reasoningModel":self.reasoningModel ?: @"",
        @"systemPrompt":self.systemPrompt ?: @"", @"timeout":@(self.timeout), @"requestUsage":@(self.requestUsage), @"enabled":@(self.enabled) } forKey:DSConfigKey];
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
