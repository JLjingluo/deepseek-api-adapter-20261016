#import "DSUsageViewController.h"
#import "DSUsageStore.h"
#import "DSAPILocalization.h"
@interface DSUsageViewController : UITableViewController
@property(nonatomic,strong) NSDictionary *snapshot;
@end
@implementation DSUsageViewController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=DSAPILocalized(@"usage");
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(close)];
    self.navigationItem.leftBarButtonItem.accessibilityIdentifier=@"DSAPI.CloseUsage";
    self.refreshControl=[UIRefreshControl new]; [self.refreshControl addTarget:self action:@selector(reloadUsage) forControlEvents:UIControlEventValueChanged];
    [self reloadUsage];
}
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)reloadUsage { self.snapshot=DSAPIUsageSnapshot(); [self.tableView reloadData]; [self.refreshControl endRefreshing]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section==0 ? 4 : (section==1 ? 4 : [self.snapshot[@"recent"] count]);
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section==0 ? DSAPILocalized(@"requests") : (section==1 ? @"Token" : DSAPILocalized(@"recent"));
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return section==1 ? DSAPILocalized(@"usageNote") : nil;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:path.section==2 ? UITableViewCellStyleSubtitle : UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.selectionStyle=UITableViewCellSelectionStyleNone;
    if (path.section<2) {
        NSString *key=(path.section==0 ? @[@"requests",@"succeeded",@"failed",@"cancelled"] : @[@"prompt_tokens",@"completion_tokens",@"total_tokens",@"unreported_requests"])[path.row];
        cell.textLabel.text=DSAPILocalized(key); cell.detailTextLabel.text=[self.snapshot[key] stringValue] ?: @"0";
    } else {
        NSDictionary *record=self.snapshot[@"recent"][path.row];
        cell.textLabel.text=[NSString stringWithFormat:@"%@ · %@",record[@"model"] ?: @"",DSAPILocalized(record[@"outcome"] ?: @"failed")];
        NSDateFormatter *formatter=[NSDateFormatter new]; formatter.dateStyle=NSDateFormatterShortStyle; formatter.timeStyle=NSDateFormatterShortStyle;
        formatter.locale=[NSLocale localeWithLocaleIdentifier:DSOriginalLocalized(@"locale")];
        cell.detailTextLabel.text=[NSString stringWithFormat:@"%@ · %@ · %.1fs",[formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:[record[@"timestamp"] doubleValue]]],record[@"host"] ?: @"",[record[@"duration"] doubleValue]];
        cell.detailTextLabel.numberOfLines=0;
    }
    cell.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody]; cell.textLabel.adjustsFontForContentSizeCategory=YES;
    return cell;
}
@end
UIViewController *DSAPICreateUsageController(void) {
    return [[UINavigationController alloc] initWithRootViewController:[[DSUsageViewController alloc] initWithStyle:UITableViewStyleInsetGrouped]];
}
