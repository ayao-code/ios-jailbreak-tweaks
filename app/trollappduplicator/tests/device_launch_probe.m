#import "device_launch_probe.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#include <stdlib.h>

static void emit(NSDictionary *record) {
    NSData *data=[NSJSONSerialization dataWithJSONObject:record options:0 error:nil];
    fwrite(data.bytes,1,data.length,stdout); fputc('\n',stdout);fflush(stdout);
}
static id property(id object,NSString *name) {
    if(![object respondsToSelector:NSSelectorFromString(name)]) return NSNull.null;
    @try { return [object valueForKey:name]?:NSNull.null; } @catch(NSException *e) { return NSNull.null; }
}
static id service(NSString *className,NSString *factory) {
    Class cls=NSClassFromString(className);SEL sel=NSSelectorFromString(factory);
    return [cls respondsToSelector:sel]?((id(*)(id,SEL))objc_msgSend)(cls,sel):nil;
}
static NSDictionary *errorInfo(NSError *error) {
    if(!error) return @{};
    NSMutableDictionary *info=[@{@"domain":error.domain,@"code":@(error.code),@"description":error.localizedDescription?:@""} mutableCopy];
    NSError *underlying=error.userInfo[NSUnderlyingErrorKey];
    if([underlying isKindOfClass:NSError.class]) info[@"underlying"]=@{@"domain":underlying.domain,@"code":@(underlying.code),@"description":underlying.localizedDescription?:@""};
    return info;
}
static int pidFor(id service,NSString *bundle) {
    SEL sel=NSSelectorFromString(@"pidForApplication:");
    return [service respondsToSelector:sel]?((int(*)(id,SEL,id))objc_msgSend)(service,sel,bundle):-1;
}
int cloneRunLaunchProbe(NSString *bundle,BOOL frontBoard) {
    // Fixed sensitive target, normal launch request only; no attach, code injection or login.
    NSString *approvedTarget = NSProcessInfo.processInfo.environment[@"CLONE_PROBE_TARGET_BUNDLE"];
    if (!approvedTarget.length || ![bundle isEqual:approvedTarget] || ![approvedTarget hasPrefix:@"cn.damai.iphone."]) return 2;
    dlopen("/System/Library/Frameworks/CoreServices.framework/CoreServices",RTLD_LAZY);
    dlopen("/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices",RTLD_LAZY);
    dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices",RTLD_LAZY);
    id workspace=service(@"LSApplicationWorkspace",@"defaultWorkspace");
    Class proxyClass=NSClassFromString(@"LSApplicationProxy");SEL proxySel=NSSelectorFromString(@"applicationProxyForIdentifier:");
    id proxy=[proxyClass respondsToSelector:proxySel]?((id(*)(id,SEL,id))objc_msgSend)(proxyClass,proxySel,bundle):nil;
    id fb=service(@"FBSSystemService",@"sharedService");
    NSMutableArray *methods=[NSMutableArray array];unsigned count=0;
    Method *all=class_copyMethodList([workspace class],&count);
    for(unsigned i=0;i<count;i++) {
        const char *name=sel_getName(method_getName(all[i]));
        if(strstr(name,"openApplication")) [methods addObject:@{@"selector":@(name),@"encoding":@(method_getTypeEncoding(all[i]))}];
    }
    free(all);
    emit(@{@"event":@"state",@"caller":@"CloneStudio CLI; not actual TrollStore caller",@"bundle_id":bundle,
        @"application_identifier":property(proxy,@"applicationIdentifier"),@"launch_prohibited":property(proxy,@"launchProhibited"),
        @"application_type":property(proxy,@"applicationType"),@"pid_before":@(pidFor(fb,bundle)),@"launch_methods":methods});
    SEL can=NSSelectorFromString(@"canOpenApplication:reason:");
    if([fb respondsToSelector:can]) {
        long long reason=-1;BOOL allowed=((BOOL(*)(id,SEL,id,long long*))objc_msgSend)(fb,can,bundle,&reason);
        emit(@{@"event":@"can_open",@"allowed":@(allowed),@"reason":@(reason)});
    }
    if(!frontBoard) {
        SEL open=NSSelectorFromString(@"openApplicationWithBundleID:");
        NSMethodSignature *signature=[workspace methodSignatureForSelector:open];
        if(!signature || signature.numberOfArguments!=3) return 3;
        const char *ret=signature.methodReturnType;
        if(!strcmp(ret,@encode(BOOL)) || !strcmp(ret,@encode(bool)) || !strcmp(ret,"c")) {
            BOOL result=((BOOL(*)(id,SEL,id))objc_msgSend)(workspace,open,bundle);
            emit(@{@"event":@"ls_open",@"return_type":@(ret),@"result":@(result)});
        } else { emit(@{@"event":@"unsupported_return_type",@"return_type":@(ret)});return 4; }
        [NSThread sleepForTimeInterval:1];
        emit(@{@"event":@"pid_after",@"pid":@(pidFor(fb,bundle))});return 0;
    }
    SEL open=NSSelectorFromString(@"openApplication:options:withResult:");
    if(![fb respondsToSelector:open]) return 3;
    __block BOOL complete=NO;
    void (^callback)(NSError *)=^(NSError *error) {
        emit(@{@"event":@"frontboard_result",@"error":errorInfo(error),@"pid":@(pidFor(fb,bundle))});complete=YES;
    };
    ((void(*)(id,SEL,id,id,id))objc_msgSend)(fb,open,bundle,@{},callback);
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:10];
    while(!complete && deadline.timeIntervalSinceNow>0) {
        @autoreleasepool { [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]]; }
    }
    if(!complete) { emit(@{@"event":@"callback_timeout"});return 5; }
    return 0;
}
