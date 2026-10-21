#import <Foundation/Foundation.h>
#import <Celestial/AVSystemController.h>
#import <dlfcn.h>
#import <notify.h>

static NSString *const PreferencesDomain = @"ayao.lockaudioprofiles";
static NSString *const PreferencesChangedNotification = @"ayao.lockaudioprofiles/preferences.changed";
static NSString *const SpringBoardPreferencesDomain = @"com.apple.springboard";

static id CopyAppPreference(NSString *key) {
    CFStringRef domain = (__bridge CFStringRef)PreferencesDomain;
    CFPreferencesAppSynchronize(domain);
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, domain));
}

static BOOL ReadAppBool(NSString *key, BOOL defaultValue) {
    id value = CopyAppPreference(key);
    return value ? [value boolValue] : defaultValue;
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

static uint64_t ReadNotifyState(const char *name) {
    int token = NOTIFY_TOKEN_INVALID;
    if (notify_register_check(name, &token) != NOTIFY_STATUS_OK) {
        return UINT64_MAX;
    }
    uint64_t state = UINT64_MAX;
    notify_get_state(token, &state);
    notify_cancel(token);
    return state;
}

static int PrintState(void) {
    float ringerVolume = -1.0f;
    float mediaVolume = -1.0f;
    AVSystemController *controller = [AVSystemController sharedAVSystemController];
    BOOL hasRingerVolume = [controller getVolume:&ringerVolume forCategory:@"Ringtone"];
    BOOL hasMediaVolume = [controller getVolume:&mediaVolume forCategory:@"Audio/Video"];
    printf(
        "locked=%llu ringer_state=%llu ringer=%s%.3f media=%s%.3f ring_vibrate=%d silent_vibrate=%d profiles=%d total_silence=%d snapshot=%d\n",
        ReadNotifyState("com.apple.springboard.lockstate"),
        ReadNotifyState("com.apple.springboard.ringerstate"),
        hasRingerVolume ? "" : "unavailable:",
        ringerVolume,
        hasMediaVolume ? "" : "unavailable:",
        mediaVolume,
        ReadSystemBool(@"ring-vibrate", YES),
        ReadSystemBool(@"silent-vibrate", YES),
        ReadAppBool(@"profilesEnabled", NO),
        ReadAppBool(@"totalSilenceEnabled", NO),
        ReadAppBool(@"silenceSnapshotValid", NO)
    );
    return 0;
}

static void WriteAppPreference(NSString *key, id value) {
    CFPreferencesSetAppValue(
        (__bridge CFStringRef)key,
        (__bridge CFPropertyListRef)value,
        (__bridge CFStringRef)PreferencesDomain
    );
}

static void PostPreferencesChanged(void) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)PreferencesDomain);
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)PreferencesChangedNotification,
        NULL,
        NULL,
        YES
    );
}

static int ConfigureTestProfile(void) {
    NSDictionary<NSString *, id> *values = @{
        @"profilesEnabled": @YES,
        @"manageRingerVolume": @YES,
        @"manageMediaVolume": @YES,
        @"manageRingVibration": @YES,
        @"manageSilentVibration": @YES,
        @"lockRingerVolume": @60,
        @"lockMediaVolume": @60,
        @"lockRingVibration": @YES,
        @"lockSilentVibration": @YES,
        @"unlockRingerVolume": @0,
        @"unlockMediaVolume": @0,
        @"unlockRingVibration": @NO,
        @"unlockSilentVibration": @NO,
        @"totalSilenceEnabled": @NO
    };
    [values enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
        (void)stop;
        WriteAppPreference(key, value);
    }];
    PostPreferencesChanged();
    return 0;
}

static int SetTotalSilence(BOOL enabled) {
    WriteAppPreference(@"totalSilenceEnabled", @(enabled));
    PostPreferencesChanged();
    return 0;
}

static int SetVolume(NSString *category, float volume) {
    AVSystemController *controller = [AVSystemController sharedAVSystemController];
    BOOL setResult = [controller setVolumeTo:volume forCategory:category];
    float readback = -1.0f;
    BOOL readResult = [controller getVolume:&readback forCategory:category];
    printf(
        "category=%s requested=%.3f set=%d read=%d readback=%.3f\n",
        category.UTF8String,
        volume,
        setResult,
        readResult,
        readback
    );
    return setResult ? 0 : 69;
}

static int LockDevice(void) {
    void *framework = dlopen(
        "/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices",
        RTLD_NOW
    );
    if (!framework) {
        return 69;
    }
    void (*lockDevice)(void) = dlsym(framework, "SBSLockDevice");
    if (!lockDevice) {
        dlclose(framework);
        return 69;
    }
    lockDevice();
    dlclose(framework);
    return 0;
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        if (argc == 2 && strcmp(argv[1], "state") == 0) {
            return PrintState();
        }
        if (argc == 2 && strcmp(argv[1], "configure-test") == 0) {
            return ConfigureTestProfile();
        }
        if (argc == 3 && strcmp(argv[1], "silence") == 0) {
            if (strcmp(argv[2], "on") == 0) {
                return SetTotalSilence(YES);
            }
            if (strcmp(argv[2], "off") == 0) {
                return SetTotalSilence(NO);
            }
        }
        if (argc == 2 && strcmp(argv[1], "lock") == 0) {
            return LockDevice();
        }
        if (argc == 4 && strcmp(argv[1], "set-volume") == 0) {
            NSString *category = strcmp(argv[2], "ringer") == 0 ? @"Ringtone" : @"Audio/Video";
            return SetVolume(category, strtof(argv[3], NULL));
        }
        fprintf(stderr, "usage: lap-diagnose state|configure-test|silence on|silence off|lock|set-volume ringer|media value\n");
        return 64;
    }
}
