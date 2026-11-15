// Standalone caller is intentionally NOT SpringBoard; it must be rejected.
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import "../Shared/VPNIPC.h"
#import <notify.h>
#import <sys/stat.h>
#import <unistd.h>
@interface NSObject (VPNBoundaryLaunch)
+ (id)sharedService;
- (void)openApplication:(NSString *)identifier options:(NSDictionary *)options withResult:(void (^)(NSError *))result;
@end
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *provider = argc == 2 || argc == 3 ? @(argv[1]) : nil;
        if (!VPNBundle(provider)) return 2;
        if (argc == 3 && !strcmp(argv[2], "--path")) {
            NSString *path = VPNIPCSocketPath(provider); if (!path) return 3;
            puts(path.fileSystemRepresentation); return 0;
        }
        if (argc == 3 && !strcmp(argv[2], "--cleanup")) {
            NSString *path = VPNIPCSocketPath(provider);
            struct stat st;
            if (!path) return 3;
            if (lstat(path.fileSystemRepresentation, &st)) return 0;
            if (!S_ISSOCK(st.st_mode) || st.st_uid != 501) return 4;
            BOOL removed = unlink(path.fileSystemRepresentation) == 0;
            printf("test_socket_removed=%d\n", removed); return removed ? 0 : 5;
        }
        dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_NOW);
        NSString *const *key = (NSString *const *)dlsym(RTLD_DEFAULT, "FBSOpenApplicationOptionKeyActivateSuspended");
        id service = [NSClassFromString(@"FBSSystemService") sharedService];
        if (!key || !*key || ![service respondsToSelector:@selector(openApplication:options:withResult:)]) return 3;
        [service openApplication:VPNBundle(provider) options:@{*key:@YES} withResult:^(NSError *error) { printf("launch_error=%ld\n", (long)error.code); }];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:2]];
        VPNIPCClient *client = [[VPNIPCClient alloc] initWithProvider:provider];
        BOOL opened = [client open]; BOOL ready = opened && [client probe]; [client close];
        printf("socket_opened=%d unauthorized_probe_rejected=%d\n", opened, !ready);
        int token; uint64_t stage = 0;
        NSString *name = [NSString stringWithFormat:@"ayao.vpn.%@.diagnostic-stage.v1", provider];
        if (notify_register_check(name.UTF8String, &token) == NOTIFY_STATUS_OK) {
            notify_get_state(token, &stage); notify_cancel(token);
        }
        printf("diagnostic_stage=%llu\n", stage);
        return opened && !ready ? 0 : 1;
    }
}
