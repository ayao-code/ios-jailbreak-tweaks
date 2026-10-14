#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <substrate.h>
#import <stdint.h>

#define NSLog(...) do { if (NO) { (void)[NSString stringWithFormat:__VA_ARGS__]; } } while (0)

static id gDSGesture = nil;
static BOOL gDSRecording = NO;
static BOOL gDSStarting = NO;
static BOOL gDSVirtualStateActive = NO;
static UIGestureRecognizerState gDSVirtualState = UIGestureRecognizerStatePossible;
static NSInteger (*gDSOriginalGestureState)(id, SEL) = NULL;

static NSString * const kDSPrefsDomain = @"ayao.aipowerbutton";
static NSString * const kDSStartNotification = @"ayao.aipowerbutton.deepseek.start";
static NSString * const kDSStopSendNotification = @"ayao.aipowerbutton.deepseek.stopSend";

static void DSSetPreferenceString(NSString *key, NSString *value) {
    CFStringRef domain = (__bridge CFStringRef)kDSPrefsDomain;
    CFPreferencesSetAppValue((__bridge CFStringRef)key, value ? (__bridge CFPropertyListRef)value : NULL, domain);
    CFPreferencesAppSynchronize(domain);
}

static BOOL DSClassNameContains(id object, NSString *part) {
    if (!object) {
        return NO;
    }
    NSString *className = NSStringFromClass([object class]);
    return [className rangeOfString:part].location != NSNotFound;
}

static id DSFirstVoiceGesture(UIView *view) {
    if (!view || ![view respondsToSelector:@selector(gestureRecognizers)]) {
        return nil;
    }

    for (id gesture in view.gestureRecognizers) {
        if (DSClassNameContains(gesture, @"VoiceGesture")) {
            return gesture;
        }
    }
    return nil;
}

static NSDictionary *DSFindVoiceGestureTarget(UIView *view, UIWindow *window) {
    if (!view || view.hidden || view.alpha <= 0.01 || CGRectIsEmpty(view.bounds)) {
        return nil;
    }

    for (UIView *subview in [view.subviews reverseObjectEnumerator]) {
        NSDictionary *target = DSFindVoiceGestureTarget(subview, window);
        if (target) {
            return target;
        }
    }

    id gesture = DSFirstVoiceGesture(view);
    if (!gesture) {
        return nil;
    }

    CGPoint point = [view convertPoint:CGPointMake(CGRectGetMidX(view.bounds), CGRectGetMidY(view.bounds)) toView:window];
    if (!CGRectContainsPoint(window.bounds, point)) {
        return nil;
    }
    return @{ @"gesture": gesture };
}

static NSDictionary *DSFindTarget(void) {
    UIApplication *application = UIApplication.sharedApplication;
    SEL windowsSelector = @selector(windows);
    NSArray *windows = [application respondsToSelector:windowsSelector] ? ((id (*)(id, SEL))objc_msgSend)(application, windowsSelector) : nil;
    CGRect bounds = UIScreen.mainScreen.bounds;
    CGPoint fallbackPoint = CGPointMake(CGRectGetMidX(bounds), CGRectGetMaxY(bounds) - 132.0);

    for (UIWindow *window in [windows reverseObjectEnumerator]) {
        if (window.hidden || window.alpha <= 0.01) {
            continue;
        }

        NSDictionary *target = DSFindVoiceGestureTarget(window, window);
        if (target) {
            return target;
        }

        UIView *hitView = [window hitTest:fallbackPoint withEvent:nil];
        if (!hitView) {
            continue;
        }

        UIView *promptView = hitView.superview;
        UIView *inputView = promptView.superview;
        id gesture = DSFirstVoiceGesture(promptView) ?: DSFirstVoiceGesture(inputView);
        if (gesture) {
            return @{ @"gesture": gesture };
        }
    }
    return nil;
}

static NSInteger DSHookedGestureState(id gesture, SEL selector) {
    if (gDSVirtualStateActive && gesture == gDSGesture) {
        return gDSVirtualState;
    }
    return gDSOriginalGestureState ? gDSOriginalGestureState(gesture, selector) : UIGestureRecognizerStatePossible;
}

static BOOL DSInstallGestureStateHook(void) {
    static BOOL installed = NO;
    if (installed) {
        return YES;
    }

    Class gestureClass = NSClassFromString(@"_TtCC13DeepSeek_Chat13InputAreaView12VoiceGesture");
    if (!gestureClass) {
        return NO;
    }
    MSHookMessageEx(gestureClass, @selector(state), (IMP)DSHookedGestureState, (IMP *)&gDSOriginalGestureState);
    installed = gDSOriginalGestureState != NULL;
    return installed;
}

static BOOL DSInvokeLongPress(id gesture, UIGestureRecognizerState state) {
    SEL actionSelector = NSSelectorFromString(@"__onLongPress:");
    if (![gesture respondsToSelector:actionSelector] || !DSInstallGestureStateHook()) {
        return NO;
    }

    BOOL invoked = NO;
    @try {
        gDSVirtualState = state;
        gDSVirtualStateActive = YES;
        ((void (*)(id, SEL, id))objc_msgSend)(gesture, actionSelector, gesture);
        invoked = YES;
    } @catch (__unused NSException *exception) {
        invoked = NO;
    } @finally {
        gDSVirtualStateActive = NO;
        gDSVirtualState = UIGestureRecognizerStatePossible;
    }
    return invoked;
}

static BOOL DSStartRecording(void) {
    if (gDSRecording && gDSGesture) {
        return YES;
    }

    NSDictionary *target = DSFindTarget();
    if (!target) {
        return NO;
    }

    gDSGesture = target[@"gesture"];
    NSInteger state = [gDSGesture respondsToSelector:@selector(state)] ? ((NSInteger (*)(id, SEL))objc_msgSend)(gDSGesture, @selector(state)) : -1;
    if (state != UIGestureRecognizerStatePossible || !DSInvokeLongPress(gDSGesture, UIGestureRecognizerStateBegan)) {
        gDSGesture = nil;
        return NO;
    }

    gDSRecording = YES;
    DSSetPreferenceString(@"deepseekPendingAction", nil);
    return YES;
}

static void DSStartAttempt(NSInteger attempts) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gDSStarting) {
            return;
        }
        if (DSStartRecording()) {
            gDSStarting = NO;
            return;
        }
        if (attempts <= 0) {
            gDSStarting = NO;
            DSSetPreferenceString(@"deepseekPendingAction", nil);
            return;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            DSStartAttempt(attempts - 1);
        });
    });
}

static void DSStartWithAttempts(NSInteger attempts) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if ((gDSRecording && gDSGesture) || gDSStarting) {
            return;
        }
        gDSStarting = YES;
        DSStartAttempt(attempts);
    });
}

static void DSSendOnMain(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gDSGesture) {
            gDSRecording = NO;
            DSSetPreferenceString(@"deepseekPendingAction", nil);
            return;
        }

        DSInvokeLongPress(gDSGesture, UIGestureRecognizerStateEnded);
        gDSRecording = NO;
        gDSGesture = nil;
        DSSetPreferenceString(@"deepseekPendingAction", nil);
    });
}

static void DSStartCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    DSStartWithAttempts(8);
}

static void DSStopSendCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    gDSStarting = NO;
    DSSetPreferenceString(@"deepseekPendingAction", nil);
    DSSendOnMain();
}

%ctor {
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, DSStartCallback, (__bridge CFStringRef)kDSStartNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, DSStopSendCallback, (__bridge CFStringRef)kDSStopSendNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}
