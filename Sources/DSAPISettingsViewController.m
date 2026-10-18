#import "DSAPISettingsViewController.h"
#import "DSAPIConfiguration.h"
#import "DSAPILocalization.h"
#import "DSUsageViewController.h"
@interface DSAPISettingsViewController ()
@property(nonatomic, strong) DSAPIConfiguration *configuration;
@property(nonatomic, strong) NSArray<UITextField *> *fields;
@property(nonatomic, strong) UIFont *bodyFont;
@end
@implementation DSAPISettingsViewController
- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = DSAPILocalized(@"api");
    self.configuration = [DSAPIConfiguration loadConfiguration];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
        target:self action:@selector(cancel)];
    self.navigationItem.leftBarButtonItem.accessibilityLabel=DSOriginalLocalized(@"cancel");
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:DSOriginalLocalized(@"imagePreviewSavePhoto") style:UIBarButtonItemStyleDone
        target:self action:@selector(save)];
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
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
        field.secureTextEntry = i == 1;
        field.keyboardType = i == 0 ? UIKeyboardTypeURL : (i == 5 ? UIKeyboardTypeNumberPad : UIKeyboardTypeDefault);
        field.font = self.bodyFont ?: [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        field.adjustsFontForContentSizeCategory = YES;
        field.accessibilityLabel = @[@"Base URL",@"API Key",DSAPILocalized(@"model"),DSAPILocalized(@"thinkingModel"),DSAPILocalized(@"systemPrompt"),DSAPILocalized(@"timeout")][i];
        [fields addObject:field];
    }
    self.fields = fields;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 5; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section==0 || section==4 ? 1 : (section==3 ? 3 : 2);
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[DSAPILocalized(@"mode"), DSAPILocalized(@"connection"), DSAPILocalized(@"models"), DSAPILocalized(@"advanced"),DSAPILocalized(@"usage")][section];
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return DSAPILocalized(@[@"modeNote",@"connectionNote",@"modelNote",@"advancedNote",@"usageNote"][section]);
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section==0) {
        UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.textLabel.text=DSAPILocalized(@"enableAPI"); cell.textLabel.font=self.bodyFont;
        UISwitch *toggle=[UISwitch new]; toggle.on=self.configuration.enabled;
        toggle.accessibilityLabel=DSAPILocalized(@"enableAPI"); toggle.accessibilityIdentifier=@"DSAPI.Enabled";
        [toggle addTarget:self action:@selector(modeChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView=toggle; cell.selectionStyle=UITableViewCellSelectionStyleNone; return cell;
    }
    if (indexPath.section==4) {
        UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.textLabel.text=DSAPILocalized(@"usage"); cell.textLabel.font=self.bodyFont;
        cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator; cell.accessibilityIdentifier=@"DSAPI.Usage"; return cell;
    }
    if (indexPath.section==3 && indexPath.row==2) {
        UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.textLabel.text=DSAPILocalized(@"requestUsage"); cell.textLabel.font=self.bodyFont ?: [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        cell.selectionStyle=UITableViewCellSelectionStyleNone;
        UISwitch *toggle=[UISwitch new]; toggle.on=self.configuration.requestUsage;
        toggle.accessibilityLabel=DSAPILocalized(@"requestUsage"); toggle.accessibilityIdentifier=@"DSAPI.RequestUsage";
        [toggle addTarget:self action:@selector(usageOptionChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView=toggle; return cell;
    }
    NSUInteger index = (indexPath.section-1) * 2 + indexPath.row;
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UITextField *field = self.fields[index];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:field];
    [NSLayoutConstraint activateConstraints:@[
        [field.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
        [field.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
        [field.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:12],
        [field.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-12],
        [field.heightAnchor constraintGreaterThanOrEqualToConstant:24]]];
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (path.section==4) [self presentViewController:DSAPICreateUsageController(self.bodyFont) animated:YES completion:nil];
}
- (void)modeChanged:(UISwitch *)sender { self.configuration.enabled=sender.on; }
- (void)usageOptionChanged:(UISwitch *)sender { self.configuration.requestUsage=sender.on; }
- (void)cancel { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)save {
    [self.view endEditing:YES];
    self.configuration.baseURL = self.fields[0].text ?: @"";
    self.configuration.apiKey = self.fields[1].text ?: @"";
    self.configuration.model = self.fields[2].text ?: @"";
    self.configuration.reasoningModel = self.fields[3].text ?: @"";
    self.configuration.systemPrompt = self.fields[4].text ?: @"";
    self.configuration.timeout = self.fields[5].text.doubleValue;
    NSError *error = nil;
    if (![self.configuration save:&error]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:DSAPILocalized(@"saveError")
            message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:DSAPILocalized(@"ok") style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil]; return;
    }
    if (self.configuration.enabled!=DSAPIIsEnabled()) {
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:DSAPILocalized(@"restartTitle") message:DSAPILocalized(@"modeNote") preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:DSAPILocalized(@"ok") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self dismissViewControllerAnimated:YES completion:nil]; }]];
        [self presentViewController:alert animated:YES completion:nil]; return;
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}
@end
UIViewController *DSAPICreateSettingsController(UIFont *bodyFont) {
    DSAPISettingsViewController *controller=[DSAPISettingsViewController new]; controller.bodyFont=bodyFont;
    return [[UINavigationController alloc] initWithRootViewController:controller];
}
