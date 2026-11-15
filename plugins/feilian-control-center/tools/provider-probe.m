// Bounded independent adapter test. No configuration mutation or App injection.
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import "../VPNPrivate.h"

static NSArray *Allowed(void) {
    return @[@"co.hotspot.vpn.security", @"com.bestapp.gofast.vpn", @"com.zenith.jump",
             @"com.qdtiktok.easyvpn", @"com.volcengine.corplink"];
}
static NSArray *Connections(id store) {
    NSMutableArray *result = [NSMutableArray array];
    for (NSUInteger grade = 0; grade < 4; grade++) {
        id identifiers = [store vpnServicesForCurrentSetWithGrade:grade];
        if (![identifiers isKindOfClass:NSArray.class]) return nil;
        for (id identifier in identifiers) {
            id connection = [store connectionWithServiceID:identifier withGrade:grade];
            for (NSString *method in @[@"bundleID", @"status", @"connected", @"notDisconnectedOrDisconnecting", @"isProviderAvailable"])
                if (![connection respondsToSelector:NSSelectorFromString(method)]) return nil;
            [result addObject:connection];
        }
    }
    return result;
}
static BOOL Unlocked(void) {
    dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_NOW);
    mach_port_t (*port)(void) = dlsym(RTLD_DEFAULT, "SBSSpringBoardServerPort");
    void (*query)(mach_port_t, BOOL *, BOOL *) = dlsym(RTLD_DEFAULT, "SBGetScreenLockStatus");
    if (!port || !query || port() == MACH_PORT_NULL) return NO;
    BOOL locked = (BOOL)-1, passcode = (BOOL)-1; query(port(), &locked, &passcode);
    printf("unlocked=%d\n", locked == NO); return locked == NO;
}
static void Snapshot(id store, CFAbsoluteTime started) {
    for (id connection in Connections(store)) {
        NSString *bundle = [connection bundleID];
        printf("elapsed=%.3f bundle=%s status=%lu connected=%d active=%d available=%d\n",
            CFAbsoluteTimeGetCurrent() - started, [Allowed() containsObject:bundle] ? bundle.UTF8String : "external",
            (unsigned long)[connection status], [connection connected], [connection notDisconnectedOrDisconnecting], [connection isProviderAvailable]);
    }
    fflush(stdout);
}
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 3 || ![Allowed() containsObject:@(argv[1])]) return 2;
        NSString *bundleID = @(argv[1]), *action = @(argv[2]);
        if (![@[@"read", @"connect", @"disconnect", @"net"] containsObject:action]) return 2;
        if (![[NSBundle bundleWithPath:@"/System/Library/PreferenceBundles/VPNPreferences.bundle"] load]) return 3;
        id store = [NSClassFromString(@"VPNConnectionStore") sharedInstance];
        Connections(store);
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:3]];
        NSArray *connections = Connections(store);
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
        if (!connections) return 3;
        CFAbsoluteTime started = CFAbsoluteTimeGetCurrent(); Snapshot(store, started);
        if ([action isEqual:@"read"]) { Unlocked(); return 0; }
        NSMutableArray *matches = [NSMutableArray array];
        for (id connection in connections) {
            if ([[connection bundleID] isEqual:bundleID]) [matches addObject:connection];
            else if ([action isEqual:@"connect"] && [connection notDisconnectedOrDisconnecting]) {
                puts("REFUSED_OTHER_ACTIVE=1"); return 4;
            }
        }
        if (matches.count != 1 || !Unlocked()) return 4;
        id target = matches.firstObject;
        BOOL networkOnly = [action isEqual:@"net"];
        BOOL connect = [action isEqual:@"connect"] || networkOnly;
        if (![target isProviderAvailable] || ![target respondsToSelector:connect ? @selector(connect) : @selector(disconnect)]) return 4;
        if (networkOnly && ![target connected]) return 4;
        if (!networkOnly && connect && [target notDisconnectedOrDisconnecting]) { puts("REFUSED_ALREADY_ACTIVE=1"); return 4; }
        id observer = [NSNotificationCenter.defaultCenter addObserverForName:@"VPNConnectionStatusChanged" object:nil
            queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { (void)note; Snapshot(store, started); }];
        if (!networkOnly) {
            if (connect) [target connect]; else [target disconnect];
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:20]];
        }
        Snapshot(store, started);
        BOOL reached = connect ? [target connected] : ![target notDisconnectedOrDisconnecting];
        if (connect && reached) {
            __block BOOL done = NO, valid = NO;
            NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
            configuration.timeoutIntervalForRequest = 10; configuration.timeoutIntervalForResource = 15;
            NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
            [[session dataTaskWithURL:[NSURL URLWithString:@"https://www.apple.com/library/test/success.html"] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    valid = !error && ((NSHTTPURLResponse *)response).statusCode == 200 && [body containsString:@"Success"];
                    printf("https_status=%ld body_success=%d error_code=%ld\n", (long)((NSHTTPURLResponse *)response).statusCode,
                        [body containsString:@"Success"], (long)error.code); done = YES;
                });
            }] resume];
            NSDate *end = [NSDate dateWithTimeIntervalSinceNow:16];
            while (!done && end.timeIntervalSinceNow > 0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
            [session invalidateAndCancel]; reached = valid && [target connected];
        }
        [NSNotificationCenter.defaultCenter removeObserver:observer];
        printf("REACHED=%d\n", reached); return reached ? 0 : 1;
    }
}
