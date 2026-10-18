#import <Foundation/Foundation.h>
#import "DSAttachmentStore.h"
static void check(BOOL value,NSString *label) { if (!value) { fprintf(stderr,"FAIL: %s\n",label.UTF8String); exit(1); } }
static NSMutableURLRequest *upload(NSData *bytes,NSString *filename) {
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://chat.deepseek.com/api/v0/file/upload_file"]];
    request.HTTPMethod=@"POST"; [request setValue:@"multipart/form-data; boundary=fixture-boundary" forHTTPHeaderField:@"Content-Type"];
    NSMutableData *body=[NSMutableData data];
    [body appendData:[[@"--fixture-boundary\r\nContent-Disposition: form-data; name=\"purpose\"\r\n\r\nfile\r\n--fixture-boundary\r\nContent-Disposition: form-data; name=\"file\"; filename=\"" stringByAppendingFormat:@"%@\"\r\nContent-Type: application/octet-stream\r\n\r\n",filename] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:bytes]; [body appendData:[@"\r\n--fixture-boundary--\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    request.HTTPBody=body; return request;
}
int main(void) {
    @autoreleasepool {
        NSURL *root=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
        DSAttachmentStore *store=[[DSAttachmentStore alloc] initWithDirectory:root];
        NSError *error=nil;
        NSData *image=[[NSData alloc] initWithBase64EncodedString:@"iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEklEQVR4nGP4z8CAFWEXHbQSACj/P8Fu7N9hAAAAAElFTkSuQmCC" options:0];
        NSDictionary *file=[store importRequest:upload(image,@"图片.png") error:&error];
        check(file && !error && [file[@"is_image"] boolValue],@"multipart PNG and Unicode filename accepted without official authentication");
        check([file[@"width"] integerValue]==8 && [file[@"height"] integerValue]==8,@"native image metadata contains valid dimensions");
        check([file[@"file_name"] isEqual:@"图片.png"] && [[store data:file[@"id"]] isEqual:image],@"binary bytes and filename preserved");
        check([[[[store contentParts:@[file] error:&error] firstObject] objectForKey:@"type"] isEqual:@"image_url"],@"image is a multimodal API content part");
        DSAttachmentStore *reopen=[[DSAttachmentStore alloc] initWithDirectory:root];
        check([reopen file:file[@"id"]]!=nil,@"uploaded image survives restart");
        NSMutableURLRequest *stream=upload([@"附件内容🌏" dataUsingEncoding:NSUTF8StringEncoding],@"notes.md");
        NSData *body=stream.HTTPBody; stream.HTTPBody=nil; stream.HTTPBodyStream=[NSInputStream inputStreamWithData:body];
        NSDictionary *text=[store importRequest:stream error:&error];
        check(text && ![text[@"is_image"] boolValue],@"UTF-8 text and streamed multipart body accepted");
        NSArray *parts=[store contentParts:@[text] error:&error];
        check([parts[0][@"text"] containsString:@"附件内容🌏"],@"text attachment is sent as text without loss");
        NSDictionary *path=[store importRequest:upload(image,@"../../safe.png") error:&error];
        check([path[@"file_name"] isEqual:@"safe.png"] && [store data:@"../../secrets"]==nil,@"filename cannot escape attachment storage");
        NSMutableURLRequest *bad=upload(image,@"bad.png"); bad.HTTPBody=[@"broken multipart" dataUsingEncoding:NSUTF8StringEncoding];
        check([store importRequest:bad error:&error]==nil,@"malformed upload fails locally");
        const unsigned char binary[]={0,255,0,1};
        check([store importRequest:upload([NSData dataWithBytes:binary length:4],@"binary.exe") error:&error]==nil,@"unsupported binary fails explicitly");
        [NSFileManager.defaultManager removeItemAtURL:root error:NULL];
        check([store contentParts:@[file] error:&error]==nil,@"missing attachment prevents incomplete context replay");
        puts("PASS: local multipart attachments, image/text API parts, restart, Unicode, streams, path validation and errors");
    } return 0;
}
