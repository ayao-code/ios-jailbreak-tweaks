#import "LAPShared.h"

NSString *const LAPPreferencesDomain = @"ayao.lockaudioprofiles";
NSString *const LAPPreferencesChangedNotification = @"ayao.lockaudioprofiles/preferences.changed";

static id LAPCopyPreference(NSString *key) {
    CFStringRef domain = (__bridge CFStringRef)LAPPreferencesDomain;
    CFPreferencesAppSynchronize(domain);
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key, domain);
    return CFBridgingRelease(value);
}

BOOL LAPReadBoolPreference(NSString *key, BOOL defaultValue) {
    id value = LAPCopyPreference(key);
    return value ? [value boolValue] : defaultValue;
}

double LAPReadDoublePreference(NSString *key, double defaultValue) {
    id value = LAPCopyPreference(key);
    return value ? [value doubleValue] : defaultValue;
}

void LAPWritePreference(NSString *key, id value) {
    CFStringRef domain = (__bridge CFStringRef)LAPPreferencesDomain;
    CFPreferencesSetAppValue(
        (__bridge CFStringRef)key,
        (__bridge CFPropertyListRef)value,
        domain
    );
    CFPreferencesAppSynchronize(domain);
}

void LAPPostPreferencesChangedNotification(void) {
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)LAPPreferencesChangedNotification,
        NULL,
        NULL,
        YES
    );
}
