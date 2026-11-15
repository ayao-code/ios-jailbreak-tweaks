// Finite in-host acceptance of direct selections. No touch injection or App hooks.
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import "../VPNController.h"
#import "../VPNModuleViewController.h"
#import "../Shared/VPNIPC.h"
@interface NSObject (SilentSwitchHost)
- (id)contentViewController;
@end
static id Module;
static VPNModuleViewController *View;
static AYAVPNController *Controller;
static dispatch_source_t Timer;
static NSUInteger Step;
static NSDate *Deadline;
static BOOL Issued;
static BOOL BusySeen;
static NSDate *IssuedAt;
static NSArray *Selections;
#ifdef VPN_TEST_SOFT_STOP
static void (*OriginalStop)(id,SEL,NSString *,uint64_t);
static BOOL InjectedStopTimeout;
#endif
static void Log(NSString *text) {
    NSString *path=@"/var/mobile/Library/Caches/ayao.vpn-silent-switch.log";
    NSFileHandle *file=[NSFileHandle fileHandleForWritingAtPath:path];
    NSData *bytes=[[text stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    if(!file){[bytes writeToFile:path atomically:YES];return;}
    [file seekToEndOfFile];[file writeData:bytes];[file closeFile];
}
static void Stop(void){if(Timer){dispatch_source_cancel(Timer);Timer=nil;}}
#ifdef VPN_TEST_SOFT_STOP
static void TestStop(id object,SEL selector,NSString *provider,uint64_t generation) {
    if(!InjectedStopTimeout && [provider isEqual:@"feilian"] &&
        [[object valueForKey:@"phase"] isEqual:@"switch-disconnect"]) {
        InjectedStopTimeout=YES;Log(@"TEST_SOURCE_STOP_TIMEOUT_INJECTED=1");return;
    }
    OriginalStop(object,selector,provider,generation);
}
#endif
static void Tick(void) {
    if(Deadline.timeIntervalSinceNow<=0){Log(@"SWITCH_TIMEOUT=1");Stop();return;}
    if(!Controller.ready)return;
    if(Controller.busy){BusySeen=YES;return;}
    if(Step>=Selections.count) {
        if([Controller.activeProvider isEqual:@"none"]){Log(@"SWITCH_SEQUENCE_DONE=1");Stop();}
        else if(!Issued){Issued=YES;[Controller toggle];}
        return;
    }
    NSString *provider=Selections[Step];
    if(!Issued) {
        NSDictionary *intent=[Controller selectionIntent:provider];
        if(!intent){Log(@"SELECTION_UNAVAILABLE=1");Stop();return;}
        Issued=YES;BusySeen=NO;IssuedAt=NSDate.date;
        // Exercise the exact menu action, not a separate selection implementation.
        SEL select=NSSelectorFromString(@"select:");
        ((void(*)(id,SEL,id))[View methodForSelector:select])(View,select,provider);
        if([Controller.activeProvider isEqual:@"none"]) {
            // No active connection: selection intentionally only changes default.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{
                if([Controller.preferredProvider isEqual:provider] && !Controller.busy)[Controller toggle];
            });
        }
        Deadline=[NSDate dateWithTimeIntervalSinceNow:140];return;
    }
    if(!BusySeen && IssuedAt.timeIntervalSinceNow>-3)return;
    if(!Controller.connected && !Controller.failed)return;
    Log([NSString stringWithFormat:@"step=%lu provider=%@ preferred=%@ active=%@ connected=%d failed=%d message=%@",(unsigned long)Step,provider,
        Controller.preferredProvider,Controller.activeProvider,Controller.connected,Controller.failed,Controller.message]);
    if(!Controller.connected || ![Controller.activeProvider isEqual:provider]) {
        if(Controller.connected) {
            // Failure must not strand the test with A connected; restore the
            // source selection and continue testing its explicit stop path.
            [Controller applySelection:[Controller selectionIntent:Controller.activeProvider]];
        }
        Step++;Issued=NO;return;
    }
    Step++;Issued=NO;
}
__attribute__((constructor)) static void Initialize(void) {
    if(![NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.springboard"])return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,8*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        Dl_info info={0};if(!dladdr((void *)Initialize,&info)||!info.dli_fname)return;
        NSString *root=@(info.dli_fname);for(unsigned i=0;i<4;i++)root=root.stringByDeletingLastPathComponent;
        NSBundle *bundle=[NSBundle bundleWithPath:[root stringByAppendingPathComponent:@"Library/ControlCenter/Bundles/FeilianControlCenter.bundle"]];
        if(![bundle load]){Log(@"BUNDLE_LOAD_FAILED=1");return;}
        Module=[bundle.principalClass new];View=(id)[Module contentViewController];[View loadViewIfNeeded];Controller=View.vpn;
        Log(@"SWITCH_HOST_LOADED=1");
#ifdef VPN_TEST_SOFT_STOP
        Method method=class_getInstanceMethod(Controller.class,NSSelectorFromString(@"nativeDisconnect:generation:"));
        if(method)OriginalStop=(void *)method_setImplementation(method,(IMP)TestStop);
#endif
#ifdef VPN_TEST_SOFT_STOP
        Selections=@[@"easy",@"feilian",@"easy",@"hotspot",@"easy"];
#else
        Selections=@[@"easy",@"feilian",@"easy",@"hotspot",@"easy",@"jump",@"easy",@"gofast",@"easy"];
#endif
        Deadline=[NSDate dateWithTimeIntervalSinceNow:140];
        Timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
        dispatch_source_set_timer(Timer,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),NSEC_PER_SEC,NSEC_PER_MSEC*100);
        dispatch_source_set_event_handler(Timer,^{[Controller reload];Tick();});dispatch_resume(Timer);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,900*NSEC_PER_SEC),dispatch_get_main_queue(),^{Stop();});
    });
}
