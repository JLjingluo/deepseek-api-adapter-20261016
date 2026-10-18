#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "DSAPISettingsViewController.h"
#import "DSAPILocalization.h"

static char DSTableKey, DSStyleKey;
static void (*originalLoad)(id,SEL), (*originalLayout)(id,SEL);
static NSInteger (*originalSections)(id,SEL,UITableView *);
static NSInteger (*originalRows)(id,SEL,UITableView *,NSInteger);
static UITableViewCell *(*originalCell)(id,SEL,UITableView *,NSIndexPath *);
static void (*originalSelect)(id,SEL,UITableView *,NSIndexPath *);
static BOOL (*originalHighlight)(id,SEL,UITableView *,NSIndexPath *);
static UIView *(*originalHeader)(id,SEL,UITableView *,NSInteger), *(*originalFooter)(id,SEL,UITableView *,NSInteger);
static CGFloat (*originalHeaderHeight)(id,SEL,UITableView *,NSInteger), (*originalFooterHeight)(id,SEL,UITableView *,NSInteger);
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
static NSInteger nativeSections(UITableView *table) {
    return originalSections ? originalSections(table.dataSource,@selector(numberOfSectionsInTableView:),table) : 1;
}
static BOOL isAPISection(UITableView *table,NSInteger section) { return hasAPIRow(table) && section==nativeSections(table); }
static UIFont *nativeBodyFont(UIViewController *controller) {
    UIListContentConfiguration *style=objc_getAssociatedObject(controller,&DSStyleKey);
    return style.textProperties.font ?: [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
}
static void presentAPI(id self,SEL selector) {
    [(UIViewController *)self presentViewController:DSAPICreateSettingsController(nativeBodyFont(self)) animated:YES completion:nil];
}
static NSInteger sections(id self,SEL selector,UITableView *table) {
    NSInteger count=originalSections ? originalSections(self,selector,table) : 1;
    return count+(hasAPIRow(table) ? 1 : 0);
}
static NSInteger rows(id self,SEL selector,UITableView *table,NSInteger section) {
    return isAPISection(table,section) ? 1 : originalRows(self,selector,table,section);
}
static UITableViewCell *apiCell(id self,SEL selector,UITableView *table,NSIndexPath *index) {
    if (!isAPISection(table,index.section)) return originalCell(self,selector,table,index);
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
    style.image=[UIImage systemImageNamed:@"network"];
    cell.contentConfiguration=style;
    cell.accessibilityIdentifier=@"DSAPI.APISettings";
    cell.accessibilityLabel=style.text;
    return cell;
}
static void selectRow(id self,SEL selector,UITableView *table,NSIndexPath *index) {
    if (isAPISection(table,index.section)) { [table deselectRowAtIndexPath:index animated:YES]; presentAPI(self,selector); }
    else if (originalSelect) originalSelect(self,selector,table,index);
}
static BOOL highlightRow(id self,SEL selector,UITableView *table,NSIndexPath *index) {
    return isAPISection(table,index.section) ? YES : (originalHighlight ? originalHighlight(self,selector,table,index) : YES);
}
static UIView *header(id self,SEL selector,UITableView *table,NSInteger section) {
    return isAPISection(table,section) ? nil : (originalHeader ? originalHeader(self,selector,table,section) : nil);
}
static UIView *footer(id self,SEL selector,UITableView *table,NSInteger section) {
    return isAPISection(table,section) ? nil : (originalFooter ? originalFooter(self,selector,table,section) : nil);
}
static CGFloat headerHeight(id self,SEL selector,UITableView *table,NSInteger section) {
    if (!isAPISection(table,section)) return originalHeaderHeight ? originalHeaderHeight(self,selector,table,section) : UITableViewAutomaticDimension;
    NSInteger reference=MIN(1,MAX(0,nativeSections(table)-1));
    CGFloat height=originalHeaderHeight ? originalHeaderHeight(self,selector,table,reference) : 28;
    return height>0 ? height : 28;
}
static CGFloat footerHeight(id self,SEL selector,UITableView *table,NSInteger section) {
    return isAPISection(table,section) ? 0.01 : (originalFooterHeight ? originalFooterHeight(self,selector,table,section) : UITableViewAutomaticDimension);
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
        // Keep the original diffable source and its item identifiers. Appending
        // an independent section leaves all original section/row paths intact.
        Class source=object_getClass(table.dataSource);
        if (![NSStringFromClass(source) containsString:@"ProfileViewController"]) return;
        static dispatch_once_t once;
        dispatch_once(&once,^{
            originalSections=(void *)replaceMethod(source,@selector(numberOfSectionsInTableView:),(IMP)sections);
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
    originalHeader=(void *)replaceMethod(profile,@selector(tableView:viewForHeaderInSection:),(IMP)header);
    originalFooter=(void *)replaceMethod(profile,@selector(tableView:viewForFooterInSection:),(IMP)footer);
    originalHeaderHeight=(void *)replaceMethod(profile,@selector(tableView:heightForHeaderInSection:),(IMP)headerHeight);
    originalFooterHeight=(void *)replaceMethod(profile,@selector(tableView:heightForFooterInSection:),(IMP)footerHeight);
}
