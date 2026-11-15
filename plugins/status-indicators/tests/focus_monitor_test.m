#import "../SIFocusMonitor.h"
#import <objc/message.h>
#include <assert.h>

@interface SITestFocusState : NSObject
@property(nonatomic) BOOL active;
@property(nonatomic, copy) NSArray *identifiers;
@property(nonatomic, strong) id activeModeConfiguration;
- (BOOL)isActive;
- (NSArray *)activeModeIdentifiers;
@end
@implementation SITestFocusState
- (BOOL)isActive { return self.active; }
- (NSArray *)activeModeIdentifiers { return self.identifiers; }
@end
@interface SITestFocusUpdate : NSObject
@property(nonatomic, strong) id state;
@end
@implementation SITestFocusUpdate
@end
static SITestFocusState *State(BOOL active, NSArray *identifiers) {
    SITestFocusState *state = [SITestFocusState new];
    state.active = active; state.identifiers = identifiers;
    return state;
}
@interface SITestFocusMode : NSObject
@property(nonatomic, copy) NSString *modeIdentifier;
@property(nonatomic, strong) id symbolImageName;
@property(nonatomic, strong) id name;
@end
@implementation SITestFocusMode
@end
@interface SITestFocusConfiguration : NSObject
@property(nonatomic, strong) id mode;
@end
@implementation SITestFocusConfiguration
@end
@interface SITestBadSymbolABI : NSObject
- (NSInteger)symbolImageName;
@end
@implementation SITestBadSymbolABI
- (NSInteger)symbolImageName { return 1; }
@end
@interface SITestThrowingConfiguration : NSObject
- (id)mode;
@end
@implementation SITestThrowingConfiguration
- (id)mode { [NSException raise:@"fixture" format:@"unavailable getter"]; return nil; }
@end
static SITestFocusState *ConfiguredState(BOOL active, NSString *symbol) {
    SITestFocusMode *mode = [SITestFocusMode new];
    mode.modeIdentifier = @"fixture.opaque-mode-id"; mode.symbolImageName = symbol;
    SITestFocusConfiguration *configuration = [SITestFocusConfiguration new]; configuration.mode = mode;
    SITestFocusState *state = State(active, @[mode.modeIdentifier]);
    state.activeModeConfiguration = configuration;
    return state;
}
@interface SITestFocusService : NSObject
@property(atomic, strong) id listener;
@property(atomic, strong) id initialState;
@property(atomic, copy) void (^queryAction)(void);
@property(atomic) NSUInteger adds, removes, queries;
@property(atomic) BOOL rejectRegistration, queryFails;
- (BOOL)addStateUpdateListener:(id)listener error:(NSError **)error;
- (void)removeStateUpdateListener:(id)listener;
- (id)queryCurrentStateWithError:(NSError **)error;
- (void)emit:(id)state listener:(id)listener;
@end
@implementation SITestFocusService
- (BOOL)addStateUpdateListener:(id)listener error:(NSError **)error {
    assert(!NSThread.isMainThread);
    self.adds++;
    // Model APIs that retain even a rejected listener, requiring cleanup.
    self.listener = listener;
    if (self.rejectRegistration) {
        *error = [NSError errorWithDomain:@"test" code:1 userInfo:nil]; return NO;
    }
    return YES;
}
- (void)removeStateUpdateListener:(id)listener {
    assert(!NSThread.isMainThread);
    if (self.listener == listener) self.listener = nil;
    self.removes++;
}
- (id)queryCurrentStateWithError:(NSError **)error {
    assert(!NSThread.isMainThread);
    self.queries++;
    if (self.queryAction) self.queryAction();
    if (self.queryFails) { *error = [NSError errorWithDomain:@"test" code:2 userInfo:nil]; return nil; }
    return self.initialState;
}
- (void)emit:(id)state listener:(id)listener {
    SITestFocusUpdate *update = [SITestFocusUpdate new]; update.state = state;
    ((void (*)(id, SEL, id, id))objc_msgSend)(listener,
        NSSelectorFromString(@"stateService:didReceiveDoNotDisturbStateUpdate:"), self, update);
}
@end
@interface SITestBadABI : NSObject
- (NSInteger)isActive;
@end
@implementation SITestBadABI
- (NSInteger)isActive { return 1; }
@end

static void Wait(BOOL (^condition)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
    while (!condition() && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.002]];
    assert(condition());
}
static void Drain(void) {
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.03]];
}
static NSDictionary *Encoded(SIFocusSnapshot s) { return @{ @"known": @(s.known), @"style": @(s.style) }; }
int main(void) {
    @autoreleasepool {
        assert(NSThread.isMainThread);
        NSArray *modes = @[@"com.apple.donotdisturb.mode.default", @"com.apple.donotdisturb.mode.personal",
            @"com.apple.donotdisturb.mode.work", @"com.apple.donotdisturb.mode.gaming", @"custom.other"];
        for (NSUInteger i = 0; i < modes.count; i++) {
            SIFocusSnapshot s = SIFocusSnapshotFromState(State(YES, @[modes[i]]));
            assert(s.known && s.style == (NSInteger)i);
            s = SIFocusSnapshotFromState(State(NO, @[modes[i]]));
            assert(s.known && s.style == -1); // Inactive beats even stale identifiers.
        }
        assert(!SIFocusSnapshotFromState(nil).known);
        assert(!SIFocusSnapshotFromState([SITestBadABI new]).known);
        assert(SIFocusSnapshotFromState(State(YES, @[])).style == 4);
        assert(SIFocusSnapshotFromState(State(YES, @[@1, NSNull.null, @"custom.workout"])).style == 4);
        assert(SIFocusSnapshotFromState(State(YES, @[@"custom.work"])).style == 4);
        assert(SIFocusSnapshotFromState(State(YES, @[@"custom.other", modes[2]])).style == 2);

        NSArray *symbolGroups = @[
            @[@"moon", @"moon.fill"],
            @[@"person", @"person.fill", @"person.crop.circle", @"person.crop.circle.fill"],
            @[@"briefcase", @"briefcase.fill", @"person.lanyardcard", @"person.lanyardcard.fill"],
            @[@"gamecontroller", @"gamecontroller.fill"],
            @[@"sparkles", @"leaf.fill", @"custom.person.fill"]
        ];
        NSUInteger configurationCases = 0;
        for (NSUInteger i = 0; i < symbolGroups.count; i++) {
            for (NSString *symbol in symbolGroups[i]) {
                SITestFocusState *state = ConfiguredState(YES, symbol);
                // Current configuration wins over stale/ambiguous assertion identifiers.
                state.identifiers = @[modes[0]];
                SIFocusSnapshot snapshot = SIFocusSnapshotFromState(state);
                assert(snapshot.known && snapshot.style == (NSInteger)i);
                state.active = NO;
                snapshot = SIFocusSnapshotFromState(state);
                assert(snapshot.known && snapshot.style == -1);
                configurationCases += 2;
            }
        }
        SITestFocusState *missingSymbol = ConfiguredState(YES, nil);
        assert(SIFocusSnapshotFromState(missingSymbol).style == 4);
        ((SITestFocusMode *)((SITestFocusConfiguration *)missingSymbol.activeModeConfiguration).mode).symbolImageName = @1;
        assert(SIFocusSnapshotFromState(missingSymbol).style == 4);
        ((SITestFocusMode *)((SITestFocusConfiguration *)missingSymbol.activeModeConfiguration).mode).modeIdentifier = modes[2];
        assert(SIFocusSnapshotFromState(missingSymbol).style == 2);
        ((SITestFocusConfiguration *)missingSymbol.activeModeConfiguration).mode = [SITestBadSymbolABI new];
        assert(SIFocusSnapshotFromState(missingSymbol).style == 4);
        ((SITestFocusConfiguration *)missingSymbol.activeModeConfiguration).mode = nil;
        missingSymbol.identifiers = @[modes[1]];
        assert(SIFocusSnapshotFromState(missingSymbol).style == 1);
        missingSymbol.activeModeConfiguration = [SITestThrowingConfiguration new];
        assert(SIFocusSnapshotFromState(missingSymbol).style == 1);
        printf("PASS Focus configuration: %lu symbol/closed cases + 6 missing/type/ABI/fallback cases\n", (unsigned long)configurationCases);

        SITestFocusState *namedGame = ConfiguredState(YES, @"arrow.up.right");
        SITestFocusMode *gameMode = ((SITestFocusConfiguration *)namedGame.activeModeConfiguration).mode;
        gameMode.name = @"\u6e38\u620f";
        assert(SIFocusSnapshotFromState(namedGame).style == 3);
        namedGame.active = NO;
        assert(SIFocusSnapshotFromState(namedGame).style == -1);
        namedGame.active = YES; gameMode.symbolImageName = nil;
        assert(SIFocusSnapshotFromState(namedGame).style == 3);
        for (id nonGame in @[@"\u6e38\u620f\u65f6\u95f4", @"Gaming", @1, NSNull.null]) {
            gameMode.name = nonGame;
            assert(SIFocusSnapshotFromState(namedGame).style == 4);
        }
        gameMode.name = @"\u6e38\u620f"; gameMode.modeIdentifier = modes[2];
        assert(SIFocusSnapshotFromState(namedGame).style == 2); // Known system ID retains priority.
        gameMode.modeIdentifier = @"fixture.opaque-mode-id";
        puts("PASS Focus game name: exact local name, unknown/missing symbol, closed state, nonmatches/types, known ID priority (8 cases)");

        NSMutableArray *events = [NSMutableArray new];
        SITestFocusService *service = [SITestFocusService new];
        service.initialState = State(YES, @[modes[2]]);
        SIFocusMonitor *monitor = [[SIFocusMonitor alloc] initWithHandler:^(SIFocusSnapshot snapshot) {
            assert(NSThread.isMainThread); [events addObject:Encoded(snapshot)];
        } serviceFactory:^{ assert(!NSThread.isMainThread); return service; }];
        [monitor start]; [monitor start];
        Wait(^BOOL { return events.count == 1; });
        assert(service.adds == 1 && service.queries == 1 && [events.lastObject[@"style"] integerValue] == 2);
        NSUInteger queriesBeforeNamedGame = service.queries;
        [service emit:namedGame listener:service.listener];
        Wait(^BOOL { return events.count == 2; });
        assert([events.lastObject[@"style"] integerValue] == 3 && service.queries == queriesBeforeNamedGame);
        [events removeAllObjects];
        [service emit:State(YES, @[modes[2]]) listener:service.listener];
        Wait(^BOOL { return events.count == 1; });
        // Modes with opaque IDs use the same realtime callbacks, no extra query.
        NSUInteger startQueries = service.queries;
        NSArray *configuredModes = @[@"person.fill", @"person.lanyardcard.fill", @"gamecontroller.fill"];
        for (NSUInteger i = 0; i < configuredModes.count; i++) {
            NSUInteger count = events.count;
            [service emit:ConfiguredState(YES, configuredModes[i]) listener:service.listener];
            Wait(^BOOL { return events.count == count + 1; });
            assert([events.lastObject[@"style"] integerValue] == (NSInteger)i + 1);
        }
        [service emit:ConfiguredState(NO, configuredModes[2]) listener:service.listener];
        Wait(^BOOL { return events.count == 5; });
        assert([events.lastObject[@"style"] integerValue] == -1 && service.queries == startQueries);
        [events removeAllObjects];
        [service emit:ConfiguredState(NO, configuredModes[2]) listener:service.listener];
        Wait(^BOOL { return events.count == 1; });
        id oldListener = service.listener;
        // Four transitions and an explicit close never require UI/host events.
        for (NSString *mode in modes) [service emit:State(YES, @[mode]) listener:service.listener];
        [service emit:State(NO, @[modes[1]]) listener:service.listener];
        Wait(^BOOL { return events.count == 7; });
        assert([events.lastObject[@"known"] boolValue] && [events.lastObject[@"style"] integerValue] == -1);
        [service emit:nil listener:service.listener];
        Wait(^BOOL { return events.count == 8; });
        assert(![events.lastObject[@"known"] boolValue]);
        [monitor stop];
        [service emit:State(YES, @[modes[1]]) listener:oldListener];
        Wait(^BOOL { return service.removes == 1; }); Drain();
        assert(events.count == 8);

        // During initial query, a new close event arrives before stale active query returns.
        [events removeAllObjects];
        __weak SITestFocusService *weakService = service;
        service.queryAction = ^{
            SITestFocusService *current = weakService;
            [current emit:State(NO, @[]) listener:current.listener];
        };
        [monitor start];
        Wait(^BOOL { return events.count == 1; });
        assert([events.lastObject[@"known"] boolValue] && [events.lastObject[@"style"] integerValue] == -1);
        [service emit:State(YES, @[modes[0]]) listener:oldListener]; Drain();
        assert(events.count == 1); // A listener from the old generation cannot resurrect state.
        [monitor stop]; Wait(^BOOL { return service.removes == 2; });
        service.queryAction = nil;

        // Query failures are unknown, not an explicit close; valid later callbacks recover.
        [events removeAllObjects]; service.queryFails = YES;
        [monitor start]; Wait(^BOOL { return events.count == 1; });
        assert(![events.lastObject[@"known"] boolValue]);
        [service emit:State(YES, @[modes[1]]) listener:service.listener];
        Wait(^BOOL { return events.count == 2; });
        assert([events.lastObject[@"style"] integerValue] == 1);
        [monitor stop]; Wait(^BOOL { return service.removes == 3; });

        [events removeAllObjects]; service.rejectRegistration = YES;
        NSUInteger queries = service.queries;
        [monitor start]; Wait(^BOOL { return events.count == 1; });
        assert(![events.lastObject[@"known"] boolValue] && service.queries == queries);
        assert(service.listener == nil && service.removes == 4);
        [monitor stop]; Drain();

        // Wrong service capability fails closed before private method invocation.
        __block BOOL incompatibleDelivered = NO;
        SIFocusMonitor *unsupported = [[SIFocusMonitor alloc] initWithHandler:^(SIFocusSnapshot s) {
            assert(!s.known); incompatibleDelivered = YES;
        } serviceFactory:^{ return [NSObject new]; }];
        [unsupported start]; Wait(^BOOL { return incompatibleDelivered; });
        [unsupported stop]; Drain();

        // Starting then immediately stopping cancels queued initial delivery.
        __block NSUInteger cancelledEvents = 0;
        SITestFocusService *cancelledService = [SITestFocusService new];
        cancelledService.initialState = State(YES, @[modes[0]]);
        SIFocusMonitor *cancelled = [[SIFocusMonitor alloc] initWithHandler:^(__unused SIFocusSnapshot s) {
            cancelledEvents++;
        } serviceFactory:^{ return cancelledService; }];
        [cancelled start]; [cancelled stop]; Drain();
        assert(cancelledEvents == 0 && cancelledService.listener == nil);

        // Destruction of an active owner unregisters without blocking main.
        SITestFocusService *deallocatedService = [SITestFocusService new];
        deallocatedService.initialState = State(NO, @[]);
        __weak SIFocusMonitor *releasedMonitor;
        @autoreleasepool {
            SIFocusMonitor *temporary = [[SIFocusMonitor alloc] initWithHandler:^(__unused SIFocusSnapshot s) {}
                serviceFactory:^{ return deallocatedService; }];
            releasedMonitor = temporary; [temporary start];
            Wait(^BOOL { return deallocatedService.queries == 1; }); Drain();
        }
        Wait(^BOOL { return releasedMonitor == nil && deallocatedService.removes == 1; });
        puts("PASS Focus: mode parsing, inactive/unknown distinction, subscription lifecycle, query-event race, stale generation, failures and callback recovery");
    }
    return 0;
}
