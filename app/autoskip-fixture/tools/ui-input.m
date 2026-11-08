#import <Foundation/Foundation.h>
#import <CFNetwork/CFNetwork.h>
#import <dlfcn.h>
#import <ifaddrs.h>
#import <math.h>
#import <mach/mach.h>
#import <mach/mach_time.h>
#import <sys/socket.h>
#import <stdio.h>
#import <string.h>
#import <unistd.h>

typedef CFTypeRef SDPHIDEvent;
typedef CFTypeRef SDPHIDClient;

@interface NSObject (SDPDisplayLayoutObservation)
+ (id)configurationForDefaultMainDisplayMonitor;
+ (id)monitorWithConfiguration:(id)configuration;
- (void)setTransitionHandler:(id)handler;
- (void)invalidate;
- (id)currentLayout;
- (NSArray *)elements;
- (BOOL)isUIApplicationElement;
- (NSString *)bundleIdentifier;
- (BOOL)hasKeyboardFocus;
@end

extern SDPHIDClient IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern void IOHIDEventSystemClientDispatchEvent(SDPHIDClient client, SDPHIDEvent event);
extern SDPHIDEvent IOHIDEventCreateDigitizerEvent(CFAllocatorRef allocator, uint64_t timestamp,
    uint32_t type, uint32_t index, uint32_t identity, uint32_t mask, uint32_t buttons,
    double horizontal, double vertical, double depth, double pressure, double barrelPressure,
    Boolean range, Boolean touch, uint32_t options);
extern SDPHIDEvent IOHIDEventCreateDigitizerFingerEvent(CFAllocatorRef allocator, uint64_t timestamp,
    uint32_t index, uint32_t identity, uint32_t mask, double horizontal, double vertical,
    double depth, double pressure, double twist, Boolean range, Boolean touch, uint32_t options);
extern SDPHIDEvent IOHIDEventCreateKeyboardEvent(CFAllocatorRef allocator, uint64_t timestamp,
    uint16_t usagePage, uint16_t usage, Boolean down, uint32_t options);
extern void IOHIDEventAppendEvent(SDPHIDEvent parent, SDPHIDEvent child);
extern void IOHIDEventSetIntegerValue(SDPHIDEvent event, uint32_t field, CFIndex value);
extern void IOHIDEventSetSenderID(SDPHIDEvent event, uint64_t sender);

static NSArray<NSString *> *SDPStringDictionaryKeys(NSDictionary *dictionary) {
    NSMutableArray<NSString *> *keys = [NSMutableArray array];
    for (id key in dictionary) {
        if ([key isKindOfClass:NSString.class]) {
            [keys addObject:key];
        }
    }
    return [keys sortedArrayUsingSelector:@selector(compare:)];
}

static NSArray<NSString *> *SDPInterfaceNames(void) {
    struct ifaddrs *interfaces = NULL;
    if (getifaddrs(&interfaces) != 0) {
        return @[];
    }
    NSMutableSet<NSString *> *names = [NSMutableSet set];
    for (struct ifaddrs *cursor = interfaces; cursor != NULL; cursor = cursor->ifa_next) {
        if (cursor->ifa_name == NULL || cursor->ifa_addr == NULL) {
            continue;
        }
        sa_family_t family = cursor->ifa_addr->sa_family;
        if (family != AF_INET && family != AF_INET6) {
            continue;
        }
        NSString *name = @(cursor->ifa_name);
        if (name.length > 0) {
            [names addObject:name];
        }
    }
    freeifaddrs(interfaces);
    return [[names allObjects] sortedArrayUsingSelector:@selector(compare:)];
}

static int SDPPrintNetworkStatus(void) {
    NSDictionary *settings = CFBridgingRelease(CFNetworkCopySystemProxySettings());
    if (![settings isKindOfClass:NSDictionary.class]) {
        settings = @{};
    }
    NSDictionary *scoped = settings[@"__SCOPED__"];
    if (![scoped isKindOfClass:NSDictionary.class]) {
        scoped = @{};
    }
    NSArray<NSString *> *scopedNames = SDPStringDictionaryKeys(scoped);
    NSMutableArray<NSString *> *matches = [NSMutableArray array];
    for (NSString *name in scopedNames) {
        if ([name containsString:@"tap"] || [name containsString:@"tun"] || [name containsString:@"ppp"]) {
            [matches addObject:name];
        }
    }
    NSDictionary *report = @{
        @"interfaces": SDPInterfaceNames(),
        @"proxy_top_level_keys": SDPStringDictionaryKeys(settings),
        @"scoped_interface_names": scopedNames,
        @"damai_vpn_matches": matches,
        @"damai_use_vpn_result": @(matches.count > 0),
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingSortedKeys error:nil];
    if (data == nil || fwrite(data.bytes, 1, data.length, stdout) != data.length) {
        return 1;
    }
    fputc('\n', stdout);
    return 0;
}

static BOOL SDPDispatchPoint(SDPHIDClient client, double horizontal, double vertical, uint32_t mask, BOOL down) {
    uint64_t timestamp = mach_absolute_time();
    SDPHIDEvent hand = IOHIDEventCreateDigitizerEvent(kCFAllocatorDefault, timestamp,
        3, 1, 1, mask, 0, horizontal, vertical, 0, 0, 0, down, down, 0);
    SDPHIDEvent finger = IOHIDEventCreateDigitizerFingerEvent(kCFAllocatorDefault, timestamp,
        1, 1, mask, horizontal, vertical, 0, 0, 0, down, down, 0);
    if (!hand || !finger) {
        if (hand) CFRelease(hand);
        if (finger) CFRelease(finger);
        return NO;
    }
    IOHIDEventSetIntegerValue(hand, 4, 1);
    IOHIDEventSetIntegerValue(hand, 0x000b0019, 1);
    IOHIDEventSetIntegerValue(hand, 0x000b0016, 1);
    IOHIDEventSetSenderID(hand, 0x8000000817319372);
    IOHIDEventAppendEvent(hand, finger);
    IOHIDEventSystemClientDispatchEvent(client, hand);
    CFRelease(finger);
    CFRelease(hand);
    return YES;
}

static BOOL SDPParseCoordinate(const char *text, double *output) {
    char *end = NULL;
    *output = strtod(text, &end);
    return end != text && *end == '\0' && isfinite(*output) && *output >= 0 && *output <= 1;
}

static BOOL SDPReadLockState(BOOL *locked, BOOL *passcodeEnabled) {
    mach_port_t (*serverPort)(void) = dlsym(RTLD_DEFAULT, "SBSSpringBoardServerPort");
    void (*queryLockState)(mach_port_t, BOOL *, BOOL *) = dlsym(RTLD_DEFAULT, "SBGetScreenLockStatus");
    if (!serverPort || !queryLockState) {
        return NO;
    }
    mach_port_t port = serverPort();
    if (port == MACH_PORT_NULL) {
        return NO;
    }
    BOOL observedLocked = (BOOL)-1;
    BOOL observedPasscodeEnabled = (BOOL)-1;
    queryLockState(port, &observedLocked, &observedPasscodeEnabled);
    if ((observedLocked != NO && observedLocked != YES) ||
        (observedPasscodeEnabled != NO && observedPasscodeEnabled != YES)) {
        return NO;
    }
    *locked = observedLocked;
    *passcodeEnabled = observedPasscodeEnabled;
    return YES;
}

static BOOL SDPConfirmUnlocked(void) {
    BOOL locked = YES;
    BOOL passcodeEnabled = YES;
    return SDPReadLockState(&locked, &passcodeEnabled) && locked == NO;
}

static int SDPWakeWithPowerButtonWithoutPasscode(void) {
    BOOL locked = YES;
    BOOL passcodeEnabled = YES;
    if (!SDPReadLockState(&locked, &passcodeEnabled)) {
        fprintf(stderr, "lock_state_not_observed_no_input_dispatched\n");
        return 8;
    }
    if (!locked) {
        fprintf(stdout, "already_unlocked_no_input_dispatched\n");
        return 0;
    }
    if (passcodeEnabled) {
        fprintf(stderr, "passcode_enabled_wake_refused\n");
        return 9;
    }
    SDPHIDClient client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (!client) {
        fprintf(stderr, "hid_client_unavailable\n");
        return 5;
    }
    SDPHIDEvent down = IOHIDEventCreateKeyboardEvent(kCFAllocatorDefault, mach_absolute_time(),
        0x0c, 0x30, YES, 0);
    SDPHIDEvent up = IOHIDEventCreateKeyboardEvent(kCFAllocatorDefault, mach_absolute_time(),
        0x0c, 0x30, NO, 0);
    if (!down || !up) {
        if (down) CFRelease(down);
        if (up) CFRelease(up);
        CFRelease(client);
        fprintf(stderr, "power_button_event_creation_failed\n");
        return 6;
    }
    IOHIDEventSetSenderID(down, 0x8000000817319372);
    IOHIDEventSetSenderID(up, 0x8000000817319372);
    IOHIDEventSystemClientDispatchEvent(client, down);
    usleep(80000);
    IOHIDEventSystemClientDispatchEvent(client, up);
    CFRelease(down);
    CFRelease(up);
    CFRelease(client);
    fprintf(stdout, "power_button_wake_requested_no_unlock\n");
    return 0;
}

static int SDPUnlockWithoutPasscode(void) {
    BOOL locked = YES;
    BOOL passcodeEnabled = YES;
    if (!SDPReadLockState(&locked, &passcodeEnabled)) {
        fprintf(stderr, "lock_state_not_observed_no_input_dispatched\n");
        return 8;
    }
    if (!locked) {
        fprintf(stdout, "already_unlocked_no_input_dispatched\n");
        return 0;
    }
    if (passcodeEnabled) {
        fprintf(stderr, "passcode_enabled_unlock_refused\n");
        return 9;
    }
    int wakeResult = SDPWakeWithPowerButtonWithoutPasscode();
    if (wakeResult != 0) {
        return wakeResult;
    }
    usleep(600000);
    if (!SDPReadLockState(&locked, &passcodeEnabled) || !locked || passcodeEnabled) {
        fprintf(stderr, "lock_state_changed_no_input_dispatched\n");
        return 11;
    }
    SDPHIDClient client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (!client) {
        fprintf(stderr, "hid_client_unavailable\n");
        return 5;
    }
    const double horizontal = 0.5;
    const double verticalStart = 0.9;
    const double verticalEnd = 0.2;
    BOOL dispatched = SDPDispatchPoint(client, horizontal, verticalStart, 0x23, YES);
    usleep(70000);
    for (NSUInteger step = 1; step <= 12 && dispatched; step++) {
        double fraction = (double)step / 12;
        dispatched = SDPDispatchPoint(client, horizontal,
            verticalStart + (verticalEnd - verticalStart) * fraction, 0x04, YES);
        usleep(20000);
    }
    usleep(250000);
    BOOL released = SDPDispatchPoint(client, horizontal, verticalEnd, 0x27, NO);
    CFRelease(client);
    if (!dispatched || !released) {
        fprintf(stderr, "input_event_creation_failed\n");
        return 6;
    }
    usleep(700000);
    if (!SDPReadLockState(&locked, &passcodeEnabled) || locked) {
        fprintf(stderr, "unlock_not_confirmed_after_input\n");
        return 12;
    }
    fprintf(stdout, "wake_and_unlock_without_passcode_confirmed\n");
    return 0;
}

static BOOL SDPConfirmDisplayLayout(NSString *expectedBundle) {
    Class monitorClass = NSClassFromString(@"FBSDisplayLayoutMonitor");
    Class configurationClass = NSClassFromString(@"FBSDisplayLayoutMonitorConfiguration");
    if (![monitorClass respondsToSelector:@selector(monitorWithConfiguration:)] ||
        ![configurationClass respondsToSelector:@selector(configurationForDefaultMainDisplayMonitor)]) {
        fprintf(stderr, "display_layout_monitor_unavailable\n");
        return NO;
    }
    id configuration = [configurationClass configurationForDefaultMainDisplayMonitor];
    if (![configuration respondsToSelector:@selector(setTransitionHandler:)]) {
        fprintf(stderr, "display_layout_subscription_unavailable\n");
        return NO;
    }
    [configuration setTransitionHandler:^(id context) { (void)context; }];
    id monitor = [monitorClass monitorWithConfiguration:configuration];
    if (![monitor respondsToSelector:@selector(currentLayout)] ||
        ![monitor respondsToSelector:@selector(invalidate)]) {
        fprintf(stderr, "display_layout_query_unavailable\n");
        return NO;
    }
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
    id layout = [monitor currentLayout];
    [monitor invalidate];
    if (![layout respondsToSelector:@selector(elements)]) {
        fprintf(stderr, "display_layout_not_observed\n");
        return NO;
    }
    NSArray *elements = [layout elements];
    if (![elements isKindOfClass:NSArray.class] || elements.count > 32) {
        return NO;
    }
    NSUInteger focusedApplicationCount = 0;
    BOOL expectedFound = NO;
    for (id element in elements) {
        if (![element respondsToSelector:@selector(isUIApplicationElement)] ||
            ![element respondsToSelector:@selector(bundleIdentifier)] ||
            ![element respondsToSelector:@selector(hasKeyboardFocus)]) {
            return NO;
        }
        if ([element isUIApplicationElement] && [element hasKeyboardFocus]) {
            focusedApplicationCount++;
            expectedFound = [[element bundleIdentifier] isEqualToString:expectedBundle];
        }
    }
    fprintf(stderr, "display_layout_focused_application_count=%lu\n", (unsigned long)focusedApplicationCount);
    return focusedApplicationCount == 1 && expectedFound;
}

static BOOL SDPConfirmFrontmost(NSString *expectedBundle) {
    NSString *(*frontmostIdentifier)(void) = dlsym(RTLD_DEFAULT, "SBSCopyFrontmostApplicationDisplayIdentifier");
    NSString *observedBundle = frontmostIdentifier ? frontmostIdentifier() : nil;
    if (observedBundle.length > 0) {
        return [observedBundle isEqualToString:expectedBundle];
    }
    mach_port_t (*serverPort)(void) = dlsym(RTLD_DEFAULT, "SBSSpringBoardServerPort");
    void (*queryFrontmost)(mach_port_t, char *) = dlsym(RTLD_DEFAULT, "SBFrontmostApplicationDisplayIdentifier");
    if (!serverPort || !queryFrontmost) {
        fprintf(stderr, "frontmost_query_unavailable\n");
        return NO;
    }
    mach_port_t port = serverPort();
    if (port == MACH_PORT_NULL) {
        fprintf(stderr, "frontmost_server_port_unavailable\n");
        return NO;
    }
    char identifier[1024] = {0};
    queryFrontmost(port, identifier);
    if (strnlen(identifier, sizeof(identifier)) == sizeof(identifier) || identifier[0] == '\0') {
        fprintf(stderr, "frontmost_query_returned_no_identifier\n");
        return SDPConfirmDisplayLayout(expectedBundle);
    }
    return [[NSString stringWithUTF8String:identifier] isEqualToString:expectedBundle];
}

int main(int argumentCount, char *arguments[]) {
    @autoreleasepool {
        if (argumentCount == 2 && !strcmp(arguments[1], "--network-status")) {
            return SDPPrintNetworkStatus();
        }
#ifdef SDP_ASG_FIXTURE_UI
        NSArray *allowedBundles = @[@"ayao.autoskip.fixture", @"ayao.autoskip.originalfixture", @"com.opa334.TrollStore"];
#elif defined(SDP_ALI_RESTORE_UI)
        NSArray *allowedBundles = @[@"com.apple.AppStore", @"com.roothide.manager"];
#elif defined(SDP_COUPON_TEST_UI)
        NSArray *allowedBundles = @[@"com.apple.mobilesafari", @"com.taobao.taobao4iphone"];
#elif defined(SDP_QUNAR_TEST_UI)
        NSArray *allowedBundles = @[@"com.qunar.iphoneclient8"];
#elif defined(SDP_TROLLSTORE_UI)
        NSArray *allowedBundles = @[@"com.opa334.TrollStore"];
#elif defined(SDP_ROOTHIDE_UI)
        NSArray *allowedBundles = @[@"com.roothide.manager"];
#elif defined(SDP_SETTINGS_UI)
        NSArray *allowedBundles = @[@"com.apple.Preferences"];
#elif defined(SDP_DAMAI_TEST_UI)
        NSArray *allowedBundles = @[@"cn.damai.iphone", @"wiki.qaq.TrollFools"];
#else
        NSArray *allowedBundles = @[@"com.apple.Preferences", @"com.taobao.taobao4iphone"];
#endif
        NSArray *checkBundles = [allowedBundles arrayByAddingObject:@"cn.damai.iphone"];
        if (argumentCount == 2 && !strcmp(arguments[1], "--wake-power-button-no-passcode")) {
            return SDPWakeWithPowerButtonWithoutPasscode();
        }
        if (argumentCount == 2 && !strcmp(arguments[1], "--unlock-no-passcode")) {
            return SDPUnlockWithoutPasscode();
        }
        if (argumentCount == 3 && !strcmp(arguments[1], "--check") &&
            [checkBundles containsObject:@(arguments[2])]) {
            NSDictionary *state = @{@"unlocked_confirmed": @(SDPConfirmUnlocked()),
                @"expected_frontmost_confirmed": @(SDPConfirmFrontmost(@(arguments[2]))),
                @"input_dispatched": @NO};
            NSData *data = [NSJSONSerialization dataWithJSONObject:state options:NSJSONWritingSortedKeys error:nil];
            fwrite(data.bytes, 1, data.length, stdout);
            fputc('\n', stdout);
            return 0;
        }
        if (argumentCount != 5 && argumentCount != 7) {
            fprintf(stderr, "usage: ui-input --wake-power-button-no-passcode | --unlock-no-passcode | tap <frontmost-bundle> <x> <y> | swipe <frontmost-bundle> <x1> <y1> <x2> <y2>\n");
            return 1;
        }
        NSString *operation = @(arguments[1]);
        NSString *expectedBundle = @(arguments[2]);
        BOOL validOperation = ([operation isEqualToString:@"tap"] && argumentCount == 5) ||
                              ([operation isEqualToString:@"swipe"] && argumentCount == 7);
        if (![allowedBundles containsObject:expectedBundle] ||
            !validOperation) {
            fprintf(stderr, "operation_or_frontmost_not_allowed\n");
            return 2;
        }
        double horizontalStart, verticalStart, horizontalEnd, verticalEnd;
        if (!SDPParseCoordinate(arguments[3], &horizontalStart) || !SDPParseCoordinate(arguments[4], &verticalStart)) {
            fprintf(stderr, "invalid_normalized_coordinates\n");
            return 3;
        }
        horizontalEnd = horizontalStart;
        verticalEnd = verticalStart;
        if (argumentCount == 7 && (!SDPParseCoordinate(arguments[5], &horizontalEnd) ||
                                  !SDPParseCoordinate(arguments[6], &verticalEnd))) {
            fprintf(stderr, "invalid_normalized_coordinates\n");
            return 3;
        }
        if (!SDPConfirmUnlocked()) {
            fprintf(stderr, "unlocked_state_not_confirmed_no_input_dispatched\n");
            return 7;
        }
        if (!SDPConfirmFrontmost(expectedBundle)) {
            fprintf(stderr, "frontmost_not_confirmed_no_input_dispatched\n");
            return 4;
        }
        if (!SDPConfirmUnlocked()) {
            fprintf(stderr, "unlocked_state_changed_no_input_dispatched\n");
            return 7;
        }
        SDPHIDClient client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
        if (!client) {
            fprintf(stderr, "hid_client_unavailable\n");
            return 5;
        }
        BOOL dispatched = SDPDispatchPoint(client, horizontalStart, verticalStart, 0x23, YES);
        usleep(70000);
        if ([operation isEqualToString:@"swipe"]) {
            for (NSUInteger step = 1; step <= 12 && dispatched; step++) {
                double fraction = (double)step / 12;
                dispatched = SDPDispatchPoint(client, horizontalStart + (horizontalEnd - horizontalStart) * fraction,
                    verticalStart + (verticalEnd - verticalStart) * fraction, 0x04, YES);
                usleep(20000);
            }
            usleep(250000);
            if (dispatched) {
                dispatched = SDPDispatchPoint(client, horizontalEnd, verticalEnd, 0x04, YES);
            }
            usleep(50000);
        }
        BOOL released = SDPDispatchPoint(client, horizontalEnd, verticalEnd, 0x27, NO);
        CFRelease(client);
        if (!dispatched || !released) {
            fprintf(stderr, "input_event_creation_failed\n");
            return 6;
        }
        fprintf(stdout, "input_requested_verify_with_screenshot\n");
        return 0;
    }
}
