#import "DSUsageStore.h"
static NSString *const DSUsageKey=@"DSAPIAdapter.usage.v1";
NSDictionary *DSAPIUsageSnapshot(void) {
    return [NSUserDefaults.standardUserDefaults dictionaryForKey:DSUsageKey] ?: @{};
}
void DSRecordAPIUsage(NSDictionary *record) {
    @synchronized (NSUserDefaults.standardUserDefaults) {
        NSMutableDictionary *snapshot=[DSAPIUsageSnapshot() mutableCopy];
        void (^increment)(NSString *,NSNumber *)=^(NSString *key,NSNumber *value) {
            snapshot[key]=@([snapshot[key] longLongValue]+value.longLongValue);
        };
        increment(@"requests",@1);
        NSString *outcome=record[@"outcome"] ?: @"failed";
        increment(outcome,@1);
        NSDictionary *usage=record[@"usage"];
        if ([usage isKindOfClass:NSDictionary.class] && [usage[@"total_tokens"] isKindOfClass:NSNumber.class]) {
            for (NSString *key in @[@"prompt_tokens",@"completion_tokens",@"total_tokens"])
                if ([usage[key] isKindOfClass:NSNumber.class] && [usage[key] longLongValue]>=0)
                    increment(key,usage[key]);
            increment(@"reported_requests",@1);
        } else increment(@"unreported_requests",@1);
        NSMutableArray *recent=[snapshot[@"recent"] mutableCopy] ?: [NSMutableArray array];
        [recent insertObject:record atIndex:0];
        if (recent.count>100) [recent removeObjectsInRange:NSMakeRange(100,recent.count-100)];
        snapshot[@"recent"]=recent; snapshot[@"updated_at"]=@(NSDate.date.timeIntervalSince1970);
        [NSUserDefaults.standardUserDefaults setObject:snapshot forKey:DSUsageKey];
    }
}
