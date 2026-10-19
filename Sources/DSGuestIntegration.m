#import "DSGuestIntegration.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "DSAPIConfiguration.h"
#import "DSAPILocalization.h"
#import "DSAPISettingsViewController.h"
extern BOOL DSAPIBeginGuest(void *controller);
extern BOOL DSAPILeaveGuest(void);
extern BOOL DSAPIPresentGuestConversation(void *controller);
extern BOOL DSAPIFinishGuestWelcome(void *controller);
extern void *DSAPIGuestFooterLabel(void *controller);
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
        [alert addAction:[UIAlertAction actionWithTitle:DSAPILocalized(@"signIn") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            dispatch_async(dispatch_get_main_queue(),^{
                if (!DSAPIIsLocalGuest()) return;
                UIViewController *presenter=top.presentingViewController;
                if (presenter) [presenter dismissViewControllerAnimated:YES completion:^{ DSAPILeaveGuest(); }];
                else DSAPILeaveGuest();
            });
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:DSAPILocalized(@"useAPI") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            dispatch_async(dispatch_get_main_queue(),^{ openAPI(nil,NULL); });
        }]]; [top presentViewController:alert animated:YES completion:nil];
    });
}
@implementation DSGuestGuardProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if ([NSURLProtocol propertyForKey:@"DSAPI.DirectAPI" inRequest:request]) return NO;
    NSString *authorization=[request valueForHTTPHeaderField:@"Authorization"] ?: @"";
    NSString *token=[authorization.lowercaseString hasPrefix:@"bearer "] ? [authorization substringFromIndex:7] : authorization;
    BOOL marked=[token isEqual:@"dsapi-local-guest"];
    if (marked) return YES;
    if (![request.URL.host.lowercaseString isEqual:@"chat.deepseek.com"]) return NO;
    NSString *path=request.URL.path;
    if (DSAPIIsLocalGuest()) {
        if ([token stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length && ![token isEqual:@"dsapi-local-guest"] && ![token.lowercaseString isEqual:@"bearer"]) {
            [NSUserDefaults.standardUserDefaults setBool:NO forKey:@"DSAPIAdapter.localGuestActive"]; return NO;
        }
        return [path hasPrefix:@"/api/"];
    }
    if (DSAPIIsEnabled() || DSAPIHasPendingModeChange()) return NO;
    return [path isEqual:@"/api/v0/guest/available"] || [path hasPrefix:@"/api/v0/guest/chat/"] || [path isEqual:@"/api/v0/users/create_guest_challenge"];
}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    NSString *authorization=[self.request valueForHTTPHeaderField:@"Authorization"] ?: @"";
    if (!DSAPIIsLocalGuest() && [authorization containsString:@"dsapi-local-guest"]) {
        [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]]; return;
    }
    NSString *path=self.request.URL.path;
    NSDictionary *guest=@{@"id":@"api-guest",@"token":@"dsapi-local-guest",@"email":@"",@"mobile_number":@"",@"area_code":@"",@"status":@0,@"id_profiles":@[],@"chat":@{@"is_muted":@0},@"has_legacy_chat_history":@NO,@"need_birthday":@NO,@"is_mainland":@NO};
    id payload=@{};
    if ([path hasSuffix:@"/guest/available"]) payload=@{@"value":@"true",@"available":@YES};
    else if (DSAPIIsLocalGuest() && [path hasSuffix:@"/users/current"]) { NSMutableDictionary *user=[guest mutableCopy]; user[@"user"]=guest; payload=user; }
    else if (DSAPIIsLocalGuest() && [path hasSuffix:@"/index/prepare"]) {
        id store=[NSClassFromString(@"DSLocalStore") performSelector:NSSelectorFromString(@"shared")];
        NSMutableArray *sessions=[NSMutableArray array];
        for (NSDictionary *session in [store valueForKey:@"sessions"]) if (!session[@"_ds_cloud_owner"]) [sessions addObject:session];
        payload=@{@"user":guest,@"settings":@{},@"chat_sessions":sessions};
    } else if (DSAPIIsLocalGuest() && [path hasSuffix:@"/client/settings"]) payload=@{@"version":@0,@"settings":@{}};
    else if (DSAPIIsLocalGuest() && [path hasSuffix:@"/users/auth_token/check_device"]) payload=@{@"rotate":NSNull.null};
    else if (DSAPIIsLocalGuest() && [path hasSuffix:@"/check_client_update"]) payload=@{@"need_update":@NO,@"force_update":@NO};
    else if (DSAPIIsLocalGuest() && [path hasSuffix:@"/ip_to_country_code"]) payload=@{@"country_code":NSLocale.currentLocale.countryCode ?: @"US"};
    else if (DSAPIIsLocalGuest() && ([path hasSuffix:@"/users/logout"] || [path hasSuffix:@"/users/auth_token/logout"])) {
        [NSUserDefaults.standardUserDefaults setBool:NO forKey:@"DSAPIAdapter.localGuestActive"];
    } else if (!DSAPIIsLocalGuest() || [path hasPrefix:@"/api/v0/users/"]) {
        requireSignIn(); [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:@"DSAPI.SignInRequired" code:401 userInfo:@{NSLocalizedDescriptionKey:DSAPILocalized(@"signInNote")}]]; return;
    }
    NSData *body=[NSJSONSerialization dataWithJSONObject:@{@"code":@0,@"msg":@"",@"data":@{@"biz_code":@0,@"biz_msg":@"",@"biz_data":payload}} options:0 error:NULL];
    NSHTTPURLResponse *response=[[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":@"application/json"}];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed]; [self.client URLProtocol:self didLoadData:body]; [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end
static char DSSkipButtonKey, DSSidebarAPIKey, DSBaseInsetKey;
static __weak UIViewController *DSSidebarController;
static void (*welcomeLoad)(id,SEL), (*loginLoad)(id,SEL), (*sidebarLayout)(id,SEL),(*footerLayout)(id,SEL),(*welcomeLayout)(id,SEL),(*loginLayout)(id,SEL);
static IMP replace(Class cls,SEL selector,IMP replacement) {
    Method method=class_getInstanceMethod(cls,selector); if (!method) return NULL;
    IMP old=method_getImplementation(method);
    if (!class_addMethod(cls,selector,replacement,method_getTypeEncoding(method))) class_replaceMethod(cls,selector,replacement,method_getTypeEncoding(method));
    return old;
}
static void finishWelcome(UIViewController *controller,NSUInteger attempt) {
    if (!controller.view.window || ![NSStringFromClass(controller.class) containsString:@"WelcomeViewController"]) return;
    if (DSAPIFinishGuestWelcome((__bridge void *)controller) || attempt>=80) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC/10),dispatch_get_main_queue(),^{ finishWelcome(controller,attempt+1); });
}
static void skipLogin(id self,SEL selector) {
    [NSUserDefaults.standardUserDefaults setObject:@"Skip action received" forKey:@"DSAPIAdapter.guestActivationStatus"];
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"DSAPIAdapter.skippedLogin"];
    if (DSAPIBeginGuest((__bridge void *)self)) {
        UIViewController *controller=self;
        dispatch_async(dispatch_get_main_queue(),^{
            if (DSAPIPresentGuestConversation((__bridge void *)controller)) return;
            UIViewController *modal=controller.navigationController.presentingViewController ? controller.navigationController : controller;
            if (modal.presentingViewController) {
                [modal dismissViewControllerAnimated:YES completion:nil];
            } else finishWelcome(controller,0);
        }); return;
    }
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
static void layoutSkip(UIViewController *controller) {
    UIButton *button=objc_getAssociatedObject(controller,&DSSkipButtonKey);
    if (button.superview==controller.view) [controller.view bringSubviewToFront:button];
}
static void welcomeDidLayout(id self,SEL selector) { if (welcomeLayout) welcomeLayout(self,selector); layoutSkip(self); }
static void loginDidLayout(id self,SEL selector) { if (loginLayout) loginLayout(self,selector); layoutSkip(self); }
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
// Mirror the original footer's geometry rather than giving the API row its own
// button configuration/insets. Both rows belong to the same sidebar container.
static UIImageView *firstImage(UIView *view) {
    if ([view isKindOfClass:UIImageView.class] && !view.hidden && view.bounds.size.width>=20) return (UIImageView *)view;
    for (UIView *child in view.subviews) { UIImageView *image=firstImage(child); if (image) return image; }
    return nil;
}
static UICollectionView *sidebarList(UIView *view) {
    if ([view isKindOfClass:UICollectionView.class] && [NSStringFromClass(view.class) hasSuffix:@"SessionListCollectionView"]) return (UICollectionView *)view;
    for (UIView *child in view.subviews) { UICollectionView *list=sidebarList(child); if (list) return list; } return nil;
}
static UIView *copyDecoration(UIView *source) {
    UIView *copy=[UIView new]; copy.frame=source.frame; copy.backgroundColor=source.backgroundColor;
    copy.alpha=source.alpha; copy.hidden=source.hidden; copy.layer.cornerRadius=source.layer.cornerRadius;
    copy.clipsToBounds=source.clipsToBounds; copy.userInteractionEnabled=NO;
    for (UIView *child in source.subviews) [copy addSubview:copyDecoration(child)];
    return copy;
}
static void layoutSidebar(id self,SEL selector) {
    if (sidebarLayout) sidebarLayout(self,selector);
    UIViewController *controller=self; DSSidebarController=controller;
    UIView *footer=find(controller.view,@"FooterView"); if (!footer || !footer.superview) return;
    UILabel *label=firstLabel(footer);
    if (DSAPIIsLocalGuest() && label && ![label.text isEqual:DSAPILocalized(@"guest")]) label.text=DSAPILocalized(@"guest");
    BOOL enabled=[DSAPIConfiguration loadConfigurationWithoutAPIKey].showAPIInChat;
    UIButton *button=objc_getAssociatedObject(self,&DSSidebarAPIKey);
    if (!button && enabled) {
        button=[UIButton buttonWithType:UIButtonTypeCustom]; button.accessibilityIdentifier=@"DSAPI.ConversationAPI";
        button.isAccessibilityElement=YES;
        [button addTarget:self action:NSSelectorFromString(@"dsapi_openAPI") forControlEvents:UIControlEventTouchUpInside];
        UIImageView *icon=[UIImageView new]; icon.tag=8101; icon.contentMode=UIViewContentModeCenter; icon.clipsToBounds=YES;
        UILabel *title=[UILabel new]; title.tag=8102;
        UIView *accessory=[UIView new]; accessory.tag=8103;
        for (UIView *child in @[icon,title,accessory]) { child.userInteractionEnabled=NO; child.isAccessibilityElement=NO; [button addSubview:child]; }
        objc_setAssociatedObject(self,&DSSidebarAPIKey,button,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    button.hidden=!enabled;
    // Use the native footer's parent so its clipping, sidebar transition and
    // safe-area treatment also apply to the added row.
    if (!enabled) [button removeFromSuperview];
    else if (button && button.superview!=footer.superview) [footer.superview insertSubview:button belowSubview:footer];
    UICollectionView *list=sidebarList(controller.view);
    if (list && !objc_getAssociatedObject(list,&DSBaseInsetKey)) objc_setAssociatedObject(list,&DSBaseInsetKey,[NSValue valueWithUIEdgeInsets:list.contentInset],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    CGFloat height=footer.bounds.size.height;
    if (height<=0) return;
    if (list) {
        UIEdgeInsets inset=[objc_getAssociatedObject(list,&DSBaseInsetKey) UIEdgeInsetsValue]; inset.bottom+=enabled ? height : 0;
        if (!UIEdgeInsetsEqualToEdgeInsets(list.contentInset,inset)) list.contentInset=inset;
        list.verticalScrollIndicatorInsets=inset;
    }
    if (!enabled) return;
    button.frame=CGRectOffset(footer.frame,0,-height);
    button.backgroundColor=footer.backgroundColor ?: controller.view.backgroundColor ?: UIColor.systemBackgroundColor;
    button.accessibilityLabel=DSAPILocalized(@"api");
    UILabel *title=[button viewWithTag:8102];
    title.text=DSAPILocalized(@"api"); title.font=label.font ?: [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    title.textColor=label.textColor ?: UIColor.labelColor; title.adjustsFontSizeToFitWidth=NO; title.lineBreakMode=NSLineBreakByTruncatingTail;
    CGRect titleRect=label ? [label convertRect:label.bounds toView:footer] : CGRectMake(64,0,MAX(0,footer.bounds.size.width-104),height);
    title.frame=titleRect;
    UIImageView *originalIcon=firstImage(footer), *icon=[button viewWithTag:8101];
    CGRect iconRect=originalIcon ? [originalIcon convertRect:originalIcon.bounds toView:footer] : CGRectMake(16,(height-32)/2,32,32);
    icon.frame=iconRect; icon.layer.cornerRadius=MIN(iconRect.size.width,iconRect.size.height)/2;
    icon.backgroundColor=UIColor.tertiarySystemFillColor; icon.tintColor=UIColor.secondaryLabelColor;
    icon.image=[UIImage systemImageNamed:@"network" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:MIN(iconRect.size.width,iconRect.size.height)*0.58 weight:UIImageSymbolWeightRegular]];
    // Preserve the trailing action's location and weight, without copying the
    // account avatar or any account-specific text into the API shortcut.
    UIView *accessory=[button viewWithTag:8103];
    for (UIView *child in accessory.subviews) [child removeFromSuperview];
    UIView *nativeAccessory=nil;
    for (UIView *child in footer.subviews) if ([NSStringFromClass(child.class) hasSuffix:@"AutoStackLayout"]) { nativeAccessory=child; break; }
    if (nativeAccessory) {
        accessory.frame=[nativeAccessory convertRect:nativeAccessory.bounds toView:footer];
        UIView *decoration=copyDecoration(nativeAccessory); decoration.frame=accessory.bounds; [accessory addSubview:decoration];
    }
    accessory.hidden=!nativeAccessory;
    // Keep the native label width and its truncation behaviour as well.
    title.frame=titleRect;
}
static void layoutFooter(id self,SEL selector) {
    if (footerLayout) footerLayout(self,selector);
    if (DSAPIIsLocalGuest()) {
        UILabel *label=(__bridge UILabel *)DSAPIGuestFooterLabel((__bridge void *)self);
        if (![label.text isEqual:DSAPILocalized(@"guest")]) label.text=DSAPILocalized(@"guest");
    }
}
void DSInstallGuestIntegration(void) {
    [NSNotificationCenter.defaultCenter addObserverForName:@"DSAPIAdapter.SettingsChanged" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        UIViewController *sidebar=DSSidebarController;
        if (sidebar.isViewLoaded) { [sidebar.view setNeedsLayout]; [sidebar.view layoutIfNeeded]; }
    }];
    [NSNotificationCenter.defaultCenter addObserverForName:@"DSAPIAdapter.GuestSignInRequired" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { requireSignIn(); }];
    Class footerClass=NSClassFromString(@"_TtCC13DeepSeek_Chat25SessionListViewController10FooterView");
    footerLayout=(void *)replace(footerClass,@selector(layoutSubviews),(IMP)layoutFooter);
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
    welcomeLayout=(void *)replace(welcomeClass,@selector(viewDidLayoutSubviews),(IMP)welcomeDidLayout);
    loginLayout=(void *)replace(loginClass,@selector(viewDidLayoutSubviews),(IMP)loginDidLayout);
    Class sidebar=NSClassFromString(@"_TtC13DeepSeek_Chat25SessionListViewController");
    class_addMethod(sidebar,NSSelectorFromString(@"dsapi_openAPI"),(IMP)openAPI,"v@:");
    sidebarLayout=(void *)replace(sidebar,@selector(viewDidLayoutSubviews),(IMP)layoutSidebar);
}
