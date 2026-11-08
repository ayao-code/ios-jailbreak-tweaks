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
- (NSString *)identifier;
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
    BOOL springBoardFound = NO;
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
        if ([expectedBundle isEqualToString:@"com.apple.springboard"]) {
            fprintf(stderr, "system_layout_element=%s ui=%d focus=%d\n", [[element bundleIdentifier] UTF8String], [element isUIApplicationElement], [element hasKeyboardFocus]);
            NSString *identifier = [element respondsToSelector:@selector(identifier)] ? [element identifier] : nil;
            fprintf(stderr, "system_layout_identifier=%s\n", identifier.UTF8String);
            if ([identifier isEqualToString:@"com.apple.control-center"]) springBoardFound = YES;
        }
    }
    fprintf(stderr, "display_layout_focused_application_count=%lu\n", (unsigned long)focusedApplicationCount);
    return (focusedApplicationCount == 1 && expectedFound) ||
        ([expectedBundle isEqualToString:@"com.apple.springboard"] && focusedApplicationCount == 0 && springBoardFound);
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

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSArray *allowed = @[@"com.volcengine.corplink", @"com.apple.Preferences", @"com.apple.springboard"];
        if (argc == 3 && !strcmp(argv[1], "--check") && [allowed containsObject:@(argv[2])]) {
            NSDictionary *state = @{@"unlocked_confirmed": @(SDPConfirmUnlocked()),
                @"expected_frontmost_confirmed": @(SDPConfirmFrontmost(@(argv[2]))), @"input_dispatched": @NO};
            NSData *data = [NSJSONSerialization dataWithJSONObject:state options:NSJSONWritingSortedKeys error:nil];
            fwrite(data.bytes, 1, data.length, stdout); fputc('\n', stdout); return 0;
        }
        if (argc != 5 && argc != 7) return 2;
        BOOL swipe = !strcmp(argv[1], "swipe") && argc == 7;
        BOOL tap = !strcmp(argv[1], "tap") && argc == 5;
        NSString *expected = @(argv[2]);
        if ((!swipe && !tap) || ![allowed containsObject:expected]) return 2;
        double x1, y1, x2, y2;
        if (!SDPParseCoordinate(argv[3], &x1) || !SDPParseCoordinate(argv[4], &y1)) return 3;
        x2 = x1; y2 = y1;
        if (swipe && (!SDPParseCoordinate(argv[5], &x2) || !SDPParseCoordinate(argv[6], &y2))) return 3;
        if (!SDPConfirmUnlocked() || !SDPConfirmFrontmost(expected) || !SDPConfirmUnlocked()) return 4;
        SDPHIDClient client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
        if (!client) return 5;
        BOOL sent = SDPDispatchPoint(client, x1, y1, 0x23, YES);
        usleep(70000);
        if (swipe) for (NSUInteger step = 1; step <= 12 && sent; step++) {
            double f = (double)step / 12;
            sent = SDPDispatchPoint(client, x1 + (x2-x1)*f, y1 + (y2-y1)*f, 0x04, YES);
            usleep(20000);
        }
        BOOL released = SDPDispatchPoint(client, x2, y2, 0x27, NO);
        CFRelease(client);
        puts("input_requested_verify_with_screenshot");
        return sent && released ? 0 : 6;
    }
}
