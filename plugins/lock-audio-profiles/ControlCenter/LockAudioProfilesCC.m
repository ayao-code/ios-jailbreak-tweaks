#import <ControlCenterUIKit/CCUIToggleModule.h>
#import <UIKit/UIKit.h>
#import "../Shared/LAPShared.h"

@interface LockAudioProfilesCC : CCUIToggleModule
@end

static void LAPControlCenterPreferencesChanged(
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
    LockAudioProfilesCC *module = (__bridge LockAudioProfilesCC *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        [module refreshState];
    });
}

@implementation LockAudioProfilesCC

- (UIImage *)glyphImageNamed:(NSString *)name {
    NSBundle *bundle = [NSBundle bundleForClass:self.class];
    UIImage *image = [UIImage imageNamed:name inBundle:bundle compatibleWithTraitCollection:nil];
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

- (UIImage *)systemGlyphNamed:(NSString *)symbolName fallback:(NSString *)fallbackName {
    UIImage *image = [UIImage systemImageNamed:symbolName];
    if (!image) {
        return [self glyphImageNamed:fallbackName];
    }
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:27.0 weight:UIImageSymbolWeightSemibold];
    return [[image imageByApplyingSymbolConfiguration:configuration] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            (__bridge void *)self,
            LAPControlCenterPreferencesChanged,
            (__bridge CFStringRef)LAPPreferencesChangedNotification,
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
    }
    return self;
}

- (void)dealloc {
    CFNotificationCenterRemoveObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge void *)self,
        (__bridge CFStringRef)LAPPreferencesChangedNotification,
        NULL
    );
}

- (BOOL)isSelected {
    return LAPReadBoolPreference(@"totalSilenceEnabled", NO);
}

- (void)setSelected:(BOOL)selected {
    if (self.isSelected == selected) {
        return;
    }
    LAPWritePreference(@"totalSilenceEnabled", @(selected));
    LAPPostPreferencesChangedNotification();
    [self refreshState];
}

- (UIImage *)iconGlyph {
    return [self systemGlyphNamed:@"speaker.wave.2.fill" fallback:@"sound-vibration"];
}

- (UIImage *)selectedIconGlyph {
    return [self systemGlyphNamed:@"speaker.slash.fill" fallback:@"sound-vibration-off"];
}

- (UIColor *)selectedColor {
    return [UIColor colorWithRed:0.94 green:0.20 blue:0.25 alpha:1.0];
}

@end
