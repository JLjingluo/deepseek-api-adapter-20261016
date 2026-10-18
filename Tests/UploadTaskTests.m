#import <Foundation/Foundation.h>
#import "DSAPIConfiguration.h"
#import "DSCompatibilityProtocol.h"
#import "DSAttachmentStore.h"
#import "DSUploadBodyBridge.h"
static void check(BOOL value,NSString *label) { if (!value) { fprintf(stderr,"FAIL: %s\n",label.UTF8String);exit(1); } }
@interface UploadCapture : NSObject <NSURLSessionDataDelegate>
@property(strong) NSMutableData *bytes;
@property(strong) NSError *error;
@property BOOL done;
@end
@implementation UploadCapture
- (instancetype)init { if ((self=[super init])) _bytes=[NSMutableData data];return self; }
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data { [self.bytes appendData:data]; }
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error { self.error=error;self.done=YES; }
@end
int main(void) {
    @autoreleasepool {
        [NSUserDefaults.standardUserDefaults setObject:@{@"enabled":@YES} forKey:@"DSAPIAdapter.configuration.v1"];
        NSData *png=[[NSData alloc] initWithBase64EncodedString:@"iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEklEQVR4nGP4z8CAFWEXHbQSACj/P8Fu7N9hAAAAAElFTkSuQmCC" options:0];
        NSMutableData *body=[[@"--upload-task\r\nContent-Disposition: form-data; name=\"file\"; filename=\"red.png\"\r\nContent-Type: image/png\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
        [body appendData:png]; [body appendData:[@"\r\n--upload-task--\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
        NSURL *file=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
        check([body writeToURL:file atomically:YES],@"multipart disk fixture created");
        for (NSNumber *value in @[@0,@1,@2,@3]) {
            NSInteger variant=value.integerValue; BOOL fromFile=variant%2==1,completion=variant>=2;
            UploadCapture *capture=[UploadCapture new];
            NSURLSessionConfiguration *config=NSURLSessionConfiguration.ephemeralSessionConfiguration;
            config.protocolClasses=@[DSCompatibilityProtocol.class];
            NSURLSession *session=[NSURLSession sessionWithConfiguration:config delegate:capture delegateQueue:nil];
            DSAPIInstallUploadBodyBridge(session); DSAPIInstallUploadBodyBridge(session);
            NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://chat.deepseek.com/api/v0/file/upload_file"]];
            request.HTTPMethod=@"POST"; [request setValue:@"multipart/form-data; boundary=upload-task" forHTTPHeaderField:@"Content-Type"];
            void (^callback)(NSData *,NSURLResponse *,NSError *)=^(NSData *data,NSURLResponse *response,NSError *error) {
                if (data) [capture.bytes appendData:data];capture.error=error;capture.done=YES;
            };
            NSURLSessionUploadTask *task;
            if (completion) task=fromFile ? [session uploadTaskWithRequest:request fromFile:file completionHandler:callback] : [session uploadTaskWithRequest:request fromData:body completionHandler:callback];
            else task=fromFile ? [session uploadTaskWithRequest:request fromFile:file] : [session uploadTaskWithRequest:request fromData:body];
            [task resume]; NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:8];
            while (!capture.done && deadline.timeIntervalSinceNow>0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
            if (capture.error) fprintf(stderr,"upload variant %ld error: %s\n",(long)variant,capture.error.localizedDescription.UTF8String);
            check(capture.done && !capture.error,@"native NSURLSession upload variant completes locally");
            NSDictionary *json=[NSJSONSerialization JSONObjectWithData:capture.bytes options:0 error:NULL];
            NSDictionary *uploaded=json[@"data"][@"biz_data"];
            check([uploaded[@"file_size"] unsignedIntegerValue]==png.length && [uploaded[@"is_image"] boolValue],@"uploadTask body arrives intact through URLProtocol");
            check([[DSAttachmentStore.shared data:uploaded[@"id"]] isEqual:png],@"uploaded bytes match the source image");
            [session invalidateAndCancel];
            printf("PASS: native upload from%s %s\n",fromFile ? "File" : "Data",completion ? "completion" : "delegate");
        }
        [NSFileManager.defaultManager removeItemAtURL:file error:NULL];
    }return 0;
}
