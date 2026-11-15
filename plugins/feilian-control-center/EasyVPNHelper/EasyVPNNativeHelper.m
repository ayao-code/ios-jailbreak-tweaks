// Temporary native-flow helper for Easy VPN 2.1.0. No credential access.
#import <UIKit/UIKit.h>
#import <NetworkExtension/NetworkExtension.h>
#import <objc/runtime.h>
#import "EasyVPNRequest.h"

extern void MSHookMessageEx(Class cls, SEL sel, IMP replacement, IMP *original);

@interface NSObject (EasyNativeFlow)
- (void)startButtonClick:(id)sender;
- (void)stopButtonClick:(id)sender;
- (UIButton *)startButton;
- (UIButton *)stopButton;
@end

static __weak UIViewController *MainController;
static int RequestToken = NOTIFY_TOKEN_INVALID;
static int ResultToken = NOTIFY_TOKEN_INVALID;
static int StageToken = NOTIFY_TOKEN_INVALID;
static uint64_t Pending;
static uint8_t Action;
static BOOL Invoked;
static UIBackgroundTaskIdentifier BackgroundTask;
static NETunnelProviderSession *Session;
static void (*OriginalViewDidLoad)(id, SEL);
static BOOL (*OriginalStartTunnel)(id, SEL, NSDictionary *, NSError **);
static void (*OriginalPresent)(id, SEL, UIViewController *, BOOL, void (^)(void));

static UIViewController *FindController(UIViewController *controller) {
    if (!controller) return nil;
    if ([NSStringFromClass(controller.class) isEqualToString:@"ViewController"]) return controller;
    for (UIViewController *child in controller.childViewControllers) {
        UIViewController *found = FindController(child);
        if (found) return found;
    }
    return nil;
}

static void Stage(uint64_t value) {
    if (StageToken != NOTIFY_TOKEN_INVALID) notify_set_state(StageToken, value);
}

static void Finish(uint64_t request, EasyResult result) {
    if (!request || Pending != request) return;
    Pending = 0;
    Invoked = NO;
    Action = 0;
    Session = nil;
    if (ResultToken != NOTIFY_TOKEN_INVALID) {
        notify_set_state(ResultToken, request * 16 + result);
        notify_post(EasyResultName);
    }
    if (BackgroundTask != UIBackgroundTaskInvalid) {
        UIBackgroundTaskIdentifier task = BackgroundTask;
        BackgroundTask = UIBackgroundTaskInvalid;
        [UIApplication.sharedApplication endBackgroundTask:task];
    }
    NSLog(@"[EasyNative] result=%u", result);
}

static void CheckSession(uint64_t request) {
    if (Pending != request || !Session) return;
    if (Action == 1 && Session.status == NEVPNStatusConnected) Finish(request, EasyConnected);
    else if (Action == 2 && Session.status == NEVPNStatusDisconnected) Finish(request, EasyDisconnected);
}

static void InvokeIfReady(void) {
    if (!Pending || Invoked || !Session) return;
    uint64_t request = Pending;
    UIApplication *app = UIApplication.sharedApplication;
    if (!app.protectedDataAvailable) { Finish(request, EasyLocked); return; }
    if (!MainController) {
        for (UIScene *scene in app.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                MainController = FindController(window.rootViewController);
                if (MainController) break;
            }
            if (MainController) break;
        }
    }
    UIViewController *controller = MainController;
    if (!controller || !controller.isViewLoaded || app.applicationState == UIApplicationStateInactive) return;
    if (controller.presentedViewController) { Finish(request, EasyInteractionRequired); return; }
    SEL selector = Action == 1 ? @selector(startButtonClick:) : @selector(stopButtonClick:);
    if (![controller respondsToSelector:selector]) { Finish(request, EasyUnavailable); return; }
    Invoked = YES;
    Stage(3);
    // Exact original button action, including existing prompts and purchase checks.
    // Never invoke prepareStartVPN/startVPN directly or fabricate tunnel options.
    @try {
        if (Action == 1) [controller startButtonClick:[controller startButton]];
        else [controller stopButtonClick:[controller stopButton]];
    } @catch (NSException *exception) {
        (void)exception;
        Finish(request, EasyFailed);
    }
}

static void HandleRequest(void) {
    if (Pending) return;
    uint64_t request = 0;
    if (notify_get_state(RequestToken, &request) != NOTIFY_STATUS_OK) return;
    uint8_t action = request % 4;
    NSTimeInterval remaining = (NSTimeInterval)(request / 4) / 1000 - NSDate.date.timeIntervalSince1970;
    if ((action != 1 && action != 2) || remaining <= 0 || remaining > EasyLifetime + 1) return;
    if (notify_set_state(RequestToken, 0) != NOTIFY_STATUS_OK) return;
    Pending = request;
    Action = action;
    Stage(2);
    BackgroundTask = [UIApplication.sharedApplication beginBackgroundTaskWithName:@"EasyVPN.native-request"
        expirationHandler:^{ Finish(request, EasyTimedOut); }];
    if (BackgroundTask == UIBackgroundTaskInvalid) { Finish(request, EasyUnavailable); return; }
    // Read only this App's tunnel status; never serialize any protocol/options.
    [NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:^(NSArray *managers, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (Pending != request) return;
            if (error) { Finish(request, EasyUnavailable); return; }
            NSMutableArray *targets = [NSMutableArray array];
            for (NETunnelProviderManager *manager in managers) {
                if (![manager.protocolConfiguration isKindOfClass:NETunnelProviderProtocol.class]) continue;
                NSString *provider = ((NETunnelProviderProtocol *)manager.protocolConfiguration).providerBundleIdentifier;
                if ([@[@"com.qdtiktok.easyvpn.tunnel", @"com.qdtiktok.easyvpn.tunnel2",
                       @"com.qdtiktok.easyvpn.tunnel3"] containsObject:provider]) [targets addObject:manager];
            }
            if (targets.count != 1) { Finish(request, EasyUnavailable); return; }
            Session = (NETunnelProviderSession *)((NETunnelProviderManager *)targets.firstObject).connection;
            CheckSession(request);
            InvokeIfReady();
        });
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(remaining * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        CheckSession(request);
        Finish(request, EasyTimedOut);
    });
}

static void ViewDidLoad(id self, SEL command) {
    OriginalViewDidLoad(self, command);
    MainController = self;
    Stage(1);
    dispatch_async(dispatch_get_main_queue(), ^{ HandleRequest(); InvokeIfReady(); });
}

static BOOL StartTunnel(id self, SEL command, NSDictionary *options, NSError **error) {
    BOOL started = OriginalStartTunnel(self, command, options, error);
    // Forward unchanged; do not log or retain options, credentials or endpoints.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!Pending || Action != 1) return;
        Session = self;
        Stage(started ? 4 : 5);
        if (!started) Finish(Pending, EasyFailed);
        else CheckSession(Pending);
    });
    return started;
}

static void Present(id self, SEL command, UIViewController *controller, BOOL animated, void (^completion)(void)) {
    // Preserve every native interaction. Mark it as not a one-trigger connection.
    if (Pending) Finish(Pending, EasyInteractionRequired);
    OriginalPresent(self, command, controller, animated, completion);
}

__attribute__((constructor)) static void Initialize(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.qdtiktok.easyvpn"]) return;
        BackgroundTask = UIBackgroundTaskInvalid;
        Class controllerClass = NSClassFromString(@"ViewController");
        if (!controllerClass || !class_getInstanceMethod(controllerClass, @selector(startButtonClick:)) ||
            !class_getInstanceMethod(controllerClass, @selector(stopButtonClick:))) return;
        notify_register_check(EasyResultName, &ResultToken);
        notify_register_check(EasyStageName, &StageToken);
        Stage(0);
        notify_register_dispatch(EasyRequestName, &RequestToken, dispatch_get_main_queue(), ^(int token) {
            (void)token;
            HandleRequest();
        });
        MSHookMessageEx(controllerClass, @selector(viewDidLoad), (IMP)ViewDidLoad, (IMP *)&OriginalViewDidLoad);
        MSHookMessageEx(NETunnelProviderSession.class, @selector(startTunnelWithOptions:andReturnError:),
            (IMP)StartTunnel, (IMP *)&OriginalStartTunnel);
        MSHookMessageEx(UIViewController.class, @selector(presentViewController:animated:completion:),
            (IMP)Present, (IMP *)&OriginalPresent);
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                (void)note; HandleRequest(); InvokeIfReady();
            }];
        [NSNotificationCenter.defaultCenter addObserverForName:NEVPNStatusDidChangeNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                (void)note; CheckSession(Pending);
            }];
        NSLog(@"[EasyNative] helper loaded");
    }
}
