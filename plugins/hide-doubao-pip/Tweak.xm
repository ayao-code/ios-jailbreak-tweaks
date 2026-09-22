#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <notify.h>
#import <objc/message.h>
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
static const void *kWindowLayerMutedKey = &kWindowLayerMutedKey;
static NSString *const kDNJPrepareNotification = @"ayao.hidedoubaopip.visual.prepare";
static NSString *const kDNJReadyNotification = @"ayao.hidedoubaopip.visual.ready";
static NSString *const kDNJAudioActiveNotification = @"ayao.hidedoubaopip.visual.audio_active";
static NSString *const kDNJCompleteNotification = @"ayao.hidedoubaopip.visual.complete";
static NSString *const kDNJDoubaoBundleIdentifier = @"com.bytedance.ios.doubaoime";
static const NSTimeInterval kDNJTransitionTimeout = 6.0;
static const NSTimeInterval kDNJOverlayPresentationDelay = 0.04;
static const NSTimeInterval kDNJPiPWaitAfterAudio = 0.9;
static const NSTimeInterval kDNJForwardTransitionFallbackAfterAudio = 1.35;
static UIWindow *sDNJOverlayWindow = nil;
static NSString *sDNJReturnBundleIdentifier = nil;
static NSUInteger sDNJTransitionGeneration = 0;
static BOOL sDNJTransitionActive = NO;
static BOOL sDNJAudioActive = NO;
static BOOL sDNJPiPReady = NO;
static BOOL sDNJPiPGraceElapsed = NO;
static BOOL sDNJForwardTransitionFinished = NO;
static BOOL sDNJReturnStarted = NO;
static int sDNJPrepareStateToken = 0;

typedef UIImage *(*DNJScreenImageFunction)(void);
static NSArray<UIWindow *> *SpringBoardWindows(void);

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

static void DNJPostNotification(NSString *name) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)name,
                                         NULL,
                                         NULL,
                                         YES);
}

static NSString *DNJFrontmostBundleIdentifier(void) {
    Class userAgentClass = NSClassFromString(@"SBUserAgent");
    SEL sharedUserAgentSelector = NSSelectorFromString(@"sharedUserAgent");
    SEL foregroundSelector = NSSelectorFromString(@"foregroundApplicationDisplayID");
    if ([userAgentClass respondsToSelector:sharedUserAgentSelector]) {
        id userAgent = ((id (*)(id, SEL))objc_msgSend)(userAgentClass, sharedUserAgentSelector);
        if ([userAgent respondsToSelector:foregroundSelector]) {
            NSString *bundleIdentifier = ((id (*)(id, SEL))objc_msgSend)(userAgent, foregroundSelector);
            if (bundleIdentifier.length > 0) return bundleIdentifier;
        }
    }

    id springBoard = UIApplication.sharedApplication;
    SEL frontmostSelector = NSSelectorFromString(@"_accessibilityFrontMostApplication");
    if ([springBoard respondsToSelector:frontmostSelector]) {
        id application = ((id (*)(id, SEL))objc_msgSend)(springBoard, frontmostSelector);
        SEL bundleSelector = NSSelectorFromString(@"bundleIdentifier");
        if ([application respondsToSelector:bundleSelector]) {
            NSString *bundleIdentifier = ((id (*)(id, SEL))objc_msgSend)(application, bundleSelector);
            if (bundleIdentifier.length > 0) return bundleIdentifier;
        }
    }
    return nil;
}

static uint64_t DNJBundleIdentifierHash(NSString *bundleIdentifier) {
    const unsigned char *bytes = (const unsigned char *)bundleIdentifier.UTF8String;
    if (!bytes) return 0;
    uint64_t hash = 1469598103934665603ULL;
    while (*bytes) {
        hash ^= *bytes++;
        hash *= 1099511628211ULL;
    }
    return hash;
}

static NSString *DNJBundleIdentifierFromPrepareState(void) {
    if (sDNJPrepareStateToken == 0) return nil;
    uint64_t expectedHash = 0;
    if (notify_get_state(sDNJPrepareStateToken, &expectedHash) != NOTIFY_STATUS_OK || expectedHash == 0) {
        return nil;
    }

    Class controllerClass = NSClassFromString(@"SBApplicationController");
    SEL sharedSelector = NSSelectorFromString(@"sharedInstance");
    SEL identifiersSelector = NSSelectorFromString(@"allBundleIdentifiers");
    if (![controllerClass respondsToSelector:sharedSelector]) return nil;
    id controller = ((id (*)(id, SEL))objc_msgSend)(controllerClass, sharedSelector);
    if (![controller respondsToSelector:identifiersSelector]) return nil;
    NSArray *bundleIdentifiers = ((id (*)(id, SEL))objc_msgSend)(controller, identifiersSelector);
    for (id value in bundleIdentifiers) {
        if (![value isKindOfClass:NSString.class]) continue;
        NSString *bundleIdentifier = value;
        if (DNJBundleIdentifierHash(bundleIdentifier) == expectedHash) return bundleIdentifier;
    }
    return nil;
}

static UIWindowScene *DNJActiveWindowScene(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        if (windowScene.activationState == UISceneActivationStateForegroundActive ||
            windowScene.activationState == UISceneActivationStateForegroundInactive) {
            return windowScene;
        }
    }
    return nil;
}

static void DNJRemoveOverlay(NSString *reason) {
    if (sDNJOverlayWindow) {
        sDNJOverlayWindow.hidden = YES;
        sDNJOverlayWindow.rootViewController = nil;
        sDNJOverlayWindow = nil;
    }
    WriteLog(@"[VISUAL] overlay removed reason=%@", reason ?: @"unknown");
}

static void DNJFinishTransition(NSString *reason) {
    if (!sDNJTransitionActive) return;
    sDNJTransitionActive = NO;
    sDNJAudioActive = NO;
    sDNJPiPReady = NO;
    sDNJPiPGraceElapsed = NO;
    sDNJForwardTransitionFinished = NO;
    sDNJReturnStarted = NO;
    sDNJReturnBundleIdentifier = nil;
    DNJRemoveOverlay(reason);
    DNJPostNotification(kDNJCompleteNotification);
}

static void DNJReturnToSpotlight(NSString *reason) {
    if (!sDNJTransitionActive || sDNJReturnStarted) return;
    sDNJReturnStarted = YES;
    NSUInteger generation = sDNJTransitionGeneration;
    WriteLog(@"[VISUAL] spotlight exempt return begin reason=%@ generation=%lu",
             reason ?: @"unknown",
             (unsigned long)generation);

    id springBoard = UIApplication.sharedApplication;
    SEL dismissSpotlightSelector = NSSelectorFromString(@"_dismissSpotlightWithHomeButtonEvent");
    SEL homeSelector = NSSelectorFromString(@"_simulateHomeButtonPress");
    BOOL homeRequested = NO;
    if ([springBoard respondsToSelector:dismissSpotlightSelector]) {
        ((void (*)(id, SEL))objc_msgSend)(springBoard, dismissSpotlightSelector);
        homeRequested = YES;
    } else if ([springBoard respondsToSelector:homeSelector]) {
        ((void (*)(id, SEL))objc_msgSend)(springBoard, homeSelector);
        homeRequested = YES;
    } else {
        Class uiControllerClass = NSClassFromString(@"SBUIController");
        SEL sharedSelector = NSSelectorFromString(@"sharedInstance");
        SEL clickSelector = NSSelectorFromString(@"clickedMenuButton");
        if ([uiControllerClass respondsToSelector:sharedSelector]) {
            id uiController = ((id (*)(id, SEL))objc_msgSend)(uiControllerClass, sharedSelector);
            if ([uiController respondsToSelector:clickSelector]) {
                ((BOOL (*)(id, SEL))objc_msgSend)(uiController, clickSelector);
                homeRequested = YES;
            }
        }
    }
    if (!homeRequested) {
        DNJFinishTransition(@"spotlight_home_unavailable");
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (generation == sDNJTransitionGeneration && sDNJTransitionActive) {
            DNJFinishTransition(@"spotlight_exempt_home");
        }
    });
}

static void DNJReturnToSource(NSString *reason) {
    if (!sDNJTransitionActive || sDNJReturnStarted) return;
    NSString *bundleIdentifier = sDNJReturnBundleIdentifier;
    if (bundleIdentifier.length == 0 || [bundleIdentifier isEqualToString:kDNJDoubaoBundleIdentifier]) {
        DNJFinishTransition(@"invalid_return_target");
        return;
    }

    if ([bundleIdentifier isEqualToString:@"com.apple.Spotlight"]) {
        DNJReturnToSpotlight(reason);
        return;
    }

    sDNJReturnStarted = YES;
    NSUInteger generation = sDNJTransitionGeneration;
    WriteLog(@"[VISUAL] return begin bundle=%@ reason=%@ generation=%lu",
             bundleIdentifier,
             reason ?: @"unknown",
             (unsigned long)generation);

    Class serviceClass = NSClassFromString(@"FBSSystemService");
    SEL sharedSelector = NSSelectorFromString(@"sharedService");
    SEL openSelector = NSSelectorFromString(@"openApplication:options:withResult:");
    if (![serviceClass respondsToSelector:sharedSelector]) {
        DNJFinishTransition(@"frontboard_unavailable");
        return;
    }

    id service = ((id (*)(id, SEL))objc_msgSend)(serviceClass, sharedSelector);
    if (![service respondsToSelector:openSelector]) {
        DNJFinishTransition(@"open_application_unavailable");
        return;
    }

    void (^result)(void) = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != sDNJTransitionGeneration || !sDNJTransitionActive) return;
            WriteLog(@"[VISUAL] return request accepted generation=%lu",
                     (unsigned long)generation);
        });
    };
    ((void (*)(id, SEL, NSString *, NSDictionary *, void (^)(void)))objc_msgSend)(service,
                                                                                  openSelector,
                                                                                  bundleIdentifier,
                                                                                  @{},
                                                                                  result);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (generation == sDNJTransitionGeneration && sDNJTransitionActive) {
            DNJFinishTransition(@"return_transaction_timeout");
        }
    });
}

static void DNJMaybeReturnToSource(NSString *reason) {
    if (!sDNJTransitionActive ||
        !sDNJAudioActive ||
        !sDNJForwardTransitionFinished ||
        (!sDNJPiPReady && !sDNJPiPGraceElapsed)) {
        return;
    }
    DNJReturnToSource(reason);
}

static UIImage *DNJCaptureVisibleWindows(void) {
    CGSize size = UIScreen.mainScreen.bounds.size;
    UIGraphicsBeginImageContextWithOptions(size, YES, UIScreen.mainScreen.scale);
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context) {
        UIGraphicsEndImageContext();
        return nil;
    }

    NSArray<UIWindow *> *windows = SpringBoardWindows();
    for (UIWindow *window in windows) {
        if (window.hidden || window.alpha <= 0.01 || window == sDNJOverlayWindow) continue;
        CGContextSaveGState(context);
        CGContextConcatCTM(context, window.transform);
        [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:NO];
        CGContextRestoreGState(context);
    }
    UIImage *snapshot = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return snapshot;
}

static void DNJShowOverlay(void) {
    DNJScreenImageFunction screenImage = (DNJScreenImageFunction)dlsym(RTLD_DEFAULT, "UIGetScreenImage");
    UIImage *snapshot = screenImage ? screenImage() : DNJCaptureVisibleWindows();
    if (!snapshot) return;

    UIViewController *controller = [UIViewController new];
    UIImageView *imageView = [[UIImageView alloc] initWithFrame:UIScreen.mainScreen.bounds];
    imageView.image = snapshot;
    imageView.contentMode = UIViewContentModeScaleToFill;
    controller.view = imageView;

    UIWindow *window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIWindowScene *windowScene = DNJActiveWindowScene();
    if (windowScene) window.windowScene = windowScene;
    window.rootViewController = controller;
    window.windowLevel = UIWindowLevelAlert + 1000.0;
    window.userInteractionEnabled = NO;
    window.hidden = NO;
    sDNJOverlayWindow = window;
}

static void DNJPrepareCallback(CFNotificationCenterRef center,
                               void *observer,
                               CFStringRef name,
                               const void *object,
                               CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (sDNJTransitionActive) {
            DNJPostNotification(kDNJReadyNotification);
            return;
        }

        NSString *frontmost = DNJBundleIdentifierFromPrepareState();
        if (frontmost.length == 0) frontmost = DNJFrontmostBundleIdentifier();
        if (frontmost.length == 0 || [frontmost isEqualToString:kDNJDoubaoBundleIdentifier]) {
            WriteLog(@"[VISUAL] prepare rejected frontmost=%@", frontmost ?: @"nil");
            DNJPostNotification(kDNJReadyNotification);
            return;
        }

        NSUInteger generation = ++sDNJTransitionGeneration;
        sDNJTransitionActive = YES;
        sDNJAudioActive = NO;
        sDNJPiPReady = NO;
        sDNJPiPGraceElapsed = NO;
        sDNJForwardTransitionFinished = NO;
        sDNJReturnStarted = NO;
        sDNJReturnBundleIdentifier = [frontmost copy];
        DNJShowOverlay();
        WriteLog(@"[VISUAL] prepare source=%@ overlay=%d generation=%lu",
                 frontmost,
                 sDNJOverlayWindow != nil,
                 (unsigned long)generation);
        NSTimeInterval readyDelay = sDNJOverlayWindow ? kDNJOverlayPresentationDelay : 0.0;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(readyDelay * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (generation == sDNJTransitionGeneration && sDNJTransitionActive) {
                DNJPostNotification(kDNJReadyNotification);
            }
        });

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kDNJTransitionTimeout * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (generation != sDNJTransitionGeneration || !sDNJTransitionActive) return;
            NSString *current = DNJFrontmostBundleIdentifier();
            if ([current isEqualToString:kDNJDoubaoBundleIdentifier]) {
                DNJReturnToSource(@"transition_timeout");
            } else {
                DNJFinishTransition(@"transition_timeout_no_doubao");
            }
        });
    });
}

static void DNJAudioActiveCallback(CFNotificationCenterRef center,
                                   void *observer,
                                   CFStringRef name,
                                   const void *object,
                                   CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!sDNJTransitionActive) return;
        NSUInteger generation = sDNJTransitionGeneration;
        sDNJAudioActive = YES;
        WriteLog(@"[VISUAL] audio active generation=%lu", (unsigned long)generation);
        DNJMaybeReturnToSource(@"audio_and_pip_ready");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kDNJPiPWaitAfterAudio * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (generation == sDNJTransitionGeneration && sDNJTransitionActive && sDNJAudioActive) {
                sDNJPiPGraceElapsed = YES;
                WriteLog(@"[VISUAL] pip grace elapsed generation=%lu", (unsigned long)generation);
                DNJMaybeReturnToSource(@"audio_ready_pip_grace");
            }
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kDNJForwardTransitionFallbackAfterAudio * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (generation != sDNJTransitionGeneration ||
                !sDNJTransitionActive ||
                !sDNJAudioActive ||
                sDNJReturnStarted ||
                sDNJForwardTransitionFinished) {
                return;
            }
            sDNJForwardTransitionFinished = YES;
            WriteLog(@"[VISUAL] forward transition fallback generation=%lu",
                     (unsigned long)generation);
            DNJMaybeReturnToSource(@"forward_transition_fallback");
        });
    });
}

static void DNJInstallVisualTransitionBridge(void) {
    notify_register_check(kDNJPrepareNotification.UTF8String, &sDNJPrepareStateToken);
    CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterAddObserver(center,
                                    NULL,
                                    DNJPrepareCallback,
                                    (__bridge CFStringRef)kDNJPrepareNotification,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(center,
                                    NULL,
                                    DNJAudioActiveCallback,
                                    (__bridge CFStringRef)kDNJAudioActiveNotification,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    WriteLog(@"[VISUAL] bridge installed=1");
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

static NSString *LocalBundleIDFromPiPController(id pipCtrl) {
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

    return nil;
}

static NSString *BundleIDFromPiPController(id pipCtrl) {
    NSString *bundleID = LocalBundleIDFromPiPController(pipCtrl);
    return bundleID.length > 0 ? bundleID : BundleIDFromPegasusApp(pipCtrl);
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

static NSString *LocalBundleIDFromPiPWindow(UIWindow *window) {
    return LocalBundleIDFromPiPController(PiPControllerFromWindow(window));
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

static DoubaoPiPIdentity EffectiveIdentityFromPiPWindow(UIWindow *window, BOOL forceRefresh) {
    if (!window || !IsPiPWindow(window)) return DoubaoPiPIdentityUnknown;

    if (HasMultipleActivePiPWindows(window, forceRefresh)) {
        DoubaoPiPIdentity localIdentity = IdentityFromBundleID(LocalBundleIDFromPiPWindow(window));
        if (localIdentity != DoubaoPiPIdentityUnknown) return localIdentity;
        return IsLikelyDoubaoPiPWindowByViewTree(window) ? DoubaoPiPIdentityDoubao : DoubaoPiPIdentityUnknown;
    }

    DoubaoPiPIdentity identity = IdentityFromPiPWindow(window);
    if (identity != DoubaoPiPIdentityUnknown) return identity;
    return IsLikelyDoubaoPiPWindowByViewTree(window) ? DoubaoPiPIdentityDoubao : DoubaoPiPIdentityUnknown;
}

static BOOL IsDoubaoPiPWindowWithRefresh(UIWindow *window, BOOL forceRefresh) {
    return EffectiveIdentityFromPiPWindow(window, forceRefresh) == DoubaoPiPIdentityDoubao;
}

static BOOL HasExplicitDoubaoIdentity(UIWindow *window, BOOL forceRefresh) {
    NSString *bundleID = HasMultipleActivePiPWindows(window, forceRefresh)
        ? LocalBundleIDFromPiPWindow(window)
        : BundleIDFromPiPWindow(window);
    return IsDoubaoBundleID(bundleID);
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
    CGFloat beforeWindowOpacity = window.layer.opacity;
    CGFloat beforeHitOpacity = hitView ? hitView.layer.opacity : -1.0;
    BOOL explicitDoubao = HasExplicitDoubaoIdentity(window, NO);
    BOOL transitionCandidate = sDNJTransitionActive && !explicitDoubao;
    BOOL shouldMuteWindowLayer = explicitDoubao || transitionCandidate;
    if (shouldMuteWindowLayer && beforeWindowOpacity > 0.01) changed = YES;
    if (hitView && beforeHitOpacity > 0.01) changed = YES;
    if (shouldMuteWindowLayer) {
        window.layer.opacity = 0.0;
        objc_setAssociatedObject(window, kWindowLayerMutedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
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
        WriteLog(@"[HIDE] reason=%@ mode=windowLayerHitContent changed=%d bundle=%@ explicit=%d transitionCandidate=%d windowOpacity=%.3f->%.3f hitOpacity=%.3f->%.3f restoredTargets=%lu targets=%lu windowAlpha=%.3f windowHidden=%d",
                 reason ?: @"unknown",
                 changed,
                 BundleIDFromPiPWindow(window) ?: @"nil",
                 explicitDoubao,
                 transitionCandidate,
                 beforeWindowOpacity,
                 window.layer.opacity,
                 beforeHitOpacity,
                 hitView ? hitView.layer.opacity : -1.0,
                 (unsigned long)restoredTargets,
                 (unsigned long)targets.count,
                 window.alpha,
                 window.hidden);
    }
    if (sDNJTransitionActive && !sDNJPiPReady) {
        sDNJPiPReady = YES;
        WriteLog(@"[VISUAL] pip ready reason=%@ generation=%lu",
                 reason ?: @"unknown",
                 (unsigned long)sDNJTransitionGeneration);
        DNJMaybeReturnToSource(@"audio_and_pip_ready");
    }
}

static void RestoreWindowLayerIfNeeded(UIWindow *window, NSString *reason, BOOL forceRefresh) {
    if (![objc_getAssociatedObject(window, kWindowLayerMutedKey) boolValue]) return;
    if (EffectiveIdentityFromPiPWindow(window, forceRefresh) != DoubaoPiPIdentityNonDoubao) return;

    CGFloat beforeOpacity = window.layer.opacity;
    window.layer.opacity = window.alpha;
    objc_setAssociatedObject(window, kWindowLayerMutedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    WriteLog(@"[RESTORE] reason=%@ bundle=%@ windowOpacity=%.3f->%.3f windowAlpha=%.3f",
             reason ?: @"unknown",
             BundleIDFromPiPWindow(window) ?: @"nil",
             beforeOpacity,
             window.layer.opacity,
             window.alpha);
}

static void HideDoubaoWindow(UIWindow *window, NSString *reason) {
    if (!window || !IsPiPWindow(window)) return;

    BOOL forceRefresh = [reason isEqualToString:@"didMoveToWindow"] || [reason isEqualToString:@"setHidden"] || [reason isEqualToString:@"setAlpha"];

    if (HasMultipleActivePiPWindows(window, forceRefresh)) {
        for (UIWindow *candidate in SpringBoardWindows()) {
            if (!IsVisiblePiPWindow(candidate)) continue;
            if (IsDoubaoPiPWindowWithRefresh(candidate, forceRefresh)) {
                HideSingleDoubaoWindow(candidate, reason);
            } else {
                RestoreWindowLayerIfNeeded(candidate, reason, forceRefresh);
            }
        }
        return;
    }

    if (!IsVisiblePiPWindow(window)) return;

    if (!IsDoubaoPiPWindowWithRefresh(window, forceRefresh)) {
        RestoreWindowLayerIfNeeded(window, reason, forceRefresh);
        return;
    }

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
    } else if (alpha > 0.01) {
        RestoreWindowLayerIfNeeded(self, @"setAlpha", YES);
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

- (void)setAlpha:(CGFloat)alpha {
    UIWindow *window = ((UIView *)self).window;
    if (alpha > 0.01 && IsDoubaoPiPWindowWithRefresh(window, YES)) {
        %orig;
        ((UIView *)self).layer.opacity = 0.0;
        NSString *logKey = [NSString stringWithFormat:@"hit-alpha-%p", self];
        if (ShouldRunThrottled(logKey, 10.0)) {
            WriteLog(@"[HIDE] reason=hitTestSetAlpha requestedAlpha=%.3f bundle=%@",
                     alpha,
                     BundleIDFromPiPWindow(window));
        }
        return;
    }
    %orig;
}

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

%hook SBAppToAppWorkspaceTransaction

- (void)_didComplete {
    %orig;
    if (!sDNJTransitionActive) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (!sDNJTransitionActive) return;
        NSString *frontmost = DNJFrontmostBundleIdentifier();
        if (sDNJReturnStarted) {
            if (sDNJReturnBundleIdentifier.length == 0 ||
                [sDNJReturnBundleIdentifier isEqualToString:@"com.apple.Spotlight"] ||
                ![frontmost isEqualToString:sDNJReturnBundleIdentifier]) {
                return;
            }
            WriteLog(@"[VISUAL] return app-to-app transaction completed bundle=%@ generation=%lu",
                     frontmost,
                     (unsigned long)sDNJTransitionGeneration);
            DNJFinishTransition(@"return_app_to_app_completed");
            return;
        }

        if (sDNJForwardTransitionFinished ||
            ![frontmost isEqualToString:kDNJDoubaoBundleIdentifier]) {
            return;
        }

        sDNJForwardTransitionFinished = YES;
        WriteLog(@"[VISUAL] forward app-to-app transaction completed generation=%lu",
                 (unsigned long)sDNJTransitionGeneration);
        DNJMaybeReturnToSource(@"forward_app_to_app_completed");
    });
}

%end

%ctor {
    DNJInstallVisualTransitionBridge();
    WriteLog(@"[INIT] HideDoubaoPiP v1.0.30 bidirectional-transaction-gate");
}
