#import "LAPRootListController.h"
#import <Celestial/AVSystemController.h>
#import <mach/mach_time.h>
#import <Preferences/PSSpecifier.h>
#import "../Shared/LAPShared.h"

static NSString *const MediaVolumeCategory = @"Audio/Video";
static NSString *const RingerVolumeCategory = @"Ringtone";
static CFAbsoluteTime systemVolumeWriteDeadline = 0;

@interface LAPRootListController ()
- (void)refreshControlAvailability;
@end

static void LAPSettingsPreferencesChanged(
    CFNotificationCenterRef center,
    void *observer,
    CFStringRef name,
    const void *object,
    CFDictionaryRef userInfo
) {
    (void)center;
    (void)name;
    (void)object;
    (void)userInfo;
    LAPRootListController *controller = (__bridge LAPRootListController *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        [controller reloadSpecifiers];
        [controller refreshControlAvailability];
    });
}

@implementation LAPRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge void *)self,
        LAPSettingsPreferencesChanged,
        (__bridge CFStringRef)LAPPreferencesChangedNotification,
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
    [[NSNotificationCenter defaultCenter]
        addObserver:self
        selector:@selector(systemVolumeChanged:)
        name:AVSystemController_SystemVolumeDidChangeNotification
        object:nil];
    [self refreshControlAvailability];
}

- (void)dealloc {
    CFNotificationCenterRemoveObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge void *)self,
        (__bridge CFStringRef)LAPPreferencesChangedNotification,
        NULL
    );
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshControlAvailability];
    [self reloadSpecifierID:@"overallMediaVolume"];
    [self reloadSpecifierID:@"overallRingerVolume"];
}

- (void)systemVolumeChanged:(NSNotification *)notification {
    (void)notification;
    if (CFAbsoluteTimeGetCurrent() <= systemVolumeWriteDeadline) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self reloadSpecifierID:@"overallMediaVolume"];
        [self reloadSpecifierID:@"overallRingerVolume"];
    });
}

- (BOOL)lockStateControlIsActiveForKey:(NSString *)key {
    BOOL profilesEnabled = LAPReadBoolPreference(@"profilesEnabled", NO);
    return profilesEnabled && LAPReadBoolPreference(key, YES);
}

- (void)setSpecifierID:(NSString *)specifierID enabled:(BOOL)enabled {
    PSSpecifier *specifier = [self specifierForID:specifierID];
    if (!specifier) {
        return;
    }
    [specifier setProperty:@(enabled) forKey:PSEnabledKey];
    [self reloadSpecifier:specifier];
}

- (void)refreshControlAvailability {
    BOOL profilesEnabled = LAPReadBoolPreference(@"profilesEnabled", NO);
    BOOL mediaUsesLockState = [self lockStateControlIsActiveForKey:@"manageMediaVolume"];
    BOOL ringerUsesLockState = [self lockStateControlIsActiveForKey:@"manageRingerVolume"];
    BOOL totalSilenceEnabled = LAPReadBoolPreference(@"totalSilenceEnabled", NO);

    [self setSpecifierID:@"overallMediaVolume" enabled:totalSilenceEnabled || !mediaUsesLockState];
    [self setSpecifierID:@"overallRingerVolume" enabled:!ringerUsesLockState && !totalSilenceEnabled];
    [self setSpecifierID:@"lockMediaVolume" enabled:mediaUsesLockState];
    [self setSpecifierID:@"unlockMediaVolume" enabled:mediaUsesLockState];
    [self setSpecifierID:@"lockRingerVolume" enabled:ringerUsesLockState];
    [self setSpecifierID:@"unlockRingerVolume" enabled:ringerUsesLockState];
    for (NSString *specifierID in @[
        @"lockRingVibration",
        @"lockSilentVibration",
        @"unlockRingVibration",
        @"unlockSilentVibration"
    ]) {
        [self setSpecifierID:specifierID enabled:profilesEnabled];
    }
}

- (void)setModePreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:PSKeyNameKey];
    if (!key) {
        return;
    }
    LAPWritePreference(key, value);
    LAPPostPreferencesChangedNotification();
    [self refreshControlAvailability];
}

- (id)readSystemVolume:(PSSpecifier *)specifier {
    NSString *category = [specifier propertyForKey:@"volumeCategory"];
    if ([category isEqualToString:RingerVolumeCategory] &&
        [self lockStateControlIsActiveForKey:@"manageRingerVolume"] &&
        LAPReadBoolPreference(@"ringerMuteOwned", NO)) {
        return @0;
    }

    float volume = 0.0f;
    if (![[AVSystemController sharedAVSystemController] getVolume:&volume forCategory:category]) {
        return @0;
    }
    return @(volume * 100.0f);
}

- (void)setSystemVolume:(id)value specifier:(PSSpecifier *)specifier {
    NSString *category = [specifier propertyForKey:@"volumeCategory"];
    BOOL usesLockState = [category isEqualToString:MediaVolumeCategory]
        ? [self lockStateControlIsActiveForKey:@"manageMediaVolume"]
        : [self lockStateControlIsActiveForKey:@"manageRingerVolume"];
    if (usesLockState ||
        ([category isEqualToString:RingerVolumeCategory] &&
         LAPReadBoolPreference(@"totalSilenceEnabled", NO))) {
        [self reloadSpecifier:specifier];
        return;
    }

    double percentage = MAX(0.0, MIN(100.0, [value doubleValue]));
    systemVolumeWriteDeadline = CFAbsoluteTimeGetCurrent() + 0.3;
    LAPWritePreference(@"manualVolumeRequest", @{
        @"category": category,
        @"value": @(percentage),
        @"id": @(mach_continuous_time())
    });
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)LAPManualVolumeChangedNotification,
        NULL,
        NULL,
        YES
    );
}

@end
