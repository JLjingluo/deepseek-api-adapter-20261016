#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface DSLocalStore : NSObject
+ (instancetype)shared;
- (instancetype)initWithDirectory:(NSURL *)directory;
- (nullable NSDictionary *)session:(NSString *)identifier;
- (NSArray<NSDictionary *> *)sessions;
- (BOOL)importCloudSessions:(NSArray<NSDictionary *> *)sessions owner:(NSString *)owner error:(NSError **)error;
- (BOOL)importCloudHistory:(NSDictionary *)session messages:(NSArray<NSDictionary *> *)messages owner:(NSString *)owner error:(NSError **)error;
- (nullable NSDictionary *)createSession:(NSString *)model error:(NSError **)error;
- (BOOL)updateSession:(NSString *)identifier values:(NSDictionary *)values error:(NSError **)error;
- (BOOL)deleteSessions:(NSArray<NSString *> *)identifiers error:(NSError **)error;
- (NSArray<NSDictionary *> *)messages:(NSString *)session;
- (nullable NSArray<NSDictionary *> *)beginTurn:(NSString *)session parent:(nullable NSNumber *)parent
    prompt:(nullable NSString *)prompt thinking:(BOOL)thinking error:(NSError **)error;
- (nullable NSArray<NSDictionary *> *)apiHistory:(NSString *)session endingAt:(NSNumber *)message error:(NSError **)error;
- (BOOL)updateMessage:(NSNumber *)identifier session:(NSString *)session values:(NSDictionary *)values error:(NSError **)error;
- (nullable NSDictionary *)message:(NSNumber *)identifier session:(NSString *)session;
@end
NS_ASSUME_NONNULL_END
