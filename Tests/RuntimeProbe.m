#import <Foundation/Foundation.h>
#import "DSAPIConfiguration.h"
#include <stdlib.h>
#import <objc/runtime.h>
extern void DSAPIRunRuntimeProbe(void);
static id (*originalFixtureLoad)(id,SEL);
static id DSLoadLocalFixture(id cls,SEL selector) {
    DSAPIConfiguration *configuration=originalFixtureLoad(cls,selector);
    NSDictionary *fixture=[NSUserDefaults.standardUserDefaults dictionaryForKey:@"DSAPIAdapter.localTestFixture"];
    if ([[NSURL URLWithString:fixture[@"baseURL"] ?: @""].host isEqual:@"127.0.0.1"]) {
        configuration.baseURL=fixture[@"baseURL"]; configuration.model=@"ci-mock-model"; configuration.apiKey=@"ci-dummy-key";
    }
    return configuration;
}
static void DSPrepareMockConfiguration(void) {
    const char *base = getenv("DSAPI_TEST_BASE_URL");
    NSString *baseURL=base ? [NSString stringWithUTF8String:base] : [NSUserDefaults.standardUserDefaults dictionaryForKey:@"DSAPIAdapter.localTestFixture"][@"baseURL"];
    if (!baseURL || ![[NSURL URLWithString:baseURL].host isEqual:@"127.0.0.1"]) return;
    Class configurationClass = NSClassFromString(@"DSAPIConfiguration");
    DSAPIConfiguration *configuration = [configurationClass loadConfiguration];
    if (!configuration) return;
    configuration.baseURL = baseURL;
    configuration.apiKey = @"ci-dummy-key";
    configuration.model = @"ci-mock-model";
    NSError *error = nil;
    BOOL saved = [configuration save:&error];
    [NSUserDefaults.standardUserDefaults setBool:saved forKey:@"DSAPIAdapter.testConfigurationSaved"];
    if (!saved) [NSUserDefaults.standardUserDefaults setObject:[NSString stringWithFormat:@"%@ (%@:%ld)", error.localizedDescription ?: @"unknown", error.domain, (long)error.code]
        forKey:@"DSAPIAdapter.testConfigurationError"];
    if (!saved && error.code==-34018) {
        // Ad-hoc converted simulator apps have no provisioned keychain group.
        // Test-only local dummy-key injection isolates rendering from signing.
        // The actual device adapter keeps its normal Keychain implementation.
        [NSUserDefaults.standardUserDefaults setObject:@{@"baseURL":baseURL} forKey:@"DSAPIAdapter.localTestFixture"];
        Method method=class_getClassMethod(configurationClass,@selector(loadConfiguration));
        originalFixtureLoad=(void *)method_setImplementation(method,(IMP)DSLoadLocalFixture);
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"DSAPIAdapter.testKeychainBypassed"];
    }
}
__attribute__((constructor)) static void DSInstallRuntimeProbe(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        DSPrepareMockConfiguration();
        DSAPIRunRuntimeProbe();
    });
    for (int delay=9;delay<=249;delay+=10)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delay*NSEC_PER_SEC), dispatch_get_main_queue(), ^{ DSAPIRunRuntimeProbe(); });
}
