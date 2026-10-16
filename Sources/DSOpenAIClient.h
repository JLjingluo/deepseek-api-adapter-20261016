#import <Foundation/Foundation.h>
#import "DSAPIConfiguration.h"
NS_ASSUME_NONNULL_BEGIN
@interface DSOpenAIClient : NSObject <NSURLSessionDataDelegate, NSURLSessionTaskDelegate>
/// All callbacks are delivered on the main queue. Keep the client alive until terminal delivery.
- (instancetype)initWithConfiguration:(DSAPIConfiguration *)configuration;
- (void)startMessages:(NSArray<NSDictionary *> *)messages reasoning:(BOOL)reasoning
    delta:(void (^)(NSString *, NSString *))delta
    completion:(void (^)(NSString * _Nullable, NSError * _Nullable))completion;
- (void)cancel;
@end
NS_ASSUME_NONNULL_END
