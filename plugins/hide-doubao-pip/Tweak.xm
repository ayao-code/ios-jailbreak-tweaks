#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <sys/stat.h>
#import <time.h>

static FILE *logFile = NULL;
static const NSUInteger kMaxLogSize = 256 * 1024;
static NSString *const kLogPath = @"/var/mobile/Documents/PiPArrowHide.log";
static const NSTimeInterval kPiPWindowCountCacheInterval = 0.10;
static NSTimeInterval sLastPiPWindowCountCheckTime = 0;
static BOOL sLastHasMultipleActivePiPWindows = NO;
static NSMutableDictionary<NSString *, NSNumber *> *sThrottleTimes = nil;

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

static BOOL ShouldRunThrottled(NSString *key, NSTimeInterval interval) {
    if (key.length == 0) return YES;
    if (!sThrottleTimes) sThrottleTimes = [NSMutableDictionary dictionary];

    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSNumber *last = sThrottleTimes[key];
    if (last && now - last.doubleValue < interval) return NO;

    sThrottleTimes[key] = @(now);
    return YES;
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

static NSString *StringValue(id value) {
    return [value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0 ? value : nil;
}

static BOOL IsDoubaoBundleID(id value) {
    return [value isKindOfClass:[NSString class]] && [(NSString *)value isEqualToString:@"com.bytedance.ios.doubaoime"];
}

static DoubaoPiPIdentity IdentityFromBundleID(id value) {
    NSString *bundleID = StringValue(value);
    if (bundleID.length == 0) return DoubaoPiPIdentityUnknown;
    return IsDoubaoBundleID(bundleID) ? DoubaoPiPIdentityDoubao : DoubaoPiPIdentityNonDoubao;
}

static NSString *BundleIDFromProcess(id process) {
    if (!process) return nil;

    @try {
        if ([process respondsToSelector:@selector(bundleIdentifier)]) {
            NSString *bundleID = StringValue([process performSelector:@selector(bundleIdentifier)]);
            if (bundleID.length > 0) return bundleID;
        }
        if ([process respondsToSelector:@selector(bundleID)]) {
            NSString *bundleID = StringValue([process performSelector:@selector(bundleID)]);
            if (bundleID.length > 0) return bundleID;
        }
    } @catch (NSException *e) {}

    NSString *bundleID = StringValue(SafeKVC(process, @"bundleIdentifier"));
    if (bundleID.length > 0) return bundleID;
    return StringValue(SafeKVC(process, @"bundleID"));
}

static NSString *BundleIDFromPegasusApp(id pipCtrl) {
    id adapter = SafeKVC(pipCtrl, @"_adapter");
    id pegasus = SafeKVC(adapter, @"_pegasusController");
    id activeApp = SafeKVC(pegasus, @"_activePictureInPictureApplication");
    return StringValue(SafeKVC(activeApp, @"_bundleIdentifier"));
}

static NSString *BundleIDFromPiPController(id pipCtrl) {
    if (!pipCtrl) return nil;

    NSArray *bundleKeys = @[
        @"_bundleIDForAppAnimatingPIPStartInBackground",
        @"_bundleIDForAppRecentlyStoppingPIP"
    ];
    for (NSString *key in bundleKeys) {
        NSString *bundleID = StringValue(SafeKVC(pipCtrl, key));
        if (bundleID.length > 0) return bundleID;
    }

    NSArray *processKeys = @[@"_pipProcess", @"_applicationProcess"];
    for (NSString *key in processKeys) {
        NSString *bundleID = BundleIDFromProcess(SafeKVC(pipCtrl, key));
        if (bundleID.length > 0) return bundleID;
    }

    return BundleIDFromPegasusApp(pipCtrl);
}

static DoubaoPiPIdentity IdentityFromPiPController(id pipCtrl) {
    return IdentityFromBundleID(BundleIDFromPiPController(pipCtrl));
}

static id PiPControllerFromWindow(UIWindow *window) {
    return SafeKVC(window.rootViewController, @"_pipController");
}

static NSString *BundleIDFromPiPWindow(UIWindow *window) {
    return BundleIDFromPiPController(PiPControllerFromWindow(window));
}

static DoubaoPiPIdentity IdentityFromPiPWindow(UIWindow *window) {
    return IdentityFromPiPController(PiPControllerFromWindow(window));
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
    if (width < 150.0 || width > 340.0 || height < 80.0 || height > 220.0) return NO;

    CGFloat aspect = width / MAX(height, 1.0);
    return aspect > 1.35 && aspect < 2.35;
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

    NSUInteger hiddenButtons = CountDirectSubviewClass(layoutView, @"PGButtonView", YES);
    NSUInteger visibleButtons = CountDirectSubviewClass(layoutView, @"PGButtonView", NO);
    return hiddenButtons >= 3 && visibleButtons <= 2 && stashView.hidden;
}

static NSArray<UIWindow *> *SpringBoardWindows(void) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    NSArray *windows = [(id)[UIApplication sharedApplication] performSelector:NSSelectorFromString(@"windows")];
#pragma clang diagnostic pop
    return windows ?: @[];
}

static BOOL HasMultipleActivePiPWindows(UIWindow *candidate, BOOL forceRefresh) {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (!forceRefresh && sLastPiPWindowCountCheckTime > 0 && now - sLastPiPWindowCountCheckTime < kPiPWindowCountCacheInterval) {
        return sLastHasMultipleActivePiPWindows;
    }

    NSUInteger count = 0;
    for (UIWindow *window in SpringBoardWindows()) {
        if (window == candidate || IsVisiblePiPWindow(window)) {
            count++;
            if (count >= 2) break;
        }
    }

    sLastPiPWindowCountCheckTime = now;
    sLastHasMultipleActivePiPWindows = count >= 2;
    return sLastHasMultipleActivePiPWindows;
}

static BOOL IsDoubaoPiPWindowWithRefresh(UIWindow *window, BOOL forceRefresh) {
    if (!window || !IsPiPWindow(window)) return NO;

    DoubaoPiPIdentity identity = IdentityFromPiPWindow(window);
    if (!HasMultipleActivePiPWindows(window, forceRefresh)) {
        if (identity == DoubaoPiPIdentityDoubao) return YES;
        if (identity == DoubaoPiPIdentityNonDoubao) return NO;
    } else if (identity != DoubaoPiPIdentityUnknown) {
        return identity == DoubaoPiPIdentityDoubao;
    }

    return IsLikelyDoubaoPiPWindowByViewTree(window);
}

static void AddViewIfPresent(NSMutableArray<UIView *> *views, UIView *view) {
    if (!view || [views containsObject:view]) return;
    [views addObject:view];
}

static NSArray<UIView *> *DoubaoContentHideTargets(UIWindow *window) {
    UIView *root = window.rootViewController.view;
    if (!root) return @[];

    NSMutableArray<UIView *> *targets = [NSMutableArray array];
    AddViewIfPresent(targets, FindViewByClassName(root, @"PGLayoutContainerView", 8));
    AddViewIfPresent(targets, FindViewByClassName(root, @"PGControlsView", 8));
    AddViewIfPresent(targets, FindViewByClassName(root, @"PGDimmingView", 8));
    AddViewIfPresent(targets, FindViewByClassName(root, @"PGCABackdropLayerView", 8));
    AddViewIfPresent(targets, FindViewByClassName(root, @"PGProgressIndicator", 8));
    return targets;
}

static UIView *DoubaoHitView(UIWindow *window) {
    return FindViewByClassName(window.rootViewController.view, @"PGHitTestExtendableView", 8);
}

static void HideSingleDoubaoWindow(UIWindow *window, NSString *reason) {
    UIView *hitView = DoubaoHitView(window);
    NSArray<UIView *> *targets = DoubaoContentHideTargets(window);
    BOOL changed = NO;
    CGFloat beforeHitOpacity = hitView ? hitView.layer.opacity : -1.0;
    if (hitView && beforeHitOpacity > 0.01) changed = YES;
    hitView.layer.opacity = 0.0;

    NSUInteger restoredTargets = 0;
    for (UIView *target in targets) {
        if (target.alpha > 0.01 || target.userInteractionEnabled) {
            changed = YES;
            restoredTargets++;
        }
        target.alpha = 0.0;
        target.userInteractionEnabled = NO;
    }

    if (changed || ShouldRunThrottled([NSString stringWithFormat:@"hide-sample-%p", window], 30.0)) {
        WriteLog(@"[HIDE] reason=%@ mode=hitLayerContent changed=%d bundle=%@ hitOpacity=%.3f->%.3f restoredTargets=%lu targets=%lu windowAlpha=%.3f windowHidden=%d",
                 reason ?: @"unknown",
                 changed,
                 BundleIDFromPiPWindow(window) ?: @"nil",
                 beforeHitOpacity,
                 hitView ? hitView.layer.opacity : -1.0,
                 (unsigned long)restoredTargets,
                 (unsigned long)targets.count,
                 window.alpha,
                 window.hidden);
    }
}

static void HideDoubaoWindow(UIWindow *window, NSString *reason) {
    if (!window || !IsPiPWindow(window)) return;

    BOOL forceRefresh = [reason isEqualToString:@"didMoveToWindow"] || [reason isEqualToString:@"setHidden"] || [reason isEqualToString:@"setAlpha"];

    if (HasMultipleActivePiPWindows(window, forceRefresh)) {
        for (UIWindow *candidate in SpringBoardWindows()) {
            if (!IsVisiblePiPWindow(candidate)) continue;
            if (!IsDoubaoPiPWindowWithRefresh(candidate, forceRefresh)) continue;
            HideSingleDoubaoWindow(candidate, reason);
        }
        return;
    }

    if (!IsVisiblePiPWindow(window)) return;

    if (!IsDoubaoPiPWindowWithRefresh(window, forceRefresh)) return;

    HideSingleDoubaoWindow(window, reason);
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
    %orig;
    if (alpha > 0.01 && IsDoubaoPiPWindowWithRefresh(self, YES)) {
        HideSingleDoubaoWindow(self, @"setAlpha");
    }
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
    WriteLog(@"[INIT] HideDoubaoPiP v1.0.23 hit-layer-content-hide-release");
}
