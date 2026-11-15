// Independent foreground/background entry probe. Does not inject or click UI.
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import "../VPNPrivate.h"
@interface NSObject (VPNAppEntry)
+ (id)sharedService;
- (void)openApplication:(NSString *)identifier options:(NSDictionary *)options withResult:(void (^)(NSError *))result;
@end

static NSString *const Apps[] = {@"co.hotspot.vpn.security", @"com.bestapp.gofast.vpn", @"com.zenith.jump"};
static NSArray *Read(id store) {
    NSMutableArray *result = [NSMutableArray array];
    for (NSUInteger grade = 0; grade < 4; grade++) {
        id identifiers = [store vpnServicesForCurrentSetWithGrade:grade];
        if (![identifiers isKindOfClass:NSArray.class]) return nil;
        for (id identifier in identifiers) {
            id connection = [store connectionWithServiceID:identifier withGrade:grade];
            if (![connection respondsToSelector:@selector(bundleID)] || ![connection respondsToSelector:@selector(connected)] ||
                ![connection respondsToSelector:@selector(notDisconnectedOrDisconnecting)]) return nil;
            [result addObject:connection];
        }
    }
    return result;
}
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2 || argc > 3) return 2;
        NSString *bundle = @(argv[1]);
        if (![[@[Apps[0],Apps[1],Apps[2]] copy] containsObject:bundle]) return 2;
        if (![[NSBundle bundleWithPath:@"/System/Library/PreferenceBundles/VPNPreferences.bundle"] load]) return 3;
        id store = [NSClassFromString(@"VPNConnectionStore") sharedInstance];
        Read(store); [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:3]];
        NSArray *connections = Read(store);
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
        if (!connections) return 3;
        for (id connection in connections) if ([connection notDisconnectedOrDisconnecting] && ![[connection bundleID] isEqual:bundle]) {
            puts("REFUSED_OTHER_ACTIVE=1"); return 4;
        }
        dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_NOW);
        mach_port_t (*port)(void) = dlsym(RTLD_DEFAULT,"SBSSpringBoardServerPort");
        void (*lock)(mach_port_t,BOOL *,BOOL *) = dlsym(RTLD_DEFAULT,"SBGetScreenLockStatus");
        BOOL locked = YES, passcode = YES;
        if (!port || !lock || port()==MACH_PORT_NULL) return 4;
        lock(port(),&locked,&passcode); if (locked) { puts("REFUSED_LOCKED=1"); return 4; }
        dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_NOW);
        BOOL background = argc == 3 && !strcmp(argv[2], "--background");
        NSDictionary *options = @{};
        if (background) {
            NSString *const *key = (NSString *const *)dlsym(RTLD_DEFAULT,"FBSOpenApplicationOptionKeyActivateSuspended");
            if (!key || !*key) return 3; options = @{*key:@YES};
        }
        id service = [NSClassFromString(@"FBSSystemService") sharedService];
        if (![service respondsToSelector:@selector(openApplication:options:withResult:)]) return 3;
        [service openApplication:bundle options:options withResult:^(NSError *error) { printf("launch_error=%ld background=%d\n", (long)error.code,background); }];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:20]];
        BOOL connected = NO;
        for (id connection in Read(store)) if ([[connection bundleID] isEqual:bundle]) {
            connected = [connection connected]; printf("target_connected=%d active=%d\n",connected,[connection notDisconnectedOrDisconnecting]);
        }
        return connected ? 0 : 1;
    }
}
