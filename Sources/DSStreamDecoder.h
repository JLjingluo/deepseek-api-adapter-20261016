#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
/// Call consume/endOfInput on one queue. Byte and UTF-8 boundaries are independent.
@interface DSStreamDecoder : NSObject
@property(nonatomic, copy, nullable) void (^onDelta)(NSString *text, NSString *reasoning);
@property(nonatomic, copy, nullable) void (^onFinish)(NSString *reason);
@property(nonatomic, copy, nullable) void (^onUsage)(NSDictionary *usage);
@property(nonatomic, copy, nullable) void (^onError)(NSError *error);
@property(nonatomic, readonly) BOOL terminal;
- (void)consume:(NSData *)data;
- (void)endOfInput;
@end
NS_ASSUME_NONNULL_END
