#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSDictionary *DSLocalVoiceConfiguration(void);
FOUNDATION_EXPORT BOOL DSSelectLocalVoice(NSString *identifier);
FOUNDATION_EXPORT NSString *DSSelectedLocalVoice(void);
FOUNDATION_EXPORT void DSGenerateLocalVoiceDemo(NSString *identifier,void (^completion)(NSData * _Nullable,NSError * _Nullable));
NS_ASSUME_NONNULL_END
