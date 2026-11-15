#import "SIController.h"
#import "SIItemViews.h"
#import "SISettingsStore.h"
#import "SIFocusMonitor.h"
#import "Shared/SIPresentation.h"
#import "Shared/SIRate.h"
#import "Shared/SINetworkSample.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <notify.h>
#import <roothide.h>
#include <stdio.h>
#include <stdatomic.h>

static const CGFloat SIGeometryEpsilon = 0.5;
static const NSUInteger SIMaxDiscoveryViews = 512;
static CFStringRef const SIMutePreferencesDomain = CFSTR("ayao.lockaudioprofiles");
static CFStringRef const SIMutePreferenceKey = CFSTR("totalSilenceEnabled");
static const char *SIMutePreferencesChangedNotification = "ayao.lockaudioprofiles/preferences.changed";
static BOOL SITotalSilenceEnabled(void) {
    CFPreferencesAppSynchronize(SIMutePreferencesDomain);
    CFPropertyListRef value=CFPreferencesCopyAppValue(SIMutePreferenceKey, SIMutePreferencesDomain);
    BOOL enabled=value ? [(__bridge id)value boolValue] : NO;
    if (value) CFRelease(value);
    return enabled;
}

// SpringBoard owns the status-bar scene while the foreground App is active.
// On iOS 16 that scene is commonly ForegroundInactive, so treating only
// ForegroundActive as visible makes every normal App look like a hidden bar.

static UIWindow *SIStatusWindowForHost(UIView *host) {
    UIWindow *window = host.window;
    if (!window || window.screen != UIScreen.mainScreen) return nil;
    NSString *name = NSStringFromClass(window.class);
    if ([name containsString:@"ControlCenter"] || [name containsString:@"ReusePool"]) return nil;
    return window;
}
static BOOL SIWindowVisible(UIWindow *window) {
    if (!window || window.screen != UIScreen.mainScreen || window.hidden || window.alpha < .99
        || CGRectIsEmpty(window.bounds)) return NO;
    if (!window.windowScene) return NO;
    UISceneActivationState activationState = window.windowScene.activationState;
    if (activationState == UISceneActivationStateUnattached || activationState == UISceneActivationStateBackground) return NO;
    if (activationState != UISceneActivationStateForegroundActive
        && activationState != UISceneActivationStateForegroundInactive) return NO;
    BOOL homeScreenVisible = NO, coverSheetVisible = NO;
    for (UIWindow *candidate in window.windowScene.windows) {
        if (candidate == window || candidate.hidden || candidate.alpha <= .01) continue;
        NSString *name = NSStringFromClass(candidate.class);
        if ([name containsString:@"SBHomeScreenWindow"]) homeScreenVisible = YES;
        if ([name containsString:@"ControlCenter"] || [name containsString:@"NotificationCenter"])
            return NO;
        // CoverSheetWindow is kept visible by SpringBoard on the Home Screen
        // even when it is not presenting the lock screen.  Treating its mere
        // existence as an occluder hid the overlay only on the desktop.
        if ([name containsString:@"CoverSheet"]) coverSheetVisible = YES;
    }
    if (coverSheetVisible && !homeScreenVisible) return NO;
    return YES;
}
static BOOL SIHostVisible(UIView *host) {
    UIWindow *window = SIStatusWindowForHost(host);
    if (!SIWindowVisible(window) || CGRectIsEmpty(host.bounds)) return NO;
    for (UIView *view = host; view; view = view.superview) {
        NSString *name=NSStringFromClass(view.class);
        if ([name containsString:@"ControlCenter"] || [name containsString:@"ReusePool"]) return NO;
        if (view.hidden || view.alpha < .99) return NO;
    }
    CGRect rect = [host convertRect:host.bounds toView:window];
    return CGRectIntersectsRect(window.bounds, rect);
}
// SpringBoard's scene can remain portrait while an App's hosted content is
// landscape. Only the observed live transformed host is used as a fallback.
static BOOL SIReadManagerFlag(NSString *className, NSString *factoryName, NSString *flagName, BOOL *value) {
    Class cls=NSClassFromString(className); SEL factory=NSSelectorFromString(factoryName);
    if (![cls respondsToSelector:factory]) return NO;
    id manager=((id(*)(id,SEL))objc_msgSend)(cls,factory);
    SEL getter=NSSelectorFromString(flagName); NSMethodSignature *sig=[manager methodSignatureForSelector:getter];
    if (sig.numberOfArguments!=2 || (strcmp(sig.methodReturnType,"B") && strcmp(sig.methodReturnType,"c"))) return NO;
    *value=((BOOL(*)(id,SEL))objc_msgSend)(manager,getter); return YES;
}
static BOOL SILandscapeSystemAllowsOverlay(void) {
    BOOL locked=YES, switcher=YES, controlCenter=YES;
    return SIReadManagerFlag(@"SBLockScreenManager",@"sharedInstance",@"isUILocked",&locked) && !locked
        && SIReadManagerFlag(@"SBMainSwitcherControllerCoordinator",@"sharedInstanceIfExists",@"isAnySwitcherVisible",&switcher) && !switcher
        && SIReadManagerFlag(@"SBControlCenterController",@"sharedInstanceIfExists",@"isPresentedOrDismissing",&controlCenter) && !controlCenter;
}
static UIView *SILandscapeContainerForHost(UIView *host) {
    UIWindow *window=SIStatusWindowForHost(host);
    if (!SIWindowVisible(window)) return nil;
    UIView *container=nil;
    for (UIView *view=host.superview;view && view!=window;view=view.superview) {
        NSString *name=NSStringFromClass(view.class);
        // The zero-height status-bar wrapper itself is intentionally ignored.
        if ([name isEqualToString:@"UIStatusBar_Modern"]) continue;
        if (view.hidden || view.alpha<.99 || [name containsString:@"ControlCenter"] || [name containsString:@"ReusePool"]) return nil;
        if (!container && [name isEqualToString:@"SBFTouchPassThroughView"] &&
            view.bounds.size.width>view.bounds.size.height && view.bounds.size.height>100) container=view;
    }
    // Ordinary portrait hosts must not query three private managers on every
    // layout or numeric sample. Gate IPC is needed only for a landscape host.
    if (!container || !SILandscapeSystemAllowsOverlay()) return nil;
    CGRect projected=[container convertRect:container.bounds toView:window];
    CGRect visible=CGRectIntersection(projected,window.bounds);
    // Reject off-screen/partially exposed app-switcher pages and transitions.
    if (CGRectIsEmpty(visible) || visible.size.width+1<projected.size.width || visible.size.height+1<projected.size.height) return nil;
    return container;
}
static BOOL SIIsStatusBarHost(UIView *view, Class legacyClass, Class modernClass) {
    if (!view) return NO;
    if (legacyClass && [view isKindOfClass:legacyClass]) return YES;
    // On the Home Screen iOS 16 can expose the status bar through the modern
    // wrapper while the legacy _UIStatusBar child is not present in the
    // traversed window.  Treat the wrapper as a host fallback; App scenes
    // still prefer the legacy host when both exist.
    return modernClass && [view isKindOfClass:modernClass];
}
static UIWindow *SIOverlayWindow(UIWindow *reference) {
    UIWindowScene *scene = reference.windowScene;
    if (!scene) return nil;
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:scene];
    window.frame = scene.coordinateSpace.bounds;
    window.windowLevel = UIWindowLevelStatusBar + 1.0;
    window.backgroundColor = UIColor.clearColor;
    window.opaque = NO;
    window.userInteractionEnabled = NO;
    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = UIColor.clearColor;
    root.view.userInteractionEnabled = NO;
    window.rootViewController = root;
    window.hidden = YES;
    return window;
}
static UIView *SIOverlayContainer(UIView *window, CGRect frame) {
    if (!window || CGRectIsEmpty(frame)) return nil;
    UIView *container = [window viewWithTag:0x4159414F];
    if (!container) {
        container = [[UIView alloc] initWithFrame:frame];
        container.tag = 0x4159414F;
        container.userInteractionEnabled = NO;
        container.isAccessibilityElement = NO;
        container.backgroundColor = UIColor.clearColor;
        container.autoresizingMask = UIViewAutoresizingNone;
        container.clipsToBounds = NO;
        [window addSubview:container];
    }
    container.frame = frame;
    return container;
}
static BOOL SIGeometryEqual(CGRect a, CGRect b) {
    return fabs(a.origin.x-b.origin.x) <= SIGeometryEpsilon
        && fabs(a.origin.y-b.origin.y) <= SIGeometryEpsilon
        && fabs(a.size.width-b.size.width) <= SIGeometryEpsilon
        && fabs(a.size.height-b.size.height) <= SIGeometryEpsilon;
}

static UIColor *SINativeStatusBarColor(UIView *host) {
    if (!host) return nil;
    @try {
        id foreground = [host valueForKey:@"foregroundColor"];
        if ([foreground isKindOfClass:UIColor.class]
            && CGColorGetAlpha(((UIColor *)foreground).CGColor) >= .5)
            return foreground;
    } @catch (NSException *exception) {}
    return nil;
}
static id SICurrentData(UIView *host) {
    @try {
        SEL selector = NSSelectorFromString(@"currentData");
        if (![host respondsToSelector:selector]) return nil;
        NSMethodSignature *signature = [host methodSignatureForSelector:selector];
        if (!signature || signature.numberOfArguments != 2 || signature.methodReturnType[0] != '@') return nil;
        return ((id (*)(id, SEL))objc_msgSend)(host, selector);
    } @catch (NSException *exception) { return nil; }
}

static NSString *const SIDomain = @"ayao.statusindicators";
static NSDictionary *SIPreferenceSnapshot;
static id SIPreference(NSString *key) {
    if (SIPreferenceSnapshot) return SIPreferenceSnapshot[key];
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)SIDomain));
}
static void SIDiagnostic(NSDictionary *details) {
#if SI_DIAGNOSTICS
    static unsigned count;
    if (count++ >= 24 || !NSThread.isMainThread) return;
    NSData *data = [NSJSONSerialization dataWithJSONObject:details options:0 error:NULL];
    if (data.length > 4096) return;
    FILE *file = fopen(jbroot(@"/var/mobile/Documents/status-indicators-test4.jsonl").fileSystemRepresentation, "a");
    if (!file) return;
    if (!fseek(file,0,SEEK_END) && ftell(file) < 28*1024) {
        fwrite(data.bytes,1,data.length,file); fputc('\n',file);
    }
    fclose(file);
#else
    (void)details;
#endif
}
static BOOL SIBool(NSString *key, BOOL fallback) {
    id v = SIPreference(key); return [v isKindOfClass:NSNumber.class] ? [v boolValue] : fallback;
}
static double SINumber(NSString *key, double fallback, double low, double high) {
    id v = SIPreference(key); double n = [v respondsToSelector:@selector(doubleValue)] ? [v doubleValue] : fallback;
    return isfinite(n) ? MIN(high, MAX(low, n)) : fallback;
}
static NSNumber *SIEnabledEntry(id data, NSString *key) {
    // Capability/KVC boundaries fail unknown, not "VPN connected".
    @try {
        id entry = [data valueForKey:key];
        if (!entry) return nil;
        id value = nil;
        if ([entry respondsToSelector:NSSelectorFromString(@"enabled")]) value = [entry valueForKey:@"enabled"];
        if (![value isKindOfClass:NSNumber.class] && [entry respondsToSelector:NSSelectorFromString(@"isEnabled")]) value = [entry valueForKey:@"isEnabled"];
        if (![value isKindOfClass:NSNumber.class] && [entry respondsToSelector:NSSelectorFromString(@"active")]) value = [entry valueForKey:@"active"];
        return [value isKindOfClass:NSNumber.class] ? value : nil;
    } @catch (NSException *exception) { return nil; }
}
@implementation SIController {
    __weak UIView *_activeHost;
    __weak UIWindow *_activeWindow;
    UIWindow *_overlayWindow;
    __weak UIView *_landscapeContainer;
    BOOL _landscapeFallback;
    UIView *_overlay;
    SIItemViews *_items;
    NSMapTable<UIView *, NSNumber *> *_hostStates;
    NSHashTable<UIView *> *_knownHosts;
    CGRect _lastGeometry;
    BOOL _hasLastGeometry;
    NSUInteger _stableGeometryPasses;
    CGRect _fixedAnchor;
    BOOL _hasFixedAnchor;
    UIInterfaceOrientation _fixedAnchorOrientation;
    BOOL _layoutPending;
    BOOL _stabilityCheckPending;
    BOOL _stabilityCheckAttempted;
    BOOL _visible, _refreshing;
    BOOL _deferredHostReadPending;
    NSHashTable<UIView *> *_dirtyHosts;
    SIFocusMonitor *_focusMonitor;
    BOOL _focusKnown;
    dispatch_queue_t _sampleQueue;
    dispatch_source_t _timer;
    SIRateState _rateState;
    uint64_t _samplingGeneration;
    int _blankToken, _prefsToken, _mutePrefsToken;
    BOOL _enabled, _speed, _vpn, _showMute, _muteEnabled, _showFocus, _screenOn;
    NSInteger _focusStyle;
    BOOL _started;
    double _interval;
    NSDictionary *_settings;
    SIRate _currentRate;
    UIColor *_nativeStatusColor;
    NSArray *_observers;
    atomic_bool _deliveryPending;
    atomic_bool _samplingActive;
    atomic_uint_fast64_t _sampleEpoch;
}
- (instancetype)init {
    if ((self = [super init])) {
        _hostStates = [NSMapTable weakToStrongObjectsMapTable];
        _knownHosts = [NSHashTable weakObjectsHashTable];
        _dirtyHosts = [NSHashTable weakObjectsHashTable];
        _focusStyle = -1;
        atomic_init(&_deliveryPending, false); atomic_init(&_samplingActive, false);
        atomic_init(&_sampleEpoch, 0);
    }
    return self;
}
+ (instancetype)shared {
    static SIController *controller; static dispatch_once_t once;
    dispatch_once(&once, ^{ controller = [SIController new]; }); return controller;
}
- (void)start {
    if (_started || !NSThread.isMainThread) return;
    _started = YES; _blankToken = _prefsToken = _mutePrefsToken = -1;
    _sampleQueue = dispatch_queue_create("ayao.statusindicators.sample", DISPATCH_QUEUE_SERIAL);
    dispatch_set_target_queue(_sampleQueue, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    __weak SIController *weakSelf = self;
    notify_register_dispatch("com.apple.springboard.hasBlankedScreen", &_blankToken, dispatch_get_main_queue(), ^(int token) {
        [weakSelf refreshVisibility];
    });
    notify_register_dispatch("ayao.statusindicators/preferences.changed", &_prefsToken, dispatch_get_main_queue(), ^(int token) {
        [weakSelf reloadPreferences];
    });
    notify_register_dispatch(SIMutePreferencesChangedNotification, &_mutePrefsToken, dispatch_get_main_queue(), ^(int token) {
        SIController *owner=weakSelf;
        if (!owner) return;
        owner->_muteEnabled=SITotalSilenceEnabled();
        [owner requestLayout];
    });
    _focusMonitor = [[SIFocusMonitor alloc] initWithHandler:^(SIFocusSnapshot snapshot) {
        SIController *owner = weakSelf;
        if (!owner || !owner->_enabled || !owner->_showFocus) return;
        owner->_focusKnown = snapshot.known;
        owner->_focusStyle = snapshot.style;
        // Focus changes affect only content/group membership, never visibility or sampling.
        [owner render];
    }];
    NSMutableArray *observers = [NSMutableArray array];
    for (NSString *name in @[UISceneDidActivateNotification, UISceneWillDeactivateNotification]) {
        [observers addObject:[NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            [weakSelf requestLayout];
        }]];
    }
    [observers addObject:[NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidReceiveMemoryWarningNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        SIController *owner = weakSelf;
        if (owner && (!owner->_enabled || !owner->_screenOn)) [owner detachLabels];
    }]];
    _observers = observers;
#if SI_DIAGNOSTICS
    int diagnosticToken;
    notify_register_dispatch("ayao.statusindicators.diagnostic", &diagnosticToken, dispatch_get_main_queue(), ^(int token) {
        [weakSelf writeDiagnosticSnapshot];
    });
#endif
    [self reloadPreferences];
}
- (void)writeDiagnosticSnapshot {
#if SI_DIAGNOSTICS
    if (!NSThread.isMainThread) return;
    NSMutableArray *windows=[NSMutableArray array], *hosts=[NSMutableArray array];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (windows.count>=40) break;
            [windows addObject:@{@"class":NSStringFromClass(window.class),@"hidden":@(window.hidden),@"alpha":@(window.alpha),
                @"level":@(window.windowLevel),@"bounds":NSStringFromCGRect(window.bounds),
                @"orientation":@(window.windowScene.interfaceOrientation),@"scene":@(scene.activationState)}];
        }
    }
    UIView *host = _activeHost;
    if (host) {
        NSMutableArray *chain=[NSMutableArray array];
        for (UIView *v=host;v && chain.count<10;v=v.superview)
            [chain addObject:@{@"class":NSStringFromClass(v.class),@"hidden":@(v.hidden),@"alpha":@(v.alpha),@"frame":NSStringFromCGRect(v.frame)}];
        [hosts addObject:@{@"class":NSStringFromClass(host.class),@"visible":@(SIHostVisible(host)),@"chain":chain,
            @"window":host.window ? NSStringFromClass(host.window.class) : @"absent",
            @"windowBounds":_activeWindow ? NSStringFromCGRect(_activeWindow.bounds) : @"absent",
            @"geometry":_activeWindow ? NSStringFromCGRect([host convertRect:host.bounds toView:_activeWindow]) : @"absent",
            @"dataClass":SICurrentData(host) ? NSStringFromClass([SICurrentData(host) class]) : @"absent"}];
    }
    // Inspect remembered status-bar hosts even when visibility filters reject
    // them. This is bounded and runs only after the diagnostic notification.
    NSMutableArray *knownHosts=[NSMutableArray array];
    for (UIView *candidate in _knownHosts.allObjects) {
        if (knownHosts.count>=20) break;
        NSMutableArray *chain=[NSMutableArray array];
        for (UIView *v=candidate;v && chain.count<10;v=v.superview)
            [chain addObject:@{@"class":NSStringFromClass(v.class),@"hidden":@(v.hidden),
                @"alpha":@(v.alpha),@"bounds":NSStringFromCGRect(v.bounds),@"frame":NSStringFromCGRect(v.frame),
                @"clips":@(v.clipsToBounds)}];
        UIView *landscapeContainer=nil;
        for (UIView *ancestor=candidate.superview;ancestor && ancestor!=candidate.window;ancestor=ancestor.superview)
            if ([NSStringFromClass(ancestor.class) isEqualToString:@"SBFTouchPassThroughView"]) { landscapeContainer=ancestor; break; }
        [knownHosts addObject:@{@"visible":@(SIHostVisible(candidate)),@"chain":chain,
            @"orientation":@(candidate.window.windowScene.interfaceOrientation),
            @"window":candidate.window ? NSStringFromClass(candidate.window.class) : @"absent",
            @"landscapeProjection":landscapeContainer && candidate.window ?
                NSStringFromCGRect([landscapeContainer convertRect:landscapeContainer.bounds toView:candidate.window]) : @"absent",
            @"fallbackEligible":@(SILandscapeContainerForHost(candidate)!=nil)}];
    }
    NSMutableDictionary *itemFrames=[NSMutableDictionary dictionary];
    if (_items) for (NSString *item in @[@"vpn",@"mute",@"focus",@"speed"])
        itemFrames[item]=NSStringFromCGRect([_items frameForItem:item]);
    NSDictionary *snapshot=@{@"windows":windows,@"hosts":hosts,@"enabled":@(_enabled),@"screenOn":@(_screenOn),
        @"visible":@(_visible),@"timer":@(_timer!=nil),@"rateValid":@(_currentRate.valid)};
    NSMutableDictionary *details=[snapshot mutableCopy];
    details[@"settings"]=_settings ?: @{};
    details[@"knownHosts"]=knownHosts;
    details[@"itemFrames"]=itemFrames;
    details[@"fixedAnchor"]=NSStringFromCGRect(_fixedAnchor);
    details[@"fixedAnchorOrientation"]=@(_fixedAnchorOrientation);
    details[@"overlayFrame"]=_overlay ? NSStringFromCGRect(_overlay.frame) : @"absent";
    details[@"overlayBounds"]=_overlay ? NSStringFromCGRect(_overlay.bounds) : @"absent";
    details[@"overlayWindowBounds"]=_overlayWindow ? NSStringFromCGRect(_overlayWindow.bounds) : @"absent";
    details[@"stableGeometryPasses"]=@(_stableGeometryPasses);
    NSMutableDictionary *visibilityGates=[NSMutableDictionary dictionary];
    for (NSArray *spec in @[@[@"SBLockScreenManager",@"sharedInstance",@"isUILocked"],
                           @[@"SBMainSwitcherControllerCoordinator",@"sharedInstanceIfExists",@"isAnySwitcherVisible"],
                           @[@"SBControlCenterController",@"sharedInstanceIfExists",@"isVisible"]]) {
        Class cls=NSClassFromString(spec[0]); SEL factory=NSSelectorFromString(spec[1]);
        if (![cls respondsToSelector:factory]) { visibilityGates[spec[0]]=@"factory unavailable"; continue; }
        id object=((id(*)(id,SEL))objc_msgSend)(cls,factory);
        SEL getter=NSSelectorFromString(spec[2]); NSMethodSignature *sig=[object methodSignatureForSelector:getter];
        if (sig.numberOfArguments==2 && (!strcmp(sig.methodReturnType,"B") || !strcmp(sig.methodReturnType,"c")))
            visibilityGates[spec[0]]=@(((BOOL(*)(id,SEL))objc_msgSend)(object,getter));
        else visibilityGates[spec[0]]=@"getter unavailable";
    }
    details[@"visibilityGates"]=visibilityGates;
    details[@"landscapeFallback"]=@(_landscapeFallback);
    BOOL landscape=_landscapeFallback || UIInterfaceOrientationIsLandscape(_fixedAnchorOrientation);
    UIColor *effectiveColor=SIColorForOrientation(_settings,_nativeStatusColor ?: UIColor.labelColor,landscape);
    CGFloat red=0,green=0,blue=0,alpha=0;
    if ([effectiveColor getRed:&red green:&green blue:&blue alpha:&alpha])
        details[@"effectiveColor"]=@{@"landscape":@(landscape),@"red":@(red),@"green":@(green),@"blue":@(blue),@"alpha":@(alpha)};
    Class cc=NSClassFromString(@"SBControlCenterController");
    SEL shared=NSSelectorFromString(@"sharedInstanceIfExists");
    if ([cc respondsToSelector:shared]) {
        id object=((id(*)(id,SEL))objc_msgSend)(cc,shared);
        NSMutableDictionary *states=[NSMutableDictionary dictionary];
        for(NSString *key in @[@"isVisible",@"isPresented",@"isPresentedOrDismissing"]){
            SEL getter=NSSelectorFromString(key);
            NSMethodSignature *sig=[object methodSignatureForSelector:getter];
            if (sig.numberOfArguments==2 && (!strcmp(sig.methodReturnType,"B") || !strcmp(sig.methodReturnType,"c")))
                states[key]=@(((BOOL(*)(id,SEL))objc_msgSend)(object,getter));
        }
        details[@"controlCenter"]=states;
    }
    NSData *data=[NSJSONSerialization dataWithJSONObject:details options:NSJSONWritingPrettyPrinted error:NULL];
    if (data.length<=32768) [data writeToFile:jbroot(@"/var/mobile/Documents/status-indicators-test9-snapshot.json") atomically:YES];
#endif
}
- (void)reloadPreferences {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self reloadPreferences]; }); return; }
    SIPreferenceSnapshot = SIReadSettings();
    BOOL previousEnabled = _enabled;
    BOOL previousSpeed = _speed;
    double previousInterval = _interval;
    _settings = SIPreferenceSnapshot ?: @{};
    _enabled = SIBool(@"enabled", NO); _speed = SIBool(@"showSpeed", YES);
    _vpn = SIBool(@"showVPN", YES);
    _showMute = SIBool(@"showMute", NO);
    _muteEnabled = SITotalSilenceEnabled();
    _showFocus = SIBool(@"showFocus", NO);
    if (_enabled && _showFocus) [_focusMonitor start];
    else {
        [_focusMonitor stop];
        _focusKnown = NO; _focusStyle = -1;
    }
    _interval = SINumber(@"interval", 2, 1, 5);
    // Style/position changes re-render the current numeric sample without resetting
    // the timer, allocating another queue or performing another interface snapshot.
    if (previousSpeed != _speed || previousInterval != _interval) [self stopSampling];
    if (_enabled && !previousEnabled) [self requestLayout];
    [self refreshVisibility];
    SIDiagnostic(@{@"event": @"reload", @"enabled": @(_enabled), @"screenOn": @(_screenOn),
        @"hosts": @(_activeHost ? 1 : 0), @"visible": @(_visible), @"timer": @(_timer != nil),
        @"scenes": @(UIApplication.sharedApplication.connectedScenes.count)});
}
- (void)readStateForHost:(UIView *)host {
    id data = SICurrentData(host);
    NSNumber *vpn = SIEnabledEntry(data, @"vpnEntry");
    // This cache is VPN-only. Layout/lifecycle snapshots cannot change global Focus.
    unsigned bits = vpn.boolValue ? 1u : 0u;
    if ([[_hostStates objectForKey:host] unsignedIntValue] != bits || ![_hostStates objectForKey:host])
        [_hostStates setObject:@(bits) forKey:host];
}
- (void)detachLabels {
    [_items detach];
    _items = nil;
    [_overlay removeFromSuperview];
    _overlay = nil;
    _overlayWindow.hidden = YES;
    _overlayWindow = nil;
    _activeHost = nil;
    _activeWindow = nil;
    _landscapeContainer = nil;
    _landscapeFallback = NO;
    _hasLastGeometry = NO;
    _stableGeometryPasses = 0;
    _hasFixedAnchor = NO;
    _fixedAnchor = CGRectZero;
    _fixedAnchorOrientation = UIInterfaceOrientationUnknown;
}
- (UIView *)chooseActiveHost {
    UIView *best = nil;
    UIWindow *bestWindow = nil;
    Class hostClass = NSClassFromString(@"_UIStatusBar");
    Class modernClass = NSClassFromString(@"UIStatusBar_Modern");
    if (!hostClass && !modernClass) return nil;
    for (UIView *candidate in _knownHosts.allObjects) {
        if (SIIsStatusBarHost(candidate,hostClass,modernClass) && SILandscapeContainerForHost(candidate)) {
            if (!best || (hostClass && [candidate isKindOfClass:hostClass] && ![best isKindOfClass:hostClass])) best=candidate;
        }
    }
    if (best) return best;
    // Prefer hosts observed through their lifecycle hooks.  SpringBoard may
    // keep the Home Screen status bar in a reuse/special window that is not
    // discoverable from the currently visible window tree.
    for (UIView *candidate in _knownHosts.allObjects) {
        if (!SIIsStatusBarHost(candidate, hostClass, modernClass) || !SIHostVisible(candidate)) continue;
        UIWindow *window = SIStatusWindowForHost(candidate);
        BOOL preferLegacy = hostClass && [candidate isKindOfClass:hostClass]
            && (!best || ![best isKindOfClass:hostClass]);
        if (!best || preferLegacy || window.windowLevel > bestWindow.windowLevel
            || (window == _activeWindow && bestWindow != _activeWindow)) {
            best = candidate; bestWindow = window;
        }
    }
    if (best) return best;
    NSMutableArray<UIView *> *pending = [NSMutableArray array];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (SIWindowVisible(window) && pending.count < SIMaxDiscoveryViews) [pending addObject:window];
        }
    }
    NSUInteger visited = 0;
    while (pending.count && visited++ < SIMaxDiscoveryViews) {
        UIView *view = pending.lastObject; [pending removeLastObject];
        if (SIIsStatusBarHost(view, hostClass, modernClass) && SIHostVisible(view)) {
            UIWindow *window = SIStatusWindowForHost(view);
            BOOL preferLegacy = hostClass && [view isKindOfClass:hostClass]
                && (!best || ![best isKindOfClass:hostClass]);
            if (!best || preferLegacy || window.windowLevel > bestWindow.windowLevel
                || (window == _activeWindow && bestWindow != _activeWindow)) {
                best = view; bestWindow = window;
            }
            continue;
        }
        for (UIView *child in view.subviews) {
            if (pending.count + visited >= SIMaxDiscoveryViews) break;
            [pending addObject:child];
        }
    }
    return best;
}
- (void)hostDidChange:(UIView *)host readCurrentData:(BOOL)readData {
    if (!NSThread.isMainThread || !_enabled) return;
    if ((readData || ![_hostStates objectForKey:host]) && SIHostVisible(host)) [self readStateForHost:host];
    [self requestLayout];
}
- (void)hostDidUpdateData:(UIView *)host {
    if (!NSThread.isMainThread || !_enabled || !host) return;
    [_knownHosts addObject:host];
    [_dirtyHosts addObject:host];
    if (_deferredHostReadPending) return;
    _deferredHostReadPending = YES;
    __weak SIController *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        SIController *owner = weakSelf;
        if (!owner) return;
        owner->_deferredHostReadPending = NO;
        NSArray<UIView *> *hosts = owner->_dirtyHosts.allObjects;
        [owner->_dirtyHosts removeAllObjects];
        if (!owner->_enabled) return;
        // Coalesce layout, not data: consume every live host after the system commits.
        for (UIView *changedHost in hosts) {
            if (SIHostVisible(changedHost)) [owner readStateForHost:changedHost];
        }
        [owner requestLayout];
    });
}
- (void)rememberHost:(UIView *)host {
    if (!host || !NSThread.isMainThread) return;
    [_knownHosts addObject:host];
    if (_enabled) [self requestLayout];
}
- (void)requestLayout {
    if (_layoutPending || !NSThread.isMainThread) return;
    _stabilityCheckAttempted = NO;
    _layoutPending = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_layoutPending = NO;
        [self refreshVisibility];
    });
}
- (void)requestStabilityCheck {
    if (_stabilityCheckPending || _stabilityCheckAttempted || !NSThread.isMainThread) return;
    _stabilityCheckPending = YES;
    _stabilityCheckAttempted = YES;
    // One deferred confirmation closes the current layout transaction. This is
    // not a polling loop: no timer is retained and no work repeats while idle.
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_stabilityCheckPending = NO;
        // Do not rearm the one-shot from its own callback: persistent hidden
        // geometry must wait for a real lifecycle event, not spin the queue.
        [self refreshVisibility];
    });
}
- (void)refreshVisibility {
    if (!NSThread.isMainThread || _refreshing) return;
    _refreshing = YES;
    uint64_t blank = 1;
    BOOL wasOn = _screenOn;
    BOOL wasVisible = _visible;
    _screenOn = _blankToken >= 0 && notify_get_state(_blankToken, &blank) == NOTIFY_STATUS_OK && blank == 0;
    UIView *host = (_enabled && _screenOn) ? [self chooseActiveHost] : nil;
    UIWindow *window = SIStatusWindowForHost(host);
    UIView *landscapeContainer=SILandscapeContainerForHost(host);
    BOOL fallback=landscapeContainer!=nil;
    BOOL fallbackChanged=fallback!=_landscapeFallback || landscapeContainer!=_landscapeContainer;
    UIInterfaceOrientation orientation = window.windowScene
        ? window.windowScene.interfaceOrientation : UIInterfaceOrientationUnknown;
    if (fallback) orientation=UIInterfaceOrientationLandscapeLeft;
    BOOL windowChanged = window != _activeWindow;
    BOOL orientationChanged = orientation != UIInterfaceOrientationUnknown
        && orientation != _fixedAnchorOrientation;
    UIColor *observedColor = SINativeStatusBarColor(host);
    if (windowChanged || host != _activeHost) _nativeStatusColor = nil;
    if (observedColor) _nativeStatusColor = observedColor;
    else if (!_nativeStatusColor) _nativeStatusColor = UIColor.labelColor;
    if (host && ![_hostStates objectForKey:host]) [self readStateForHost:host];
    CGRect geometry = fallback ? landscapeContainer.bounds : (host ? [host convertRect:host.bounds toView:window] : CGRectZero);
    BOOL anchorChanged = windowChanged || orientationChanged || fallbackChanged || !_overlay;
    // The first stable status-bar geometry is the user's fixed anchor.  Island
    // expansion may change `geometry`, but never changes this anchor.  A new
    // status-bar window or a real orientation change starts a new anchor.
    if (anchorChanged) {
        _overlayWindow.hidden = YES;
        _overlayWindow = nil;
        _hasFixedAnchor = NO;
        _fixedAnchor = CGRectZero;
    }
    if (host && window && anchorChanged) {
        if (fallback) {
            _fixedAnchor=CGRectMake(0,0,landscapeContainer.bounds.size.width,1);
        } else {
            _overlayWindow = SIOverlayWindow(window);
            _fixedAnchor = _overlayWindow ? [host convertRect:host.bounds toView:_overlayWindow] : CGRectZero;
        }
        _hasFixedAnchor = !CGRectIsEmpty(_fixedAnchor);
        _fixedAnchorOrientation = orientation;
    }
    _landscapeContainer=landscapeContainer;
    _landscapeFallback=fallback;
    // First observation establishes a baseline; the next identical event is the stable pass.
    BOOL sameGeometry = host == _activeHost && window == _activeWindow && _hasLastGeometry && SIGeometryEqual(geometry, _lastGeometry);
    if (host != _activeHost || window != _activeWindow || !_hasLastGeometry || !sameGeometry) {
        _stableGeometryPasses = 0;
        _hasLastGeometry = host != nil;
        _lastGeometry = geometry;
        [_items hide];
    } else if (_hasLastGeometry) {
        _stableGeometryPasses = MIN(_stableGeometryPasses + 1, 2u);
    }
    if (anchorChanged) {
        [_items detach]; _items = nil;
        [_overlay removeFromSuperview]; _overlay = nil;
        _activeHost = host; _activeWindow = window;
        if (fallback && _hasFixedAnchor) _overlay=SIOverlayContainer(landscapeContainer,landscapeContainer.bounds);
        else if (host && window && _overlayWindow && _hasFixedAnchor)
            _overlay = SIOverlayContainer(_overlayWindow, _overlayWindow.bounds);
    } else {
        _activeHost = host;
    }
    if (_overlay && _hasFixedAnchor) _overlay.frame = fallback ? landscapeContainer.bounds : _fixedAnchor;
    _visible = _enabled && _screenOn && host && window
        && (fallback ? SILandscapeContainerForHost(host)==landscapeContainer : SIHostVisible(host)) && _stableGeometryPasses >= 1;
    if (_enabled && _screenOn && host && window && !_visible) [self requestStabilityCheck];
    if (!_visible) {
        [_items hide];
        _overlayWindow.hidden = YES;
        if (_timer || _currentRate.valid) [self stopSampling];
    } else {
        _overlayWindow.hidden = NO;
        if (!_items) _items = [[SIItemViews alloc] initWithHost:_overlay];
        [_items moveToContainer:_overlay];
        [self render];
        if (_speed && !_timer) [self startSampling];
        if (!_speed && _timer) [self stopSampling];
    }
    if (!_enabled) [self detachLabels];
    _refreshing = NO;
    if (wasOn != _screenOn || wasVisible != _visible)
        SIDiagnostic(@{ @"event": @"visibility", @"screenOn": @(_screenOn), @"visible": @(_visible),
            @"activeHost": _activeHost ? NSStringFromClass(_activeHost.class) : @"none",
            @"activeWindow": _activeWindow ? NSStringFromClass(_activeWindow.class) : @"none",
            @"geometry": NSStringFromCGRect(geometry), @"stablePasses": @(_stableGeometryPasses),
            @"timer": @(_timer != nil) });
}
- (void)render {
    if (!_enabled || !_screenOn || !_visible || !_activeHost || !_activeWindow || !_overlay) return;
    NSString *rate = _speed ? SISpeedText(_currentRate.download,_currentRate.upload,_currentRate.valid,SISpeedStyleFromSettings(_settings)) : @"";
    if (_landscapeFallback ? SILandscapeContainerForHost(_activeHost)!=_landscapeContainer : !SIHostVisible(_activeHost)) {
        [_items hide];
        _overlayWindow.hidden = YES;
        _visible = NO;
        [self stopSampling];
        [self requestLayout];
        return;
    }
    unsigned bits = [[_hostStates objectForKey:_activeHost] unsignedIntValue];
    BOOL vpn = _vpn && (bits & 1u);
    BOOL mute = _showMute && _muteEnabled;
    NSInteger configuredFocusStyle=(NSInteger)SINumber(@"focusStyle",0,0,5);
    NSInteger effectiveFocusStyle=configuredFocusStyle > 0 ? configuredFocusStyle-1 : _focusStyle;
    NSString *focus = (_showFocus && _focusKnown && _focusStyle >= 0 && effectiveFocusStyle >= 0)
        ? [NSString stringWithFormat:@"%ld",(long)effectiveFocusStyle] : @"";
    if (!vpn && !mute && !focus.length && !rate.length) { [_items hide]; return; }
    [_items moveToContainer:_overlay];
    // The container is anchored in window coordinates.  The host geometry is
    // used only to detect a transition and hide briefly; it never moves the
    // configured item positions. Fixed/custom modes still bypass this through
    // SIColorFromSettings.
    UIColor *color = _nativeStatusColor ?: UIColor.labelColor;
    BOOL landscape = _landscapeFallback || (_activeWindow.windowScene
        ? UIInterfaceOrientationIsLandscape(_activeWindow.windowScene.interfaceOrientation)
        : _activeWindow.bounds.size.width > _activeWindow.bounds.size.height);
    CGRect bounds = _overlay.bounds;
    if (_hasFixedAnchor) {
        CGFloat virtualExtent = 200.0;
        bounds = CGRectMake(CGRectGetMinX(_fixedAnchor), CGRectGetMidY(_fixedAnchor) - virtualExtent / 2.0,
            CGRectGetWidth(_fixedAnchor), virtualExtent);
    }
    [_items renderVPN:vpn mute:mute focus:focus focusLabel:_settings[@"focusLabel"] speed:rate speedStyle:SISpeedStyleFromSettings(_settings) color:SIColorForOrientation(_settings,color,landscape)
        bounds:bounds layout:SILayoutFromSettings(_settings,landscape) style:SIStyleFromSettings(_settings)];
}
- (void)stopSampling {
    _samplingGeneration++;
    atomic_store(&_sampleEpoch, _samplingGeneration);
    atomic_store(&_samplingActive, false);
    if (_timer) { dispatch_source_cancel(_timer); _timer = nil; }
    _currentRate = (SIRate){0};
}
- (void)startSampling {
    uint64_t generation = ++_samplingGeneration;
    atomic_store(&_sampleEpoch, generation);
    atomic_store(&_samplingActive, true);
    double interval = _interval;
    dispatch_async(_sampleQueue, ^{ memset(&self->_rateState, 0, sizeof(self->_rateState)); });
    _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _sampleQueue);
    dispatch_source_set_timer(_timer, dispatch_time(DISPATCH_TIME_NOW, 0), (uint64_t)(interval * NSEC_PER_SEC), NSEC_PER_SEC / 4);
    __weak SIController *weakSelf = self;
    dispatch_source_set_event_handler(_timer, ^{
        SIController *owner = weakSelf; if (!owner) return;
        if (!atomic_load(&owner->_samplingActive) || atomic_load(&owner->_sampleEpoch) != generation) return;
        @autoreleasepool {
            SISample samples[SI_MAX_INTERFACES] = {0}; size_t count = 0;
            BOOL valid = SIReadNetworkSamples(samples, &count);
            SIRate rate = SIUpdateRate(&owner->_rateState, samples, valid ? count : SI_MAX_INTERFACES + 1, CACurrentMediaTime());
            if (atomic_exchange(&owner->_deliveryPending, true)) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                SIController *current = weakSelf;
                if (!current) return;
                atomic_store(&current->_deliveryPending, false);
                if (current->_samplingGeneration != generation || !current->_enabled || !current->_screenOn || !current->_visible) return;
                current->_currentRate = rate; [current render];
            });
        }
    });
    dispatch_resume(_timer);
}
@end
