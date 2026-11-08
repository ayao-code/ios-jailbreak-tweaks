#import "ASGTouch.h"
#import <objc/message.h>
#import <dlfcn.h>
#import <mach/mach_time.h>
#import <objc/runtime.h>

static char ASGSyntheticKey;
BOOL ASGIsSyntheticTouch(UITouch *touch) { return [objc_getAssociatedObject(touch, &ASGSyntheticKey) boolValue]; }

// Runtime-resolved IOKit HID ABI; see Theos vendor IOHIDEvent.h prototypes.
typedef CFTypeRef (*ASGCreateHand)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t,
    uint32_t, uint32_t, double, double, double, double, double, Boolean, Boolean, uint32_t);
typedef CFTypeRef (*ASGCreateFinger)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t,
    double, double, double, double, double, Boolean, Boolean, uint32_t);
typedef void (*ASGAppendHID)(CFTypeRef, CFTypeRef, uint32_t);
typedef void (*ASGSetHIDInteger)(CFTypeRef, uint32_t, int64_t);

static BOOL ASGAttachHID(UITouch *touch, UIEvent *event, CGPoint point, BOOL down) {
    static ASGCreateHand hand;
    static ASGCreateFinger finger;
    static ASGAppendHID append;
    static ASGSetHIDInteger setInteger;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *library = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL);
        if (!library) return;
        hand = (ASGCreateHand)dlsym(library, "IOHIDEventCreateDigitizerEvent");
        finger = (ASGCreateFinger)dlsym(library, "IOHIDEventCreateDigitizerFingerEvent");
        append = (ASGAppendHID)dlsym(library, "IOHIDEventAppendEvent");
        setInteger = (ASGSetHIDInteger)dlsym(library, "IOHIDEventSetIntegerValue");
    });
    SEL eventHID = NSSelectorFromString(@"_setHIDEvent:");
    SEL touchHID = NSSelectorFromString(@"_setHidEvent:");
    if (!hand || !finger || !append || !setInteger || ![event respondsToSelector:eventHID]
        || ![touch respondsToSelector:touchHID]) return NO;
    uint64_t timestamp = mach_absolute_time();
    CFTypeRef parent = hand(kCFAllocatorDefault, timestamp, 3, 0, 0, 3, 0, 0, 0, 0, 0, 0, YES, down, 0);
    CFTypeRef child = finger(kCFAllocatorDefault, timestamp, 1, 2, 3, point.x, point.y, 0, 0, 0, YES, down, 0);
    if (!parent || !child) { if (parent) CFRelease(parent); if (child) CFRelease(child); return NO; }
    @try {
        setInteger(parent, 0xB0019, 1); // display-integrated digitizer event
        setInteger(child, 0xB0019, 1);
        append(parent, child, 0);
        ((void (*)(id, SEL, CFTypeRef))objc_msgSend)(touch, touchHID, parent);
        ((void (*)(id, SEL, CFTypeRef))objc_msgSend)(event, eventHID, parent);
    } @catch (NSException *exception) { CFRelease(child); CFRelease(parent); return NO; }
    CFRelease(child);
    CFRelease(parent);
    return YES;
}

BOOL ASGPerformLocalTap(UIView *target, UIWindow *window, void (^completion)(BOOL)) {
    CGRect rect = [target convertRect:target.bounds toView:window];
    return ASGPerformLocalTapAtPoint(target, window, CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect)), completion);
}

BOOL ASGPerformLocalTapAtPoint(UIView *target, UIWindow *window, CGPoint point, void (^completion)(BOOL)) {
    return ASGPerformGuardedTap(target, window, point, nil, completion);
}

BOOL ASGPerformGuardedTap(UIView *target, UIWindow *window, CGPoint point,
                         BOOL (^stillValid)(void), void (^completion)(BOOL)) {
    if (!NSThread.isMainThread || !target || !window || target.window != window) return NO;
    SEL location = NSSelectorFromString(@"_setLocationInWindow:resetPrevious:");
    SEL eventSelector = NSSelectorFromString(@"_touchesEvent");
    SEL clear = NSSelectorFromString(@"_clearTouches");
    SEL add = NSSelectorFromString(@"_addTouch:forDelayedDelivery:");
    UITouch *touch = [[UITouch alloc] init];
    objc_setAssociatedObject(touch, &ASGSyntheticKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (![touch respondsToSelector:location] || ![UIApplication.sharedApplication respondsToSelector:eventSelector]) return NO;
    UIView *hit = [window hitTest:point withEvent:nil];
    if (hit != target && ![hit isDescendantOfView:target]) return NO;
    // Every private operation is capability checked and exception contained.
    // Unsupported iOS versions fail without declaring success.
    @try {
        [touch setValue:window forKey:@"window"];
        [touch setValue:hit forKey:@"view"];
        [touch setValue:@1 forKey:@"tapCount"];
        [touch setValue:@(NSProcessInfo.processInfo.systemUptime) forKey:@"timestamp"];
        [touch setValue:@(UITouchPhaseBegan) forKey:@"phase"];
        ((void (*)(id, SEL, CGPoint, BOOL))objc_msgSend)(touch, location, point, YES);
        UIEvent *event = ((id (*)(id, SEL))objc_msgSend)(UIApplication.sharedApplication, eventSelector);
        if (!event || ![event respondsToSelector:clear] || ![event respondsToSelector:add]) return NO;
        ((void (*)(id, SEL))objc_msgSend)(event, clear);
        ((void (*)(id, SEL, id, BOOL))objc_msgSend)(event, add, touch, NO);
        if (!ASGAttachHID(touch, event, point, YES)) return NO;
        if (stillValid && !stillValid()) return NO;
        [UIApplication.sharedApplication sendEvent:event];
        // A touch sequence must finish even if the app changes page after Began.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 40 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            BOOL ended = NO;
            BOOL terminated = NO;
            BOOL cancelled = stillValid && !stillValid();
            @try {
                [touch setValue:@(cancelled ? UITouchPhaseCancelled : UITouchPhaseEnded) forKey:@"phase"];
                [touch setValue:@(NSProcessInfo.processInfo.systemUptime) forKey:@"timestamp"];
                UIEvent *finish = ((id (*)(id, SEL))objc_msgSend)(UIApplication.sharedApplication, eventSelector);
                if ([finish respondsToSelector:clear] && [finish respondsToSelector:add]) {
                    ((void (*)(id, SEL))objc_msgSend)(finish, clear);
                    ((void (*)(id, SEL, id, BOOL))objc_msgSend)(finish, add, touch, NO);
                    if (ASGAttachHID(touch, finish, point, NO)) {
                        [UIApplication.sharedApplication sendEvent:finish];
                        terminated = YES;
                        ended = !cancelled;
                    }
                }
            } @catch (NSException *exception) { ended = NO; }
            if (!terminated) {
                @try {
                    [touch setValue:@(UITouchPhaseCancelled) forKey:@"phase"];
                    [touch setValue:@(NSProcessInfo.processInfo.systemUptime) forKey:@"timestamp"];
                    UIEvent *cancel = ((id (*)(id, SEL))objc_msgSend)(UIApplication.sharedApplication, eventSelector);
                    if ([cancel respondsToSelector:clear] && [cancel respondsToSelector:add]) {
                        ((void (*)(id, SEL))objc_msgSend)(cancel, clear);
                        ((void (*)(id, SEL, id, BOOL))objc_msgSend)(cancel, add, touch, NO);
                        if (ASGAttachHID(touch, cancel, point, NO)) [UIApplication.sharedApplication sendEvent:cancel];
                    }
                } @catch (NSException *exception) { /* Report failure, never synthesize success. */ }
            }
            if (completion) completion(ended);
        });
        return YES;
    } @catch (NSException *exception) { return NO; }
}
