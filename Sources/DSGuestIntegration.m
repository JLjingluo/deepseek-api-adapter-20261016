#import "DSGuestIntegration.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "DSAPIConfiguration.h"
#import "DSAPILocalization.h"
#import "DSAPISettingsViewController.h"
extern BOOL DSAPIBeginGuest(void *controller);
static UIViewController *topController(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) if ([scene isKindOfClass:UIWindowScene.class])
        for (UIWindow *window in ((UIWindowScene *)scene).windows) if (window.isKeyWindow) {
            UIViewController *top=window.rootViewController; while (top.presentedViewController) top=top.presentedViewController; return top;
        }
    return nil;
}
static void openAPI(id self,SEL selector) {
    UIViewController *top=topController(); if (!top) return;
    [top.view endEditing:YES];
    [top presentViewController:DSAPICreateSettingsController([UIFont preferredFontForTextStyle:UIFontTextStyleBody]) animated:YES completion:nil];
}
static void requireSignIn(void) {
    dispatch_async(dispatch_get_main_queue(),^{
        UIViewController *top=topController(); if (!top || [top isKindOfClass:UIAlertController.class]) return;
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:DSAPILocalized(@"signInRequired") message:DSAPILocalized(@"signInNote") preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:DSOriginalLocalized(@"cancel") style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:DSAPILocalized(@"useAPI") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            dispatch_async(dispatch_get_main_queue(),^{ openAPI(nil,NULL); });
        }]]; [top presentViewController:alert animated:YES completion:nil];
    });
}
@implementation DSGuestGuardProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if (DSAPIIsEnabled() || DSAPIHasPendingModeChange() || [NSURLProtocol propertyForKey:@"DSAPI.DirectAPI" inRequest:request]) return NO;
    if (![request.URL.host.lowercaseString isEqual:@"chat.deepseek.com"]) return NO;
    NSString *path=request.URL.path;
    return [path isEqual:@"/api/v0/guest/available"] || [path hasPrefix:@"/api/v0/guest/chat/"] || [path isEqual:@"/api/v0/users/create_guest_challenge"];
}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    if ([self.request.URL.path hasSuffix:@"/guest/available"]) {
        NSData *body=[NSJSONSerialization dataWithJSONObject:@{@"code":@0,@"msg":@"",@"data":@{@"biz_code":@0,@"biz_msg":@"",@"biz_data":@{@"value":@"true",@"available":@YES}}} options:0 error:NULL];
        NSHTTPURLResponse *response=[[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":@"application/json"}];
        [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        [self.client URLProtocol:self didLoadData:body]; [self.client URLProtocolDidFinishLoading:self]; return;
    }
    requireSignIn();
    [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:@"DSAPI.SignInRequired" code:401 userInfo:@{NSLocalizedDescriptionKey:DSAPILocalized(@"signInNote")}]];
}
- (void)stopLoading {}
@end
static char DSSkipButtonKey, DSSidebarAPIKey, DSBaseInsetKey;
static void (*welcomeLoad)(id,SEL), (*loginLoad)(id,SEL), (*sidebarLayout)(id,SEL);
static IMP replace(Class cls,SEL selector,IMP replacement) {
    Method method=class_getInstanceMethod(cls,selector); if (!method) return NULL;
    IMP old=method_getImplementation(method);
    if (!class_addMethod(cls,selector,replacement,method_getTypeEncoding(method))) class_replaceMethod(cls,selector,replacement,method_getTypeEncoding(method));
    return old;
}
static void skipLogin(id self,SEL selector) {
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"DSAPIAdapter.skippedLogin"];
    if (DSAPIBeginGuest((__bridge void *)self)) return;
    UIViewController *controller=self;
    if (controller.navigationController.presentingViewController) [controller.navigationController dismissViewControllerAnimated:YES completion:nil];
    else if (controller.presentingViewController) [controller dismissViewControllerAnimated:YES completion:nil];
    else if (controller.navigationController.viewControllers.count>1) [controller.navigationController popViewControllerAnimated:YES];
    else openAPI(nil,NULL);
}
static void installSkip(UIViewController *controller) {
    if (objc_getAssociatedObject(controller,&DSSkipButtonKey)) return;
    UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *style=UIButtonConfiguration.plainButtonConfiguration; style.title=DSAPILocalized(@"skipLogin"); button.configuration=style;
    button.accessibilityIdentifier=@"DSAPI.SkipLogin"; [button addTarget:controller action:NSSelectorFromString(@"dsapi_skipLogin") forControlEvents:UIControlEventTouchUpInside];
    objc_setAssociatedObject(controller,&DSSkipButtonKey,button,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (controller.navigationController && ![NSStringFromClass(controller.class) containsString:@"WelcomeViewController"]) {
        UIBarButtonItem *item=[[UIBarButtonItem alloc] initWithCustomView:button];
        NSMutableArray *items=[controller.navigationItem.rightBarButtonItems mutableCopy] ?: [NSMutableArray array]; [items addObject:item]; controller.navigationItem.rightBarButtonItems=items;
    } else {
        button.translatesAutoresizingMaskIntoConstraints=NO; [controller.view addSubview:button];
        [NSLayoutConstraint activateConstraints:@[[button.trailingAnchor constraintEqualToAnchor:controller.view.safeAreaLayoutGuide.trailingAnchor constant:-16],
            [button.topAnchor constraintEqualToAnchor:controller.view.safeAreaLayoutGuide.topAnchor constant:8], [button.heightAnchor constraintGreaterThanOrEqualToConstant:44]]];
    }
}
static void welcome(id self,SEL selector) { if (welcomeLoad) welcomeLoad(self,selector); installSkip(self); }
static void login(id self,SEL selector) { if (loginLoad) loginLoad(self,selector); installSkip(self); }
static UIView *find(UIView *view,NSString *suffix) {
    if ([NSStringFromClass(view.class) hasSuffix:suffix]) return view;
    for (UIView *child in view.subviews) { UIView *match=find(child,suffix); if (match) return match; } return nil;
}
static UILabel *firstLabel(UIView *view) {
    if ([view isKindOfClass:UILabel.class] && ((UILabel *)view).text.length) return (UILabel *)view;
    for (UIView *child in view.subviews) { UILabel *label=firstLabel(child); if (label) return label; } return nil;
}
static void layoutSidebar(id self,SEL selector) {
    if (sidebarLayout) sidebarLayout(self,selector);
    UIViewController *controller=self;
    UIView *footer=find(controller.view,@"FooterView"); if (!footer || !footer.superview) return;
    BOOL enabled=[DSAPIConfiguration loadConfigurationWithoutAPIKey].showAPIInChat;
    UIButton *button=objc_getAssociatedObject(self,&DSSidebarAPIKey);
    if (!button && enabled) {
        button=[UIButton buttonWithType:UIButtonTypeSystem]; button.accessibilityIdentifier=@"DSAPI.ConversationAPI";
        [button addTarget:self action:NSSelectorFromString(@"dsapi_openAPI") forControlEvents:UIControlEventTouchUpInside];
        [controller.view addSubview:button]; objc_setAssociatedObject(self,&DSSidebarAPIKey,button,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    button.hidden=!enabled;
    UICollectionView *list=(UICollectionView *)find(controller.view,@"UICollectionView");
    if (list && !objc_getAssociatedObject(list,&DSBaseInsetKey)) objc_setAssociatedObject(list,&DSBaseInsetKey,[NSValue valueWithUIEdgeInsets:list.contentInset],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    CGFloat height=MAX(48,MIN(60,footer.bounds.size.height));
    if (list) {
        UIEdgeInsets inset=[objc_getAssociatedObject(list,&DSBaseInsetKey) UIEdgeInsetsValue]; inset.bottom+=enabled ? height : 0;
        if (!UIEdgeInsetsEqualToEdgeInsets(list.contentInset,inset)) list.contentInset=inset;
    }
    if (!enabled) return;
    CGRect rect=[footer.superview convertRect:footer.frame toView:controller.view];
    button.frame=CGRectMake(rect.origin.x,rect.origin.y-height,rect.size.width,height);
    UILabel *label=firstLabel(footer); UIFont *font=label.font ?: [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    UIButtonConfiguration *style=UIButtonConfiguration.plainButtonConfiguration; style.title=DSAPILocalized(@"api");
    style.image=[UIImage systemImageNamed:@"network"]; style.imagePadding=12; style.contentInsets=NSDirectionalEdgeInsetsMake(10,16,10,16);
    style.baseForegroundColor=label.textColor ?: UIColor.labelColor;
    style.titleTextAttributesTransformer=^NSDictionary *(NSDictionary *attributes) { NSMutableDictionary *copy=[attributes mutableCopy]; copy[NSFontAttributeName]=font; return copy; };
    button.configuration=style; button.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;
    button.backgroundColor=footer.backgroundColor ?: controller.view.backgroundColor ?: UIColor.systemBackgroundColor;
    [controller.view bringSubviewToFront:button];
}
void DSInstallGuestIntegration(void) {
    [NSNotificationCenter.defaultCenter addObserverForName:@"DSAPIAdapter.CloudHistoryFailed" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        static BOOL shown=NO; if (shown) return;
        UIViewController *top=topController(); if (!top || [top isKindOfClass:UIAlertController.class]) return; shown=YES;
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:DSAPILocalized(@"historySync") message:note.userInfo[NSLocalizedDescriptionKey] preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:DSAPILocalized(@"ok") style:UIAlertActionStyleDefault handler:nil]]; [top presentViewController:alert animated:YES completion:nil];
    }];
    Class welcomeClass=NSClassFromString(@"_TtC13DeepSeek_Chat21WelcomeViewController");
    Class loginClass=NSClassFromString(@"_TtC13DeepSeek_Chat19LoginViewController");
    for (Class cls in @[welcomeClass ?: NSObject.class,loginClass ?: NSObject.class]) if (cls!=NSObject.class) class_addMethod(cls,NSSelectorFromString(@"dsapi_skipLogin"),(IMP)skipLogin,"v@:");
    welcomeLoad=(void *)replace(welcomeClass,@selector(viewDidLoad),(IMP)welcome);
    loginLoad=(void *)replace(loginClass,@selector(viewDidLoad),(IMP)login);
    Class sidebar=NSClassFromString(@"_TtC13DeepSeek_Chat25SessionListViewController");
    class_addMethod(sidebar,NSSelectorFromString(@"dsapi_openAPI"),(IMP)openAPI,"v@:");
    sidebarLayout=(void *)replace(sidebar,@selector(viewDidLayoutSubviews),(IMP)layoutSidebar);
}
