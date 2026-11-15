// Regression-only: call the installed IPC client's probe, then concurrently close
// that one client twice. Never sends a connect/disconnect command.
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import "../../Shared/VPNIPC.h"
#import "RuntimeGuard.h"
#ifndef VPN_TEST_START_DELAY
#define VPN_TEST_START_DELAY 10
#endif
@interface NSObject (VPNStressLaunch)
+ (id)sharedService;
- (void)openApplication:(NSString *)identifier options:(NSDictionary *)options withResult:(void (^)(NSError *))result;
@end

static void Log(NSString *line) {
    NSString *path=@"/var/mobile/Library/Caches/ayao.vpn-assertion-stress.log";
    NSFileHandle *file=[NSFileHandle fileHandleForWritingAtPath:path];
    NSData *data=[[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    if(!file){[data writeToFile:path atomically:YES];return;}
    [file seekToEndOfFile];[file writeData:data];[file closeFile];
}
__attribute__((constructor)) static void Initialize(void) {
    if(![NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.springboard"])return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,VPN_TEST_START_DELAY*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        Dl_info info={0};if(!dladdr((void *)Initialize,&info)||!info.dli_fname)return;
        NSString *root=@(info.dli_fname);for(unsigned i=0;i<4;i++)root=root.stringByDeletingLastPathComponent;
        NSBundle *bundle=[NSBundle bundleWithPath:[root stringByAppendingPathComponent:@"Library/ControlCenter/Bundles/FeilianControlCenter.bundle"]];
        if(![bundle load]){Log(@"STRESS_BUNDLE_FAILED=1");return;}
        Class clientClass=NSClassFromString(@"VPNIPCClient");
        if(!clientClass){Log(@"STRESS_CLASS_UNAVAILABLE=1");return;}
        dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices",RTLD_NOW);
        NSString *const *key=(NSString *const *)dlsym(RTLD_DEFAULT,"FBSOpenApplicationOptionKeyActivateSuspended");
        id service=[NSClassFromString(@"FBSSystemService") sharedService];
        if(!key || !*key || !VPNTestSignature(service,@selector(openApplication:options:withResult:),5,"v")) {
            Log(@"STRESS_BACKGROUND_LAUNCH_UNAVAILABLE=1");return;
        }
        [service openApplication:@"com.qdtiktok.easyvpn" options:@{*key:@YES} withResult:^(NSError *error){
        if(error){Log(@"STRESS_BACKGROUND_LAUNCH_FAILED=1");return;}
        Log(@"STRESS_STARTED=1 iterations=10 operation=probe-only");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
            unsigned readyCount=0;
#ifdef VPN_TEST_LEASE_EXPIRY
            const unsigned iterations=2;
#else
            const unsigned iterations=10;
#endif
            for(unsigned iteration=0;iteration<iterations;iteration++) {
                @autoreleasepool {
                    VPNIPCClient *client=[[clientClass alloc] initWithProvider:@"easy"];
                    if(!VPNTestObjectMatches(client,@"VPNIPCClient",bundle.executablePath) ||
                       !VPNTestSignature(client,@selector(open),2,@encode(BOOL)) ||
                       !VPNTestSignature(client,@selector(probe),2,@encode(BOOL)) ||
                       !VPNTestSignature(client,@selector(close),2,"v")) {
                        Log(@"STRESS_CLIENT_CONTRACT_REJECTED=1");return;
                    }
                    BOOL ready=[client open] && [client probe];
                    if(ready)readyCount++;
                    Log([NSString stringWithFormat:@"ITERATION=%u ready=%d",iteration,ready]);
                    if(!ready){[client close];Log(@"STRESS_ACQUIRE_FAILED=1");return;}
#ifdef VPN_TEST_LEASE_EXPIRY
                    if(!ready){Log(@"LEASE_EXPIRY_PRECONDITION_FAILED=1");return;}
                    [NSThread sleepForTimeInterval:20];
                    BOOL stillOpen=[client probe];
                    Log([NSString stringWithFormat:@"ITERATION=%u lease_expired_closed=%d",iteration,!stillOpen]);
                    if(stillOpen){[client close];Log(@"LEASE_EXPIRY_FAILED=1");return;}
#endif
                    dispatch_group_t group=dispatch_group_create();
                    for(unsigned i=0;i<2;i++)dispatch_group_async(group,dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{[client close];});
                    if(dispatch_group_wait(group,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))) {
                        Log(@"STRESS_CLOSE_TIMEOUT=1");return;
                    }
                    // Drain the main-queue invalidation before the next acquire.
                    dispatch_sync(dispatch_get_main_queue(),^{});
                    if([client probe]){Log(@"STRESS_CLOSED_PROBE_FAILED=1");return;}
                    Log([NSString stringWithFormat:@"ITERATION=%u concurrent_close_completed=1",iteration]);
                }
                [NSThread sleepForTimeInterval:0.25];
            }
            Log([NSString stringWithFormat:@"ASSERTION_CLOSE_STRESS_DONE=1 ready_count=%u",readyCount]);
        });
        }];
    });
}
