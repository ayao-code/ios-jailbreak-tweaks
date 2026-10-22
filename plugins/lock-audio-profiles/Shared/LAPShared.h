#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString *const LAPPreferencesDomain;
FOUNDATION_EXPORT NSString *const LAPPreferencesChangedNotification;
FOUNDATION_EXPORT NSString *const LAPManualVolumeChangedNotification;

FOUNDATION_EXPORT BOOL LAPReadBoolPreference(NSString *key, BOOL defaultValue);
FOUNDATION_EXPORT double LAPReadDoublePreference(NSString *key, double defaultValue);
FOUNDATION_EXPORT void LAPWritePreference(NSString *key, id value);
FOUNDATION_EXPORT void LAPPostPreferencesChangedNotification(void);
