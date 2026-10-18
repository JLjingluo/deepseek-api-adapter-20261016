#import "DSUploadBodyBridge.h"
#import "DSAPIConfiguration.h"
#import <objc/runtime.h>
static NSMutableDictionary<NSString *,NSValue *> *DSUploadImplementations;
static NSString *DSUploadKey(Class cls,SEL selector) { return [NSStringFromClass(cls) stringByAppendingFormat:@"/%@",NSStringFromSelector(selector)]; }
static IMP DSUploadOriginal(id session,SEL selector) {
    @synchronized(NSURLSession.class) {
        for (Class cls=object_getClass(session);cls;cls=class_getSuperclass(cls)) {
            NSValue *value=DSUploadImplementations[DSUploadKey(cls,selector)]; if (value) return value.pointerValue;
        }
    }
    return NULL;
}
static NSURLRequest *DSUploadRequest(NSURLRequest *request,id body,NSString *key) {
    if ((!DSAPIIsEnabled() && !DSAPIHasPendingModeChange()) || ![request.URL.host.lowercaseString isEqual:@"chat.deepseek.com"] ||
        ![request.URL.path hasSuffix:@"/file/upload_file"] || !body) return request;
    NSMutableURLRequest *copy=[request mutableCopy];
    // NSURLProtocol does not receive uploadTask(fromFile/fromData)'s body.
    // Carry a private request property, never an HTTP header, into our router.
    [NSURLProtocol setProperty:body forKey:key inRequest:copy];
    return copy;
}
static id DSUploadData(id self,SEL selector,NSURLRequest *request,NSData *data) {
    IMP original=DSUploadOriginal(self,selector);
    return ((id (*)(id,SEL,id,id))original)(self,selector,DSUploadRequest(request,data,@"DSAPI.UploadData"),data);
}
static id DSUploadFile(id self,SEL selector,NSURLRequest *request,NSURL *file) {
    IMP original=DSUploadOriginal(self,selector);
    return ((id (*)(id,SEL,id,id))original)(self,selector,DSUploadRequest(request,file,@"DSAPI.UploadFileURL"),file);
}
static id DSUploadDataCompletion(id self,SEL selector,NSURLRequest *request,NSData *data,id completion) {
    IMP original=DSUploadOriginal(self,selector);
    return ((id (*)(id,SEL,id,id,id))original)(self,selector,DSUploadRequest(request,data,@"DSAPI.UploadData"),data,completion);
}
static id DSUploadFileCompletion(id self,SEL selector,NSURLRequest *request,NSURL *file,id completion) {
    IMP original=DSUploadOriginal(self,selector);
    return ((id (*)(id,SEL,id,id,id))original)(self,selector,DSUploadRequest(request,file,@"DSAPI.UploadFileURL"),file,completion);
}
void DSAPIInstallUploadBodyBridge(NSURLSession *session) {
    @synchronized(NSURLSession.class) {
        if (!DSUploadImplementations) DSUploadImplementations=[NSMutableDictionary dictionary];
        Class cls=object_getClass(session);
        NSArray *selectors=@[@"uploadTaskWithRequest:fromData:",@"uploadTaskWithRequest:fromFile:",@"uploadTaskWithRequest:fromData:completionHandler:",@"uploadTaskWithRequest:fromFile:completionHandler:"];
        IMP replacements[]={(IMP)DSUploadData,(IMP)DSUploadFile,(IMP)DSUploadDataCompletion,(IMP)DSUploadFileCompletion};
        for (NSUInteger index=0;index<selectors.count;index++) {
            SEL selector=NSSelectorFromString(selectors[index]); Method method=class_getInstanceMethod(cls,selector);
            if (!method || method_getImplementation(method)==replacements[index]) continue;
            DSUploadImplementations[DSUploadKey(cls,selector)]=[NSValue valueWithPointer:method_getImplementation(method)];
            if (!class_addMethod(cls,selector,replacements[index],method_getTypeEncoding(method))) class_replaceMethod(cls,selector,replacements[index],method_getTypeEncoding(method));
        }
    }
}
