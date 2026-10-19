#import "DSAPISettingsViewController.h"
#import "DSAPIConfiguration.h"
#import "DSAPILocalization.h"
#import "DSUsageViewController.h"
@interface DSAPIModelPicker : UITableViewController <UISearchResultsUpdating>
@property(nonatomic,copy) NSArray<NSString *> *models;
@property(nonatomic,copy) NSArray<NSString *> *filtered;
@property(nonatomic,copy) NSString *selected;
@property(nonatomic,strong) UIFont *bodyFont;
@property(nonatomic,copy) void (^onSelect)(NSString *);
@end
@implementation DSAPIModelPicker
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=DSAPILocalized(@"models"); self.filtered=self.models;
    UISearchController *search=[[UISearchController alloc] initWithSearchResultsController:nil];
    search.searchResultsUpdater=self; search.obscuresBackgroundDuringPresentation=NO;
    search.searchBar.placeholder=DSAPILocalized(@"modelSearch"); self.navigationItem.searchController=search;
    self.definesPresentationContext=YES;
}
- (void)updateSearchResultsForSearchController:(UISearchController *)search {
    NSString *query=search.searchBar.text ?: @"";
    self.filtered=query.length ? [self.models filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *model,NSDictionary *bindings) {
        return [model rangeOfString:query options:NSCaseInsensitiveSearch].location!=NSNotFound;
    }]] : self.models; [self.tableView reloadData];
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return self.filtered.count; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[table dequeueReusableCellWithIdentifier:@"model"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"model"];
    cell.textLabel.text=self.filtered[path.row]; cell.textLabel.numberOfLines=2; cell.textLabel.font=self.bodyFont ?: [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.accessoryType=[cell.textLabel.text isEqual:self.selected] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone; return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    if (self.onSelect) self.onSelect(self.filtered[path.row]); [self.navigationController popViewControllerAnimated:YES];
}
@end

@interface DSAPISettingsViewController () <NSURLSessionTaskDelegate, UITextFieldDelegate>
@property(nonatomic, strong) DSAPIConfiguration *configuration;
@property(nonatomic, strong) NSArray<UITextField *> *fields;
@property(nonatomic, strong) UIFont *bodyFont;
@property(nonatomic) BOOL saving;
@property(nonatomic) BOOL fetchingModels;
@property(nonatomic) BOOL showModelsAfterFetch;
@property(nonatomic,strong) NSURLSession *modelSession;
@property(nonatomic,copy) NSArray<NSString *> *modelIDs;
@property(nonatomic,copy) NSString *modelError;
@property(nonatomic) NSUInteger modelGeneration;
@property(nonatomic,copy) NSString *keyOriginHost;
@end
@implementation DSAPISettingsViewController
- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = DSAPILocalized(@"api");
    self.configuration = [DSAPIConfiguration loadConfigurationWithoutAPIKey];
    self.keyOriginHost=[NSURL URLWithString:self.configuration.baseURL].host;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
        target:self action:@selector(cancel)];
    self.navigationItem.leftBarButtonItem.accessibilityLabel=DSOriginalLocalized(@"cancel");
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:DSOriginalLocalized(@"imagePreviewSavePhoto") style:UIBarButtonItemStyleDone
        target:self action:@selector(save)];
    self.navigationItem.rightBarButtonItem.accessibilityIdentifier=@"DSAPI.Save";
    self.navigationItem.leftBarButtonItem.accessibilityIdentifier=@"DSAPI.Cancel";
    NSMutableArray *fields = [NSMutableArray array];
    NSArray *values = @[self.configuration.baseURL, self.configuration.apiKey,
        self.configuration.model, self.configuration.reasoningModel, self.configuration.systemPrompt,
        [NSString stringWithFormat:@"%.0f",self.configuration.timeout]];
    NSArray *placeholders = @[@"https://example.com/v1", @"API Key", DSAPILocalized(@"model"),
        DSAPILocalized(@"thinkingModel"), DSAPILocalized(@"systemPrompt"), @"180"];
    for (NSUInteger i = 0; i < values.count; i++) {
        UITextField *field = [UITextField new];
        field.text = values[i]; field.placeholder = placeholders[i];
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.delegate=self; field.returnKeyType=UIReturnKeyDone;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
        field.secureTextEntry = i == 1;
        field.keyboardType = i == 0 ? UIKeyboardTypeURL : (i == 5 ? UIKeyboardTypeNumberPad : UIKeyboardTypeDefault);
        field.font = self.bodyFont ?: [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        field.adjustsFontForContentSizeCategory = YES;
        field.accessibilityLabel = @[@"Base URL",@"API Key",DSAPILocalized(@"model"),DSAPILocalized(@"thinkingModel"),DSAPILocalized(@"systemPrompt"),DSAPILocalized(@"timeout")][i];
        [field addTarget:self action:@selector(connectionEdited:) forControlEvents:UIControlEventEditingDidEnd];
        [fields addObject:field];
    }
    self.fields = fields;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.fields[1].enabled=NO; self.navigationItem.rightBarButtonItem.enabled=NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        DSAPIConfiguration *loaded=[DSAPIConfiguration loadConfiguration];
        dispatch_async(dispatch_get_main_queue(),^{
            BOOL sameProvider=[[NSURL URLWithString:self.fields[0].text].host isEqual:[NSURL URLWithString:loaded.baseURL].host];
            self.configuration.apiKey=sameProvider ? loaded.apiKey : @""; self.fields[1].text=self.configuration.apiKey;
            self.fields[1].enabled=YES;
            if (!self.saving) self.navigationItem.rightBarButtonItem.enabled=YES;
            if (self.configuration.automaticModels && self.fields[1].text.length) [self fetchModelsShowingPicker:NO];
        });
    });
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { return 7; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return [@[@2,@1,@2,@4,@1,@3,@1][section] integerValue];
}
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section {
    return DSAPILocalized(@[@"mode",@"providers",@"connection",@"models",@"effort",@"advanced",@"usage"][section]);
}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    return DSAPILocalized(@[@"modeNote",@"providerNote",@"connectionNote",@"modelNote",@"effortNote",@"advancedNote",@"usageNote"][section]);
}
- (UITableViewCell *)switchCell:(NSString *)title identifier:(NSString *)identifier on:(BOOL)on action:(SEL)action {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text=DSAPILocalized(title); cell.textLabel.font=self.bodyFont;
    cell.textLabel.adjustsFontSizeToFitWidth=YES; cell.textLabel.minimumScaleFactor=0.8;
    UISwitch *toggle=[UISwitch new]; toggle.on=on; toggle.accessibilityLabel=cell.textLabel.text; toggle.accessibilityIdentifier=identifier;
    [toggle addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    cell.accessoryView=toggle; cell.selectionStyle=UITableViewCellSelectionStyleNone; return cell;
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    if (path.section==0) return path.row==0 ?
        [self switchCell:@"enableAPI" identifier:@"DSAPI.Enabled" on:self.configuration.enabled action:@selector(modeChanged:)] :
        [self switchCell:@"showAPIInChat" identifier:@"DSAPI.ShowInChat" on:self.configuration.showAPIInChat action:@selector(showInChatChanged:)];
    if (path.section==3 && path.row==2) return [self switchCell:@"automaticModels" identifier:@"DSAPI.AutomaticModels" on:self.configuration.automaticModels action:@selector(automaticModelsChanged:)];
    if (path.section==5 && path.row==2) return [self switchCell:@"requestUsage" identifier:@"DSAPI.RequestUsage" on:self.configuration.requestUsage action:@selector(usageOptionChanged:)];
    if (path.section==1 || path.section==4 || path.section==6 || (path.section==3 && path.row==3)) {
        UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
        NSString *key=path.section==1 ? @"providers" : (path.section==4 ? @"effort" : (path.section==6 ? @"usage" : @"fetchModels"));
        cell.textLabel.text=DSAPILocalized(key); cell.textLabel.font=self.bodyFont;
        cell.accessibilityIdentifier=@{@"providers":@"DSAPI.Provider",@"effort":@"DSAPI.Effort",@"usage":@"DSAPI.Usage",@"fetchModels":@"DSAPI.FetchModels"}[key];
        cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
        if (path.section==1) {
            cell.detailTextLabel.text=DSAPILocalized(@"customProvider");
            for (NSDictionary *preset in DSAPIConfiguration.providerPresets) if ([self.fields[0].text isEqual:preset[@"baseURL"]]) cell.detailTextLabel.text=preset[@"name"];
        } else if (path.section==4) cell.detailTextLabel.text=DSAPILocalized(self.configuration.reasoningEffort ?: @"auto");
        else if (path.section==3) { cell.detailTextLabel.text=self.fetchingModels ? DSAPILocalized(@"fetchingModels") : (self.modelError ?: (self.modelIDs.count ? [NSString stringWithFormat:@"%lu",(unsigned long)self.modelIDs.count] : @"")); cell.detailTextLabel.numberOfLines=2; }
        return cell;
    }
    NSUInteger index=path.section==2 ? path.row : (path.section==3 ? 2+path.row : 4+path.row);
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle=UITableViewCellSelectionStyleNone;
    UITextField *field=self.fields[index]; field.translatesAutoresizingMaskIntoConstraints=NO; [cell.contentView addSubview:field];
    [NSLayoutConstraint activateConstraints:@[[field.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
        [field.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
        [field.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:12],
        [field.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-12],
        [field.heightAnchor constraintGreaterThanOrEqualToConstant:24]]]; return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES]; [self.view endEditing:YES];
    if (path.section==6) [self presentViewController:DSAPICreateUsageController(self.bodyFont) animated:YES completion:nil];
    else if (path.section==1) [self chooseProvider:[table cellForRowAtIndexPath:path]];
    else if (path.section==4) [self chooseEffort:[table cellForRowAtIndexPath:path]];
    else if (path.section==3 && path.row==3) { if (self.modelIDs.count) [self showModelPicker]; else [self fetchModelsShowingPicker:YES]; }
}
- (BOOL)textFieldShouldReturn:(UITextField *)field { [field resignFirstResponder]; return YES; }
- (void)presentChoices:(UIAlertController *)alert cell:(UITableViewCell *)cell {
    [self.view endEditing:YES];
    [alert addAction:[UIAlertAction actionWithTitle:DSOriginalLocalized(@"cancel") style:UIAlertActionStyleCancel handler:nil]];
    alert.popoverPresentationController.sourceView=cell ?: self.view;
    alert.popoverPresentationController.sourceRect=cell ? cell.bounds : CGRectMake(self.view.bounds.size.width/2,self.view.bounds.size.height/2,1,1);
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)chooseProvider:(UITableViewCell *)cell {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:DSAPILocalized(@"providers") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf=self;
    for (NSDictionary *preset in DSAPIConfiguration.providerPresets) [alert addAction:[UIAlertAction actionWithTitle:preset[@"name"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        typeof(self) self=weakSelf; if (!self) return;
        BOOL changed=![[NSURL URLWithString:self.fields[0].text].host isEqual:[NSURL URLWithString:preset[@"baseURL"]].host];
        [self.modelSession invalidateAndCancel]; self.modelSession=nil; self.modelGeneration++; self.fetchingModels=NO; self.modelIDs=nil; self.modelError=nil;
        self.fields[0].text=preset[@"baseURL"]; self.fields[2].text=preset[@"model"]; self.fields[3].text=@"";
        if (changed) self.fields[1].text=@"";
        self.keyOriginHost=[NSURL URLWithString:preset[@"baseURL"]].host;
        [self.tableView reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:DSAPILocalized(@"customProvider") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        typeof(self) self=weakSelf; if (!self) return; [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:2] atScrollPosition:UITableViewScrollPositionMiddle animated:NO]; [self.fields[0] becomeFirstResponder];
    }]]; [self presentChoices:alert cell:cell];
}
- (void)chooseEffort:(UITableViewCell *)cell {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:DSAPILocalized(@"effort") message:DSAPILocalized(@"effortNote") preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf=self;
    for (NSString *effort in @[@"auto",@"low",@"medium",@"high",@"max"]) [alert addAction:[UIAlertAction actionWithTitle:DSAPILocalized(effort) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        weakSelf.configuration.reasoningEffort=effort; [weakSelf.tableView reloadSections:[NSIndexSet indexSetWithIndex:4] withRowAnimation:UITableViewRowAnimationNone];
    }]]; [self presentChoices:alert cell:cell];
}
- (void)showModelPicker {
    DSAPIModelPicker *picker=[[DSAPIModelPicker alloc] initWithStyle:UITableViewStyleInsetGrouped]; picker.models=self.modelIDs; picker.selected=self.fields[2].text; picker.bodyFont=self.bodyFont;
    __weak typeof(self) weakSelf=self; picker.onSelect=^(NSString *name) { weakSelf.fields[2].text=name; };
    [self.navigationController pushViewController:picker animated:YES];
}
- (void)connectionEdited:(UITextField *)field {
    if (field!=self.fields[0] && field!=self.fields[1]) return;
    NSString *host=[NSURL URLWithString:self.fields[0].text].host;
    if (field==self.fields[0] && self.keyOriginHost.length && ![host isEqual:self.keyOriginHost]) self.fields[1].text=@"";
    self.keyOriginHost=host;
    [self.modelSession invalidateAndCancel]; self.modelSession=nil; self.modelGeneration++; self.fetchingModels=NO; self.modelIDs=nil; self.modelError=nil;
    if (self.configuration.automaticModels && !self.saving && self.fields[1].enabled) [self fetchModelsShowingPicker:NO];
}
- (void)fetchModelsShowingPicker:(BOOL)showPicker {
    if (self.fetchingModels) { self.showModelsAfterFetch|=showPicker; return; }
    if (self.saving || !self.fields[1].enabled) return;
    self.showModelsAfterFetch=showPicker;
    DSAPIConfiguration *draft=[DSAPIConfiguration new]; draft.baseURL=self.fields[0].text ?: @"";
    NSError *error=nil; NSURL *url=[draft modelsURL:&error];
    if (!url || [self.fields[1].text rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location!=NSNotFound) { self.modelError=error.localizedDescription ?: DSAPILocalized(@"invalidFields"); [self.tableView reloadData]; return; }
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url]; request.timeoutInterval=20;
    [NSURLProtocol setProperty:@YES forKey:@"DSAPI.DirectAPI" inRequest:request];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    if (self.fields[1].text.length) [request setValue:[@"Bearer " stringByAppendingString:self.fields[1].text] forHTTPHeaderField:@"Authorization"];
    self.fetchingModels=YES; self.modelError=nil; NSUInteger generation=++self.modelGeneration;
    NSURLSessionConfiguration *options=NSURLSessionConfiguration.ephemeralSessionConfiguration; options.HTTPCookieStorage=nil; options.URLCache=nil;
    self.modelSession=[NSURLSession sessionWithConfiguration:options delegate:self delegateQueue:nil];
    __weak typeof(self) weakSelf=self;
    NSURLSession *session=self.modelSession;
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *networkError) {
        NSError *parseError=nil; NSInteger status=[response isKindOfClass:NSHTTPURLResponse.class] ? [(NSHTTPURLResponse *)response statusCode] : 0;
        NSArray *models=networkError ? nil : [DSAPIConfiguration modelIDsFromData:data status:status error:&parseError];
        [session finishTasksAndInvalidate];
        dispatch_async(dispatch_get_main_queue(),^{
            typeof(self) self=weakSelf; if (!self || generation!=self.modelGeneration) return;
            self.modelSession=nil; self.fetchingModels=NO; self.modelIDs=models; self.modelError=(networkError ?: parseError).localizedDescription;
            [self.tableView reloadData];
            BOOL show=self.showModelsAfterFetch; self.showModelsAfterFetch=NO;
            if (show && self.view.window && !self.presentedViewController) {
                if (models.count) [self showModelPicker];
                else { UIAlertController *alert=[UIAlertController alertControllerWithTitle:DSAPILocalized(@"modelsFailed") message:self.modelError preferredStyle:UIAlertControllerStyleAlert]; [alert addAction:[UIAlertAction actionWithTitle:DSAPILocalized(@"ok") style:UIAlertActionStyleDefault handler:nil]]; [self presentViewController:alert animated:YES completion:nil]; }
            }
        });
    }] resume]; [self.tableView reloadData];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest * _Nullable))handler { handler(nil); }
- (void)showInChatChanged:(UISwitch *)sender { self.configuration.showAPIInChat=sender.on; }
- (void)automaticModelsChanged:(UISwitch *)sender { self.configuration.automaticModels=sender.on; if (sender.on) [self fetchModelsShowingPicker:NO]; }
- (void)modeChanged:(UISwitch *)sender { self.configuration.enabled=sender.on; }
- (void)usageOptionChanged:(UISwitch *)sender { self.configuration.requestUsage=sender.on; }
- (void)cancel { self.modelGeneration++; [self.modelSession invalidateAndCancel]; self.modelSession=nil; [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)save {
    if (self.saving) return;
    [self.view endEditing:YES];
    self.configuration.baseURL = self.fields[0].text ?: @"";
    self.configuration.apiKey = self.fields[1].text ?: @"";
    self.configuration.model = self.fields[2].text ?: @"";
    self.configuration.reasoningModel = self.fields[3].text ?: @"";
    self.configuration.systemPrompt = self.fields[4].text ?: @"";
    self.configuration.timeout = self.fields[5].text.doubleValue;
    self.saving=YES; self.modelGeneration++; [self.modelSession invalidateAndCancel]; self.modelSession=nil;
    self.navigationItem.leftBarButtonItem.enabled=NO;
    self.navigationItem.rightBarButtonItem.enabled=NO;
    self.tableView.userInteractionEnabled=NO;
    DSAPIConfiguration *configuration=self.configuration;
    // Keychain can wait on the device security service. Never hold the UI thread.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSError *error=nil; BOOL saved=[configuration save:&error];
        dispatch_async(dispatch_get_main_queue(),^{ [self didSave:saved error:error]; });
    });
}
- (void)didSave:(BOOL)saved error:(NSError *)error {
    self.saving=NO;
    self.navigationItem.leftBarButtonItem.enabled=YES;
    self.navigationItem.rightBarButtonItem.enabled=YES;
    self.tableView.userInteractionEnabled=YES;
    if (!self.view.window) return;
    if (!saved) {
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:DSAPILocalized(@"saveError")
            message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:DSAPILocalized(@"ok") style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil]; return;
    }
    [NSNotificationCenter.defaultCenter postNotificationName:@"DSAPIAdapter.SettingsChanged" object:nil];
    if (self.configuration.enabled!=DSAPIIsEnabled()) {
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:DSAPILocalized(@"restartTitle") message:DSAPILocalized(@"modeNote") preferredStyle:UIAlertControllerStyleAlert];
        __weak typeof(self) weakSelf=self;
        [alert addAction:[UIAlertAction actionWithTitle:DSAPILocalized(@"ok") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            // Let UIKit dismiss the alert before dismissing its presenting page.
            dispatch_async(dispatch_get_main_queue(),^{ [weakSelf dismissViewControllerAnimated:YES completion:nil]; });
        }]];
        [self presentViewController:alert animated:YES completion:nil]; return;
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}
@end
UIViewController *DSAPICreateSettingsController(UIFont *bodyFont) {
    DSAPISettingsViewController *controller=[DSAPISettingsViewController new]; controller.bodyFont=bodyFont;
    return [[UINavigationController alloc] initWithRootViewController:controller];
}
