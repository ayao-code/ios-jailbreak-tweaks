#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Celestial/AVSystemController.h>
#import <notify.h>
#import "Shared/LAPShared.h"

@interface SBLockScreenManager : NSObject
- (BOOL)isUILocked;
- (void)_reallySetUILocked:(BOOL)isLocked;
@end

@interface SBVolumeControl : NSObject
- (instancetype)initWithHUDController:(id)hudController
                        ringerControl:(id)ringerControl
                      telephonyManager:(id)telephonyManager
                     conferenceManager:(id)conferenceManager;
- (void)_presentVolumeHUDWithVolume:(float)volume;
- (void)handleVolumeButtonWithType:(NSInteger)type down:(BOOL)down;
- (void)increaseVolume;
- (void)decreaseVolume;
- (float)volumeStepUp;
- (float)volumeStepDown;
@end

@interface SBRingerControl : NSObject
- (instancetype)initWithBannerManager:(id)bannerManager soundController:(id)soundController;
- (BOOL)isRingerMuted;
- (void)setRingerMuted:(BOOL)muted;
- (void)setRingerMuted:(BOOL)muted
          withFeedback:(BOOL)feedback
                reason:(NSInteger)reason
            clientType:(NSInteger)clientType;
- (void)activateRingerHUD:(BOOL)muted withInitialVolume:(float)volume fromSource:(NSInteger)source;
- (void)activateRingerHUDForVolumeChangeWithInitialVolume:(float)volume;
@end

@interface MRUContinuousSliderView : UIView
@property(nonatomic) float value;
@end

@interface MRUVolumeView : UIView
@property(nonatomic, strong) MRUContinuousSliderView *primarySlider;
@end

static NSString *const MediaVolumeCategory = @"Audio/Video";
static NSString *const RingerVolumeCategory = @"Ringtone";
static NSString *const SpringBoardPreferencesDomain = @"com.apple.springboard";
static NSString *const RingVibrateKey = @"ring-vibrate";
static NSString *const SilentVibrateKey = @"silent-vibrate";
static NSString *const RingVibrateChangedNotification = @"com.apple.springboard.ring-vibrate.changed";
static NSString *const SilentVibrateChangedNotification = @"com.apple.springboard.silent-vibrate.changed";

static BOOL profilesEnabled = NO;
static BOOL manageMediaVolume = YES;
static BOOL manageRingerVolume = YES;
static BOOL totalSilenceEnabled = NO;
static BOOL hasObservedLockState = NO;
static BOOL lastObservedLockState = NO;
static BOOL isApplyingState = NO;
static BOOL isApplyingRingerMute = NO;
static BOOL ownsRingerMute = NO;
static __weak SBVolumeControl *volumeControlInstance = nil;
static __weak SBRingerControl *ringerControlInstance = nil;
static __weak MRUVolumeView *controlCenterVolumeView = nil;
static NSInteger pendingRingerMuteState = -1;
static CFAbsoluteTime automaticVolumeChangeDeadline = 0;

static void CaptureVolumeControl(SBVolumeControl *volumeControl) {
    volumeControlInstance = volumeControl;
    if (!ringerControlInstance) {
        @try {
            ringerControlInstance = [volumeControl valueForKey:@"ringerControl"];
        } @catch (__unused NSException *exception) {
        }
    }
}

static float ClampVolume(double percentage) {
    return (float)MAX(0.0, MIN(100.0, percentage)) / 100.0f;
}

static BOOL IsRingerMuted(void) {
    SBRingerControl *control = ringerControlInstance;
    if ([control respondsToSelector:@selector(isRingerMuted)]) {
        return [control isRingerMuted];
    }

    int token = NOTIFY_TOKEN_INVALID;
    if (notify_register_check("com.apple.springboard.ringerstate", &token) != NOTIFY_STATUS_OK) {
        return NO;
    }

    uint64_t state = 1;
    notify_get_state(token, &state);
    notify_cancel(token);
    return state == 0;
}

static SBRingerControl *GetRingerControl(void) {
    return ringerControlInstance;
}

static BOOL ShouldSuppressAutomaticVolumeHUD(void) {
    return CFAbsoluteTimeGetCurrent() <= automaticVolumeChangeDeadline;
}

static BOOL SetRingerMuted(BOOL muted) {
    if (IsRingerMuted() == muted) {
        return YES;
    }

    SBRingerControl *control = GetRingerControl();
    if (!control) {
        pendingRingerMuteState = muted ? 1 : 0;
        return NO;
    }

    isApplyingRingerMute = YES;
    if ([control respondsToSelector:@selector(setRingerMuted:withFeedback:reason:clientType:)]) {
        [control setRingerMuted:muted withFeedback:NO reason:0 clientType:0];
    } else if ([control respondsToSelector:@selector(setRingerMuted:)]) {
        [control setRingerMuted:muted];
    }
    isApplyingRingerMute = NO;

    BOOL succeeded = IsRingerMuted() == muted;
    if (succeeded) {
        pendingRingerMuteState = -1;
        ownsRingerMute = muted;
        LAPWritePreference(@"ringerMuteOwned", @(muted));
    }
    return succeeded;
}

static void ApplyRingerMuteForVolume(float volume) {
    if (volume <= 0.0001f) {
        if (!IsRingerMuted()) {
            SetRingerMuted(YES);
        } else {
            pendingRingerMuteState = -1;
        }
        return;
    }

    if (ownsRingerMute) {
        SetRingerMuted(NO);
    } else {
        pendingRingerMuteState = -1;
    }
}

static BOOL ReadSystemBool(NSString *key, BOOL defaultValue) {
    CFPropertyListRef value = CFPreferencesCopyValue(
        (__bridge CFStringRef)key,
        (__bridge CFStringRef)SpringBoardPreferencesDomain,
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost
    );
    if (!value) {
        return defaultValue;
    }
    BOOL result = [(__bridge id)value boolValue];
    CFRelease(value);
    return result;
}

static void WriteSystemBool(NSString *key, BOOL value, NSString *notificationName) {
    if (ReadSystemBool(key, YES) == value) {
        return;
    }

    CFPreferencesSetValue(
        (__bridge CFStringRef)key,
        value ? kCFBooleanTrue : kCFBooleanFalse,
        (__bridge CFStringRef)SpringBoardPreferencesDomain,
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost
    );
    CFPreferencesSynchronize(
        (__bridge CFStringRef)SpringBoardPreferencesDomain,
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost
    );
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)notificationName,
        NULL,
        NULL,
        YES
    );
}

static BOOL ReadVolume(NSString *category, float *volume) {
    return [[AVSystemController sharedAVSystemController] getVolume:volume forCategory:category];
}

static void WriteVolumeIfNeeded(NSString *category, float volume) {
    float currentVolume = 0.0f;
    if (ReadVolume(category, &currentVolume) && fabsf(currentVolume - volume) < 0.001f) {
        return;
    }

    isApplyingState = YES;
    automaticVolumeChangeDeadline = CFAbsoluteTimeGetCurrent() + 0.15;
    [[AVSystemController sharedAVSystemController] setVolumeTo:volume forCategory:category];
    isApplyingState = NO;
}

static void WriteVolume(NSString *category, float volume) {
    isApplyingState = YES;
    automaticVolumeChangeDeadline = CFAbsoluteTimeGetCurrent() + 0.15;
    [[AVSystemController sharedAVSystemController] setVolumeTo:volume forCategory:category];
    isApplyingState = NO;
}

static BOOL IsMediaVolumeZero(void) {
    float mediaVolume = 0.0f;
    return ReadVolume(MediaVolumeCategory, &mediaVolume) && mediaVolume <= 0.0001f;
}

static void SetZeroVolumeFillHidden(MRUContinuousSliderView *slider, BOOL hidden) {
    if (!slider) {
        return;
    }
    @try {
        UIView *clippingView = [slider valueForKey:@"valueIndicatorClippingView"];
        clippingView.hidden = hidden;
    } @catch (__unused NSException *exception) {
    }
}

static void RefreshZeroMediaVolumeAppearance(MRUVolumeView *volumeView) {
    if (![NSStringFromClass(volumeView.window.class) isEqualToString:@"SBControlCenterWindow"]) {
        return;
    }

    controlCenterVolumeView = volumeView;
    MRUContinuousSliderView *slider = volumeView.primarySlider;
    BOOL isZero = slider && IsMediaVolumeZero();
    if (isZero && slider.value > 0.0001f) {
        slider.value = 0.0f;
    }
    SetZeroVolumeFillHidden(slider, isZero);
}

static void LoadPreferences(void) {
    profilesEnabled = LAPReadBoolPreference(@"profilesEnabled", NO);
    manageMediaVolume = LAPReadBoolPreference(@"manageMediaVolume", YES);
    manageRingerVolume = LAPReadBoolPreference(@"manageRingerVolume", YES);
    totalSilenceEnabled = LAPReadBoolPreference(@"totalSilenceEnabled", NO);
    ownsRingerMute = LAPReadBoolPreference(@"ringerMuteOwned", NO);
}

static BOOL LockStateControlsMediaVolume(void) {
    return profilesEnabled && manageMediaVolume;
}

static BOOL LockStateControlsRingerVolume(void) {
    return profilesEnabled && manageRingerVolume;
}

static void ApplyProfile(BOOL isLocked) {
    if (!profilesEnabled || totalSilenceEnabled) {
        return;
    }

    NSString *prefix = isLocked ? @"lock" : @"unlock";
    if (LockStateControlsRingerVolume()) {
        NSString *ringerVolumeKey = [prefix stringByAppendingString:@"RingerVolume"];
        float ringerVolume = ClampVolume(LAPReadDoublePreference(ringerVolumeKey, 50.0));
        if (ringerVolume > 0.0001f) {
            WriteVolumeIfNeeded(RingerVolumeCategory, ringerVolume);
        }
        ApplyRingerMuteForVolume(ringerVolume);
    }

    if (LockStateControlsMediaVolume()) {
        NSString *mediaVolumeKey = [prefix stringByAppendingString:@"MediaVolume"];
        WriteVolume(MediaVolumeCategory, ClampVolume(LAPReadDoublePreference(mediaVolumeKey, 50.0)));
    }

    NSString *ringVibrationKey = [prefix stringByAppendingString:@"RingVibration"];
    WriteSystemBool(
        RingVibrateKey,
        LAPReadBoolPreference(ringVibrationKey, YES),
        RingVibrateChangedNotification
    );

    NSString *silentVibrationKey = [prefix stringByAppendingString:@"SilentVibration"];
    WriteSystemBool(
        SilentVibrateKey,
        LAPReadBoolPreference(silentVibrationKey, YES),
        SilentVibrateChangedNotification
    );
}

static void PresentManualVolumeHUD(NSString *category, float volume) {
    automaticVolumeChangeDeadline = 0;
    if ([category isEqualToString:MediaVolumeCategory]) {
        [volumeControlInstance _presentVolumeHUDWithVolume:volume];
        return;
    }

    SBRingerControl *ringerControl = GetRingerControl();
    if ([ringerControl respondsToSelector:@selector(activateRingerHUDForVolumeChangeWithInitialVolume:)]) {
        [ringerControl activateRingerHUDForVolumeChangeWithInitialVolume:volume];
    } else if ([ringerControl respondsToSelector:@selector(activateRingerHUD:withInitialVolume:fromSource:)]) {
        [ringerControl activateRingerHUD:volume <= 0.0001f withInitialVolume:volume fromSource:0];
    }
}

static void ApplyManualVolumeRequest(void) {
    static uint64_t lastRequestID = 0;
    CFPreferencesAppSynchronize((__bridge CFStringRef)LAPPreferencesDomain);
    NSDictionary *request = (__bridge_transfer NSDictionary *)CFPreferencesCopyAppValue(
        CFSTR("manualVolumeRequest"),
        (__bridge CFStringRef)LAPPreferencesDomain
    );
    uint64_t requestID = [request[@"id"] unsignedLongLongValue];
    if (requestID == 0 || requestID == lastRequestID) {
        return;
    }
    lastRequestID = requestID;

    NSString *category = request[@"category"];
    float volume = ClampVolume([request[@"value"] doubleValue]);
    if ([category isEqualToString:MediaVolumeCategory]) {
        if (LockStateControlsMediaVolume() && !totalSilenceEnabled) {
            return;
        }
        automaticVolumeChangeDeadline = CFAbsoluteTimeGetCurrent() + 0.15;
        isApplyingState = YES;
        [[AVSystemController sharedAVSystemController] setVolumeTo:volume forCategory:MediaVolumeCategory];
        isApplyingState = NO;
        PresentManualVolumeHUD(category, volume);
        return;
    }

    if (![category isEqualToString:RingerVolumeCategory] ||
        LockStateControlsRingerVolume() ||
        totalSilenceEnabled) {
        return;
    }
    if (volume > 0.0001f) {
        automaticVolumeChangeDeadline = CFAbsoluteTimeGetCurrent() + 0.15;
        isApplyingState = YES;
        [[AVSystemController sharedAVSystemController] setVolumeTo:volume forCategory:RingerVolumeCategory];
        isApplyingState = NO;
    }
    ApplyRingerMuteForVolume(volume);
    PresentManualVolumeHUD(category, volume);
}

static void SaveTotalSilenceSnapshotIfNeeded(void) {
    if (LAPReadBoolPreference(@"silenceSnapshotValid", NO)) {
        return;
    }

    float ringerVolume = 0.0f;
    float mediaVolume = 0.0f;
    BOOL hasRingerVolume = ReadVolume(RingerVolumeCategory, &ringerVolume);
    BOOL hasMediaVolume = ReadVolume(MediaVolumeCategory, &mediaVolume);

    LAPWritePreference(@"snapshotHasRingerVolume", @(hasRingerVolume));
    LAPWritePreference(@"snapshotHasMediaVolume", @(hasMediaVolume));
    if (hasRingerVolume) {
        LAPWritePreference(@"snapshotRingerVolume", @(ringerVolume));
    }
    if (hasMediaVolume) {
        LAPWritePreference(@"snapshotMediaVolume", @(mediaVolume));
    }
    LAPWritePreference(@"snapshotRingVibration", @(ReadSystemBool(RingVibrateKey, YES)));
    LAPWritePreference(@"snapshotSilentVibration", @(ReadSystemBool(SilentVibrateKey, YES)));
    LAPWritePreference(@"snapshotRingerMuted", @(IsRingerMuted()));
    LAPWritePreference(@"silenceSnapshotValid", @YES);
}

static void EnforceTotalSilence(void) {
    if (!totalSilenceEnabled) {
        return;
    }

    WriteVolumeIfNeeded(RingerVolumeCategory, 0.0f);
    WriteVolume(MediaVolumeCategory, 0.0f);
    ApplyRingerMuteForVolume(0.0f);
    WriteSystemBool(RingVibrateKey, NO, RingVibrateChangedNotification);
    WriteSystemBool(SilentVibrateKey, NO, SilentVibrateChangedNotification);
}

static void EnforceTotalSilenceAfterVolumeChange(void) {
    if (!totalSilenceEnabled) {
        return;
    }

    float ringerVolume = 0.0f;
    if (ReadVolume(RingerVolumeCategory, &ringerVolume) && ringerVolume > 0.07f) {
        WriteVolumeIfNeeded(RingerVolumeCategory, 0.0f);
    }
    ApplyRingerMuteForVolume(0.0f);
}

static void EnforceTotalSilenceAfterVibrationChange(void) {
    if (!totalSilenceEnabled) {
        return;
    }

    WriteSystemBool(RingVibrateKey, NO, RingVibrateChangedNotification);
    WriteSystemBool(SilentVibrateKey, NO, SilentVibrateChangedNotification);
}

static void AdjustMediaVolumeForTotalSilence(SBVolumeControl *volumeControl, BOOL increase) {
    float currentVolume = 0.0f;
    if (!ReadVolume(MediaVolumeCategory, &currentVolume)) {
        return;
    }

    float step = increase ? [volumeControl volumeStepUp] : [volumeControl volumeStepDown];
    float targetVolume = MAX(0.0f, MIN(1.0f, currentVolume + (increase ? fabsf(step) : -fabsf(step))));
    isApplyingState = YES;
    [[AVSystemController sharedAVSystemController] setVolumeTo:targetVolume forCategory:MediaVolumeCategory];
    isApplyingState = NO;
    automaticVolumeChangeDeadline = 0;
    [volumeControl _presentVolumeHUDWithVolume:targetVolume];
}

static void RestoreTotalSilenceSnapshot(void) {
    if (!LAPReadBoolPreference(@"silenceSnapshotValid", NO)) {
        return;
    }

    if (LAPReadBoolPreference(@"snapshotHasRingerVolume", NO)) {
        WriteVolumeIfNeeded(
            RingerVolumeCategory,
            (float)LAPReadDoublePreference(@"snapshotRingerVolume", 0.0)
        );
    }
    if (LAPReadBoolPreference(@"snapshotHasMediaVolume", NO)) {
        WriteVolumeIfNeeded(
            MediaVolumeCategory,
            (float)LAPReadDoublePreference(@"snapshotMediaVolume", 0.0)
        );
    }
    WriteSystemBool(
        RingVibrateKey,
        LAPReadBoolPreference(@"snapshotRingVibration", YES),
        RingVibrateChangedNotification
    );
    WriteSystemBool(
        SilentVibrateKey,
        LAPReadBoolPreference(@"snapshotSilentVibration", YES),
        SilentVibrateChangedNotification
    );
    if (!LAPReadBoolPreference(@"snapshotRingerMuted", NO) && ownsRingerMute) {
        SetRingerMuted(NO);
    }
    LAPWritePreference(@"silenceSnapshotValid", @NO);
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

    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL wasTotalSilenceEnabled = totalSilenceEnabled;
        LoadPreferences();

        if (totalSilenceEnabled) {
            if (!wasTotalSilenceEnabled) {
                SaveTotalSilenceSnapshotIfNeeded();
            }
            EnforceTotalSilence();
            return;
        }

        if (wasTotalSilenceEnabled || LAPReadBoolPreference(@"silenceSnapshotValid", NO)) {
            RestoreTotalSilenceSnapshot();
        }
        if (!LockStateControlsRingerVolume() && ownsRingerMute) {
            SetRingerMuted(NO);
        }
        if (hasObservedLockState) {
            ApplyProfile(lastObservedLockState);
        }
    });
}

static void VibrationPreferenceChanged(
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
    dispatch_async(dispatch_get_main_queue(), ^{
        EnforceTotalSilenceAfterVibrationChange();
    });
}

static void ManualVolumeChanged(
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
    dispatch_async(dispatch_get_main_queue(), ^{
        LoadPreferences();
        ApplyManualVolumeRequest();
    });
}

%hook AVSystemController

- (BOOL)setVolumeTo:(float)volume forCategory:(NSString *)category {
    if (totalSilenceEnabled && !isApplyingState && [category isEqualToString:RingerVolumeCategory]) {
        return %orig(0.0f, category);
    }
    return %orig;
}

%end

%hook SBVolumeControl

- (instancetype)initWithHUDController:(id)hudController
                        ringerControl:(SBRingerControl *)ringerControl
                      telephonyManager:(id)telephonyManager
                     conferenceManager:(id)conferenceManager {
    SBVolumeControl *result = %orig;
    volumeControlInstance = result;
    ringerControlInstance = ringerControl;
    return result;
}

- (void)_effectiveVolumeChanged:(id)notification {
    CaptureVolumeControl(self);
    %orig;

    if (pendingRingerMuteState >= 0) {
        SetRingerMuted(pendingRingerMuteState == 1);
    }
}

- (void)_presentVolumeHUDWithVolume:(float)volume {
    if (ShouldSuppressAutomaticVolumeHUD()) {
        return;
    }
    %orig;
}

- (void)handleVolumeButtonWithType:(NSInteger)type down:(BOOL)down {
    if (down) {
        automaticVolumeChangeDeadline = 0;
    }
    %orig;
}

- (void)increaseVolume {
    if (totalSilenceEnabled) {
        AdjustMediaVolumeForTotalSilence(self, YES);
        return;
    }
    %orig;
}

- (void)decreaseVolume {
    if (totalSilenceEnabled) {
        AdjustMediaVolumeForTotalSilence(self, NO);
        return;
    }
    %orig;
}

%end

%hook SBRingerControl

- (instancetype)initWithBannerManager:(id)bannerManager soundController:(id)soundController {
    SBRingerControl *result = %orig;
    ringerControlInstance = result;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (totalSilenceEnabled) {
            EnforceTotalSilence();
        } else if (!LockStateControlsRingerVolume() && ownsRingerMute) {
            SetRingerMuted(NO);
        } else if (hasObservedLockState) {
            ApplyProfile(lastObservedLockState);
        }
    });
    return result;
}

- (void)setRingerMuted:(BOOL)muted {
    if (!isApplyingRingerMute) {
        ownsRingerMute = NO;
        LAPWritePreference(@"ringerMuteOwned", @NO);
    }
    %orig;
}

- (void)setRingerMuted:(BOOL)muted
          withFeedback:(BOOL)feedback
                reason:(NSInteger)reason
            clientType:(NSInteger)clientType {
    if (!isApplyingRingerMute) {
        ownsRingerMute = NO;
        LAPWritePreference(@"ringerMuteOwned", @NO);
    }
    %orig;
}

- (void)activateRingerHUD:(BOOL)muted
        withInitialVolume:(float)volume
               fromSource:(NSInteger)source {
    if (ShouldSuppressAutomaticVolumeHUD()) {
        return;
    }
    %orig;
}

- (void)activateRingerHUDForVolumeChangeWithInitialVolume:(float)volume {
    if (ShouldSuppressAutomaticVolumeHUD()) {
        return;
    }
    %orig;
}

%end

%hook MRUVolumeView

- (void)didMoveToWindow {
    %orig;
    RefreshZeroMediaVolumeAppearance(self);
}

%end


%hook SBLockScreenManager

- (void)_reallySetUILocked:(BOOL)isLocked {
    %orig;
    BOOL currentLockState = [self isUILocked];
    if (hasObservedLockState && lastObservedLockState == currentLockState) {
        return;
    }

    hasObservedLockState = YES;
    lastObservedLockState = currentLockState;
    ApplyProfile(currentLockState);
}

%end

%ctor {
    @autoreleasepool {
        LoadPreferences();
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            PreferencesChanged,
            (__bridge CFStringRef)LAPPreferencesChangedNotification,
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            VibrationPreferenceChanged,
            (__bridge CFStringRef)RingVibrateChangedNotification,
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            ManualVolumeChanged,
            (__bridge CFStringRef)LAPManualVolumeChangedNotification,
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            VibrationPreferenceChanged,
            (__bridge CFStringRef)SilentVibrateChangedNotification,
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
        [[NSNotificationCenter defaultCenter]
            addObserverForName:AVSystemController_SystemVolumeDidChangeNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(NSNotification *notification) {
                (void)notification;
                EnforceTotalSilenceAfterVolumeChange();
                RefreshZeroMediaVolumeAppearance(controlCenterVolumeView);
            }];

        %init;
        if (totalSilenceEnabled) {
            SaveTotalSilenceSnapshotIfNeeded();
            EnforceTotalSilence();
        } else if (LAPReadBoolPreference(@"silenceSnapshotValid", NO)) {
            RestoreTotalSilenceSnapshot();
        }
    }
}
