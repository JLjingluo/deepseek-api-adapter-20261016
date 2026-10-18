#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import "DSAPIConfiguration.h"

// The supplied 2.6.2 binary has its unused GuestManager methods stripped.
// Enter an explicitly LOCAL profile through its existing account-context
// transition, with a non-credential local marker. This marker never authenticates to
// the official backend; its requests terminate in the local protocol.
// These offsets are specific to the verified input, whose TEXT is preserved.
static uintptr_t nativeBase(void) {
    if (![[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleExecutable"] isEqual:@"DeepSeek Chat"] ||
        ![[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] isEqual:@"2.6.2"]) return 0;
    return (uintptr_t)_dyld_get_image_header(0);
}
void *DSAPINativeAccountManager(void) {
    uintptr_t base=nativeBase(); if (!base) return NULL;
    void *manager=*(void **)(base+0x15cde48);
    if (!manager) {
        dispatch_once_f((dispatch_once_t *)(base+0x14f0400),NULL,(dispatch_function_t)(base+0x76fb34));
        manager=*(void **)(base+0x15cde48);
    }
    if (!manager || object_getClass((__bridge id)manager)!=NSClassFromString(@"_TtC13DeepSeek_Chat14AccountManager")) return NULL;
    return manager;
}
typedef void * __attribute__((swiftcall)) (*DSSetUser)(const void *user,void *context __attribute__((swift_context)));
typedef BOOL __attribute__((swiftcall)) (*DSLeaveUser)(void *account,void *context __attribute__((swift_context)));
BOOL DSAPIActivateGuestUser(const void *user) {
    if (!NSThread.isMainThread || !user) return NO;
    uintptr_t base=nativeBase(); void *manager=DSAPINativeAccountManager();
    if (!manager || *(uint32_t *)(base+0x770a0c)!=0xa9ba6ffc) { [NSUserDefaults.standardUserDefaults setObject:@"Native manager unavailable or unsupported binary" forKey:@"DSAPIAdapter.guestActivationStatus"]; return NO; }
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"DSAPIAdapter.localGuestActive"];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"DSAPIAdapter.currentOfficialUserID"];
    void *created=((DSSetUser)(base+0x770a0c))(user,manager);
    if (created) { __unused id context=CFBridgingRelease(created); }
    [NSUserDefaults.standardUserDefaults setObject:@"Native local profile transition invoked" forKey:@"DSAPIAdapter.guestActivationStatus"];
    return YES;
}
BOOL DSAPILeaveGuestContext(void *context) {
    if (!NSThread.isMainThread || !context) return NO;
    uintptr_t base=nativeBase(); void *manager=DSAPINativeAccountManager();
    if (!manager || *(uint32_t *)(base+0x770d60)!=0xa9bb67fa) return NO;
    [NSUserDefaults.standardUserDefaults setBool:NO forKey:@"DSAPIAdapter.localGuestActive"];
    [NSUserDefaults.standardUserDefaults setBool:NO forKey:@"DSAPIAdapter.skippedLogin"];
    BOOL left=((DSLeaveUser)(base+0x770d60))(context,manager);
    if (!left) [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"DSAPIAdapter.localGuestActive"];
    return left;
}

// Normal successful sign-in creates SessionViewController and replaces the
// login navigation stack. Its no-argument initializer reads the current context.
typedef void * __attribute__((swiftcall)) (*DSSessionInit)(void *context __attribute__((swift_context)));
void *DSAPICreateGuestSession(void) {
    uintptr_t base=nativeBase();
    Class cls=NSClassFromString(@"_TtC13DeepSeek_Chat21SessionViewController");
    if (!NSThread.isMainThread || !base || !cls || *(uint32_t *)(base+0x744b00)!=0xa9ba6ffc) return NULL;
    id allocated=[cls alloc];
    void *owned=(__bridge_retained void *)allocated;
    return ((DSSessionInit)(base+0x744b00))(owned);
}
