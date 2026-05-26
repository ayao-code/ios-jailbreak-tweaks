#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <sys/stat.h>
#import <time.h>

static FILE *logFile = NULL;
static const NSUInteger kMaxLogSize = 512 * 1024;
static NSString *const kLogPath = @"/var/mobile/Documents/PiPArrowHide.log";
static const NSTimeInterval kPiPWindowCountCacheInterval = 0.10;
static NSTimeInterval sLastPiPWindowCountCheckTime = 0;
static BOOL sLastHasMultipleActivePiPWindows = NO;

typedef NS_ENUM(NSInteger, DoubaoPiPIdentity) {
    DoubaoPiPIdentityUnknown = 0,
    DoubaoPiPIdentityDoubao,
    DoubaoPiPIdentityNonDoubao,
};

static void WriteLog(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);
static void WriteLog(NSString *format, ...) {
    struct stat st;
    BOOL shouldResetLog = stat(kLogPath.UTF8String, &st) == 0 && (NSUInteger)st.st_size >= kMaxLogSize;
    if (logFile && shouldResetLog) {
        fclose(logFile);
        logFile = NULL;
    }
    if (!logFile) {
        logFile = fopen(kLogPath.UTF8String, shouldResetLog ? "w" : "a");
    }
    if (!logFile) return;
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    time_t rawTime;
    time(&rawTime);
    struct tm timeInfo;
    localtime_r(&rawTime, &timeInfo);
    char ts[16];
    strftime(ts, sizeof(ts), "%H:%M:%S", &timeInfo);
    fprintf(logFile, "[%s] %s\n", ts, msg.UTF8String);
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

    return IdentityFromBundleID(SafeKVC(activeApp, @"_bundleIdentifier"));
}

static DoubaoPiPIdentity IdentityFromPiPControllerLocal(id pipCtrl) {
    if (!pipCtrl) return DoubaoPiPIdentityUnknown;

    NSArray *bundleKeys = @[
        @"_bundleIDForAppAnimatingPIPStartInBackground",
        @"_bundleIDForAppRecentlyStoppingPIP"
    ];
    for (NSString *key in bundleKeys) {
        DoubaoPiPIdentity identity = IdentityFromBundleID(SafeKVC(pipCtrl, key));
        if (identity != DoubaoPiPIdentityUnknown) return identity;
    }

    NSArray *processKeys = @[@"_pipProcess", @"_applicationProcess"];
    for (NSString *key in processKeys) {
        DoubaoPiPIdentity identity = IdentityFromProcess(SafeKVC(pipCtrl, key));
        if (identity != DoubaoPiPIdentityUnknown) return identity;
    }

    return DoubaoPiPIdentityUnknown;
}

static BOOL IsPiPWindow(UIWindow *window) {
    return [SafeClassName(window) isEqualToString:@"SBPictureInPictureWindow"];
}

static BOOL IsVisiblePiPWindow(UIWindow *window) {
    return IsPiPWindow(window) && !window.hidden && window.alpha > 0.01;
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

static DoubaoPiPIdentity IdentityFromPiPController(id pipCtrl) {
    DoubaoPiPIdentity identity = IdentityFromPiPControllerLocal(pipCtrl);
    if (identity != DoubaoPiPIdentityUnknown) return identity;

    return IdentityFromPegasusApp(pipCtrl);
}

static BOOL HasMultipleActivePiPWindows(UIWindow *candidate, BOOL forceRefresh) {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (!forceRefresh && sLastPiPWindowCountCheckTime > 0 && now - sLastPiPWindowCountCheckTime < kPiPWindowCountCacheInterval) {
        return sLastHasMultipleActivePiPWindows;
    }

    NSUInteger count = 0;
    BOOL hasMultiple = NO;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    NSArray *allWindows = [(id)[UIApplication sharedApplication] performSelector:NSSelectorFromString(@"windows")];
#pragma clang diagnostic pop
    for (UIWindow *w in allWindows) {
        if (w == candidate || IsVisiblePiPWindow(w)) {
            count++;
            if (count >= 2) {
                hasMultiple = YES;
                break;
            }
        }
    }

    sLastPiPWindowCountCheckTime = now;
    sLastHasMultipleActivePiPWindows = hasMultiple;
    return hasMultiple;
}

static BOOL IsDoubaoPiPWindowWithRefresh(UIWindow *window, BOOL forceRefresh) {
    if (!window) return NO;
    if (!IsPiPWindow(window)) return NO;

    UIViewController *rvc = window.rootViewController;
    if (!rvc) return NO;

    id pipCtrl = SafeKVC(rvc, @"_pipController");
    DoubaoPiPIdentity identity = IdentityFromPiPController(pipCtrl);

    if (!HasMultipleActivePiPWindows(window, forceRefresh)) {
        if (identity == DoubaoPiPIdentityDoubao) return YES;
        if (identity == DoubaoPiPIdentityNonDoubao) return NO;
    } else {
        return IsLikelyDoubaoPiPWindowByViewTree(window);
    }

    return IsLikelyDoubaoPiPWindowByViewTree(window);
}

static BOOL IsDoubaoPiPWindow(UIWindow *window) {
    return IsDoubaoPiPWindowWithRefresh(window, NO);
}

static void HideDoubaoWindow(UIWindow *window, NSString *reason) {
    if (!window || !IsVisiblePiPWindow(window)) return;

    BOOL forceRefresh = [reason isEqualToString:@"didMoveToWindow"] || [reason isEqualToString:@"setHidden"] || [reason isEqualToString:@"setAlpha"];
    if (HasMultipleActivePiPWindows(window, forceRefresh)) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        NSArray *allWindows = [(id)[UIApplication sharedApplication] performSelector:NSSelectorFromString(@"windows")];
#pragma clang diagnostic pop
        for (UIWindow *w in allWindows) {
            if (!IsVisiblePiPWindow(w)) continue;
            if (!IsDoubaoPiPWindow(w)) continue;

            w.alpha = 0.0;
            w.userInteractionEnabled = NO;
            WriteLog(@"[WINDOW] Hidden Doubao PiP ptr=%p reason=%@", w, reason);
        }
        return;
    }

    if (!IsDoubaoPiPWindowWithRefresh(window, forceRefresh)) return;

    window.alpha = 0.0;
    window.userInteractionEnabled = NO;
    WriteLog(@"[WINDOW] Hidden Doubao PiP ptr=%p reason=%@", window, reason);
}

static void HideDoubaoWindowForView(UIView *view, NSString *reason) {
    if (!view) return;
    HideDoubaoWindow(view.window, reason);
}

@interface SBPictureInPictureWindow : UIWindow
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
    if (alpha > 0.01 && IsDoubaoPiPWindowWithRefresh(self, YES)) {
        %orig(0.0);
        self.userInteractionEnabled = NO;
        return;
    }
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

%ctor {
    WriteLog(@"[INIT] HideDoubaoPiP v1.0.0");
}
