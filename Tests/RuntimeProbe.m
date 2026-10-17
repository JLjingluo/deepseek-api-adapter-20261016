#import <Foundation/Foundation.h>
#import "DSAPIConfiguration.h"
#include <stdlib.h>
extern void DSAPIRunRuntimeProbe(void);
static void DSPrepareMockConfiguration(void) {
    const char *base = getenv("DSAPI_TEST_BASE_URL");
    if (!base) return;
    Class configurationClass = NSClassFromString(@"DSAPIConfiguration");
    DSAPIConfiguration *configuration = [configurationClass loadConfiguration];
    if (!configuration) return;
    configuration.baseURL = [NSString stringWithUTF8String:base];
    configuration.apiKey = @"ci-dummy-key";
    configuration.model = @"ci-mock-model";
    NSError *error = nil;
    BOOL saved = [configuration save:&error];
    [NSUserDefaults.standardUserDefaults setBool:saved forKey:@"DSAPIAdapter.testConfigurationSaved"];
    if (!saved) [NSUserDefaults.standardUserDefaults setObject:error.localizedDescription ?: @"unknown"
        forKey:@"DSAPIAdapter.testConfigurationError"];
}
__attribute__((constructor)) static void DSInstallRuntimeProbe(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        DSPrepareMockConfiguration();
        DSAPIRunRuntimeProbe();
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 9*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        DSAPIRunRuntimeProbe();
    });
}
