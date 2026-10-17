#import <Foundation/Foundation.h>
#import "DSLocalStore.h"
static void check(BOOL value, NSString *message) {
    if (!value) { fprintf(stderr,"FAIL: %s\n",message.UTF8String); exit(1); }
}
int main(void) {
    @autoreleasepool {
        NSURL *directory = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
        DSLocalStore *store = [[DSLocalStore alloc] initWithDirectory:directory];
        NSError *error = nil;
        NSDictionary *session = [store createSession:@"default" error:&error];
        check(session != nil && error == nil,@"create local session");
        NSString *sid = session[@"id"];
        NSArray *turn = [store beginTurn:sid parent:nil prompt:@"hello" thinking:YES error:&error];
        check(turn.count == 2,@"first turn creates user and assistant");
        NSNumber *firstAssistant = turn.lastObject[@"message_id"];
        check([store updateMessage:firstAssistant session:sid values:@{@"status":@"FINISHED",@"fragments":@[
            @{@"type":@"THINK",@"content":@"private thought"},@{@"type":@"RESPONSE",@"content":@"world"}]} error:&error],@"persist response");
        NSArray *next = [store beginTurn:sid parent:firstAssistant prompt:@"next" thinking:NO error:&error];
        NSArray *history = [store apiHistory:sid endingAt:next.firstObject[@"message_id"] error:&error];
        check(history.count == 3,@"selected history includes previous turn");
        check([history[1][@"content"] isEqual:@"world"],@"reasoning is excluded from replay");
        NSArray *branch = [store beginTurn:sid parent:turn.firstObject[@"message_id"] prompt:nil thinking:NO error:&error];
        check(branch.count == 1,@"regeneration creates an assistant branch");
        NSArray *branchHistory = [store apiHistory:sid endingAt:branch.lastObject[@"parent_id"] error:&error];
        check(branchHistory.count == 1 && [branchHistory[0][@"content"] isEqual:@"hello"],@"sibling branch is excluded");
        check([store updateSession:sid values:@{@"title":@"标题🧠",@"pinned":@YES} error:&error],@"rename and pin");
        DSLocalStore *reopened = [[DSLocalStore alloc] initWithDirectory:directory];
        check([[reopened session:sid][@"title"] isEqual:@"标题🧠"],@"history survives reopen");
        check([reopened messages:sid].count == 5,@"all message branches survive reopen");
        NSUInteger before = [reopened messages:sid].count;
        check([reopened beginTurn:sid parent:@999999 prompt:@"invalid" thinking:NO error:&error] == nil,@"unknown parent rejected");
        check([reopened messages:sid].count == before,@"invalid parent does not mutate history");
        check([reopened deleteSessions:@[sid] error:&error],@"delete local session");
        check([reopened session:sid] == nil && [reopened messages:sid].count == 0,@"delete removes local history");
        [NSFileManager.defaultManager removeItemAtURL:directory error:NULL];
        puts("PASS: persistent conversations, selected branches, reasoning exclusion, rename, pin, deletion");
    }
    return 0;
}
