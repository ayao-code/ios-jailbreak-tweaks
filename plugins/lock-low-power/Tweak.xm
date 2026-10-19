#import <Foundation/Foundation.h>

@interface _PMLowPowerMode : NSObject
+ (instancetype)sharedInstance;
- (BOOL)setPowerMode:(NSInteger)mode fromSource:(NSString *)source;
@end

@interface SBLockScreenManager : NSObject
- (BOOL)isUILocked;
- (void)_reallySetUILocked:(BOOL)isLocked;
@end

extern NSString *const kPMLPMSourceSpringBoardAlert;

static NSString *const PreferencesDomain = @"ayao.locklowpower";
static NSString *const PreferencesChangedNotification = @"ayao.locklowpower/preferences.changed";

static BOOL enabled = YES;
static BOOL hasObservedLockState = NO;
static BOOL lastObservedLockState = NO;
static BOOL ownsLowPowerMode = NO;

static void LoadPreferences(void) {
    CFStringRef domain = (__bridge CFStringRef)PreferencesDomain;
    CFPreferencesAppSynchronize(domain);
    CFPropertyListRef value = CFPreferencesCopyAppValue(CFSTR("enabled"), domain);
    enabled = value ? [(__bridge id)value boolValue] : YES;
    if (value) {
        CFRelease(value);
    }
}

static void PreferencesChanged(
    CFNotificationCenterRef center,
    void *observer,
    CFStringRef name,
    const void *object,
    CFDictionaryRef userInfo
) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    LoadPreferences();
    if (!enabled) {
        ownsLowPowerMode = NO;
    }
}

static BOOL SetLowPowerMode(BOOL lowPowerModeEnabled) {
    return [[%c(_PMLowPowerMode) sharedInstance]
        setPowerMode:(lowPowerModeEnabled ? 1 : 0)
        fromSource:kPMLPMSourceSpringBoardAlert];
}

static void HandleLockState(BOOL isLocked) {
    if (hasObservedLockState && lastObservedLockState == isLocked) {
        return;
    }
    hasObservedLockState = YES;
    lastObservedLockState = isLocked;

    BOOL lowPowerModeEnabled = NSProcessInfo.processInfo.lowPowerModeEnabled;
    if (isLocked) {
        ownsLowPowerMode = NO;
        if (!lowPowerModeEnabled && SetLowPowerMode(YES)) {
            ownsLowPowerMode = YES;
        }
        return;
    }

    if (ownsLowPowerMode && lowPowerModeEnabled) {
        SetLowPowerMode(NO);
    }
    ownsLowPowerMode = NO;
}

%hook SBLockScreenManager

- (void)_reallySetUILocked:(BOOL)isLocked {
    %orig;
    BOOL currentLockState = [self isUILocked];
    if (!enabled) {
        hasObservedLockState = YES;
        lastObservedLockState = currentLockState;
        return;
    }
    HandleLockState(currentLockState);
}

%end

%ctor {
    @autoreleasepool {
        LoadPreferences();
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            PreferencesChanged,
            (__bridge CFStringRef)PreferencesChangedNotification,
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
        %init;
    }
}
