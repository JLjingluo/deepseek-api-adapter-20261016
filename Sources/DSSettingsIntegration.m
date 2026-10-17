#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "DSAPISettingsViewController.h"
#import "DSUsageViewController.h"
#import "DSAPILocalization.h"

static void (*originalLoad)(id,SEL);
static void (*originalLayout)(id,SEL);
static void (*originalFooterLayout)(id,SEL);
static void (*originalSelect)(id,SEL,UITableView *,NSIndexPath *);
static void (*originalDisplay)(id,SEL,UITableView *,UITableViewCell *,NSIndexPath *);
static CGFloat (*originalHeight)(id,SEL,UITableView *,NSIndexPath *);
static char footerOverlayKey, cellOverlayKey, cellStateKey;
static IMP replaceMethod(Class cls,SEL selector,IMP replacement,const char *fallback) {
    if (!cls) return NULL;
    Method method=class_getInstanceMethod(cls,selector);
    IMP prior=method ? method_getImplementation(method) : NULL;
    const char *encoding=method ? method_getTypeEncoding(method) : fallback;
    if (!class_addMethod(cls,selector,replacement,encoding)) class_replaceMethod(cls,selector,replacement,encoding);
    return prior;
}
static BOOL isItem(NSString *item,NSString *name) {
    return [item isEqual:name] || [item hasSuffix:[@"." stringByAppendingString:name]];
}
static NSString *itemAt(UITableView *table,NSIndexPath *path) {
    id source=table.dataSource; SEL selector=NSSelectorFromString(@"itemIdentifierForIndexPath:");
    return [source respondsToSelector:selector] ? [((id (*)(id,SEL,id))objc_msgSend)(source,selector,path) description] ?: @"" : @"";
}
static BOOL removedItem(NSString *item) {
    for (NSString *name in @[@"accountManagement",@"logout",@"aboutService",@"contactUs",@"helpAndFeedback"])
        if (isItem(item,name)) return YES;
    return NO;
}
static void gatherLabels(UIView *root,NSMutableArray *labels) {
    if ([root isKindOfClass:UILabel.class]) [labels addObject:root];
    for (UIView *view in root.subviews) gatherLabels(view,labels);
}
static void presentAPI(id self,SEL selector) {
    [(UIViewController *)self presentViewController:DSAPICreateSettingsController() animated:YES completion:nil];
}
static void updateTitle(UIViewController *controller) {
    NSString *title=DSAPILocalized(@"settings");
    if (![controller.title isEqual:title]) controller.title=title;
    NSMutableArray *labels=[NSMutableArray array]; gatherLabels(controller.navigationItem.titleView,labels);
    for (UILabel *label in labels) if (label.text.length && ![label.text isEqual:title]) label.text=title;
    for (UIBarButtonItem *item in controller.navigationItem.rightBarButtonItems)
        if (item.action==NSSelectorFromString(@"dsapi_presentSettings")) item.accessibilityLabel=DSAPILocalized(@"api");
}
static void profileLoad(id self,SEL selector) {
    if (originalLoad) originalLoad(self,selector);
    UIViewController *controller=self;
    NSMutableArray *buttons=[controller.navigationItem.rightBarButtonItems mutableCopy] ?: [NSMutableArray array];
    UIBarButtonItem *api=[[UIBarButtonItem alloc] initWithTitle:@"API" style:UIBarButtonItemStylePlain target:self action:NSSelectorFromString(@"dsapi_presentSettings")];
    api.accessibilityIdentifier=@"DSAPI.APISettings"; [buttons addObject:api];
    controller.navigationItem.rightBarButtonItems=buttons;
    updateTitle(controller);
}
static void profileLayout(id self,SEL selector) {
    if (originalLayout) originalLayout(self,selector);
    UIViewController *controller=self;
    NSMutableArray *labels=[NSMutableArray array]; gatherLabels(controller.view,labels);
    NSMutableArray *texts=[NSMutableArray array]; for (UILabel *label in labels) if (label.text.length) [texts addObject:label.text];
    if (DSObserveNativeSettingsLanguage(texts)) {
        if ([controller isKindOfClass:UITableViewController.class]) [[(UITableViewController *)controller tableView] reloadData];
    }
    updateTitle(controller);
}
static void profileSelect(id self,SEL selector,UITableView *table,NSIndexPath *path) {
    NSString *item=itemAt(table,path);
    if (removedItem(item)) return;
    if (isItem(item,@"accountDataConfig")) {
        [table deselectRowAtIndexPath:path animated:YES];
        [(UIViewController *)self presentViewController:DSAPICreateUsageController() animated:YES completion:nil]; return;
    }
    if (isItem(item,@"aboutCheckUpdate")) {
        [table deselectRowAtIndexPath:path animated:YES];
        [UIApplication.sharedApplication openURL:[NSURL URLWithString:@"https://github.com/JLjingluo/deepseek-api-adapter-20261016/releases"] options:@{} completionHandler:nil]; return;
    }
    if (originalSelect) originalSelect(self,selector,table,path);
}
static CGFloat profileHeight(id self,SEL selector,UITableView *table,NSIndexPath *path) {
    if (removedItem(itemAt(table,path))) return 0.01;
    return originalHeight ? originalHeight(self,selector,table,path) : UITableViewAutomaticDimension;
}
static void profileDisplay(id self,SEL selector,UITableView *table,UITableViewCell *cell,NSIndexPath *path) {
    for (NSArray *entry in objc_getAssociatedObject(cell,&cellStateKey)) ((UIView *)entry[0]).hidden=[entry[1] boolValue];
    [objc_getAssociatedObject(cell,&cellOverlayKey) removeFromSuperview];
    objc_setAssociatedObject(cell,&cellStateKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(cell,&cellOverlayKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    cell.hidden=NO;
    if (originalDisplay) originalDisplay(self,selector,table,cell,path);
    NSString *item=itemAt(table,path); cell.hidden=removedItem(item);
    #if DSAPI_RUNTIME_DIAGNOSTICS
    NSMutableArray *observed=[[NSUserDefaults.standardUserDefaults arrayForKey:@"DSAPIAdapter.nativeSettingsItems"] mutableCopy] ?: [NSMutableArray array];
    if (item.length && ![observed containsObject:item]) { [observed addObject:item]; [NSUserDefaults.standardUserDefaults setObject:observed forKey:@"DSAPIAdapter.nativeSettingsItems"]; }
    #endif
    if ([cell.accessibilityIdentifier isEqual:@"DSAPI.Usage"]) cell.accessibilityIdentifier=nil;
    if (!isItem(item,@"accountDataConfig")) return;
    NSMutableArray *states=[NSMutableArray array];
    for (UIView *view in cell.contentView.subviews) { [states addObject:@[view,@(view.hidden)]]; view.hidden=YES; }
    objc_setAssociatedObject(cell,&cellStateKey,states,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UILabel *label=[UILabel new]; label.text=DSAPILocalized(@"usage"); label.textColor=UIColor.labelColor;
    label.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody]; label.adjustsFontForContentSizeCategory=YES;
    label.translatesAutoresizingMaskIntoConstraints=NO;
    [cell.contentView addSubview:label];
    objc_setAssociatedObject(cell,&cellOverlayKey,label,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [NSLayoutConstraint activateConstraints:@[[label.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
        [label.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor]]];
    cell.accessibilityIdentifier=@"DSAPI.Usage"; cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
}
static void footerLayout(id self,SEL selector) {
    if (originalFooterLayout) originalFooterLayout(self,selector);
    UIView *footer=self;
    UIView *overlay=objc_getAssociatedObject(footer,&footerOverlayKey);
    if (!overlay) {
        overlay=[UIView new]; overlay.userInteractionEnabled=NO; overlay.translatesAutoresizingMaskIntoConstraints=NO;
        UIImageView *icon=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"gearshape"]];
        icon.tintColor=UIColor.secondaryLabelColor; icon.contentMode=UIViewContentModeScaleAspectFit;
        UILabel *label=[UILabel new]; label.tag=7401; label.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        label.textColor=UIColor.labelColor; label.adjustsFontForContentSizeCategory=YES;
        UIImageView *arrow=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]]; arrow.tintColor=UIColor.tertiaryLabelColor;
        for (UIView *view in @[icon,label,arrow]) { view.translatesAutoresizingMaskIntoConstraints=NO; [overlay addSubview:view]; }
        [footer addSubview:overlay];
        [NSLayoutConstraint activateConstraints:@[[overlay.leadingAnchor constraintEqualToAnchor:footer.leadingAnchor],
            [overlay.trailingAnchor constraintEqualToAnchor:footer.trailingAnchor],[overlay.topAnchor constraintEqualToAnchor:footer.topAnchor],
            [overlay.bottomAnchor constraintEqualToAnchor:footer.bottomAnchor],
            [icon.leadingAnchor constraintEqualToAnchor:overlay.leadingAnchor constant:16],[icon.centerYAnchor constraintEqualToAnchor:overlay.centerYAnchor],
            [icon.widthAnchor constraintEqualToConstant:32],[icon.heightAnchor constraintEqualToConstant:32],
            [label.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:16],[label.centerYAnchor constraintEqualToAnchor:overlay.centerYAnchor],
            [arrow.trailingAnchor constraintEqualToAnchor:overlay.trailingAnchor constant:-24],[arrow.centerYAnchor constraintEqualToAnchor:overlay.centerYAnchor],
            [arrow.widthAnchor constraintEqualToConstant:10],[arrow.heightAnchor constraintEqualToConstant:16],
            [label.trailingAnchor constraintLessThanOrEqualToAnchor:arrow.leadingAnchor constant:-12]]];
        objc_setAssociatedObject(footer,&footerOverlayKey,overlay,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    for (UIView *view in footer.subviews) if (view!=overlay) view.hidden=YES;
    UILabel *label=[overlay viewWithTag:7401]; NSString *text=DSAPILocalized(@"settings");
    if (![label.text isEqual:text]) label.text=text;
    footer.accessibilityLabel=text; footer.accessibilityIdentifier=@"DSAPI.SettingsEntry";
}
void DSInstallSettingsIntegration(void) {
    Class profile=NSClassFromString(@"_TtC13DeepSeek_Chat21ProfileViewController");
    if (profile) {
        class_addMethod(profile,NSSelectorFromString(@"dsapi_presentSettings"),(IMP)presentAPI,"v@:");
        originalLoad=(void *)replaceMethod(profile,@selector(viewDidLoad),(IMP)profileLoad,"v@:");
        originalLayout=(void *)replaceMethod(profile,@selector(viewDidLayoutSubviews),(IMP)profileLayout,"v@:");
        originalSelect=(void *)replaceMethod(profile,@selector(tableView:didSelectRowAtIndexPath:),(IMP)profileSelect,"v@:@@");
        originalDisplay=(void *)replaceMethod(profile,@selector(tableView:willDisplayCell:forRowAtIndexPath:),(IMP)profileDisplay,"v@:@@@");
        originalHeight=(void *)replaceMethod(profile,@selector(tableView:heightForRowAtIndexPath:),(IMP)profileHeight,"d@:@@");
    }
    Class footer=NSClassFromString(@"_TtCC13DeepSeek_Chat25SessionListViewController10FooterView");
    originalFooterLayout=(void *)replaceMethod(footer,@selector(layoutSubviews),(IMP)footerLayout,"v@:");
}
