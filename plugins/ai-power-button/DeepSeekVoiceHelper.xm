#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <stdint.h>

#define NSLog(...) do { if (NO) { (void)[NSString stringWithFormat:__VA_ARGS__]; } } while (0)

static UIWindow *gDSWindow = nil;
static UIView *gDSHitView = nil;
static id gDSGesture = nil;
static id gDSTouch = nil;
static NSSet *gDSTouches = nil;
static NSMutableArray *gDSGestureArray = nil;
static BOOL gDSRecording = NO;
static BOOL gDSStarting = NO;

static NSString * const kDSPrefsDomain = @"ayao.aipowerbutton";
static NSString * const kDSStartNotification = @"ayao.aipowerbutton.deepseek.start";
static NSString * const kDSStopSendNotification = @"ayao.aipowerbutton.deepseek.stopSend";

static id DSAllocInit(Class cls) {
    if (!cls) {
        return nil;
    }
    id object = ((id (*)(id, SEL))objc_msgSend)(cls, @selector(alloc));
    return ((id (*)(id, SEL))objc_msgSend)(object, @selector(init));
}

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

    NSArray *gestures = [view gestureRecognizers];
    for (id gesture in gestures) {
        if (DSClassNameContains(gesture, @"VoiceGesture")) {
            return gesture;
        }
    }
    return nil;
}

static NSDictionary *DSFindTarget(void) {
    UIApplication *app = [UIApplication sharedApplication];
    SEL windowsSelector = @selector(windows);
    NSArray *windows = [app respondsToSelector:windowsSelector] ? ((id (*)(id, SEL))objc_msgSend)(app, windowsSelector) : nil;
    CGRect bounds = [[UIScreen mainScreen] bounds];
    CGPoint point = CGPointMake(CGRectGetMidX(bounds), CGRectGetMaxY(bounds) - 132.0);
    NSLog(@"[DeepSeekVoiceHelper] find target windows=%lu point=%.0f,%.0f", (unsigned long)[windows count], point.x, point.y);

    for (UIWindow *window in [windows reverseObjectEnumerator]) {
        if ([window respondsToSelector:@selector(isHidden)] && [window isHidden]) {
            continue;
        }
        if ([window respondsToSelector:@selector(alpha)] && [window alpha] <= 0.01) {
            continue;
        }

        UIView *hitView = [window hitTest:point withEvent:nil];
        if (!hitView) {
            continue;
        }

        UIView *promptView = [hitView superview];
        UIView *inputView = [promptView superview];
        id gesture = DSFirstVoiceGesture(promptView);
        if (!gesture) {
            gesture = DSFirstVoiceGesture(inputView);
        }
        if (!gesture) {
            continue;
        }

        NSLog(@"[DeepSeekVoiceHelper] found target hit=%@ gesture=%@", NSStringFromClass([hitView class]), NSStringFromClass([gesture class]));
        return @{
            @"window": window,
            @"hitView": hitView,
            @"gesture": gesture
        };
    }
    NSLog(@"[DeepSeekVoiceHelper] target not found");
    return nil;
}

static void DSWriteTouch(id touch, UIWindow *window, UIView *view, id gesture, NSInteger phase) {
    gDSGestureArray = [NSMutableArray arrayWithObject:gesture];
    uint8_t *base = (uint8_t *)(__bridge void *)touch;
    CGPoint point = CGPointMake(CGRectGetMidX([[UIScreen mainScreen] bounds]), CGRectGetMaxY([[UIScreen mainScreen] bounds]) - 132.0);

    *(int64_t *)(base + 16) = phase;
    *(uint64_t *)(base + 24) = 1;
    *(uint32_t *)(base + 56) = 1;
    *(void **)(base + 64) = (__bridge void *)window;
    *(void **)(base + 72) = (__bridge void *)view;
    *(void **)(base + 80) = (__bridge void *)view;
    *(void **)(base + 88) = (__bridge void *)gDSGestureArray;
    *(double *)(base + 104) = point.x;
    *(double *)(base + 112) = point.y;
    *(double *)(base + 120) = point.x;
    *(double *)(base + 128) = point.y;
    *(double *)(base + 136) = point.x;
    *(double *)(base + 144) = point.y;
    *(double *)(base + 152) = point.x;
    *(double *)(base + 160) = point.y;
    *(double *)(base + 208) = 1.0;
    *(double *)(base + 216) = 1.0;
    *(double *)(base + 248) = [[NSDate date] timeIntervalSince1970];
    *(int64_t *)(base + 296) = 0;
}

static BOOL DSStartRecording(void) {
    NSLog(@"[DeepSeekVoiceHelper] start recording enter recording=%d gesture=%@", gDSRecording, gDSGesture);
    if (gDSRecording && gDSGesture) {
        NSLog(@"[DeepSeekVoiceHelper] already recording");
        return YES;
    }

    NSDictionary *target = DSFindTarget();
    if (!target) {
        return NO;
    }

    id touch = DSAllocInit(NSClassFromString(@"UITouch"));
    if (!touch) {
        NSLog(@"[DeepSeekVoiceHelper] UITouch alloc failed");
        return NO;
    }

    gDSWindow = target[@"window"];
    gDSHitView = target[@"hitView"];
    gDSGesture = target[@"gesture"];
    gDSTouch = touch;
    gDSTouches = [NSSet setWithObject:gDSTouch];

    DSWriteTouch(gDSTouch, gDSWindow, gDSHitView, gDSGesture, 0);
    NSLog(@"[DeepSeekVoiceHelper] call touchesBegan gesture=%@ hit=%@", NSStringFromClass([gDSGesture class]), NSStringFromClass([gDSHitView class]));
    ((void (*)(id, SEL, id, id))objc_msgSend)(gDSGesture, @selector(touchesBegan:withEvent:), gDSTouches, nil);
    gDSRecording = YES;
    DSSetPreferenceString(@"deepseekPendingAction", nil);
    NSLog(@"[DeepSeekVoiceHelper] start recording success");
    return YES;
}

static void DSStartAttempt(NSInteger attempts) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gDSStarting) {
            NSLog(@"[DeepSeekVoiceHelper] start attempt cancelled attempts=%ld", (long)attempts);
            return;
        }
        NSLog(@"[DeepSeekVoiceHelper] start attempt attemptsLeft=%ld", (long)attempts);
        if (DSStartRecording()) {
            gDSStarting = NO;
            NSLog(@"[DeepSeekVoiceHelper] start attempts finished success");
            return;
        }
        if (attempts <= 0) {
            gDSStarting = NO;
            DSSetPreferenceString(@"deepseekPendingAction", nil);
            NSLog(@"[DeepSeekVoiceHelper] start attempts exhausted");
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
            NSLog(@"[DeepSeekVoiceHelper] ignore start recording=%d starting=%d gesture=%@", gDSRecording, gDSStarting, gDSGesture);
            return;
        }
        gDSStarting = YES;
        NSLog(@"[DeepSeekVoiceHelper] start attempts begin attempts=%ld", (long)attempts);
        DSStartAttempt(attempts);
    });
}

static void DSSendOnMain(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"[DeepSeekVoiceHelper] send enter gesture=%@ recording=%d", gDSGesture, gDSRecording);
        if (!gDSGesture) {
            gDSRecording = NO;
            DSSetPreferenceString(@"deepseekPendingAction", nil);
            NSLog(@"[DeepSeekVoiceHelper] send no gesture");
            return;
        }

        SEL setStateSelector = @selector(setState:);
        SEL privateSetStateSelector = NSSelectorFromString(@"_setState:");
        if ([gDSGesture respondsToSelector:setStateSelector]) {
            NSLog(@"[DeepSeekVoiceHelper] send setState:3");
            ((void (*)(id, SEL, NSInteger))objc_msgSend)(gDSGesture, setStateSelector, 3);
        } else if ([gDSGesture respondsToSelector:privateSetStateSelector]) {
            NSLog(@"[DeepSeekVoiceHelper] send _setState:3");
            ((void (*)(id, SEL, NSInteger))objc_msgSend)(gDSGesture, privateSetStateSelector, 3);
        } else {
            NSLog(@"[DeepSeekVoiceHelper] send selector missing gesture=%@", NSStringFromClass([gDSGesture class]));
        }

        gDSRecording = NO;
        gDSGesture = nil;
        gDSTouch = nil;
        gDSTouches = nil;
        gDSHitView = nil;
        gDSWindow = nil;
        gDSGestureArray = nil;
        DSSetPreferenceString(@"deepseekPendingAction", nil);
        NSLog(@"[DeepSeekVoiceHelper] send done");
    });
}

static void DSStartCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NSLog(@"[DeepSeekVoiceHelper] start notification received");
    DSStartWithAttempts(8);
}

static void DSStopSendCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NSLog(@"[DeepSeekVoiceHelper] send notification received");
    gDSStarting = NO;
    DSSetPreferenceString(@"deepseekPendingAction", nil);
    DSSendOnMain();
}

%ctor {
    NSLog(@"[DeepSeekVoiceHelper] loaded");
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, DSStartCallback, (__bridge CFStringRef)kDSStartNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, DSStopSendCallback, (__bridge CFStringRef)kDSStopSendNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}
