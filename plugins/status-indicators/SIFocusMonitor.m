#import "SIFocusMonitor.h"
#import <objc/message.h>
#import <dlfcn.h>
#include <stdatomic.h>
#include <string.h>

static const char *SIUnqualifiedType(const char *type) {
    while (*type && strchr("rnNoORV", *type)) type++;
    return type;
}
static BOOL SIObjectGetter(id object, SEL selector) {
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    return [object respondsToSelector:selector] && signature.numberOfArguments == 2
        && SIUnqualifiedType(signature.methodReturnType)[0] == '@';
}
static id SIReadObject(id object, NSString *key) {
    SEL selector = NSSelectorFromString(key);
    return SIObjectGetter(object, selector) ? ((id (*)(id, SEL))objc_msgSend)(object, selector) : nil;
}
static NSInteger SIStyleForModeIdentifier(NSString *identifier) {
    NSString *name = identifier.lowercaseString;
    // System mode IDs, not localized status-bar labels or arbitrary substrings.
    NSString *prefix = @"com.apple.donotdisturb.mode.";
    if (![name hasPrefix:prefix]) return 4;
    NSString *suffix = [name substringFromIndex:prefix.length];
    if ([name isEqualToString:@"com.apple.donotdisturb.mode.default"]
        || [suffix isEqualToString:@"do_not_disturb"] || [suffix isEqualToString:@"dnd"]
        || [suffix isEqualToString:@"donotdisturb"]) return 0;
    if ([suffix isEqualToString:@"personal"]) return 1;
    if ([suffix isEqualToString:@"work"]) return 2;
    if ([suffix isEqualToString:@"gaming"] || [suffix isEqualToString:@"game"]) return 3;
    return 4;
}
static NSInteger SIStyleForActiveConfiguration(id state) {
    @try {
        id configuration = SIReadObject(state, @"activeModeConfiguration");
        id mode = SIReadObject(configuration, @"mode");
        if (!mode) return -1; // Older state schemas may expose identifiers only.
        id identifier = SIReadObject(mode, @"modeIdentifier");
        if ([identifier isKindOfClass:NSString.class]) {
            NSInteger style = SIStyleForModeIdentifier(identifier);
            if (style != 4) return style;
        }
        // User-confirmed local mode name, from this event's model (not cached UI).
        // Exact match only; other custom mode names retain the existing mapping.
        id modeName = SIReadObject(mode, @"name");
        if ([modeName isKindOfClass:NSString.class] && [modeName isEqualToString:@"\u6e38\u620f"]) return 3;
        // iOS 16 modes need not have the guessed built-in identifier strings.
        // Resolve the exact system symbol from THIS event's active configuration;
        // never match substrings, localized UI snapshots, or unverified enum values.
        id rawSymbol = SIReadObject(mode, @"symbolImageName");
        if (![rawSymbol isKindOfClass:NSString.class]) return 4;
        NSString *symbol = [rawSymbol lowercaseString];
        if ([@[@"moon", @"moon.fill"] containsObject:symbol]) return 0;
        if ([@[@"person", @"person.fill", @"person.crop.circle", @"person.crop.circle.fill"] containsObject:symbol]) return 1;
        if ([@[@"briefcase", @"briefcase.fill", @"person.lanyardcard", @"person.lanyardcard.fill"] containsObject:symbol]) return 2;
        if ([@[@"gamecontroller", @"gamecontroller.fill"] containsObject:symbol]) return 3;
        return 4;
    } @catch (__unused NSException *exception) { return -1; }
}
SIFocusSnapshot SIFocusSnapshotFromState(id state) {
    SIFocusSnapshot unknown = {NO, -1};
    @try {
        SEL active = NSSelectorFromString(@"isActive");
        NSMethodSignature *signature = [state methodSignatureForSelector:active];
        if (![state respondsToSelector:active] || signature.numberOfArguments != 2) return unknown;
        const char *type = SIUnqualifiedType(signature.methodReturnType);
        if (strcmp(type, "B") && strcmp(type, "c")) return unknown;
        if (!((BOOL (*)(id, SEL))objc_msgSend)(state, active)) return (SIFocusSnapshot){YES, -1};
        NSInteger configuredStyle = SIStyleForActiveConfiguration(state);
        if (configuredStyle >= 0) return (SIFocusSnapshot){YES, configuredStyle};
        id identifiers = SIReadObject(state, @"activeModeIdentifiers");
        // An active mode with no recognized ID still has the explicit "other" icon.
        if (![identifiers isKindOfClass:NSArray.class]) return (SIFocusSnapshot){YES, 4};
        for (id identifier in identifiers) {
            if (![identifier isKindOfClass:NSString.class] || ![identifier length]) continue;
            NSInteger style = SIStyleForModeIdentifier(identifier);
            if (style != 4) return (SIFocusSnapshot){YES, style};
        }
        return (SIFocusSnapshot){YES, 4};
    } @catch (__unused NSException *exception) { return unknown; }
}

static id SIStateService(void) {
    static dispatch_once_t once;
    static void *framework;
    dispatch_once(&once, ^{
        framework = dlopen("/System/Library/PrivateFrameworks/DoNotDisturb.framework/DoNotDisturb", RTLD_LAZY);
    });
    if (!framework) return nil;
    Class cls = NSClassFromString(@"DNDStateService");
    SEL factory = NSSelectorFromString(@"serviceForClientIdentifier:");
    NSMethodSignature *signature = [cls methodSignatureForSelector:factory];
    if (![cls respondsToSelector:factory] || signature.numberOfArguments != 3
        || SIUnqualifiedType(signature.methodReturnType)[0] != '@'
        || SIUnqualifiedType([signature getArgumentTypeAtIndex:2])[0] != '@') return nil;
    // Verified in the target SpringBoard signature for both state request and updates.
    return ((id (*)(id, SEL, id))objc_msgSend)(cls, factory, @"com.apple.springboard.dndstatemonitor");
}
static BOOL SIServiceCompatible(id service) {
    SEL query = NSSelectorFromString(@"queryCurrentStateWithError:");
    SEL add = NSSelectorFromString(@"addStateUpdateListener:error:");
    SEL remove = NSSelectorFromString(@"removeStateUpdateListener:");
    NSMethodSignature *q = [service methodSignatureForSelector:query];
    NSMethodSignature *a = [service methodSignatureForSelector:add];
    NSMethodSignature *r = [service methodSignatureForSelector:remove];
    if (![service respondsToSelector:query] || q.numberOfArguments != 3
        || SIUnqualifiedType(q.methodReturnType)[0] != '@'
        || strcmp(SIUnqualifiedType([q getArgumentTypeAtIndex:2]), "^@")) return NO;
    if (![service respondsToSelector:add] || a.numberOfArguments != 4
        || (strcmp(SIUnqualifiedType(a.methodReturnType), "B") && strcmp(SIUnqualifiedType(a.methodReturnType), "c"))
        || SIUnqualifiedType([a getArgumentTypeAtIndex:2])[0] != '@'
        || strcmp(SIUnqualifiedType([a getArgumentTypeAtIndex:3]), "^@")) return NO;
    return [service respondsToSelector:remove] && r.numberOfArguments == 3
        && !strcmp(SIUnqualifiedType(r.methodReturnType), "v")
        && SIUnqualifiedType([r getArgumentTypeAtIndex:2])[0] == '@';
}

@class SIFocusListener;
@protocol DNDStateUpdateListener <NSObject>
- (void)stateService:(id)service didReceiveDoNotDisturbStateUpdate:(id)update;
@end
@interface SIFocusMonitor ()
- (instancetype)initWithHandler:(void (^)(SIFocusSnapshot))handler serviceFactory:(id (^)(void))factory;
- (void)receiveUpdate:(id)update service:(id)service listener:(SIFocusListener *)listener;
@end
@interface SIFocusListener : NSObject <DNDStateUpdateListener> {
@public
    atomic_uint_fast64_t received;
}
@property(atomic, weak) SIFocusMonitor *owner;
@property(nonatomic) uint64_t generation;
- (void)stateService:(id)service didReceiveDoNotDisturbStateUpdate:(id)update;
@end
@implementation SIFocusListener
- (instancetype)init {
    if ((self = [super init])) atomic_init(&received, 0);
    return self;
}
- (void)stateService:(id)service didReceiveDoNotDisturbStateUpdate:(id)update {
    // Increment on receipt, before queueing: initial IPC cannot overwrite a newer event.
    [self.owner receiveUpdate:update service:service listener:self];
}
@end

@implementation SIFocusMonitor {
    dispatch_queue_t _queue;
    id (^_factory)(void);
    void (^_handler)(SIFocusSnapshot);
    // Main-thread state. Queue-owned service/listener are never read on main.
    BOOL _running;
    uint64_t _generation, _delivered;
    atomic_uint_fast64_t _epoch;
    id _service;
    SIFocusListener *_listener;
}
- (instancetype)initWithHandler:(void (^)(SIFocusSnapshot))handler {
    return [self initWithHandler:handler serviceFactory:^{ return SIStateService(); }];
}
- (instancetype)initWithHandler:(void (^)(SIFocusSnapshot))handler serviceFactory:(id (^)(void))factory {
    if ((self = [super init])) {
        _handler = [handler copy]; _factory = [factory copy];
        _queue = dispatch_queue_create("ayao.statusindicators.focus", DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(_queue, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
        atomic_init(&_epoch, 0);
    }
    return self;
}
- (void)deliver:(SIFocusSnapshot)snapshot generation:(uint64_t)generation sequence:(uint64_t)sequence {
    __weak SIFocusMonitor *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        SIFocusMonitor *owner = weakSelf;
        if (!owner || !owner->_running || owner->_generation != generation || sequence <= owner->_delivered) return;
        owner->_delivered = sequence;
        if (owner->_handler) owner->_handler(snapshot);
    });
}
- (void)clearSubscription {
    if (_service && _listener) {
        @try { ((void (*)(id, SEL, id))objc_msgSend)(_service, NSSelectorFromString(@"removeStateUpdateListener:"), _listener); }
        @catch (__unused NSException *exception) {}
    }
    _listener.owner = nil; _listener = nil; _service = nil;
}
- (void)start {
    if (!NSThread.isMainThread || _running) return;
    _running = YES; _delivered = 0;
    uint64_t generation = ++_generation;
    atomic_store(&_epoch, generation);
    dispatch_async(_queue, ^{
        @autoreleasepool {
            [self clearSubscription];
            if (atomic_load(&self->_epoch) != generation) return;
            @try {
                id service = self->_factory ? self->_factory() : nil;
                if (!SIServiceCompatible(service)) {
                    [self deliver:(SIFocusSnapshot){NO, -1} generation:generation sequence:1]; return;
                }
                SIFocusListener *listener = [SIFocusListener new];
                listener.owner = self; listener.generation = generation;
                self->_service = service; self->_listener = listener;
                NSError *error = nil;
                BOOL subscribed = ((BOOL (*)(id, SEL, id, NSError **))objc_msgSend)(service,
                    NSSelectorFromString(@"addStateUpdateListener:error:"), listener, &error);
                if (!subscribed || error || atomic_load(&self->_epoch) != generation) {
                    [self clearSubscription];
                    [self deliver:(SIFocusSnapshot){NO, -1} generation:generation sequence:1]; return;
                }
                id state = ((id (*)(id, SEL, NSError **))objc_msgSend)(service,
                    NSSelectorFromString(@"queryCurrentStateWithError:"), &error);
                if (atomic_load(&listener->received) == 0) {
                    [self deliver:error ? (SIFocusSnapshot){NO, -1} : SIFocusSnapshotFromState(state)
                        generation:generation sequence:1];
                }
            } @catch (__unused NSException *exception) {
                [self clearSubscription];
                [self deliver:(SIFocusSnapshot){NO, -1} generation:generation sequence:1];
            }
        }
    });
}
- (void)stop {
    if (!NSThread.isMainThread || !_running) return;
    _running = NO;
    atomic_store(&_epoch, ++_generation);
    dispatch_async(_queue, ^{ [self clearSubscription]; });
}
- (void)receiveUpdate:(id)update service:(id)service listener:(SIFocusListener *)listener {
    uint64_t sequence = atomic_fetch_add(&listener->received, 1) + 2;
    uint64_t generation = listener.generation;
    SIFocusSnapshot snapshot = {NO, -1};
    @try { snapshot = SIFocusSnapshotFromState(SIReadObject(update, @"state")); }
    @catch (__unused NSException *exception) {}
    dispatch_async(_queue, ^{
        if (atomic_load(&self->_epoch) != generation || self->_listener != listener || self->_service != service) return;
        [self deliver:snapshot generation:generation sequence:sequence];
    });
}
- (void)dealloc {
    // Normally stop runs when the feature is disabled. Also release registrations
    // if an owner is destroyed; do not run private IPC on the deallocation thread.
    id service = _service;
    SIFocusListener *listener = _listener;
    if (service && listener) {
        dispatch_async(_queue, ^{
            @try {
                ((void (*)(id, SEL, id))objc_msgSend)(service,
                    NSSelectorFromString(@"removeStateUpdateListener:"), listener);
            } @catch (__unused NSException *exception) {}
        });
    }
}
@end
