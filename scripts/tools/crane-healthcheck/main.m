#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <stdio.h>

static BOOL Wait(BOOL (^done)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!done() && deadline.timeIntervalSinceNow > 0) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    return done();
}

static NSDictionary *ErrorInfo(NSError *error) {
    if (!error) return [NSDictionary dictionary];
    return @{ @"domain": error.domain, @"code": @(error.code) };
}

int main(void) {
    @autoreleasepool {
        // Only loads libcrane into this short-lived helper, never another process.
        if (!dlopen("@rpath/libcrane.dylib", RTLD_NOW)) {
            fprintf(stderr, "libcrane load failed: %s\n", dlerror());
            return 69;
        }
        Class cls = objc_getClass("CraneManager");
        SEL shared = sel_registerName("sharedManager");
        if (!cls || ![cls respondsToSelector:shared]) return 69;
        id manager = ((id (*)(id, SEL))objc_msgSend)(cls, shared);
        SEL selector = sel_registerName("cranehelperdGlobalAsyncRemoteObjectProxy");
        if (![manager respondsToSelector:selector]) return 69;
        id proxy = ((id (*)(id, SEL))objc_msgSend)(manager, selector);
        if (!proxy) return 69;

        NSMutableDictionary *report = [NSMutableDictionary dictionary];
        __block BOOL received = NO;
        void (^insurance)(BOOL, NSArray *, NSError *) = ^(BOOL valid, NSArray *broken, NSError *error) {
            report[@"insuranceValid"] = @(valid);
            report[@"brokenDaemons"] = broken ?: [NSArray array];
            report[@"error"] = ErrorInfo(error);
            received = YES;
        };
        ((void (*)(id, SEL, id))objc_msgSend)(proxy,
            sel_registerName("verifyCraneInsuranceAndReply:"), insurance);
        report[@"replyReceived"] = @(Wait(^BOOL { return received; }));
        __block BOOL sbReceived = NO;
        void (^sbReply)(BOOL) = ^(BOOL loaded) {
            report[@"springBoardLoaded"] = @(loaded);
            sbReceived = YES;
        };
        ((void (*)(id, SEL, id))objc_msgSend)(proxy,
            sel_registerName("verifyCraneSBLoadedAndReply:"), sbReply);
        report[@"springBoardReplyReceived"] = @(Wait(^BOOL { return sbReceived; }));
        NSData *data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:NULL];
        if (!data) return 70;
        fwrite(data.bytes, 1, data.length, stdout);
        fputc('\n', stdout);
        return received && sbReceived && [report[@"insuranceValid"] boolValue] &&
            [report[@"springBoardLoaded"] boolValue] ? 0 : 75;
    }
}
