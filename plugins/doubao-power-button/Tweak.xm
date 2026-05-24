#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <spawn.h>
#import <sys/wait.h>

#define NSLog(...) do { if (NO) { (void)[NSString stringWithFormat:__VA_ARGS__]; } } while (0)

static NSTimeInterval gLastTriggerAt = 0;
static NSTimeInterval gProtectSystemPowerUntil = 0;
static NSTimeInterval gLastDeepSeekOpenAt = 0;
static BOOL gEnabled = YES;
static BOOL gDoubaoRecording = NO;
static BOOL gDoubaoReleaseSendPending = NO;
static BOOL gDoubaoReleasePollActive = NO;
static BOOL gDeepSeekRecording = NO;
static BOOL gDeepSeekReleaseSendPending = NO;
static BOOL gDeepSeekReleasePollActive = NO;
static NSTimeInterval gDeepSeekEarliestSendAt = 0;
static NSString *gProvider = nil;

static const NSTimeInterval kProtectSeconds = 8.0;
static const NSTimeInterval kDebounceSeconds = 4.0;
static NSString * const kPrefsDomain = @"com.ayao.doubaopowerbutton";
static NSString * const kPrefsChangedNotification = @"com.ayao.doubaopowerbutton/preferences.changed";
static NSString * const kDoubaoBundleID = @"com.bot.doubao";
static NSString * const kDoubaoAudioInputIntentIdentifier = @"FlowOpenMainBotAudioInputHandsfreeAppIntent";
static NSString * const kDoubaoAudioInputIntentMangledTypeName = @"5Grace43FlowOpenMainBotAudioInputHandsfreeAppIntentV";
static NSString * const kDeepSeekBundleID = @"com.deepseek.chat";
static NSString * const kProviderDoubao = @"doubao";
static NSString * const kProviderDeepSeek = @"deepseek";
static NSString * const kDeepSeekStartNotification = @"com.ayao.doubaopowerbutton.deepseek.start";
static NSString * const kDeepSeekStopSendNotification = @"com.ayao.doubaopowerbutton.deepseek.stopSend";

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

static id AYPBAllocInit(Class cls) {
    if (!cls) {
        return nil;
    }
    id object = ((id (*)(id, SEL))objc_msgSend)(cls, @selector(alloc));
    return ((id (*)(id, SEL))objc_msgSend)(object, @selector(init));
}

static id AYPBCopyPreferenceValue(NSString *key) {
    CFStringRef domain = (__bridge CFStringRef)kPrefsDomain;
    CFPreferencesAppSynchronize(domain);
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key, domain);
    return value ? CFBridgingRelease(value) : nil;
}

static void AYPBLoadPrefs(void) {
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
        gDoubaoReleasePollActive = NO;
    }
    NSLog(@"[DoubaoPowerButton] prefs enabled=%d provider=%@ doubaoRecording=%d deepseekRecording=%d", gEnabled, gProvider, gDoubaoRecording, gDeepSeekRecording);
}

static void AYPBPrefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    AYPBLoadPrefs();
}

static void AYPBPostDarwinNotification(NSString *notificationName) {
    NSLog(@"[DoubaoPowerButton] post notification %@", notificationName);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)notificationName, NULL, NULL, YES);
}

extern char **environ;

static void AYPBOpenApplicationAsync(NSString *bundleID) {
    NSString *bundleIDCopy = [bundleID copy];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSLog(@"[DoubaoPowerButton] uiopen request %@", bundleIDCopy);
        const char *path = "/var/jb/usr/bin/uiopen";
        const char *bundleIDString = [bundleIDCopy UTF8String];
        char * const argv[] = {
            (char *)"uiopen",
            (char *)"--bundleid",
            (char *)bundleIDString,
            NULL
        };
        pid_t pid = 0;
        int result = posix_spawn(&pid, path, NULL, NULL, argv, environ);
        NSLog(@"[DoubaoPowerButton] uiopen spawn result=%d pid=%d", result, pid);
        if (result == 0) {
            int status = 0;
            waitpid(pid, &status, 0);
            NSLog(@"[DoubaoPowerButton] uiopen exit status=%d", status);
        }
    });
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
    AYPBOpenApplicationAsync(kDeepSeekBundleID);
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

static void AYPBPerformDoubaoAppIntent(NSString *identifier, NSString *mangledTypeName, BOOL openAppWhenRun) {
    Class actionClass = NSClassFromString(@"LNAction");
    Class connectionManagerClass = NSClassFromString(@"LNConnectionManager");
    Class optionsClass = NSClassFromString(@"LNActionExecutorOptions");
    Class executorClass = NSClassFromString(@"LNActionExecutor");
    if (!actionClass || !connectionManagerClass || !optionsClass || !executorClass) {
        NSLog(@"[DoubaoPowerButton] doubao intent missing LinkServices classes identifier=%@", identifier);
        return;
    }

    id actionAlloc = ((id (*)(id, SEL))objc_msgSend)(actionClass, @selector(alloc));
    id action = ((id (*)(id, SEL, id, id, BOOL, id))objc_msgSend)(
        actionAlloc,
        @selector(initWithIdentifier:mangledTypeName:openAppWhenRun:parameters:),
        identifier,
        mangledTypeName,
        openAppWhenRun,
        @[]
    );
    if (!action) {
        NSLog(@"[DoubaoPowerButton] doubao intent action init failed identifier=%@", identifier);
        return;
    }

    SEL sharedSelector = @selector(sharedInstance);
    if (![connectionManagerClass respondsToSelector:sharedSelector]) {
        NSLog(@"[DoubaoPowerButton] doubao intent missing connection manager sharedInstance");
        return;
    }

    id manager = ((id (*)(id, SEL))objc_msgSend)(connectionManagerClass, sharedSelector);
    SEL connectionSelector = @selector(connectionForBundleIdentifier:appBundleIdentifier:error:);
    if (!manager || ![manager respondsToSelector:connectionSelector]) {
        NSLog(@"[DoubaoPowerButton] doubao intent missing connection selector");
        return;
    }

    NSError *error = nil;
    id connection = ((id (*)(id, SEL, id, id, NSError **))objc_msgSend)(manager, connectionSelector, kDoubaoBundleID, kDoubaoBundleID, &error);
    if (!connection) {
        NSLog(@"[DoubaoPowerButton] doubao intent connection failed identifier=%@ error=%@", identifier, error);
        return;
    }

    id options = AYPBAllocInit(optionsClass);
    if (!options) {
        NSLog(@"[DoubaoPowerButton] doubao intent options init failed identifier=%@", identifier);
        return;
    }

    SEL interactionSelector = @selector(setInteractionMode:);
    if ([options respondsToSelector:interactionSelector]) {
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(options, interactionSelector, 1);
    }

    SEL labelSelector = @selector(setClientLabel:);
    if ([options respondsToSelector:labelSelector]) {
        ((void (*)(id, SEL, id))objc_msgSend)(options, labelSelector, @"DoubaoPowerButton");
    }

    SEL donateSelector = @selector(setDonateToTranscript:);
    if ([options respondsToSelector:donateSelector]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(options, donateSelector, NO);
    }

    id executorAlloc = ((id (*)(id, SEL))objc_msgSend)(executorClass, @selector(alloc));
    id executor = ((id (*)(id, SEL, id, id, id))objc_msgSend)(executorAlloc, @selector(initWithAction:connection:options:), action, connection, options);
    if (!executor) {
        NSLog(@"[DoubaoPowerButton] doubao intent executor init failed identifier=%@", identifier);
        return;
    }

    SEL performSelector = @selector(perform);
    if (![executor respondsToSelector:performSelector]) {
        NSLog(@"[DoubaoPowerButton] doubao intent executor missing perform identifier=%@", identifier);
        return;
    }

    NSLog(@"[DoubaoPowerButton] doubao intent perform identifier=%@ open=%d", identifier, openAppWhenRun);
    ((void (*)(id, SEL))objc_msgSend)(executor, performSelector);
}

static void AYPBPerformDoubaoAudioInput(void) {
    AYPBPerformDoubaoAppIntent(kDoubaoAudioInputIntentIdentifier, kDoubaoAudioInputIntentMangledTypeName, YES);
}

static void AYPBPerformDoubaoAction(void) {
    NSLog(@"[DoubaoPowerButton] doubao action open audio input");
    gDoubaoRecording = NO;
    gDoubaoReleaseSendPending = NO;
    gDoubaoReleasePollActive = NO;
    AYPBPerformDoubaoAudioInput();
}

static void AYPBPerformDeepSeekAction(void) {
    NSTimeInterval now = AYPBNow();
    NSLog(@"[DoubaoPowerButton] deepseek action enter recording=%d pendingRelease=%d lastOpenDelta=%.2f", gDeepSeekRecording, gDeepSeekReleaseSendPending, now - gLastDeepSeekOpenAt);
    if (!gDeepSeekRecording) {
        gDeepSeekRecording = YES;
        gDeepSeekReleaseSendPending = YES;
        BOOL didOpen = NO;
        if (now - gLastDeepSeekOpenAt > 1.0) {
            gLastDeepSeekOpenAt = now;
            didOpen = YES;
            AYPBOpenApplicationAsync(kDeepSeekBundleID);
        }

        gDeepSeekEarliestSendAt = now + (didOpen ? 3.4 : 1.2);
        NSLog(@"[DoubaoPowerButton] deepseek start didOpen=%d earliestSendDelay=%.2f", didOpen, gDeepSeekEarliestSendAt - now);
        if (didOpen) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                NSLog(@"[DoubaoPowerButton] deepseek delayed start notification 1");
                AYPBPostDarwinNotification(kDeepSeekStartNotification);
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                NSLog(@"[DoubaoPowerButton] deepseek delayed start notification 2");
                AYPBPostDarwinNotification(kDeepSeekStartNotification);
            });
        } else {
            AYPBPostDarwinNotification(kDeepSeekStartNotification);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                NSLog(@"[DoubaoPowerButton] deepseek retry start notification");
                AYPBPostDarwinNotification(kDeepSeekStartNotification);
            });
        }
        return;
    }

    AYPBSendDeepSeekFromSpringBoard(@"second long press fallback");
}

%hook SBVolumeHardwareButtonActions

- (void)volumeIncreasePressDownWithModifiers:(long long)modifiers {
    AYPBProtectSystemPower();
    %orig;
}

- (void)volumeDecreasePressDownWithModifiers:(long long)modifiers {
    AYPBProtectSystemPower();
    %orig;
}

%end

%hook SBLockHardwareButton

- (void)terminalLockLongPress:(id)gesture {
    AYPBProtectSystemPower();
    %orig;
}

%end

%hook SBLockHardwareButtonActions

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

%ctor {
    AYPBLoadPrefs();
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, AYPBPrefsChanged, (__bridge CFStringRef)kPrefsChangedNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}
