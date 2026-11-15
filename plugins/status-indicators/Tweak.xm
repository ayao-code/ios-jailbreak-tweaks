#import "SIController.h"
#import <objc/runtime.h>
#include <string.h>

@interface _UIStatusBar : UIView
@end
@interface UIStatusBar_Modern : UIView
@end
@interface SBLockScreenManager : NSObject
@end

static BOOL SIMethodCompatible(Class cls, SEL selector, const char *argumentType) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != (argumentType ? 3u : 2u)) return NO;
    char result[16] = {0}, argument[32] = {0};
    method_getReturnType(method, result, sizeof(result));
    if (strcmp(result, "v")) return NO;
    if (!argumentType) return YES;
    method_getArgumentType(method, 2, argument, sizeof(argument));
    if (argumentType[0] == '@') return argument[0] == '@';
    if (!strcmp(argumentType,@encode(BOOL))) return !strcmp(argument,"B") || !strcmp(argument,"c");
    return !strcmp(argument, argumentType);
}

%group SIHostLifecycle
%hook _UIStatusBar
- (void)layoutSubviews {
    %orig;
    [[SIController shared] rememberHost:self];
    [[SIController shared] requestLayout];
}
- (void)didMoveToWindow {
    %orig;
    [[SIController shared] rememberHost:self];
    [[SIController shared] hostDidChange:self readCurrentData:YES];
}
- (void)setHidden:(BOOL)hidden {
    %orig;
    [[SIController shared] hostDidChange:self readCurrentData:!hidden];
}
- (void)setAlpha:(CGFloat)alpha {
    %orig;
    [[SIController shared] hostDidChange:self readCurrentData:alpha > .01];
}
%end
%end

%group SILockLifecycle
%hook SBLockScreenManager
- (void)_reallySetUILocked:(BOOL)locked {
    %orig;
    [[SIController shared] requestLayout];
}
%end
%end

%group SIWrapperVisibility
%hook UIStatusBar_Modern
- (void)setHidden:(BOOL)hidden {
    %orig;
    [[SIController shared] requestLayout];
}
- (void)setAlpha:(CGFloat)alpha {
    %orig;
    [[SIController shared] requestLayout];
}
- (void)didMoveToWindow {
    %orig;
    [[SIController shared] rememberHost:self];
    [[SIController shared] requestLayout];
}
- (void)layoutSubviews {
    %orig;
    [[SIController shared] rememberHost:self];
    [[SIController shared] requestLayout];
}
%end
%end

%group SIHostData
%hook _UIStatusBar
- (void)_updateWithAggregatedData:(id)data {
    %orig;
    // VPN-only resolved snapshots are coalesced per host after the system commits.
    // Focus comes from its own service subscription, never this UI cache.
    [[SIController shared] hostDidUpdateData:self];
}
%end
%end

%group SIModernHostData
%hook UIStatusBar_Modern
- (void)_updateWithAggregatedData:(id)data {
    %orig;
    [[SIController shared] hostDidUpdateData:self];
}
%end
%end

%group SIWindowVisibility
%hook UIStatusBarWindow
- (void)setHidden:(BOOL)hidden {
    %orig;
    [[SIController shared] requestLayout];
}
- (void)setAlpha:(CGFloat)alpha {
    %orig;
    [[SIController shared] requestLayout];
}
%end
%end

%group SIControlCenterVisibility
%hook SBControlCenterWindow
- (void)setHidden:(BOOL)hidden {
    %orig;
    [[SIController shared] requestLayout];
}
- (void)setAlpha:(CGFloat)alpha {
    %orig;
    [[SIController shared] requestLayout];
}
%end
%end

%group SIMainSwitcherVisibility
%hook SBMainSwitcherWindow
- (void)setHidden:(BOOL)hidden {
    %orig;
    [[SIController shared] requestLayout];
}
- (void)setAlpha:(CGFloat)alpha {
    %orig;
    [[SIController shared] requestLayout];
}
%end
%end

%ctor {
    Class cls = NSClassFromString(@"_UIStatusBar");
    if (SIMethodCompatible(cls, @selector(layoutSubviews), NULL)
        && SIMethodCompatible(cls, @selector(didMoveToWindow), NULL)
        && SIMethodCompatible(cls, @selector(setHidden:), @encode(BOOL))
        && SIMethodCompatible(cls, @selector(setAlpha:), @encode(CGFloat))) {
        %init(SIHostLifecycle);
    }
    if (SIMethodCompatible(cls, NSSelectorFromString(@"_updateWithAggregatedData:"), "@")) {
        %init(SIHostData);
    }
    Class wrapper = NSClassFromString(@"UIStatusBar_Modern");
    if (SIMethodCompatible(wrapper, NSSelectorFromString(@"_updateWithAggregatedData:"), "@")) {
        %init(SIModernHostData);
    }
    if (SIMethodCompatible(wrapper, @selector(setHidden:), @encode(BOOL))
        && SIMethodCompatible(wrapper, @selector(setAlpha:), @encode(CGFloat))
        && SIMethodCompatible(wrapper, @selector(didMoveToWindow), NULL)
        && SIMethodCompatible(wrapper, @selector(layoutSubviews), NULL)) {
        %init(SIWrapperVisibility);
    }
    Class window = NSClassFromString(@"UIStatusBarWindow");
    if (SIMethodCompatible(window, @selector(setHidden:), @encode(BOOL))
        && SIMethodCompatible(window, @selector(setAlpha:), @encode(CGFloat))) {
        %init(SIWindowVisibility);
    }
    Class controlCenter = NSClassFromString(@"SBControlCenterWindow");
    if (SIMethodCompatible(controlCenter, @selector(setHidden:), @encode(BOOL))
        && SIMethodCompatible(controlCenter, @selector(setAlpha:), @encode(CGFloat))) {
        %init(SIControlCenterVisibility);
    }
    Class switcherWindow=NSClassFromString(@"SBMainSwitcherWindow");
    if (SIMethodCompatible(switcherWindow,@selector(setHidden:),@encode(BOOL))
        && SIMethodCompatible(switcherWindow,@selector(setAlpha:),@encode(CGFloat))) {
        %init(SIMainSwitcherVisibility);
    }
    Class lockManager = NSClassFromString(@"SBLockScreenManager");
    if (SIMethodCompatible(lockManager, NSSelectorFromString(@"_reallySetUILocked:"), @encode(BOOL))) {
        %init(SILockLifecycle);
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [[SIController shared] start];
#if SI_DIAGNOSTICS
        [[SIController shared] writeDiagnosticSnapshot];
#endif
    });
}
