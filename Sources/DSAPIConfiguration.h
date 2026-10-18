#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface DSAPIConfiguration : NSObject
@property(nonatomic, copy) NSString *baseURL;
@property(nonatomic, copy) NSString *model;
@property(nonatomic, copy) NSString *reasoningModel;
@property(nonatomic, copy) NSString *systemPrompt;
@property(nonatomic) NSTimeInterval timeout;
@property(nonatomic) BOOL requestUsage;
@property(nonatomic, copy) NSString *apiKey;
+ (instancetype)loadConfiguration;
- (BOOL)save:(NSError **)error;
- (nullable NSURL *)completionURL:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
