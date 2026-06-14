#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>

static BOOL XYACDebugEnabled(void) {
    return NO;
}

static void XYACLog(NSString *format, ...) {
    if (!XYACDebugEnabled()) {
        return;
    }
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"[XianYuAdCleaner] %@", message);
}

static BOOL XYACStringContainsAny(NSString *value, NSArray<NSString *> *needles) {
    if (value.length == 0) {
        return NO;
    }
    NSString *lower = value.lowercaseString;
    for (NSString *needle in needles) {
        if ([lower containsString:needle.lowercaseString]) {
            return YES;
        }
    }
    return NO;
}

static NSString *XYACClassName(id object) {
    if (!object) {
        return nil;
    }
    return NSStringFromClass([object class]);
}

static BOOL XYACIsTabOrChromeView(UIView *view) {
    NSString *className = XYACClassName(view);
    return XYACStringContainsAny(className, @[
        @"tabbar",
        @"navigationbar",
        @"statusbar",
        @"toolbar",
        @"bottombar"
    ]);
}

static BOOL XYACIsLikelyAdView(UIView *view) {
    if (!view || XYACIsTabOrChromeView(view)) {
        return NO;
    }

    NSString *className = XYACClassName(view);
    NSString *identifier = view.accessibilityIdentifier;

    if (XYACStringContainsAny(className, @[
        @"fishsplashad",
        @"fishad",
        @"splashad",
        @"splashview",
        @"mamasplash",
        @"advert",
        @"advertise",
        @"adbanner",
        @"adview",
        @"gdt",
        @"beizi",
        @"csj"
    ])) {
        return YES;
    }

    if (XYACStringContainsAny(identifier, @[
        @"splash",
        @"advert",
        @"adbanner",
        @"ad_view"
    ])) {
        return YES;
    }

    return NO;
}

static void XYACRemoveAdViewIfNeeded(UIView *view) {
    if (!XYACIsLikelyAdView(view)) {
        return;
    }
    XYACLog(@"remove ad view %@", XYACClassName(view));
    view.hidden = YES;
    view.alpha = 0.0;
    view.userInteractionEnabled = NO;
    [view removeFromSuperview];
}

static void XYACScanSubviews(UIView *root) {
    if (!root) {
        return;
    }

    NSArray<UIView *> *subviews = [root.subviews copy];
    for (UIView *subview in subviews) {
        XYACRemoveAdViewIfNeeded(subview);
        XYACScanSubviews(subview);
    }
}

static void (*orig_FMSplashModule_setSplashView)(id self, SEL _cmd, id view);
static void hooked_FMSplashModule_setSplashView(id self, SEL _cmd, id view) {
    if ([view isKindOfClass:UIView.class]) {
        XYACRemoveAdViewIfNeeded((UIView *)view);
    }
    if (orig_FMSplashModule_setSplashView) {
        orig_FMSplashModule_setSplashView(self, _cmd, nil);
    }
}

static void (*orig_FMSplashModule_voidMethod)(id self, SEL _cmd);
static void hooked_FMSplashModule_voidMethod(id self, SEL _cmd) {
    XYACLog(@"blocked %@", NSStringFromSelector(_cmd));
}

static BOOL (*orig_FMSplashModule_isADShowing)(id self, SEL _cmd);
static BOOL hooked_FMSplashModule_isADShowing(id self, SEL _cmd) {
    return NO;
}

static void (*orig_UIView_didAddSubview)(UIView *self, SEL _cmd, UIView *subview);
static void hooked_UIView_didAddSubview(UIView *self, SEL _cmd, UIView *subview) {
    if (orig_UIView_didAddSubview) {
        orig_UIView_didAddSubview(self, _cmd, subview);
    }
    XYACRemoveAdViewIfNeeded(subview);
}

static void (*orig_UIWindow_makeKeyAndVisible)(UIWindow *self, SEL _cmd);
static void hooked_UIWindow_makeKeyAndVisible(UIWindow *self, SEL _cmd) {
    if (orig_UIWindow_makeKeyAndVisible) {
        orig_UIWindow_makeKeyAndVisible(self, _cmd);
    }
    XYACScanSubviews(self);
}

static void XYACHookInstanceMethod(Class cls, SEL selector, IMP replacement, IMP *original) {
    if (!cls || !selector) {
        return;
    }
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) {
        XYACLog(@"missing method %@ on %@", NSStringFromSelector(selector), NSStringFromClass(cls));
        return;
    }
    MSHookMessageEx(cls, selector, replacement, original);
}

%ctor {
    @autoreleasepool {
        Class splashModule = objc_getClass("FMSplashModule");
        XYACHookInstanceMethod(splashModule,
                               @selector(setSplashView:),
                               (IMP)hooked_FMSplashModule_setSplashView,
                               (IMP *)&orig_FMSplashModule_setSplashView);
        XYACHookInstanceMethod(splashModule,
                               @selector(showSplashView),
                               (IMP)hooked_FMSplashModule_voidMethod,
                               (IMP *)&orig_FMSplashModule_voidMethod);
        XYACHookInstanceMethod(splashModule,
                               @selector(showFishSplashAdView),
                               (IMP)hooked_FMSplashModule_voidMethod,
                               NULL);
        XYACHookInstanceMethod(splashModule,
                               @selector(showMamaSplashView),
                               (IMP)hooked_FMSplashModule_voidMethod,
                               NULL);
        XYACHookInstanceMethod(splashModule,
                               @selector(isADShowing),
                               (IMP)hooked_FMSplashModule_isADShowing,
                               (IMP *)&orig_FMSplashModule_isADShowing);

        XYACHookInstanceMethod(UIView.class,
                               @selector(didAddSubview:),
                               (IMP)hooked_UIView_didAddSubview,
                               (IMP *)&orig_UIView_didAddSubview);
        XYACHookInstanceMethod(UIWindow.class,
                               @selector(makeKeyAndVisible),
                               (IMP)hooked_UIWindow_makeKeyAndVisible,
                               (IMP *)&orig_UIWindow_makeKeyAndVisible);
    }
}
