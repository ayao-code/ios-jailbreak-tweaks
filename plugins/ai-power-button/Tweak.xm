#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "CameraShortcut.h"
#import "CameraDiagnostics.h"
#import "Shared/AYCameraPolicy.h"

#define NSLog(...) do { if (NO) { (void)[NSString stringWithFormat:__VA_ARGS__]; } } while (0)

static NSTimeInterval gLastTriggerAt = 0;
static NSTimeInterval gProtectSystemPowerUntil = 0;
static NSTimeInterval gLastDeepSeekOpenAt = 0;
static BOOL gEnabled = YES;
static BOOL gDoubaoRecording = NO;
static BOOL gDoubaoReleaseSendPending = NO;
static BOOL gDeepSeekRecording = NO;
static BOOL gDeepSeekReleaseSendPending = NO;
static BOOL gDeepSeekReleasePollActive = NO;
static NSTimeInterval gDeepSeekEarliestSendAt = 0;
static NSString *gProvider = nil;
static AYVolumeDoublePress gCameraVolumePress;
static BOOL gCameraVolumeHooksReady, gCameraSideDown, gCameraVolumeUpDown;
static NSTimeInterval gCameraChordUntil;
static __weak id gCameraSideActions;

static void AYCameraCancelVolumeGesture(void) {AYVolumeDoublePressReset(&gCameraVolumePress);}
static BOOL AYCameraSideBlocksVolume(void) {
    if(!gCameraSideDown)return NO;
    id actions=gCameraSideActions;
    SEL selector=NSSelectorFromString(@"isButtonDown");
    if(!actions || ![actions respondsToSelector:selector])return YES;
    @try {
        NSMethodSignature *signature=[actions methodSignatureForSelector:selector];
        BOOL known=signature && signature.numberOfArguments==2
            && (!strcmp(signature.methodReturnType,"B") || !strcmp(signature.methodReturnType,"c"));
        BOOL down=known?((BOOL (*)(id,SEL))objc_msgSend)(actions,selector):YES;
        BOOL blocked=AYVolumeSideBlocks(gCameraSideDown,known,down);
        if(!blocked)gCameraSideDown=NO;
        AYCameraDiagnostic(@"side_native_state",@{@"known":@(known),@"down":@(down),@"blocked":@(blocked)});
        return blocked;
    } @catch(NSException *exception) {return YES;}
}
static BOOL AYCameraVolumePermitted(void) {
    return NSThread.isMainThread && gCameraVolumeHooksReady && AYCameraVolumeDownEnabled()
        && !AYCameraSideBlocksVolume() && !gCameraVolumeUpDown && NSProcessInfo.processInfo.systemUptime>=gCameraChordUntil
        && !gDoubaoRecording && !gDeepSeekRecording;
}
// The volume press itself sets the legacy AI power guard. Do not treat that
// as a side-key chord; use the independent actual side/volume-up gates here.
BOOL AYCameraPendingVolumeAllowed(void) {return AYCameraVolumePermitted();}
#if AYVOLUME_DIAGNOSTICS
static void AYCameraVolumeDiagnostic(NSString *event, long long modifiers) {
    AYCameraDiagnostic(event, @{@"hooksReady":@(gCameraVolumeHooksReady),
        @"configured":@(AYCameraVolumeDownEnabled()), @"sideDown":@(gCameraSideDown),
        @"volumeUpDown":@(gCameraVolumeUpDown), @"modifiers":@(modifiers),
        @"permitted":@(AYCameraVolumePermitted()), @"down":@(gCameraVolumePress.down),
        @"firstReleased":@(gCameraVolumePress.firstReleased), @"rejectedHold":@(gCameraVolumePress.rejectedHold),
        @"pressedAt":@(gCameraVolumePress.pressedAt), @"firstPressedAt":@(gCameraVolumePress.firstPressedAt),
        @"chordUntil":@(gCameraChordUntil), @"recording":@(gDoubaoRecording || gDeepSeekRecording)});
}
#define AYVolumeTrace(event, modifiers) AYCameraVolumeDiagnostic(event, modifiers)
#else
#define AYVolumeTrace(event, modifiers) do {} while (0)
#endif

static const NSTimeInterval kProtectSeconds = 8.0;
static const NSTimeInterval kDebounceSeconds = 4.0;
static NSString * const kPrefsDomain = @"ayao.aipowerbutton";
static NSString * const kPrefsChangedNotification = @"ayao.aipowerbutton/preferences.changed";
static NSString * const kDoubaoBundleID = @"com.bot.doubao";
static NSString * const kDeepSeekBundleID = @"com.deepseek.chat";
static NSString * const kProviderDoubao = @"doubao";
static NSString * const kProviderDeepSeek = @"deepseek";
static NSString * const kDoubaoStartNotification = @"ayao.aipowerbutton.doubao.start";
static NSString * const kDoubaoStopSendNotification = @"ayao.aipowerbutton.doubao.stopSend";
static NSString * const kDeepSeekStartNotification = @"ayao.aipowerbutton.deepseek.start";
static NSString * const kDeepSeekStopSendNotification = @"ayao.aipowerbutton.deepseek.stopSend";

static NSTimeInterval AYPBNow(void) {
    return [[NSDate date] timeIntervalSince1970];
}

static void AYPBProtectSystemPower(void) {
    NSTimeInterval until = AYPBNow() + kProtectSeconds;
    if (until > gProtectSystemPowerUntil) {
        gProtectSystemPowerUntil = until;
    }
}

static BOOL AYPBIsProtected(void) {
    return AYPBNow() < gProtectSystemPowerUntil;
}

static id AYPBCopyPreferenceValue(NSString *key) {
    return AYCameraPreferenceSnapshotValue(key);
}

static void AYPBLoadPrefs(void) {
    AYCameraCancelVolumeGesture();
    AYCameraReloadPreferences();
    id enabledValue = AYPBCopyPreferenceValue(@"enabled");
    gEnabled = enabledValue ? [enabledValue boolValue] : YES;

    id providerValue = AYPBCopyPreferenceValue(@"provider");
    if ([providerValue isKindOfClass:NSString.class] && ([providerValue isEqualToString:kProviderDoubao] || [providerValue isEqualToString:kProviderDeepSeek])) {
        gProvider = providerValue;
    } else {
        gProvider = kProviderDoubao;
    }

    if (![gProvider isEqualToString:kProviderDeepSeek]) {
        gDeepSeekRecording = NO;
        gDeepSeekReleaseSendPending = NO;
        gDeepSeekReleasePollActive = NO;
    }
    if (![gProvider isEqualToString:kProviderDoubao]) {
        gDoubaoRecording = NO;
        gDoubaoReleaseSendPending = NO;
    }
    NSLog(@"[DoubaoPowerButton] prefs enabled=%d provider=%@ doubaoRecording=%d deepseekRecording=%d", gEnabled, gProvider, gDoubaoRecording, gDeepSeekRecording);
}

static void AYPBPrefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    if (NSThread.isMainThread) AYPBLoadPrefs();
    else dispatch_async(dispatch_get_main_queue(), ^{ AYPBLoadPrefs(); });
}

static void AYPBPostDarwinNotification(NSString *notificationName) {
    NSLog(@"[DoubaoPowerButton] post notification %@", notificationName);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)notificationName, NULL, NULL, YES);
}

static void AYPBOpenApplicationAsync(NSString *bundleID) {
    NSString *bundleIDCopy = [bundleID copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        Class serviceClass = NSClassFromString(@"FBSSystemService");
        SEL sharedSelector = NSSelectorFromString(@"sharedService");
        SEL openSelector = NSSelectorFromString(@"openApplication:options:withResult:");
        if (![serviceClass respondsToSelector:sharedSelector]) {
            NSLog(@"[DoubaoPowerButton] FrontBoard service unavailable");
            return;
        }

        id service = ((id (*)(id, SEL))objc_msgSend)(serviceClass, sharedSelector);
        if (![service respondsToSelector:openSelector]) {
            NSLog(@"[DoubaoPowerButton] open application selector unavailable");
            return;
        }

        ((void (*)(id, SEL, NSString *, NSDictionary *, id))objc_msgSend)(service,
                                                                          openSelector,
                                                                          bundleIDCopy,
                                                                          @{},
                                                                          nil);
    });
}

static NSString *AYPBFrontmostBundleIdentifier(void) {
    Class userAgentClass = NSClassFromString(@"SBUserAgent");
    SEL sharedUserAgentSelector = NSSelectorFromString(@"sharedUserAgent");
    SEL foregroundSelector = NSSelectorFromString(@"foregroundApplicationDisplayID");
    if ([userAgentClass respondsToSelector:sharedUserAgentSelector]) {
        id userAgent = ((id (*)(id, SEL))objc_msgSend)(userAgentClass, sharedUserAgentSelector);
        if ([userAgent respondsToSelector:foregroundSelector]) {
            NSString *bundleIdentifier = ((id (*)(id, SEL))objc_msgSend)(userAgent, foregroundSelector);
            if (bundleIdentifier.length > 0) {
                NSLog(@"[DoubaoPowerButton] frontmost from SBUserAgent=%@", bundleIdentifier);
                return bundleIdentifier;
            }
        }
    }

    UIApplication *application = UIApplication.sharedApplication;
    SEL frontmostSelector = NSSelectorFromString(@"_accessibilityFrontMostApplication");
    if ([application respondsToSelector:frontmostSelector]) {
        id frontmostApplication = ((id (*)(id, SEL))objc_msgSend)(application, frontmostSelector);
        SEL bundleIdentifierSelector = NSSelectorFromString(@"bundleIdentifier");
        if ([frontmostApplication respondsToSelector:bundleIdentifierSelector]) {
            NSString *bundleIdentifier = ((id (*)(id, SEL))objc_msgSend)(frontmostApplication, bundleIdentifierSelector);
            if (bundleIdentifier.length > 0) {
                NSLog(@"[DoubaoPowerButton] frontmost from accessibility=%@", bundleIdentifier);
                return bundleIdentifier;
            }
        }
    }
    NSLog(@"[DoubaoPowerButton] frontmost unavailable");
    return nil;
}

static BOOL AYPBIsDeepSeekFrontmost(void) {
    return [AYPBFrontmostBundleIdentifier() isEqualToString:kDeepSeekBundleID];
}

static BOOL AYPBReadLockButtonDown(id actions, BOOL *available) {
    if (available) {
        *available = NO;
    }
    if (!actions) {
        return NO;
    }

    Ivar ivar = class_getInstanceVariable([actions class], "_isButtonDown");
    if (!ivar) {
        NSLog(@"[DoubaoPowerButton] release poll missing _isButtonDown class=%@", NSStringFromClass([actions class]));
        return NO;
    }

    if (available) {
        *available = YES;
    }
    uint8_t *base = (uint8_t *)(__bridge void *)actions;
    return *(BOOL *)(base + ivar_getOffset(ivar));
}

static void AYPBSendDeepSeekFromSpringBoard(NSString *reason) {
    if (!gDeepSeekRecording && !gDeepSeekReleaseSendPending) {
        NSLog(@"[DoubaoPowerButton] deepseek send ignored reason=%@", reason);
        return;
    }

    gDeepSeekRecording = NO;
    gDeepSeekReleaseSendPending = NO;
    NSTimeInterval delay = MAX(0.8, gDeepSeekEarliestSendAt - AYPBNow());
    NSLog(@"[DoubaoPowerButton] deepseek send foreground reason=%@ delay=%.2f", reason, delay);
    if (!AYPBIsDeepSeekFrontmost()) {
        AYPBOpenApplicationAsync(kDeepSeekBundleID);
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSLog(@"[DoubaoPowerButton] deepseek delayed send notification");
        AYPBPostDarwinNotification(kDeepSeekStopSendNotification);
    });
}

static void AYPBPollDeepSeekRelease(id actions, NSInteger attemptsLeft) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!gDeepSeekReleaseSendPending) {
            gDeepSeekReleasePollActive = NO;
            NSLog(@"[DoubaoPowerButton] release poll cancelled");
            return;
        }

        BOOL available = NO;
        BOOL isDown = AYPBReadLockButtonDown(actions, &available);
        if (!available) {
            gDeepSeekReleasePollActive = NO;
            NSLog(@"[DoubaoPowerButton] release poll unavailable");
            return;
        }

        if (!isDown) {
            gDeepSeekReleasePollActive = NO;
            NSLog(@"[DoubaoPowerButton] release poll detected button up");
            AYPBSendDeepSeekFromSpringBoard(@"button released");
            return;
        }

        if (attemptsLeft <= 0) {
            gDeepSeekReleasePollActive = NO;
            gDeepSeekReleaseSendPending = NO;
            NSLog(@"[DoubaoPowerButton] release poll timeout");
            return;
        }

        AYPBPollDeepSeekRelease(actions, attemptsLeft - 1);
    });
}

static void AYPBStartDeepSeekReleasePoll(id actions) {
    if (gDeepSeekReleasePollActive || !gDeepSeekReleaseSendPending) {
        return;
    }

    BOOL available = NO;
    BOOL isDown = AYPBReadLockButtonDown(actions, &available);
    NSLog(@"[DoubaoPowerButton] release poll start available=%d down=%d class=%@", available, isDown, NSStringFromClass([actions class]));
    if (!available) {
        return;
    }

    gDeepSeekReleasePollActive = YES;
    AYPBPollDeepSeekRelease(actions, 600);
}

static void AYPBSendDoubaoFromSpringBoard(NSString *reason) {
    if (!gDoubaoRecording && !gDoubaoReleaseSendPending) {
        return;
    }

    gDoubaoRecording = NO;
    gDoubaoReleaseSendPending = NO;
    AYPBPostDarwinNotification(kDoubaoStopSendNotification);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        AYPBPostDarwinNotification(kDoubaoStopSendNotification);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        AYPBPostDarwinNotification(kDoubaoStopSendNotification);
    });
}

static void AYPBPerformDoubaoAction(void) {
    gDoubaoRecording = YES;
    gDoubaoReleaseSendPending = YES;
    AYPBOpenApplicationAsync(kDoubaoBundleID);
    AYPBPostDarwinNotification(kDoubaoStartNotification);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (gDoubaoReleaseSendPending) {
            AYPBPostDarwinNotification(kDoubaoStartNotification);
        }
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (gDoubaoReleaseSendPending) {
            AYPBPostDarwinNotification(kDoubaoStartNotification);
        }
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (gDoubaoReleaseSendPending) {
            AYPBPostDarwinNotification(kDoubaoStartNotification);
        }
    });
}

static void AYPBPerformDeepSeekAction(void) {
    NSTimeInterval now = AYPBNow();
    NSLog(@"[DoubaoPowerButton] deepseek action enter recording=%d pendingRelease=%d lastOpenDelta=%.2f", gDeepSeekRecording, gDeepSeekReleaseSendPending, now - gLastDeepSeekOpenAt);
    if (!gDeepSeekRecording) {
        gDeepSeekRecording = YES;
        gDeepSeekReleaseSendPending = YES;
        BOOL didOpen = NO;
        BOOL isFrontmost = AYPBIsDeepSeekFrontmost();
        if (!isFrontmost && now - gLastDeepSeekOpenAt > 1.0) {
            gLastDeepSeekOpenAt = now;
            didOpen = YES;
            AYPBOpenApplicationAsync(kDeepSeekBundleID);
        }

        gDeepSeekEarliestSendAt = now + (didOpen ? 3.4 : 1.2);
        NSLog(@"[DoubaoPowerButton] deepseek start frontmost=%d didOpen=%d earliestSendDelay=%.2f", isFrontmost, didOpen, gDeepSeekEarliestSendAt - now);
        if (didOpen) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (gDeepSeekReleaseSendPending) {
                    NSLog(@"[DoubaoPowerButton] deepseek delayed start notification 1");
                    AYPBPostDarwinNotification(kDeepSeekStartNotification);
                }
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (gDeepSeekReleaseSendPending) {
                    NSLog(@"[DoubaoPowerButton] deepseek delayed start notification 2");
                    AYPBPostDarwinNotification(kDeepSeekStartNotification);
                }
            });
        } else {
            AYPBPostDarwinNotification(kDeepSeekStartNotification);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (gDeepSeekReleaseSendPending) {
                    NSLog(@"[DoubaoPowerButton] deepseek retry start notification");
                    AYPBPostDarwinNotification(kDeepSeekStartNotification);
                }
            });
        }
        return;
    }

    AYPBSendDeepSeekFromSpringBoard(@"second long press fallback");
}

%hook SBVolumeHardwareButtonActions

- (void)volumeIncreasePressDownWithModifiers:(long long)modifiers {
    if(NSThread.isMainThread) {
        AYCameraCancelPendingWake();
        gCameraVolumeUpDown=YES;AYCameraCancelVolumeGesture();
        gCameraChordUntil=NSProcessInfo.processInfo.systemUptime+8.0;
    }
    AYPBProtectSystemPower();
    %orig;
}

- (void)volumeDecreasePressDownWithModifiers:(long long)modifiers {
    AYVolumeTrace(@"volume_down_before",modifiers);
    // Do not use AYPBIsProtected here: our own volume event sets that guard.
    // Independent side/chord state preserves power/SOS combinations.
    if(NSThread.isMainThread)AYVolumeDoublePressEvent(&gCameraVolumePress,true,AYCameraVolumePermitted() && modifiers==0,
        NSProcessInfo.processInfo.systemUptime);
    AYPBProtectSystemPower();
    %orig;
    AYVolumeTrace(@"volume_down_after",modifiers);
}

%end

%hook SBLockHardwareButton

- (void)terminalLockLongPress:(id)gesture {
    if(NSThread.isMainThread) {
        AYCameraCancelPendingWake();
        AYCameraCancelVolumeGesture();gCameraChordUntil=NSProcessInfo.processInfo.systemUptime+8.0;
    }
    AYPBProtectSystemPower();
    %orig;
}

%end

%hook SBLockHardwareButtonActions

- (void)performFinalButtonUpActions {
    %orig;
    if (gEnabled && [gProvider isEqualToString:kProviderDoubao] && gDoubaoReleaseSendPending) {
        AYPBSendDoubaoFromSpringBoard(@"button released");
    }
}

- (void)performLongPressActions {
    if (!gEnabled) {
        NSLog(@"[DoubaoPowerButton] long press passthrough disabled");
        %orig;
        return;
    }

    if (AYPBIsProtected()) {
        NSLog(@"[DoubaoPowerButton] long press passthrough protected");
        %orig;
        return;
    }

    NSTimeInterval now = AYPBNow();
    if (now - gLastTriggerAt < kDebounceSeconds) {
        NSLog(@"[DoubaoPowerButton] long press ignored debounce delta=%.2f", now - gLastTriggerAt);
        return;
    }

    gLastTriggerAt = now;
    NSLog(@"[DoubaoPowerButton] long press provider=%@", gProvider);
    if ([gProvider isEqualToString:kProviderDeepSeek]) {
        AYPBPerformDeepSeekAction();
        AYPBStartDeepSeekReleasePoll(self);
    } else {
        AYPBPerformDoubaoAction();
    }
}

%end

%group AYCameraSide
%hook SBLockHardwareButtonActions
- (BOOL)_shouldWaitForDoublePress {
    BOOL original = %orig;
    BOOL camera = AYCameraShouldWaitForDoublePress(AYPBIsProtected(), gDoubaoRecording || gDeepSeekRecording);
    AYCameraDiagnostic(@"wait_for_double", @{@"systemResult": @(original), @"cameraRequiresDouble": @(camera)});
    return original || camera;
}
- (void)performDoublePressActions {
    if (!AYCameraHandleDoublePress(0, AYPBIsProtected(), gDoubaoRecording || gDeepSeekRecording)) %orig;
}
%end
%end

#if AYCAMERA_DIAGNOSTICS
%group AYCameraDiagnosticButtons
%hook SBLockHardwareButtonActions
- (void)performInitialButtonDownActions {
    AYCameraDiagnostic(@"initial_down", @{});
    %orig;
}
- (void)performSecondButtonDownActions {
    AYCameraDiagnostic(@"second_down", @{});
    %orig;
}
%end
%end
#endif

%group AYCameraVolume
%hook SBVolumeHardwareButtonActions
- (void)volumeIncreasePressUp {
    if(!NSThread.isMainThread) {%orig;return;}
    gCameraVolumeUpDown=NO;AYCameraCancelVolumeGesture();
    %orig;
}
- (void)volumeDecreasePressUp {
    AYVolumeTrace(@"volume_up_before",0);
    %orig;
    AYVolumeTrace(@"volume_up_after_original",0);
    if(!NSThread.isMainThread)return;
    if(AYVolumeDoublePressEvent(&gCameraVolumePress,false,AYCameraVolumePermitted(),
        NSProcessInfo.processInfo.systemUptime))
        AYCameraHandleDoublePress(1, NO, gDoubaoRecording || gDeepSeekRecording);
    AYVolumeTrace(@"volume_up_after",0);
}
- (void)cancelVolumePress {
    AYVolumeTrace(@"volume_cancel_before",0);
    if(!NSThread.isMainThread) {%orig;return;}
    AYCameraCancelPendingWake();
    gCameraVolumeUpDown=NO;
    AYCameraCancelVolumeGesture();
    %orig;
    AYVolumeTrace(@"volume_cancel_after",0);
}
%end
%hook SBLockHardwareButtonActions
- (void)performInitialButtonDownActions {
    if(!NSThread.isMainThread) {%orig;return;}
    AYCameraCancelPendingWake();
    gCameraSideActions=self;
    gCameraSideDown=YES;AYCameraCancelVolumeGesture();
    %orig;
}
- (void)performSecondButtonDownActions {
    if(!NSThread.isMainThread) {%orig;return;}
    AYCameraCancelPendingWake();
    gCameraSideActions=self;
    gCameraSideDown=YES;AYCameraCancelVolumeGesture();
    %orig;
}
- (void)performFinalButtonUpActions {
    if(!NSThread.isMainThread) {%orig;return;}
    gCameraSideDown=NO;gCameraChordUntil=NSProcessInfo.processInfo.systemUptime+.45;
    AYCameraCancelVolumeGesture();
    %orig;
}
%end
%end

%group AYCameraLockObserver
%hook SBLockScreenManager
- (void)_reallySetUILocked:(BOOL)locked {
    if(NSThread.isMainThread) {AYCameraCancelVolumeGesture();AYCameraCancelPendingWake();}
    %orig;
    AYCameraRememberLockManager(self);
}
%end
%end

%group AYCameraDisplayObserver
%hook CSCoverSheetViewController
- (void)_displayWillAppearImplementation {
    %orig;
    if(AYCameraHasPendingWake())dispatch_async(dispatch_get_main_queue(), ^{AYCameraDisplayDidAppear(self);});
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if(AYCameraHasPendingWake())dispatch_async(dispatch_get_main_queue(), ^{AYCameraDisplayDidAppear(self);});
}
%end
%end

%group AYCameraBacklightObserver
%hook CSCoverSheetViewController
- (void)setBacklightLevel:(double)level {
    %orig;
    if(AYCameraHasPendingWake() && level>0)
        dispatch_async(dispatch_get_main_queue(), ^{AYCameraDisplayDidAppear(self);});
}
%end
%end

static BOOL AYCameraHookCompatible(NSString *className, NSString *methodName, BOOL takesBool) {
    Method method = class_getInstanceMethod(NSClassFromString(className), NSSelectorFromString(methodName));
    if (!method || method_getNumberOfArguments(method) != (takesBool ? 3u : 2u)) return NO;
    char result[16] = {0}; method_getReturnType(method, result, sizeof(result));
    if (strcmp(result, "v")) return NO;
    if (takesBool) {
        char argument[16] = {0}; method_getArgumentType(method, 2, argument, sizeof(argument));
        if (strcmp(argument, "B") && strcmp(argument, "c")) return NO;
    }
    return YES;
}

%ctor {
    %init;
    // Unknown private ABI is a passthrough, never a guessed hardware-button hook.
    Method doubleWait = class_getInstanceMethod(NSClassFromString(@"SBLockHardwareButtonActions"), NSSelectorFromString(@"_shouldWaitForDoublePress"));
    char waitReturn[16] = {0};
    if (doubleWait) method_getReturnType(doubleWait, waitReturn, sizeof(waitReturn));
    if (AYCameraHookCompatible(@"SBLockHardwareButtonActions", @"performDoublePressActions", NO)
        && doubleWait && method_getNumberOfArguments(doubleWait) == 2
        && (!strcmp(waitReturn, "B") || !strcmp(waitReturn, "c"))) {
        %init(AYCameraSide);
    }
    Method volumeDown=class_getInstanceMethod(NSClassFromString(@"SBVolumeHardwareButtonActions"),NSSelectorFromString(@"volumeDecreasePressDownWithModifiers:"));
    char volumeArgument[16]={0},volumeReturn[16]={0};
    if(volumeDown) {
        method_getArgumentType(volumeDown,2,volumeArgument,sizeof(volumeArgument));
        method_getReturnType(volumeDown,volumeReturn,sizeof(volumeReturn));
    }
    if(volumeDown && method_getNumberOfArguments(volumeDown)==3 && !strcmp(volumeArgument,"q") && !strcmp(volumeReturn,"v")
        && AYCameraHookCompatible(@"SBVolumeHardwareButtonActions", @"volumeDecreasePressUp", NO)
        && AYCameraHookCompatible(@"SBVolumeHardwareButtonActions", @"volumeIncreasePressUp", NO)
        && AYCameraHookCompatible(@"SBVolumeHardwareButtonActions", @"cancelVolumePress", NO)
        && AYCameraHookCompatible(@"SBLockHardwareButtonActions", @"performInitialButtonDownActions", NO)
        && AYCameraHookCompatible(@"SBLockHardwareButtonActions", @"performSecondButtonDownActions", NO)
        && AYCameraHookCompatible(@"SBLockHardwareButtonActions", @"performFinalButtonUpActions", NO)) {
        gCameraVolumeHooksReady=YES;
        %init(AYCameraVolume);
    }
#if AYVOLUME_DIAGNOSTICS
    dispatch_async(dispatch_get_main_queue(), ^{ AYVolumeTrace(@"volume_hook_gate",0); });
#endif
    if (AYCameraHookCompatible(@"SBLockScreenManager", @"_reallySetUILocked:", YES)) {
        %init(AYCameraLockObserver);
    }
    if(AYCameraHookCompatible(@"CSCoverSheetViewController",@"_displayWillAppearImplementation",NO)
        && AYCameraHookCompatible(@"CSCoverSheetViewController",@"viewDidAppear:",YES)) {
        %init(AYCameraDisplayObserver);
        AYCameraSetDisplayHooksReady(YES);
    }
    Method backlight=class_getInstanceMethod(NSClassFromString(@"CSCoverSheetViewController"),NSSelectorFromString(@"setBacklightLevel:"));
    char backlightArgument[16]={0},backlightReturn[16]={0};
    if(backlight && method_getNumberOfArguments(backlight)==3) {
        method_getArgumentType(backlight,2,backlightArgument,sizeof(backlightArgument));
        method_getReturnType(backlight,backlightReturn,sizeof(backlightReturn));
        if(!strcmp(backlightArgument,"d") && !strcmp(backlightReturn,"v")) {
            %init(AYCameraBacklightObserver);
            AYCameraSetDisplayHooksReady(YES);
        }
    }
    AYPBLoadPrefs();
#if AYCAMERA_DIAGNOSTICS
    dispatch_async(dispatch_get_main_queue(), ^{ AYCameraAuditRuntime(); });
    Class actions = NSClassFromString(@"SBLockHardwareButtonActions");
    if (AYCAMERA_DIAGNOSTICS && !AYVOLUME_DIAGNOSTICS && class_getInstanceMethod(actions, @selector(performInitialButtonDownActions))
        && class_getInstanceMethod(actions, @selector(performSecondButtonDownActions))
        && class_getInstanceMethod(actions, NSSelectorFromString(@"_shouldWaitForDoublePress"))) {
        %init(AYCameraDiagnosticButtons);
    }
#endif
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, AYPBPrefsChanged, (__bridge CFStringRef)kPrefsChangedNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}
