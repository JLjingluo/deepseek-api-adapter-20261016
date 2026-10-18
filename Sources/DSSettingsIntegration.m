#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "DSAPISettingsViewController.h"
#import "DSAPILocalization.h"

static void (*originalLoad)(id,SEL);
static void (*originalLayout)(id,SEL);
static void gatherLabels(UIView *root,NSMutableArray *labels) {
    if ([root isKindOfClass:UILabel.class]) [labels addObject:root];
    for (UIView *child in root.subviews) gatherLabels(child,labels);
}
static UIFont *nativeBodyFont(UIViewController *controller) {
    if ([controller isKindOfClass:UITableViewController.class]) {
        for (UITableViewCell *cell in ((UITableViewController *)controller).tableView.visibleCells) {
            NSMutableArray *labels=[NSMutableArray array]; gatherLabels(cell.contentView,labels);
            for (UILabel *label in labels) if (!label.hidden && label.text.length && label.font) return label.font;
        }
    }
    return [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
}
static void presentAPI(id self,SEL selector) {
    [(UIViewController *)self presentViewController:DSAPICreateSettingsController(nativeBodyFont(self)) animated:YES completion:nil];
}
static void profileLoad(id self,SEL selector) {
    if (originalLoad) originalLoad(self,selector);
    UIViewController *controller=self;
    NSMutableArray *buttons=[controller.navigationItem.rightBarButtonItems mutableCopy] ?: [NSMutableArray array];
    UIBarButtonItem *api=[[UIBarButtonItem alloc] initWithTitle:@"API" style:UIBarButtonItemStylePlain target:self action:NSSelectorFromString(@"dsapi_presentSettings")];
    api.accessibilityIdentifier=@"DSAPI.APISettings"; [buttons addObject:api];
    controller.navigationItem.rightBarButtonItems=buttons;
}
static void profileLayout(id self,SEL selector) {
    if (originalLayout) originalLayout(self,selector);
    NSMutableArray *labels=[NSMutableArray array], *texts=[NSMutableArray array];
    gatherLabels(((UIViewController *)self).view,labels);
    for (UILabel *label in labels) if (label.text.length) [texts addObject:label.text];
    DSObserveNativeSettingsLanguage(texts);
}
static IMP replaceMethod(Class cls,SEL selector,IMP replacement) {
    Method method=class_getInstanceMethod(cls,selector);
    if (!method) return NULL;
    IMP original=method_getImplementation(method);
    if (!class_addMethod(cls,selector,replacement,method_getTypeEncoding(method)))
        class_replaceMethod(cls,selector,replacement,method_getTypeEncoding(method));
    return original;
}
void DSInstallSettingsIntegration(void) {
    Class profile=NSClassFromString(@"_TtC13DeepSeek_Chat21ProfileViewController");
    if (!profile) return;
    class_addMethod(profile,NSSelectorFromString(@"dsapi_presentSettings"),(IMP)presentAPI,"v@:");
    originalLoad=(void *)replaceMethod(profile,@selector(viewDidLoad),(IMP)profileLoad);
    originalLayout=(void *)replaceMethod(profile,@selector(viewDidLayoutSubviews),(IMP)profileLayout);
}
