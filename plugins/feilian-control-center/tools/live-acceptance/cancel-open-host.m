// Regression-only real host: no VPN network commands or business overrides.
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import "../../Shared/VPNIPC.h"
#import "../../VPNController.h"
#import "RuntimeGuard.h"
@interface NSObject (VPNCancelLaunch)
+ (id)sharedService;
- (void)openApplication:(NSString *)identifier options:(NSDictionary *)options withResult:(void (^)(NSError *))result;
- (id)contentViewController;
- (id)vpn;
@end
static id Module;
static void Log(NSString *line) {
 NSString *path=@"/var/mobile/Library/Caches/ayao.vpn-cancel-regression.log";
 NSFileHandle *handle=[NSFileHandle fileHandleForWritingAtPath:path];
 NSData *data=[[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
 if(!handle){[data writeToFile:path atomically:YES];return;}
 [handle seekToEndOfFile];[handle writeData:data];[handle closeFile];
}
__attribute__((constructor)) static void Initialize(void) {
 if(![NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.springboard"])return;
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC),dispatch_get_main_queue(),^{
  Dl_info info={0};if(!dladdr((void *)Initialize,&info)||!info.dli_fname)return;
  NSString *root=@(info.dli_fname);for(unsigned i=0;i<4;i++)root=root.stringByDeletingLastPathComponent;
  NSBundle *bundle=[NSBundle bundleWithPath:[root stringByAppendingPathComponent:@"Library/ControlCenter/Bundles/FeilianControlCenter.bundle"]];
  if(![bundle load]){Log(@"LIBRARY_LOAD_FAILED=1");return;}
  id module=[bundle.principalClass new];
  if(!VPNTestSignature(module,@selector(contentViewController),2,@encode(id))){Log(@"MODULE_CONTRACT_REJECTED=1");return;}
  id view=[module contentViewController];
  if(!VPNTestSignature(view,@selector(vpn),2,@encode(id))){Log(@"VIEW_CONTRACT_REJECTED=1");return;}
  AYAVPNController *controller=[view vpn];
  if(!VPNTestObjectMatches(controller,@"AYAVPNController",bundle.executablePath) ||
     !VPNTestSignature(controller,@selector(ready),2,@encode(BOOL)) ||
     !VPNTestSignature(controller,@selector(reload),2,"v") ||
     !VPNTestSignature(controller,@selector(setStateChanged:),3,"v")) {
      Log(@"CONTROLLER_ORIGIN_REJECTED=1");return;
  }
  Class clientClass=NSClassFromString(@"VPNIPCClient");
  if(!clientClass){Log(@"CLASS_UNAVAILABLE=1");return;}
  Module=module;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC),dispatch_get_main_queue(),^{
   @try {
   if(!controller.ready){Log(@"SNAPSHOT_PRECONDITION_FAILED=1");return;}
   __block unsigned callbacks=0;controller.stateChanged=^{callbacks++;};
   for(unsigned i=0;i<20;i++)[controller reload];
   dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{
    @try {Log([NSString stringWithFormat:@"IDENTICAL_RELOADS=20 state_callbacks=%u",callbacks]);controller.stateChanged=nil;}
    @catch(NSException *exception){(void)exception;Log(@"SNAPSHOT_CALLBACK_EXCEPTION=1");}
   });
   } @catch(NSException *exception){(void)exception;Log(@"SNAPSHOT_TEST_EXCEPTION=1");}
  });
  dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices",RTLD_NOW);
  NSString *const *key=(NSString *const *)dlsym(RTLD_DEFAULT,"FBSOpenApplicationOptionKeyActivateSuspended");
  id service=[NSClassFromString(@"FBSSystemService") sharedService];
  if(!key || !*key || !VPNTestSignature(service,@selector(openApplication:options:withResult:),5,"v")) {
      Log(@"LAUNCH_UNAVAILABLE=1");return;
  }
  [service openApplication:@"com.qdtiktok.easyvpn" options:@{*key:@YES} withResult:^(NSError *error){
   if(error){Log(@"LAUNCH_FAILED=1");return;}
   dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
    unsigned interrupted=0,openingCount=0;
    for(unsigned i=0;i<10;i++) {
     @autoreleasepool {
      VPNIPCClient *client=[[clientClass alloc] initWithProvider:@"easy"];
      if(!VPNTestObjectMatches(client,@"VPNIPCClient",bundle.executablePath) ||
         !VPNTestSignature(client,@selector(open),2,@encode(BOOL)) ||
         !VPNTestSignature(client,@selector(close),2,"v") ||
         !VPNTestSignature(client,@selector(probe),2,@encode(BOOL))) {
          Log(@"CLIENT_ORIGIN_REJECTED=1");return;
      }
      dispatch_group_t group=dispatch_group_create();__block BOOL opened=NO;
      CFAbsoluteTime start=CFAbsoluteTimeGetCurrent();
      dispatch_group_async(group,dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{opened=[client open];});
      int pendingFD=-1;
      @try {
       // Wait for the intended race window, not an arbitrary 50 ms sample.
       // Stop if open already returned; a missed window remains unverified.
       CFAbsoluteTime observeUntil=CFAbsoluteTimeGetCurrent()+1;
       do {
        pendingFD=[[client valueForKey:@"openingFD"] intValue];
        if(pendingFD>=0 || !dispatch_group_wait(group,DISPATCH_TIME_NOW))break;
        [NSThread sleepForTimeInterval:0.001];
       } while(CFAbsoluteTimeGetCurrent()<observeUntil);
      }
      @catch(NSException *exception) {
          (void)exception;[client close];
          dispatch_group_wait(group,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC));
          Log(@"CLIENT_DIAGNOSTIC_CONTRACT_REJECTED=1");return;
      }
      BOOL opening=pendingFD>=0;openingCount+=opening;
      [client close];
      if(dispatch_group_wait(group,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))) {
       Log(@"OPEN_CANCEL_WAIT_FAILED=1");return;
      }
      BOOL probe=[client probe];
      NSTimeInterval elapsed=CFAbsoluteTimeGetCurrent()-start;
      BOOL pass=!opened && !probe && elapsed<3 && opening;
      interrupted+=pass;
      Log([NSString stringWithFormat:@"iteration=%u pending_open=%d opened=%d probe=%d cancel_elapsed=%.3f passed=%d",
         i,opening,opened,probe,elapsed,pass]);
      if(!opening)Log([NSString stringWithFormat:@"iteration=%u CANCEL_WINDOW_NOT_OBSERVED=1",i]);
      [client close];dispatch_sync(dispatch_get_main_queue(),^{});
     }
     [NSThread sleepForTimeInterval:0.2];
    }
    Log([NSString stringWithFormat:@"CANCEL_OPEN_DONE=1 opening_count=%u passed=%u",openingCount,interrupted]);
   });
  }];
 });
}
