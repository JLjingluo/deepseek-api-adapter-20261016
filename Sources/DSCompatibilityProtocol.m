#import "DSCompatibilityProtocol.h"
#import "DSLocalStore.h"
#import "DSOpenAIClient.h"
#import <CommonCrypto/CommonDigest.h>
#import "DSVoiceCatalog.h"
#import "DSAttachmentStore.h"
#if DSAPI_RUNTIME_DIAGNOSTICS
extern BOOL DSAPIValidateModelData(const void *,NSInteger,const char *);
#endif

@implementation DSCompatibilityProtocol {
    BOOL _stopped;
    DSAPIConfiguration *_loadedConfiguration;
    DSOpenAIClient *_upstream;
    NSString *_sessionID;
    NSNumber *_assistantID;
    NSMutableString *_text;
    NSMutableString *_thought;
    NSTimeInterval _lastSave;
    dispatch_source_t _heartbeat;
}
static NSMutableDictionary<NSString *,DSCompatibilityProtocol *> *DSActiveStreams(void) {
    static NSMutableDictionary *streams; static dispatch_once_t once;
    dispatch_once(&once, ^{ streams = [NSMutableDictionary dictionary]; }); return streams;
}
 + (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSString *path=request.URL.path;
    // Authentication, account settings and all original services stay native.
    // API mode owns its entire chat namespace, including unsupported chat routes.
    return (DSAPIIsEnabled() || DSAPIHasPendingModeChange()) && ![NSURLProtocol propertyForKey:@"DSAPI.DirectAPI" inRequest:request] &&
        [request.URL.host.lowercaseString isEqual:@"chat.deepseek.com"] &&
        ([path hasPrefix:@"/api/v0/chat/"] || [path hasPrefix:@"/api/v0/chat_session/"] || [path hasPrefix:@"/api/v0/file/"] || [path hasPrefix:@"/api/v0/guest/chat/"] || [path isEqual:@"/api/v0/guest/available"] || [path isEqual:@"/api/v0/users/create_guest_challenge"]);
}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    NSString *path=self.request.URL.path;
    if (!DSAPIHasPendingModeChange() && ([path hasSuffix:@"/chat/completion"] || [path hasSuffix:@"/chat/regenerate"] || [path hasSuffix:@"/chat/continue"])) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
            DSAPIConfiguration *configuration=[DSAPIConfiguration loadConfiguration];
            dispatch_async(dispatch_get_main_queue(),^{
                if (!self->_stopped) { self->_loadedConfiguration=configuration; [self route]; }
            });
        });
    } else dispatch_async(dispatch_get_main_queue(), ^{ if (!self->_stopped) [self route]; });
}
- (void)stopLoading {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_stopped) return;
        [self closeHeartbeat];
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
    if ([self.request.URL.path hasPrefix:@"/api/v0/file/"]) [NSUserDefaults.standardUserDefaults setObject:description ?: @"upload failed" forKey:@"DSAPIAdapter.lastAttachmentError"];
    [self closeHeartbeat];
    [_upstream cancel]; _upstream = nil;
    if (_assistantID) [DSActiveStreams() removeObjectForKey:_assistantID.stringValue];
    _stopped = YES;
    [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:@"DSAPI.Compatibility" code:1
        userInfo:@{NSLocalizedDescriptionKey:description}]];
}
- (void)closeHeartbeat {
    if (_heartbeat) { dispatch_source_cancel(_heartbeat); _heartbeat = nil; }
}
- (void)startHeartbeat {
    _heartbeat = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
    dispatch_source_set_timer(_heartbeat,dispatch_time(DISPATCH_TIME_NOW,8*NSEC_PER_SEC),8*NSEC_PER_SEC,NSEC_PER_SEC);
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_heartbeat, ^{
        typeof(self) strong = weakSelf;
        if (!strong || strong->_stopped) return;
        NSData *keepAlive = [@": local-api-keep-alive\n\n" dataUsingEncoding:NSUTF8StringEncoding];
        [strong.client URLProtocol:strong didLoadData:keepAlive];
    });
    dispatch_resume(_heartbeat);
}
- (void)event:(NSString *)name body:(id)body {
    if (_stopped) return;
    NSData *json = [NSJSONSerialization dataWithJSONObject:body ?: @{} options:0 error:NULL];
    if (!json) { [self fail:@"无法编码流式消息。"]; return; }
    #if DSAPI_RUNTIME_DIAGNOSTICS
    NSString *type=[@{@"ready":@"ServerModels.Completion.ReadyChunk",@"title":@"ServerModels.Completion.TitleChunk",@"delta":@"ServerModels.POV",@"finish":@"ServerModels.Completion.FinishChunk"} objectForKey:name];
    if (type) [NSUserDefaults.standardUserDefaults setBool:DSAPIValidateModelData(json.bytes,json.length,type.UTF8String)
        forKey:[@"DSAPIAdapter.actualWireValid." stringByAppendingString:name]];
    #endif
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
    if (DSAPIHasPendingModeChange()) { [self fail:@"服务模式已保存，请关闭并重新打开应用后再发送；本次请求未发送到原服务器或 API。"]; return; }
    NSString *requestPath=self.request.URL.path;
    if ([requestPath hasSuffix:@"/file/upload_file"]) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
            NSError *error=nil; NSDictionary *file=[DSAttachmentStore.shared importRequest:self.request error:&error];
            dispatch_async(dispatch_get_main_queue(),^{
                if (self->_stopped) return;
                if (file) {
                    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"DSAPIAdapter.lastAttachmentError"];
                    [NSUserDefaults.standardUserDefaults setObject:@{@"bytes":file[@"file_size"],@"mime":file[@"mime"]} forKey:@"DSAPIAdapter.lastAttachmentImport"];
                    [self json:file];
                } else [self fail:error.localizedDescription ?: @"无法读取附件。"]; });
        }); return;
    }
    if ([requestPath containsString:@"/file/local/"]) {
        NSString *identifier=requestPath.lastPathComponent; NSDictionary *file=[DSAttachmentStore.shared file:identifier];
        NSData *data=file ? [DSAttachmentStore.shared data:identifier] : nil;
        if (!data) { [self fail:@"本地附件不存在。"]; return; }
        [self responseType:file[@"mime"] ?: @"application/octet-stream"];
        [self.client URLProtocol:self didLoadData:data]; _stopped=YES; [self.client URLProtocolDidFinishLoading:self]; return;
    }
    NSDictionary *p = [self parameters];
    if (!p) { [self fail:@"请求体无效或超过本地资源限制。"]; return; }
    NSString *path = self.request.URL.path;
    [NSUserDefaults.standardUserDefaults setObject:path forKey:@"DSAPIAdapter.lastLocalRoute"];
    #if DSAPI_RUNTIME_DIAGNOSTICS
    if ([path hasSuffix:@"/chat/completion"] || [path hasSuffix:@"/chat/regenerate"] || [path hasSuffix:@"/chat/continue"]) {
        NSMutableDictionary *summary=[@{@"path":path,@"keys":[p.allKeys sortedArrayUsingSelector:@selector(compare:)],
            @"prompt_length":@([p[@"prompt"] isKindOfClass:NSString.class] ? [p[@"prompt"] length] : 0)} mutableCopy];
        for (NSString *key in @[@"action",@"parent_message_id",@"message_id",@"child_message_id",@"thinking_enabled"])
            if ([p[key] isKindOfClass:NSString.class] || [p[key] isKindOfClass:NSNumber.class]) summary[key]=p[key];
        [NSUserDefaults.standardUserDefaults setObject:summary forKey:@"DSAPIAdapter.lastChatRequestSummary"];
    }
    #endif
    DSLocalStore *store = DSLocalStore.shared;
    if ([path hasSuffix:@"/file/fetch_files"]) {
        NSArray *ids=[p[@"file_ids"] isKindOfClass:NSArray.class] ? p[@"file_ids"] : @[];
        [self json:@{@"files":[DSAttachmentStore.shared files:ids]}]; return;
    }
    if ([path hasSuffix:@"/file/sign_session_files"]) {
        NSArray *paths=[p[@"paths"] isKindOfClass:NSArray.class] ? p[@"paths"] : @[];
        NSMutableArray *results=[NSMutableArray array];
        for (id value in paths) {
            NSString *path=[value isKindOfClass:NSString.class] ? value : ([value isKindOfClass:NSDictionary.class] ? value[@"path"] : nil);
            if ([path hasPrefix:@"https://chat.deepseek.com/api/v0/file/local/"]) [results addObject:@{@"path":path}];
            else { [self fail:@"该附件属于原服务，请切回原模式查看。"]; return; }
        }
        [self json:@{@"results":results}]; return;
    }
    if ([path hasSuffix:@"/guest/available"]) { [self json:@{@"value":@"true",@"available":@YES}]; return; }
    if ([path containsString:@"/chat/tts/local_demo/"]) {
        NSString *identifier=path.lastPathComponent.stringByRemovingPercentEncoding;
        DSGenerateLocalVoiceDemo(identifier,^(NSData *data,NSError *error) {
            if (self->_stopped) return;
            if (error || !data.length) { [self fail:@"语音试听不可用；请在 iPhone 设置中确认已下载所选音色。"]; return; }
            [self responseType:@"audio/x-caf"]; [self.client URLProtocol:self didLoadData:data];
            self->_stopped=YES; [self.client URLProtocolDidFinishLoading:self];
        }); return;
    }
    if ([path hasSuffix:@"/chat/tts/voices"]) { [self json:DSLocalVoiceConfiguration()]; return; }
    if ([path hasSuffix:@"/chat/tts/voice"]) {
        NSString *identifier=p[@"voice_id"] ?: p[@"voiceID"];
        if (![identifier isKindOfClass:NSString.class] || !DSSelectLocalVoice(identifier)) { [self fail:@"所选设备音色不可用。"]; return; }
        [self json:DSLocalVoiceConfiguration()]; return;
    }
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
        [self json:@{@"cache_control":@"REPLACE",@"chat_messages":[store messages:sid],@"chat_session":session,@"cache_reset_at":@0}];
    } else if ([path hasSuffix:@"/chat/message_feedback"]) {
        NSNumber *mid=[p[@"message_id"] isKindOfClass:NSNumber.class] ? p[@"message_id"] : nil;
        NSString *kind=[p[@"feedback_type"] isKindOfClass:NSString.class] ? [p[@"feedback_type"] uppercaseString] : nil;
        if (!mid || (kind && ![@[@"GOOD",@"BAD",@"NONE"] containsObject:kind])) { [self fail:@"消息反馈无效。"]; return; }
        if (!sid.length) for (NSDictionary *session in store.sessions)
            if ([store message:mid session:session[@"id"]]) { sid=session[@"id"]; break; }
        id feedback=kind && ![kind isEqual:@"NONE"] ? @{@"feedback_type":kind} : NSNull.null;
        if (![store updateMessage:mid session:sid values:@{@"feedback":feedback} error:&error]) [self fail:error.localizedDescription];
        else [self json:@{}];
    } else if ([path hasSuffix:@"/chat/completion"] || [path hasSuffix:@"/chat/regenerate"] || [path hasSuffix:@"/chat/continue"]) {
        [self chat:p];
    } else if ([path hasSuffix:@"/chat/stop_stream"]) {
        NSNumber *mid = [p[@"message_id"] isKindOfClass:NSNumber.class] ? p[@"message_id"] : nil;
        DSCompatibilityProtocol *active = DSActiveStreams()[mid.stringValue ?: @""];
        if (active) [active finishStream:@"INCOMPLETE" error:nil];
        [self json:@{}];
    } else if ([path hasSuffix:@"/chat/get_client_streams"]) {
        [self json:@{@"streams":@[]}];
    } else if ([path hasSuffix:@"/chat/create_pow_challenge"] || [path hasSuffix:@"/users/create_guest_challenge"]) {
        // An entirely local compatibility handshake; no official service is contacted.
        long long expires = (long long)((NSDate.date.timeIntervalSince1970+3600)*1000);
        NSString *salt = @"local-api-handshake";
        NSString *prefix = [NSString stringWithFormat:@"%@_%lld_0",salt,expires];
        NSData *input = [prefix dataUsingEncoding:NSUTF8StringEncoding]; uint8_t digest[CC_SHA256_DIGEST_LENGTH];
        CC_SHA256(input.bytes,(CC_LONG)input.length,digest);
        NSMutableString *hex = [NSMutableString string]; for (NSUInteger i=0;i<sizeof(digest);i++) [hex appendFormat:@"%02x",digest[i]];
        [self json:@{([path hasSuffix:@"/users/create_guest_challenge"] ? @"guest_challenge" : @"challenge"):@{@"algorithm":@"SHA-256",@"challenge":hex,@"salt":salt,@"signature":@"local-only",
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
    // The native root owns its response object. Merge a root snapshot so the
    // original POV layer updates that object instead of assigning its property.
    [self event:@"delta" body:@{@"p":@"",@"o":@"SET",@"v":@{@"response":message}}];
}
- (void)finishStream:(NSString *)status error:(NSError *)error {
    if (_stopped) return;
    [self closeHeartbeat];
    [self saveStreamStatus:status];
    if (error) {
        [self event:@"toast" body:@{@"type":@"error",@"content":error.localizedDescription,@"finish_reason":@"error"}];
    }
    [self sendMessageStatus:status]; [self event:@"finish" body:@{}];
    if (_stopped) return;
    _stopped = YES;
    DSOpenAIClient *upstream = _upstream; _upstream = nil; [upstream cancel];
    [DSActiveStreams() removeObjectForKey:_assistantID.stringValue];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)chat:(NSDictionary *)p {
    DSAPIConfiguration *config = _loadedConfiguration;
    if (!config.apiKey.length) { [self fail:@"请先在 API 设置中填写 Base URL、API Key 和模型名。"]; return; }
    NSArray *fileIDs=[p[@"ref_file_ids"] isKindOfClass:NSArray.class] ? p[@"ref_file_ids"] : @[];
    NSArray *files=[DSAttachmentStore.shared files:fileIDs];
    NSError *attachmentError=nil;
    if (files.count!=fileIDs.count || ![DSAttachmentStore.shared contentParts:files error:&attachmentError]) {
        [self fail:attachmentError.localizedDescription ?: @"附件不在 API 本地存储中，请重新添加；未发送缺失的文件。"]; return;
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
    if (!prompt && files.count) prompt=@"";
    NSString *path=self.request.URL.path;
    NSDictionary *parentMessage=parent ? [DSLocalStore.shared message:parent session:sid] : nil;
    BOOL retry=[path hasSuffix:@"/chat/regenerate"] || [p[@"action"] isEqual:@"retry"] ||
        (!prompt && ![path hasSuffix:@"/chat/continue"] && [parentMessage[@"role"] isEqual:@"ASSISTANT"]);
    if (retry) {
        NSNumber *target=parent ?: ([p[@"message_id"] isKindOfClass:NSNumber.class] ? p[@"message_id"] : nil);
        if (!target && [p[@"child_message_id"] isKindOfClass:NSNumber.class]) target=p[@"child_message_id"];
        NSDictionary *selected=target ? [DSLocalStore.shared message:target session:sid] : nil;
        if ([selected[@"role"] isEqual:@"ASSISTANT"]) target=[selected[@"parent_id"] isKindOfClass:NSNumber.class] ? selected[@"parent_id"] : nil;
        NSDictionary *question=target ? [DSLocalStore.shared message:target session:sid] : nil;
        if (![question[@"role"] isEqual:@"USER"]) { [self fail:@"待重新生成的原问题不存在。"]; return; }
        parent=target; prompt=nil;
    }
    if (!parent && [p[@"message_id"] isKindOfClass:NSNumber.class]) {
        NSDictionary *selected = [DSLocalStore.shared message:p[@"message_id"] session:sid];
        if (!selected) { [self fail:@"待重试或编辑的消息不存在。"]; return; }
        if ([selected[@"role"] isEqual:@"ASSISTANT"]) {
            id userID = selected[@"parent_id"];
            NSDictionary *user = [userID isKindOfClass:NSNumber.class] ? [DSLocalStore.shared message:userID session:sid] : nil;
            parent = prompt ? ([user[@"parent_id"] isKindOfClass:NSNumber.class] ? user[@"parent_id"] : nil) : userID;
        } else {
            parent = prompt ? ([selected[@"parent_id"] isKindOfClass:NSNumber.class] ? selected[@"parent_id"] : nil) : selected[@"message_id"];
        }
    }
    if (!parent && !prompt && [p[@"child_message_id"] isKindOfClass:NSNumber.class]) parent = p[@"child_message_id"];
    if (!prompt && !parent) { [self fail:@"缺少消息内容或父消息。"]; return; }
    NSError *error = nil;
    NSArray *turn = [DSLocalStore.shared beginTurn:sid parent:parent prompt:prompt thinking:[p[@"thinking_enabled"] boolValue] error:&error];
    if (!turn) { [self fail:error.localizedDescription]; return; }
    NSDictionary *assistant = turn.lastObject;
    NSNumber *requestID = assistant[@"parent_id"];
    if (files.count && prompt!=nil) {
        NSDictionary *user=[DSLocalStore.shared message:requestID session:sid];
        NSMutableArray *fragments=[user[@"fragments"] mutableCopy];
        [fragments addObject:@{@"id":@(requestID.longLongValue+1000000000),@"type":@"FILE",@"files":files}];
        if (![DSLocalStore.shared updateMessage:requestID session:sid values:@{@"fragments":fragments} error:&error]) { [self fail:error.localizedDescription]; return; }
    }
    NSArray *history = [DSLocalStore.shared apiHistory:sid endingAt:requestID error:&error];
    if (!history) { [self fail:error.localizedDescription]; return; }
    _sessionID = sid; _assistantID = assistant[@"message_id"];
    _text = [NSMutableString string]; _thought = [NSMutableString string];
    DSActiveStreams()[_assistantID.stringValue] = self;
    [self responseType:@"text/event-stream; charset=utf-8"];
    [self startHeartbeat];
    NSMutableDictionary *ready=[@{@"model_type":p[@"model_type"] ?: @"default",
        @"request_message_id":requestID ?: @0,@"response_message_id":_assistantID,@"ban_edit":@NO} mutableCopy];
    if (prompt) ready[@"request_content"]=prompt;
    [self event:@"ready" body:ready];
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
