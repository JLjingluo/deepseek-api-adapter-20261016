#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "DSAPIConfiguration.h"
#import "DSAPISettingsViewController.h"
#import "DSAPILocalization.h"

static char DSTableKey, DSStyleKey;
static void (*originalLoad)(id,SEL), (*originalLayout)(id,SEL);
static NSInteger (*originalRows)(id,SEL,UITableView *,NSInteger);
static UITableViewCell *(*originalCell)(id,SEL,UITableView *,NSIndexPath *);
static void (*originalSelect)(id,SEL,UITableView *,NSIndexPath *);
static BOOL (*originalHighlight)(id,SEL,UITableView *,NSIndexPath *);
static IMP replaceMethod(Class cls,SEL selector,IMP replacement) {
    Method method=class_getInstanceMethod(cls,selector); if (!method) return NULL;
    IMP original=method_getImplementation(method);
    if (!class_addMethod(cls,selector,replacement,method_getTypeEncoding(method)))
        class_replaceMethod(cls,selector,replacement,method_getTypeEncoding(method));
    return original;
}
static void gatherLabels(UIView *root,NSMutableArray *labels) {
    if ([root isKindOfClass:UILabel.class]) [labels addObject:root];
    for (UIView *child in root.subviews) gatherLabels(child,labels);
}
static BOOL hasAPIRow(UITableView *table) { return objc_getAssociatedObject(table,&DSTableKey)!=nil; }
static BOOL isAPIRow(UITableView *table,NSIndexPath *index) {
    return hasAPIRow(table) && index.section==0 && index.row==originalRows(table.dataSource,@selector(tableView:numberOfRowsInSection:),table,0);
}
static UIFont *nativeBodyFont(UIViewController *controller) {
    UIListContentConfiguration *style=objc_getAssociatedObject(controller,&DSStyleKey);
    return style.textProperties.font ?: [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
}
static void presentAPI(id self,SEL selector) {
    [(UIViewController *)self presentViewController:DSAPICreateSettingsController(nativeBodyFont(self)) animated:YES completion:nil];
}
static NSInteger rows(id self,SEL selector,UITableView *table,NSInteger section) {
    return originalRows(self,selector,table,section)+(hasAPIRow(table) && section==0 ? 1 : 0);
}
static UITableViewCell *apiCell(id self,SEL selector,UITableView *table,NSIndexPath *index) {
    if (!isAPIRow(table,index)) {
        UITableViewCell *cell=originalCell(self,selector,table,index);
        if (hasAPIRow(table) && index.section==0 && index.row==originalRows(self,@selector(tableView:numberOfRowsInSection:),table,0)-1)
            cell.layer.maskedCorners &= ~(kCALayerMinXMaxYCorner|kCALayerMaxXMaxYCorner);
        return cell;
    }
    UITableViewCell *cell=[table dequeueReusableCellWithIdentifier:@"DSAPI.NativeSettingsRow"];
    if (!cell) {
        Class native=NSClassFromString(@"_TtCC13DeepSeek_Chat21ProfileViewController17InsetsGroupedCell");
        cell=[[(native ?: UITableViewCell.class) alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"DSAPI.NativeSettingsRow"];
        Class chevron=NSClassFromString(@"_TtCC13DeepSeek_Chat21ProfileViewController14ForwardChevron");
        if (chevron) cell.accessoryView=[[chevron alloc] init];
        else cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    }
    UIListContentConfiguration *style=[objc_getAssociatedObject(table.delegate,&DSStyleKey) copy] ?: [cell defaultContentConfiguration];
    style.text=DSAPILocalized(@"api"); style.secondaryText=nil;
    style.image=[UIImage systemImageNamed:@"network" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:style.textProperties.font.pointSize weight:UIImageSymbolWeightRegular]]; style.imageProperties.tintColor=style.textProperties.color ?: UIColor.labelColor;
    cell.layer.maskedCorners=kCALayerMinXMaxYCorner|kCALayerMaxXMaxYCorner;
    cell.contentConfiguration=style;
    cell.accessibilityIdentifier=@"DSAPI.APISettings";
    cell.accessibilityLabel=style.text;
    return cell;
}
static void selectRow(id self,SEL selector,UITableView *table,NSIndexPath *index) {
    if (isAPIRow(table,index)) { [table deselectRowAtIndexPath:index animated:YES]; presentAPI(self,selector); }
    else {
        id identifier=nil;
        SEL item=NSSelectorFromString(@"itemIdentifierForIndexPath:");
        if (DSAPIIsLocalGuest() && [(id)table.dataSource respondsToSelector:item]) identifier=((id (*)(id,SEL,id))objc_msgSend)(table.dataSource,item,index);
        if (DSAPIIsLocalGuest() && [[identifier description] containsString:@"accountManagement"]) DSAPIRequestGuestSignIn();
        else if (originalSelect) originalSelect(self,selector,table,index);
    }
}
static BOOL highlightRow(id self,SEL selector,UITableView *table,NSIndexPath *index) {
    return isAPIRow(table,index) ? YES : (originalHighlight ? originalHighlight(self,selector,table,index) : YES);
}
static void profileLoad(id self,SEL selector) { if (originalLoad) originalLoad(self,selector); }
static void profileLayout(id self,SEL selector) {
    if (originalLayout) originalLayout(self,selector);
    UIViewController *controller=self;
    NSMutableArray *labels=[NSMutableArray array],*texts=[NSMutableArray array]; gatherLabels(controller.view,labels);
    for (UILabel *label in labels) if (label.text.length) [texts addObject:label.text];
    DSObserveNativeSettingsLanguage(texts);
    if (![controller isKindOfClass:UITableViewController.class]) return;
    UITableView *table=((UITableViewController *)controller).tableView;
    for (UITableViewCell *cell in table.visibleCells) {
        if ([cell.accessibilityIdentifier isEqual:@"DSAPI.APISettings"]) continue;
        if ([cell.contentConfiguration isKindOfClass:UIListContentConfiguration.class]) {
            objc_setAssociatedObject(self,&DSStyleKey,[(UIListContentConfiguration *)cell.contentConfiguration copy],OBJC_ASSOCIATION_RETAIN_NONATOMIC); break;
        }
    }
    if (!hasAPIRow(table) && table.dataSource) {
        // Add a row to the account/settings group. Every original section and
        // original row keeps its existing index; legal/footer content stays last.
        Class source=object_getClass(table.dataSource);
        if (![NSStringFromClass(source) containsString:@"ProfileViewController"]) return;
        static dispatch_once_t once;
        dispatch_once(&once,^{
            originalRows=(void *)replaceMethod(source,@selector(tableView:numberOfRowsInSection:),(IMP)rows);
            originalCell=(void *)replaceMethod(source,@selector(tableView:cellForRowAtIndexPath:),(IMP)apiCell);
        });
        if (!originalRows || !originalCell) return;
        objc_setAssociatedObject(table,&DSTableKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [table reloadData];
    }
    for (UITableViewCell *cell in table.visibleCells) if ([cell.accessibilityIdentifier isEqual:@"DSAPI.APISettings"]) {
        UIListContentConfiguration *style=[(UIListContentConfiguration *)cell.contentConfiguration copy];
        UIFont *font=nativeBodyFont(controller);
        if (![style.text isEqual:DSAPILocalized(@"api")] || ![style.textProperties.font isEqual:font]) { style.text=DSAPILocalized(@"api"); style.textProperties.font=font; cell.contentConfiguration=style; cell.accessibilityLabel=style.text; }
    }
}
void DSInstallSettingsIntegration(void) {
    Class profile=NSClassFromString(@"_TtC13DeepSeek_Chat21ProfileViewController"); if (!profile) return;
    class_addMethod(profile,NSSelectorFromString(@"dsapi_presentSettings"),(IMP)presentAPI,"v@:");
    originalLoad=(void *)replaceMethod(profile,@selector(viewDidLoad),(IMP)profileLoad);
    originalLayout=(void *)replaceMethod(profile,@selector(viewDidLayoutSubviews),(IMP)profileLayout);
    originalSelect=(void *)replaceMethod(profile,@selector(tableView:didSelectRowAtIndexPath:),(IMP)selectRow);
    originalHighlight=(void *)replaceMethod(profile,@selector(tableView:shouldHighlightRowAtIndexPath:),(IMP)highlightRow);
}
