#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <sys/stat.h>

static FILE *logFile = NULL;
static const NSUInteger kMaxLogSize = 512 * 1024;
static NSString *const kLogPath = @"/var/mobile/Documents/PiPArrowHide.log";
static NSMutableDictionary *sExtraAssertionsByPid = nil;

typedef NS_ENUM(NSInteger, DoubaoPiPIdentity) {
    DoubaoPiPIdentityUnknown = 0,
    DoubaoPiPIdentityDoubao,
    DoubaoPiPIdentityNonDoubao,
};

static void WriteLog(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);
static void WriteLog(NSString *format, ...) {
    if (!logFile) {
        struct stat st;
        if (stat(kLogPath.UTF8String, &st) == 0 && (NSUInteger)st.st_size >= kMaxLogSize) {
            logFile = fopen(kLogPath.UTF8String, "w");
        } else {
            logFile = fopen(kLogPath.UTF8String, "a");
        }
    }
    if (!logFile) return;
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSDate *now = [NSDate date];
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"HH:mm:ss";
    NSString *ts = [fmt stringFromDate:now];
    fprintf(logFile, "[%s] %s\n", ts.UTF8String, msg.UTF8String);
    fflush(logFile);
}

static BOOL IsDoubaoBundleID(id value) {
    return [value isKindOfClass:[NSString class]] && [(NSString *)value isEqualToString:@"com.bytedance.ios.doubaoime"];
}

static DoubaoPiPIdentity IdentityFromBundleID(id value) {
    if (![value isKindOfClass:[NSString class]]) return DoubaoPiPIdentityUnknown;

    NSString *bundleID = (NSString *)value;
    if (bundleID.length == 0) return DoubaoPiPIdentityUnknown;
    return IsDoubaoBundleID(bundleID) ? DoubaoPiPIdentityDoubao : DoubaoPiPIdentityNonDoubao;
}

static id SafeKVC(id object, NSString *key) {
    if (!object || key.length == 0) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (NSException *e) {
        return nil;
    }
}

static NSString *SafeClassName(id object) {
    if (!object) return nil;
    @try {
        return NSStringFromClass(object_getClass(object));
    } @catch (NSException *e) {
        return nil;
    }
}

static DoubaoPiPIdentity IdentityFromProcess(id process) {
    if (!process) return DoubaoPiPIdentityUnknown;

    @try {
        if ([process respondsToSelector:@selector(bundleIdentifier)]) {
            DoubaoPiPIdentity identity = IdentityFromBundleID([process performSelector:@selector(bundleIdentifier)]);
            if (identity != DoubaoPiPIdentityUnknown) return identity;
        }
        if ([process respondsToSelector:@selector(bundleID)]) {
            DoubaoPiPIdentity identity = IdentityFromBundleID([process performSelector:@selector(bundleID)]);
            if (identity != DoubaoPiPIdentityUnknown) return identity;
        }
    } @catch (NSException *e) {}

    DoubaoPiPIdentity identity = IdentityFromBundleID(SafeKVC(process, @"bundleIdentifier"));
    if (identity != DoubaoPiPIdentityUnknown) return identity;

    return IdentityFromBundleID(SafeKVC(process, @"bundleID"));
}

static DoubaoPiPIdentity IdentityFromPegasusApp(id pipCtrl) {
    if (!pipCtrl) return DoubaoPiPIdentityUnknown;

    id adapter = SafeKVC(pipCtrl, @"_adapter");
    if (!adapter) return DoubaoPiPIdentityUnknown;

    id pegasus = SafeKVC(adapter, @"_pegasusController");
    if (!pegasus) return DoubaoPiPIdentityUnknown;

    id activeApp = SafeKVC(pegasus, @"_activePictureInPictureApplication");
    if (!activeApp) return DoubaoPiPIdentityUnknown;

    id bundleID = SafeKVC(activeApp, @"_bundleIdentifier");
    if (bundleID) {
        DoubaoPiPIdentity identity = IdentityFromBundleID(bundleID);
        if (identity != DoubaoPiPIdentityUnknown) {
            WriteLog(@"[IDENTIFY] Pegasus resolved identity=%ld bundleID=%@", (long)identity, bundleID);
            return identity;
        }
    }

    return DoubaoPiPIdentityUnknown;
}

static DoubaoPiPIdentity IdentityFromPiPController(id pipCtrl) {
    if (!pipCtrl) return DoubaoPiPIdentityUnknown;

    NSArray *bundleKeys = @[
        @"_bundleIDForAppAnimatingPIPStartInBackground",
        @"_bundleIDForAppRecentlyStoppingPIP"
    ];
    for (NSString *key in bundleKeys) {
        id val = SafeKVC(pipCtrl, key);
        DoubaoPiPIdentity identity = IdentityFromBundleID(val);
        if (identity != DoubaoPiPIdentityUnknown) {
            WriteLog(@"[IDENTIFY] SBPIPCtrl resolved identity=%ld via %@ val=%@", (long)identity, key, val);
            return identity;
        }
    }

    NSArray *processKeys = @[@"_pipProcess", @"_applicationProcess"];
    for (NSString *key in processKeys) {
        id proc = SafeKVC(pipCtrl, key);
        DoubaoPiPIdentity identity = IdentityFromProcess(proc);
        if (identity != DoubaoPiPIdentityUnknown) {
            WriteLog(@"[IDENTIFY] SBPIPCtrl resolved identity=%ld via %@", (long)identity, key);
            return identity;
        }
    }

    return IdentityFromPegasusApp(pipCtrl);
}

static BOOL IsDoubaoPiPController(id pipCtrl) {
    return IdentityFromPiPController(pipCtrl) == DoubaoPiPIdentityDoubao;
}

static UIView *FindViewByClassName(UIView *view, NSString *className, NSUInteger maxDepth) {
    if (!view || className.length == 0) return nil;
    if ([SafeClassName(view) isEqualToString:className]) return view;
    if (maxDepth == 0) return nil;

    for (UIView *subview in view.subviews) {
        UIView *found = FindViewByClassName(subview, className, maxDepth - 1);
        if (found) return found;
    }
    return nil;
}

static NSUInteger CountDirectSubviewClass(UIView *view, NSString *className, BOOL hidden) {
    if (!view || className.length == 0) return 0;

    NSUInteger count = 0;
    for (UIView *subview in view.subviews) {
        if ([SafeClassName(subview) isEqualToString:className] && subview.hidden == hidden) {
            count++;
        }
    }
    return count;
}

static BOOL ViewIsHiddenOrTransparent(UIView *view) {
    return !view || view.hidden || view.alpha < 0.05;
}

static BOOL RectLooksLikeDoubaoPiP(CGRect rect) {
    CGFloat width = CGRectGetWidth(rect);
    CGFloat height = CGRectGetHeight(rect);
    if (width < 160.0 || width > 260.0 || height < 90.0 || height > 150.0) return NO;

    CGFloat aspect = width / MAX(height, 1.0);
    return aspect > 1.55 && aspect < 1.95;
}

static BOOL IsLikelyDoubaoPiPWindowByViewTree(UIWindow *window) {
    UIView *rootView = window.rootViewController.view;
    if (!rootView) return NO;

    UIView *hitTestView = FindViewByClassName(rootView, @"PGHitTestExtendableView", 8);
    if (!hitTestView || !RectLooksLikeDoubaoPiP(hitTestView.frame)) return NO;

    UIView *layoutView = FindViewByClassName(rootView, @"PGLayoutContainerView", 8);
    UIView *progressView = FindViewByClassName(rootView, @"PGProgressIndicator", 8);
    UIView *backdropView = FindViewByClassName(rootView, @"PGCABackdropLayerView", 8);
    UIView *dimmingView = FindViewByClassName(rootView, @"PGDimmingView", 8);
    UIView *stashView = FindViewByClassName(rootView, @"PGStashView", 8);

    if (!layoutView || !progressView || !backdropView || !dimmingView || !stashView) return NO;
    if (!ViewIsHiddenOrTransparent(progressView)) return NO;
    if (!ViewIsHiddenOrTransparent(backdropView)) return NO;
    if (!ViewIsHiddenOrTransparent(dimmingView)) return NO;
    if (!stashView.hidden) return NO;

    NSUInteger hiddenButtons = CountDirectSubviewClass(layoutView, @"PGButtonView", YES);
    NSUInteger visibleButtons = CountDirectSubviewClass(layoutView, @"PGButtonView", NO);
    return hiddenButtons >= 3 && visibleButtons <= 2;
}

static BOOL HasMultiplePiPWindows(void) {
    NSUInteger count = 0;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    NSArray *allWindows = [(id)[UIApplication sharedApplication] performSelector:NSSelectorFromString(@"windows")];
#pragma clang diagnostic pop
    for (UIWindow *w in allWindows) {
        if ([SafeClassName(w) isEqualToString:@"SBPictureInPictureWindow"]) {
            count++;
            if (count >= 2) return YES;
        }
    }
    return NO;
}

static BOOL IsDoubaoPiPWindow(UIWindow *window) {
    if (!window) return NO;
    if (![SafeClassName(window) isEqualToString:@"SBPictureInPictureWindow"]) return NO;

    UIViewController *rvc = window.rootViewController;
    if (!rvc) return NO;

    id pipCtrl = SafeKVC(rvc, @"_pipController");
    DoubaoPiPIdentity identity = IdentityFromPiPController(pipCtrl);

    // When only one PiP window exists, global identity is trustworthy
    if (!HasMultiplePiPWindows()) {
        if (identity == DoubaoPiPIdentityDoubao) {
            WriteLog(@"[IDENTIFY] single-PiP identity=Doubao, hiding");
            return YES;
        }
        if (identity == DoubaoPiPIdentityNonDoubao) {
            WriteLog(@"[IDENTIFY] single-PiP identity=NonDoubao, keeping");
            return NO;
        }
    } else {
        // Multiple PiP windows: global identity is unreliable (points to
        // whichever app activated PiP last), so use per-window view tree
        WriteLog(@"[IDENTIFY] multi-PiP detected identity=%ld, using viewTree", (long)identity);
        return IsLikelyDoubaoPiPWindowByViewTree(window);
    }

    WriteLog(@"[IDENTIFY] identity unknown, falling back to viewTree");
    return IsLikelyDoubaoPiPWindowByViewTree(window);
}

static pid_t GetDoubaoPid(id pipCtrl) {
    if (!pipCtrl) return 0;
    @try {
        id process = [pipCtrl valueForKey:@"_pipProcess"];
        if (process && [process respondsToSelector:@selector(processID)]) {
            return (pid_t)[(NSNumber *)[process performSelector:@selector(processID)] intValue];
        }
        id appProcess = [pipCtrl valueForKey:@"_applicationProcess"];
        if (appProcess && [appProcess respondsToSelector:@selector(processID)]) {
            return (pid_t)[(NSNumber *)[appProcess performSelector:@selector(processID)] intValue];
        }
    } @catch (NSException *e) {
        WriteLog(@"[KEEPALIVE] GetDoubaoPid error: %@", e.reason);
    }
    return 0;
}

static void AcquireExtraAssertion(pid_t pid) {
    if (pid == 0) return;

    NSNumber *pidKey = @(pid);
    if (!sExtraAssertionsByPid) {
        sExtraAssertionsByPid = [NSMutableDictionary new];
    }
    if (sExtraAssertionsByPid[pidKey]) {
        return;
    }

    Class assertionClass = NSClassFromString(@"BKSProcessAssertion");
    if (!assertionClass) {
        WriteLog(@"[KEEPALIVE] BKSProcessAssertion class not found");
        return;
    }

    NSUInteger flags = 0x200;
    NSString *reason = @"HideDoubaoPiP KeepAlive";
    NSString *name = @"com.dada.hidedoubaopip.keepalive";

    SEL initSel = NSSelectorFromString(@"initWithPID:flags:reason:name:");
    if (![assertionClass instancesRespondToSelector:initSel]) {
        WriteLog(@"[KEEPALIVE] BKSProcessAssertion does not respond to initWithPID:flags:reason:name:");
        return;
    }

    id (*msgSend)(id, SEL, pid_t, NSUInteger, NSString *, NSString *) =
        (id (*)(id, SEL, pid_t, NSUInteger, NSString *, NSString *))objc_msgSend;

    id assertion = msgSend([assertionClass alloc], initSel, pid, flags, reason, name);
    if (assertion) {
        sExtraAssertionsByPid[pidKey] = assertion;
        WriteLog(@"[KEEPALIVE] Acquired extra assertion for pid=%d flags=0x%lx", pid, (unsigned long)flags);
    } else {
        WriteLog(@"[KEEPALIVE] Failed to create assertion for pid=%d", pid);
    }
}

static void HideDoubaoWindow(UIWindow *window, NSString *reason) {
    if (!window) return;

    NSString *windowClass = SafeClassName(window);
    BOOL isPiPWindow = [windowClass isEqualToString:@"SBPictureInPictureWindow"];
    WriteLog(@"[HIDE-CALL] reason=%@ class=%@ isPiP=%d alpha=%.2f userInteraction=%d",
             reason, windowClass, isPiPWindow, window.alpha, window.userInteractionEnabled);

    if (!isPiPWindow) return;

    // When multiple PiP windows exist, check ALL of them — the triggering
    // window might not be the Doubao one, but a coexisting one might be.
    if (HasMultiplePiPWindows()) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        NSArray *allWindows = [(id)[UIApplication sharedApplication] performSelector:NSSelectorFromString(@"windows")];
#pragma clang diagnostic pop
        for (UIWindow *w in allWindows) {
            if ([SafeClassName(w) isEqualToString:@"SBPictureInPictureWindow"]) {
                BOOL wIsDoubao = IsDoubaoPiPWindow(w);
                WriteLog(@"[HIDE-COEX] ptr=%p alpha=%.2f hidden=%d isDoubao=%d",
                         w, w.alpha, w.hidden, wIsDoubao);
                if (wIsDoubao && w.alpha != 0.0) {
                    w.alpha = 0.0;
                    w.userInteractionEnabled = NO;
                    WriteLog(@"[WINDOW] Hidden coexisting Doubao PiP ptr=%p reason=%@", w, reason);

                    UIViewController *wRvc = w.rootViewController;
                    if (wRvc) {
                        id wPipCtrl = SafeKVC(wRvc, @"_pipController");
                        if (wPipCtrl) {
                            pid_t pid = GetDoubaoPid(wPipCtrl);
                            if (pid > 0) AcquireExtraAssertion(pid);
                        }
                    }
                }
            }
        }
        return;
    }

    // Single PiP window: direct check
    BOOL isDoubao = IsDoubaoPiPWindow(window);
    WriteLog(@"[HIDE-IDENT] isDoubao=%d for reason=%@ ptr=%p", isDoubao, reason, window);

    if (!isDoubao) return;

    BOOL changed = NO;
    if (window.alpha != 0.0) {
        window.alpha = 0.0;
        changed = YES;
    }
    if (window.userInteractionEnabled) {
        window.userInteractionEnabled = NO;
        changed = YES;
    }

    UIViewController *rvc = window.rootViewController;
    if (rvc) {
        id pipCtrl = SafeKVC(rvc, @"_pipController");
        if (IsDoubaoPiPController(pipCtrl)) {
            pid_t pid = GetDoubaoPid(pipCtrl);
            if (pid > 0) {
                AcquireExtraAssertion(pid);
            }
        }
    }

    if (changed) {
        WriteLog(@"[WINDOW] Transparent Doubao PiP window reason=%@", reason);
    }
}

static void HideDoubaoWindowForView(UIView *view, NSString *reason) {
    if (!view) return;
    HideDoubaoWindow(view.window, reason);
}

@interface SBPictureInPictureWindow : UIWindow
@end

@interface SBPIPController : NSObject
@end

%hook SBPictureInPictureWindow

- (void)didMoveToWindow {
    %orig;
    HideDoubaoWindow(self, @"didMoveToWindow");
}

- (void)layoutSubviews {
    %orig;
    HideDoubaoWindow(self, @"layoutSubviews");
}

- (void)setAlpha:(CGFloat)alpha {
    if (IsDoubaoPiPWindow(self)) {
        WriteLog(@"[SETALPHA] blocked alpha=%.2f -> 0.0 ptr=%p", alpha, self);
        %orig(0.0);
        HideDoubaoWindow(self, @"setAlpha");
        return;
    }
    WriteLog(@"[SETALPHA] passed alpha=%.2f ptr=%p", alpha, self);
    %orig;
}

- (void)setHidden:(BOOL)hidden {
    %orig;
    if (!hidden) {
        HideDoubaoWindow(self, @"setHidden");
    }
}

%end

%hook SBPIPContainerViewController

- (void)viewDidLayoutSubviews {
    %orig;
    HideDoubaoWindowForView(((UIViewController *)self).view, @"containerViewDidLayout");
}

%end

%hook PGHitTestExtendableView

- (void)layoutSubviews {
    %orig;
    HideDoubaoWindowForView((UIView *)self, @"hitTestLayout");
}

%end

%hook PGControlsView

- (void)layoutSubviews {
    %orig;
    HideDoubaoWindowForView((UIView *)self, @"controlsLayout");
}

%end

%hook PGLayoutContainerView

- (void)layoutSubviews {
    %orig;
    HideDoubaoWindowForView((UIView *)self, @"layoutContainerLayout");
}

%end

%hook SBPIPController

- (void)invalidateIdleTimerBehaviors {
    if (IsDoubaoPiPController(self)) {
        WriteLog(@"[KEEPALIVE] Blocked invalidateIdleTimerBehaviors for Doubao PiP");
        return;
    }
    %orig;
}

%end

%ctor {
    WriteLog(@"[INIT] HideDoubaoPiP v0.0.6");
}
