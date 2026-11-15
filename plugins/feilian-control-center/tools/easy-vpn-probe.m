// Standalone iOS 16 feasibility probe. Never loaded into any App process.
// Does not enumerate credentials, write preferences, or replace another VPN.
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import "../VPNPrivate.h"

static NSString *const TargetBundle = @"com.qdtiktok.easyvpn";

static BOOL ConfirmUnlocked(void) {
    dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_NOW);
    mach_port_t (*serverPort)(void) = dlsym(RTLD_DEFAULT, "SBSSpringBoardServerPort");
    void (*query)(mach_port_t, BOOL *, BOOL *) = dlsym(RTLD_DEFAULT, "SBGetScreenLockStatus");
    if (!serverPort || !query) return NO;
    mach_port_t port = serverPort();
    if (port == MACH_PORT_NULL) return NO;
    BOOL locked = (BOOL)-1, passcode = (BOOL)-1;
    query(port, &locked, &passcode);
    printf("lock_state_known=%d unlocked=%d\n", locked == NO || locked == YES, locked == NO);
    return locked == NO && (passcode == NO || passcode == YES);
}

static NSArray *Connections(id store) {
    if (![store respondsToSelector:@selector(vpnServicesForCurrentSetWithGrade:)] ||
        ![store respondsToSelector:@selector(connectionWithServiceID:withGrade:)]) return nil;
    NSMutableArray *connections = [NSMutableArray array];
    for (NSUInteger grade = 0; grade < 4; grade++) {
        id services = [store vpnServicesForCurrentSetWithGrade:grade];
        if (![services isKindOfClass:NSArray.class]) return nil;
        for (id identifier in services) {
            id connection = [store connectionWithServiceID:identifier withGrade:grade];
            for (NSString *name in @[@"bundleID", @"connected", @"status",
                                    @"notDisconnectedOrDisconnecting", @"isProviderAvailable"]) {
                if (![connection respondsToSelector:NSSelectorFromString(name)]) return nil;
            }
            [connections addObject:connection];
        }
    }
    return connections;
}

static void Snapshot(id store, NSString *phase, NSTimeInterval started) {
    for (id connection in Connections(store)) {
        // No profile UUID, server address, options, credentials or account data.
        printf("phase=%s elapsed=%.3f target=%d status=%lu connected=%d active=%d available=%d\n",
            phase.UTF8String, NSDate.date.timeIntervalSince1970 - started,
            [[connection bundleID] isEqualToString:TargetBundle],
            (unsigned long)[connection status], [connection connected],
            [connection notDisconnectedOrDisconnecting], [connection isProviderAvailable]);
    }
    fflush(stdout);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *action = argc == 2 ? @(argv[1]) : @"--read";
        if (![@[@"--read", @"--connect", @"--disconnect"] containsObject:action]) return 2;
        NSError *error = nil;
        NSBundle *bundle = [NSBundle bundleWithPath:@"/System/Library/PreferenceBundles/VPNPreferences.bundle"];
        if (![bundle loadAndReturnError:&error]) { printf("vpn_framework_unavailable=1\n"); return 3; }
        Class storeClass = NSClassFromString(@"VPNConnectionStore");
        if (![storeClass respondsToSelector:@selector(sharedInstance)]) return 3;
        id store = [storeClass sharedInstance];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:2]];
        NSArray *connections = Connections(store);
        if (!connections) { printf("vpn_state_unavailable=1\n"); return 3; }
        NSTimeInterval started = NSDate.date.timeIntervalSince1970;
        Snapshot(store, @"before", started);
        if ([action isEqualToString:@"--read"]) { ConfirmUnlocked(); return 0; }
        NSMutableArray *matches = [NSMutableArray array];
        for (id connection in connections) {
            if ([[connection bundleID] isEqualToString:TargetBundle]) [matches addObject:connection];
            else if ([action isEqualToString:@"--connect"] && [connection notDisconnectedOrDisconnecting]) {
                printf("refused_other_vpn_active=1\n"); return 4;
            }
        }
        if (matches.count != 1) { printf("refused_target_count=%lu\n", (unsigned long)matches.count); return 4; }
        id target = matches.firstObject;
        SEL selector = [action isEqualToString:@"--connect"] ? @selector(connect) : @selector(disconnect);
        if (![target isProviderAvailable] || ![target respondsToSelector:selector] || !ConfirmUnlocked()) return 4;
        if (selector == @selector(connect) && [target notDisconnectedOrDisconnecting]) {
            printf("refused_target_already_active=1\n"); return 4;
        }
        id observer = [NSNotificationCenter.defaultCenter addObserverForName:@"VPNConnectionStatusChanged"
            object:nil queue:nil usingBlock:^(NSNotification *note) { Snapshot(store, @"event", started); }];
        if (selector == @selector(connect)) [target connect]; else [target disconnect];
        printf("action_dispatched=%s\n", action.UTF8String);
        Snapshot(store, @"dispatched", started);
        // Fixed observation window; status events, not a repeating polling loop.
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:15]];
        Snapshot(store, @"after", started);
        BOOL reached = selector == @selector(connect) ? [target connected] : ![target notDisconnectedOrDisconnecting];
        printf("target_reached=%d\n", reached);
        [NSNotificationCenter.defaultCenter removeObserver:observer];
        return reached ? 0 : 1;
    }
}
