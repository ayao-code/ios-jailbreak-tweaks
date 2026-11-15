// Disposable SpringBoard acceptance harness, NOT included in the shipping package.
// Commands arrive through a task-local file after a diagnostic notification.
// It calls the installed module, not copied VPN business implementations.
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <notify.h>
#import "../../VPNModuleViewController.h"
#import "../../VPNPrivate.h"
#import "RuntimeGuard.h"
@interface NSObject (VPNLocalTest)
- (id)contentViewController;
+ (id)sharedInstance;
+ (id)sharedController;
- (BOOL)isUILocked;
- (BOOL)isPasscodeSet;
- (void)lockScreenViewControllerRequestsUnlock;
@end
static id Module;
static VPNModuleViewController *View;
static AYAVPNController *Controller;
static int Token=NOTIFY_TOKEN_INVALID;
static NSString *OriginalPreference;
static NSString *RequestID;
static BOOL Stopped;
static NSArray *Providers(void) {return @[@"easy",@"feilian",@"hotspot",@"gofast",@"jump"];}
static NSString *BundleFor(NSString *provider) {return @{@"easy":@"com.qdtiktok.easyvpn",@"feilian":@"com.volcengine.corplink",@"hotspot":@"co.hotspot.vpn.security",@"gofast":@"com.bestapp.gofast.vpn",@"jump":@"com.zenith.jump"}[provider];}
static NSString *const Root=@"/var/mobile/Library/Caches/ayao.vpn-v2-test";
static void Save(NSString *suffix,NSDictionary *value) {
    NSData *data=[NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingSortedKeys error:nil];
    [data writeToFile:[Root stringByAppendingString:suffix] atomically:YES];
}
static NSDictionary *State(void) {
    NSMutableArray *profiles=[NSMutableArray array];
    id store=[NSClassFromString(@"VPNConnectionStore") sharedInstance];
    for(NSUInteger grade=0;grade<4;grade++)for(id key in [store vpnServicesForCurrentSetWithGrade:grade]) {
        id connection=[store connectionWithServiceID:key withGrade:grade];
        NSString *provider=@"external";
        for(NSString *p in Providers())if([[connection bundleID] isEqual:BundleFor(p)])provider=p;
        [profiles addObject:@{@"provider":provider,@"status":@([connection status]),@"connected":@([connection connected]),@"active":@([connection notDisconnectedOrDisconnecting])}];
    }
    id lock=[NSClassFromString(@"SBLockScreenManager") sharedInstance];
    return @{@"version":@"1.3.1~localopen1",@"ready":@(Controller.ready),@"busy":@(Controller.busy),
        @"active":Controller.activeProvider?:@"unknown",@"preferred":Controller.preferredProvider?:@"unknown",
        @"message":Controller.message?:@"",@"failed":@(Controller.failed),@"pid":@(getpid()),
        @"locked":@([lock isUILocked]),@"profiles":profiles,@"request":RequestID?:@""};
}
static void HandleCommand(void) {
    if(Stopped)return;
    NSDictionary *request=[NSDictionary dictionaryWithContentsOfFile:[Root stringByAppendingString:@".request.plist"]];
    NSString *kind=request[@"action"],*identifier=request[@"id"];
    if(![identifier isKindOfClass:NSString.class] || [identifier isEqual:RequestID])return;
    RequestID=identifier;
    [Controller reload];
    if([kind isEqual:@"state"]){Save(@".state.json",State());return;}
    if([kind isEqual:@"select"] && [Providers() containsObject:request[@"provider"]] && !Controller.busy) {
        SEL sel=NSSelectorFromString(@"select:");
        ((void(*)(id,SEL,id))[View methodForSelector:sel])(View,sel,request[@"provider"]);
    } else if([kind isEqual:@"toggle"] && !Controller.busy)[View buttonTapped:nil forEvent:nil];
    else if([kind isEqual:@"network"]) {
        NSURLSessionConfiguration *config=NSURLSessionConfiguration.ephemeralSessionConfiguration;
        config.timeoutIntervalForRequest=12;config.timeoutIntervalForResource=15;
        NSURLSession *session=[NSURLSession sessionWithConfiguration:config];
        [[session dataTaskWithURL:[NSURL URLWithString:@"https://www.apple.com/library/test/success.html"] completionHandler:^(NSData *data,NSURLResponse *response,NSError *error) {
            NSString *body=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            Save(@".network.json",@{@"request":identifier,@"status":@(((NSHTTPURLResponse *)response).statusCode),@"success":@(!error && ((NSHTTPURLResponse *)response).statusCode==200 && [body containsString:@"Success"]),@"error":@(error.code)});
            [session finishTasksAndInvalidate];
        }] resume];
    } else if([kind isEqual:@"stop"]){Stopped=YES;if(Token!=NOTIFY_TOKEN_INVALID)notify_cancel(Token);Token=NOTIFY_TOKEN_INVALID;}
    Save(@".state.json",State());
}
__attribute__((constructor)) static void Initialize(void) {
    if(![NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.springboard"])return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,8*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        NSBundle *bundle;
        // Resolve dynamically from this harness image, never compile device IDs.
        Dl_info info={0};if(!dladdr((void *)Initialize,&info)||!info.dli_fname)return;
        NSString *root=@(info.dli_fname);for(unsigned i=0;i<4;i++)root=root.stringByDeletingLastPathComponent;
        bundle=[NSBundle bundleWithPath:[root stringByAppendingPathComponent:@"Library/ControlCenter/Bundles/FeilianControlCenter.bundle"]];
        if(![bundle load]){Save(@".ready.json",@{@"error":@"bundle-load"});return;}
        Module=[bundle.principalClass new];View=[Module contentViewController];Controller=View.vpn;
        if(!VPNTestObjectMatches(Controller,@"AYAVPNController",bundle.executablePath)){Save(@".ready.json",@{@"error":@"wrong-image"});return;}
        [View loadViewIfNeeded];OriginalPreference=Controller.preferredProvider;
        __weak AYAVPNController *weakController=Controller;
        Controller.stateChanged=^{if(weakController)Save(@".state.json",State());};
        int result=notify_register_dispatch("ayao.vpn.v2.acceptance-command",&Token,dispatch_get_main_queue(),^(int token){(void)token;HandleCommand();});
        Save(@".ready.json",@{@"version":[bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]?:@"",@"pid":@(getpid()),@"notify":@(result),@"originalPreference":OriginalPreference?:@""});
        Save(@".state.json",State());
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1200*NSEC_PER_SEC),dispatch_get_main_queue(),^{Stopped=YES;if(Token!=NOTIFY_TOKEN_INVALID)notify_cancel(Token);Token=NOTIFY_TOKEN_INVALID;});
    });
}
