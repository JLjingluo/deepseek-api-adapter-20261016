#import "DSStreamDecoder.h"
#include <string.h>

static const NSUInteger DSStreamLimit = 4 * 1024 * 1024;
@implementation DSStreamDecoder {
    NSMutableData *_line;
    NSMutableData *_event;
    NSString *_finishReason;
    BOOL _terminal, _skipLF, _firstLine, _hasData;
}
- (instancetype)init {
    if ((self = [super init])) {
        _line = [NSMutableData data]; _event = [NSMutableData data]; _firstLine = YES;
    }
    return self;
}
- (BOOL)terminal { return _terminal; }
- (void)fail:(NSString *)message {
    if (_terminal) return;
    _terminal = YES;
    [_line setLength:0]; [_event setLength:0];
    if (self.onError) self.onError([NSError errorWithDomain:@"DSAPI.Stream" code:1
        userInfo:@{NSLocalizedDescriptionKey:message}]);
}
- (void)finish {
    if (_terminal) return;
    _terminal = YES;
    if (self.onFinish) self.onFinish(_finishReason ?: @"stop");
}
- (void)dispatchEvent {
    if (!_hasData || _terminal) return;
    _hasData = NO;
    NSString *text = [[NSString alloc] initWithData:_event encoding:NSUTF8StringEncoding];
    [_event setLength:0];
    if (!text) { [self fail:@"Invalid UTF-8 in SSE event"]; return; }
    if ([text isEqualToString:@"[DONE]"]) { [self finish]; return; }
    id object = [NSJSONSerialization JSONObjectWithData:[text dataUsingEncoding:NSUTF8StringEncoding]
        options:0 error:NULL];
    if (![object isKindOfClass:NSDictionary.class]) {
        [self fail:@"Expected a JSON object in SSE event"]; return;
    }
    NSDictionary *chunk = object;
    if ([chunk[@"usage"] isKindOfClass:NSDictionary.class] && self.onUsage) self.onUsage(chunk[@"usage"]);
    if (chunk[@"error"] && chunk[@"error"] != NSNull.null) {
        [self fail:@"The API returned an error event"]; return;
    }
    id choices = chunk[@"choices"];
    if (![choices isKindOfClass:NSArray.class]) {
        [self fail:@"Missing choices array in API stream"]; return;
    }
    for (id value in choices) {
        if (![value isKindOfClass:NSDictionary.class]) {
            [self fail:@"Invalid choice in API stream"]; return;
        }
        NSDictionary *choice = value;
        id index = choice[@"index"];
        if (![index isKindOfClass:NSNumber.class]) {
            [self fail:@"Missing choice index in API stream"]; return;
        }
        if ([index integerValue] != 0) continue;
        id delta = choice[@"delta"];
        if (delta && delta != NSNull.null && ![delta isKindOfClass:NSDictionary.class]) {
            [self fail:@"Invalid delta in API stream"]; return;
        }
        if (![delta isKindOfClass:NSDictionary.class]) delta = @{};
        if (delta[@"tool_calls"] || delta[@"function_call"]) {
            [self fail:@"Tool calls require a separate application adapter"]; return;
        }
        id content = delta[@"content"], reasoning = delta[@"reasoning_content"];
        if ((content && content != NSNull.null && ![content isKindOfClass:NSString.class]) ||
            (reasoning && reasoning != NSNull.null && ![reasoning isKindOfClass:NSString.class])) {
            [self fail:@"Unsupported non-text delta"]; return;
        }
        NSString *body = [content isKindOfClass:NSString.class] ? content : @"";
        NSString *thought = [reasoning isKindOfClass:NSString.class] ? reasoning : @"";
        if ((body.length || thought.length) && self.onDelta) self.onDelta(body, thought);
        id reason = choice[@"finish_reason"];
        if (reason && reason != NSNull.null) {
            if (![reason isKindOfClass:NSString.class]) {
                [self fail:@"Invalid finish reason"]; return;
            }
            if ([reason isEqualToString:@"tool_calls"] || [reason isEqualToString:@"function_call"]) {
                [self fail:@"Tool calls require a separate application adapter"]; return;
            }
            _finishReason = reason;
        }
    }
}
- (void)completeLine {
    NSData *line = [_line copy]; [_line setLength:0];
    const uint8_t *raw = line.bytes; NSUInteger length = line.length;
    if (_firstLine) {
        _firstLine = NO;
        if (length >= 3 && raw[0] == 0xef && raw[1] == 0xbb && raw[2] == 0xbf) {
            raw += 3; length -= 3;
        }
    }
    if (!length) { [self dispatchEvent]; return; }
    if (raw[0] == ':') return;
    if (length >= 5 && memcmp(raw, "data:", 5) == 0) {
        NSUInteger start = length > 5 && raw[5] == ' ' ? 6 : 5;
        if (_event.length + length - start + 1 > DSStreamLimit) {
            [self fail:@"SSE event exceeds the resource limit"]; return;
        }
        if (_hasData) [_event appendBytes:"\n" length:1];
        _hasData = YES;
        [_event appendBytes:raw + start length:length - start];
    }
}
- (void)consume:(NSData *)data {
    if (_terminal) return;
    const uint8_t *bytes = data.bytes;
    for (NSUInteger i = 0; i < data.length && !_terminal; i++) {
        uint8_t byte = bytes[i];
        if (_skipLF) { _skipLF = NO; if (byte == '\n') continue; }
        if (byte == '\r' || byte == '\n') {
            _skipLF = byte == '\r'; [self completeLine];
        } else {
            if (_line.length >= DSStreamLimit) {
                [self fail:@"SSE line exceeds the resource limit"]; return;
            }
            [_line appendBytes:&byte length:1];
        }
    }
}
- (void)endOfInput {
    if (_terminal) return;
    if (_line.length || _hasData) { [self fail:@"Truncated SSE event"]; return; }
    if (_finishReason) [self finish];
    else [self fail:@"Stream ended before a completion marker"];
}
@end
