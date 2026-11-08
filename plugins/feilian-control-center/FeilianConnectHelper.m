#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "FeilianRequest.h"

extern void MSHookMessageEx(Class cls, SEL selector, IMP replacement, IMP *original);

@interface NSObject (FeilianNativeConnection)
+ (instancetype)share;
- (BOOL)isLogin;
- (id)tunnel;
- (void)connect:(void (^)(NSError *))completion;
- (void)disconnect;
@end

static int RequestToken = NOTIFY_TOKEN_INVALID;
static int ResultToken = NOTIFY_TOKEN_INVALID;
static uint64_t PendingRequest = 0;
static UIBackgroundTaskIdentifier BackgroundTask;
static id PendingTunnel;
static void (*OriginalPresent)(id, SEL, UIViewController *, BOOL, void (^)(void));
static void (*OriginalOpenURL)(id, SEL, NSURL *, NSDictionary *, void (^)(BOOL));

static void FinishRequest(uint64_t request, FeilianResult result) {
    if (!request || PendingRequest != request) return;
    PendingRequest = 0;
    PendingTunnel = nil;
    if (ResultToken != NOTIFY_TOKEN_INVALID && notify_set_state(ResultToken, request * 256 + result) == NOTIFY_STATUS_OK)
        notify_post(FeilianResultName);
    if (BackgroundTask != UIBackgroundTaskInvalid) {
        [UIApplication.sharedApplication endBackgroundTask:BackgroundTask];
        BackgroundTask = UIBackgroundTaskInvalid;
    }
    NSLog(@"[FeilianCC] silent request result=%u", (unsigned)result);
}

static void PresentController(id self, SEL command, UIViewController *controller, BOOL animated, void (^completion)(void)) {
    if (PendingRequest) {
        // Interactive auth/permission/UI cannot complete silently. Refuse the
        // whole operation; never select an action, fabricate auth, or resume it.
        uint64_t request = PendingRequest;
        id tunnel = PendingTunnel;
        FinishRequest(request, FeilianResultInteractionRequired);
        if ([tunnel respondsToSelector:@selector(disconnect)]) [tunnel disconnect];
        NSLog(@"[FeilianCC] interactive UI refused during strict silent request");
        return;
    }
    OriginalPresent(self, command, controller, animated, completion);
}

static void OpenURL(id self, SEL command, NSURL *url, NSDictionary *options, void (^completion)(BOOL)) {
    if (PendingRequest) {
        // Native auth must not transfer focus to Safari or another app during
        // a strict silent request. Fail instead, regardless of the URL value.
        uint64_t request = PendingRequest;
        id tunnel = PendingTunnel;
        FinishRequest(request, FeilianResultInteractionRequired);
        if ([tunnel respondsToSelector:@selector(disconnect)]) [tunnel disconnect];
        if (completion) completion(NO);
        return;
    }
    OriginalOpenURL(self, command, url, options, completion);
}

static void HandleRequest(void) {
    uint64_t request = 0;
    if (RequestToken == NOTIFY_TOKEN_INVALID || notify_get_state(RequestToken, &request) != NOTIFY_STATUS_OK) return;
    NSTimeInterval remaining = (NSTimeInterval)request / 1000 - NSDate.date.timeIntervalSince1970;
    if (remaining <= 0 || remaining > FeilianRequestLifetime + 1 || PendingRequest) return;
    // One accepted click, not an ongoing app behavior change.
    if (notify_set_state(RequestToken, 0) != NOTIFY_STATUS_OK) return;
    PendingRequest = request;
    UIApplication *app = UIApplication.sharedApplication;
    if (!app.protectedDataAvailable || app.applicationState == UIApplicationStateActive) {
        FinishRequest(request, FeilianResultNotBackground);
        return;
    }
    Class modelClass = NSClassFromString(@"TopGoModel");
    if (![modelClass respondsToSelector:@selector(share)]) {
        FinishRequest(request, FeilianResultUnavailable);
        return;
    }
    id model = [modelClass share];
    if (![model respondsToSelector:@selector(isLogin)] || ![model isLogin]) {
        FinishRequest(request, FeilianResultInteractionRequired);
        return;
    }
    if (![model respondsToSelector:@selector(tunnel)]) {
        FinishRequest(request, FeilianResultUnavailable);
        return;
    }
    id tunnel = [model tunnel];
    if (![NSStringFromClass([tunnel class]) isEqualToString:@"FLTunnelManager"] ||
        ![tunnel respondsToSelector:@selector(connect:)]) {
        FinishRequest(request, FeilianResultUnavailable);
        return;
    }
    PendingTunnel = tunnel;
    BackgroundTask = [app beginBackgroundTaskWithName:@"FeilianCC.user-request" expirationHandler:^{
        if (PendingRequest != request) return;
        id pending = PendingTunnel;
        FinishRequest(request, FeilianResultTimedOut);
        if ([pending respondsToSelector:@selector(disconnect)]) [pending disconnect];
    }];
    if (BackgroundTask == UIBackgroundTaskInvalid) {
        FinishRequest(request, FeilianResultUnavailable);
        return;
    }
    NSLog(@"[FeilianCC] native connect requested in background state=%ld", (long)app.applicationState);
    // Keep all app-native account/session/MFA checks. Do not access their data.
    [tunnel connect:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (PendingRequest != request) return;
            NSLog(@"[FeilianCC] native completion error_domain=%@ code=%ld", error.domain, (long)error.code);
            FinishRequest(request, error ? FeilianResultConnectionFailed : FeilianResultStarted);
        });
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(FeilianRequestLifetime * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (PendingRequest != request) return;
        id pending = PendingTunnel;
        FinishRequest(request, FeilianResultTimedOut);
        if ([pending respondsToSelector:@selector(disconnect)]) [pending disconnect];
    });
}

__attribute__((constructor)) static void InitializeFeilianConnectHelper(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.volcengine.corplink"]) return;
        BackgroundTask = UIBackgroundTaskInvalid;
        if (notify_register_dispatch(FeilianRequestName, &RequestToken, dispatch_get_main_queue(), ^(int token) {
            HandleRequest();
        }) != NOTIFY_STATUS_OK) return;
        notify_register_check(FeilianResultName, &ResultToken);
        MSHookMessageEx(UIViewController.class, @selector(presentViewController:animated:completion:),
            (IMP)PresentController, (IMP *)&OriginalPresent);
        MSHookMessageEx(UIApplication.class, @selector(openURL:options:completionHandler:),
            (IMP)OpenURL, (IMP *)&OriginalOpenURL);
        // Cold launch checks the pending user request only after app init.
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil
            queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { HandleRequest(); }];
        NSLog(@"[FeilianCC] strict silent helper loaded");
    }
}
