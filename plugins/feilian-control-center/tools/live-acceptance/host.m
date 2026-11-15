// Finite real-device host acceptance. Does not replace business implementations,
// dispatch HID input, or inject into any application except SpringBoard.
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import "../../VPNModuleViewController.h"
#import "../../Shared/VPNIPC.h"
#import "../../VPNPrivate.h"
@interface NSObject (VPNLiveAcceptance)
- (id)contentViewController;
- (CGFloat)preferredExpandedContentHeight;
@end
static id Module;
static VPNModuleViewController *View;
static AYAVPNController *Controller;
static dispatch_source_t Timer;
static NSArray *Providers;
static NSUInteger Index, Stage, SwitchIndex;
static BOOL NetworkPending, Switching;
static NSDate *Deadline, *Issued;
static NSString *OriginalPreference;
static NSArray *SwitchTargets;
static NSURLSession *NetworkSession;
static BOOL ProgressChecked;
static NSArray *TestProviders(void) {return @[@"easy",@"feilian",@"hotspot",@"gofast",@"jump"];}
static NSString *TestBundle(NSString *provider) {
 return @{@"easy":@"com.qdtiktok.easyvpn",@"feilian":@"com.volcengine.corplink",@"hotspot":@"co.hotspot.vpn.security",
  @"gofast":@"com.bestapp.gofast.vpn",@"jump":@"com.zenith.jump"}[provider];
}
static void Log(NSString *line) {
    NSString *path=@"/var/mobile/Library/Caches/ayao.vpn-live-acceptance.log";
    NSFileHandle *file=[NSFileHandle fileHandleForWritingAtPath:path];
    NSData *bytes=[[NSString stringWithFormat:@"%.3f %@\n",NSDate.date.timeIntervalSince1970,line] dataUsingEncoding:NSUTF8StringEncoding];
    if(!file){[bytes writeToFile:path atomically:YES];return;}
    [file seekToEndOfFile];[file writeData:bytes];[file closeFile];
}
static void Stop(void) {
    if(Timer){dispatch_source_cancel(Timer);Timer=nil;}
    [NetworkSession invalidateAndCancel];NetworkSession=nil;
}
static void Readback(NSString *label) {
    id store=[NSClassFromString(@"VPNConnectionStore") sharedInstance];
    for(NSUInteger grade=0;grade<4;grade++) for(id sid in [store vpnServicesForCurrentSetWithGrade:grade]) {
        id connection=[store connectionWithServiceID:sid withGrade:grade];
        NSString *provider=@"external";
        for(NSString *p in TestProviders()) if([[connection bundleID] isEqual:TestBundle(p)])provider=p;
        Log([NSString stringWithFormat:@"STATE label=%@ provider=%@ status=%lu connected=%d active=%d",label,provider,
            (unsigned long)[connection status],[connection connected],[connection notDisconnectedOrDisconnecting]]);
    }
}
static void IssueTap(void) {
    [View buttonTapped:nil forEvent:nil];
    ProgressChecked=NO;
    Issued=NSDate.date;Deadline=[NSDate dateWithTimeIntervalSinceNow:140];
}
static void Select(NSString *provider) {
    SEL selector=NSSelectorFromString(@"select:");
    ((void(*)(id,SEL,id))[View methodForSelector:selector])(View,selector,provider);
    ProgressChecked=NO;
    Issued=NSDate.date;Deadline=[NSDate dateWithTimeIntervalSinceNow:140];
}
static void Network(NSString *provider,NSString *kind) {
    NetworkPending=YES;
    NSURLSessionConfiguration *config=NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.timeoutIntervalForRequest=10;config.timeoutIntervalForResource=15;
    NetworkSession=[NSURLSession sessionWithConfiguration:config];
    [[NetworkSession dataTaskWithURL:[NSURL URLWithString:@"https://www.apple.com/library/test/success.html"]
        completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
            dispatch_async(dispatch_get_main_queue(),^{
                NSString *body=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                Log([NSString stringWithFormat:@"NET kind=%@ provider=%@ https=%ld success=%d error=%ld",kind,provider,
                    (long)((NSHTTPURLResponse *)response).statusCode,[body containsString:@"Success"],(long)error.code]);
                [NetworkSession finishTasksAndInvalidate];NetworkSession=nil;NetworkPending=NO;
                if(error || ((NSHTTPURLResponse *)response).statusCode!=200 || ![body containsString:@"Success"]) {
                    Log(@"NETWORK_FAILED=1");Stop();return;
                }
                if(Switching){SwitchIndex++;Stage=0;}
                else {Stage=4;IssueTap();}
            });
        }] resume];
}
static void Tick(void) {
    if(Deadline.timeIntervalSinceNow<=0){Readback(@"timeout");Log(@"RUN_TIMEOUT=1");Stop();return;}
    if(Controller.busy && !ProgressChecked) {
        [View.view setNeedsLayout];[View.view layoutIfNeeded];
        UIView *button=View.buttonView;
        for(UIView *child in button.subviews)if([child isKindOfClass:UIActivityIndicatorView.class]) {
            CGPoint expected=CGPointMake(CGRectGetMidX(button.bounds),CGRectGetMidY(button.bounds));
            Log([NSString stringWithFormat:@"PROGRESS centered=%d delta_x=%.3f delta_y=%.3f animating=%d width=%.1f height=%.1f",
                fabs(child.center.x-expected.x)<0.5 && fabs(child.center.y-expected.y)<0.5,
                child.center.x-expected.x,child.center.y-expected.y,[(UIActivityIndicatorView *)child isAnimating],
                CGRectGetWidth(button.bounds),CGRectGetHeight(button.bounds)]);
            ProgressChecked=YES;
        }
    }
    if(!Controller.ready || Controller.busy || NetworkPending)return;
    if(Switching) {
        if(SwitchIndex>=SwitchTargets.count) {
            if(Stage==0 && ![Controller.activeProvider isEqual:@"none"]){Stage=5;IssueTap();return;}
            if(![Controller.activeProvider isEqual:@"none"] && Stage==5 && Issued.timeIntervalSinceNow>-2)return;
            if(![Controller.activeProvider isEqual:@"none"]){Readback(@"final-stop-failed");Log(@"RUN_FINAL_STOP_FAILED=1");Stop();return;}
            if(![Controller.preferredProvider isEqual:OriginalPreference]){Select(OriginalPreference);return;}
            Readback(@"final");Log(@"PREFERENCE_RESTORED=1\nLIVE_ACCEPTANCE_DONE=1");Stop();return;
        }
        NSString *provider=SwitchTargets[SwitchIndex];
        if(Stage==0) {
            BOOL none=[Controller.activeProvider isEqual:@"none"];
            Select(provider);Stage=none?1:2;return;
        }
        if(Stage==1 && [Controller.preferredProvider isEqual:provider]){Stage=2;IssueTap();return;}
        if(Stage==2 && Issued.timeIntervalSinceNow<-2) {
            if(!Controller.connected && !Controller.failed)return;
            Log([NSString stringWithFormat:@"CASE kind=switch provider=%@ preferred=%@ active=%@ connected=%d failed=%d message=%@",
                provider,Controller.preferredProvider,Controller.activeProvider,Controller.connected,Controller.failed,Controller.message]);
            Readback(@"switch");
            if(!Controller.connected || ![Controller.activeProvider isEqual:provider]) {
                Log(@"SWITCH_FAILED=1");
                if(![Controller.activeProvider isEqual:@"none"]){Stop();return;}
                SwitchIndex++;Stage=0;return;
            }
            Stage=3;Network(provider,@"switch");return;
        }
        return;
    }
    if(Index>=Providers.count){Switching=YES;Stage=0;SwitchIndex=0;Deadline=[NSDate dateWithTimeIntervalSinceNow:90];return;}
    NSString *provider=Providers[Index];
    if(Stage==0){
        if(![Controller.activeProvider isEqual:@"none"]){Readback(@"initial-active");Log(@"REFUSED_OTHER_INITIAL_ACTIVE=1");Stop();return;}
        Select(provider);Stage=1;return;
    }
    if(Stage==1 && [Controller.preferredProvider isEqual:provider]){Stage=2;IssueTap();return;}
    if(Stage==2 && Issued.timeIntervalSinceNow<-2) {
        if(!Controller.connected && !Controller.failed)return;
        Log([NSString stringWithFormat:@"CASE kind=connect provider=%@ active=%@ connected=%d failed=%d message=%@",provider,
            Controller.activeProvider,Controller.connected,Controller.failed,Controller.message]);
        Readback(@"connect");
        if(Controller.connected && [Controller.activeProvider isEqual:provider]){Stage=3;Network(provider,@"connect");return;}
        if(![Controller.activeProvider isEqual:@"none"]){Stage=4;IssueTap();return;}
        Index++;Stage=0;return;
    }
    if(Stage==4 && Issued.timeIntervalSinceNow<-2) {
        if(![Controller.activeProvider isEqual:@"none"] && !Controller.failed)return;
        Log([NSString stringWithFormat:@"CASE kind=disconnect provider=%@ active=%@ failed=%d message=%@",provider,
            Controller.activeProvider,Controller.failed,Controller.message]);
        Readback(@"disconnect");
        if(![Controller.activeProvider isEqual:@"none"]){Log(@"DISCONNECT_FAILED=1");Stop();return;}
        Index++;Stage=0;
    }
}
__attribute__((constructor)) static void Initialize(void) {
    if(![NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.springboard"])return;
    Log(@"DIAGNOSTIC_CONSTRUCTOR=1");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        Dl_info info={0};if(!dladdr((void *)Initialize,&info)||!info.dli_fname)return;
        NSString *root=@(info.dli_fname);for(unsigned i=0;i<4;i++)root=root.stringByDeletingLastPathComponent;
        NSBundle *bundle=[NSBundle bundleWithPath:[root stringByAppendingPathComponent:@"Library/ControlCenter/Bundles/FeilianControlCenter.bundle"]];
        if(![bundle load]){Log(@"BUNDLE_LOAD_FAILED=1");return;}
        Log(@"BUNDLE_LOADED=1");
        Module=[bundle.principalClass new];View=(id)[Module contentViewController];[View loadViewIfNeeded];Controller=View.vpn;
        OriginalPreference=Controller.preferredProvider;
        Providers=TestProviders();SwitchTargets=@[@"easy",@"feilian",@"hotspot",@"jump",@"gofast",@"easy"];
        View.view.frame=CGRectMake(0,0,65,65);
        [View willTransitionToExpandedContentMode:YES];[View didTransitionToExpandedContentMode:YES];[View.view layoutIfNeeded];
        Log([NSString stringWithFormat:@"HOST_LOADED=1 version=%@ provider_count=%lu expanded_height=%.1f view_loaded=%d",
            [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"],(unsigned long)Providers.count,
            [(id)View preferredExpandedContentHeight],View.isViewLoaded]);
        [View willTransitionToExpandedContentMode:NO];[View didTransitionToExpandedContentMode:NO];
        Deadline=[NSDate dateWithTimeIntervalSinceNow:90];
        Timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
        dispatch_source_set_timer(Timer,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),NSEC_PER_SEC,NSEC_PER_MSEC*100);
        dispatch_source_set_event_handler(Timer,^{[Controller reload];Tick();});dispatch_resume(Timer);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,900*NSEC_PER_SEC),dispatch_get_main_queue(),^{Log(@"RUN_MAX_DEADLINE=1");Stop();});
    });
}
