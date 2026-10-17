#import "DSCompatibilityProtocol.h"
#import "DSLocalStore.h"
#import "DSOpenAIClient.h"
#import <CommonCrypto/CommonDigest.h>

@implementation DSCompatibilityProtocol {
    BOOL _stopped;
    DSOpenAIClient *_upstream;
    NSString *_sessionID;
    NSNumber *_assistantID;
    NSMutableString *_text;
    NSMutableString *_thought;
    NSTimeInterval _lastSave;
}
static NSMutableDictionary<NSString *,DSCompatibilityProtocol *> *DSActiveStreams(void) {
    static NSMutableDictionary *streams; static dispatch_once_t once;
    dispatch_once(&once, ^{ streams = [NSMutableDictionary dictionary]; }); return streams;
}
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    return ![NSURLProtocol propertyForKey:@"DSAPI.DirectAPI" inRequest:request] &&
        [request.URL.host.lowercaseString isEqual:@"chat.deepseek.com"] && [request.URL.path hasPrefix:@"/api/"];
}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    dispatch_async(dispatch_get_main_queue(), ^{ if (!self->_stopped) [self route]; });
}
- (void)stopLoading {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_stopped) return;
        [self saveStreamStatus:@"INCOMPLETE"];
        self->_stopped = YES;
        [self->_upstream cancel]; self->_upstream = nil;
        if (self->_assistantID) [DSActiveStreams() removeObjectForKey:self->_assistantID.stringValue];
    });
}
- (void)responseType:(NSString *)type {
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:200
        HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":type,@"Cache-Control":@"no-store",@"x-trace-id":@"local-api"}];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
}
- (void)json:(id)payload {
    if (_stopped) return;
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"code":@0,@"msg":@"",@"data":@{
        @"biz_code":@0,@"biz_msg":@"",@"biz_data":payload ?: @{}}} options:0 error:NULL];
    [self responseType:@"application/json; charset=utf-8"];
    [self.client URLProtocol:self didLoadData:data];
    _stopped = YES; [self.client URLProtocolDidFinishLoading:self];
}
- (void)fail:(NSString *)description {
    if (_stopped) return;
    _stopped = YES;
    [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:@"DSAPI.Compatibility" code:1
        userInfo:@{NSLocalizedDescriptionKey:description}]];
}
- (void)event:(NSString *)name body:(id)body {
    if (_stopped) return;
    NSData *json = [NSJSONSerialization dataWithJSONObject:body ?: @{} options:0 error:NULL];
    if (!json) { [self fail:@"无法编码流式消息。"]; return; }
    NSString *value = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    NSString *sse = [NSString stringWithFormat:@"event: %@\ndata: %@\n\n",name,value];
    [self.client URLProtocol:self didLoadData:[sse dataUsingEncoding:NSUTF8StringEncoding]];
}
- (NSDictionary *)parameters {
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    for (NSURLQueryItem *item in [NSURLComponents componentsWithURL:self.request.URL resolvingAgainstBaseURL:NO].queryItems)
        if (item.value) values[item.name] = item.value;
    NSData *body = self.request.HTTPBody;
    if (body.length > 8*1024*1024) return nil;
    if (!body && self.request.HTTPBodyStream) {
        NSInputStream *stream = self.request.HTTPBodyStream; [stream open];
        NSMutableData *buffer = [NSMutableData data]; uint8_t bytes[4096]; NSInteger length;
        while ((length = [stream read:bytes maxLength:sizeof(bytes)]) > 0) {
            [buffer appendBytes:bytes length:(NSUInteger)length];
            if (buffer.length > 8*1024*1024) { [stream close]; return nil; }
        }
        [stream close]; if (length < 0) return nil; body = buffer;
    }
    if (body.length) {
        id value = [NSJSONSerialization JSONObjectWithData:body options:0 error:NULL];
        if (![value isKindOfClass:NSDictionary.class]) return nil;
        [values addEntriesFromDictionary:value];
    }
    return values;
}
- (NSDictionary *)localUser {
    return @{@"id":@"local-api",@"token":@"local-api-no-official-account",@"email":@"",@"mobile_number":@"",
        @"area_code":@"",@"status":@0,@"id_profiles":@[],@"chat":@{@"is_muted":@0},
        @"has_legacy_chat_history":@NO,@"need_birthday":@NO,@"is_mainland":@NO};
}
- (void)route {
    NSDictionary *p = [self parameters];
    if (!p) { [self fail:@"请求体无效或超过本地资源限制。"]; return; }
    NSString *path = self.request.URL.path;
    [NSUserDefaults.standardUserDefaults setObject:path forKey:@"DSAPIAdapter.lastLocalRoute"];
    DSLocalStore *store = DSLocalStore.shared;
    NSError *error = nil;
    NSString *sid = [p[@"chat_session_id"] isKindOfClass:NSString.class] ? p[@"chat_session_id"] : @"";
    if ([path hasSuffix:@"/chat_session/create"]) {
        NSDictionary *session = [store createSession:[p[@"model_type"] isKindOfClass:NSString.class] ? p[@"model_type"] : @"default" error:&error];
        if (!session) { [self fail:error.localizedDescription]; return; }
        NSMutableDictionary *result = [session mutableCopy]; result[@"chat_session"] = session; [self json:result];
    } else if ([path hasSuffix:@"/chat_session/fetch_page"]) {
        [self json:@{@"chat_sessions":store.sessions,@"has_more":@NO}];
    } else if ([path hasSuffix:@"/chat_session/delete_all"]) {
        NSMutableArray *ids = [NSMutableArray array]; for (NSDictionary *s in store.sessions) [ids addObject:s[@"id"]];
        if (![store deleteSessions:ids error:&error]) [self fail:error.localizedDescription]; else [self json:@{}];
    } else if ([path hasSuffix:@"/chat_session/delete"]) {
        NSArray *ids = [p[@"chat_session_ids"] isKindOfClass:NSArray.class] ? p[@"chat_session_ids"] : (sid.length ? @[sid] : @[]);
        if (![store deleteSessions:ids error:&error]) [self fail:error.localizedDescription]; else [self json:@{}];
    } else if ([path hasSuffix:@"/chat_session/update_title"]) {
        if (![p[@"title"] isKindOfClass:NSString.class]) { [self fail:@"会话标题无效。"]; return; }
        if (![store updateSession:sid values:@{@"title":p[@"title"],@"title_type":@"USER"} error:&error]) [self fail:error.localizedDescription];
        else [self json:[store session:sid]];
    } else if ([path hasSuffix:@"/chat_session/batch_update_pinned"]) {
        NSMutableArray *updated = [NSMutableArray array];
        for (NSString *identifier in [p[@"chat_session_ids"] isKindOfClass:NSArray.class] ? p[@"chat_session_ids"] : @[]) {
            if (![identifier isKindOfClass:NSString.class] || ![store updateSession:identifier values:@{@"pinned":@([p[@"pinned"] boolValue])} error:&error]) {
                [self fail:error.localizedDescription ?: @"置顶会话无效。"]; return;
            }
            [updated addObject:@{@"id":identifier,@"updated_at":[store session:identifier][@"updated_at"]}];
        }
        [self json:@{@"updated_chat_sessions":updated,@"illegal_chat_session_ids":@[],@"ignored_chat_session_ids":@[]}];
    } else if ([path hasSuffix:@"/chat/history_messages"]) {
        NSDictionary *session = [store session:sid];
        if (!session) { [self fail:@"本地会话不存在。"]; return; }
        [self json:@{@"cache_control":@"replace",@"chat_messages":[store messages:sid],@"chat_session":session,@"cache_reset_at":@0}];
    } else if ([path hasSuffix:@"/chat/completion"] || [path hasSuffix:@"/chat/regenerate"] || [path hasSuffix:@"/chat/continue"]) {
        [self chat:p];
    } else if ([path hasSuffix:@"/chat/stop_stream"]) {
        NSNumber *mid = [p[@"message_id"] isKindOfClass:NSNumber.class] ? p[@"message_id"] : nil;
        DSCompatibilityProtocol *active = DSActiveStreams()[mid.stringValue ?: @""];
        if (active) [active finishStream:@"INCOMPLETE" error:nil];
        [self json:@{}];
    } else if ([path hasSuffix:@"/chat/get_client_streams"]) {
        [self json:@{@"streams":@[]}];
    } else if ([path hasSuffix:@"/chat/create_pow_challenge"]) {
        // An entirely local compatibility handshake; no official service is contacted.
        long long expires = (long long)((NSDate.date.timeIntervalSince1970+3600)*1000);
        NSString *salt = @"local-api-handshake";
        NSString *prefix = [NSString stringWithFormat:@"%@_%lld_0",salt,expires];
        NSData *input = [prefix dataUsingEncoding:NSUTF8StringEncoding]; uint8_t digest[CC_SHA256_DIGEST_LENGTH];
        CC_SHA256(input.bytes,(CC_LONG)input.length,digest);
        NSMutableString *hex = [NSMutableString string]; for (NSUInteger i=0;i<sizeof(digest);i++) [hex appendFormat:@"%02x",digest[i]];
        [self json:@{@"challenge":@{@"algorithm":@"SHA256",@"challenge":hex,@"salt":salt,@"signature":@"local-only",
            @"difficulty":@0,@"expire_at":@(expires),@"expire_after":@3600000}}];
    } else if ([path hasSuffix:@"/users/current"]) {
        NSMutableDictionary *u = [[self localUser] mutableCopy]; u[@"user"] = [self localUser]; [self json:u];
    } else if ([path hasSuffix:@"/users/auth_token/check_device"]) {
        [self json:@{@"rotate":NSNull.null}];
    } else if ([path hasSuffix:@"/client/settings"]) {
        [self json:@{@"version":@0,@"settings":@{}}];
    } else if ([path hasSuffix:@"/index/prepare"]) {
        [self json:@{@"user":[self localUser],@"settings":@{},@"chat_sessions":store.sessions}];
    } else if ([path hasSuffix:@"/users/settings"]) {
        [self json:@{}];
    } else if ([path hasSuffix:@"/client/settings/report"] || [path hasSuffix:@"/users/update_settings"] ||
               [path hasSuffix:@"/chat/message_feedback"]) {
        [self json:@{}];
    } else if ([path hasSuffix:@"/check_client_update"]) {
        [self json:@{@"need_update":@NO,@"force_update":@NO}];
    } else if ([path hasSuffix:@"/ip_to_country_code"]) {
        [self json:@{@"country_code":@"US"}];
    } else {
        // Unknown routes never fall back to the original service.
        [self fail:@"该功能没有配置对应的 API 服务；未连接原应用服务器。"];
    }
}
- (NSArray *)fragments {
    NSMutableArray *fragments = [NSMutableArray array];
    if (_thought.length) [fragments addObject:@{@"id":@1,@"type":@"THINK",@"content":[_thought copy],
        @"elapsed_secs":@0,@"references":@[],@"stage_id":@0}];
    if (_text.length) [fragments addObject:@{@"id":@2,@"type":@"RESPONSE",@"content":[_text copy],@"references":@[],@"stage_id":@0}];
    return fragments;
}
- (void)saveStreamStatus:(NSString *)status {
    if (!_assistantID || !_sessionID) return;
    [DSLocalStore.shared updateMessage:_assistantID session:_sessionID values:@{@"fragments":[self fragments],@"status":status} error:NULL];
}
- (void)sendMessageStatus:(NSString *)status {
    NSMutableDictionary *message = [[DSLocalStore.shared message:_assistantID session:_sessionID] mutableCopy];
    message[@"fragments"] = [self fragments]; message[@"status"] = status; message[@"quasi_status"] = status;
    [self event:@"delta" body:@{@"p":@"response",@"o":@"SET",@"v":message}];
}
- (void)finishStream:(NSString *)status error:(NSError *)error {
    if (_stopped) return;
    [self saveStreamStatus:status];
    if (error) {
        [self event:@"toast" body:@{@"type":@"error",@"content":error.localizedDescription,@"finish_reason":@"error"}];
    }
    [self sendMessageStatus:status]; [self event:@"finish" body:@{}];
    _stopped = YES;
    DSOpenAIClient *upstream = _upstream; _upstream = nil; [upstream cancel];
    [DSActiveStreams() removeObjectForKey:_assistantID.stringValue];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)chat:(NSDictionary *)p {
    DSAPIConfiguration *config = [DSAPIConfiguration load];
    if (!config.apiKey.length) { [self fail:@"请先在 API 设置中填写 Base URL、API Key 和模型名。"]; return; }
    if ([p[@"ref_file_ids"] isKindOfClass:NSArray.class] && [p[@"ref_file_ids"] count]) {
        [self fail:@"当前附件服务尚未接入；没有将附件静默丢弃。"]; return;
    }
    if ([p[@"search_enabled"] boolValue]) {
        [self fail:@"当前 API 未配置联网搜索服务，请关闭搜索后发送。"]; return;
    }
    NSString *sid = [p[@"chat_session_id"] isKindOfClass:NSString.class] ? p[@"chat_session_id"] : @"";
    if (!sid.length) {
        NSError *createError = nil; NSDictionary *session = [DSLocalStore.shared createSession:@"default" error:&createError];
        sid = session[@"id"]; if (!sid) { [self fail:createError.localizedDescription]; return; }
    }
    NSNumber *parent = [p[@"parent_message_id"] isKindOfClass:NSNumber.class] ? p[@"parent_message_id"] : nil;
    NSString *prompt = [p[@"prompt"] isKindOfClass:NSString.class] ? p[@"prompt"] : nil;
    if (!prompt && !parent) { [self fail:@"缺少消息内容或父消息。"]; return; }
    NSError *error = nil;
    NSArray *turn = [DSLocalStore.shared beginTurn:sid parent:parent prompt:prompt thinking:[p[@"thinking_enabled"] boolValue] error:&error];
    if (!turn) { [self fail:error.localizedDescription]; return; }
    NSDictionary *assistant = turn.lastObject;
    NSNumber *requestID = assistant[@"parent_id"];
    NSArray *history = [DSLocalStore.shared apiHistory:sid endingAt:requestID error:&error];
    if (!history) { [self fail:error.localizedDescription]; return; }
    _sessionID = sid; _assistantID = assistant[@"message_id"];
    _text = [NSMutableString string]; _thought = [NSMutableString string];
    DSActiveStreams()[_assistantID.stringValue] = self;
    [self responseType:@"text/event-stream; charset=utf-8"];
    [self event:@"ready" body:@{@"request_content":prompt ?: @"",@"model_type":p[@"model_type"] ?: @"default",
        @"request_message_id":requestID ?: @0,@"response_message_id":_assistantID,@"ban_edit":@NO}];
    [self sendMessageStatus:@"WIP"];
    [self event:@"title" body:@{@"content":[DSLocalStore.shared session:sid][@"title"] ?: @"新对话"}];
    _upstream = [[DSOpenAIClient alloc] initWithConfiguration:config];
    __weak typeof(self) weakSelf = self;
    [_upstream startMessages:history reasoning:[p[@"thinking_enabled"] boolValue]
        delta:^(NSString *text, NSString *thought) {
            typeof(self) strong = weakSelf; if (!strong || strong->_stopped) return;
            [strong->_text appendString:text]; [strong->_thought appendString:thought];
            [strong sendMessageStatus:@"WIP"];
            NSTimeInterval now = NSDate.date.timeIntervalSince1970;
            if (now - strong->_lastSave > 0.5) { [strong saveStreamStatus:@"WIP"]; strong->_lastSave = now; }
        } completion:^(NSString *reason, NSError *streamError) {
            typeof(self) strong = weakSelf; if (!strong || strong->_stopped) return;
            NSString *status = streamError ? @"INCOMPLETE" : ([reason isEqual:@"length"] ? @"CONTEXT_LENGTH_EXCEEDED" :
                ([reason isEqual:@"content_filter"] ? @"CONTENT_FILTER" : @"FINISHED"));
            [strong finishStream:status error:streamError];
        }];
}
@end
