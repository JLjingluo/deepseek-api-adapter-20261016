#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
@interface DSAPISettingsViewController : UITableViewController
@end
/// The original application's settings integration must explicitly present this.
FOUNDATION_EXPORT UIViewController *DSAPICreateSettingsController(void);
NS_ASSUME_NONNULL_END
