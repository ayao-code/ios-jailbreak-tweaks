#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <stdint.h>

static UIWindow *gDBWindow = nil;
static UIView *gDBVoiceView = nil;
static UIView *gDBHitView = nil;
static id gDBGesture = nil;
static id gDBTouch = nil;
static NSSet *gDBTouches = nil;
static NSMutableArray *gDBGestureArray = nil;
static BOOL gDBRecording = NO;
static BOOL gDBStarting = NO;
static BOOL gDBRequestedVoiceMode = NO;
static NSUInteger gDBSessionGeneration = 0;

static NSString * const kDBStartNotification = @"ayao.aipowerbutton.doubao.start";
static NSString * const kDBStopSendNotification = @"ayao.aipowerbutton.doubao.stopSend";

static id DBAllocInit(Class cls) {
    if (!cls) {
        return nil;
    }
    id object = ((id (*)(id, SEL))objc_msgSend)(cls, @selector(alloc));
    return ((id (*)(id, SEL))objc_msgSend)(object, @selector(init));
}

static BOOL DBViewIsVisible(UIView *view) {
    return view && view.window && !view.hidden && view.alpha > 0.01 && !CGRectIsEmpty(view.bounds);
}

static UIView *DBFindViewOfClass(UIView *view, Class targetClass) {
    if (!view || view.hidden || view.alpha <= 0.01) {
        return nil;
    }
    if (targetClass && [view isKindOfClass:targetClass]) {
        return view;
    }
    for (UIView *subview in [view.subviews reverseObjectEnumerator]) {
        UIView *match = DBFindViewOfClass(subview, targetClass);
        if (match) {
            return match;
        }
    }
    return nil;
}

static UIView *DBFindVoiceView(UIView *view, Class voiceViewClass) {
    if (!view || view.hidden || view.alpha <= 0.01) {
        return nil;
    }
    NSString *className = NSStringFromClass(view.class);
    if ((voiceViewClass && [view isKindOfClass:voiceViewClass]) || [className containsString:@"BasicInputVoiceView"]) {
        return view;
    }
    for (UIView *subview in [view.subviews reverseObjectEnumerator]) {
        UIView *match = DBFindVoiceView(subview, voiceViewClass);
        if (match) {
            return match;
        }
    }
    return nil;
}

static id DBObjectIvar(id object, const char *name) {
    if (!object) {
        return nil;
    }
    Ivar ivar = class_getInstanceVariable([object class], name);
    return ivar ? object_getIvar(object, ivar) : nil;
}

static BOOL DBRequestVoiceMode(UIWindow *window) {
    if (gDBRequestedVoiceMode) {
        return NO;
    }
    UIView *basicInputView = DBFindViewOfClass(window, NSClassFromString(@"_TtC14FlowInputBizUI14BasicInputView"));
    id voiceButton = DBObjectIvar(basicInputView, "_voiceButton");
    if (![voiceButton isKindOfClass:UIControl.class]) {
        voiceButton = DBObjectIvar(basicInputView, "voiceButton");
    }
    if (![voiceButton isKindOfClass:UIControl.class]) {
        return NO;
    }
    gDBRequestedVoiceMode = YES;
    [(UIControl *)voiceButton sendActionsForControlEvents:UIControlEventTouchUpInside];
    return YES;
}

static id DBFindVoiceGesture(UIView *voiceView) {
    SEL voiceGestureSelector = NSSelectorFromString(@"voiceInputGesture");
    if ([voiceView respondsToSelector:voiceGestureSelector]) {
        id gesture = ((id (*)(id, SEL))objc_msgSend)(voiceView, voiceGestureSelector);
        if ([gesture isKindOfClass:UIGestureRecognizer.class]) {
            return gesture;
        }
    }

    NSMutableArray<UIView *> *views = [NSMutableArray arrayWithObject:voiceView];
    while (views.count > 0) {
        UIView *candidate = views.lastObject;
        [views removeLastObject];
        for (UIGestureRecognizer *gesture in candidate.gestureRecognizers) {
            NSString *className = NSStringFromClass(gesture.class);
            if ([gesture isKindOfClass:UILongPressGestureRecognizer.class] || [className containsString:@"VoiceLongPressGestureRecognizer"]) {
                return gesture;
            }
        }
        [views addObjectsFromArray:candidate.subviews];
    }
    return nil;
}

static NSDictionary *DBFindTarget(void) {
    UIApplication *application = UIApplication.sharedApplication;
    SEL windowsSelector = @selector(windows);
    NSArray *windows = [application respondsToSelector:windowsSelector] ? ((id (*)(id, SEL))objc_msgSend)(application, windowsSelector) : nil;
    Class voiceViewClass = NSClassFromString(@"_TtC19FlowVoiceInputBizUI19BasicInputVoiceView");

    for (UIWindow *window in [windows reverseObjectEnumerator]) {
        if (window.hidden || window.alpha <= 0.01) {
            continue;
        }
        UIView *voiceView = DBFindVoiceView(window, voiceViewClass);
        if (!DBViewIsVisible(voiceView)) {
            UIView *basicInputView = DBFindViewOfClass(window, NSClassFromString(@"_TtC14FlowInputBizUI14BasicInputView"));
            UIView *storedVoiceView = DBObjectIvar(basicInputView, "voiceInputView");
            if (DBViewIsVisible(storedVoiceView)) {
                voiceView = storedVoiceView;
            }
        }
        if (!DBViewIsVisible(voiceView)) {
            DBRequestVoiceMode(window);
            continue;
        }

        id gesture = DBFindVoiceGesture(voiceView);
        if (!gesture) {
            continue;
        }
        CGPoint point = [voiceView convertPoint:CGPointMake(CGRectGetMidX(voiceView.bounds), CGRectGetMidY(voiceView.bounds)) toView:window];
        UIView *hitView = [window hitTest:point withEvent:nil] ?: voiceView;
        return @{
            @"window": window,
            @"voiceView": voiceView,
            @"hitView": hitView,
            @"gesture": gesture,
            @"point": [NSValue valueWithCGPoint:point]
        };
    }
    return nil;
}

static void DBWriteTouch(id touch, UIWindow *window, UIView *view, id gesture, CGPoint point, NSInteger phase) {
    gDBGestureArray = [NSMutableArray arrayWithObject:gesture];
    uint8_t *base = (uint8_t *)(__bridge void *)touch;

    *(int64_t *)(base + 16) = phase;
    *(uint64_t *)(base + 24) = 1;
    *(uint32_t *)(base + 56) = 1;
    *(void **)(base + 64) = (__bridge void *)window;
    *(void **)(base + 72) = (__bridge void *)view;
    *(void **)(base + 80) = (__bridge void *)view;
    *(void **)(base + 88) = (__bridge void *)gDBGestureArray;
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

static void DBClearRecordingState(void) {
    gDBRecording = NO;
    gDBGesture = nil;
    gDBTouch = nil;
    gDBTouches = nil;
    gDBHitView = nil;
    gDBVoiceView = nil;
    gDBWindow = nil;
    gDBGestureArray = nil;
    gDBRequestedVoiceMode = NO;
}

static void DBFinishRecording(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        gDBStarting = NO;
        gDBSessionGeneration++;
        if (!gDBGesture) {
            DBClearRecordingState();
            return;
        }
        if (gDBTouch && gDBTouches) {
            CGPoint point = [gDBVoiceView convertPoint:CGPointMake(CGRectGetMidX(gDBVoiceView.bounds), CGRectGetMidY(gDBVoiceView.bounds)) toView:gDBWindow];
            DBWriteTouch(gDBTouch, gDBWindow, gDBHitView, gDBGesture, point, 3);
            if ([gDBGesture respondsToSelector:@selector(touchesEnded:withEvent:)]) {
                ((void (*)(id, SEL, id, id))objc_msgSend)(gDBGesture, @selector(touchesEnded:withEvent:), gDBTouches, nil);
            }
        }
        NSInteger state = [gDBGesture respondsToSelector:@selector(state)] ? ((NSInteger (*)(id, SEL))objc_msgSend)(gDBGesture, @selector(state)) : 0;
        if (state != UIGestureRecognizerStateEnded && [gDBGesture respondsToSelector:@selector(setState:)]) {
            ((void (*)(id, SEL, NSInteger))objc_msgSend)(gDBGesture, @selector(setState:), UIGestureRecognizerStateEnded);
        }
        DBClearRecordingState();
    });
}

static BOOL DBStartRecording(void) {
    if (gDBRecording && gDBGesture) {
        return YES;
    }
    NSDictionary *target = DBFindTarget();
    if (!target) {
        return NO;
    }

    gDBWindow = target[@"window"];
    gDBVoiceView = target[@"voiceView"];
    gDBHitView = target[@"hitView"];
    gDBGesture = target[@"gesture"];
    gDBTouch = DBAllocInit(NSClassFromString(@"UITouch"));
    if (!gDBTouch || ![gDBGesture respondsToSelector:@selector(touchesBegan:withEvent:)]) {
        DBClearRecordingState();
        return NO;
    }
    gDBTouches = [NSSet setWithObject:gDBTouch];
    DBWriteTouch(gDBTouch, gDBWindow, gDBHitView, gDBGesture, [target[@"point"] CGPointValue], 0);
    ((void (*)(id, SEL, id, id))objc_msgSend)(gDBGesture, @selector(touchesBegan:withEvent:), gDBTouches, nil);
    gDBRecording = YES;
    return YES;
}

static void DBStartAttempt(NSInteger attemptsLeft, NSUInteger generation) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gDBStarting || generation != gDBSessionGeneration) {
            return;
        }
        if (DBStartRecording() || attemptsLeft <= 0) {
            gDBStarting = NO;
            return;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            DBStartAttempt(attemptsLeft - 1, generation);
        });
    });
}

static void DBStartCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if ((gDBRecording && gDBGesture) || gDBStarting) {
            return;
        }
        gDBStarting = YES;
        gDBRequestedVoiceMode = NO;
        NSUInteger generation = ++gDBSessionGeneration;
        DBStartAttempt(16, generation);
    });
}

static void DBStopSendCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    DBFinishRecording();
}

%ctor {
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, DBStartCallback, (__bridge CFStringRef)kDBStartNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, DBStopSendCallback, (__bridge CFStringRef)kDBStopSendNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}
