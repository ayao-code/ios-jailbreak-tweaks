#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import "ASGPolicy.h"
#import "ASGCache.h"
#import "ASGMatchers.h"
#import "ASGTouch.h"
#import "ASGDiagnostics.h"
#import "ASGTip.h"
#import "ASGActionIdentity.h"

static NSString *const ASGVersion = ASG_VERSION;
static BOOL ASGArmed;
static double ASGNow(void) { return CACurrentMediaTime(); }
static BOOL ASGHasWord(NSString *value, NSString *word) {
    return value.length && word.length && [value rangeOfString:word options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static BOOL ASGExcludedPage(UIViewController *vc) {
    NSString *name = NSStringFromClass(vc.class).lowercaseString;
    for (NSString *word in @[@"login", @"signin", @"permission", @"payment", @"purchase", @"onboard"]) {
        if (ASGHasWord(name, word)) return YES;
    }
    return NO;
}

static UIViewController *ASGTopController(UIViewController *root) {
    UIViewController *vc = root;
    for (NSUInteger i = 0; vc && i < 16; i++) {
        UIViewController *next = vc.presentedViewController;
        if (!next && [vc isKindOfClass:UINavigationController.class]) next = ((UINavigationController *)vc).visibleViewController;
        if (!next && [vc isKindOfClass:UITabBarController.class]) next = ((UITabBarController *)vc).selectedViewController;
        if (!next || next == vc) break;
        vc = next;
    }
    return vc;
}

static NSArray<UIWindow *> *ASGWindows(void) {
    UIWindowScene *scene = nil;
    for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
        if (candidate.activationState != UISceneActivationStateForegroundActive || ![candidate isKindOfClass:UIWindowScene.class]) continue;
        if (scene) return @[]; // Do not choose an arbitrary foreground scene.
        scene = (UIWindowScene *)candidate;
    }
    NSArray *windows = scene.windows;
    if (!scene) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        windows = UIApplication.sharedApplication.windows;
#pragma clang diagnostic pop
    }
    NSMutableArray *visible = [NSMutableArray array];
    for (UIWindow *window in windows) {
        NSString *name = NSStringFromClass(window.class);
        if (window.hidden || window.alpha <= 0.01 || CGRectIsEmpty(window.bounds)
            || ASGHasWord(name, @"keyboard") || ASGHasWord(name, @"texteffects")) continue;
        [visible addObject:window];
    }
    [visible sortUsingComparator:^NSComparisonResult(UIWindow *a, UIWindow *b) {
        if (a.windowLevel != b.windowLevel) return a.windowLevel > b.windowLevel ? NSOrderedAscending : NSOrderedDescending;
        return a.isKeyWindow == b.isKeyWindow ? NSOrderedSame : (a.isKeyWindow ? NSOrderedAscending : NSOrderedDescending);
    }];
    return visible;
}
static UIWindow *ASGWindow(void) { return ASGWindows().firstObject; }
static BOOL ASGWindowActive(UIWindow *window) { return window && [ASGWindows() containsObject:window]; }
static UIView *ASGForegroundHit(UIWindow *reference, CGPoint point) {
    for (UIWindow *window in ASGWindows()) {
        UIView *hit = [window hitTest:[window convertPoint:point fromWindow:reference] withEvent:nil];
        if (hit) return hit;
    }
    return nil;
}

static BOOL ASGVisible(UIView *view, UIWindow *window) {
    // UIWindow.window need not point to itself. Rejecting it prunes the entire search tree.
    if (!view || !window || (view != window && view.window != window) || CGRectIsEmpty(view.bounds)) return NO;
    UIView *ancestor = view;
    for (NSUInteger i = 0; ancestor && i < 32; i++, ancestor = ancestor.superview) {
        if (ancestor.hidden || ancestor.alpha <= 0.01) return NO;
    }
    CGRect rect = [view convertRect:view.bounds toView:window];
    return !CGRectIsNull(rect) && !CGRectIsInfinite(rect) && CGRectIntersectsRect(rect, window.bounds);
}

static CGRect ASGNormalizedRect(UIView *view, UIView *container) {
    CGRect rect = [view convertRect:view.bounds toView:container];
    CGRect bounds = container.bounds;
    if (bounds.size.width <= 0 || bounds.size.height <= 0) return CGRectNull;
    return CGRectMake((rect.origin.x - bounds.origin.x) / bounds.size.width,
                      (rect.origin.y - bounds.origin.y) / bounds.size.height,
                      rect.size.width / bounds.size.width, rect.size.height / bounds.size.height);
}

static NSString *ASGText(UIView *view) {
    // Do not let an empty UILabel/UIButton field mask an accessibility label.
    NSMutableArray<NSString *> *values = [NSMutableArray arrayWithCapacity:6];
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        if (label.text.length) [values addObject:label.text];
        if (label.attributedText.length) [values addObject:label.attributedText.string];
    } else if ([view isKindOfClass:UIButton.class]) {
        UIButton *button = (UIButton *)view;
        if (button.currentTitle.length) [values addObject:button.currentTitle];
        if (button.currentAttributedTitle.length) [values addObject:button.currentAttributedTitle.string];
    } else {
        for (NSString *name in @[@"text", @"attributedText"]) {
            SEL selector = NSSelectorFromString(name);
            if (![view respondsToSelector:selector]) continue;
            @try {
                id text = ((id (*)(id, SEL))objc_msgSend)(view, selector);
                if ([text isKindOfClass:NSAttributedString.class]) text = [text string];
                if ([text isKindOfClass:NSString.class] && [text length]) [values addObject:text];
            } @catch (NSException *exception) { /* Try the other independent sources. */ }
        }
    }
    if (view.accessibilityLabel.length) [values addObject:view.accessibilityLabel];
    if (view.accessibilityValue.length) [values addObject:view.accessibilityValue];
    NSMutableArray *bounded = [NSMutableArray array];
    for (NSString *value in values) if (value.length <= 512 && ![bounded containsObject:value]) [bounded addObject:value];
    return [bounded componentsJoinedByString:@" "];
}

static NSString *ASGEntryText(UIView *view) {
    NSString *own = ASGText(view);
    if (!view.subviews.count) return own; // No subtree or repeated parsing on ordinary leaf views.
    if (ASGActionForText(own) != ASGActionNone) return own;
    if (!view || view.bounds.size.width > 240 || view.bounds.size.height > 100) return own;
    NSMutableArray *parts = [NSMutableArray array];
    if (own.length && own.length <= 80) [parts addObject:own];
    NSMutableArray *queue = [NSMutableArray arrayWithArray:view.subviews];
    unsigned visited = 0;
    while (queue.count && visited++ < 12) {
        UIView *child = queue.firstObject; [queue removeObjectAtIndex:0];
        if (child.hidden || child.alpha <= .01) continue;
        NSString *text = ASGText(child);
        if (text.length && text.length <= 80 && ![parts containsObject:text]) [parts addObject:text];
        if (queue.count + child.subviews.count <= 12) [queue addObjectsFromArray:child.subviews];
    }
    NSString *combined = [parts componentsJoinedByString:@" "];
    return ASGAdCountdownText(combined) ? combined : own;
}

static BOOL ASGControlSemantic(UIView *control) {
    if (ASGActionForText(ASGText(control)) != ASGActionNone || ASGSkipIdentifier(control.accessibilityIdentifier)) return YES;
    unsigned visited = 0;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:control.subviews];
    while (queue.count && visited++ < 12) {
        UIView *view = queue.lastObject;
        [queue removeLastObject];
        if (!view.hidden && view.alpha > 0.01 && ASGActionForText(ASGText(view)) != ASGActionNone) return YES;
        if (queue.count + view.subviews.count < 16) [queue addObjectsFromArray:view.subviews];
    }
    return NO;
}

static UIView *ASGControlFromView(UIView *view, UIView *container) {
    for (unsigned i = 0; view && view != container && i < 64; i++, view = view.superview) {
        if ([view isKindOfClass:UIControl.class]) return view;
        for (UIGestureRecognizer *gesture in view.gestureRecognizers) {
            if ([gesture isKindOfClass:UITapGestureRecognizer.class] && gesture.enabled) return view;
        }
        if (view.isAccessibilityElement && (view.accessibilityTraits & UIAccessibilityTraitButton)) return view;
    }
    return nil;
}

static NSArray<NSNumber *> *ASGPath(UIView *control, UIView *container) {
    NSMutableArray *path = [NSMutableArray array];
    UIView *view = control;
    while (view && view != container && path.count < 16) {
        UIView *parent = view.superview;
        NSUInteger index = [parent.subviews indexOfObjectIdenticalTo:view];
        if (!parent || index == NSNotFound || index > 199) return nil;
        [path insertObject:@(index) atIndex:0];
        view = parent;
    }
    return view == container && path.count ? path : nil;
}

static UIImage *ASGRenderROI(UIView *context, CGRect roi, BOOL *valid) {
    *valid = NO;
    if (!context || CGRectIsEmpty(roi) || CGRectIsInfinite(roi) || CGRectIsNull(roi)) return nil;
    CGFloat scale = MIN(2.0, MIN(ASG_MAX_IMAGE_WIDTH / roi.size.width, ASG_MAX_IMAGE_HEIGHT / roi.size.height));
    if (scale <= 0 || !isfinite(scale)) return nil;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = scale;
    format.opaque = YES;
    format.preferredRange = UIGraphicsImageRendererFormatRangeStandard;
#if ASG_DIAGNOSTICS
    double start = ASGNow();
#endif
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:roi.size format:format];
    __block BOOL drawn = NO;
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *r) {
        CGContextTranslateCTM(r.CGContext, -roi.origin.x, -roi.origin.y);
        if ([context isKindOfClass:UIWindow.class]) {
            drawn = YES;
            for (UIWindow *window in ASGWindows().reverseObjectEnumerator) {
                CGRect frame = [(UIWindow *)context convertRect:window.bounds fromWindow:window];
                CGContextSaveGState(r.CGContext);
                CGContextTranslateCTM(r.CGContext, frame.origin.x - window.bounds.origin.x, frame.origin.y - window.bounds.origin.y);
                drawn = [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:NO] && drawn;
                CGContextRestoreGState(r.CGContext);
            }
        } else drawn = [context drawViewHierarchyInRect:context.bounds afterScreenUpdates:NO];
    }];
#if ASG_DIAGNOSTICS
    double duration = ASGNow() - start;
    ASGDiagnostic(@"roi_render", @{@"drawn": @(drawn), @"image": @(image.CGImage != NULL), @"durationMS": @(duration * 1000)});
#endif
    // Capture work cannot be preempted at 8ms; throwing away a usable 30ms image wastes
    // that work and disables the only fallback. Bound request count, not just frame time.
    *valid = drawn && image.CGImage;
    return image;
}

// Frames keep weak views, not a retained copy of a whole application's hierarchy.
@interface ASGScanFrame : NSObject
@property(nonatomic, weak) UIView *view;
@property(nonatomic) NSUInteger nextChild;
@property(nonatomic) NSUInteger childCount;
@property(nonatomic) BOOL visited;
@end
@implementation ASGScanFrame
@end

@interface ASGCandidate : NSObject
@property(nonatomic, weak, readonly) UIView *target;
@property(nonatomic, weak, readonly) UIView *source;
@property(nonatomic, weak, readonly) UIView *container;
@property(nonatomic, weak, readonly) UIWindow *window;
@property(nonatomic, copy, readonly) NSString *text;
@property(nonatomic, readonly) CGRect rect;
@property(nonatomic, readonly) ASGActionKind kind;
@property(nonatomic, readonly) BOOL ocr;
@property(nonatomic, readonly) BOOL explicitAd;
@property(nonatomic, readonly) double capturedAt;
@property(nonatomic, weak, readonly) UIViewController *controller;
@property(nonatomic, readonly) UIInterfaceOrientation orientation;
@property(nonatomic, readonly) CGRect windowBounds;
@property(nonatomic, copy, readonly) NSData *visualEvidence;
@property(nonatomic, readonly) CGRect evidenceRegion;
- (instancetype)initWithTarget:(UIView *)target source:(UIView *)source container:(UIView *)container
    window:(UIWindow *)window text:(NSString *)text rect:(CGRect)rect kind:(ASGActionKind)kind ocr:(BOOL)ocr;
- (void)bindVisualEvidence:(NSData *)evidence region:(CGRect)region capturedAt:(double)capturedAt;
@end
@implementation ASGCandidate
- (instancetype)initWithTarget:(UIView *)target source:(UIView *)source container:(UIView *)container
    window:(UIWindow *)window text:(NSString *)text rect:(CGRect)rect kind:(ASGActionKind)kind ocr:(BOOL)ocr {
    if ((self = [super init])) {
        _target = target; _source = source; _container = container; _window = window;
        _text = [text copy]; _rect = rect; _kind = kind; _ocr = ocr; _explicitAd = ASGExplicitAdText(text);
        _capturedAt = ASGNow(); _controller = ASGTopController(window.rootViewController);
        _orientation = window.windowScene.interfaceOrientation;
        _windowBounds = window.bounds;
    }
    return self;
}
- (void)bindVisualEvidence:(NSData *)evidence region:(CGRect)region capturedAt:(double)capturedAt {
    _visualEvidence = [evidence copy]; _evidenceRegion = region; _capturedAt = capturedAt;
}
@end

static NSData *ASGLocalImageEvidence(UIImage *image) {
    if (!image.CGImage) return nil;
    unsigned char pixels[8192] = {0}; // 64 x 32 x RGBA, local entry only.
    CGColorSpaceRef color = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, 64, 32, 8, 256, color,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(color);
    if (!context) return nil;
    CGContextSetInterpolationQuality(context, kCGInterpolationLow);
    CGContextDrawImage(context, CGRectMake(0, 0, 64, 32), image.CGImage);
    CGContextRelease(context);
    return [NSData dataWithBytes:pixels length:sizeof(pixels)];
}

static BOOL ASGLocalEvidenceCurrent(ASGCandidate *candidate) {
    if (!candidate.visualEvidence || !candidate.window) return NO;
    BOOL rendered = NO;
    UIImage *image = ASGRenderROI(candidate.window, candidate.evidenceRegion, &rendered);
    NSData *current = rendered ? ASGLocalImageEvidence(image) : nil;
    return ASGVisualEvidenceMatches(candidate.visualEvidence.bytes, current.bytes, (unsigned)current.length);
}

// A small, transient visual signature is only used to verify self-drawn/root ads.
static NSArray<NSDictionary *> *ASGControlCallbacks(UIView *view) {
    if (![view isKindOfClass:UIControl.class]) return nil;
    UIControl *control = (UIControl *)view;
    UIControlEvents allowed = UIControlEventTouchUpInside | UIControlEventPrimaryActionTriggered;
    if (control.allControlEvents & ~allowed) return nil;
    NSMutableArray *callbacks = [NSMutableArray array];
    @try {
        for (id target in control.allTargets) {
            if (target == NSNull.null) return nil;
            for (NSNumber *event in @[@(UIControlEventTouchUpInside), @(UIControlEventPrimaryActionTriggered)]) {
                for (NSString *action in [control actionsForTarget:target forControlEvent:event.unsignedLongLongValue]) {
                    [callbacks addObject:@{@"target": target, @"action": action, @"event": event}];
                    if (callbacks.count > 8) return nil;
                }
            }
        }
    } @catch (NSException *exception) { return nil; }
    return callbacks.count ? callbacks : nil;
}

static NSData *ASGSignature(UIView *view, CGRect region) {
    if (!view || CGRectIsEmpty(region)) return nil;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1; format.opaque = YES;
    UIImage *image = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(16, 16) format:format]
        imageWithActions:^(UIGraphicsImageRendererContext *r) {
            CGContextScaleCTM(r.CGContext, 16 / region.size.width, 16 / region.size.height);
            CGContextTranslateCTM(r.CGContext, -region.origin.x, -region.origin.y);
            [view.layer renderInContext:r.CGContext];
        }];
    if (!image.CGImage) return nil;
    uint8_t pixels[256] = {0};
    CGColorSpaceRef gray = CGColorSpaceCreateDeviceGray();
    CGContextRef bitmap = CGBitmapContextCreate(pixels, 16, 16, 8, 16, gray, kCGImageAlphaNone);
    CGColorSpaceRelease(gray);
    if (!bitmap) return nil;
    CGContextDrawImage(bitmap, CGRectMake(0, 0, 16, 16), image.CGImage); CGContextRelease(bitmap);
    return [NSData dataWithBytes:pixels length:sizeof(pixels)];
}
static BOOL ASGSignatureChanged(NSData *a, NSData *b) {
    if (a.length != 256 || b.length != 256) return NO;
    const uint8_t *x = a.bytes, *y = b.bytes;
    unsigned difference = 0;
    for (unsigned i = 0; i < 256; i++) difference += abs((int)x[i] - (int)y[i]);
    return difference > 256 * 18;
}
static BOOL ASGSignatureStable(NSData *a, NSData *b) {
    if (a.length != 256 || b.length != 256) return NO;
    const uint8_t *x = a.bytes, *y = b.bytes; unsigned difference = 0;
    for (unsigned i = 0; i < 256; i++) difference += abs((int)x[i] - (int)y[i]);
    return difference < 256 * 5;
}

@interface ASGGuard : NSObject
+ (instancetype)shared;
- (void)activate;
- (void)cancel;
- (void)userTouched;
@end

@implementation ASGGuard {
    ASGSession _session;
    ASGCache *_cache;
    NSMutableArray *_observers;
    BOOL _ocrInFlight;
    BOOL _attempted;
    unsigned _attemptCount;
    unsigned _ocrPasses;
    BOOL _dispatchingSynthetic;
    BOOL _ocrDisabledForLaunch;
    ASGOCRSchedule _ocrSchedule;
    id _ocrRequest;
    __weak UIWindow *_cycleWindow;
    __weak UIViewController *_cycleController;
    NSString *_bundle;
    NSMutableArray<ASGScanFrame *> *_scanStack;
    NSMutableArray<ASGCandidate *> *_scanCandidates;
    NSArray<NSValue *> *_scanWindows; // nonretained window identity, never dereferenced
    unsigned _scanVisited;
    unsigned _scanRestarts;
    BOOL _scanIncomplete;
    ASGCandidate *_candidate;
    BOOL _forceTouch;
    double _launchStarted;
    double _suppressUntil;
    unsigned _visualChecks;
    unsigned _ambiguityGeneration;
    NSArray<ASGCandidate *> *_equivalentCandidates;
    BOOL _ocrFullWindowNext;
    BOOL _probeScheduled;
    double _probeDue;
    uint64_t _probeTicket;
}

+ (instancetype)shared {
    static ASGGuard *guard;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ guard = [ASGGuard new]; });
    return guard;
}

- (instancetype)init {
    if ((self = [super init])) {
        _bundle = NSBundle.mainBundle.bundleIdentifier;
        // Original parity does not require persistent locators. Keep the repaired cache
        // component available, but do not spend I/O or trust historical layouts by default.
        _observers = [NSMutableArray array];
        __weak ASGGuard *owner = self;
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        for (NSString *name in @[UIApplicationDidBecomeActiveNotification, UISceneDidActivateNotification]) {
            [_observers addObject:[center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { [owner activate]; }]];
        }
        for (NSString *name in @[UIApplicationWillResignActiveNotification, UISceneWillDeactivateNotification,
                                 UISceneDidDisconnectNotification, UIApplicationDidReceiveMemoryWarningNotification]) {
            [_observers addObject:[center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                ASGGuard *guard = owner;
                if (!guard) return;
                if ([note.object isKindOfClass:UIWindowScene.class] && guard->_cycleWindow.windowScene != note.object) return;
                ASGRemoveSuccessTip();
                if ([note.name isEqual:UIApplicationDidReceiveMemoryWarningNotification]) guard->_ocrDisabledForLaunch = YES;
                unsigned reason = [note.name isEqual:UIApplicationDidReceiveMemoryWarningNotification] ? 7 : 8;
                [guard cancelReason:reason];
            }]];
        }
    }
    return self;
}

- (void)cancel { [self cancelReason:0]; }
- (BOOL)trackOCRRequest:(id)request token:(uint64_t)token {
    // Invoked from the worker only, before performRequests. All request ownership
    // transitions happen on main, including crop/exit checks previously not tracked.
    __block BOOL valid = NO;
    dispatch_sync(dispatch_get_main_queue(), ^{
        valid = request && ASGSessionValid(&self->_session, token, ASGNow());
        if (valid) self->_ocrRequest = request;
        else if ([request respondsToSelector:@selector(cancel)]) [request performSelector:@selector(cancel)];
    });
    return valid;
}
- (void)cancelReason:(unsigned)reason {
    NSAssert(NSThread.isMainThread, @"UI ownership must be main-thread");
    ASGDiagnostic(@"cancel", @{@"reason": @(reason), @"probes": @(_session.probes), @"ocrPasses": @(_ocrPasses), @"actions": @(_attemptCount)});
    ASGCancelSession(&_session); ASGFlushDiagnostics(); ASGArmed = NO;
    if ([_ocrRequest respondsToSelector:@selector(cancel)]) [_ocrRequest performSelector:@selector(cancel)];
    _ocrRequest = nil; _candidate = nil; _scanStack = nil; _scanCandidates = nil; _scanWindows = nil; _equivalentCandidates = nil;
    _cycleWindow = nil; _cycleController = nil;
    _probeScheduled = NO;
    _probeTicket++;
    // Cancellation is not completion: only the actual worker may clear inFlight.
}
- (void)userTouched {
    if (_session.active && !_dispatchingSynthetic) { _suppressUntil = ASGNow() + 15; [self cancelReason:1]; }
}
#if ASG_TEST_HARNESS
- (void)startFixture {
    [self cancel]; _suppressUntil = 0; [self activate];
}
#endif

- (void)schedule:(NSTimeInterval)delay token:(uint64_t)token block:(void (^)(ASGGuard *))block {
    __weak ASGGuard *owner = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        ASGGuard *guard = owner;
        if (!guard || !ASGSessionValid(&guard->_session, token, ASGNow())) return;
        block(guard);
    });
}

- (void)scheduleExpiration:(uint64_t)token {
    __weak ASGGuard *owner = self;
    NSTimeInterval delay = MAX(0.05, _session.deadline - ASGNow() + 0.05);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        ASGGuard *guard = owner;
        if (!guard || !guard->_session.active || guard->_session.generation != token) return;
        // Do not use SessionValid here: expiration must clean up even after a busy runloop delays this block.
        if (ASGNow() >= guard->_session.deadline) [guard cancel];
        else [guard scheduleExpiration:token];
    });
}

- (void)scheduleProbe:(double)delay token:(uint64_t)token {
    double now = ASGNow();
    if (!ASGSessionValid(&_session, token, now) || !isfinite(delay) || delay < 0) return;
    double due = now + delay;
    if (due >= _session.deadline || (_probeScheduled && _probeDue <= due)) return;
    _probeScheduled = YES;
    _probeDue = due;
    uint64_t ticket = ++_probeTicket;
    [self schedule:delay token:token block:^(ASGGuard *guard) {
        if (guard->_probeTicket != ticket) return; // Retire a replaced later wakeup.
        guard->_probeScheduled = NO;
        [guard probe:token];
    }];
}

- (void)discoveryMiss:(uint64_t)token {
    if (!ASGSessionValid(&_session, token, ASGNow()) || _attempted) return;
    double delay = ASGCompleteOCRMiss(&_ocrSchedule, ASGNow());
    ASGDiagnostic(@"ocr_backoff", @{@"waitMS": @(delay * 1000), @"misses": @(_ocrSchedule.misses), @"passes": @(_ocrPasses)});
    [self scheduleProbe:delay token:token];
}

- (void)activate {
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive || ASGNow() < _suppressUntil) return;
    if (_session.active && ASGNow() < _session.deadline) return;
    if (_session.active) [self cancelReason:2];
    _session.generation++; _session.active = YES; ASGArmed = YES; _session.verifying = NO;
    _launchStarted = ASGNow(); _session.deadline = _launchStarted + ASG_ACTIVE_SECONDS; _session.probes = 0;
    _attempted = _forceTouch = NO; _attemptCount = _ocrPasses = _visualChecks = 0;
    ASGResetOCRSchedule(&_ocrSchedule, _launchStarted);
    _ocrFullWindowNext = NO;
    _probeScheduled = NO;
    _scanStack = nil; _scanWindows = nil; _candidate = nil; _ambiguityGeneration = 0;
    _cycleWindow = ASGWindow(); _cycleController = ASGTopController(_cycleWindow.rootViewController);
    ASGStartDiagnosticCycle(_session.generation);
    ASGDiagnostic(@"activated", @{@"window": @(_cycleWindow != nil)});
    uint64_t token = _session.generation;
    [self scheduleExpiration:token];
    [self scheduleProbe:.15 token:token];
}

- (NSString *)environment:(UIWindow *)window {
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    CGRect bounds = window.bounds;
    UIEdgeInsets safe = window.safeAreaInsets;
    return [NSString stringWithFormat:@"%@|%@|%@|%@|%ld|%.0fx%.0f|%ld|%.0f,%.0f,%.0f,%.0f|%@|%@",
            _bundle, info[@"CFBundleShortVersionString"] ?: @"", info[@"CFBundleVersion"] ?: @"", ASGVersion,
            (long)NSProcessInfo.processInfo.operatingSystemVersion.majorVersion, bounds.size.width, bounds.size.height,
            (long)window.windowScene.interfaceOrientation, safe.top, safe.left, safe.bottom, safe.right,
            NSLocale.preferredLanguages.firstObject ?: @"", window.traitCollection.preferredContentSizeCategory];
}

- (UIView *)containerForTarget:(UIView *)target window:(UIWindow *)window {
    UIViewController *vc = ASGTopController(window.rootViewController);
    UIView *root = vc.isViewLoaded ? vc.view : nil;
    if (vc.presentingViewController && root && [target isDescendantOfView:root]) return root;
    UIView *found = nil;
    for (UIView *view = target.superview; view && view != window && view != root; view = view.superview) {
        CGRect rect = [view convertRect:view.bounds toView:window];
        if (rect.size.width >= window.bounds.size.width * .35 && rect.size.height >= window.bounds.size.height * .20
            && ASGVisible(view, window)) found = view;
    }
    return found ?: window;
}

- (BOOL)authorize:(ASGCandidate *)c {
    UIWindow *window = c.window; UIView *target = c.target;
    if (!window || !target || !ASGWindowActive(window) || !ASGVisible(target, window) || !target.userInteractionEnabled
        || ASGExcludedPage(ASGTopController(window.rootViewController)) || ASGUnsafeActionText(c.text)
        || ASGUnsafeActionText(target.accessibilityIdentifier)) return NO;
    if (c.controller != ASGTopController(window.rootViewController) || c.orientation != window.windowScene.interfaceOrientation) return NO;
    if (!CGRectEqualToRect(c.windowBounds, window.bounds)) return NO;
    if (c.ocr && ASGNow() - c.capturedAt > 1.5) return NO;
    CGRect r = CGRectMake((c.rect.origin.x - window.bounds.origin.x) / window.bounds.size.width,
        (c.rect.origin.y - window.bounds.origin.y) / window.bounds.size.height,
        c.rect.size.width / window.bounds.size.width, c.rect.size.height / window.bounds.size.height);
    BOOL adContext = NO;
    for (UIView *ancestor = target; ancestor && ancestor != window; ancestor = ancestor.superview) {
        if (ASGAdClass(NSStringFromClass(ancestor.class))) { adContext = YES; break; }
    }
    adContext = adContext || ASGAdClass(NSStringFromClass(c.controller.class));
    BOOL overlay = c.container != window && ASGVisible(c.container, window) && adContext;
    BOOL countdown = ASGCountdownText(c.text);
    if (c.kind == ASGActionAdCountdown) {
        if (!ASGAdCountdownEntry(adContext, r.origin.x, r.origin.y, r.size.width, r.size.height)) return NO;
    } else if (!ASGAuthorizeCandidate(c.kind == ASGActionSkip, c.explicitAd, countdown, overlay, ASGArrowText(c.text),
                                     r.origin.x, r.origin.y, r.size.width, r.size.height)) return NO;
    CGPoint point = CGPointMake(CGRectGetMidX(c.rect), CGRectGetMidY(c.rect));
    if (!c.ocr && (c.source != target && ![c.source isDescendantOfView:target])) return NO;
    if (ASGUnsafeActionText(ASGText(target))) return NO;
    UIView *hit = ASGForegroundHit(window, point);
    // Disabled countdown buttons can still have an application-owned action.
    // A parent hit is acceptable only when it really contains this target, never a covering sibling.
    if (!c.ocr && [target isKindOfClass:UIControl.class] && !((UIControl *)target).enabled
        && hit != window && [target isDescendantOfView:hit]) return YES;
    return hit == target || [hit isDescendantOfView:target];
}

- (ASGCandidate *)candidateForView:(UIView *)view window:(UIWindow *)window {
    NSString *text = ASGEntryText(view);
    ASGActionKind kind = ASGActionForText(text);
    if (kind == ASGActionNone && ASGSkipIdentifier(view.accessibilityIdentifier)) {
        kind = ASGActionSkip;
        text = [text stringByAppendingFormat:@" %@", view.accessibilityIdentifier];
    }
    if (kind == ASGActionNone || ASGUnsafeActionText(text)) return nil;
    CGRect rect = [view convertRect:view.bounds toView:window];
    CGPoint point = CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect));
    UIView *hit = [window hitTest:point withEvent:nil];
    UIView *target = ASGControlFromView(view, window);
    // Preserve a directly interactive custom entry, not an unrelated sibling hit.
    if (!target && view.userInteractionEnabled && hit == view) target = view;
    if (!target || (target != view && ![view isDescendantOfView:target])) return nil;
    ASGCandidate *c = [[ASGCandidate alloc] initWithTarget:target source:view container:[self containerForTarget:target window:window]
        window:window text:text rect:rect kind:kind ocr:NO];
    return [self authorize:c] ? c : nil;
}

- (void)beginScan:(NSArray<UIWindow *> *)windows {
    _scanStack = [NSMutableArray array]; _scanCandidates = [NSMutableArray array];
    NSMutableArray *identities = [NSMutableArray array];
    for (UIWindow *window in windows) [identities addObject:[NSValue valueWithNonretainedObject:window]];
    _scanWindows = [identities copy]; _scanVisited = 0; _scanRestarts = 0; _scanIncomplete = NO;
    for (UIWindow *window in windows.reverseObjectEnumerator) {
        ASGScanFrame *frame = [ASGScanFrame new]; frame.view = window; frame.childCount = window.subviews.count;
        [_scanStack addObject:frame];
    }
}

- (BOOL)equivalent:(ASGCandidate *)a to:(ASGCandidate *)b {
    if (!a || !b || a.kind != b.kind || !a.container || a.container == a.window
        || a.container != b.container || a.window != b.window || ![self authorize:a] || ![self authorize:b]) return NO;
    // Same selector can branch on sender.tag or state. Do not merge those declarations.
    if (![a.target isKindOfClass:UIControl.class] || ![b.target isKindOfClass:UIControl.class]
        || a.target.class != b.target.class || a.target.tag != b.target.tag
        || ((UIControl *)a.target).enabled != ((UIControl *)b.target).enabled
        || a.target.gestureRecognizers.count || b.target.gestureRecognizers.count) return NO;
    return ASGActionsEquivalent(ASGControlCallbacks(a.target), ASGControlCallbacks(b.target));
}

- (BOOL)tiedCandidatesAmbiguous:(NSArray<ASGCandidate *> *)candidates {
    _equivalentCandidates = nil;
    ASGCandidate *best = candidates.firstObject;
    NSMutableArray *aliases = [NSMutableArray array];
    for (NSUInteger i = 1; i < candidates.count; i++) {
        ASGCandidate *other = candidates[i];
        if (other.window != best.window || ASGActionPriority(other.kind) != ASGActionPriority(best.kind) || other.explicitAd != best.explicitAd
            || fabs(CGRectGetMinY(other.rect) - CGRectGetMinY(best.rect)) >= 8) continue;
        if (![self equivalent:best to:other]) return YES;
        [aliases addObject:other];
    }
    if (aliases.count) {
        _equivalentCandidates = [aliases copy];
        ASGDiagnostic(@"equivalent_controls", @{@"aliases": @(aliases.count)});
    }
    return NO;
}

- (BOOL)scanSlice {
    double start = ASGNow(); unsigned visited = 0;
    while (_scanStack.count && visited < 256 && ASGNow() - start < .006) {
        ASGScanFrame *frame = _scanStack.lastObject; UIView *view = frame.view;
        UIWindow *window = [view isKindOfClass:UIWindow.class] ? (UIWindow *)view : view.window;
        if (!ASGVisible(view, window) || [view.accessibilityIdentifier isEqual:@"ayao.AutoSkipGuard.successTip"]) {
            [_scanStack removeLastObject]; continue;
        }
        if (!frame.visited) {
            frame.visited = YES; visited++; _scanVisited++;
            ASGCandidate *c = [self candidateForView:view window:window];
            if (c) {
                BOOL duplicate = NO;
                for (ASGCandidate *old in _scanCandidates) if (old.target == c.target) { duplicate = YES; break; }
                if (!duplicate) [_scanCandidates addObject:c];
                if (_scanCandidates.count > 32) { _scanIncomplete = YES; [_scanStack removeAllObjects]; break; }
            }
        }
        NSArray<UIView *> *children = view.subviews;
        if (frame.childCount != children.count) {
            // Restart the affected branch; don't treat mutation as completed discovery.
            frame.childCount = children.count; frame.nextChild = 0;
            if (++_scanRestarts > 32) { _scanIncomplete = YES; [_scanStack removeAllObjects]; break; }
        }
        if (_scanVisited >= 24000 || _scanStack.count >= 128) {
            _scanIncomplete = YES; [_scanStack removeAllObjects]; break;
        }
        if (frame.nextChild >= children.count) { [_scanStack removeLastObject]; continue; }
        UIView *child = children[children.count - 1 - frame.nextChild++];
        ASGScanFrame *next = [ASGScanFrame new]; next.view = child; next.childCount = child.subviews.count;
        [_scanStack addObject:next];
    }
    return _scanStack.count == 0;
}

- (void)probe:(uint64_t)token {
    if (_attempted || _session.verifying || !ASGSessionValid(&_session, token, ASGNow())) return;
    NSArray<UIWindow *> *windows = ASGWindows();
    NSMutableArray *identities = [NSMutableArray array];
    for (UIWindow *window in windows) [identities addObject:[NSValue valueWithNonretainedObject:window]];
    if (![_scanWindows isEqual:identities] || !_scanStack) [self beginScan:windows];
    if (![self scanSlice]) {
        [self scheduleProbe:.01 token:token]; return;
    }
    if (!ASGConsumeProbe(&_session, ASGNow())) { [self cancelReason:3]; return; }
    NSMutableArray<ASGCandidate *> *valid = [NSMutableArray array];
    for (ASGCandidate *c in _scanCandidates) {
        // Every completed slice is revalidated against the current text and geometry.
        ASGCandidate *fresh = [self candidateForView:c.source window:c.window];
        if (fresh) [valid addObject:fresh];
    }
    // Rank the visible uppermost entry as the original does, but do not break equal-position ambiguity.
    [valid sortUsingComparator:^NSComparisonResult(ASGCandidate *a, ASGCandidate *b) {
        if (a.window.windowLevel != b.window.windowLevel) return a.window.windowLevel > b.window.windowLevel ? NSOrderedAscending : NSOrderedDescending;
        if (ASGActionPriority(a.kind) != ASGActionPriority(b.kind))
            return ASGActionPriority(a.kind) < ASGActionPriority(b.kind) ? NSOrderedAscending : NSOrderedDescending;
        if (a.explicitAd != b.explicitAd) return a.explicitAd ? NSOrderedAscending : NSOrderedDescending;
        if (CGRectGetMinY(a.rect) == CGRectGetMinY(b.rect)) return NSOrderedSame;
        return CGRectGetMinY(a.rect) < CGRectGetMinY(b.rect) ? NSOrderedAscending : NSOrderedDescending;
    }];
    ASGCandidate *chosen = valid.firstObject;
    BOOL ambiguous = [self tiedCandidatesAmbiguous:valid];
    BOOL incomplete = _scanIncomplete;
    if (ambiguous || incomplete) _ambiguityGeneration++;
    _scanStack = nil; _scanCandidates = nil;
    if (chosen && !ambiguous && !incomplete) {
        _cycleWindow = chosen.window; _cycleController = ASGTopController(chosen.window.rootViewController);
        _candidate = chosen;
        ASGDiagnostic(@"native_candidate", @{@"visited": @(_scanVisited), @"kind": @(chosen.kind)});
        [self tapCandidate:chosen token:token];
    } else {
        ASGDiagnostic(ambiguous ? @"native_ambiguous" : (incomplete ? @"native_incomplete" : @"native_no_match"), @{@"visited": @(_scanVisited)});
        if (!ambiguous && !incomplete && ASGOCRDue(&_ocrSchedule, &_session, token, ASGNow(), _ocrInFlight)) {
            UIWindow *window = windows.firstObject;
            if (window && !ASGExcludedPage(ASGTopController(window.rootViewController))) {
                _cycleWindow = window; _cycleController = ASGTopController(window.rootViewController);
                [self recognizeWindow:window token:token];
            }
        }
    }
    if (!_attempted && !_session.verifying) {
        double delay = .4;
        if (!_ocrInFlight && _ocrSchedule.nextAt > ASGNow()) delay = MIN(delay, _ocrSchedule.nextAt - ASGNow());
        [self scheduleProbe:delay token:token];
    }
}

- (NSDictionary *)recordFor:(UIView *)control container:(UIView *)container {
    NSArray *path = ASGPath(control, container);
    CGRect r = ASGNormalizedRect(control, container);
    NSString *identifier = control.accessibilityIdentifier ?: @"";
    if ([container isKindOfClass:UIWindow.class] || !ASGControlSemantic(control)) return nil; // Unknown context/indirect text cannot authorize persistent learning.
    if (!path || identifier.length > 160 || !ASGRectValid(r.origin.x, r.origin.y, r.size.width, r.size.height)) return nil;
    return @{@"contextClass": NSStringFromClass(container.class), @"controlClass": NSStringFromClass(control.class),
             @"identifier": identifier, @"semantic": ASGMeaning(_candidate.kind) ?: @"skip", @"path": path,
             @"rect": @[@(r.origin.x), @(r.origin.y), @(r.size.width), @(r.size.height)]};
}

- (void)tapCandidate:(ASGCandidate *)c token:(uint64_t)token {
    if (_attempted || _attemptCount >= 2 || !ASGSessionValid(&_session, token, ASGNow()) || ![self authorize:c]) return;
    UIView *target = c.target; UIWindow *window = c.window; UIView *container = c.container;
    for (ASGCandidate *alias in _equivalentCandidates) if (![self equivalent:c to:alias]) return;
    // Native candidates are re-read at use time; cached coordinates never authorize an action.
    if (!c.ocr) {
        NSString *currentText = ASGEntryText(c.source);
        if (ASGUnsafeActionText(currentText) || (ASGActionForText(currentText) != c.kind && !ASGSkipIdentifier(c.source.accessibilityIdentifier))) return;
        if (!CGRectEqualToRect(c.rect, [c.source convertRect:c.source.bounds toView:window])) return;
    }
    UIViewController *top = ASGTopController(window.rootViewController);
    UIViewController *expected = top.isViewLoaded && top.view == container && top.presentingViewController ? top.presentingViewController : top;
    NSString *environment = [self environment:window];
    NSDictionary *record = (_cache && !c.ocr && c.explicitAd) ? [self recordFor:target container:container] : nil;
    CGRect bounds = window.bounds; UIInterfaceOrientation orientation = window.windowScene.interfaceOrientation;
    NSInteger seconds = ASGCountdownSeconds(c.text);
    // Root/canvas ads may keep the hit view alive: use a transient visual-change witness as well.
    NSData *before = container == window ? ASGSignature(window, window.bounds) : nil;
    if (c.ocr && !ASGLocalEvidenceCurrent(c)) {
        ASGDiagnostic(@"ocr_content_changed", nil);
        return;
    }
    if (!ASGSessionValid(&_session, token, ASGNow()) || ![self authorize:c]) return;
    double started = ASGNow(); // Measure feedback from the actual action, not screenshot preparation.
    _attempted = YES; _attemptCount++; _session.verifying = YES;
    unsigned attempt = _attemptCount;
    // The eight-second total budget includes verification and retries: never extend it.
    _dispatchingSynthetic = YES;
    BOOL dispatched = NO;
    if (!_forceTouch && [target isKindOfClass:UIControl.class]) {
        UIControl *control = (UIControl *)target;
        // Match the original: send TouchUpInside even if allControlEvents is not populated.
        UIControlEvents event = !(control.allControlEvents & UIControlEventTouchUpInside)
            && (control.allControlEvents & UIControlEventPrimaryActionTriggered)
            ? UIControlEventPrimaryActionTriggered : UIControlEventTouchUpInside;
        @try {
            if (ASGSessionValid(&_session, token, ASGNow())) {
                [control sendActionsForControlEvents:event]; dispatched = YES;
            }
        }
        @catch (NSException *exception) { ASGDiagnostic(@"control_action_exception", nil); }
    }
    if (!dispatched && ASGSessionValid(&_session, token, ASGNow()) && !_forceTouch && target.isAccessibilityElement && (target.accessibilityTraits & UIAccessibilityTraitButton)) {
        @try { dispatched = [target accessibilityActivate]; } @catch (NSException *exception) { dispatched = NO; }
    }
    __block BOOL sequenceComplete = dispatched;
    if (!dispatched) {
        sequenceComplete = NO;
        __weak ASGGuard *owner = self;
        dispatched = ASGPerformGuardedTap(target, window, CGPointMake(CGRectGetMidX(c.rect), CGRectGetMidY(c.rect)), ^BOOL {
            ASGGuard *guard = owner;
            return guard && ASGSessionValid(&guard->_session, token, ASGNow());
        }, ^(BOOL ended) {
            sequenceComplete = ended;
            ASGGuard *guard = owner;
            if (!ended && guard && ASGSessionValid(&guard->_session, token, ASGNow())) [guard cancelReason:4];
        });
    }
    _dispatchingSynthetic = NO;
    ASGDiagnostic(dispatched ? @"action_dispatched" : @"action_failed", @{@"touch": @(_forceTouch), @"ocr": @(c.ocr)});
    if (!dispatched) { _attempted = NO; _session.verifying = NO; return; }
    __weak UIView *oldTarget = target; __weak UIView *oldSource = c.source; __weak UIView *oldContainer = container;
    __weak UIWindow *oldWindow = window; __weak UIViewController *expectedController = expected;
    __weak UIViewController *initialController = top;
    __block double firstGone = -1;
    __block BOOL reported = NO;
    __block BOOL checkingVisual = NO;
    __block BOOL visualConfirmed = NO;
    __block NSData *settledSignature = nil;
    for (NSNumber *delay in @[@.12, @.30, @.55, @.85, @1.20, @1.60]) {
        [self schedule:delay.doubleValue token:token block:^(ASGGuard *guard) {
            if (reported || guard->_attemptCount != attempt) return;
            UIWindow *current = oldWindow;
            BOOL oldWindowGone = !ASGWindowActive(current);
            if (oldWindowGone) current = ASGWindow();
            UIViewController *vc = ASGTopController(current.rootViewController);
            BOOL stableScene = current && UIApplication.sharedApplication.applicationState == UIApplicationStateActive
                && CGRectEqualToRect(current.bounds, bounds) && current.windowScene.interfaceOrientation == orientation && !ASGExcludedPage(vc);
            BOOL contextGone = oldWindowGone || (oldContainer != oldWindow && (!oldContainer || !ASGVisible(oldContainer, oldWindow)));
            BOOL sourceGone = !oldSource || !ASGVisible(oldSource, oldWindow) || ASGActionForText(ASGEntryText(oldSource)) != c.kind;
            BOOL targetGone = !oldTarget || !ASGVisible(oldTarget, oldWindow);
            // Navigation to a promotion is not an ad exit. A disappearing container
            // alone cannot authorize an arbitrary replacement controller.
            BOOL pageExpected = vc && vc == expectedController;
            if (!stableScene) { [guard cancelReason:9]; return; }
            if (!pageExpected) {
                // A closing modal may keep its original controller until dismissal ends.
                // Wait without rendering while that original controller is still present;
                // a genuinely new controller is an ineligible navigation, stop immediately.
                if (vc == initialController && expectedController != initialController && delay.doubleValue < 1.5) return;
                [guard cancelReason:9]; return;
            }
            BOOL visualGone = NO;
            if (before && stableScene && !contextGone) {
                UIView *hit = [oldWindow hitTest:CGPointMake(CGRectGetMidX(c.rect), CGRectGetMidY(c.rect)) withEvent:nil];
                ASGActionKind nowKind = ASGActionForText(ASGText(hit));
                NSData *nowSignature = ASGSignature(oldWindow, oldWindow.bounds);
                BOOL changed = nowKind != c.kind && ASGSignatureChanged(before, nowSignature);
                if (c.ocr && changed && !checkingVisual && !visualConfirmed && delay.doubleValue <= .85) {
                    checkingVisual = YES;
                    [guard verifyOCRExit:c token:token completion:^(BOOL absent) {
                        checkingVisual = NO; visualConfirmed = absent;
                        if (absent) settledSignature = nowSignature;
                    }];
                }
                // OCR-only absence needs a fresh, successful read. Animation alone is not exit.
                visualGone = changed && (!c.ocr || (visualConfirmed && ASGSignatureStable(settledSignature, nowSignature)));
            }
            double elapsed = ASGNow() - started;
            BOOL notNaturalExpiry = ASGExitEvidenceSafe((int)seconds, elapsed)
                && (c.kind != ASGActionAdCountdown || seconds >= 2);
            BOOL exited = sequenceComplete && stableScene && pageExpected && notNaturalExpiry
                && ((contextGone && (targetGone || sourceGone)) || (sourceGone && visualGone)
                    || (!c.ocr && targetGone && sourceGone && (c.explicitAd || seconds >= 2)));
            if (ASGObserveExit(&firstGone, ASGNow(), exited)) {
                reported = YES;
                if (record && contextGone && targetGone) [guard->_cache confirmRecord:record environment:environment];
                ASGDiagnostic(@"verified_exit", @{@"cacheEligible": @(record && contextGone && targetGone)});
                [guard cancelReason:5];
                ASGShowSuccessTip(current); // Every confirmed exit goes through this one path.
                return;
            }
            BOOL stillPresent = [guard authorize:c] && (c.ocr || ASGActionForText(ASGEntryText(oldSource)) == c.kind);
            BOOL fallbackReady = !exited && firstGone < 0 && !checkingVisual && delay.doubleValue >= .85;
            if (fallbackReady && stillPresent && guard->_attemptCount < 2) {
                guard->_attempted = NO; guard->_session.verifying = NO; guard->_forceTouch = YES;
                reported = YES; // Retire this attempt's remaining checks before the retry.
                // Reacquire both native and OCR candidates before retry; never reuse an aged screenshot.
                [guard->_cache invalidateEnvironment:environment];
                guard->_scanStack = nil;
                // Action retries do not reset or bypass the discovery cooldown.
                [guard scheduleProbe:.05 token:token];
            } else if (delay.doubleValue >= 1.5) [guard cancelReason:6]; // Unknown outcome is not success.
        }];
    }
}

- (void)recognizeWindow:(UIWindow *)window token:(uint64_t)token {
    if (!ASGOCRDue(&_ocrSchedule, &_session, token, ASGNow(), _ocrInFlight) || _ocrDisabledForLaunch
        || NSProcessInfo.processInfo.thermalState >= NSProcessInfoThermalStateSerious) return;
    _ocrPasses++; _ocrInFlight = YES; // Count for diagnostics, never veto the seventh discovery.
    CGRect bounds = window.bounds;
    BOOL fullWindow = _ocrFullWindowNext;
    _ocrFullWindowNext = !fullWindow;
    CGRect region = fullWindow ? bounds : CGRectMake(bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height * .30);
    ASGDiagnostic(@"ocr_start", @{@"pass": @(_ocrPasses), @"fullWindow": @(fullWindow)});
    BOOL rendered = NO;
    // Region discovery misses always fall back to full-window coverage in the same cycle.
    UIImage *image = ASGRenderROI(window, region, &rendered);
    double capturedAt = ASGNow();
    unsigned ambiguityGeneration = _ambiguityGeneration;
    if (!rendered) { _ocrInFlight = NO; [self discoveryMiss:token]; return; }
    __weak ASGGuard *owner = self; __weak UIWindow *weakWindow = window;
    __weak UIViewController *capturedController = ASGTopController(window.rootViewController);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            static void *vision; static dispatch_once_t once;
            dispatch_once(&once, ^{ vision = dlopen("/System/Library/Frameworks/Vision.framework/Vision", RTLD_LAZY | RTLD_LOCAL); });
            Class requestClass = vision ? NSClassFromString(@"VNRecognizeTextRequest") : Nil;
            Class handlerClass = vision ? NSClassFromString(@"VNImageRequestHandler") : Nil;
            id request = [requestClass new];
            NSMutableArray<NSDictionary *> *matches = [NSMutableArray array];
#if ASG_DIAGNOSTICS
            unsigned rawMatches = 0;
#endif
            BOOL truncated = NO;
            BOOL ok = NO;
            @try {
                if (request && handlerClass) {
                    [request setValue:@0 forKey:@"recognitionLevel"];
                    [request setValue:@NO forKey:@"usesLanguageCorrection"];
                    [request setValue:@NO forKey:@"preferBackgroundProcessing"];
                    NSArray *languages = ((id (*)(id, SEL, NSError **))objc_msgSend)(request, NSSelectorFromString(@"supportedRecognitionLanguagesAndReturnError:"), NULL);
                    NSMutableArray *chosen = [NSMutableArray array];
                    for (NSString *desired in @[@"zh-Hans", @"zh-Hant", @"en-US"]) if ([languages containsObject:desired]) [chosen addObject:desired];
                    if (chosen.count) [request setValue:chosen forKey:@"recognitionLanguages"];
                    id handler = ((id (*)(id, SEL, CGImageRef, NSDictionary *))objc_msgSend)([handlerClass alloc], NSSelectorFromString(@"initWithCGImage:options:"), image.CGImage, @{});
                    NSError *error = nil;
                    ok = [owner trackOCRRequest:request token:token] && ((BOOL (*)(id, SEL, NSArray *, NSError **))objc_msgSend)(handler, NSSelectorFromString(@"performRequests:error:"), @[request], &error) && !error;
                    if (ok) for (id observation in [request valueForKey:@"results"]) {
                        id text = ((id (*)(id, SEL, NSUInteger))objc_msgSend)(observation, NSSelectorFromString(@"topCandidates:"), 1);
                        id result = [text firstObject]; NSString *string = [result valueForKey:@"string"];
                        ASGActionKind kind = ASGActionForOCRText(string);
                        if (kind == ASGActionNone || ASGUnsafeActionText(string) || [[result valueForKey:@"confidence"] floatValue] < .25) continue;
#if ASG_DIAGNOSTICS
                        rawMatches++;
#endif
                        CGRect box = [[observation valueForKey:@"boundingBox"] CGRectValue];
                        if (!ASGRectValid(box.origin.x, box.origin.y, box.size.width, box.size.height)) continue;
                        CGRect rect = CGRectMake(region.origin.x + box.origin.x * region.size.width,
                            region.origin.y + (1 - box.origin.y - box.size.height) * region.size.height,
                            box.size.width * region.size.width, box.size.height * region.size.height);
                        // One immutable record per observation: rejected entries cannot overwrite another's coordinates.
                        [matches addObject:@{@"text": string, @"rect": [NSValue valueWithCGRect:rect], @"kind": @(kind)}];
                        if (matches.count >= 32) { truncated = YES; break; }
                    }
                }
            } @catch (NSException *exception) { ok = NO; [matches removeAllObjects]; }
            NSArray *snapshot = [matches copy];
            dispatch_async(dispatch_get_main_queue(), ^{
                ASGGuard *guard = owner; if (!guard) return;
                guard->_ocrInFlight = NO; if (guard->_ocrRequest == request) guard->_ocrRequest = nil;
                UIWindow *current = weakWindow;
                if (!ASGSessionValid(&guard->_session, token, ASGNow())) return;
                ASGDiagnostic(@"ocr_discovery", @{@"rawMatches": @(rawMatches), @"truncated": @(truncated), @"ok": @(ok)});
                if (!ok || !ASGSessionValid(&guard->_session, token, ASGNow()) || guard->_attempted
                    || truncated
                    || guard->_ambiguityGeneration != ambiguityGeneration || !ASGWindowActive(current)
                    || !CGRectEqualToRect(bounds, current.bounds)
                    || !ASGOCRResultValid(guard->_session.generation, token, ASGNow() - capturedAt,
                        ASGTopController(current.rootViewController) == capturedController)) {
                    [guard discoveryMiss:token]; return;
                }
                NSMutableArray<ASGCandidate *> *authorized = [NSMutableArray array];
                for (NSDictionary *r in snapshot) {
                    CGRect rect = [r[@"rect"] CGRectValue]; CGPoint point = CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect));
                    UIView *hit = ASGForegroundHit(current, point);
                    UIWindow *targetWindow = hit.window;
                    CGRect targetRect = [targetWindow convertRect:rect fromWindow:current];
                    UIView *target = ASGControlFromView(hit, targetWindow) ?: hit;
                    ASGCandidate *c = [[ASGCandidate alloc] initWithTarget:target source:nil container:[guard containerForTarget:target window:targetWindow]
                        window:targetWindow text:r[@"text"] rect:targetRect kind:[r[@"kind"] integerValue] ocr:YES];
                    if ([guard authorize:c]) [authorized addObject:c];
                }
                [authorized sortUsingComparator:^NSComparisonResult(ASGCandidate *a, ASGCandidate *b) {
                    if (ASGActionPriority(a.kind) != ASGActionPriority(b.kind))
                        return ASGActionPriority(a.kind) < ASGActionPriority(b.kind) ? NSOrderedAscending : NSOrderedDescending;
                    if (a.explicitAd != b.explicitAd) return a.explicitAd ? NSOrderedAscending : NSOrderedDescending;
                    if (CGRectGetMinY(a.rect) == CGRectGetMinY(b.rect)) return NSOrderedSame;
                    return CGRectGetMinY(a.rect) < CGRectGetMinY(b.rect) ? NSOrderedAscending : NSOrderedDescending;
                }];
                ASGCandidate *best = authorized.firstObject;
                // Native discovery can finish while Vision is running; its known candidates
                // remain relevant to current authorization even when the image contains one entry.
                for (ASGCandidate *native in guard->_scanCandidates) {
                    if (![guard authorize:native] || native.target == best.target) continue;
                    if (native.window == best.window && ASGActionPriority(native.kind) == ASGActionPriority(best.kind) && native.explicitAd == best.explicitAd
                        && fabs(CGRectGetMinY(native.rect) - CGRectGetMinY(best.rect)) < 8) { best = nil; break; }
                }
                // Check every tied candidate, not just entry #2; reuse native authorization.
                BOOL ambiguous = best && [guard tiedCandidatesAmbiguous:authorized];
                ASGDiagnostic(@"ocr_results", @{@"matches": @(authorized.count), @"ambiguous": @(ambiguous), @"ageMS": @((ASGNow() - capturedAt) * 1000), @"fullWindow": @(fullWindow)});
                if (best && !ambiguous) {
                    guard->_candidate = best; guard->_cycleWindow = best.window; guard->_cycleController = ASGTopController(best.window.rootViewController);
                    // One small fresh reread before clicking, not another full-screen OCR pass.
                    guard->_session.verifying = YES;
                    [guard confirmOCRCandidate:best token:token completion:^(BOOL present, ASGCandidate *fresh) {
                        ASGGuard *currentGuard = owner;
                        if (!currentGuard || !ASGSessionValid(&currentGuard->_session, token, ASGNow())) return;
                        currentGuard->_session.verifying = NO;
                        if (present) { currentGuard->_candidate = fresh; [currentGuard tapCandidate:fresh token:token]; }
                        if (!currentGuard->_attempted) [currentGuard discoveryMiss:token];
                    }];
                } else [guard discoveryMiss:token];
            });
        }
    });
}

- (void)confirmOCRCandidate:(ASGCandidate *)c token:(uint64_t)token completion:(void (^)(BOOL, ASGCandidate *))completion {
    if (_ocrInFlight || !ASGSessionValid(&_session, token, ASGNow()) || ![self authorize:c]) { completion(NO, nil); return; }
    CGRect region = CGRectIntersection(CGRectInset(c.rect, -12, -8), c.window.bounds);
    BOOL rendered = NO; UIImage *image = ASGRenderROI(c.window, region, &rendered);
    NSData *evidence = rendered ? ASGLocalImageEvidence(image) : nil;
    if (!evidence) { completion(NO, nil); return; }
    _ocrInFlight = YES;
    __weak ASGGuard *owner = self; __weak UIWindow *weakWindow = c.window;
    __weak UIViewController *controller = ASGTopController(c.window.rootViewController);
    double capturedAt = ASGNow();
    unsigned ambiguityGeneration = _ambiguityGeneration;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            NSMutableArray<NSDictionary *> *observations = [NSMutableArray array];
            BOOL ok = NO;
            BOOL truncated = NO;
            @try {
                id request = [NSClassFromString(@"VNRecognizeTextRequest") new];
                [request setValue:@0 forKey:@"recognitionLevel"];
                [request setValue:@NO forKey:@"usesLanguageCorrection"];
                [request setValue:@[@"zh-Hans", @"en-US"] forKey:@"recognitionLanguages"];
                id handler = ((id (*)(id, SEL, CGImageRef, NSDictionary *))objc_msgSend)([NSClassFromString(@"VNImageRequestHandler") alloc], NSSelectorFromString(@"initWithCGImage:options:"), image.CGImage, @{});
                NSError *error = nil;
                ok = request && handler && [owner trackOCRRequest:request token:token] && ((BOOL (*)(id, SEL, NSArray *, NSError **))objc_msgSend)(handler, NSSelectorFromString(@"performRequests:error:"), @[request], &error) && !error;
                if (ok) for (id observation in [request valueForKey:@"results"]) {
                    id results = ((id (*)(id, SEL, NSUInteger))objc_msgSend)(observation, NSSelectorFromString(@"topCandidates:"), 1);
                    id result = [results firstObject]; NSString *text = [result valueForKey:@"string"];
                    ASGActionKind kind = ASGActionForOCRText(text);
                    if (kind == ASGActionNone || ASGUnsafeActionText(text) || [[result valueForKey:@"confidence"] floatValue] < .25) continue;
                    CGRect box = [[observation valueForKey:@"boundingBox"] CGRectValue];
                    if (!ASGRectValid(box.origin.x, box.origin.y, box.size.width, box.size.height)) continue;
                    CGRect rect = CGRectMake(region.origin.x + box.origin.x * region.size.width,
                        region.origin.y + (1 - box.origin.y - box.size.height) * region.size.height,
                        box.size.width * region.size.width, box.size.height * region.size.height);
                    [observations addObject:@{@"text": text, @"kind": @(kind), @"rect": [NSValue valueWithCGRect:rect]}];
                    if (observations.count >= 32) { truncated = YES; break; }
                }
            } @catch (NSException *exception) { ok = NO; }
            NSArray *snapshot = [observations copy];
            dispatch_async(dispatch_get_main_queue(), ^{
                ASGGuard *guard = owner; if (!guard) return;
                guard->_ocrInFlight = NO;
                guard->_ocrRequest = nil;
                if (!ASGSessionValid(&guard->_session, token, ASGNow())) return;
                BOOL valid = ok && !truncated && ASGWindowActive(weakWindow) && ASGNow() - capturedAt < .8
                    && guard->_ambiguityGeneration == ambiguityGeneration
                    && ASGTopController(weakWindow.rootViewController) == controller && [guard authorize:c];
                if (!valid) { completion(NO, nil); return; }
                NSMutableArray<ASGCandidate *> *candidates = [NSMutableArray array];
                for (NSDictionary *record in snapshot) {
                    CGRect rect = [record[@"rect"] CGRectValue];
                    UIView *hit = ASGForegroundHit(weakWindow, CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect)));
                    UIView *target = ASGControlFromView(hit, weakWindow) ?: hit;
                    // Do not attribute another window's hit to the captured window.
                    if (target.window != weakWindow) continue;
                    ASGCandidate *fresh = [[ASGCandidate alloc] initWithTarget:target source:nil container:[guard containerForTarget:target window:weakWindow]
                        window:weakWindow text:record[@"text"] rect:rect kind:[record[@"kind"] integerValue] ocr:YES];
                    [fresh bindVisualEvidence:evidence region:region capturedAt:capturedAt];
                    if ([guard authorize:fresh]) [candidates addObject:fresh];
                }
                [candidates sortUsingComparator:^NSComparisonResult(ASGCandidate *a, ASGCandidate *b) {
                    if (ASGActionPriority(a.kind) != ASGActionPriority(b.kind))
                        return ASGActionPriority(a.kind) < ASGActionPriority(b.kind) ? NSOrderedAscending : NSOrderedDescending;
                    if (a.explicitAd != b.explicitAd) return a.explicitAd ? NSOrderedAscending : NSOrderedDescending;
                    if (CGRectGetMinY(a.rect) == CGRectGetMinY(b.rect)) return NSOrderedSame;
                    return CGRectGetMinY(a.rect) < CGRectGetMinY(b.rect) ? NSOrderedAscending : NSOrderedDescending;
                }];
                ASGCandidate *fresh = candidates.firstObject;
                BOOL ambiguous = [guard tiedCandidatesAmbiguous:candidates];
                CGRect shared = CGRectIntersection(fresh ? fresh.rect : CGRectNull, c.rect);
                double common = CGRectIsNull(shared) ? 0 : shared.size.width * shared.size.height;
                double total = fresh ? fresh.rect.size.width * fresh.rect.size.height + c.rect.size.width * c.rect.size.height - common : 0;
                valid = fresh && !ambiguous && fresh.kind == c.kind && fresh.target == c.target
                    && total > 0 && ASGOCRPairAgrees(common / total, true, true);
                // Pixel witness is checked once, at actual use in tapCandidate, not here and again later.
                ASGDiagnostic(@"ocr_confirmation", @{@"candidates": @(candidates.count), @"ambiguous": @(ambiguous), @"current": @(valid)});
                completion(valid && [guard authorize:fresh], valid ? fresh : nil);
            });
        }
    });
}

- (void)verifyOCRExit:(ASGCandidate *)c token:(uint64_t)token completion:(void (^)(BOOL))completion {
    if (_ocrInFlight || _visualChecks >= 2 || !ASGSessionValid(&_session, token, ASGNow())) { completion(NO); return; }
    _visualChecks++;
    BOOL rendered = NO; CGRect bounds = c.window.bounds;
    UIImage *image = ASGRenderROI(c.window, bounds, &rendered);
    if (!rendered) { completion(NO); return; }
    _ocrInFlight = YES;
    __weak ASGGuard *owner = self; __weak UIWindow *weakWindow = c.window;
    double capturedAt = ASGNow();
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        @autoreleasepool {
            BOOL absent = NO;
            id request = [NSClassFromString(@"VNRecognizeTextRequest") new];
            @try {
                [request setValue:@0 forKey:@"recognitionLevel"];
                [request setValue:@NO forKey:@"usesLanguageCorrection"];
                [request setValue:@[@"zh-Hans", @"en-US"] forKey:@"recognitionLanguages"];
                id handler = ((id (*)(id, SEL, CGImageRef, NSDictionary *))objc_msgSend)([NSClassFromString(@"VNImageRequestHandler") alloc], NSSelectorFromString(@"initWithCGImage:options:"), image.CGImage, @{});
                NSError *error = nil;
                BOOL ok = request && handler && [owner trackOCRRequest:request token:token] && ((BOOL (*)(id, SEL, NSArray *, NSError **))objc_msgSend)(handler, NSSelectorFromString(@"performRequests:error:"), @[request], &error) && !error;
                NSArray *results = [request valueForKey:@"results"];
                absent = ok && results.count > 0; // Blank/failed recognition is unknown, not closed.
                for (id observation in results) {
                    id text = ((id (*)(id, SEL, NSUInteger))objc_msgSend)(observation, NSSelectorFromString(@"topCandidates:"), 1);
                    NSString *string = [[text firstObject] valueForKey:@"string"];
                    if (ASGActionForOCRText(string) == c.kind && !ASGUnsafeActionText(string)) { absent = NO; break; }
                }
            } @catch (NSException *exception) { absent = NO; }
            dispatch_async(dispatch_get_main_queue(), ^{
                ASGGuard *guard = owner; if (!guard) return;
                guard->_ocrInFlight = NO;
                guard->_ocrRequest = nil;
                if (!ASGSessionValid(&guard->_session, token, ASGNow())) return;
                completion(absent && ASGWindowActive(weakWindow) && CGRectEqualToRect(bounds, weakWindow.bounds) && ASGNow() - capturedAt < 1.5);
            });
        }
    });
}

@end

#if ASG_TEST_HARNESS
// Test build only: new controlled scenes are independent launch cycles.
void ASGFixtureStart(void) {
    [[ASGGuard shared] startFixture];
}
#endif

static void (*ASGOriginalSendEvent)(id, SEL, UIEvent *);
static void ASGSendEvent(id app, SEL selector, UIEvent *event) {
    if (ASGArmed && event.type == UIEventTypeTouches) {
        for (UITouch *touch in event.allTouches) if (touch.phase == UITouchPhaseBegan && !ASGIsSyntheticTouch(touch)) { [[ASGGuard shared] userTouched]; break; }
    }
    ASGOriginalSendEvent(app, selector, event);
}

__attribute__((constructor)) static void ASGBootstrap(void) {
    // Required app-local dylib entry point: no OCR, disk I/O, or eager touch objects here.
    dispatch_async(dispatch_get_main_queue(), ^{
        ASGDiagnostic(@"bootstrap", nil);
        ASGGuard *guard = [ASGGuard shared];
        Method method = class_getInstanceMethod(UIApplication.class, @selector(sendEvent:));
        if (method) ASGOriginalSendEvent = (void (*)(id, SEL, UIEvent *))method_setImplementation(method, (IMP)ASGSendEvent);
        [guard activate];

    });
}
