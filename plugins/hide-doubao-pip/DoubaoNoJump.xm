#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFAudio/AVFAudio.h>
#import <dlfcn.h>
#import <notify.h>
#import <substrate.h>

static NSString *const kDNJAppGroupIdentifier = @"group.com.bytedance.ios.doubaoime";
static NSString *const kDNJPrepareNotification = @"ayao.hidedoubaopip.visual.prepare";
static NSString *const kDNJReadyNotification = @"ayao.hidedoubaopip.visual.ready";
static NSString *const kDNJAudioActiveNotification = @"ayao.hidedoubaopip.visual.audio_active";
static NSString *const kDNJCompleteNotification = @"ayao.hidedoubaopip.visual.complete";
static NSString *const kDNJRememberedHostBundleKey = @"last_app_bundle_id";
static const unsigned long long kDNJLogSizeLimit = 64 * 1024;
static const NSTimeInterval kDNJPrepareTimeout = 0.45;
static const NSTimeInterval kDNJRequestSafetyTimeout = 8.0;
static const char *const kDNJForceRecoverySymbol = "$s12SwiftKitchen0B10BaseConfigC17WaveCloudSettingsE30enablePiPNotReadyForceRecoverySbvgZ";
static const char *const kDNJDisableJumpFixSymbol = "$s12SwiftKitchen0B10BaseConfigC17WaveCloudSettingsE14disableJumpFixSbvgZ";

static BOOL (*gOriginalEnablePiPNotReadyForceRecovery)(void) = NULL;
static BOOL (*gOriginalDisableJumpFix)(void) = NULL;
static void (*gOriginalApplicationOpenURL)(id, SEL, NSURL *, NSDictionary *, void (^)(BOOL)) = NULL;
static BOOL (*gOriginalAudioSessionSetActive)(id, SEL, BOOL, NSError **) = NULL;
static BOOL (*gOriginalAudioSessionSetActiveWithOptions)(id, SEL, BOOL, AVAudioSessionSetActiveOptions, NSError **) = NULL;
static id gPendingApplication = nil;
static SEL gPendingSelector = NULL;
static NSURL *gPendingURL = nil;
static NSDictionary *gPendingOptions = nil;
static void (^gPendingCompletion)(BOOL) = nil;
static NSUInteger gRequestGeneration = 0;
static BOOL gWaitingForVisualReady = NO;
static BOOL gRequestInFlight = NO;
static int gPrepareStateToken = 0;
static BOOL gAudioSessionReportedActive = NO;

static BOOL DNJEnablePiPNotReadyForceRecovery(void) {
    return YES;
}

static BOOL DNJDisableJumpFix(void) {
    return NO;
}

static BOOL DNJHookSwiftGetter(const char *symbolName, void *replacement, void **original) {
    void *symbol = dlsym(RTLD_DEFAULT, symbolName);
    if (!symbol) return NO;
    MSHookFunction(symbol, replacement, original);
    return YES;
}

static NSURL *DNJSharedContainerURL(void) {
    return [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:kDNJAppGroupIdentifier];
}

static void DNJAppendLog(NSString *message) {
    NSURL *containerURL = DNJSharedContainerURL();
    if (!containerURL || message.length == 0) return;

    NSString *line = [NSString stringWithFormat:@"%@ %@\n", NSDate.date, message];
    NSURL *logURL = [containerURL URLByAppendingPathComponent:@"DoubaoNoJump.log"];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:logURL.path error:nil];
    if (!attributes || attributes.fileSize >= kDNJLogSizeLimit) {
        [data writeToURL:logURL atomically:YES];
        return;
    }

    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:logURL.path];
    [handle seekToEndOfFile];
    [handle writeData:data];
    [handle closeFile];
}

static BOOL DNJIsStartASRURL(NSURL *url) {
    return [[url.scheme lowercaseString] isEqualToString:@"oime"] &&
           [[url.host lowercaseString] isEqualToString:@"start_asr_from_keyboard"];
}

static void DNJPostNotification(NSString *name) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)name,
                                         NULL,
                                         NULL,
                                         YES);
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

static NSString *DNJRememberedHostBundleIdentifier(void) {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:kDNJAppGroupIdentifier];
    NSString *bundleIdentifier = [defaults stringForKey:kDNJRememberedHostBundleKey];
    if (bundleIdentifier.length == 0 ||
        [bundleIdentifier isEqualToString:@"com.bytedance.ios.doubaoime"] ||
        [bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
        return nil;
    }
    return bundleIdentifier;
}

static void DNJClearPendingOpen(void) {
    gPendingApplication = nil;
    gPendingSelector = NULL;
    gPendingURL = nil;
    gPendingOptions = nil;
    gPendingCompletion = nil;
    gWaitingForVisualReady = NO;
}

static void DNJPerformPendingOpen(NSString *reason) {
    if (!gWaitingForVisualReady || !gPendingApplication || !gOriginalApplicationOpenURL) return;

    id application = gPendingApplication;
    SEL selector = gPendingSelector;
    NSURL *url = gPendingURL;
    NSDictionary *options = gPendingOptions;
    void (^completion)(BOOL) = gPendingCompletion;
    DNJClearPendingOpen();
    gRequestInFlight = YES;
    DNJAppendLog([NSString stringWithFormat:@"keyboard open=original reason=%@", reason ?: @"unknown"]);
    gOriginalApplicationOpenURL(application, selector, url, options, completion);
}

static void DNJApplicationOpenURL(id self,
                                  SEL selector,
                                  NSURL *url,
                                  NSDictionary *options,
                                  void (^completion)(BOOL)) {
    if (!DNJIsStartASRURL(url)) {
        gOriginalApplicationOpenURL(self, selector, url, options, completion);
        return;
    }

    if (gRequestInFlight || gWaitingForVisualReady) {
        DNJAppendLog(@"keyboard request=coalesced");
        if (completion) completion(YES);
        return;
    }

    NSUInteger generation = ++gRequestGeneration;
    gPendingApplication = self;
    gPendingSelector = selector;
    gPendingURL = url;
    gPendingOptions = [options copy];
    gPendingCompletion = [completion copy];
    gWaitingForVisualReady = YES;
    NSString *hostBundleIdentifier = DNJRememberedHostBundleIdentifier();
    uint64_t hostHash = DNJBundleIdentifierHash(hostBundleIdentifier);
    if (gPrepareStateToken != 0 && hostHash != 0) {
        notify_set_state(gPrepareStateToken, hostHash);
    }
    DNJAppendLog([NSString stringWithFormat:@"keyboard request=visual_prepare generation=%lu host=%@ state=%llu",
                  (unsigned long)generation,
                  hostBundleIdentifier ?: @"nil",
                  hostHash]);
    DNJPostNotification(kDNJPrepareNotification);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kDNJPrepareTimeout * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (generation == gRequestGeneration) DNJPerformPendingOpen(@"prepare_timeout");
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kDNJRequestSafetyTimeout * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (generation == gRequestGeneration) {
            gRequestInFlight = NO;
            DNJClearPendingOpen();
        }
    });
}

static void DNJReadyCallback(CFNotificationCenterRef center,
                             void *observer,
                             CFStringRef name,
                             const void *object,
                             CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        DNJPerformPendingOpen(@"overlay_ready");
    });
}

static void DNJCompleteCallback(CFNotificationCenterRef center,
                                void *observer,
                                CFStringRef name,
                                const void *object,
                                CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        gRequestInFlight = NO;
        DNJClearPendingOpen();
        DNJAppendLog(@"keyboard request=complete");
    });
}

static BOOL DNJAudioSessionSetActive(id self, SEL selector, BOOL active, NSError **error) {
    BOOL success = gOriginalAudioSessionSetActive(self, selector, active, error);
    if (active && success && !gAudioSessionReportedActive) {
        gAudioSessionReportedActive = YES;
        DNJAppendLog(@"app audio_session=active visual_return=1");
        DNJPostNotification(kDNJAudioActiveNotification);
    } else if (!active && success) {
        gAudioSessionReportedActive = NO;
    }
    return success;
}

static BOOL DNJAudioSessionSetActiveWithOptions(id self,
                                                SEL selector,
                                                BOOL active,
                                                AVAudioSessionSetActiveOptions options,
                                                NSError **error) {
    BOOL success = gOriginalAudioSessionSetActiveWithOptions(self, selector, active, options, error);
    if (active && success && !gAudioSessionReportedActive) {
        gAudioSessionReportedActive = YES;
        DNJAppendLog(@"app audio_session=active visual_return=1");
        DNJPostNotification(kDNJAudioActiveNotification);
    } else if (!active && success) {
        gAudioSessionReportedActive = NO;
    }
    return success;
}

static void DNJHookKeyboardOpenURL(void) {
    notify_register_check(kDNJPrepareNotification.UTF8String, &gPrepareStateToken);
    SEL selector = @selector(openURL:options:completionHandler:);
    if (!class_getInstanceMethod(UIApplication.class, selector)) {
        DNJAppendLog(@"keyboard hook=open_url installed=0");
        return;
    }
    MSHookMessageEx(UIApplication.class,
                    selector,
                    (IMP)DNJApplicationOpenURL,
                    (IMP *)&gOriginalApplicationOpenURL);
    CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterAddObserver(center,
                                    NULL,
                                    DNJReadyCallback,
                                    (__bridge CFStringRef)kDNJReadyNotification,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(center,
                                    NULL,
                                    DNJCompleteCallback,
                                    (__bridge CFStringRef)kDNJCompleteNotification,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    DNJAppendLog(@"keyboard hook=open_url installed=1");
}

static void DNJHookAudioSession(void) {
    SEL simpleSelector = @selector(setActive:error:);
    SEL optionsSelector = @selector(setActive:withOptions:error:);
    BOOL simpleInstalled = class_getInstanceMethod(AVAudioSession.class, simpleSelector) != NULL;
    BOOL optionsInstalled = class_getInstanceMethod(AVAudioSession.class, optionsSelector) != NULL;
    if (simpleInstalled) {
        MSHookMessageEx(AVAudioSession.class,
                        simpleSelector,
                        (IMP)DNJAudioSessionSetActive,
                        (IMP *)&gOriginalAudioSessionSetActive);
    }
    if (optionsInstalled) {
        MSHookMessageEx(AVAudioSession.class,
                        optionsSelector,
                        (IMP)DNJAudioSessionSetActiveWithOptions,
                        (IMP *)&gOriginalAudioSessionSetActiveWithOptions);
    }
    DNJAppendLog([NSString stringWithFormat:@"app hook=audio_session simple=%d options=%d",
                  simpleInstalled,
                  optionsInstalled]);
}

%ctor {
    @autoreleasepool {
        NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier;
        BOOL isMainApp = [bundleIdentifier isEqualToString:@"com.bytedance.ios.doubaoime"];
        BOOL isKeyboard = [bundleIdentifier isEqualToString:@"com.bytedance.ios.doubaoime.keyboardExtension"];
        if (!isMainApp && !isKeyboard) return;

        BOOL forceRecoveryHook = DNJHookSwiftGetter(kDNJForceRecoverySymbol,
                                                    (void *)DNJEnablePiPNotReadyForceRecovery,
                                                    (void **)&gOriginalEnablePiPNotReadyForceRecovery);
        BOOL disableJumpFixHook = DNJHookSwiftGetter(kDNJDisableJumpFixSymbol,
                                                     (void *)DNJDisableJumpFix,
                                                     (void **)&gOriginalDisableJumpFix);
        if (isMainApp) {
            DNJHookAudioSession();
        } else {
            DNJHookKeyboardOpenURL();
        }
        DNJAppendLog([NSString stringWithFormat:@"init bundle=%@ forceRecoveryHook=%d disableJumpFixHook=%d",
                      bundleIdentifier,
                      forceRecoveryHook,
                      disableJumpFixHook]);
    }
}
