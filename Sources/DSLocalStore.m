#import "DSLocalStore.h"
#import "DSAttachmentStore.h"
#import <TargetConditionals.h>
#include <limits.h>

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
- (BOOL)adoptCloudOwner:(NSString *)oldOwner asOwner:(NSString *)owner error:(NSError **)error {
    if (!oldOwner.length || !owner.length || [oldOwner isEqual:owner]) return YES;
    NSString *claimed=_state[@"cloud_owner_aliases"][oldOwner];
    if (claimed && ![claimed isEqual:owner]) { if (error) *error=DSStoreError(@"原账号缓存标识已属于其他账号。"); return NO; }
    NSMutableDictionary *next=nil;
    for (NSDictionary *session in [_state[@"sessions"] allValues]) if ([session[@"_ds_cloud_owner"] isEqual:oldOwner]) {
        if (!next) next=[self nextState];
        next[@"sessions"][session[@"id"]][@"_ds_cloud_owner"]=owner;
    }
    if (!next && claimed) return YES;
    if (!next) next=[self nextState];
    if (!next[@"cloud_owner_aliases"]) next[@"cloud_owner_aliases"]=[NSMutableDictionary dictionary];
    next[@"cloud_owner_aliases"][oldOwner]=owner;
    return [self commit:next error:error];
}
- (BOOL)importCloudSessions:(NSArray<NSDictionary *> *)sessions owner:(NSString *)owner error:(NSError **)error {
    NSMutableDictionary *next=[self nextState];
    for (id value in sessions) {
        if (![value isKindOfClass:NSDictionary.class] || ![value[@"id"] isKindOfClass:NSString.class] || ![value[@"id"] length]) { if (error) *error=DSStoreError(@"原账号会话格式无效。"); return NO; }
        NSString *identifier=value[@"id"]; NSMutableDictionary *old=next[@"sessions"][identifier];
        if (old[@"_ds_cloud_owner"] && ![old[@"_ds_cloud_owner"] isEqual:owner]) { if (error) *error=DSStoreError(@"会话属于不同账号，未合并。"); return NO; }
        NSMutableDictionary *session=[value mutableCopy]; session[@"_ds_cloud_owner"]=owner;
        if ([old[@"_api_local_turns"] boolValue]) {
            for (NSString *key in @[@"updated_at",@"current_message_id",@"is_empty",@"_api_local_turns"]) if (old[key]) session[key]=old[key];
        }
        next[@"sessions"][identifier]=session;
        if (!next[@"messages"][identifier]) next[@"messages"][identifier]=[NSMutableArray array];
    }
    return [self commit:next error:error];
}
- (BOOL)importCloudHistory:(NSDictionary *)session messages:(NSArray<NSDictionary *> *)incoming owner:(NSString *)owner error:(NSError **)error {
    if (![session isKindOfClass:NSDictionary.class] || ![incoming isKindOfClass:NSArray.class] || ![session[@"id"] isKindOfClass:NSString.class]) { if (error) *error=DSStoreError(@"原账号历史格式无效。"); return NO; }
    // Validate before mutating storage; retain every API branch when cloud
    // history is refreshed rather than replacing the locally continued thread.
    long long highest=1000000000000LL;
    for (id message in incoming) {
        if (![message isKindOfClass:NSDictionary.class] || ![message[@"message_id"] isKindOfClass:NSNumber.class] || ![message[@"fragments"] isKindOfClass:NSArray.class] || ![@[@"USER",@"ASSISTANT"] containsObject:message[@"role"]]) { if (error) *error=DSStoreError(@"原账号消息格式无效，未覆盖本地记录。"); return NO; }
        highest=MAX(highest,[message[@"message_id"] longLongValue]);
        if (highest==LLONG_MAX) { if (error) *error=DSStoreError(@"消息编号超出可用范围。"); return NO; }
    }
    if (![self importCloudSessions:@[session] owner:owner error:error]) return NO;
    NSMutableDictionary *next=[self nextState]; NSString *identifier=session[@"id"];
    NSMutableDictionary *indexed=[NSMutableDictionary dictionary];
    for (NSDictionary *message in next[@"messages"][identifier]) indexed[[message[@"message_id"] stringValue]]=[message mutableCopy];
    for (NSDictionary *message in incoming) {
        NSString *key=[message[@"message_id"] stringValue];
        if (![indexed[key][@"_api_local"] boolValue]) indexed[key]=[message mutableCopy];
    }
    NSArray *ordered=[indexed.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b) { return [a[@"message_id"] compare:b[@"message_id"]]; }];
    next[@"messages"][identifier]=[ordered mutableCopy];
    next[@"sessions"][identifier][@"_ds_cloud_loaded"]=@YES;
    next[@"nextID"]=@(MAX([next[@"nextID"] longLongValue],highest+1));
    return [self commit:next error:error];
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
        NSDictionary *user = @{@"_api_local":@YES,@"message_id":uid,@"parent_id":previous ?: NSNull.null,@"role":@"USER",
            @"fragments":@[@{@"id":uid,@"type":@"REQUEST",@"content":prompt}],@"status":@"FINISHED",
            @"quasi_status":@"FINISHED",@"accumulated_token_usage":@0,@"feedback":NSNull.null,
            @"thinking_enabled":@(thinking),@"ban_edit":@NO,@"ban_regenerate":@NO,@"tips":@[],
            @"conversation_mode":@"CHAT",@"search_enabled":@NO,@"search_triggered":@NO,@"extra_search_providers":@[]};
        [messages addObject:[user mutableCopy]]; [created addObject:user]; previous = uid;
    }
    NSNumber *aid = next[@"nextID"]; next[@"nextID"] = @(aid.longLongValue + 1);
    NSMutableDictionary *assistant = [@{@"_api_local":@YES,@"message_id":aid,@"parent_id":previous ?: NSNull.null,@"role":@"ASSISTANT",
        @"fragments":@[],@"status":@"WIP",@"quasi_status":@"WIP",@"accumulated_token_usage":@0,
        @"feedback":NSNull.null,@"thinking_enabled":@(thinking),@"ban_edit":@NO,@"ban_regenerate":@NO,@"tips":@[],
        @"conversation_mode":@"CHAT",@"search_enabled":@NO,@"search_triggered":@NO,@"extra_search_providers":@[]} mutableCopy];
    [messages addObject:assistant]; [created addObject:assistant];
    NSMutableDictionary *session = next[@"sessions"][identifier];
    session[@"_api_local_turns"] = @YES;
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
        NSMutableArray *files=[NSMutableArray array];
        for (NSDictionary *fragment in message[@"fragments"]) {
            if ([fragment[@"type"] isEqual:@"FILE"] && [fragment[@"files"] isKindOfClass:NSArray.class]) [files addObjectsFromArray:fragment[@"files"]];
            if (([fragment[@"type"] isEqual:@"REQUEST"] || [fragment[@"type"] isEqual:@"RESPONSE"]) &&
                [fragment[@"content"] isKindOfClass:NSString.class]) [content appendString:fragment[@"content"]];
        }
        if (files.count && [message[@"role"] isEqual:@"USER"]) {
            NSArray *attachments=[DSAttachmentStore.shared contentParts:files error:error]; if (!attachments) return nil;
            NSMutableArray *parts=[NSMutableArray array];
            if (content.length) [parts addObject:@{@"type":@"text",@"text":content}];
            [parts addObjectsFromArray:attachments];
            [history insertObject:@{@"role":@"user",@"content":parts} atIndex:0];
        } else if (content.length) [history insertObject:@{@"role":[message[@"role"] isEqual:@"USER"] ? @"user" : @"assistant",@"content":content} atIndex:0];
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
        if (values[@"status"]) message[@"quasi_status"] = values[@"status"];
        return [self commit:next error:error];
    }
    if (error) *error = DSStoreError(@"消息不存在。"); return NO;
}
@end
