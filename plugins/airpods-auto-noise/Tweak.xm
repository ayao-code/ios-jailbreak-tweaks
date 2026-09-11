#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <sys/stat.h>
#import <time.h>

static NSString * const kAANLogPath = @"/var/mobile/Library/Logs/AirPodsAutoNoise.log";
static NSString * const kAANLogBackupPath = @"/var/mobile/Library/Logs/AirPodsAutoNoise.log.1";
static const NSUInteger kAANMaxLogSize = 256 * 1024;
static FILE *gLogFile = NULL;

static void AANLog(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);
static void AANLog(NSString *format, ...) {
    struct stat st;
    BOOL reset = stat(kAANLogPath.UTF8String, &st) == 0 && (NSUInteger)st.st_size >= kAANMaxLogSize;
    if (gLogFile && reset) {
        fclose(gLogFile);
        gLogFile = NULL;
    }
    if (reset) {
        remove(kAANLogBackupPath.UTF8String);
        rename(kAANLogPath.UTF8String, kAANLogBackupPath.UTF8String);
    }
    if (!gLogFile) {
        gLogFile = fopen(kAANLogPath.UTF8String, "a");
    }
    if (!gLogFile) return;

    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    time_t raw;
    time(&raw);
    struct tm info;
    localtime_r(&raw, &info);
    char ts[16];
    strftime(ts, sizeof(ts), "%H:%M:%S", &info);
    fprintf(gLogFile, "[%s] %s\n", ts, message.UTF8String);
    fflush(gLogFile);
}

static NSString *AANDescribe(id value) {
    if (!value) return @"<nil>";
    @try {
        return [NSString stringWithFormat:@"<%@: %p> %@", NSStringFromClass([value class]), value, [value description]];
    } @catch (__unused NSException *exception) {
        return [NSString stringWithFormat:@"<%@ %p description-crashed>", NSStringFromClass([value class]), value];
    }
}

typedef void (*MRMediaRemoteRegisterForNowPlayingNotificationsFn)(dispatch_queue_t queue);
typedef void (*MRMediaRemoteBeginRouteDiscoveryFn)(void);
typedef void (*MRMediaRemoteGetNowPlayingApplicationIsPlayingFn)(dispatch_queue_t queue, void (^completion)(Boolean isPlaying));
typedef void (*MRMediaRemoteGetAnyApplicationIsPlayingFn)(dispatch_queue_t queue, void (^completion)(Boolean isPlaying));
typedef void (*MRMediaRemoteGetNowPlayingApplicationPlaybackStateFn)(dispatch_queue_t queue, void (^completion)(unsigned int playbackState));
typedef void (*MRMediaRemoteGetNowPlayingApplicationPIDFn)(dispatch_queue_t queue, void (^completion)(int PID));
typedef void (*MRMediaRemoteGetNowPlayingInfoFn)(dispatch_queue_t queue, void (^completion)(CFDictionaryRef information));
typedef id (*MRAVOutputContextGetSharedSystemAudioContextFn)(void);
typedef CFArrayRef (*MRAVOutputContextCopyOutputDevicesFn)(id context);
typedef CFTypeRef (*MRAVOutputDeviceCopyNameFn)(id device);
typedef CFTypeRef (*MRAVOutputDeviceCopyModelIDFn)(id device);
typedef CFTypeRef (*MRAVOutputDeviceCopyAvailableBluetoothListeningModeFn)(id device);
typedef CFTypeRef (*MRAVOutputDeviceCopyCurrentBluetoothListeningModeFn)(id device);
typedef BOOL (*MRAVOutputDeviceSetCurrentBluetoothListeningModeFn)(id device, id mode, id *error);

typedef NS_ENUM(NSInteger, AANPlaybackState) {
    AANPlaybackStateUnknown = 0,
    AANPlaybackStateStopped,
    AANPlaybackStatePlaying,
};

typedef NS_ENUM(NSInteger, AANNoiseMode) {
    AANNoiseModeNone = 0,
    AANNoiseModeANC,
    AANNoiseModeTransparency,
    AANNoiseModeNormal,
};

typedef NS_ENUM(NSInteger, AANPostPauseBehavior) {
    AANPostPauseBehaviorTransparency = 0,
    AANPostPauseBehaviorNormal,
    AANPostPauseBehaviorNone,
};

static void *gMediaRemoteHandle = NULL;
static MRMediaRemoteRegisterForNowPlayingNotificationsFn gRegisterNowPlaying = NULL;
static MRMediaRemoteBeginRouteDiscoveryFn gBeginRouteDiscovery = NULL;
static MRMediaRemoteGetNowPlayingApplicationIsPlayingFn gGetIsPlaying = NULL;
static MRMediaRemoteGetAnyApplicationIsPlayingFn gGetAnyIsPlaying = NULL;
static MRMediaRemoteGetNowPlayingApplicationPlaybackStateFn gGetPlaybackState = NULL;
static MRMediaRemoteGetNowPlayingApplicationPIDFn gGetNowPlayingPID = NULL;
static MRMediaRemoteGetNowPlayingInfoFn gGetNowPlayingInfo = NULL;
static MRAVOutputContextGetSharedSystemAudioContextFn gGetContext = NULL;
static MRAVOutputContextCopyOutputDevicesFn gCopyDevices = NULL;
static MRAVOutputDeviceCopyNameFn gCopyName = NULL;
static MRAVOutputDeviceCopyModelIDFn gCopyModelID = NULL;
static MRAVOutputDeviceCopyAvailableBluetoothListeningModeFn gCopyAvailableModes = NULL;
static MRAVOutputDeviceCopyCurrentBluetoothListeningModeFn gCopyCurrentMode = NULL;
static MRAVOutputDeviceSetCurrentBluetoothListeningModeFn gSetMode = NULL;

static NSString *gIsPlayingNotification = nil;
static NSString *gPlaybackStateNotification = nil;
static NSString *gRouteStatusNotification = nil;
static NSString *gPickableRoutesNotification = nil;
static NSString *gDistributedAppPlayingNotification = nil;
static NSString *gDistributedActivePlayersNotification = nil;

static BOOL gStarted = NO;
static BOOL gEnabled = YES;
static BOOL gAutoANCOnConnect = NO;
static AANPostPauseBehavior gPostPauseBehavior = AANPostPauseBehaviorTransparency;
static BOOL gDebugLogs = NO;
static BOOL gHadTargetDevice = NO;
static BOOL gHasSeenPlayingSinceTarget = NO;
static BOOL gStopConfirmedReady = NO;
static NSString *gTargetDeviceKey = nil;
static AANPlaybackState gPlaybackState = AANPlaybackStateUnknown;
static AANNoiseMode gLastAppliedMode = AANNoiseModeNone;
static AANNoiseMode gLastSetAttemptMode = AANNoiseModeNone;
static NSTimeInterval gLastAppliedAt = 0;
static NSTimeInterval gSuppressUntil = 0;
static NSTimeInterval gStartupGuardUntil = 0;
static NSTimeInterval gLastTargetSeenAt = 0;
static NSTimeInterval gLastNoTargetLogAt = 0;
static NSUInteger gPendingPlaybackQueries = 0;
static NSUInteger gPlaybackPositiveVotes = 0;
static NSUInteger gPlaybackNegativeVotes = 0;
static NSUInteger gPlaybackQueryGeneration = 0;
static NSUInteger gStopConfirmGeneration = 0;
static BOOL gHasLastNowPlayingSnapshot = NO;
static double gLastNowPlayingDuration = 0;
static double gLastNowPlayingElapsed = 0;
static double gLastNowPlayingRate = 0;
static NSTimeInterval gLastNowPlayingAt = 0;
static NSTimeInterval gTrackTransitionUntil = 0;
static NSUInteger gDeferredStopGeneration = 0;

static const NSTimeInterval kAANCooldownSeconds = 2.0;
static const NSTimeInterval kAANSuppressSeconds = 20.0;
static const NSTimeInterval kAANStartupGuardSeconds = 5.0;
static const NSTimeInterval kAANStopConfirmSeconds = 0.3;
static const NSTimeInterval kAANTrackTransitionWindowSeconds = 2.0;
static const NSTimeInterval kAANDeferredStopConfirmSeconds = 1.5;
static const double kAANTrackTransitionTailSeconds = 8.0;

static NSString * const kPrefsDomain = @"ayao.airpodsautonoise";
static NSString * const kPrefsChangedNotification = @"ayao.airpodsautonoise/preferences.changed";

static NSTimeInterval AANNow(void) {
    return [[NSDate date] timeIntervalSince1970];
}

static NSString *AANModeName(AANNoiseMode mode) {
    switch (mode) {
        case AANNoiseModeANC: return @"ANC";
        case AANNoiseModeTransparency: return @"Transparency";
        case AANNoiseModeNormal: return @"Normal";
        default: return @"None";
    }
}

static NSString *AANPostPauseBehaviorName(AANPostPauseBehavior behavior) {
    switch (behavior) {
        case AANPostPauseBehaviorTransparency: return @"Transparency";
        case AANPostPauseBehaviorNormal: return @"Normal";
        case AANPostPauseBehaviorNone: return @"None";
    }
}

static NSString *AANPlaybackName(AANPlaybackState state) {
    switch (state) {
        case AANPlaybackStatePlaying: return @"Playing";
        case AANPlaybackStateStopped: return @"Stopped";
        default: return @"Unknown";
    }
}

static id AANCopyPreferenceValue(NSString *key) {
    CFStringRef domain = (__bridge CFStringRef)kPrefsDomain;
    CFPreferencesAppSynchronize(domain);
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key, domain);
    return value ? CFBridgingRelease(value) : nil;
}

static void AANLoadPrefs(void) {
    id enabled = AANCopyPreferenceValue(@"enabled");
    id postPauseBehavior = AANCopyPreferenceValue(@"postPauseBehavior");
    id debug = AANCopyPreferenceValue(@"debugLogs");
    gEnabled = enabled ? [enabled boolValue] : YES;
    gAutoANCOnConnect = NO;
    if ([postPauseBehavior isKindOfClass:[NSString class]]) {
        NSString *value = (NSString *)postPauseBehavior;
        if ([value isEqualToString:@"normal"]) {
            gPostPauseBehavior = AANPostPauseBehaviorNormal;
        } else if ([value isEqualToString:@"none"]) {
            gPostPauseBehavior = AANPostPauseBehaviorNone;
        } else {
            gPostPauseBehavior = AANPostPauseBehaviorTransparency;
        }
    } else {
        gPostPauseBehavior = AANPostPauseBehaviorTransparency;
    }
    gDebugLogs = debug ? [debug boolValue] : NO;
    AANLog(@"prefs enabled=%d autoANCOnConnect=%d postPauseBehavior=%@ debugLogs=%d", gEnabled, gAutoANCOnConnect, AANPostPauseBehaviorName(gPostPauseBehavior), gDebugLogs);
}

static NSNumber *AANNumberValue(NSDictionary *info, NSString *key) {
    id value = info[key];
    return [value isKindOfClass:[NSNumber class]] ? value : nil;
}

static void AANCaptureNowPlayingSnapshot(CFDictionaryRef information) {
    NSDictionary *info = (__bridge NSDictionary *)information;
    if (![info isKindOfClass:[NSDictionary class]]) return;
    NSNumber *duration = AANNumberValue(info, @"kMRMediaRemoteNowPlayingInfoDuration");
    NSNumber *elapsed = AANNumberValue(info, @"kMRMediaRemoteNowPlayingInfoElapsedTime");
    NSNumber *rate = AANNumberValue(info, @"kMRMediaRemoteNowPlayingInfoPlaybackRate");
    if (duration || elapsed || rate) {
        gHasLastNowPlayingSnapshot = YES;
        gLastNowPlayingDuration = duration ? duration.doubleValue : 0;
        gLastNowPlayingElapsed = elapsed ? elapsed.doubleValue : 0;
        gLastNowPlayingRate = rate ? rate.doubleValue : 0;
        gLastNowPlayingAt = AANNow();
    }
}

static BOOL AANLooksLikeTrackTransitionNoise(void) {
    if (!gHasLastNowPlayingSnapshot) return NO;
    NSTimeInterval age = AANNow() - gLastNowPlayingAt;
    if (age > 3.0) return NO;
    if (gLastNowPlayingRate >= 0.99) return YES;
    if (gLastNowPlayingDuration > 0 && (gLastNowPlayingDuration - gLastNowPlayingElapsed) <= kAANTrackTransitionTailSeconds) return YES;
    return NO;
}

static NSString *AANTrackTransitionReason(void) {
    if (!gHasLastNowPlayingSnapshot) return @"no-snapshot";
    if (gLastNowPlayingRate >= 0.99) return [NSString stringWithFormat:@"rate=%.2f", gLastNowPlayingRate];
    return [NSString stringWithFormat:@"tail=%.2fs", MAX(0.0, gLastNowPlayingDuration - gLastNowPlayingElapsed)];
}

static NSString *AANStringValue(NSDictionary *info, NSString *key) {
    id value = info[key];
    if (!value) return @"<nil>";
    if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]]) return [value description];
    return NSStringFromClass([value class]);
}

static void AANLogNowPlayingSummary(NSString *reason) {
    if (gGetNowPlayingPID && gDebugLogs) {
        gGetNowPlayingPID(dispatch_get_main_queue(), ^(int PID) {
            AANLog(@"nowPlaying reason=%@ pid=%d", reason, PID);
        });
    }
    if (!gGetNowPlayingInfo) return;
    gGetNowPlayingInfo(dispatch_get_main_queue(), ^(CFDictionaryRef information) {
        AANCaptureNowPlayingSnapshot(information);
        if (!gDebugLogs) return;
        NSDictionary *info = (__bridge NSDictionary *)information;
        if (![info isKindOfClass:[NSDictionary class]]) {
            AANLog(@"nowPlaying reason=%@ info=%@", reason, AANDescribe((__bridge id)information));
            return;
        }
        AANLog(@"nowPlaying reason=%@ title=%@ artist=%@ album=%@ unique=%@ duration=%@ elapsed=%@ rate=%@ keys=%lu", reason, AANStringValue(info, @"kMRMediaRemoteNowPlayingInfoTitle"), AANStringValue(info, @"kMRMediaRemoteNowPlayingInfoArtist"), AANStringValue(info, @"kMRMediaRemoteNowPlayingInfoAlbum"), AANStringValue(info, @"kMRMediaRemoteNowPlayingInfoUniqueIdentifier"), AANStringValue(info, @"kMRMediaRemoteNowPlayingInfoDuration"), AANStringValue(info, @"kMRMediaRemoteNowPlayingInfoElapsedTime"), AANStringValue(info, @"kMRMediaRemoteNowPlayingInfoPlaybackRate"), (unsigned long)info.count);
    });
}

static void *AANLoadSymbol(const char *name, BOOL required) {
    void *fn = gMediaRemoteHandle ? dlsym(gMediaRemoteHandle, name) : NULL;
    if (gDebugLogs || required) AANLog(@"symbol %-64s %@", name, fn ? @"FOUND" : @"missing");
    if (required && !fn) AANLog(@"missing required symbol %s", name);
    return fn;
}

static NSString *AANCopyStringConstant(const char *name) {
    CFStringRef *constant = gMediaRemoteHandle ? (CFStringRef *)dlsym(gMediaRemoteHandle, name) : NULL;
    if (!constant || !*constant) {
        if (gDebugLogs) AANLog(@"constant missing %s", name);
        return nil;
    }
    return [(__bridge NSString *)*constant copy];
}

static BOOL AANResolveMediaRemote(void) {
    if (gMediaRemoteHandle) return YES;
    gMediaRemoteHandle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    if (!gMediaRemoteHandle) {
        AANLog(@"dlopen MediaRemote failed: %s", dlerror());
        return NO;
    }
    AANLog(@"dlopen MediaRemote OK");

    gRegisterNowPlaying = (MRMediaRemoteRegisterForNowPlayingNotificationsFn)AANLoadSymbol("MRMediaRemoteRegisterForNowPlayingNotifications", NO);
    gBeginRouteDiscovery = (MRMediaRemoteBeginRouteDiscoveryFn)AANLoadSymbol("MRMediaRemoteBeginRouteDiscovery", NO);
    gGetIsPlaying = (MRMediaRemoteGetNowPlayingApplicationIsPlayingFn)AANLoadSymbol("MRMediaRemoteGetNowPlayingApplicationIsPlaying", NO);
    gGetAnyIsPlaying = (MRMediaRemoteGetAnyApplicationIsPlayingFn)AANLoadSymbol("MRMediaRemoteGetAnyApplicationIsPlaying", NO);
    gGetPlaybackState = (MRMediaRemoteGetNowPlayingApplicationPlaybackStateFn)AANLoadSymbol("MRMediaRemoteGetNowPlayingApplicationPlaybackState", NO);
    gGetNowPlayingPID = (MRMediaRemoteGetNowPlayingApplicationPIDFn)AANLoadSymbol("MRMediaRemoteGetNowPlayingApplicationPID", NO);
    gGetNowPlayingInfo = (MRMediaRemoteGetNowPlayingInfoFn)AANLoadSymbol("MRMediaRemoteGetNowPlayingInfo", NO);
    gGetContext = (MRAVOutputContextGetSharedSystemAudioContextFn)AANLoadSymbol("MRAVOutputContextGetSharedSystemAudioContext", YES);
    gCopyDevices = (MRAVOutputContextCopyOutputDevicesFn)AANLoadSymbol("MRAVOutputContextCopyOutputDevices", YES);
    gCopyName = (MRAVOutputDeviceCopyNameFn)AANLoadSymbol("MRAVOutputDeviceCopyName", NO);
    gCopyModelID = (MRAVOutputDeviceCopyModelIDFn)AANLoadSymbol("MRAVOutputDeviceCopyModelID", NO);
    gCopyAvailableModes = (MRAVOutputDeviceCopyAvailableBluetoothListeningModeFn)AANLoadSymbol("MRAVOutputDeviceCopyAvailableBluetoothListeningMode", YES);
    gCopyCurrentMode = (MRAVOutputDeviceCopyCurrentBluetoothListeningModeFn)AANLoadSymbol("MRAVOutputDeviceCopyCurrentBluetoothListeningMode", YES);
    gSetMode = (MRAVOutputDeviceSetCurrentBluetoothListeningModeFn)AANLoadSymbol("MRAVOutputDeviceSetCurrentBluetoothListeningMode", YES);

    gIsPlayingNotification = AANCopyStringConstant("kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification");
    gPlaybackStateNotification = AANCopyStringConstant("kMRMediaRemoteNowPlayingApplicationPlaybackStateDidChangeNotification");
    gRouteStatusNotification = AANCopyStringConstant("kMRMediaRemoteRouteStatusDidChangeNotification");
    gPickableRoutesNotification = AANCopyStringConstant("kMRMediaRemotePickableRoutesDidChangeNotification");
    gDistributedAppPlayingNotification = AANCopyStringConstant("kMRNowPlayingAppIsPlayingDidChangeDistributedNotificationName");
    gDistributedActivePlayersNotification = AANCopyStringConstant("kMRNowPlayingActivePlayersIsPlayingDidChangeDistributedNotificationName");

    return gGetContext && gCopyDevices && gCopyAvailableModes && gCopyCurrentMode && gSetMode;
}

static NSArray *AANCopyOutputDevices(void) {
    if (!AANResolveMediaRemote()) return @[];
    id context = nil;
    @try {
        context = gGetContext();
    } @catch (NSException *exception) {
        AANLog(@"get context exception=%@", exception);
        return @[];
    }
    if (!context) return @[];

    id devices = nil;
    @try {
        devices = CFBridgingRelease(gCopyDevices(context));
    } @catch (NSException *exception) {
        AANLog(@"copy devices exception=%@", exception);
        return @[];
    }
    return [devices isKindOfClass:[NSArray class]] ? devices : @[];
}

static NSArray *AANCopyAvailableModes(id device) {
    if (!device || !gCopyAvailableModes) return @[];
    id modes = nil;
    @try {
        modes = CFBridgingRelease(gCopyAvailableModes(device));
    } @catch (NSException *exception) {
        AANLog(@"copy modes exception=%@", exception);
        return @[];
    }
    return [modes isKindOfClass:[NSArray class]] ? modes : @[];
}

static id AANCopyCurrentMode(id device) {
    if (!device || !gCopyCurrentMode) return nil;
    @try {
        return CFBridgingRelease(gCopyCurrentMode(device));
    } @catch (NSException *exception) {
        AANLog(@"copy current mode exception=%@", exception);
        return nil;
    }
}

static id AANFindMode(NSArray *modes, NSString *needle) {
    for (id mode in modes) {
        if ([[[mode description] lowercaseString] containsString:[needle lowercaseString]]) return mode;
    }
    return nil;
}

static NSString *AANDeviceName(id device) {
    if (!device || !gCopyName) return nil;
    @try {
        id name = CFBridgingRelease(gCopyName(device));
        return [name isKindOfClass:[NSString class]] ? name : nil;
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSString *AANDeviceModelID(id device) {
    if (!device || !gCopyModelID) return nil;
    @try {
        id model = CFBridgingRelease(gCopyModelID(device));
        return [model isKindOfClass:[NSString class]] ? model : nil;
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSString *AANDeviceKey(id device) {
    NSString *name = AANDeviceName(device) ?: @"unknown";
    NSString *model = AANDeviceModelID(device) ?: @"unknown";
    return [NSString stringWithFormat:@"%@|%@", name, model];
}

static id AANPickCapableDevice(NSArray *devices, id *ancMode, id *transparencyMode) {
    if (ancMode) *ancMode = nil;
    if (transparencyMode) *transparencyMode = nil;
    for (id device in devices) {
        NSArray *modes = AANCopyAvailableModes(device);
        id anc = AANFindMode(modes, @"ActiveNoiseCancellation");
        id transparency = AANFindMode(modes, @"AudioTransparency");
        if (anc && transparency) {
            if (ancMode) *ancMode = anc;
            if (transparencyMode) *transparencyMode = transparency;
            return device;
        }
    }
    return nil;
}

static id AANModeTokenForTarget(id device, AANNoiseMode targetMode) {
    if (!device) return nil;
    NSArray *modes = AANCopyAvailableModes(device);
    switch (targetMode) {
        case AANNoiseModeANC:
            return AANFindMode(modes, @"ActiveNoiseCancellation");
        case AANNoiseModeTransparency:
            return AANFindMode(modes, @"AudioTransparency");
        case AANNoiseModeNormal:
            return AANFindMode(modes, @"Normal");
        default:
            return nil;
    }
}

static id AANFreshCapableDeviceForTarget(AANNoiseMode targetMode, id *modeToken) {
    id anc = nil;
    id transparency = nil;
    id device = AANPickCapableDevice(AANCopyOutputDevices(), &anc, &transparency);
    if (modeToken) *modeToken = AANModeTokenForTarget(device, targetMode);
    return device;
}

static BOOL AANCurrentModeMatches(id current, AANNoiseMode target) {
    NSString *desc = [[current description] lowercaseString];
    if (target == AANNoiseModeANC) return [desc containsString:@"activenoisecancellation"];
    if (target == AANNoiseModeTransparency) return [desc containsString:@"audiotransparency"];
    if (target == AANNoiseModeNormal) return [desc containsString:@"normal"];
    return NO;
}

static AANNoiseMode AANDesiredModeForState(BOOL hasTargetDevice);

static void AANVerifyModeLater(AANNoiseMode targetMode, NSString *reason, NSUInteger attempt, NSTimeInterval delay) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        id modeToken = nil;
        id device = AANFreshCapableDeviceForTarget(targetMode, &modeToken);
        id current = AANCopyCurrentMode(device);
        BOOL matched = AANCurrentModeMatches(current, targetMode);
        if (gDebugLogs || !matched) {
            AANLog(@"verify %@ attempt=%lu delay=%.1fs reason=%@ current=%@ matched=%d", AANModeName(targetMode), (unsigned long)attempt, delay, reason, AANDescribe(current), matched ? 1 : 0);
        }
        if (matched || attempt >= 2) return;
        if (!device || !modeToken) {
            AANLog(@"verify %@ retry skipped reason=%@ no fresh target", AANModeName(targetMode), reason);
            return;
        }
        if (targetMode != AANDesiredModeForState(device != nil)) {
            AANLog(@"verify %@ retry skipped reason=%@ desired changed to %@", AANModeName(targetMode), reason, AANModeName(AANDesiredModeForState(device != nil)));
            return;
        }
        id error = nil;
        BOOL ok = NO;
        @try {
            ok = gSetMode(device, modeToken, &error);
        } @catch (NSException *exception) {
            AANLog(@"verify retry %@ exception reason=%@ exception=%@", AANModeName(targetMode), reason, exception);
            return;
        }
        AANLog(@"verify retry %@ returned=%d reason=%@ error=%@", AANModeName(targetMode), ok ? 1 : 0, reason, AANDescribe(error));
    });
}

static BOOL AANSetModeIfNeeded(id device, id modeToken, AANNoiseMode targetMode, NSString *reason) {
    if (!device || !modeToken || targetMode == AANNoiseModeNone) return NO;
    NSTimeInterval now = AANNow();
    if (now < gSuppressUntil) {
        AANLog(@"skip set %@ reason=%@ suppressed %.1fs", AANModeName(targetMode), reason, gSuppressUntil - now);
        return NO;
    }
    if (now - gLastAppliedAt < kAANCooldownSeconds && gLastSetAttemptMode == targetMode) {
        AANLog(@"skip set %@ reason=%@ same-direction cooldown", AANModeName(targetMode), reason);
        return NO;
    }

    id current = AANCopyCurrentMode(device);
    if (AANCurrentModeMatches(current, targetMode)) {
        gLastAppliedMode = targetMode;
        if (gDebugLogs) AANLog(@"already %@ reason=%@ current=%@", AANModeName(targetMode), reason, AANDescribe(current));
        return YES;
    }

    id error = nil;
    BOOL ok = NO;
    @try {
        ok = gSetMode(device, modeToken, &error);
    } @catch (NSException *exception) {
        AANLog(@"set %@ exception reason=%@ exception=%@", AANModeName(targetMode), reason, exception);
        gSuppressUntil = now + kAANSuppressSeconds;
        return NO;
    }

    gLastAppliedAt = now;
    gLastSetAttemptMode = targetMode;
    if (ok) {
        gLastAppliedMode = targetMode;
        AANLog(@"set %@ ok reason=%@ before=%@", AANModeName(targetMode), reason, AANDescribe(current));
        AANVerifyModeLater(targetMode, reason, 1, 0.3);
        AANVerifyModeLater(targetMode, reason, 2, 0.9);
        return YES;
    }

    gSuppressUntil = now + kAANSuppressSeconds;
    AANLog(@"set %@ failed reason=%@ before=%@ error=%@ suppress=%.0fs", AANModeName(targetMode), reason, AANDescribe(current), AANDescribe(error), kAANSuppressSeconds);
    return NO;
}

static BOOL AANIsInTrackTransitionWindow(void) {
    return gTrackTransitionUntil > AANNow();
}

static AANNoiseMode AANDesiredModeForState(BOOL hasTargetDevice) {
    if (!hasTargetDevice) return AANNoiseModeNone;
    if (gPlaybackState == AANPlaybackStatePlaying) {
        if (AANIsInTrackTransitionWindow()) return AANNoiseModeNone;
        return AANNoiseModeANC;
    }
    if (gPlaybackState == AANPlaybackStateStopped) {
        if (AANNow() < gStartupGuardUntil) return AANNoiseModeNone;
        if (!gHasSeenPlayingSinceTarget) return AANNoiseModeNone;
        if (!gStopConfirmedReady) return AANNoiseModeNone;
        switch (gPostPauseBehavior) {
            case AANPostPauseBehaviorTransparency:
                return AANNoiseModeTransparency;
            case AANPostPauseBehaviorNormal:
                return AANNoiseModeNormal;
            case AANPostPauseBehaviorNone:
            default:
                return AANNoiseModeNone;
        }
    }
    if (gAutoANCOnConnect && !gHadTargetDevice) return AANNoiseModeANC;
    return AANNoiseModeNone;
}

static void AANReconcile(NSString *reason) {
    if (!gEnabled) return;
    if (!AANResolveMediaRemote()) return;

    id anc = nil;
    id transparency = nil;
    id normal = nil;
    NSArray *devices = AANCopyOutputDevices();
    id device = AANPickCapableDevice(devices, &anc, &transparency);
    if (device) {
        normal = AANFindMode(AANCopyAvailableModes(device), @"Normal");
    }
    BOOL hasTarget = device != nil;

    if (hasTarget) {
        NSString *deviceKey = AANDeviceKey(device);
        BOOL newDevice = !gHadTargetDevice || ![gTargetDeviceKey isEqualToString:deviceKey];
        gLastTargetSeenAt = AANNow();
        if (newDevice) {
            if (gSuppressUntil > AANNow()) {
                AANLog(@"clear suppress on target device present reason=%@ remaining=%.1fs", reason, gSuppressUntil - AANNow());
                gSuppressUntil = 0;
            }
            gTargetDeviceKey = deviceKey;
            gHasSeenPlayingSinceTarget = NO;
            gStopConfirmedReady = NO;
            gStartupGuardUntil = AANNow() + kAANStartupGuardSeconds;
            AANLog(@"target device present key=%@ reason=%@ guard=%.1fs", deviceKey, reason, kAANStartupGuardSeconds);
            if (gAutoANCOnConnect) {
                AANSetModeIfNeeded(device, anc, AANNoiseModeANC, @"device-present");
            }
        }
    } else if (gHadTargetDevice) {
        AANLog(@"target device gone reason=%@", reason);
        gTargetDeviceKey = nil;
        gHasSeenPlayingSinceTarget = NO;
        gStopConfirmedReady = NO;
        gLastSetAttemptMode = AANNoiseModeNone;
        gLastAppliedMode = AANNoiseModeNone;
    } else {
        NSTimeInterval now = AANNow();
        if (now - gLastNoTargetLogAt > 10.0) {
            gLastNoTargetLogAt = now;
            AANLog(@"no capable AirPods target reason=%@ devices=%lu", reason, (unsigned long)devices.count);
        }
    }

    AANNoiseMode desired = AANDesiredModeForState(hasTarget);
    if (hasTarget && gDebugLogs) {
        AANLog(@"reconcile reason=%@ hasTarget=%d playback=%@ current=%@ desired=%@ suppressRemaining=%.1fs", reason, hasTarget ? 1 : 0, AANPlaybackName(gPlaybackState), AANDescribe(AANCopyCurrentMode(device)), AANModeName(desired), MAX(0.0, gSuppressUntil - AANNow()));
    }
    if (desired == AANNoiseModeANC) {
        AANSetModeIfNeeded(device, anc, desired, reason);
    } else if (desired == AANNoiseModeTransparency) {
        gStopConfirmedReady = NO;
        AANSetModeIfNeeded(device, transparency, desired, reason);
    } else if (desired == AANNoiseModeNormal) {
        gStopConfirmedReady = NO;
        AANSetModeIfNeeded(device, normal, desired, reason);
    } else if (gDebugLogs) {
        AANLog(@"no desired mode reason=%@ hasTarget=%d playback=%@", reason, hasTarget ? 1 : 0, AANPlaybackName(gPlaybackState));
    }

    gHadTargetDevice = hasTarget;
}

static void AANRunDeferredStopConfirm(NSUInteger generation, NSString *reason) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kAANDeferredStopConfirmSeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation != gDeferredStopGeneration) return;
        if (gPlaybackState != AANPlaybackStateStopped) {
            AANLog(@"deferred stop ignored reason=%@ playback=%@", reason, AANPlaybackName(gPlaybackState));
            return;
        }
        NSTimeInterval age = AANNow() - gLastNowPlayingAt;
        BOOL recentRateZero = gHasLastNowPlayingSnapshot && age <= 3.0 && gLastNowPlayingRate < 0.01;
        if (!recentRateZero || AANLooksLikeTrackTransitionNoise()) {
            AANLog(@"deferred stop skipped reason=%@ recentRateZero=%d detail=%@", reason, recentRateZero ? 1 : 0, AANTrackTransitionReason());
            return;
        }
        AANLog(@"deferred stop confirmed reason=%@ delay=%.1fs", reason, kAANDeferredStopConfirmSeconds);
        gStopConfirmedReady = YES;
        AANReconcile([reason stringByAppendingString:@":deferred-confirmed"]);
    });
}

static void AANConfirmStoppedLater(NSUInteger generation, NSString *reason) {
    void (^confirmBlock)(void) = ^{
        if (generation != gStopConfirmGeneration) {
            if (gDebugLogs) AANLog(@"stop confirm ignored stale generation reason=%@", reason);
            return;
        }
        if (gPlaybackState != AANPlaybackStateStopped) {
            if (gDebugLogs) AANLog(@"stop confirm ignored playback=%@ reason=%@", AANPlaybackName(gPlaybackState), reason);
            return;
        }
        if (AANLooksLikeTrackTransitionNoise()) {
            gTrackTransitionUntil = AANNow() + kAANTrackTransitionWindowSeconds;
            AANLog(@"ignore confirmed stop as track-transition reason=%@ detail=%@", reason, AANTrackTransitionReason());
            return;
        }
        AANLog(@"stop confirmed reason=%@ delay=%.1fs", reason, kAANStopConfirmSeconds);
        gStopConfirmedReady = YES;
        AANReconcile([reason stringByAppendingString:@":confirmed"]);
    };

    if (kAANStopConfirmSeconds <= 0.01) {
        confirmBlock();
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kAANStopConfirmSeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), confirmBlock);
}

static void AANApplyPlaybackVotes(NSString *reason) {
    AANPlaybackState next = AANPlaybackStateUnknown;
    if (gPlaybackPositiveVotes > 0) {
        next = AANPlaybackStatePlaying;
    } else if (gPendingPlaybackQueries > 0 && gPlaybackNegativeVotes == gPendingPlaybackQueries) {
        next = AANPlaybackStateStopped;
    }

    if (next != gPlaybackState) {
        AANLog(@"playback %@ -> %@ reason=%@ votes +%lu -%lu/%lu", AANPlaybackName(gPlaybackState), AANPlaybackName(next), reason, (unsigned long)gPlaybackPositiveVotes, (unsigned long)gPlaybackNegativeVotes, (unsigned long)gPendingPlaybackQueries);
        gPlaybackState = next;
        if (next == AANPlaybackStateStopped) {
            if (AANLooksLikeTrackTransitionNoise()) {
                gTrackTransitionUntil = AANNow() + kAANTrackTransitionWindowSeconds;
                gDeferredStopGeneration++;
                AANLog(@"ignore stopped as track-transition reason=%@ detail=%@", reason, AANTrackTransitionReason());
                AANRunDeferredStopConfirm(gDeferredStopGeneration, reason);
                return;
            }
            gStopConfirmedReady = NO;
            gStopConfirmGeneration++;
            AANConfirmStoppedLater(gStopConfirmGeneration, reason);
            return;
        }
        if (next == AANPlaybackStatePlaying) {
            gDeferredStopGeneration++;
            if (gTrackTransitionUntil > AANNow()) {
                AANLog(@"track-transition playing reason=%@ remaining=%.1fs", reason, gTrackTransitionUntil - AANNow());
            }
            if (gSuppressUntil > AANNow()) {
                AANLog(@"clear suppress on playback start reason=%@ remaining=%.1fs", reason, gSuppressUntil - AANNow());
                gSuppressUntil = 0;
            }
            gStopConfirmedReady = NO;
            gHasSeenPlayingSinceTarget = YES;
            gStopConfirmGeneration++;
            AANReconcile(reason);
        }
    } else if (gDebugLogs) {
        AANLog(@"playback unchanged %@ reason=%@ votes +%lu -%lu/%lu", AANPlaybackName(gPlaybackState), reason, (unsigned long)gPlaybackPositiveVotes, (unsigned long)gPlaybackNegativeVotes, (unsigned long)gPendingPlaybackQueries);
    }
}

static void AANRecordPlaybackVote(BOOL available, BOOL playing, NSString *reason, NSUInteger generation) {
    if (!available) return;
    if (generation != gPlaybackQueryGeneration) {
        if (gDebugLogs) AANLog(@"ignore stale playback vote reason=%@ generation=%lu current=%lu", reason, (unsigned long)generation, (unsigned long)gPlaybackQueryGeneration);
        return;
    }
    if (playing) gPlaybackPositiveVotes++;
    else gPlaybackNegativeVotes++;
    if (gPlaybackPositiveVotes + gPlaybackNegativeVotes >= gPendingPlaybackQueries) {
        AANApplyPlaybackVotes(reason);
    }
}

static BOOL AANShouldLogNowPlayingForReason(NSString *reason) {
    return [reason containsString:@"NowPlayingApplication"] ||
           [reason containsString:@"nowPlayingApplication"] ||
           [reason containsString:@"nowPlayingActivePlayers"];
}

static void AANQueryPlaybackAndReconcile(NSString *reason) {
    if (!AANResolveMediaRemote()) return;
    if (AANShouldLogNowPlayingForReason(reason) && gDebugLogs) {
        AANLog(@"event reason=%@ currentPlayback=%@ generation=%lu", reason, AANPlaybackName(gPlaybackState), (unsigned long)(gPlaybackQueryGeneration + 1));
        AANLogNowPlayingSummary(reason);
    } else {
        AANLogNowPlayingSummary(reason);
    }
    gPendingPlaybackQueries = 0;
    gPlaybackPositiveVotes = 0;
    gPlaybackNegativeVotes = 0;
    NSUInteger generation = ++gPlaybackQueryGeneration;

    if (gGetIsPlaying) gPendingPlaybackQueries++;
    if (gGetAnyIsPlaying) gPendingPlaybackQueries++;
    if (gGetPlaybackState) gPendingPlaybackQueries++;

    if (gPendingPlaybackQueries == 0) {
        AANLog(@"playback unknown reason=%@ no query symbols", reason);
        gPlaybackState = AANPlaybackStateUnknown;
        AANReconcile(reason);
        return;
    }

    NSString *reasonCopy = [reason copy];
    if (gGetIsPlaying) {
        gGetIsPlaying(dispatch_get_main_queue(), ^(Boolean isPlaying) {
            AANRecordPlaybackVote(YES, isPlaying ? YES : NO, reasonCopy, generation);
        });
    }
    if (gGetAnyIsPlaying) {
        gGetAnyIsPlaying(dispatch_get_main_queue(), ^(Boolean isPlaying) {
            AANRecordPlaybackVote(YES, isPlaying ? YES : NO, reasonCopy, generation);
        });
    }
    if (gGetPlaybackState) {
        gGetPlaybackState(dispatch_get_main_queue(), ^(unsigned int state) {
            BOOL playing = state == 1;
            AANRecordPlaybackVote(YES, playing, reasonCopy, generation);
        });
    }
}

static void AANDarwinPlaybackNotification(CFNotificationCenterRef center, void *observer, CFStringRef nameRef, const void *object, CFDictionaryRef userInfo) {
    (void)center; (void)observer; (void)object; (void)userInfo;
    NSString *reason = [NSString stringWithFormat:@"darwin:%@", (__bridge NSString *)nameRef];
    AANQueryPlaybackAndReconcile(reason);
}

static void AANObserveName(NSString *name) {
    if (name.length == 0) return;
    [[NSNotificationCenter defaultCenter] addObserverForName:name object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        NSString *reason = [NSString stringWithFormat:@"notification:%@", note.name];
        AANQueryPlaybackAndReconcile(reason);
    }];
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, AANDarwinPlaybackNotification, (__bridge CFStringRef)name, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    if (gDebugLogs) AANLog(@"observing %@", name);
}

static void AANRegisterNotifications(void) {
    if (gRegisterNowPlaying) {
        gRegisterNowPlaying(dispatch_get_main_queue());
        if (gDebugLogs) AANLog(@"registered now playing notifications");
    }
    if (gBeginRouteDiscovery) {
        gBeginRouteDiscovery();
        if (gDebugLogs) AANLog(@"begin route discovery");
    }
    AANObserveName(gIsPlayingNotification);
    AANObserveName(gPlaybackStateNotification);
    AANObserveName(gRouteStatusNotification);
    AANObserveName(gPickableRoutesNotification);
    AANObserveName(gDistributedAppPlayingNotification);
    AANObserveName(gDistributedActivePlayersNotification);
}

static void AANPrefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    (void)center; (void)observer; (void)name; (void)object; (void)userInfo;
    AANLoadPrefs();
    AANQueryPlaybackAndReconcile(@"prefs-changed");
}

static void AANScheduleStartupReconcile(NSTimeInterval delay, NSString *reason) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        AANReconcile(reason);
        AANQueryPlaybackAndReconcile([reason stringByAppendingString:@"-playback"]);
    });
}

static void AANStart(void) {
    if (gStarted) return;
    gStarted = YES;
    AANLoadPrefs();
    if (!AANResolveMediaRemote()) return;
    AANRegisterNotifications();
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, AANPrefsChanged, (__bridge CFStringRef)kPrefsChangedNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    AANLog(@"AirPodsAutoNoise v1.0.1 started");
    AANReconcile(@"startup");
    AANQueryPlaybackAndReconcile(@"startup-playback");
    AANScheduleStartupReconcile(1.5, @"startup-reconcile-1");
    AANScheduleStartupReconcile(5.0, @"startup-reconcile-5");
    AANScheduleStartupReconcile(10.0, @"startup-reconcile-10");
    AANScheduleStartupReconcile(20.0, @"startup-reconcile-20");
}

%ctor {
    @autoreleasepool {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            AANStart();
        });
    }
}
