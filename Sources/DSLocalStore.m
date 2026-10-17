#import "DSLocalStore.h"
#import <TargetConditionals.h>

static NSError *DSStoreError(NSString *description) {
    return [NSError errorWithDomain:@"DSAPI.Store" code:1 userInfo:@{NSLocalizedDescriptionKey:description}];
}
@implementation DSLocalStore {
    NSURL *_file;
    NSMutableDictionary *_state;
    NSError *_loadError;
}
+ (instancetype)shared {
    static DSLocalStore *store;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL *directory = [[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
            inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"DSAPIAdapter" isDirectory:YES];
        store = [[self alloc] initWithDirectory:directory];
    });
    return store;
}
- (instancetype)initWithDirectory:(NSURL *)directory {
    if ((self = [super init])) {
        NSError *error = nil;
        if (![NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:&error]) {
            _loadError = error;
        }
        _file = [directory URLByAppendingPathComponent:@"sessions-v1.json"];
        if ([NSFileManager.defaultManager fileExistsAtPath:_file.path]) {
            NSData *data = [NSData dataWithContentsOfURL:_file options:0 error:&error];
            id state = data ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&error] : nil;
            if ([state isKindOfClass:NSMutableDictionary.class] && [state[@"schema"] isEqual:@1] &&
                [state[@"sessions"] isKindOfClass:NSDictionary.class] && [state[@"messages"] isKindOfClass:NSDictionary.class] &&
                [state[@"nextID"] isKindOfClass:NSNumber.class]) _state = state;
            else _loadError = error ?: DSStoreError(@"本地历史格式损坏；已保留原文件。");
        }
        if (!_state) _state = [@{@"schema":@1,@"nextID":@1,@"sessions":[NSMutableDictionary dictionary],
            @"messages":[NSMutableDictionary dictionary]} mutableCopy];
    }
    return self;
}
- (BOOL)commit:(NSMutableDictionary *)next error:(NSError **)error {
    if (_loadError) { if (error) *error = _loadError; return NO; }
    NSData *data = [NSJSONSerialization dataWithJSONObject:next options:0 error:error];
    if (!data) return NO;
    NSDataWritingOptions options = NSDataWritingAtomic;
#if TARGET_OS_IOS
    options |= NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication;
#endif
    if (![data writeToURL:_file options:options error:error]) return NO;
    _state = next;
    return YES;
}
- (NSMutableDictionary *)nextState {
    NSData *data = [NSJSONSerialization dataWithJSONObject:_state options:0 error:NULL];
    return [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:NULL];
}
- (NSDictionary *)session:(NSString *)identifier { return [_state[@"sessions"][identifier] copy]; }
- (NSArray<NSDictionary *> *)sessions {
    return [[_state[@"sessions"] allValues] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        if ([a[@"pinned"] boolValue] != [b[@"pinned"] boolValue]) return [a[@"pinned"] boolValue] ? NSOrderedAscending : NSOrderedDescending;
        NSComparisonResult time = [b[@"updated_at"] compare:a[@"updated_at"]];
        return time == NSOrderedSame ? [a[@"id"] compare:b[@"id"]] : time;
    }];
}
- (NSDictionary *)createSession:(NSString *)model error:(NSError **)error {
    NSMutableDictionary *next = [self nextState];
    NSString *identifier = [NSUUID.UUID.UUIDString.lowercaseString stringByReplacingOccurrencesOfString:@"-" withString:@""];
    NSNumber *now = @(NSDate.date.timeIntervalSince1970);
    NSDictionary *session = @{@"id":identifier,@"title":@"新对话",@"title_type":@"SYSTEM",@"pinned":@NO,
        @"updated_at":now,@"inserted_at":now,@"is_empty":@YES,@"model_type":model ?: @"default",
        @"version":@1,@"current_message_id":NSNull.null};
    next[@"sessions"][identifier] = [session mutableCopy]; next[@"messages"][identifier] = [NSMutableArray array];
    return [self commit:next error:error] ? session : nil;
}
- (BOOL)updateSession:(NSString *)identifier values:(NSDictionary *)values error:(NSError **)error {
    NSMutableDictionary *next = [self nextState];
    NSMutableDictionary *session = next[@"sessions"][identifier];
    if (!session) { if (error) *error = DSStoreError(@"会话不存在。"); return NO; }
    for (NSString *key in @[@"title",@"title_type",@"pinned",@"current_message_id",@"is_empty"])
        if (values[key]) session[key] = values[key];
    session[@"updated_at"] = @(NSDate.date.timeIntervalSince1970);
    return [self commit:next error:error];
}
- (BOOL)deleteSessions:(NSArray<NSString *> *)identifiers error:(NSError **)error {
    NSMutableDictionary *next = [self nextState];
    for (NSString *identifier in identifiers) {
        [next[@"sessions"] removeObjectForKey:identifier]; [next[@"messages"] removeObjectForKey:identifier];
    }
    return [self commit:next error:error];
}
- (NSArray<NSDictionary *> *)messages:(NSString *)session { return [_state[@"messages"][session] copy] ?: @[]; }
- (NSDictionary *)message:(NSNumber *)identifier session:(NSString *)session {
    for (NSDictionary *message in [self messages:session]) if ([message[@"message_id"] isEqual:identifier]) return [message copy];
    return nil;
}
- (NSArray<NSDictionary *> *)beginTurn:(NSString *)identifier parent:(NSNumber *)parent prompt:(NSString *)prompt
    thinking:(BOOL)thinking error:(NSError **)error {
    if (![self session:identifier] || (parent && ![self message:parent session:identifier])) {
        if (error) *error = DSStoreError(@"会话或父消息不存在。"); return nil;
    }
    NSMutableDictionary *next = [self nextState];
    NSMutableArray *messages = next[@"messages"][identifier];
    NSMutableArray *created = [NSMutableArray array];
    NSNumber *previous = parent;
    if (prompt != nil) {
        NSNumber *uid = next[@"nextID"]; next[@"nextID"] = @(uid.longLongValue + 1);
        NSDictionary *user = @{@"message_id":uid,@"parent_id":previous ?: NSNull.null,@"role":@"USER",
            @"fragments":@[@{@"id":uid,@"type":@"REQUEST",@"content":prompt}],@"status":@"FINISHED",
            @"quasi_status":NSNull.null,@"accumulated_token_usage":@0,@"feedback":NSNull.null,
            @"thinking_enabled":@(thinking),@"ban_edit":@NO,@"ban_regenerate":@NO,@"tips":@[],
            @"conversation_mode":@"CHAT",@"search_enabled":@NO,@"search_triggered":@NO,@"extra_search_providers":@[]};
        [messages addObject:[user mutableCopy]]; [created addObject:user]; previous = uid;
    }
    NSNumber *aid = next[@"nextID"]; next[@"nextID"] = @(aid.longLongValue + 1);
    NSMutableDictionary *assistant = [@{@"message_id":aid,@"parent_id":previous ?: NSNull.null,@"role":@"ASSISTANT",
        @"fragments":@[],@"status":@"WIP",@"quasi_status":NSNull.null,@"accumulated_token_usage":@0,
        @"feedback":NSNull.null,@"thinking_enabled":@(thinking),@"ban_edit":@NO,@"ban_regenerate":@NO,@"tips":@[],
        @"conversation_mode":@"CHAT",@"search_enabled":@NO,@"search_triggered":@NO,@"extra_search_providers":@[]} mutableCopy];
    [messages addObject:assistant]; [created addObject:assistant];
    NSMutableDictionary *session = next[@"sessions"][identifier];
    session[@"is_empty"] = @NO; session[@"current_message_id"] = aid;
    session[@"updated_at"] = @(NSDate.date.timeIntervalSince1970);
    if ([session[@"title"] isEqual:@"新对话"] && prompt.length) {
        NSRange range = [prompt rangeOfComposedCharacterSequencesForRange:NSMakeRange(0,MIN((NSUInteger)32,prompt.length))];
        session[@"title"] = [prompt substringWithRange:range];
    }
    return [self commit:next error:error] ? created : nil;
}
- (NSArray<NSDictionary *> *)apiHistory:(NSString *)session endingAt:(NSNumber *)identifier error:(NSError **)error {
    NSMutableArray *history = [NSMutableArray array]; NSMutableSet *seen = [NSMutableSet set];
    while (identifier != nil) {
        if ([seen containsObject:identifier]) { if (error) *error = DSStoreError(@"消息分支包含循环。"); return nil; }
        [seen addObject:identifier];
        NSDictionary *message = [self message:identifier session:session];
        if (!message) { if (error) *error = DSStoreError(@"消息分支缺失，未发送不完整上下文。"); return nil; }
        NSMutableString *content = [NSMutableString string];
        for (NSDictionary *fragment in message[@"fragments"]) {
            if (([fragment[@"type"] isEqual:@"REQUEST"] || [fragment[@"type"] isEqual:@"RESPONSE"]) &&
                [fragment[@"content"] isKindOfClass:NSString.class]) [content appendString:fragment[@"content"]];
        }
        if (content.length) [history insertObject:@{@"role":[message[@"role"] isEqual:@"USER"] ? @"user" : @"assistant",@"content":content} atIndex:0];
        id parent = message[@"parent_id"]; identifier = [parent isKindOfClass:NSNumber.class] ? parent : nil;
    }
    return history;
}
- (BOOL)updateMessage:(NSNumber *)identifier session:(NSString *)session values:(NSDictionary *)values error:(NSError **)error {
    NSMutableDictionary *next = [self nextState];
    for (NSMutableDictionary *message in next[@"messages"][session]) {
        if (![message[@"message_id"] isEqual:identifier]) continue;
        for (NSString *key in @[@"fragments",@"status",@"feedback",@"accumulated_token_usage"])
            if (values[key]) message[key] = values[key];
        return [self commit:next error:error];
    }
    if (error) *error = DSStoreError(@"消息不存在。"); return NO;
}
@end
