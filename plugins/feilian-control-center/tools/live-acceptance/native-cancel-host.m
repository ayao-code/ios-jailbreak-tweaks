// Real installed IPC native-start cancellation, no method replacement or touch.
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import "../../Shared/VPNIPC.h"
#import "../../VPNPrivate.h"
#import "RuntimeGuard.h"
@interface NSObject (AYANativeCancelLaunch)
+ (id)sharedService;
- (void)openApplication:(NSString *)identifier options:(NSDictionary *)options withResult:(void (^)(NSError *))completion;
@end
static VPNIPCClient *Client;
static dispatch_source_t Timer;
static BOOL Dispatched, Canceled, Finished;
static CFAbsoluteTime Started, CanceledAt;
static NSInteger ReplyCode;
static unsigned InitialReads;
static void Log(NSString *line) {
 NSString *path=@"/var/mobile/Library/Caches/ayao.vpn-native-cancel.log";
 NSFileHandle *file=[NSFileHandle fileHandleForWritingAtPath:path];
 NSData *data=[[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
 if(!file){[data writeToFile:path atomically:YES];return;}
 [file seekToEndOfFile];[file writeData:data];[file closeFile];
}
static void Stop(void) {
 if(Timer){dispatch_source_cancel(Timer);Timer=nil;}
 [Client close];Client=nil;
}
static void Tick(void) {
 if(CFAbsoluteTimeGetCurrent()-Started>30){Log(@"NATIVE_CANCEL_TIMEOUT=1");Stop();return;}
 id store=[NSClassFromString(@"VPNConnectionStore") sharedInstance];
 NSUInteger active=0,other=0,status=0;BOOL found=NO;
 for(NSUInteger grade=0;grade<4;grade++)for(id key in [store vpnServicesForCurrentSetWithGrade:grade]) {
  id connection=[store connectionWithServiceID:key withGrade:grade];
  if([[connection bundleID] isEqual:@"com.qdtiktok.easyvpn"]) {found=YES;status=[connection status];}
  if([connection notDisconnectedOrDisconnecting]) {active++;if(![[connection bundleID] isEqual:@"com.qdtiktok.easyvpn"])other++;}
 }
 if(!found && !Dispatched && CFAbsoluteTimeGetCurrent()-Started<5)return;
 if(other || !found || (!Dispatched && active)){Log(@"NATIVE_CANCEL_PROFILE_CHANGED=1");Stop();return;}
 if(!Dispatched)InitialReads++;
 if(Dispatched && !Canceled && !Finished && status==2) {
  Canceled=YES;CanceledAt=CFAbsoluteTimeGetCurrent();[Client close];
  Log(@"CANCEL_WHILE_SYSTEM_CONNECTING=1");
 }
 if(Finished && !Canceled){Log(@"NATIVE_CANCEL_WINDOW_NOT_OBSERVED=1");Stop();return;}
 if(Canceled && Finished && !active && CFAbsoluteTimeGetCurrent()-CanceledAt>1) {
  Log([NSString stringWithFormat:@"NATIVE_CANCEL_DONE=1 connected_targets=0 reply=%ld elapsed=%.3f",(long)ReplyCode,CFAbsoluteTimeGetCurrent()-CanceledAt]);Stop();
 }
}
__attribute__((constructor)) static void Initialize(void) {
 if(![NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.springboard"])return;
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC),dispatch_get_main_queue(),^{
  Dl_info info={0};if(!dladdr((void *)Initialize,&info)||!info.dli_fname)return;
  NSString *root=@(info.dli_fname);for(unsigned i=0;i<4;i++)root=root.stringByDeletingLastPathComponent;
  NSBundle *bundle=[NSBundle bundleWithPath:[root stringByAppendingPathComponent:@"Library/ControlCenter/Bundles/FeilianControlCenter.bundle"]];
  if(![bundle load]){Log(@"NATIVE_CANCEL_BUNDLE_FAILED=1");return;}
  if(![[NSBundle bundleWithPath:@"/System/Library/PreferenceBundles/VPNPreferences.bundle"] load]) {
   Log(@"NATIVE_CANCEL_STORE_FAILED=1");return;
  }
  Class cls=NSClassFromString(@"VPNIPCClient");Client=[[cls alloc] initWithProvider:@"easy"];
  if(!VPNTestObjectMatches(Client,@"VPNIPCClient",bundle.executablePath) ||
     !VPNTestSignature(Client,@selector(open),2,@encode(BOOL)) ||
     !VPNTestSignature(Client,@selector(probe),2,@encode(BOOL)) ||
     !VPNTestSignature(Client,@selector(close),2,"v") ||
     !VPNTestSignature(Client,@selector(requestConnect:generation:),4,@encode(NSInteger))) {Log(@"NATIVE_CANCEL_CONTRACT_FAILED=1");Stop();return;}
  dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices",RTLD_NOW);
  NSString *const *key=(NSString *const *)dlsym(RTLD_DEFAULT,"FBSOpenApplicationOptionKeyActivateSuspended");
  id service=[NSClassFromString(@"FBSSystemService") sharedService];
  if(!key || !*key || !VPNTestSignature(service,@selector(openApplication:options:withResult:),5,"v")){Log(@"NATIVE_CANCEL_LAUNCH_CONTRACT_FAILED=1");Stop();return;}
  Log(@"NATIVE_CANCEL_STARTED=1");Started=CFAbsoluteTimeGetCurrent();
  Timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
  dispatch_source_set_timer(Timer,dispatch_time(DISPATCH_TIME_NOW,50*NSEC_PER_MSEC),50*NSEC_PER_MSEC,5*NSEC_PER_MSEC);
  dispatch_source_set_event_handler(Timer,^{@try {Tick();} @catch(NSException *e){(void)e;Log(@"NATIVE_CANCEL_RUNTIME_FAILED=1");Stop();}});dispatch_resume(Timer);
  [service openApplication:@"com.qdtiktok.easyvpn" options:@{*key:@YES} withResult:^(NSError *error){
   if(error){Log(@"NATIVE_CANCEL_LAUNCH_FAILED=1");Stop();return;}
   VPNIPCClient *client=Client;
   dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
    [NSThread sleepForTimeInterval:2];
    BOOL ready=[client open] && [client probe];
    if(!ready){dispatch_async(dispatch_get_main_queue(),^{Log(@"NATIVE_CANCEL_ACQUIRE_FAILED=1");Stop();});return;}
    __block BOOL running=NO;
    dispatch_sync(dispatch_get_main_queue(),^{running=Timer!=nil && InitialReads>=2;if(running)Dispatched=YES;});
    if(!running){[client close];return;}
    NSInteger reply=[client requestConnect:YES generation:(uint64_t)(NSDate.date.timeIntervalSince1970*1000000)];
    dispatch_async(dispatch_get_main_queue(),^{ReplyCode=reply;Finished=YES;});
   });
  }];
 });
}
