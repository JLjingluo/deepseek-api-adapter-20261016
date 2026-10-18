#import "DSAttachmentStore.h"
#import <TargetConditionals.h>
#include <string.h>
static const NSUInteger DSFileLimit=20*1024*1024;
static NSError *DSFileError(NSString *text) {
    return [NSError errorWithDomain:@"DSAPI.Attachments" code:1 userInfo:@{NSLocalizedDescriptionKey:text}];
}
static NSString *parameter(NSString *header,NSString *key) {
    for (NSString *part in [header componentsSeparatedByString:@";"]) {
        NSString *value=[part stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSString *prefix=[key stringByAppendingString:@"="];
        if (![value.lowercaseString hasPrefix:prefix]) continue;
        value=[value substringFromIndex:prefix.length];
        if ([value hasPrefix:@"\""] && [value hasSuffix:@"\""] && value.length>=2) value=[value substringWithRange:NSMakeRange(1,value.length-2)];
        return value;
    }
    return nil;
}
@implementation DSAttachmentStore {
    NSURL *_directory;
}
+ (instancetype)shared {
    static DSAttachmentStore *store; static dispatch_once_t once;
    dispatch_once(&once,^{
        NSURL *root=[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
        store=[[self alloc] initWithDirectory:[root URLByAppendingPathComponent:@"DSAPIAdapter/Attachments" isDirectory:YES]];
    }); return store;
}
- (instancetype)initWithDirectory:(NSURL *)directory { if ((self=[super init])) _directory=directory; return self; }
- (NSURL *)URL:(NSString *)identifier suffix:(NSString *)suffix {
    if (![identifier isKindOfClass:NSString.class] || ![identifier hasPrefix:@"api-file-"] || identifier.length>64 ||
        [identifier rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-"] invertedSet]].location!=NSNotFound) return nil;
    return [_directory URLByAppendingPathComponent:[identifier stringByAppendingString:suffix]];
}
- (NSDictionary *)file:(NSString *)identifier {
    NSURL *url=[self URL:identifier suffix:@".json"]; if (!url) return nil;
    NSData *data=[NSData dataWithContentsOfURL:url];
    id value=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}
- (NSArray *)files:(NSArray *)identifiers {
    NSMutableArray *files=[NSMutableArray array];
    for (NSString *identifier in identifiers) { NSDictionary *file=[self file:identifier]; if (file) [files addObject:file]; }
    return files;
}
- (NSData *)data:(NSString *)identifier { NSURL *url=[self URL:identifier suffix:@".bin"]; return url ? [NSData dataWithContentsOfURL:url] : nil; }
- (NSDictionary *)importRequest:(NSURLRequest *)request error:(NSError **)error {
    id upload=[NSURLProtocol propertyForKey:@"DSAPI.UploadData" inRequest:request];
    id fileSource=[NSURLProtocol propertyForKey:@"DSAPI.UploadFileURL" inRequest:request];
    NSData *body=[upload isKindOfClass:NSData.class] ? upload : nil;
    NSInputStream *bodyStream=nil;
    if (!body && [fileSource isKindOfClass:NSURL.class] && [(NSURL *)fileSource isFileURL]) bodyStream=[NSInputStream inputStreamWithURL:fileSource];
    if (!body && !bodyStream) { body=request.HTTPBody; bodyStream=request.HTTPBodyStream; }
    if (!body && bodyStream) {
        NSInputStream *stream=bodyStream; [stream open];
        NSMutableData *bytes=[NSMutableData data]; uint8_t buffer[16384]; NSInteger length=0;
        while ((length=[stream read:buffer maxLength:sizeof(buffer)])>0) {
            [bytes appendBytes:buffer length:length]; if (bytes.length>DSFileLimit+65536) break;
        }
        [stream close]; if (length<0) { if (error) *error=DSFileError(@"读取附件失败。"); return nil; }
        body=bytes;
    }
    if (!body.length || body.length>DSFileLimit+65536) { if (error) *error=DSFileError(@"附件为空或超过 20 MB。"); return nil; }
    NSString *contentType=[request valueForHTTPHeaderField:@"Content-Type"] ?: @"";
    NSString *boundary=parameter(contentType,@"boundary"); NSString *filename=nil; NSData *fileData=nil;
    if (boundary.length && boundary.length<=200) {
        NSData *delimiter=[[@"\r\n--" stringByAppendingString:boundary] dataUsingEncoding:NSUTF8StringEncoding];
        NSData *separator=[@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]; NSUInteger cursor=0;
        while (cursor<body.length) {
            NSRange headers=[body rangeOfData:separator options:0 range:NSMakeRange(cursor,body.length-cursor)];
            if (headers.location==NSNotFound || headers.location-cursor>16384) break;
            NSString *text=[[NSString alloc] initWithData:[body subdataWithRange:NSMakeRange(cursor,headers.location-cursor)] encoding:NSUTF8StringEncoding];
            if (!text) text=[[NSString alloc] initWithData:[body subdataWithRange:NSMakeRange(cursor,headers.location-cursor)] encoding:NSISOLatin1StringEncoding];
            NSUInteger start=NSMaxRange(headers);
            NSRange end=[body rangeOfData:delimiter options:0 range:NSMakeRange(start,body.length-start)];
            if (end.location==NSNotFound) break;
            for (NSString *line in [text componentsSeparatedByString:@"\r\n"]) if ([line.lowercaseString hasPrefix:@"content-disposition:"]) filename=parameter(line,@"filename");
            if (filename.length) { fileData=[body subdataWithRange:NSMakeRange(start,end.location-start)]; break; }
            cursor=NSMaxRange(end);
        }
    }
    if (!filename.length || !fileData.length || fileData.length>DSFileLimit) { if (error) *error=DSFileError(@"附件上传格式无效或文件超过 20 MB。"); return nil; }
    filename=filename.lastPathComponent;
    const unsigned char *bytes=fileData.bytes; NSString *mime=nil;
    if (fileData.length>=8 && !memcmp(bytes,"\x89PNG\r\n\x1a\n",8)) mime=@"image/png";
    else if (fileData.length>=3 && bytes[0]==0xff && bytes[1]==0xd8 && bytes[2]==0xff) mime=@"image/jpeg";
    else if (fileData.length>=6 && (!memcmp(bytes,"GIF87a",6) || !memcmp(bytes,"GIF89a",6))) mime=@"image/gif";
    else if (fileData.length>=12 && !memcmp(bytes,"RIFF",4) && !memcmp(bytes+8,"WEBP",4)) mime=@"image/webp";
    NSString *text=mime ? nil : [[NSString alloc] initWithData:fileData encoding:NSUTF8StringEncoding];
    if (!mime && (!text.length || [text rangeOfString:[NSString stringWithFormat:@"%C",(unichar)0]].location!=NSNotFound)) {
        if (error) *error=DSFileError(@"API 附件目前支持 PNG、JPEG、GIF、WebP 和 UTF-8 文本；该文件没有上传到原服务器。"); return nil;
    }
    if (text.length>1024*1024) { if (error) *error=DSFileError(@"文本附件超过当前 1 MB 文本上限。"); return nil; }
    NSString *identifier=[@"api-file-" stringByAppendingString:NSUUID.UUID.UUIDString]; NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    NSMutableDictionary *file=[@{@"id":identifier,@"file_name":filename,@"file_size":@(fileData.length),@"inserted_at":@(now),@"updated_at":@(now),
        @"from_share":@NO,@"status":@"SUCCESS",@"token_usage":@0,@"is_image":@(mime!=nil),@"audit_result":@"pass",@"mime":mime ?: @"text/plain",
        @"signed_path":[@"https://chat.deepseek.com/api/v0/file/local/" stringByAppendingString:identifier]} mutableCopy];
    NSData *json=[NSJSONSerialization dataWithJSONObject:file options:0 error:error]; if (!json) return nil;
    NSDataWritingOptions options=NSDataWritingAtomic;
#if TARGET_OS_IOS
    options|=NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication;
#endif
    @synchronized(self) {
        if (![NSFileManager.defaultManager createDirectoryAtURL:_directory withIntermediateDirectories:YES attributes:nil error:error] ||
            ![fileData writeToURL:[self URL:identifier suffix:@".bin"] options:options error:error] ||
            ![json writeToURL:[self URL:identifier suffix:@".json"] options:options error:error]) return nil;
    }
    return file;
}
- (NSArray *)contentParts:(NSArray *)files error:(NSError **)error {
    NSMutableArray *parts=[NSMutableArray array];
    for (NSDictionary *file in files) {
        NSString *identifier=[file isKindOfClass:NSDictionary.class] ? file[@"id"] : nil;
        NSDictionary *stored=identifier ? [self file:identifier] : nil; NSData *data=stored ? [self data:identifier] : nil;
        if (!data) { if (error) *error=DSFileError(@"本地附件缺失，未发送不完整上下文。"); return nil; }
        if ([stored[@"is_image"] boolValue]) {
            NSString *url=[NSString stringWithFormat:@"data:%@;base64,%@",stored[@"mime"],[data base64EncodedStringWithOptions:0]];
            [parts addObject:@{@"type":@"image_url",@"image_url":@{@"url":url}}];
        } else {
            NSString *text=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            [parts addObject:@{@"type":@"text",@"text":[NSString stringWithFormat:@"\n附件 %@：\n%@",stored[@"file_name"],text ?: @""]}];
        }
    }
    return parts;
}
@end
