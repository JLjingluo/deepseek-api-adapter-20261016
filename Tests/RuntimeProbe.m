#import <Foundation/Foundation.h>
extern void DSAPIRunRuntimeProbe(void);
__attribute__((constructor)) static void DSInstallRuntimeProbe(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        DSAPIRunRuntimeProbe();
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 9*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        DSAPIRunRuntimeProbe();
    });
}
