// Bounded SpringBoard diagnostic of the installed module, not shipped in the package.
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import "../VPNController.h"
#import "../VPNModuleViewController.h"
#import "../Shared/VPNIPC.h"
#import <notify.h>

@interface NSObject (Candidate2Host)
- (UIViewController *)contentViewController;
@end
static id Module;
static AYAVPNController *Controller;
static VPNModuleViewController *View;
static dispatch_source_t Timer;
static NSUInteger Index;
static NSInteger Phase;
static BOOL BusySeen;
static NSDate *Deadline;
static void Log(NSString *text) {
    NSString *path=@"/var/mobile/Library/Caches/ayao.vpn-candidate2-host.log";
    NSFileHandle *file=[NSFileHandle fileHandleForWritingAtPath:path];
    NSData *data=[[text stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    if(!file){[data writeToFile:path atomically:YES];return;}
    [file seekToEndOfFile];[file writeData:data];[file closeFile];
}
static void Stop(void){if(Timer){dispatch_source_cancel(Timer);Timer=nil;}}
static void Next(void){Index++;Phase=0;Deadline=[NSDate dateWithTimeIntervalSinceNow:100];}
static void Tick(void) {
    if(Index>=VPNProviders().count){
        if(![Controller.activeProvider isEqual:@"none"]){Log(@"FINAL_ACTIVE_UNEXPECTED=1");Stop();return;}
        if(![Controller.preferredProvider isEqual:@"easy"]){[Controller applySelection:[Controller selectionIntent:@"easy"]];return;}
        Log(@"PREFERRED_EASY_RESTORED=1\nHOST_SEQUENCE_DONE=1");Stop();return;
    }
    NSString *provider=VPNProviders()[Index];
    if(!Controller.ready)return;
    if(Controller.busy){BusySeen=YES;return;}
    if(Deadline.timeIntervalSinceNow<=0){Log([NSString stringWithFormat:@"provider=%@ timeout=1 active=%@",provider,Controller.activeProvider]);Stop();return;}
    if(Phase==0){
        if(![Controller.activeProvider isEqual:@"none"]){Log(@"REFUSED_ACTIVE=1");Stop();return;}
        NSDictionary *intent=[Controller selectionIntent:provider];
        if(!intent){Log([NSString stringWithFormat:@"provider=%@ unavailable=1",provider]);Next();return;}
        [Controller applySelection:intent];Phase=1;return;
    }
    if(Phase==1 && [Controller.preferredProvider isEqual:provider]){
        Phase=2;BusySeen=NO;Deadline=[NSDate dateWithTimeIntervalSinceNow:70];[Controller toggle];return;
    }
    if(Phase==2 && BusySeen){
        int token=NOTIFY_TOKEN_INVALID;uint64_t stage=0;
        NSString *name=[NSString stringWithFormat:@"ayao.vpn.%@.diagnostic-stage.v1",provider];
        if(notify_register_check(name.UTF8String,&token)==NOTIFY_STATUS_OK){notify_get_state(token,&stage);notify_cancel(token);}
        Log([NSString stringWithFormat:@"provider=%@ ipc_stage=%llu",provider,stage]);
        name=[NSString stringWithFormat:@"ayao.vpn.%@.server.diagnostic-stage.v1",provider];stage=0;
        if(notify_register_check(name.UTF8String,&token)==NOTIFY_STATUS_OK){notify_get_state(token,&stage);notify_cancel(token);}
        Log([NSString stringWithFormat:@"provider=%@ ipc_server_stage=%llu",provider,stage]);
        for(NSString *suffix in @[@"signature",@"uuid",@"auth"]){
            name=[NSString stringWithFormat:@"ayao.vpn.%@.%@.diagnostic-stage.v1",provider,suffix];stage=0;
            if(notify_register_check(name.UTF8String,&token)==NOTIFY_STATUS_OK){notify_get_state(token,&stage);notify_cancel(token);}
            Log([NSString stringWithFormat:@"provider=%@ %@_stage=%llu",provider,suffix,stage]);
        }
        Log([NSString stringWithFormat:@"provider=%@ connected=%d active=%@ message=%@",provider,Controller.connected,Controller.activeProvider,Controller.message]);
        if(!Controller.connected){
            if([Controller.activeProvider isEqual:@"none"]){Next();return;}
            Phase=4;BusySeen=NO;[Controller toggle];return;
        }
        Phase=3;
        NSURLSessionConfiguration *config=NSURLSessionConfiguration.ephemeralSessionConfiguration;
        config.timeoutIntervalForRequest=10;config.timeoutIntervalForResource=15;
        NSURLSession *session=[NSURLSession sessionWithConfiguration:config];
        [[session dataTaskWithURL:[NSURL URLWithString:@"https://www.apple.com/library/test/success.html"]
            completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
                dispatch_async(dispatch_get_main_queue(),^{
                    NSString *text=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    Log([NSString stringWithFormat:@"provider=%@ https=%ld success=%d error=%ld",provider,
                        (long)((NSHTTPURLResponse *)response).statusCode,[text containsString:@"Success"],(long)error.code]);
                    [session finishTasksAndInvalidate];Phase=4;BusySeen=NO;Deadline=[NSDate dateWithTimeIntervalSinceNow:70];[Controller toggle];
                });
            }] resume];return;
    }
    if(Phase==4 && (BusySeen || [Controller.activeProvider isEqual:@"none"] || Controller.failed)){
        Log([NSString stringWithFormat:@"provider=%@ disconnected=%d active=%@ message=%@",provider,
            [Controller.activeProvider isEqual:@"none"],Controller.activeProvider,Controller.message]);
        if(![Controller.activeProvider isEqual:@"none"]){Stop();return;}
        Next();
    }
}
__attribute__((constructor)) static void Initialize(void) {
    if(![NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.springboard"])return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,8*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        Dl_info info={0};if(!dladdr((void *)Initialize,&info)||!info.dli_fname)return;
        NSString *root=@(info.dli_fname);for(NSUInteger n=0;n<4;n++)root=root.stringByDeletingLastPathComponent;
        NSBundle *bundle=[NSBundle bundleWithPath:[root stringByAppendingPathComponent:@"Library/ControlCenter/Bundles/FeilianControlCenter.bundle"]];
        if(![bundle load]){Log(@"HOST_BUNDLE_LOAD_FAILED=1");return;}
        Module=[bundle.principalClass new];View=(id)[Module contentViewController];
        [View loadViewIfNeeded];Controller=View.vpn;
        Log([NSString stringWithFormat:@"HOST_VIEW_LOADED=%d providers=%lu",View.isViewLoaded,(unsigned long)VPNProviders().count]);
        Deadline=[NSDate dateWithTimeIntervalSinceNow:70];
        Timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
        dispatch_source_set_timer(Timer,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),NSEC_PER_SEC,NSEC_PER_MSEC*100);
        dispatch_source_set_event_handler(Timer,^{[Controller reload];Tick();});dispatch_resume(Timer);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,360*NSEC_PER_SEC),dispatch_get_main_queue(),^{Log(@"HOST_DIAGNOSTIC_ENDED=1");Stop();});
    });
}
