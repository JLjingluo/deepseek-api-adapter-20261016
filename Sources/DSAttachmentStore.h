#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface DSAttachmentStore : NSObject
+ (instancetype)shared;
- (instancetype)initWithDirectory:(NSURL *)directory;
- (nullable NSDictionary *)importRequest:(NSURLRequest *)request error:(NSError **)error;
- (nullable NSDictionary *)file:(NSString *)identifier;
- (NSArray *)files:(NSArray *)identifiers;
- (nullable NSData *)data:(NSString *)identifier;
- (nullable NSArray *)contentParts:(NSArray *)files error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
