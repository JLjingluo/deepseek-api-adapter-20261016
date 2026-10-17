#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "DSCompatibilityProtocol.h"
#import "DSAPISettingsViewController.h"

extern void *DSAPICopyLocalUserData(void);
static NSData *(*DSOriginalGetData)(id,SEL,NSString *);
static id (*DSOriginalSession)(id,SEL,NSURLSessionConfiguration *,id,NSOperationQueue *);
static void (*DSOriginalProfileLoad)(id,SEL);
static void (*DSOriginalProfileSelect)(id,SEL,UITableView *,NSIndexPath *);
static void (*DSOriginalProfileDisplay)(id,SEL,UITableView *,UITableViewCell *,NSIndexPath *);
static CGFloat (*DSOriginalProfileHeight)(id,SEL,UITableView *,NSIndexPath *);
static long long (*DSOriginalLocalHash)(id,SEL,NSString *,long long,NSString *);
static char DSCellHiddenStatesKey, DSCellAPILabelKey;

static NSData *DSLocalUser(id self, SEL selector, NSString *key) {
    if ([key isEqualToString:@"currentUser"]) {
        static NSData *canonical; static dispatch_once_t once;
        dispatch_once(&once, ^{
            void *result = DSAPICopyLocalUserData();
            if (result) canonical = CFBridgingRelease((CFTypeRef)result);
        });
        if (canonical) return canonical;
    }
    return DSOriginalGetData(self,selector,key);
}
static id DSCreateSession(id self, SEL selector, NSURLSessionConfiguration *configuration, id delegate, NSOperationQueue *queue) {
    NSURLSessionConfiguration *copy = [configuration copy];
    NSMutableArray *classes = [NSMutableArray arrayWithObject:DSCompatibilityProtocol.class];
    for (Class cls in copy.protocolClasses ?: @[]) if (cls != DSCompatibilityProtocol.class) [classes addObject:cls];
    copy.protocolClasses = classes;
    return DSOriginalSession(self,selector,copy,delegate,queue);
}
static NSString *DSItem(UITableView *table, NSIndexPath *path) {
    id source = table.dataSource;
    SEL selector = NSSelectorFromString(@"itemIdentifierForIndexPath:");
    if (![source respondsToSelector:selector]) return @"";
    id item = ((id (*)(id,SEL,id))objc_msgSend)(source,selector,path);
    return [item description] ?: @"";
}
static BOOL DSIs(NSString *value, NSString *name) {
    return [value isEqualToString:name] || [value hasSuffix:[@"." stringByAppendingString:name]];
}
static BOOL DSRemovedSetting(NSString *item) {
    return DSIs(item,@"logout") || DSIs(item,@"accountDataConfig");
}
static void DSShowSettings(id self, SEL selector) {
    UIViewController *controller = self;
    [controller presentViewController:DSAPICreateSettingsController() animated:YES completion:nil];
}
static void DSProfileLoad(id self, SEL selector) {
    if (DSOriginalProfileLoad) DSOriginalProfileLoad(self,selector);
    UIViewController *controller = self;
    NSMutableArray *items = [controller.navigationItem.rightBarButtonItems mutableCopy] ?: [NSMutableArray array];
    [items addObject:[[UIBarButtonItem alloc] initWithTitle:@"API" style:UIBarButtonItemStylePlain target:self
        action:NSSelectorFromString(@"dsapi_presentSettings")]];
    controller.navigationItem.rightBarButtonItems = items;
}
static void DSProfileSelect(id self, SEL selector, UITableView *table, NSIndexPath *path) {
    NSString *item = DSItem(table,path);
    if (DSIs(item,@"accountManagement")) {
        [table deselectRowAtIndexPath:path animated:YES]; DSShowSettings(self,NULL); return;
    }
    if (DSRemovedSetting(item)) return;
    if (DSOriginalProfileSelect) DSOriginalProfileSelect(self,selector,table,path);
}
static CGFloat DSProfileHeight(id self, SEL selector, UITableView *table, NSIndexPath *path) {
    if (DSRemovedSetting(DSItem(table,path))) return 0.01;
    return DSOriginalProfileHeight ? DSOriginalProfileHeight(self,selector,table,path) : UITableViewAutomaticDimension;
}
static void DSProfileDisplay(id self, SEL selector, UITableView *table, UITableViewCell *cell, NSIndexPath *path) {
    NSArray *previous = objc_getAssociatedObject(cell,&DSCellHiddenStatesKey);
    for (NSArray *entry in previous) ((UIView *)entry[0]).hidden = [entry[1] boolValue];
    [objc_getAssociatedObject(cell,&DSCellAPILabelKey) removeFromSuperview];
    objc_setAssociatedObject(cell,&DSCellHiddenStatesKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(cell,&DSCellAPILabelKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    cell.hidden = NO;
    if (DSOriginalProfileDisplay) DSOriginalProfileDisplay(self,selector,table,cell,path);
    NSString *item = DSItem(table,path);
    cell.hidden = DSRemovedSetting(item);
    if (!DSIs(item,@"accountManagement")) return;
    NSMutableArray *hiddenStates = [NSMutableArray array];
    for (UIView *view in cell.contentView.subviews) { [hiddenStates addObject:@[view,@(view.hidden)]]; view.hidden = YES; }
    objc_setAssociatedObject(cell,&DSCellHiddenStatesKey,hiddenStates,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UILabel *label = [UILabel new]; label.text = @"API 设置";
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    label.textColor = UIColor.labelColor; label.adjustsFontForContentSizeCategory = YES;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:label];
    objc_setAssociatedObject(cell,&DSCellAPILabelKey,label,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
        [label.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor]]];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
}
static long long DSLocalHash(id self, SEL selector, NSString *prefix, long long limit, NSString *target) {
    // This applies only to the handshake generated by our local URLProtocol.
    if ([prefix hasPrefix:@"local-api-handshake"]) return 0;
    return DSOriginalLocalHash(self,selector,prefix,limit,target);
}
static IMP DSReplace(Class cls, SEL selector, IMP replacement, const char *fallbackEncoding) {
    if (!cls) return NULL;
    Method method = class_getInstanceMethod(cls,selector);
    IMP previous = method ? method_getImplementation(method) : NULL;
    const char *encoding = method ? method_getTypeEncoding(method) : fallbackEncoding;
    if (!class_addMethod(cls,selector,replacement,encoding)) class_replaceMethod(cls,selector,replacement,encoding);
    return previous;
}
__attribute__((constructor)) static void DSInstall(void) {
    NSString *executable = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleExecutable"];
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    if (![executable isEqualToString:@"DeepSeek Chat"] || ![version isEqualToString:@"2.6.2"]) return;
    Class mmkv = NSClassFromString(@"MMKV");
    if (class_getInstanceMethod(mmkv,NSSelectorFromString(@"getDataForKey:")))
        DSOriginalGetData = (void *)DSReplace(mmkv,NSSelectorFromString(@"getDataForKey:"),(IMP)DSLocalUser,"@@:@");
    Class meta = object_getClass(NSURLSession.class);
    DSOriginalSession = (void *)DSReplace(meta,@selector(sessionWithConfiguration:delegate:delegateQueue:),(IMP)DSCreateSession,"@@:@@@");
    [NSURLProtocol registerClass:DSCompatibilityProtocol.class];
    Class profile = NSClassFromString(@"_TtC13DeepSeek_Chat21ProfileViewController");
    if (profile) {
        class_addMethod(profile,NSSelectorFromString(@"dsapi_presentSettings"),(IMP)DSShowSettings,"v@:");
        DSOriginalProfileLoad = (void *)DSReplace(profile,@selector(viewDidLoad),(IMP)DSProfileLoad,"v@:");
        DSOriginalProfileSelect = (void *)DSReplace(profile,@selector(tableView:didSelectRowAtIndexPath:),(IMP)DSProfileSelect,"v@:@@");
        DSOriginalProfileDisplay = (void *)DSReplace(profile,@selector(tableView:willDisplayCell:forRowAtIndexPath:),(IMP)DSProfileDisplay,"v@:@@@");
        DSOriginalProfileHeight = (void *)DSReplace(profile,@selector(tableView:heightForRowAtIndexPath:),(IMP)DSProfileHeight,"d@:@@");
    }
    Class pow = NSClassFromString(@"PowCalculator");
    SEL hash = NSSelectorFromString(@"solveHash256:diff:target:");
    if (pow && class_getClassMethod(pow,hash))
        DSOriginalLocalHash = (void *)DSReplace(object_getClass(pow),hash,(IMP)DSLocalHash,"q@:@q@");
}
