#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import "EasyVPNRequest.h"
#import "../VPNPrivate.h"

@interface NSObject (EasyLaunch)
+ (id)sharedService;
- (void)openApplication:(NSString *)identifier options:(NSDictionary *)options withResult:(void (^)(NSError *))result;
+ (id)configurationForDefaultMainDisplayMonitor;
+ (id)monitorWithConfiguration:(id)configuration;
- (void)setTransitionHandler:(id)handler;
- (id)currentLayout;
- (NSArray *)elements;
- (BOOL)isUIApplicationElement;
- (BOOL)hasKeyboardFocus;
- (NSString *)bundleIdentifier;
- (NSString *)identifier;
- (void)invalidate;
@end

static id Store;
static id Target;
static NSUInteger Targets;
static BOOL OtherActive;
static BOOL PrintState = YES;

static void ReadState(void) {
    Targets = 0; OtherActive = NO; Target = nil;
    for (NSUInteger grade = 0; grade < 4; grade++) {
        for (id identifier in [Store vpnServicesForCurrentSetWithGrade:grade]) {
            id connection = [Store connectionWithServiceID:identifier withGrade:grade];
            BOOL target = [[connection bundleID] isEqualToString:@"com.qdtiktok.easyvpn"];
            if (target) { Target = connection; Targets++; }
            else if ([connection notDisconnectedOrDisconnecting]) OtherActive = YES;
            if (PrintState) printf("target=%d status=%lu connected=%d active=%d\n", target,
                (unsigned long)[connection status], [connection connected], [connection notDisconnectedOrDisconnecting]);
        }
    }
    fflush(stdout);
}

static BOOL Unlocked(void) {
    dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_NOW);
    mach_port_t (*port)(void) = dlsym(RTLD_DEFAULT, "SBSSpringBoardServerPort");
    void (*query)(mach_port_t, BOOL *, BOOL *) = dlsym(RTLD_DEFAULT, "SBGetScreenLockStatus");
    if (!port || !query || port() == MACH_PORT_NULL) return NO;
    BOOL locked = (BOOL)-1, passcode = (BOOL)-1;
    query(port(), &locked, &passcode);
    printf("unlocked=%d\n", locked == NO);
    return locked == NO;
}

static NSString *Frontmost(void) {
    NSString *(*copy)(void) = dlsym(RTLD_DEFAULT, "SBSCopyFrontmostApplicationDisplayIdentifier");
    NSString *identifier = copy ? copy() : nil;
    if (identifier.length) return identifier;
    dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_NOW);
    Class configurationClass = NSClassFromString(@"FBSDisplayLayoutMonitorConfiguration");
    Class monitorClass = NSClassFromString(@"FBSDisplayLayoutMonitor");
    if (![configurationClass respondsToSelector:@selector(configurationForDefaultMainDisplayMonitor)] ||
        ![monitorClass respondsToSelector:@selector(monitorWithConfiguration:)]) return nil;
    id configuration = [configurationClass configurationForDefaultMainDisplayMonitor];
    if (![configuration respondsToSelector:@selector(setTransitionHandler:)]) return nil;
    [configuration setTransitionHandler:^(id context) { (void)context; }];
    id monitor = [monitorClass monitorWithConfiguration:configuration];
    if (![monitor respondsToSelector:@selector(currentLayout)] || ![monitor respondsToSelector:@selector(invalidate)]) return nil;
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
    id layout = [monitor currentLayout];
    [monitor invalidate];
    if (![layout respondsToSelector:@selector(elements)]) return nil;
    NSArray *elements = [layout elements];
    if (![elements isKindOfClass:NSArray.class] || !elements.count || elements.count > 32) return nil;
    NSUInteger focused = 0;
    BOOL homeScreen = NO;
    for (id element in elements) {
        if (![element respondsToSelector:@selector(isUIApplicationElement)] ||
            ![element respondsToSelector:@selector(hasKeyboardFocus)] ||
            ![element respondsToSelector:@selector(bundleIdentifier)]) return nil;
        if ([element isUIApplicationElement] && [element hasKeyboardFocus]) {
            focused++;
            identifier = [element bundleIdentifier];
        }
        if ([element respondsToSelector:@selector(identifier)] &&
            [[element identifier] isEqualToString:@"com.apple.springboard"]) homeScreen = YES;
    }
    return focused == 1 ? identifier : (focused == 0 && homeScreen ? @"com.apple.springboard" : nil);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2 || argc > 3) return 2;
        NSString *action = @(argv[1]);
        if (![@[@"--read", @"--connect", @"--disconnect", @"--stop", @"--net"] containsObject:action]) return 2;
        if (![[NSBundle bundleWithPath:@"/System/Library/PreferenceBundles/VPNPreferences.bundle"] load]) return 3;
        Class cls = NSClassFromString(@"VPNConnectionStore");
        if (![cls respondsToSelector:@selector(sharedInstance)]) return 3;
        Store = [cls sharedInstance];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:3]];
        // Enumeration itself starts asynchronous configuration/status loading.
        // Prime it before treating the first returned objects as authoritative.
        PrintState = NO;
        ReadState();
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:2]];
        ReadState();
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
        PrintState = YES;
        ReadState();
        if ([action isEqualToString:@"--read"]) { Unlocked(); return 0; }
        if (Targets != 1 || OtherActive || !Unlocked()) { printf("refused=1\n"); return 4; }
        if ([action isEqualToString:@"--net"]) {
            if (![Target connected]) return 4;
            __block BOOL done = NO, valid = NO;
            NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
            configuration.timeoutIntervalForRequest = 10; configuration.timeoutIntervalForResource = 15;
            NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
            [[session dataTaskWithURL:[NSURL URLWithString:@"https://www.apple.com/library/test/success.html"]
                completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                        valid=!error && ((NSHTTPURLResponse *)response).statusCode==200 && [body containsString:@"Success"];
                        printf("https_status=%ld body_success=%d error_code=%ld\n",
                            (long)((NSHTTPURLResponse *)response).statusCode, [body containsString:@"Success"], (long)error.code);
                        done = YES;
                    });
                }] resume];
            NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:16];
            while (!done && deadline.timeIntervalSinceNow > 0)
                [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
            [session invalidateAndCancel]; return done && valid && [Target connected] ? 0 : 1;
        }
        if ([action isEqualToString:@"--stop"]) {
            [Target disconnect];
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:8]];
            ReadState(); return [Target notDisconnectedOrDisconnecting] ? 1 : 0;
        }
        if ([action isEqualToString:@"--connect"] && [Target notDisconnectedOrDisconnecting]) return 4;
        int requestToken, resultToken, stageToken;
        if (notify_register_check(EasyRequestName, &requestToken) != NOTIFY_STATUS_OK ||
            notify_register_check(EasyResultName, &resultToken) != NOTIFY_STATUS_OK ||
            notify_register_check(EasyStageName, &stageToken) != NOTIFY_STATUS_OK) return 5;
        uint64_t request = (uint64_t)((NSDate.date.timeIntervalSince1970 + EasyLifetime) * 1000) * 4 +
            ([action isEqualToString:@"--connect"] ? 1 : 2);
        notify_set_state(resultToken, 0); notify_set_state(stageToken, 99);
        notify_set_state(requestToken, request);
        __block uint64_t result = 0;
        int eventToken;
        notify_register_dispatch(EasyResultName, &eventToken, dispatch_get_main_queue(), ^(int token) {
            uint64_t value = 0; notify_get_state(token, &value);
            if (value / 16 == request) { result = value % 16; printf("helper_result=%llu\n", result); }
        });
        dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_NOW);
        NSDictionary *options = @{};
        BOOL background = argc == 3 && !strcmp(argv[2], "--background");
        if (background) {
            NSString *const *key = (NSString *const *)dlsym(RTLD_DEFAULT, "FBSOpenApplicationOptionKeyActivateSuspended");
            if (!key || !*key) return 5;
            options = @{*key: @YES};
        }
        NSString *before = Frontmost();
        id service = [NSClassFromString(@"FBSSystemService") sharedService];
        [service openApplication:@"com.qdtiktok.easyvpn" options:options withResult:^(NSError *error) {
            printf("launch_error=%ld background=%d\n", (long)error.code, background);
            if (!error) notify_post(EasyRequestName);
        }];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:EasyLifetime + 2];
        NSTimeInterval started = NSDate.date.timeIntervalSince1970;
        while (!result && deadline.timeIntervalSinceNow > 0)
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
        printf("request_elapsed=%.3f\n", NSDate.date.timeIntervalSince1970 - started);
        if ([action isEqualToString:@"--connect"] && result == EasyConnected) {
            __block BOOL done = NO;
            NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
            configuration.timeoutIntervalForRequest = 10;
            configuration.timeoutIntervalForResource = 15;
            NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
            [[session dataTaskWithURL:[NSURL URLWithString:@"https://www.apple.com/library/test/success.html"]
                completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                        printf("connected_https_status=%ld body_success=%d error_code=%ld\n",
                            (long)((NSHTTPURLResponse *)response).statusCode,
                            [body containsString:@"Success"], (long)error.code);
                        done = YES;
                    });
                }] resume];
            NSDate *observationEnd = [NSDate dateWithTimeIntervalSinceNow:15];
            [[NSRunLoop currentRunLoop] runUntilDate:observationEnd];
            printf("network_completed=%d observation_seconds=15\n", done);
            [session invalidateAndCancel];
        }
        uint64_t stage = 0; notify_get_state(stageToken, &stage);
        NSString *after = Frontmost();
        printf("stage=%llu result=%llu frontmost_same=%d frontmost_known=%d before_easy=%d after_easy=%d\n", stage, result,
            before && [before isEqualToString:after], before != nil && after != nil,
            [before isEqualToString:@"com.qdtiktok.easyvpn"], [after isEqualToString:@"com.qdtiktok.easyvpn"]);
        ReadState();
        BOOL reached = [action isEqualToString:@"--connect"] ? [Target connected] : ![Target notDisconnectedOrDisconnecting];
        notify_set_state(requestToken, 0);
        notify_cancel(requestToken); notify_cancel(resultToken); notify_cancel(stageToken); notify_cancel(eventToken);
        printf("target_reached=%d\n", reached);
        uint64_t expected = [action isEqualToString:@"--connect"] ? EasyConnected : EasyDisconnected;
        return reached && result == expected ? 0 : 1;
    }
}
