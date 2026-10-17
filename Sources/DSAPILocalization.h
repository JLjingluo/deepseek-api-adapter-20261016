#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSString *DSAPILocalized(NSString *key);
FOUNDATION_EXPORT NSString *DSOriginalLocalized(NSString *key);
FOUNDATION_EXPORT BOOL DSObserveNativeSettingsLanguage(NSArray<NSString *> *texts);
NS_ASSUME_NONNULL_END
